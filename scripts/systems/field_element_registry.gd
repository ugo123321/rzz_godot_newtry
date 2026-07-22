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
	z_index = -1  # 沉到怪物/玩家(z0)之下、地形(z-5)/草地(z-4)之上：地块元素是"踩在地面"的，不该盖住单位


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


# 半径版移动阻挡：mover 中心与任一 move-blocking 元素中心的距离 < (块体半径 + mover 半径) 即挡。
# 块体半径 = 半格 20（特殊块填满一格）。用半径而非格中心，避免 mover 身体视觉重叠进块里。
const BLOCK_BODY_RADIUS := 20.0
func is_move_blocked_radius(world_pos: Vector2, mover_radius: float) -> bool:
	var stop := BLOCK_BODY_RADIUS + mover_radius
	for entry in _by_cell.values():
		if not bool(entry.get("move", false)):
			continue
		var e = entry.get("entity")
		if e == null or not is_instance_valid(e):
			continue
		if world_pos.distance_to(e.global_position) < stop:
			return true
	return false


func has_bullet_blocking_at(col: int, row: int) -> bool:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return not entry.is_empty() and bool(entry.get("bullet", false))


func entity_at(col: int, row: int) -> Node:
	var entry: Dictionary = _by_cell.get(col * 10000 + row, {})
	return entry.get("entity", null)


# 所有 move-blocking 的实体（供怪物脱困推力遍历）。跳过已失效的实例。
func get_move_blocking_entities() -> Array:
	var out: Array = []
	for entry in _by_cell.values():
		if not bool(entry.get("move", false)):
			continue
		var e = entry.get("entity")
		if e != null and is_instance_valid(e):
			out.append(e)
	return out


func clear() -> void:
	_by_cell.clear()
	blocking_cells_changed.emit()
