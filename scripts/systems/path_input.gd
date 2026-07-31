extends Node
class_name PathInput

const WATER_KI_PER_TILE := 4.0  # 画线每穿越一个水格的额外气消耗（去重后）

var drawing := false
var line_invalid := false  # 本段画线是否触碰阻挡块/锁定块/箭块 → 提交时丢弃（深坑不挡画线）
var battle


func setup(battle_node) -> void:
	battle = battle_node


func handle_start(screen_pos: Vector2) -> void:
	if battle.state != GameState.PLAYING:
		return
	var player: BattlePlayer = battle.player
	if player.state != BattlePlayer.State.IDLE:
		return
	var pos: Vector2 = battle.screen_to_world(screen_pos)
	if not battle.is_in_bounds(pos):
		return
	if pos.distance_to(player.home_position) > player.get_trigger_radius():
		battle.hud.show_message("请在主角周围白圈内开始划线", 1.0)
		return
	if not player.is_ki_full():
		battle.hud.show_message("气力未满，请稍候", 1.0)
		return
	# 画线末释放类奖励（sr=22 / sr=26 / sr=27 / sr=46）：新一次画线开始 → 清掉上次遗留的「气力耗尽」标记
	player.slash_end_ki_drained = false
	line_invalid = false
	player.set_preview_invalid(false)
	drawing = true
	battle.enter_bullet_time()
	player.start_bullet_time()
	if battle.buff_orbs:
		battle.buff_orbs.begin_draw_session(player)
	player.add_path_point(pos)


func handle_move(screen_pos: Vector2) -> void:
	if not drawing:
		return
	var player: BattlePlayer = battle.player
	if player.state != BattlePlayer.State.BULLET_TIME:
		return
	var pos: Vector2 = battle.screen_to_world(screen_pos)
	if not battle.is_in_bounds(pos):
		return
	var last: Vector2 = player.attack_path.back() if not player.attack_path.is_empty() else player.home_position
	var step: float = last.distance_to(pos)
	if step < 2.0:
		return
	if not player.consume_ki_by_distance(step):
		drawing = false
		# 画线已标红（触碰阻挡石/锁定块/箭块）→ 气力耗尽也不能发起攻击，丢弃轨迹
		# （修复：原先这里直接 exit_bullet_time(false) → start_attack，绕过 line_invalid，
		#   导致红线画线在气力恰好耗尽时仍能顺着轨迹攻击）
		# 注：深坑不在此列——画线从深坑上方斩过。
		if line_invalid:
			_discard_invalid_line()
			return
		# 本次画线把气力耗尽 → 标记下次 slash_end 触发"画线末释放"类奖励
		# （仅当攻击真的发起时才标记；丢弃的画线不算一次 slash）
		player.slash_end_ki_drained = true
		if player.attack_path.size() >= 2:
			battle.exit_bullet_time(false)
		else:
			battle.exit_bullet_time(true)
		return
	# 水地块额外扣气：每穿越一格水扣 WATER_KI_PER_TILE（去重）
	var water_count := _count_water_tiles_on_segment(battle.terrain, last, pos)
	if water_count > 0:
		player.ki = maxf(0.0, player.ki - float(water_count) * WATER_KI_PER_TILE)
		if player.ki <= 0.01:
			player.slash_end_ki_drained = true
	# 阻挡石/锁定块/箭块：触碰即整线标红，提交时丢弃（深坑不挡画线，从上方斩过）
	if _segment_hits_blocking(battle.terrain, last, pos):
		line_invalid = true
		player.set_preview_invalid(true)
	player.add_path_point(pos)
	if battle.buff_orbs:
		battle.buff_orbs.check_path_segment(last, pos)


# 段是否触碰"画线阻挡"格：地形 blocking_stone + 放置元素锁定块/箭块（registry.has_line_blocking_at）。
# 深坑不在内——深坑是地面上的洞，画线从上方斩过（pit_block 已 _configure_blocking move-only）。
func _segment_hits_blocking(terrain, a: Vector2, b: Vector2) -> bool:
	if terrain == null or not terrain.has_method("is_blocking_for_line"):
		return false
	var ts: float = float(TerrainBackground.TILE_SIZE)
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return false
	var step_px: float = ts * 0.5
	var samples: int = maxi(1, int(ceil(dist / step_px)))
	var fe = battle.field_elements if battle and "field_elements" in battle else null
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var p: Vector2 = a.lerp(b, t)
		var col: int = int(floor(p.x / ts))
		var row: int = int(floor(p.y / ts))
		if terrain.is_blocking_for_line(col, row):
			return true
		if fe and fe.has_method("has_line_blocking_at") and fe.has_line_blocking_at(col, row):
			return true
	return false


func _count_water_tiles_on_segment(terrain, a: Vector2, b: Vector2) -> int:
	if terrain == null or not terrain.has_method("get_tile_at_world"):
		return 0
	var ts: float = float(TerrainBackground.TILE_SIZE)
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return 0
	# 每 ts/2 像素采样一次，按 (col,row) 去重
	var step_px: float = ts * 0.5
	var samples: int = maxi(1, int(ceil(dist / step_px)))
	var seen_water: Dictionary = {}
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var p: Vector2 = a.lerp(b, t)
		var col: int = int(floor(p.x / ts))
		var row: int = int(floor(p.y / ts))
		var key: int = col * 10000 + row
		if seen_water.has(key):
			continue
		if terrain.get_tile(col, row) == "water":
			seen_water[key] = true
	return seen_water.size()


# 画线已标红（触碰阻挡石/锁定块/箭块）→ 丢弃本次轨迹，不发起攻击（深坑不挡画线）。
# handle_end 正常抬手 与 handle_move 气力耗尽 两条路径共用，避免丢弃逻辑散落两处不同步。
func _discard_invalid_line() -> void:
	line_invalid = false
	var player: BattlePlayer = battle.player
	player.set_preview_invalid(false)
	battle.hud.show_message(LanguageManager.tr_ui("UI_BATTLE_LINE_BLOCKED"), 1.2)
	player.invalidate_path()
	battle.exit_bullet_time(true)


func handle_end() -> void:
	var player: BattlePlayer = battle.player
	if player == null or player.state != BattlePlayer.State.BULLET_TIME:
		drawing = false
		line_invalid = false
		return
	drawing = false
	# 画线触碰阻挡石/锁定块/箭块 → 本次画线失败，丢弃不提交（深坑不挡画线）
	if line_invalid:
		_discard_invalid_line()
		return
	if player.attack_path.size() < 2:
		battle.exit_bullet_time(true)
		return
	player.set_preview_invalid(false)
	battle.exit_bullet_time(false)


func cancel_active() -> void:
	drawing = false
	line_invalid = false
	var player: BattlePlayer = battle.player
	if player:
		player.set_preview_invalid(false)
		if player.state == BattlePlayer.State.BULLET_TIME:
			battle.exit_bullet_time(true)
