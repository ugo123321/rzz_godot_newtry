extends Node2D
class_name WaterOverlay

# 水地块视觉覆盖层（始终可见）。仅做一件事：用 terrain.make_water_only_texture() 在自身
# 画一遍"原色水格" —— BULLET_TIME 时 dim_overlay 把 terrain 压暗，本层位于 dim 之上，
# 水格因此保留原色不被压暗。普通模式下与 terrain 的水视觉重叠（同一张 water.png）属良性 overdraw。
# 水面流动涟漪已删除（水格基底即 water.png 贴图，不再过程化叠加横线）。
# z 关系：z_index = -1（同 dim），本节点在 _ready 里 add_child 时晚于场景文件中的 DimOverlay →
# 同 z 下后画在上 → 水在 dim 之上。怪物 / 玩家 / 树 在 z=0 → 始终在水之上。

var _water_texture: ImageTexture = null
var _battle = null


func setup(battle) -> void:
	_battle = battle
	visible = true
	z_index = -1  # 与 dim_overlay 同层，本节点后 add → 同 z 下后画在上 → 水覆盖暗罩
	# 去掉像素滤镜：与 terrain 一致走 LINEAR 平滑采样，水格贴图不再 NEAREST 像素化。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func refresh_from_terrain() -> void:
	_water_texture = null
	if _battle == null:
		queue_redraw()
		return
	var t = _battle.terrain
	if t and t.has_method("make_water_only_texture"):
		_water_texture = t.make_water_only_texture()
	queue_redraw()


func _draw() -> void:
	if _water_texture:
		draw_texture(_water_texture, Vector2.ZERO)
