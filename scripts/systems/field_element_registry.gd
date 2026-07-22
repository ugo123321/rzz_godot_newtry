extends Node2D
class_name FieldElementRegistry

# 战场上"放置元素实体"的格注册表：按 col*10000+row 索引。
# 提供 line / move / bullet 三类阻挡的统一查询（合并地形 TerrainBackground + 本注册表）。
# battle 侧通过 is_bullet_blocked_at(world_pos) / is_field_blocking_for_line(world_pos) 调用。

# 同一格可能存在多个元素（极少见），但注册只保留"阻挡属性 OR 之后的最新一个"；
# 实际上场每格至多一个放置元素，所以这里用单 Dictionary 即可。

var _by_cell: Dictionary = {}  # key = col*10000+row -> {entity, line, move, bullet}

signal blocking_cells_changed  # 注册/注销阻挡格时 emit，供 MonsterNavigator 标 dirty


func _ready() -> void:
	name = "FieldElements"
	z_index = 2  # 在 Trees(z0) 之上、WoodDrops(z3) 之下偏后


func register(col: int, row: int, entity: Node, line: bool, move: bool, bullet: bool) -> void:
	var key: int = col * 10000 + row
	var prev: Dictionary = _by_cell.get(key, {})
	# 同格已有元素：取并集（任一阻挡即阻挡），entity 记最新（消费时由最新调用 unregister）。
	_by_cell[key] = {
		"entity": entity,
		"line": bool(prev.get("line", false)) or line,
		"move": bool(prev.get("move", false)) or move,
		"bullet": bool(prev.get("bullet", false)) or bullet,
	}
	blocking_cells_changed.emit()


func unregister(col: int, row: int) -> void:
	_by_cell.erase(col * 10000 + row)
	blocking_cells_changed.emit()


func has_blocking_at(col: int, row: int) -> bool:
	var key: int = col * 10000 + row
	var entry: Dictionary = _by_cell.get(key, {})
	if entry.is_empty():
		return false
	return bool(entry.get("line", false)) or bool(entry.get("move", false)) or bool(entry.get("bullet", false))


func has_line_blocking_at(col: int, row: int) -> bool:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return not entry.is_empty() and bool(entry.get("line", false))


func has_move_blocking_at(col: int, row: int) -> bool:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return not entry.is_empty() and bool(entry.get("move", false))


func has_bullet_blocking_at(col: int, row: int) -> bool:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return not entry.is_empty() and bool(entry.get("bullet", false))


func entity_at(col: int, row: int) -> Node:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return entry.get("entity", null)


func clear() -> void:
	_by_cell.clear()
	blocking_cells_changed.emit()
