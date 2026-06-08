extends Node
class_name PathInput

var drawing := false
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
		if player.attack_path.size() >= 2:
			battle.exit_bullet_time(false)
		else:
			battle.exit_bullet_time(true)
		return
	player.add_path_point(pos)
	if battle.buff_orbs:
		battle.buff_orbs.check_path_segment(last, pos)


func handle_end() -> void:
	var player: BattlePlayer = battle.player
	if player == null or player.state != BattlePlayer.State.BULLET_TIME:
		drawing = false
		return
	drawing = false
	if player.attack_path.size() < 2:
		battle.exit_bullet_time(true)
		return
	battle.exit_bullet_time(false)


func cancel_active() -> void:
	drawing = false
	var player: BattlePlayer = battle.player
	if player and player.state == BattlePlayer.State.BULLET_TIME:
		battle.exit_bullet_time(true)
