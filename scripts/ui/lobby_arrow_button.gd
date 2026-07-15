extends Button
class_name LobbyArrowButton

## 通用 lobby 箭头按钮（自包含，不依赖外部 style helper）。
## direction: 0 = 向右 ▶，其它（含默认 -1）= 向左 ◀
@export var direction: int = -1


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""
	custom_minimum_size = Vector2(52, 52)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 背景透明：箭头由 _draw 直接绘制
	var style := StyleBoxEmpty.new()
	for s_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s_name, style)
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := Color(0.9, 0.78, 0.45, 1.0)
	var cx := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.5
	var h := r.size.y * 0.3
	var w := r.size.x * 0.28
	var pts := PackedVector2Array()
	if direction == 0:
		pts = [Vector2(cx - w, cy - h), Vector2(cx - w, cy + h), Vector2(cx + w, cy)]
	else:
		pts = [Vector2(cx + w, cy - h), Vector2(cx + w, cy + h), Vector2(cx - w, cy)]
	draw_colored_polygon(pts, col)
