extends SceneTree

# 诊断 v3：模拟怪物跟随 A* 路径的真实移动（含碰撞 + sidestep fallback），
# 验证"±45° 对角 fallback"能否让怪穿过 1 格缺口。
# 墙：col=9 row 3..7 + 9..14（row=8 缺口）。怪从 (20, 330) [故意偏中心线 10px] 到东侧。
# 运行： /d/godot/godot --headless -s tools/test_navigator_sim.gd

const TS := 40
const BLOCK_BODY := 20.0
const MOVE_SPEED := 19.0
const REACH_PX := 20.0

class MockTerrain extends Node:
	var cols := 18
	var rows := 18
	func get_rows() -> int: return rows
	func get_cols() -> int: return cols
	func is_blocking_for_movement(_c: int, _r: int) -> bool: return false

class WallElement:
	var pos: Vector2
	func _init(p: Vector2) -> void: pos = p

class MockFieldElements extends Node:
	var walls: Array = []
	func _init() -> void:
		for r in range(3, 8):
			walls.append(WallElement.new(Vector2(9 * TS + 20, r * TS + 20)))
		for r in range(9, 15):
			walls.append(WallElement.new(Vector2(9 * TS + 20, r * TS + 20)))
	func has_move_blocking_at(col: int, row: int) -> bool:
		if col != 9: return false
		return (row >= 3 and row <= 7) or (row >= 9 and row <= 14)
	func is_move_blocked_radius(world_pos: Vector2, mover_radius: float) -> bool:
		var stop := BLOCK_BODY + mover_radius
		for w in walls:
			if world_pos.distance_to(w.pos) < stop:
				return true
		return false

func _blocked(fe: MockFieldElements, pos: Vector2, r: float) -> bool:
	return fe.is_move_blocked_radius(pos, r)

# 单次模拟：use_diag 控制是否启用 ±45° fallback；r 为怪碰撞半径。返回最终 x（>660 算穿过）。
func _simulate(fe: MockFieldElements, use_diag: bool, r: float) -> Dictionary:
	var nav = preload("res://scripts/systems/monster_navigator.gd").new()
	root.add_child(nav)
	nav.configure(MockTerrain.new(), fe)
	var pos := Vector2(20.0, 330.0)  # 故意偏中心线 10px（row8 中心是 340）
	var player_pos := Vector2(17 * TS + 20, 8 * TS + 20)
	var path := nav.find_path_world(pos, player_pos)
	var wp := 0
	var stuck_frames := 0
	var delta := 1.0 / 60.0
	for frame in 2000:
		# 推进 waypoint（reach）
		while wp < path.size() and pos.distance_to(path[wp]) < REACH_PX:
			wp += 1
		var steer_target: Vector2 = player_pos if wp >= path.size() else path[wp]
		var to_target: Vector2 = steer_target - pos
		var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT
		var step_len: float = MOVE_SPEED * delta
		var next_pos: Vector2 = pos + dir * step_len
		if not _blocked(fe, next_pos, r):
			pos = next_pos
			stuck_frames = 0
		else:
			stuck_frames += 1
			# perp ±90
			var perp_a := Vector2(-dir.y, dir.x)
			var alt_a := pos + perp_a * step_len
			var alt_b := pos - perp_a * step_len
			if not _blocked(fe, alt_a, r) and not _blocked(fe, alt_b, r):
				pos = alt_a if alt_a.distance_to(steer_target) <= alt_b.distance_to(steer_target) else alt_b
			elif not _blocked(fe, alt_a, r):
				pos = alt_a
			elif not _blocked(fe, alt_b, r):
				pos = alt_b
			elif use_diag:
				# ±45° 对角 fallback（待验证的修复）
				var da := pos + dir.rotated(PI * 0.25) * step_len
				var db := pos + dir.rotated(-PI * 0.25) * step_len
				if not _blocked(fe, da, r) and not _blocked(fe, db, r):
					pos = da if da.distance_to(steer_target) <= db.distance_to(steer_target) else db
				elif not _blocked(fe, da, r):
					pos = da
				elif not _blocked(fe, db, r):
					pos = db
			if pos.x >= player_pos.x - 40:
				break
		if pos.x >= player_pos.x - 40:
			break
	nav.queue_free()
	return {"x": pos.x, "stuck": stuck_frames, "reached": pos.x >= player_pos.x - 40}

func _initialize() -> void:
	print("=== 怪物移动模拟（偏中心线 10px 起步，1 格缺口）===")
	var fe := MockFieldElements.new()
	var r1 := _simulate(fe, false, 20.0)
	print("R=20 无 fallback: x=", r1.x, " 穿越=", r1.reached, " stuck=", r1.stuck)
	var fe2 := MockFieldElements.new()
	var r2 := _simulate(fe2, true, 20.0)
	print("R=20 有 ±45° fallback: x=", r2.x, " 穿越=", r2.reached, " stuck=", r2.stuck)
	var fe3 := MockFieldElements.new()
	var r3 := _simulate(fe3, true, 13.0)
	print("R=13 有 ±45° fallback: x=", r3.x, " 穿越=", r3.reached, " stuck=", r3.stuck)
	var fe4 := MockFieldElements.new()
	var r4 := _simulate(fe4, false, 13.0)
	print("R=13 无 fallback: x=", r4.x, " 穿越=", r4.reached, " stuck=", r4.stuck)
	if r3.reached and not r1.reached:
		print("RESULT: R=20 卡死、R=13 穿过 → 减半径到 hitbox(13) 是关键修复")
	elif r3.reached and r2.reached:
		print("RESULT: 两种半径都能穿 → 症状另有原因")
	else:
		print("RESULT: R=13 也卡 → 缺口太窄，需加宽缺口或 A* 半径膨胀")
	quit()
