extends Control
class_name RewardWheelPopup

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const SLOT_COUNT := 6
const SLOT_ANGLE := TAU / float(SLOT_COUNT)
const SPIN_DURATION := 2.7
const RESULT_HOLD_TIME := 1.25
const WHEEL_RADIUS := 124.0

signal reward_finished(reward_text: String)

var battle: BattleController
var _entries: Array[Dictionary] = []
var _result_timer := 0.0
var _selected_index := -1
var _spinning := false

var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _tip_label: Label
var _wheel_wrap: Control
var _wheel: Control
var _pointer_overlay: Control
var _spin_btn: Button
var _slot_nodes: Array[Control] = []


func setup(battle_node: BattleController) -> void:
	battle = battle_node
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_entries()
	_build_ui()
	resized.connect(_on_root_resized)


func show_for_stage(stage_index: int) -> void:
	_selected_index = -1
	_result_timer = 0.0
	_spinning = false
	_tip_label.text = "点击抽奖按钮，随机获得一个奖励"
	_title_label.text = "第%d关 奖励关 · 转盘房" % (stage_index + 1)
	_wheel.rotation = 0.0
	_spin_btn.disabled = false
	_spin_btn.text = "抽 奖"
	_sync_root_size()
	_relayout_panel()
	call_deferred("_layout_wheel_area")
	visible = true
	move_to_front()
	queue_redraw()
	if _wheel_wrap:
		_wheel_wrap.queue_redraw()
	if _pointer_overlay:
		_pointer_overlay.queue_redraw()


func _build_entries() -> void:
	_entries = [
		{
			"id": "exp30_a",
			"display": "30%经验",
			"icon": "res://assets/icons/reward_wheel/icon_reward_exp30.svg",
		},
		{
			"id": "exp60",
			"display": "60%经验",
			"icon": "res://assets/icons/reward_wheel/icon_reward_exp60.svg",
		},
		{
			"id": "exp30_b",
			"display": "30%经验",
			"icon": "res://assets/icons/reward_wheel/icon_reward_exp30_b.svg",
		},
		{
			"id": "legendary",
			"display": "传奇奖励",
			"icon": "res://assets/icons/reward_wheel/icon_reward_legendary.svg",
		},
		{
			"id": "heal100",
			"display": "恢复100%血量",
			"icon": "res://assets/icons/reward_wheel/icon_reward_heal100.svg",
		},
		{
			"id": "heal30",
			"display": "恢复30%血量",
			"icon": "res://assets/icons/reward_wheel/icon_reward_heal30.svg",
		},
	]


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.76)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(350, 520)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#2c2330")
	panel_style.border_color = Color("#d8c080")
	panel_style.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_panel.add_child(root)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text = "奖励关 · 转盘房"
	_title_label.add_theme_font_size_override("font_size", 16)
	root.add_child(_title_label)

	_wheel_wrap = Control.new()
	_wheel_wrap.custom_minimum_size = Vector2(320, 360)
	_wheel_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wheel_wrap.clip_contents = false
	_wheel_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_wheel_wrap)

	_wheel = Control.new()
	_wheel.custom_minimum_size = Vector2(300, 300)
	_wheel.size = Vector2(300, 300)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.pivot_offset = _wheel.size * 0.5
	_wheel.draw.connect(_draw_wheel)
	_wheel_wrap.add_child(_wheel)

	_build_slots()

	_pointer_overlay = Control.new()
	_pointer_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer_overlay.draw.connect(_draw_wheel_pointer)
	_wheel_wrap.add_child(_pointer_overlay)
	_wheel_wrap.resized.connect(_on_wheel_wrap_resized)

	_tip_label = Label.new()
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.text = ""
	_tip_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_tip_label)

	_spin_btn = Button.new()
	_spin_btn.text = "抽 奖"
	_spin_btn.custom_minimum_size = Vector2(0, 42)
	_spin_btn.pressed.connect(_on_spin_pressed)
	root.add_child(_spin_btn)

	PixelUi.apply_ui_font_tree(self)
	_sync_root_size()
	_relayout_panel()
	_layout_wheel_area()


func _build_slots() -> void:
	for child in _wheel.get_children():
		child.queue_free()
	_slot_nodes.clear()
	for i in range(_entries.size()):
		var slot := VBoxContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size = Vector2(86, 66)
		slot.size = slot.custom_minimum_size

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var icon_path := str(_entries[i].get("icon", ""))
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path) as Texture2D
		slot.add_child(icon)

		var text := Label.new()
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.text = str(_entries[i].get("display", ""))
		text.add_theme_font_size_override("font_size", 10)
		slot.add_child(text)

		PixelUi.apply_ui_font_tree(slot)
		_wheel.add_child(slot)
		_slot_nodes.append(slot)

	_layout_slots()


func _layout_slots() -> void:
	var center := _wheel.size * 0.5
	var ring_r := WHEEL_RADIUS * 0.67
	for i in range(_slot_nodes.size()):
		var node := _slot_nodes[i]
		var ang := -PI * 0.5 + SLOT_ANGLE * float(i)
		var pos := center + Vector2(cos(ang), sin(ang)) * ring_r
		node.position = pos - node.size * 0.5


func _draw_wheel() -> void:
	var c := _wheel.size * 0.5
	for i in range(SLOT_COUNT):
		var a0 := -PI * 0.5 + float(i) * SLOT_ANGLE - SLOT_ANGLE * 0.5
		var a1 := a0 + SLOT_ANGLE
		var color := Color("#5a3f58") if i % 2 == 0 else Color("#4b334a")
		_draw_fan(_wheel, c, WHEEL_RADIUS, a0, a1, color)
		_draw_fan(_wheel, c, WHEEL_RADIUS * 0.22, a0, a1, Color("#382c3d"))
		var edge := c + Vector2(cos(a0), sin(a0)) * WHEEL_RADIUS
		_wheel.draw_line(c, edge, Color("#2a1f2f"), 2.0)
	_wheel.draw_arc(c, WHEEL_RADIUS, 0.0, TAU, 64, Color("#e8d088"), 6.0)
	_wheel.draw_arc(c, WHEEL_RADIUS - 8.0, 0.0, TAU, 64, Color("#241a28"), 2.0)
	_wheel.draw_circle(c, WHEEL_RADIUS * 0.18, Color("#d9b86f"))
	_wheel.draw_circle(c, WHEEL_RADIUS * 0.1, Color("#332533"))


func _draw_wheel_pointer() -> void:
	if _wheel == null or _pointer_overlay == null:
		return
	var wheel_size := _wheel.size
	var wheel_center := _wheel.position + wheel_size * 0.5
	var cx := wheel_center.x
	var rim_top := wheel_center.y - WHEEL_RADIUS
	var tip_y := rim_top + 16.0
	var base_y := rim_top - 20.0
	var half_w := 17.0
	var poly := PackedVector2Array([
		Vector2(cx - half_w, base_y),
		Vector2(cx + half_w, base_y),
		Vector2(cx, tip_y),
	])
	_pointer_overlay.draw_colored_polygon(
		PackedVector2Array([
			Vector2(cx - half_w, base_y + 3.0),
			Vector2(cx + half_w, base_y + 3.0),
			Vector2(cx, tip_y + 3.0),
		]),
		Color("#1a1218")
	)
	_pointer_overlay.draw_colored_polygon(poly, Color("#ffd060"))
	_pointer_overlay.draw_polyline(poly, Color("#3a2830"), 2.0, true)
	_pointer_overlay.draw_rect(Rect2(cx - 4.0, base_y - 12.0, 8.0, 12.0), Color("#ffd060"))
	_pointer_overlay.draw_rect(Rect2(cx - 4.0, base_y - 12.0, 8.0, 2.0), Color("#3a2830"))


func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	size = vp


func _relayout_panel() -> void:
	if _panel == null:
		return
	var panel_size := _panel.custom_minimum_size
	var center := size * 0.5
	_panel.position = center - panel_size * 0.5
	_panel.size = panel_size
	_layout_wheel_area()


func _on_root_resized() -> void:
	_relayout_panel()


func _layout_wheel_area() -> void:
	if _wheel_wrap == null or _wheel == null:
		return
	var wrap_size := _wheel_wrap.size
	if wrap_size.x <= 0.0 or wrap_size.y <= 0.0:
		return
	var wheel_size := _wheel.size
	_wheel.position = Vector2(
		(wrap_size.x - wheel_size.x) * 0.5,
		(wrap_size.y - wheel_size.y) * 0.5
	)
	if _pointer_overlay:
		_pointer_overlay.size = wrap_size
		_pointer_overlay.position = Vector2.ZERO
		_pointer_overlay.queue_redraw()
	_layout_slots()


func _on_wheel_wrap_resized() -> void:
	_layout_wheel_area()


func _draw_fan(canvas: CanvasItem, center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color) -> void:
	var steps := 12
	var pts := PackedVector2Array()
	pts.append(center)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := lerpf(from_angle, to_angle, t)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	canvas.draw_colored_polygon(pts, color)


func _on_spin_pressed() -> void:
	if _spinning:
		return
	if _entries.is_empty():
		return
	_spinning = true
	_spin_btn.disabled = true
	_spin_btn.text = "抽奖中..."
	_tip_label.text = "转盘旋转中..."
	_selected_index = randi() % _entries.size()

	var desired_mod := -float(_selected_index) * SLOT_ANGLE
	var current := _wheel.rotation
	var align_delta := fposmod(desired_mod - current, TAU)
	var target := current + TAU * (4.5 + randf() * 1.1) + align_delta

	var tween := create_tween()
	tween.tween_property(_wheel, "rotation", target, SPIN_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_spin_finished)


func _on_spin_finished() -> void:
	_spinning = false
	_apply_reward()


func _apply_reward() -> void:
	if _selected_index < 0 or _selected_index >= _entries.size():
		_finish_with_reward("无奖励")
		return
	var entry := _entries[_selected_index]
	var reward_id := str(entry.get("id", ""))
	var reward_text := str(entry.get("display", ""))

	match reward_id:
		"exp30_a", "exp30_b":
			_grant_exp_ratio(0.30)
		"exp60":
			_grant_exp_ratio(0.60)
		"legendary":
			if battle and battle.player:
				battle.player.grant_force_legendary_upgrade()
			if battle and battle.experience:
				battle.experience.pending_level_ups += 1
		"heal100":
			if battle and battle.player:
				battle.player.heal_percent(1.0)
		"heal30":
			if battle and battle.player:
				battle.player.heal_percent(0.3)

	_finish_with_reward(reward_text)


func _grant_exp_ratio(ratio: float) -> void:
	if battle == null or battle.experience == null:
		return
	var max_exp := int(battle.experience.exp_to_next)
	var gain := int(round(float(max_exp) * ratio))
	battle.experience.add_exp(maxi(1, gain))


func _finish_with_reward(reward_text: String) -> void:
	_tip_label.text = "获得奖励：%s" % reward_text
	_result_timer = RESULT_HOLD_TIME


func _process(delta: float) -> void:
	if not visible:
		return
	if _result_timer > 0.0:
		_result_timer = maxf(0.0, _result_timer - delta)
		if _result_timer <= 0.0:
			var text := ""
			if _selected_index >= 0 and _selected_index < _entries.size():
				text = str(_entries[_selected_index].get("display", ""))
			visible = false
			reward_finished.emit(text)
