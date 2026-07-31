extends FieldElement
class_name PitBlock

# 深坑（实体版）：只阻挡移动，**不阻挡画线/子弹/视线**（深坑是地面上的洞，画线从上方斩过、子弹飞过、视线穿过）。
# 作为实体放在地板（水/石/草）之上，"水地板上放深坑"能同时保留地板与深坑两层视觉。
# 对敌人无效（敌人不在其上刷出；敌人本身不受地块影响）。
# 视觉走美术素材 hole_block.png（40×40，与 TILE_SIZE 对齐）。

const TEX := preload("res://assets/ui/terrains/hole_block.png")


func setup_block(col: int, row: int) -> void:
	setup(col, row, "pit", "up")
	# 只挡 move；line/bullet 不挡（深坑是地面上的洞，画线从上方斩过、子弹从上方飞过）
	_configure_blocking(true, false, false)
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = TEX.get_size()
	draw_texture(TEX, -sz * 0.5)
