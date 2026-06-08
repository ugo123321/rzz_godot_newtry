extends Node
class_name ExperienceManager

var level := 1
var exp := 0
var exp_to_next := 100
var pending_level_ups := 0


func reset() -> void:
	level = 1
	exp = 0
	exp_to_next = _calc_exp_to_next(1)
	pending_level_ups = 0
	EventBus.exp_changed.emit(level, exp, exp_to_next)


func _calc_exp_to_next(current_level: int) -> int:
	var base := float(GameConfig.get_tuning("exp_base_to_level", 100))
	var growth := float(GameConfig.get_tuning("exp_growth", 1.22))
	return int(round(base * pow(growth, current_level - 1)))


func get_kill_reward(monster: Node) -> int:
	var kind_id := str(monster.kind_id)
	var row := GameConfig.get_monster(kind_id)
	return int(row.get("exp_reward", 2))


func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	exp += amount
	while exp >= exp_to_next:
		exp -= exp_to_next
		level += 1
		exp_to_next = _calc_exp_to_next(level)
		pending_level_ups += 1
	EventBus.exp_changed.emit(level, exp, exp_to_next)


func on_monster_killed(monster: Node) -> void:
	add_exp(get_kill_reward(monster))


func try_trigger_upgrade(battle: Node) -> bool:
	if pending_level_ups <= 0:
		return false
	if battle.state != GameState.PLAYING:
		return false
	# 对齐 cankao：仅连击结算中阻塞升级，不因残影/飘字未消散而一直卡住
	if battle.combat.is_resolving():
		return false
	pending_level_ups -= 1
	battle.enter_level_up()
	AudioManager.play_level_up()
	return true


func set_debug_level(target_level: int, player: BattlePlayer) -> void:
	level = clampi(target_level, 1, 30)
	exp = 0
	exp_to_next = _calc_exp_to_next(level)
	pending_level_ups = 0
	EventBus.exp_changed.emit(level, exp, exp_to_next)
