extends SceneTree

# 诊断 v2：怪物 A* 路径 vs 半径移动碰撞的错配。
# 模拟真实场景——blocking_stone 是 FieldElement（带位置 + 半径阻挡），不是地形 tile。
# 墙：col=9 的 row 3..7 + 9..14（row=8 是 1 格缺口）。怪从 (0,8) 到 (17,8)。
# 沿 A* 路径每段采样，用 is_move_blocked_radius(sample, R) 检查 R=20（现状）vs R=13（hitbox）是否被挡。
# 运行： /d/godot/godot --headless -s tools/test_navigator_gap.gd

const TS := 40
const BLOCK_BODY := 20.0

class MockTerrain extends Node:
	var cols := 18
	var rows := 18
	func get_rows() -> int: return rows
	func get_cols() -> int: return cols
	func is_blocking_for_movement(_c: int, _r: int) -> bool: return false  # 墙全走 FieldElement

class WallElement:
	var pos: Vector2
	func _init(p: Vector2) -> void: pos = p

class MockFieldElements extends Node:
	var walls: Array = []  # WallElement
	func _init() -> void:
		# col=9, row 3..7 和 9..14（row=8 缺口）
		for r in range(3, 8):
			walls.append(WallElement.new(Vector2(9 * TS + 20, r * TS + 20)))
		for r in range(9, 15):
			walls.append(WallElement.new(Vector2(9 * TS + 20, r * TS + 20)))
	func has_move_blocking_at(col: int, row: int) -> bool:
		# 只有 col==9 且 row 在 3..7 / 9..14 是阻挡格
		if col != 9: return false
		return (row >= 3 and row <= 7) or (row >= 9 and row <= 14)
	func is_move_blocked_radius(world_pos: Vector2, mover_radius: float) -> bool:
		var stop := BLOCK_BODY + mover_radius
		for w in walls:
			if world_pos.distance_to(w.pos) < stop:
				return true
		return false

func _initialize() -> void:
	print("=== 缺口 vs 半径碰撞 诊断 ===")
	var nav = preload("res://scripts/systems/monster_navigator.gd").new()
	root.add_child(nav)
	var fe := MockFieldElements.new()
	nav.configure(MockTerrain.new(), fe)
	var from_world := Vector2(0 * TS + 20, 8 * TS + 20)
	var to_world := Vector2(17 * TS + 20, 8 * TS + 20)
	var path := nav.find_path_world(from_world, to_world)
	print("path.size = ", path.size())
	if path.size() == 0:
		print("无路径——墙全堵死？"); quit(); return

	# 关键：怪物不可能完美踩在路径中心线上（离散步进 + waypoint 推进阈值 20px 会提前转弯）。
	# 所以除了采样中心线，还要采样"偏离中心线 5/10/15px"的点——模拟怪真实位置。
	var blocked_r20 := 0
	var blocked_r13 := 0
	var samples := 0
	var first_block_r20: Vector2 = Vector2.ZERO
	var offsets := [0.0, 5.0, 10.0]  # 模拟怪物离中心线 0/5/10px（reach_px=10 时最大约 9-10px 偏离）
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg: Vector2 = b - a
		var seglen: float = seg.length()
		var segdir: Vector2 = seg.normalized() if seglen > 0.0001 else Vector2.ZERO
		var perp: Vector2 = Vector2(-segdir.y, segdir.x)
		var stepcount := int(ceil(seglen / 20.0))
		for s in stepcount + 1:
			var t: float = (float(s) / float(stepcount)) if stepcount > 0 else 0.0
			var base: Vector2 = a + seg * t
			for off in offsets:
				var sample: Vector2 = base + perp * off  # 偏离中心线 off 像素
				if fe.is_move_blocked_radius(sample, 20.0):
					blocked_r20 += 1
					if first_block_r20 == Vector2.ZERO:
						first_block_r20 = sample
				if fe.is_move_blocked_radius(sample, 13.0):
					blocked_r13 += 1
				samples += 1
	print("采样点总数(含 4 个偏移档): ", samples)
	print("R=20（现状默认）被挡采样: ", blocked_r20, "  首个挡点: ", first_block_r20)
	print("R=13（hitbox）被挡采样: ", blocked_r13)
	if blocked_r20 > 0 and blocked_r13 == 0:
		print("RESULT: 偏离中心线时 R=20 被挡、R=13 不被挡 → 把怪物碰撞半径从默认 20 改成 hitbox(13) 可解（给缺口 7px 余量）")
	elif blocked_r20 > 0 and blocked_r13 > 0:
		print("RESULT: 两种半径都被挡 → 缺口太窄，需 A* 也按半径膨胀或加宽缺口")
	else:
		print("RESULT: R=20 不被挡 → 症状另有原因（可能 both-perp-blocked 逃逸逻辑只管树）")
	quit()
