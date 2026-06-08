extends Node
class_name StageFailAnimator

var battle
var active := false
var frozen := false
var phase := "idle"
var timer := 0.0
var on_complete: Callable


func _tuning(key: String, default_value) -> float:
	return float(GameConfig.get_tuning(key, default_value))


func setup(battle_node) -> void:
	battle = battle_node


func is_active() -> bool:
	return active


func show_fail_pose() -> bool:
	return active or frozen


func reset() -> void:
	active = false
	frozen = false
	phase = "idle"
	timer = 0.0
	on_complete = Callable()
	if battle:
		battle.exit_fail_death_presentation()
		if battle.player:
			battle.player.clear_fail_death_visuals()


func start(finish_cb: Callable) -> void:
	reset()
	if battle == null or battle.player == null:
		if finish_cb.is_valid():
			finish_cb.call()
		return

	active = true
	frozen = false
	phase = "dying"
	timer = 0.0
	on_complete = finish_cb

	var speed_scale := _tuning("fail_death_anim_speed_scale", 0.35)
	var player: BattlePlayer = battle.player

	battle.enter_fail_death_presentation()
	player.state = BattlePlayer.State.IDLE
	player.begin_fail_death({"speed_scale": speed_scale})


func update(delta: float) -> void:
	if not active:
		return
	timer += delta
	match phase:
		"dying":
			var fade_dur := maxf(0.001, _tuning("fail_death_dim_fade", 0.35))
			var target_alpha := _tuning("fail_death_dim_alpha", 0.55)
			var fade_t := clampf(timer / fade_dur, 0.0, 1.0)
			battle.set_fail_death_dim(target_alpha * fade_t)
			if battle.player.is_fail_death_anim_finished():
				battle.player.freeze_fail_death_pose()
				_finish()


func _finish() -> void:
	frozen = true
	active = false
	phase = "done"
	if battle:
		battle.set_fail_death_dim(_tuning("fail_death_dim_alpha", 0.55))
	var cb := on_complete
	on_complete = Callable()
	if cb.is_valid():
		cb.call()
