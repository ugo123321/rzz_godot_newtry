extends Button
class_name LobbyArrowButton

@export var direction: int = -1


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""
	custom_minimum_size = Vector2(52, 52)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := LobbyStyle.make_arrow_button_style()
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	resized.connect(queue_redraw)


func _draw() -> void:
	LobbyStyle.draw_arrow(self, Rect2(Vector2.ZERO, size), direction)
