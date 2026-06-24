extends Node2D
class_name TreeSpawner

const BattleTreeScript = preload("res://scripts/entities/battle_tree.gd")

var trees: Array = []
var active := false


func reset() -> void:
	for t in trees:
		if is_instance_valid(t):
			t.queue_free()
	trees.clear()
	active = false


func begin(battle: Node) -> void:
	reset()
	active = true
	_spawn_wave(battle)


func stop() -> void:
	active = false


func get_active_trees() -> Array:
	var alive_trees: Array = []
	for t in trees:
		if not is_instance_valid(t):
			continue
		if not t.alive:
			continue
		alive_trees.append(t)
	return alive_trees


func update_trees(_delta: float, battle: Node) -> void:
	if not active:
		return
	# 所有树实例都已释放（含倒下动画播完）后才补刷一波
	var any_left := false
	for t in trees:
		if is_instance_valid(t):
			any_left = true
			break
	if not any_left:
		_spawn_wave(battle)


func _spawn_wave(battle: Node) -> void:
	# 只移除已 free 的实例；正在播放倒下动画 (alive=false but is_instance_valid) 的不能动
	var i := trees.size() - 1
	while i >= 0:
		var t = trees[i]
		if not is_instance_valid(t):
			trees.remove_at(i)
		i -= 1
	var count := int(GameConfig.get_tuning("tree_count_per_wave", 5))
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var safe: Vector2 = battle.player.global_position if battle.player else Vector2(w * 0.5, h * 0.5)
	var stage_idx: int = battle.stage_index if "stage_index" in battle else 0
	var terrain = battle.terrain if "terrain" in battle else null
	for n in range(count):
		var pos := _pick_tree_pos(w, h, safe, terrain)
		var tree = BattleTreeScript.new()
		var container: Node = battle.tree_container if "tree_container" in battle else self
		container.add_child(tree)
		tree.setup(pos, stage_idx)
		trees.append(tree)


func _pick_tree_pos(w: float, h: float, safe: Vector2, terrain = null) -> Vector2:
	for attempt in range(60):
		var x := randf_range(60.0, w - 60.0)
		var y := randf_range(130.0, h - 200.0)
		var pos := Vector2(x, y)
		if pos.distance_to(safe) < 200.0:
			continue
		# 不在水格里生成
		if terrain and terrain.has_method("get_tile_at_world") and terrain.get_tile_at_world(x, y) == "water":
			continue
		var clash := false
		for t in trees:
			if not is_instance_valid(t):
				continue
			if pos.distance_to(t.global_position) < 110.0:
				clash = true
				break
		if not clash:
			return pos
	return Vector2(randf_range(80.0, w - 80.0), randf_range(140.0, h - 220.0))
