extends SceneTree

# Headless 诊断：MonsterNavigator 在"玩家与怪之间隔一堵阻挡石墙"时是否真的返回绕墙路径。
# 用 mock terrain（col=9 一段竖墙）+ mock field_elements（无）。
# 运行： /d/godot/godot --headless -s tools/test_navigator.gd

class MockTerrain extends Node:
	var cols := 18
	var rows := 18
	var wall_col := 9
	func get_rows() -> int:
		return rows
	func get_cols() -> int:
		return cols
	# col==9 且 row 在 3..14 是阻挡 → 一堵竖墙，上下各留口
	func is_blocking_for_movement(col: int, row: int) -> bool:
		return col == wall_col and row >= 3 and row <= 14


class MockFieldElements extends Node:
	func has_move_blocking_at(_col: int, _row: int) -> bool:
		return false


func _initialize() -> void:
	print("=== MonsterNavigator 诊断 ===")
	var NavScript = preload("res://scripts/systems/monster_navigator.gd")

	# ---- 场景 A：add_child 后 configure（模拟 battle.get_monster_navigator 真实流程）----
	var nav = NavScript.new()
	root.add_child(nav)  # 触发 _ready（同步？）
	nav.configure(MockTerrain.new(), MockFieldElements.new())
	print("[A] add_child 后 _astar 是否 null: ", nav._astar == null)

	# from 在墙左 (col 0, row 8)，to 在墙右 (col 17, row 8)
	var from_world := Vector2(0 * 40 + 20, 8 * 40 + 20)
	var to_world := Vector2(17 * 40 + 20, 8 * 40 + 20)
	var path := nav.find_path_world(from_world, to_world)
	print("[A] from ", from_world, " to ", to_world)
	print("[A] path.size = ", path.size())
	if path.size() > 2:
		print("[A] 首尾 waypoint: ", path[0], " -> ", path[path.size() - 1])
		print("[A] RESULT: A* 绕墙成功（size ", path.size(), "）")
	elif path.size() == 0:
		print("[A] RESULT: A* 返回空路径 → 怪会回落直冲玩家 → 顶墙（BUG）")
	else:
		print("[A] RESULT: A* 直线穿过墙（size ", path.size(), "）→ 墙未被标 solid（BUG）")

	# ---- 场景 B：不 add_child（验证 _ready 依赖假设）----
	var nav2 = NavScript.new()
	nav2.configure(MockTerrain.new(), MockFieldElements.new())
	print("[B] 未 add_child 时 _astar 是否 null: ", nav2._astar == null)
	var path2 := nav2.find_path_world(from_world, to_world)
	print("[B] path.size = ", path2.size(), "（若为 0 说明 _ready 没跑 → _astar null）")

	quit()
