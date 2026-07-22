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


# 幂等地初始化 _astar。Godot 4 的 _ready 对运行时 add_child 的节点是延迟的（同帧不会触发），
# 故不能在 _ready 里建 _astar——configure() 紧跟 add_child 调用，会撞 null。改由本方法按需初始化。
func _ensure_astar() -> void:
	if _astar != null:
		return
	_astar = AStarGrid2D.new()
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_astar.offset = Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)  # 路径点 = 格中心 world 坐标
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES  # 不许贴墙角斜切（怪有碰撞半径，斜切会被卡在角上）
	_astar.jumping_enabled = false  # 不许贴角斜穿两个阻挡格


func _ready() -> void:
	_ensure_astar()


func configure(terrain: Node, field_elements: Node) -> void:
	_ensure_astar()
	_terrain = terrain
	_field_elements = field_elements
	_refresh_size()
	_dirty = true


func _refresh_size() -> void:
	if _terrain == null or not _terrain.has_method("get_rows") or not _terrain.has_method("get_cols"):
		_cols = 0
		_rows = 0
		_astar.region = Rect2i(0, 0, 1, 1)
		_astar.update()  # 改 region 后必须 update()，否则 set_point_solid 报 "Grid is not initialized"
		return
	_rows = _terrain.get_rows()
	_cols = _terrain.get_cols()
	_astar.region = Rect2i(0, 0, maxi(1, _cols), maxi(1, _rows))
	_astar.update()


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
	_ensure_astar()
	_flush_if_dirty()
	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)
	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return PackedVector2Array()
	# 起点/终点落在 solid 格（怪蹭到墙角，中心 floor 进阻挡格）时，别直接放弃——
	# 那会让怪回落"直冲玩家"撞死在墙上。改为吸附到最近的可通行格，仍算出绕行路径。
	if _astar.is_point_solid(from_cell):
		from_cell = _nearest_free_cell(from_cell)
		if from_cell.x < 0:
			return PackedVector2Array()
	if _astar.is_point_solid(to_cell):
		to_cell = _nearest_free_cell(to_cell)
		if to_cell.x < 0:
			return PackedVector2Array()
	return _astar.get_point_path(from_cell, to_cell)


# 从 solid 格向外做方形环搜索，返回最近的非 solid 格；找不到返回 (-1,-1)。
func _nearest_free_cell(cell: Vector2i) -> Vector2i:
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue  # 只查当前环的外圈
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


# 线段是否贴墙（穿过 solid 格或其 8 邻格任一）。
# 用于路径 lookahead 平滑时禁止贴墙切角——直接跳到远处 waypoint 会切进墙的 33px 阻挡半径。
# 返回 true 表示该直线太贴墙，不应跳过中间 waypoint。
func segment_too_close_to_solid(from_world: Vector2, to_world: Vector2) -> bool:
	_ensure_astar()
	_flush_if_dirty()
	var d := to_world - from_world
	var len := d.length()
	if len <= 0.5:
		return false
	var steps := maxi(2, int(len / 10.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from_world + d * t
		var c := world_to_cell(p)
		if _cell_or_neighbor_solid(c.x, c.y):
			return true
	return false


# 该格或其 8 邻格任一为 solid 即 true（越界格不算，避免场边总误判）。
func _cell_or_neighbor_solid(col: int, row: int) -> bool:
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nc := col + dc
			var nr := row + dr
			if nc < 0 or nc >= _cols or nr < 0 or nr >= _rows:
				continue
			if _astar.is_point_solid(Vector2i(nc, nr)):
				return true
	return false
