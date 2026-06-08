extends Control
class_name LevelOverlay

var battle
var stage_intro: Dictionary = {}
var clear_flash: Dictionary = {}
var fail_intro: Dictionary = {}
var show_complete := false

var _intro_callback: Callable
var _fail_retry_button: Button
var _fail_back_button: Button
var _fail_actions_box: HBoxContainer
var _fail_on_retry: Callable
var _fail_on_back: Callable


func setup(battle_node) -> void:
	battle = battle_node
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	size = Vector2(w, h)
	_build_fail_action_buttons()


func start_stage_intro(level_num: int, boss_name: String, on_complete: Callable) -> void:
	var slide_in := float(GameConfig.get_tuning("stage_intro_slide_in", 0.38))
	var hold := float(GameConfig.get_tuning("stage_intro_hold", 0.85))
	var slide_out := float(GameConfig.get_tuning("stage_intro_slide_out", 0.38))
	stage_intro = {
		"level_num": level_num,
		"boss_name": boss_name,
		"phase": "slide_in",
		"timer": slide_in,
		"slide_in_dur": slide_in,
		"hold_dur": hold,
		"slide_out_dur": slide_out,
	}
	_intro_callback = on_complete
	queue_redraw()


func show_clear_flash(on_mid: Callable) -> void:
	var dur := float(GameConfig.get_tuning("stage_clear_flash_duration", 1.1))
	clear_flash = {
		"timer": dur,
		"duration": dur,
		"on_mid": on_mid,
		"mid_done": false,
	}
	queue_redraw()


func show_fail_intro(on_retry: Callable, on_back: Callable, initial_overlay_alpha: float = -1.0) -> void:
	var alpha := initial_overlay_alpha
	if alpha < 0.0:
		var dim_alpha := float(GameConfig.get_tuning("fail_death_dim_alpha", 0.55))
		alpha = clampf(dim_alpha / 0.72, 0.0, 1.0)
	fail_intro = {
		"overlay_alpha": alpha,
		"actions_shown": alpha >= 0.55,
	}
	_fail_on_retry = on_retry
	_fail_on_back = on_back
	_set_fail_actions_visible(alpha >= 0.55)
	queue_redraw()


func show_game_complete() -> void:
	show_complete = true
	_set_fail_actions_visible(false)
	queue_redraw()


func clear_stage_intro() -> void:
	stage_intro.clear()
	queue_redraw()


func reset_all() -> void:
	stage_intro.clear()
	clear_flash.clear()
	fail_intro.clear()
	show_complete = false
	_set_fail_actions_visible(false)
	queue_redraw()


func is_stage_intro_active() -> bool:
	return not stage_intro.is_empty()


func is_fail_intro_active() -> bool:
	return not fail_intro.is_empty()


func update_overlay(delta: float) -> void:
	if not stage_intro.is_empty():
		_update_stage_intro(delta)
	if not clear_flash.is_empty():
		_update_clear_flash(delta)
	if not fail_intro.is_empty():
		_update_fail_intro(delta)
	if not stage_intro.is_empty() or not clear_flash.is_empty() or not fail_intro.is_empty() or show_complete:
		queue_redraw()


func _update_stage_intro(delta: float) -> void:
	if stage_intro.is_empty():
		return
	stage_intro["timer"] = float(stage_intro.get("timer", 0.0)) - delta
	if float(stage_intro.get("timer", 0.0)) > 0.0:
		return
	match str(stage_intro.get("phase", "")):
		"slide_in":
			stage_intro["phase"] = "hold"
			stage_intro["timer"] = float(stage_intro.get("hold_dur", 0.85))
		"hold":
			stage_intro["phase"] = "slide_out"
			stage_intro["timer"] = float(stage_intro.get("slide_out_dur", 0.38))
		_:
			stage_intro.clear()
			if _intro_callback.is_valid():
				_intro_callback.call()


func _update_clear_flash(delta: float) -> void:
	if clear_flash.is_empty():
		return
	clear_flash["timer"] = float(clear_flash.get("timer", 0.0)) - delta
	var duration := float(clear_flash.get("duration", 1.0))
	var elapsed := duration - float(clear_flash.get("timer", 0.0))
	if not bool(clear_flash.get("mid_done", false)) and elapsed >= duration * 0.45:
		clear_flash["mid_done"] = true
		var cb: Callable = clear_flash.get("on_mid", Callable())
		if cb.is_valid():
			cb.call()
		if clear_flash.is_empty():
			return
	if float(clear_flash.get("timer", 0.0)) <= 0.0:
		clear_flash.clear()


func _update_fail_intro(delta: float) -> void:
	if fail_intro.is_empty():
		return
	var fade_dur := maxf(0.001, float(GameConfig.get_tuning("stage_fail_overlay_fade", 0.65)))
	fail_intro["overlay_alpha"] = minf(1.0, float(fail_intro.get("overlay_alpha", 0.0)) + delta / fade_dur)
	if float(fail_intro.get("overlay_alpha", 0.0)) >= 0.55 and not bool(fail_intro.get("actions_shown", false)):
		fail_intro["actions_shown"] = true
		_set_fail_actions_visible(true)


func _draw() -> void:
	var w := size.x if size.x > 0 else float(GameConfig.get_tuning("logical_width", 720))
	var h := size.y if size.y > 0 else float(GameConfig.get_tuning("logical_height", 1280))
	var cx := w * 0.5
	if not stage_intro.is_empty():
		_draw_stage_intro(cx, w, h)
	if not clear_flash.is_empty():
		_draw_clear_flash(cx, h * 0.5)
	if not fail_intro.is_empty():
		_draw_fail_overlay(w, h)
	if show_complete:
		_draw_complete(w, h)


func _draw_stage_intro(cx: float, w: float, h: float) -> void:
	var intro := stage_intro
	var label_y := h * 0.22
	var off_screen := w * 0.42
	var text_x := cx
	match str(intro.get("phase", "")):
		"slide_in":
			var t := 1.0 - clampf(float(intro.get("timer", 0.0)) / float(intro.get("slide_in_dur", 0.38)), 0.0, 1.0)
			text_x = lerpf(-off_screen, cx, t * t)
		"slide_out":
			var t := 1.0 - clampf(float(intro.get("timer", 0.0)) / float(intro.get("slide_out_dur", 0.38)), 0.0, 1.0)
			text_x = lerpf(cx, w + off_screen, t * t)
	var text := "第%d关" % int(intro.get("level_num", 1))
	_draw_pixel_text(text, Vector2(text_x, label_y), 26, Color.BLACK)
	var boss_name := str(intro.get("boss_name", ""))
	if not boss_name.is_empty():
		_draw_pixel_text(boss_name, Vector2(text_x, label_y + 30.0), 14, Color.BLACK)


func _draw_clear_flash(cx: float, cy: float) -> void:
	if clear_flash.is_empty():
		return
	var alpha := clampf(float(clear_flash.get("timer", 0.0)) / float(clear_flash.get("duration", 1.0)), 0.0, 1.0)
	_draw_pixel_text("关卡通过", Vector2(cx, cy), 30, Color("#ffd8a0"), alpha)


func _draw_fail_overlay(w: float, h: float) -> void:
	var overlay_a := float(fail_intro.get("overlay_alpha", 0.0))
	if overlay_a <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0, 0, 0, 0.72 * overlay_a))
	var msg_a := clampf(overlay_a / 0.65, 0.0, 1.0)
	_draw_pixel_text("体力耗尽", Vector2(w * 0.5, h * 0.42), 26, Color("#ff9c84"), msg_a)
	_draw_pixel_text("请选择操作", Vector2(w * 0.5, h * 0.42 + 38.0), 16, Color("#f4e8da"), msg_a)


func _draw_complete(w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0, 0, 0, 0.72))
	_draw_pixel_text("你完成了全部关卡", Vector2(w * 0.5, h * 0.44), 26, Color("#ffd8a0"))
	_draw_pixel_text("点击屏幕重新开始", Vector2(w * 0.5, h * 0.58), 16, Color("#f4e8da"))


func _draw_pixel_text(text: String, pos: Vector2, font_size: int, color: Color, alpha: float = 1.0) -> void:
	var font := PixelUiHelper.get_ui_font()
	var c := color
	c.a *= alpha
	draw_string(font, pos - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)


func _build_fail_action_buttons() -> void:
	if _fail_actions_box != null:
		return
	_fail_actions_box = HBoxContainer.new()
	_fail_actions_box.visible = false
	_fail_actions_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_fail_actions_box.anchor_left = 0.5
	_fail_actions_box.anchor_right = 0.5
	_fail_actions_box.anchor_top = 0.64
	_fail_actions_box.anchor_bottom = 0.64
	_fail_actions_box.offset_left = -190.0
	_fail_actions_box.offset_right = 190.0
	_fail_actions_box.offset_top = 0.0
	_fail_actions_box.offset_bottom = 56.0
	_fail_actions_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_fail_actions_box.add_theme_constant_override("separation", 16)
	add_child(_fail_actions_box)

	_fail_retry_button = Button.new()
	_fail_retry_button.text = "重来"
	_fail_retry_button.custom_minimum_size = Vector2(170, 54)
	_fail_retry_button.pressed.connect(_on_fail_retry_pressed)
	_fail_actions_box.add_child(_fail_retry_button)

	_fail_back_button = Button.new()
	_fail_back_button.text = "回到主界面"
	_fail_back_button.custom_minimum_size = Vector2(170, 54)
	_fail_back_button.pressed.connect(_on_fail_back_pressed)
	_fail_actions_box.add_child(_fail_back_button)

	PixelUiHelper.apply_ui_font_tree(_fail_actions_box)


func _set_fail_actions_visible(visible: bool) -> void:
	if _fail_actions_box == null:
		return
	_fail_actions_box.visible = visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE


func has_active_fail_actions() -> bool:
	return _fail_actions_box != null and _fail_actions_box.visible


func _on_fail_retry_pressed() -> void:
	_set_fail_actions_visible(false)
	if _fail_on_retry.is_valid():
		_fail_on_retry.call()


func _on_fail_back_pressed() -> void:
	_set_fail_actions_visible(false)
	if _fail_on_back.is_valid():
		_fail_on_back.call()
