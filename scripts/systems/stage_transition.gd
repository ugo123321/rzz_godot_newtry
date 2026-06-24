extends Node
class_name StageTransition

# 关卡过场编排器：清关瞬间 → 玩家抛物线起跳 + 摄像机竖直滚动 1280px →
# 玩家落地于下一关中央 → 一帧原子 rebase → 释放输入。
# 详见 plan：C:\Users\admin\.claude\plans\clever-bouncing-crane.md

const DEBUG_TRANSITION_SLOW := false
const SLOW_FACTOR := 3.0
const DURATION := 0.8
const SCROLL_DISTANCE := 1280.0

enum Phase { IDLE, KICKOFF, PRESPAWN, SCROLL_JUMP, REBASE, RELEASE }

var _phase: int = Phase.IDLE
var _busy := false


func is_active() -> bool:
	return _busy


func play(battle, next_stage_index: int, on_complete: Callable) -> void:
	if _busy:
		push_warning("StageTransition.play called while already busy; ignoring.")
		return
	if battle == null:
		return
	# 通关早出口：没有下一关时直接走 game-complete 流程，不跑滚轴。
	if next_stage_index >= GameConfig.stages.size():
		_log("no next stage; game complete fallthrough")
		battle._clear_stage_transition_presentation(true)
		battle.state = GameState.COMPLETE
		if battle.level_overlay:
			battle.level_overlay.show_game_complete()
		if battle.hud:
			battle.hud.hide_message()
		return
	# 玩家已死或非 IDLE → 中止（_try_finish_stage_clear 已 gate，但二次保险）
	if battle.state == GameState.FAIL_DEATH or battle.state == GameState.STAGE_FAIL:
		_log("aborting: battle in fail state")
		return
	if battle.player == null or battle.player.state != BattlePlayer.State.IDLE:
		_log("aborting: player not idle")
		return
	_busy = true
	await _run(battle, next_stage_index, on_complete)
	_busy = false


func _run(battle, next_stage_index: int, on_complete: Callable) -> void:
	var duration := _scaled_duration()
	var from_stage: int = battle.stage_index
	# === 1. KICKOFF ===
	_phase = Phase.KICKOFF
	_log("KICKOFF from=%d to=%d" % [from_stage, next_stage_index])
	battle.state = GameState.STAGE_TRANSITION
	battle._transition_damage_lock = true
	battle._clear_stage_transition_presentation(true)
	# 注意：旧关卡的树 / 草地 / 地形 此时**不清**，让它们在滚轴前半段仍然可见。
	# REBASE 才统一替换为下一关的实例。
	if battle.portal_spawner:
		battle.portal_spawner.reset()
	_clear_container(battle.portal_container)
	_clear_container(battle.wood_drops_container)
	EventBus.stage_cleared.emit(from_stage)
	EventBus.stage_transition_started.emit(from_stage, next_stage_index)

	# === 2. PRESPAWN ===
	_phase = Phase.PRESPAWN
	_log("PRESPAWN")
	battle._prespawn_next_stage_world(next_stage_index)

	# === 3. SCROLL_JUMP ===
	_phase = Phase.SCROLL_JUMP
	_log("SCROLL_JUMP duration=%.2f" % duration)
	var camera = battle.camera
	var player = battle.player
	var start_pos: Vector2 = player.global_position
	var canonical_y: float = float(GameConfig.get_tuning("logical_height", 1280)) * 0.58
	var land_pos := Vector2(battle._initial_camera_x, canonical_y - SCROLL_DISTANCE)
	var camera_target_y: float = battle._initial_camera_y - SCROLL_DISTANCE
	var tw: Tween = battle.create_tween()
	tw.set_parallel(true)
	tw.tween_property(camera, "position:y", camera_target_y, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(
		_player_jump_setter.bind(player, start_pos, land_pos),
		0.0, 1.0, duration
	).set_trans(Tween.TRANS_LINEAR)
	# 挤压拉伸：起跳压扁 → 上升拉伸 → 下降复原。整段 duration 内三段串行。
	# 用 Tween 在 parallel 模式下也可以串行：tween_callback / tween_interval 串行子动。
	# 这里用三段 property tween（同属性串行）实现。
	var squash_tw: Tween = battle.create_tween()
	var squash_t1: float = duration * 0.1
	var squash_t2: float = duration * 0.4
	var squash_t3: float = duration * 0.5
	squash_tw.tween_property(player, "scale", Vector2(1.15, 0.85), squash_t1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	squash_tw.tween_property(player, "scale", Vector2(0.9, 1.15), squash_t2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	squash_tw.tween_property(player, "scale", Vector2.ONE, squash_t3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	# 防止 squash_tw 在 rebase 之后还残留覆盖 scale
	if squash_tw and squash_tw.is_valid():
		squash_tw.kill()

	# === 4. REBASE ===
	_phase = Phase.REBASE
	_log("REBASE")
	battle._rebase_after_transition(next_stage_index)

	# === 5. RELEASE ===
	_phase = Phase.RELEASE
	_log("RELEASE")
	battle._transition_damage_lock = false
	# 落地小幅震动 —— 给落地反馈
	if battle.has_method("shake_camera"):
		battle.shake_camera(5.5, 0.18)
	# 怪物在此时才生成（此时世界坐标已回到标准 0..1280，spawner 假设成立）
	if battle.spawner:
		battle.spawner.spawn_stage(next_stage_index, battle)
	# 树已在 PRESPAWN 直接实例化，无需再 begin；只启动传送门
	if battle.portal_spawner:
		battle.portal_spawner.begin()
	EventBus.stage_transition_completed.emit(next_stage_index)
	_phase = Phase.IDLE
	on_complete.call()


func _player_jump_setter(t: float, player, start: Vector2, land: Vector2) -> void:
	if player == null:
		return
	const APEX_HEIGHT := 900.0
	var base_x: float = lerp(start.x, land.x, t)
	var base_y: float = lerp(start.y, land.y, t)
	var arc: float = -APEX_HEIGHT * 4.0 * t * (1.0 - t)
	player.global_position = Vector2(base_x, base_y + arc)


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		if is_instance_valid(child):
			child.queue_free()


func _scaled_duration() -> float:
	if DEBUG_TRANSITION_SLOW:
		return DURATION * SLOW_FACTOR
	return DURATION


func _log(msg: String) -> void:
	if DEBUG_TRANSITION_SLOW:
		print("[StageTransition] ", msg)
