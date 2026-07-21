extends Node2D
class_name FieldElement

# 局内特殊地块上放置的"元素实体"基类（箭块 / 锁定块 / 固定传送门 / 普通宝箱 / 锁闭宝箱）。
# 由关卡编辑器或 battle._apply_level_layout 生成；统一走 FieldElementRegistry 注册到 battle.field_elements。
# 单格占位（cell_col / cell_row），渲染尺寸 = TerrainBackground.TILE_SIZE（40px）。
#
# 子类需覆写 _draw（过程化像素绘制，CLAUDE.md §9 多色分层 + 闪烁 + 外发光）和（如需）_process / _input。

const TILE_SIZE := 40  # 与 TerrainBackground.TILE_SIZE 对齐

var cell_col: int = 0
var cell_row: int = 0
var kind: String = ""          # "arrow_single" / "arrow_cross" / "locked_block" / "fixed_portal" / "chest_normal" / "chest_locked"
var facing: String = "up"     # 朝向（箭块用）：up/down/left/right
var consumed: bool = false    # 一次性元素（宝箱/锁定块）是否已被消费

# 阻挡属性：注册到 FieldElementRegistry 时用于 line/move/bullet 统一查询。
# 默认值由子类 setup 时设定；锁定块解锁后 / 宝箱开启后应置 false 并 unregister。
var blocks_line: bool = false
var blocks_move: bool = false
var blocks_bullet: bool = false

var _battle: Node = null      # 缓存 battle 引用，子类直接用


func setup(col: int, row: int, p_kind: String, p_facing: String = "up") -> void:
	cell_col = col
	cell_row = row
	kind = p_kind
	facing = p_facing
	# 以格中心为锚点（FieldElement 的 global_position 即格中心）。
	global_position = _cell_center(col, row)
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_facing(p_facing: String) -> void:
	facing = p_facing
	queue_redraw()


# 由子类决定本元素是否阻挡（默认 false，子类在 setup 里覆写）。
func _configure_blocking(line: bool, move: bool, bullet: bool) -> void:
	blocks_line = line
	blocks_move = move
	blocks_bullet = bullet


func register_self(battle: Node) -> void:
	_battle = battle
	if battle and "field_elements" in battle and battle.field_elements and battle.field_elements.has_method("register"):
		battle.field_elements.register(cell_col, cell_row, self, blocks_line, blocks_move, blocks_bullet)


func unregister_self(battle: Node) -> void:
	_battle = battle
	if battle and "field_elements" in battle and battle.field_elements and battle.field_elements.has_method("unregister"):
		battle.field_elements.unregister(cell_col, cell_row)


# 序列化用：返回 {type, col, row, facing}，供 LevelLayoutLoader 保存。
func serialize() -> Dictionary:
	return {
		"type": kind,
		"col": cell_col,
		"row": cell_row,
		"facing": facing,
	}


func _cell_center(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * float(TILE_SIZE), (row + 0.5) * float(TILE_SIZE))


# 子类覆写：消费（宝箱开启 / 锁定块解锁）后的清理 —— 取消注册 + queue_free。
func consume(battle: Node) -> void:
	if consumed:
		return
	consumed = true
	unregister_self(battle)
	queue_free()


func _draw() -> void:
	pass  # 子类覆写
