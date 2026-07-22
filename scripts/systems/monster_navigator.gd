extends Node
class_name MonsterNavigator

# A* 网格寻路：为怪物在 40px 地块网格上算绕墙路径。
# solid 判定 = terrain.is_blocking_for_movement(col,row) OR field_elements.has_move_blocking_at(col,row)
# water 非 solid（怪物照走水，与现状一致）；树不入网格（由 monster 的微碰撞滑步处理）。
# battle 在 stage 布局就绪后 / field element 注册变化时 mark_dirty()，下次查询懒重建。

const TILE_SIZE := 40  # 与 TerrainBackground.TILE_SIZE 一致

var _astar: AStarGrid2D = null
var _terrain: Node = null        # TerrainBackground
var _field_elements: Node = null  # FieldElementRegistry
var _cols: int = 0
var _rows: int = 0
var _dirty: bool = true


func _ready() -> void:
	_astar = AStarGrid2D.new()
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_astar.offset = Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)  # 路径点 = 格中心 world 坐标
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_astar.jumping_enabled = false  # 不许贴角斜穿两个阻挡格


func configure(terrain: Node, field_elements: Node) -> void:
	_terrain = terrain
	_field_elements = field_elements
	_refresh_size()
	_dirty = true


func _refresh_size() -> void:
	if _terrain == null or not _terrain.has_method("get_rows") or not _terrain.has_method("get_cols"):
		_cols = 0
		_rows = 0
		_astar.region = Rect2i(0, 0, 1, 1)
		return
	_rows = _terrain.get_rows()
	_cols = _terrain.get_cols()
	_astar.region = Rect2i(0, 0, maxi(1, _cols), maxi(1, _rows))


func mark_dirty() -> void:
	_dirty = true


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / float(TILE_SIZE))), int(floor(world_pos.y / float(TILE_SIZE))))


func _cell_solid(col: int, row: int) -> bool:
	if col < 0 or col >= _cols or row < 0 or row >= _rows:
		return true  # 越界当 solid，逼路径留在场内
	if _terrain and _terrain.has_method("is_blocking_for_movement") and _terrain.is_blocking_for_movement(col, row):
		return true
	if _field_elements and _field_elements.has_method("has_move_blocking_at") and _field_elements.has_move_blocking_at(col, row):
		return true
	return false


func _flush_if_dirty() -> void:
	if not _dirty:
		return
	_refresh_size()
	_dirty = false
	for r in range(_rows):
		for c in range(_cols):
			_astar.set_point_solid(Vector2i(c, r), _cell_solid(c, r))


# from_world -> to_world 的世界坐标 waypoint 数组。起点/终点 solid 或无路径 → 空数组（调用方回落直冲玩家）。
func find_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()
	_flush_if_dirty()
	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)
	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return PackedVector2Array()
	if _astar.is_point_solid(from_cell) or _astar.is_point_solid(to_cell):
		return PackedVector2Array()
	return _astar.get_point_path(from_cell, to_cell)
