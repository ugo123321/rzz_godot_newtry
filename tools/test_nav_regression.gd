extends SceneTree
# 多场景回归：横墙绕行 / 横墙 1 格缺口穿越 / 竖墙绕行。
# 用真实 MonsterNavigator + 忠实 update_ai 移动循环。
const TS := 40
const BLOCK_BODY := 20.0
const MOVE_SPEED := 19.0
const REACH_PX := 20.0
const NAV_REPATH_SEC := 0.30
const NAV_STUCK_SEC := 0.60
const COLS := 30
const ROWS := 20

class MockTerrain extends Node:
	func get_rows() -> int: return ROWS
	func get_cols() -> int: return COLS
	func is_blocking_for_movement(_c, _r) -> bool: return false

class MockFE extends Node:
	var cells := {}   # Vector2i -> true
	func add(c: int, r: int) -> void: cells[Vector2i(c, r)] = true
	func has_move_blocking_at(col, row) -> bool: return cells.has(Vector2i(col, row))
	func is_move_blocked_radius(world_pos, mover_radius) -> bool:
		var stop: float = BLOCK_BODY + mover_radius
		for c in cells:
			var center := Vector2(c.x * TS + 20, c.y * TS + 20)
			if world_pos.distance_to(center) < stop:
				return true
		return false

func _steer(path, wp_ref, pos, player_pos) -> Vector2:
	var wp: int = wp_ref[0]
	while wp < path.size() and pos.distance_to(path[wp]) < REACH_PX:
		wp += 1
	wp_ref[0] = wp
	if wp >= path.size(): return player_pos
	var target: Vector2 = path[wp]
	var base_dir: Vector2 = (target - pos).normalized()
	var lim: int = mini(wp + 4, path.size())
	for i in range(wp + 1, lim):
		var cand: Vector2 = path[i]
		if base_dir.dot((cand - pos).normalized()) > 0.966: target = cand
		else: break
	return target

func _sim(fe, r, start, player_pos) -> Dictionary:
	var nav = preload("res://scripts/systems/monster_navigator.gd").new()
	root.add_child(nav)
	nav.configure(MockTerrain.new(), fe)
	var pos: Vector2 = start
	var path := nav.find_path_world(pos, player_pos)
	var wp_ref := [1 if path.size() > 1 else 0]
	var repath := NAV_REPATH_SEC
	var stuck := 0.0
	var last_pcell := nav.world_to_cell(player_pos)
	var d := 1.0 / 60.0
	var mind := pos.distance_to(player_pos)
	for f in 4000:
		repath -= d
		var pcell: Vector2i = nav.world_to_cell(player_pos)
		if repath <= 0.0 or path.is_empty() or pcell != last_pcell:
			path = nav.find_path_world(pos, player_pos)
			wp_ref[0] = 1 if path.size() > 1 else 0
			repath = NAV_REPATH_SEC
			last_pcell = pcell
		var st := _steer(path, wp_ref, pos, player_pos)
		var to_t: Vector2 = st - pos
		var dir: Vector2 = to_t.normalized() if to_t.length_squared() > 0.0001 else (player_pos - pos).normalized()
		var step: float = MOVE_SPEED * d
		var nxt: Vector2 = pos + dir * step
		if fe.is_move_blocked_radius(nxt, r):
			stuck += d
			if stuck > NAV_STUCK_SEC:
				path = PackedVector2Array(); repath = 0.0
			var perp := Vector2(-dir.y, dir.x)
			var a: Vector2 = pos + perp * step
			var b: Vector2 = pos - perp * step
			var ba: bool = fe.is_move_blocked_radius(a, r)
			var bb: bool = fe.is_move_blocked_radius(b, r)
			if not ba and not bb: pos = a if a.distance_to(player_pos) <= b.distance_to(player_pos) else b
			elif not ba: pos = a
			elif not bb: pos = b
		else:
			stuck = 0.0; pos = nxt
		mind = minf(mind, pos.distance_to(player_pos))
		if pos.distance_to(player_pos) < 30.0:
			nav.queue_free(); return {"reached": true, "f": f, "mind": int(mind)}
	nav.queue_free()
	return {"reached": false, "f": 4000, "mind": int(mind)}

func _run(name, fe, start, player) -> void:
	var a := _sim(fe, 13.0, start, player)
	print(name, " R13 到达=", a.reached, " f=", a.f, " mind=", a.mind)

func _initialize() -> void:
	# 场景1：横墙 col6..23 row10，绕东端
	var fe1 := MockFE.new()
	for c in range(6, 24): fe1.add(c, 10)
	_run("横墙绕行", fe1, Vector2(15*TS+20, 4*TS+20), Vector2(15*TS+20, 16*TS+20))

	# 场景2：横墙 col0..29 row10 但 col15 缺口，必须穿缝
	var fe2 := MockFE.new()
	for c in range(0, 30):
		if c != 15: fe2.add(c, 10)
	_run("横墙缺口穿越", fe2, Vector2(15*TS+20, 4*TS+20), Vector2(15*TS+20, 16*TS+20))

	# 场景3：竖墙 row3..16 col15，绕南端(row17 开放)
	var fe3 := MockFE.new()
	for rr in range(3, 17): fe3.add(15, rr)
	_run("竖墙绕行", fe3, Vector2(8*TS+20, 10*TS+20), Vector2(22*TS+20, 10*TS+20))
	quit()
