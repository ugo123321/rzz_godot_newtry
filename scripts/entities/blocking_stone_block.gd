extends FieldElement
class_name BlockingStoneBlock

# 阻挡石块（实体版）：阻挡移动 + 画线 + 子弹。作为实体放在地板之上，
# 这样"水地板上放阻挡石"能同时保留地板与石块两层视觉。
# 对敌人无效。
# 视觉走美术素材 stone_block.png（40×40，与 TILE_SIZE 对齐），不再过程化绘制。

const STONE_BLOCK_TEX := preload("res://assets/ui/terrains/stone_block.png")


func setup_block(col: int, row: int) -> void:
	setup(col, row, "blocking_stone", "up")
	_configure_blocking(true, true, true)
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = STONE_BLOCK_TEX.get_size()
	draw_texture(STONE_BLOCK_TEX, -sz * 0.5)
