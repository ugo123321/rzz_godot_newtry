extends Node2D
class_name WaterOverlay

# 水地块视觉覆盖层（始终可见）。两件事：
# 1) 用 terrain.make_water_only_texture() 在自身画一遍"原色水格" —— BULLET_TIME 时 dim_overlay 把
#    terrain 压暗，本层位于 dim 之上，水格因此保留原色不被压暗。普通模式下与 terrain 的水视觉重叠
#    （颜色一致）属于良性 overdraw。
# 2) 在水格上叠加细小高光横线（ripple bar），按 _phase 在 X 方向漂移 → 河流"流动感"。
# z 关系：z_index = -1（同 dim），本节点在 _ready 里 add_child 时晚于场景文件中的 DimOverlay →
# 同 z 下后画在上 → 水在 dim 之上。怪物 / 玩家 / 树 在 z=0 → 始终在水之上。
# 详见 plan：C:\Users\admin\.claude\plans\clever-bouncing-crane.md

const RIPPLE_BARS_PER_CELL := 2
const RIPPLE_HEIGHT_PX := 2
const RIPPLE_COLOR := Color(0.95, 0.98, 1.0, 0.42)
const RIPPLE_BASE_SPEED := 18.0   # 像素 / 秒
const RIPPLE_SPEED_VARIANCE := 7.0

var _water_texture: ImageTexture = null
var _water_cells: Array = []
var _phase: float = 0.0
var _battle = null


func setup(battle) -> void:
	_battle = battle
	visible = true
	z_index = -1  # 与 dim_overlay 同层，本节点后 add → 同 z 下后画在上 → 水覆盖暗罩
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func refresh_from_terrain() -> void:
	_water_texture = null
	_water_cells = []
	if _battle == null:
		queue_redraw()
		return
	var t = _battle.terrain
	if t and t.has_method("make_water_only_texture"):
		_water_texture = t.make_water_only_texture()
	if t and t.has_method("iter_water_cells"):
		_water_cells = t.iter_water_cells()
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	# 每帧刷一次 —— ripple 数量小（~50 格 × 2 条），开销可接受
	queue_redraw()


func _draw() -> void:
	if _water_texture:
		draw_texture(_water_texture, Vector2.ZERO)
	if _water_cells.is_empty():
		return
	var ts: int = TerrainBackground.TILE_SIZE
	for cell in _water_cells:
		var px: int = int(cell.x) * ts
		var py: int = int(cell.y) * ts
		for i in range(RIPPLE_BARS_PER_CELL):
			var bar_w: int = 10 + i * 4
			var drift_speed: float = RIPPLE_BASE_SPEED + i * RIPPLE_SPEED_VARIANCE
			# 按 cell 坐标 + bar 序号哈希，避免所有水格同步晃
			var phase_off: int = int(cell.x) * 13 + int(cell.y) * 7 + i * 23
			var x_off: int = int(fmod(_phase * drift_speed + float(phase_off), float(ts)))
			var y: int = py + 8 + i * 18
			# 横向 wrap：超出 tile 右边的部分从左边接回来，形成无缝流动
			var first_w: int = mini(bar_w, ts - x_off)
			draw_rect(Rect2(px + x_off, y, first_w, RIPPLE_HEIGHT_PX), RIPPLE_COLOR)
			if first_w < bar_w:
				draw_rect(Rect2(px, y, bar_w - first_w, RIPPLE_HEIGHT_PX), RIPPLE_COLOR)
