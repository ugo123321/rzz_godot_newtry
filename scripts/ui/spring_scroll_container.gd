extends ScrollContainer
class_name SpringScrollContainer

@export var max_overscroll := 72.0
@export var return_speed := 16.0
@export var drag_resistance := 0.42
@export var drag_start_threshold := 8.0

var _content: Control
var _overscroll_y := 0.0
var _pointer_down := false
var _drag_scrolling := false
var _suppress_click := false
var _press_start := Vector2.ZERO
var _active_pointer := -1


func _ready() -> void:
	process_priority = 1
	set_process_input(true)
	scroll_deadzone = 0
	vertical_scroll_mode = SCROLL_MODE_SHOW_NEVER
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	if get_child_count() > 0:
		_content = get_child(0) as Control


func is_drag_scrolling() -> bool:
	return _drag_scrolling


func was_scroll_gesture() -> bool:
	return _suppress_click


func _input(event: InputEvent) -> void:
	if not _is_pointer_inside(event):
		if _pointer_down and _is_release_event(event):
			_end_pointer()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position, -1)
		else:
			_end_pointer()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position, event.index)
		elif event.index == _active_pointer:
			_end_pointer()
		return

	if event is InputEventMouseMotion and _pointer_down:
		_handle_pointer_move(event.position, event.relative.y)
	elif event is InputEventScreenDrag and event.index == _active_pointer:
		_handle_pointer_move(event.position, event.relative.y)


func _begin_pointer(pos: Vector2, pointer_index: int) -> void:
	_pointer_down = true
	_drag_scrolling = false
	_suppress_click = false
	_press_start = pos
	_active_pointer = pointer_index


func _end_pointer() -> void:
	if _drag_scrolling:
		_suppress_click = true
	_pointer_down = false
	_active_pointer = -1
	_drag_scrolling = false
	_start_return()
	if _suppress_click:
		get_viewport().set_input_as_handled()


func _handle_pointer_move(pos: Vector2, delta_y: float) -> void:
	if not _drag_scrolling and _press_start.distance_to(pos) >= drag_start_threshold:
		_drag_scrolling = true
	if not _drag_scrolling:
		return
	_apply_drag_delta(delta_y)
	get_viewport().set_input_as_handled()


func _apply_drag_delta(delta_y: float) -> void:
	var max_scroll := _get_max_scroll()
	var next_scroll := scroll_vertical - delta_y
	if next_scroll < 0.0:
		scroll_vertical = 0.0
		_overscroll_y = clampf(_overscroll_y - next_scroll * drag_resistance, 0.0, max_overscroll)
	elif next_scroll > max_scroll:
		scroll_vertical = max_scroll
		var overflow := next_scroll - max_scroll
		_overscroll_y = clampf(_overscroll_y - overflow * drag_resistance, -max_overscroll, 0.0)
	else:
		scroll_vertical = next_scroll
		if absf(_overscroll_y) > 0.01:
			_overscroll_y = move_toward(_overscroll_y, 0.0, absf(delta_y) * drag_resistance)
	_sync_content_offset()


func _start_return() -> void:
	if absf(_overscroll_y) < 0.5:
		_overscroll_y = 0.0
		_sync_content_offset()


func _process(delta: float) -> void:
	if not _pointer_down and absf(_overscroll_y) > 0.01:
		var step := return_speed * maxf(absf(_overscroll_y), 10.0) * delta
		_overscroll_y = move_toward(_overscroll_y, 0.0, step)
	_sync_content_offset()


func _sync_content_offset() -> void:
	if _content == null:
		return
	_content.position.y = -scroll_vertical + _overscroll_y


func _get_max_scroll() -> float:
	if _content == null:
		return 0.0
	return maxf(0.0, _content.size.y - size.y)


func _is_pointer_inside(event: InputEvent) -> bool:
	var pos := _event_position(event)
	if pos.x < 0.0:
		return false
	return get_global_rect().has_point(pos)


func _event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).global_position
	return Vector2(-1.0, -1.0)


func _is_release_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return not (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return false
