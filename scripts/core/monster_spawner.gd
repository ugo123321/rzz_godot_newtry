extends Node2D
class_name MonsterSpawner

var monsters: Array = []
var spawn_clusters: Array = []
var boss: Node = null

var _spawn_queue: Array = []
var _spawn_timer := 0.0
var _pending_boss_stage := -1
var _pending_boss_id := ""


func reset() -> void:
	_clear_spawn_schedule()
	for m in monsters:
		if is_instance_valid(m):
			m.queue_free()
	monsters.clear()
	spawn_clusters.clear()
	if is_instance_valid(boss):
		boss.queue_free()
	boss = null


func spawn_stage(stage_index: int, battle: Node) -> void:
	reset()
	_spawn_stage_content(stage_index, battle)


func append_stage(stage_index: int, battle: Node) -> void:
	_purge_inactive_monsters()
	_spawn_stage_content(stage_index, battle)


func is_spawning() -> bool:
	return _pending_boss_stage >= 0 or not _spawn_queue.is_empty() or _spawn_timer > 0.0


func update_spawns(delta: float, battle: Node) -> void:
	if delta <= 0.0:
		return
	if _spawn_timer > 0.0:
		_spawn_timer = maxf(0.0, _spawn_timer - delta)
	if _pending_boss_stage >= 0:
		if _spawn_timer > 0.0:
			return
		_spawn_boss(battle, _pending_boss_stage, _pending_boss_id)
		_pending_boss_stage = -1
		_pending_boss_id = ""
		return
	if _spawn_queue.is_empty() or _spawn_timer > 0.0:
		return
	var entry: Dictionary = _spawn_queue.pop_front()
	_spawn_monster(str(entry.get("kind_id", "NORMAL")), int(entry.get("stage_index", 0)), battle)
	if not _spawn_queue.is_empty():
		_spawn_timer = _spawn_interval()


func _purge_inactive_monsters() -> void:
	var i := monsters.size() - 1
	while i >= 0:
		var m = monsters[i]
		if not is_instance_valid(m) or m.get("dying") == true or m.get("alive") == false:
			if is_instance_valid(m):
				m.queue_free()
			monsters.remove_at(i)
		i -= 1
	if is_instance_valid(boss) and boss.is_defeated():
		boss.queue_free()
		boss = null


func _spawn_stage_content(stage_index: int, battle: Node) -> void:
	var stage := GameConfig.get_stage(stage_index)
	if stage.is_empty():
		return
	_spawn_timer = maxf(_spawn_timer, _spawn_wave_delay())
	var boss_id := str(stage.get("boss_id", ""))
	if not boss_id.is_empty():
		_pending_boss_stage = stage_index
		_pending_boss_id = boss_id
		return
	var counts := {
		"NORMAL": maxi(0, int(stage.get("normal", 0))),
		"ELITE": maxi(0, int(stage.get("elite", 0))),
		"SHIELD": maxi(0, int(stage.get("shield", 0))),
		"BERSERKER": maxi(0, int(stage.get("berserker", 0))),
		"SPLITTER": maxi(0, int(stage.get("splitter", 0))),
		"ARCHER": maxi(0, int(stage.get("archer", 0))),
		"FIRE_MAGE": maxi(0, int(stage.get("fire_mage", 0))),
		"SHOTGUN": maxi(0, int(stage.get("shotgun", 0))),
		"CROSS_SHOOTER": maxi(0, int(stage.get("cross_shooter", 0))),
		"BOUNCE_SLIME": maxi(0, int(stage.get("bounce_slime", 0))),
	}
	_init_clusters(battle)
	for kind_id in counts.keys():
		for i in range(counts[kind_id]):
			_spawn_queue.append({"kind_id": kind_id, "stage_index": stage_index})
	_spawn_queue.shuffle()


func get_active_monsters() -> Array:
	if boss and is_instance_valid(boss) and boss.has_method("is_boss_active") and boss.is_boss_active():
		if boss.has_method("get_active_segments"):
			return boss.get_active_segments()
		return [boss]
	var result: Array = []
	for m in monsters:
		if _is_combat_targetable(m):
			result.append(m)
	return result


func unregister_monster(monster: Node) -> void:
	var idx := monsters.find(monster)
	if idx >= 0:
		monsters.remove_at(idx)


func _is_combat_targetable(m: Node) -> bool:
	if not is_instance_valid(m):
		return false
	if m.has_method("is_combat_targetable"):
		return m.is_combat_targetable()
	if m.get("alive") == false:
		return false
	if m.get("dying") == true:
		return false
	return true


func all_dead() -> bool:
	if is_spawning():
		return false
	if boss and is_instance_valid(boss):
		return boss.is_defeated()
	for m in monsters:
		if not is_instance_valid(m):
			continue
		if m.get("alive") == false or m.get("dying") == true:
			continue
		return false
	return true


func _clear_spawn_schedule() -> void:
	_spawn_queue.clear()
	_spawn_timer = 0.0
	_pending_boss_stage = -1
	_pending_boss_id = ""


func _spawn_interval() -> float:
	return float(GameConfig.get_tuning("monster_spawn_interval", 0.05))


func _spawn_wave_delay() -> float:
	return float(GameConfig.get_tuning("monster_spawn_wave_delay", 0.55))


func _init_clusters(battle: Node) -> void:
	spawn_clusters.clear()
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var safe: Vector2 = battle.player.global_position if battle.player else Vector2(w * 0.5, h * 0.62)
	var min_player_dist := 140.0
	var cluster_count := randi_range(5, 9)
	for i in range(cluster_count):
		for attempt in range(80):
			var x := MathUtils.rand_range(26.0, w - 26.0)
			var y := MathUtils.rand_range(88.0, h - 120.0)
			if MathUtils.dist(Vector2(x, y), safe) < min_player_dist:
				continue
			var density := MathUtils.rand_range(0.3, 1.0)
			spawn_clusters.append({
				"x": x,
				"y": y,
				"radius": MathUtils.lerp_f(48.0, 92.0, density),
				"weight": 0.25 + density * density * 1.4,
			})
			break
	if spawn_clusters.is_empty():
		spawn_clusters.append({"x": w * 0.72, "y": h * 0.45, "radius": 80.0, "weight": 1.0})


func _pick_spawn_pos(battle: Node) -> Vector2:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var safe: Vector2 = battle.player.global_position if battle.player else Vector2(w * 0.5, h * 0.62)
	for i in range(140):
		var pos := Vector2.ZERO
		if randf() < 0.74 and not spawn_clusters.is_empty():
			var cluster = _pick_weighted_cluster()
			var ang := MathUtils.rand_range(0.0, TAU)
			var rad := float(cluster.radius) * sqrt(randf())
			pos = Vector2(float(cluster.x), float(cluster.y)) + Vector2(cos(ang), sin(ang)) * rad
		else:
			pos = Vector2(MathUtils.rand_range(26.0, w - 26.0), MathUtils.rand_range(88.0, h - 120.0))
		if MathUtils.dist(pos, safe) < 140.0:
			continue
		var ok := true
		for m in get_active_monsters():
			if MathUtils.dist(pos, m.global_position) < 20.0:
				ok = false
				break
		for m in monsters:
			if not is_instance_valid(m):
				continue
			if m.has_method("is_spawn_locked") and m.is_spawn_locked():
				if MathUtils.dist(pos, m.global_position) < 20.0:
					ok = false
					break
		if ok:
			return pos
	return Vector2(w * 0.72, h * 0.45)


func _pick_weighted_cluster() -> Dictionary:
	var total := 0.0
	for c in spawn_clusters:
		total += float(c.weight)
	var roll := randf() * total
	for c in spawn_clusters:
		roll -= float(c.weight)
		if roll <= 0.0:
			return c
	return spawn_clusters.back()


func _spawn_monster(kind_id: String, stage_index: int, battle: Node) -> void:
	var scene: PackedScene = load("res://scenes/entities/monster.tscn")
	var monster = scene.instantiate()
	battle.monster_container.add_child(monster)
	monster.setup(kind_id, stage_index, _pick_spawn_pos(battle))
	monster.begin_spawn()
	monsters.append(monster)


func spawn_split_children(parent: BattleMonster) -> Array:
	if parent == null or not parent.can_split():
		return []
	var battle_node = get_parent()
	if battle_node == null:
		return []
	parent.spawned_children = true
	var children: Array = []
	var scene: PackedScene = load("res://scenes/entities/monster.tscn")
	for i in range(parent.split_count):
		var ang := (float(i) / float(parent.split_count)) * TAU + MathUtils.rand_range(-0.25, 0.25)
		var dist := MathUtils.rand_range(12.0, 20.0)
		var pos := parent.global_position + Vector2(cos(ang), sin(ang)) * dist
		var child = scene.instantiate()
		battle_node.monster_container.add_child(child)
		child.setup("SPLITTER", parent.stage_index_cached, pos)
		child.split_tier = parent.split_tier + 1
		var child_scale := Vector2.ONE * maxf(0.55, 1.0 - child.split_tier * 0.12)
		child.scale = child_scale
		child.begin_spawn(-1.0, child_scale)
		monsters.append(child)
		children.append(child)
	return children


func _spawn_boss(battle: Node, stage_index: int, boss_id: String) -> void:
	match boss_id:
		"centipede":
			boss = CentipedeBoss.new()
		"lancer_knight":
			boss = LancerBoss.new()
		_:
			push_warning("MonsterSpawner: unknown boss_id %s" % boss_id)
			return
	boss.setup(battle, stage_index)
	battle.monster_container.add_child(boss)


func update_boss(delta: float, player: BattlePlayer) -> void:
	if boss and is_instance_valid(boss):
		boss.update_boss(delta, player)
