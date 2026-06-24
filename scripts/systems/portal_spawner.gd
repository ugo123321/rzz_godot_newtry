extends Node2D
class_name PortalSpawner

const LotteryPortalScript = preload("res://scripts/entities/lottery_portal.gd")

const TICK_INTERVAL := 1.5

var active := false
var _tick_t := 0.0
var _active_portal: Node = null


func reset() -> void:
	active = false
	_tick_t = 0.0
	if is_instance_valid(_active_portal):
		_active_portal.queue_free()
	_active_portal = null


func begin() -> void:
	reset()
	active = true


func stop() -> void:
	active = false


func update(delta: float, battle: Node) -> void:
	if not active:
		return
	if is_instance_valid(_active_portal):
		# wait for current portal to expire or be consumed
		return
	_tick_t += delta
	if _tick_t < TICK_INTERVAL:
		return
	_tick_t = 0.0
	var chance := float(GameConfig.get_tuning("portal_chance_per_tick", 0.015))
	if randf() >= chance:
		return
	_spawn_portal(battle)


func _spawn_portal(battle: Node) -> void:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var safe: Vector2 = battle.player.global_position if battle.player else Vector2(w * 0.5, h * 0.5)
	var portal = LotteryPortalScript.new()
	var pos := _pick_position(w, h, safe, battle)
	if pos == Vector2.INF:
		return
	var container: Node = battle.portal_container if "portal_container" in battle else self
	container.add_child(portal)
	portal.setup(pos, float(GameConfig.get_tuning("portal_lifetime_sec", 5.0)))
	_active_portal = portal


func _pick_position(w: float, h: float, safe: Vector2, battle: Node) -> Vector2:
	var trees: Array = []
	if "tree_spawner" in battle and battle.tree_spawner != null:
		trees = battle.tree_spawner.get_active_trees()
	for attempt in range(40):
		var pos := Vector2(randf_range(60.0, w - 60.0), randf_range(140.0, h - 200.0))
		if pos.distance_to(safe) < 140.0:
			continue
		var clash := false
		for t in trees:
			if is_instance_valid(t) and pos.distance_to(t.global_position) < 60.0:
				clash = true
				break
		if not clash:
			return pos
	return Vector2.INF


func has_active_portal() -> bool:
	return is_instance_valid(_active_portal)


func clear_active_portal() -> void:
	if is_instance_valid(_active_portal):
		_active_portal.queue_free()
	_active_portal = null
