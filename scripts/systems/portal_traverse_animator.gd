extends Node
class_name PortalTraverseAnimator

# 传送门进出动画统一编排器。
# 包装 5 段：
#   ENTER:  HOP_TOWARD(0.18s) → SHRINK_INTO(0.22s) → MIDPOINT_FADE(0.18+0+0.18 黑色 phase_fade)
#   EXIT :  GROW_OUT(0.22s) → HOP_TO_HOME(0.18s)
#   ENTER 的中点（黑色 fade 中段）调 on_midpoint —— 在那里切场 (state / attr_forge.begin / popup show)
#   EXIT  的最后落地后调 on_complete
#
# 被 battle.gd 的 _begin_forge_stage / _on_forge_exit_complete / on_portal_entered /
# _on_reward_wheel_finished 调用。详见 plan：C:\Users\admin\.claude\plans\jiggly-imagining-babbage.md

const DEBUG_TRAVERSE_SLOW := false
const SLOW_FACTOR := 3.0

const HOP_DUR := 0.18
const SHRINK_DUR := 0.22
const GROW_DUR := 0.22
const HOP_APEX := 60.0
const FADE_IN := 0.18
const FADE_HOLD := 0.0
const FADE_OUT := 0.18

# play_exit 落地点相对传送门中心的偏移（落在门正下方原地）。
const EXIT_OFFSET := Vector2.ZERO

var _busy := false
var _active_tweens: Array = []


func is_active() -> bool:
	return _busy


# play_enter：玩家走"小跳跃 → 缩入门 → 黑色 phase_fade（中点切场）"。
# on_midpoint 在 phase_fade 中段调用（玩家此刻已不可见，安全切 state / 启动小游戏 / 弹 popup）。
func play_enter(battle, portal_pos: Vector2, on_midpoint: Callable) -> void:
	if _busy:
		push_warning("PortalTraverseAnimator.play_enter called while busy; ignoring.")
		return
	if battle == null or battle.player == null:
		return
	_busy = true
	await _run_enter(battle, portal_pos, on_midpoint)
	_busy = false


# play_exit：黑色 phase_fade 淡出（玩家在门处 scale=0 alpha=0 →）GROW_OUT → HOP_TO_HOME。
# on_complete 在玩家落地后调用。
func play_exit(battle, portal_pos: Vector2, on_complete: Callable) -> void:
	if _busy:
		push_warning("PortalTraverseAnimator.play_exit called while busy; ignoring.")
		return
	if battle == null or battle.player == null:
		return
	_busy = true
	await _run_exit(battle, portal_pos, on_complete)
	_busy = false


# 取消所有进行中的 tween，把 player 视觉状态强制恢复（用于 player 死亡等异常中断）。
func cancel() -> void:
	for tw in _active_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_active_tweens.clear()
	_busy = false

func _run_enter(battle, portal_pos: Vector2, on_midpoint: Callable) -> void:
	var player = battle.player
	# 标记 portal_traverse 活跃 — 让 player._apply_combat_modulate 不要每帧覆盖 modulate
	if "_portal_traverse_active" in player:
		player._portal_traverse_active = true
	var start_pos: Vector2 = player.global_position
	# === 1. HOP_TOWARD ===
	# 玩家小跳跃靠近 portal（如果已经在 portal 上，就纯做 squash 演出）
	var hop_dur := _scaled(HOP_DUR)
	var hop_tw: Tween = battle.create_tween()
	_active_tweens.append(hop_tw)
	hop_tw.set_parallel(true)
	hop_tw.tween_method(
		_player_hop_setter.bind(player, start_pos, portal_pos),
		0.0, 1.0, hop_dur
	).set_trans(Tween.TRANS_LINEAR)
	# squash 串行
	var squash_tw: Tween = battle.create_tween()
	_active_tweens.append(squash_tw)
	squash_tw.tween_property(player, "scale", Vector2(1.15, 0.85), hop_dur * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	squash_tw.tween_property(player, "scale", Vector2(0.9, 1.15), hop_dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	squash_tw.tween_property(player, "scale", Vector2.ONE, hop_dur * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await hop_tw.finished
	if not is_instance_valid(player):
		return
	player.global_position = portal_pos

	# === 2. SHRINK_INTO ===
	# 玩家被传送门吸入：缩小 + 旋转 + 透明
	var shrink_dur := _scaled(SHRINK_DUR)
	var shrink_tw: Tween = battle.create_tween()
	_active_tweens.append(shrink_tw)
	shrink_tw.set_parallel(true)
	shrink_tw.tween_property(player, "scale", Vector2.ZERO, shrink_dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	shrink_tw.tween_property(player, "rotation", TAU, shrink_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	shrink_tw.tween_property(player, "modulate:a", 0.0, shrink_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	# 粒子爆（紫色 8 颗向外飞）
	if battle.particles and battle.particles.has_method("death_effect"):
		battle.particles.death_effect(portal_pos, Color("#8a5cff"), 0.85)
	await shrink_tw.finished
	if not is_instance_valid(player):
		return

	# === 3. MIDPOINT_FADE ===
	# 黑色 phase_fade（fade_in 0.18 → hold 0 → fade_out 0.18），中段调 on_midpoint。
	# 中点回调通常做：state 切换 / attr_forge.begin / reward_wheel.show_for_stage / 把 portal visible=false
	if battle.level_overlay:
		battle.level_overlay.show_phase_fade("", "", on_midpoint, FADE_IN, FADE_HOLD, FADE_OUT)
		# 等 phase_fade 完整跑完（fade_in + hold + fade_out）
		var total_fade := FADE_IN + FADE_HOLD + FADE_OUT + 0.05
		await battle.get_tree().create_timer(_scaled(total_fade)).timeout
	else:
		# 兜底：直接调中点回调
		if on_midpoint.is_valid():
			on_midpoint.call()


func _run_exit(battle, portal_pos: Vector2, on_complete: Callable) -> void:
	var player = battle.player
	# 标记 portal_traverse 活跃
	if "_portal_traverse_active" in player:
		player._portal_traverse_active = true
	# === 1. 把玩家瞬移到 portal_pos 并准备好 scale=0/alpha=0 状态 ===
	player.global_position = portal_pos
	player.scale = Vector2.ZERO
	player.modulate.a = 0.0
	player.rotation = -TAU
	player.visible = true

	# === 2. GROW_OUT ===
	# 玩家从门里长出：scale 0→1，rot -TAU→0，alpha 0→1
	var grow_dur := _scaled(GROW_DUR)
	var grow_tw: Tween = battle.create_tween()
	_active_tweens.append(grow_tw)
	grow_tw.set_parallel(true)
	grow_tw.tween_property(player, "scale", Vector2.ONE, grow_dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow_tw.tween_property(player, "rotation", 0.0, grow_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	grow_tw.tween_property(player, "modulate:a", 1.0, grow_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	# 粒子爆
	if battle.particles and battle.particles.has_method("death_effect"):
		battle.particles.death_effect(portal_pos, Color("#c8a8ff"), 1.0)
	await grow_tw.finished
	if not is_instance_valid(player):
		if on_complete.is_valid():
			on_complete.call()
		return

	# === 3. HOP_TO_HOME ===
	# 用户选择：落在门正下方原地 → home = portal_pos + EXIT_OFFSET（默认 ZERO）
	# 这里仍做一段小跳跃 + squash，让"落地"有动感（即使距离为 0）
	var home_pos := portal_pos + EXIT_OFFSET
	var hop_dur := _scaled(HOP_DUR)
	var hop_tw: Tween = battle.create_tween()
	_active_tweens.append(hop_tw)
	hop_tw.set_parallel(true)
	hop_tw.tween_method(
		_player_hop_setter.bind(player, portal_pos, home_pos),
		0.0, 1.0, hop_dur
	).set_trans(Tween.TRANS_LINEAR)
	var squash_tw: Tween = battle.create_tween()
	_active_tweens.append(squash_tw)
	squash_tw.tween_property(player, "scale", Vector2(1.15, 0.85), hop_dur * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	squash_tw.tween_property(player, "scale", Vector2(0.9, 1.15), hop_dur * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	squash_tw.tween_property(player, "scale", Vector2.ONE, hop_dur * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await hop_tw.finished
	if not is_instance_valid(player):
		if on_complete.is_valid():
			on_complete.call()
		return
	# 落地微震
	if battle.has_method("shake_camera"):
		battle.shake_camera(3.0, 0.1)
	# 同步 home_position（重要：避免玩家随后被 _nudge_player_out_of_trees 拉回旧 home）
	player.global_position = home_pos
	if "home_position" in player:
		player.home_position = home_pos
	# 清掉 portal_traverse 标记，恢复 _apply_combat_modulate 正常工作
	if "_portal_traverse_active" in player:
		player._portal_traverse_active = false
	_active_tweens.clear()
	if on_complete.is_valid():
		on_complete.call()


# 抛物线小跳跃 setter（APEX = HOP_APEX）
func _player_hop_setter(t: float, player, start: Vector2, land: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var base_x: float = lerp(start.x, land.x, t)
	var base_y: float = lerp(start.y, land.y, t)
	var arc: float = -HOP_APEX * 4.0 * t * (1.0 - t)
	player.global_position = Vector2(base_x, base_y + arc)


func _scaled(d: float) -> float:
	if DEBUG_TRAVERSE_SLOW:
		return d * SLOW_FACTOR
	return d
