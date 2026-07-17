extends Control
class_name TalentDetailPopup

# 点击已获得卡片弹出的详情放大 popup（参考 3.jpg）：
# - 全屏 dim（较轻，主界面仍可见）
# - 中央大卡（放大版 TalentCardSlot）
# - 左右三角箭头按钮切换上一/下一张已获得卡
# - 卡片下方描述文字（当前等级效果）
# - 底部关闭提示；点击非卡片非按钮区域关闭

signal closed()

const TalentCardSlotT = preload("res://scenes/ui/talent_card_slot.tscn")

const CARD_SIZE := Vector2(300.0, 400.0)
const HIDE_DURATION := 0.15

var _owned_ids: Array[String] = []
var _index: int = 0
var _overlay: ColorRect
var _card: Control
var _desc_label: Label
var _hint_label: Label
var _prev_btn: Button
var _next_btn: Button
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_for_index(owned_ids: Array, start_id: String) -> void:
	_owned_ids.clear()
	for tid in owned_ids:
		_owned_ids.append(str(tid))
	_index = _owned_ids.find(start_id)
	if _index < 0:
		_index = 0
	_build_ui()
	_refresh_card()
	modulate = Color(1, 1, 1, 0.0)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.15)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# overlay 上的点击 → 关闭（要用 gui_input，见 _overlay_gui_input）
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	_card = TalentCardSlotT.instantiate()
	_card.slot_size = CARD_SIZE
	_card.custom_minimum_size = CARD_SIZE
	_card.size = CARD_SIZE
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.interactive = false
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.anchor_right = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -CARD_SIZE.x * 0.5
	_card.offset_top = -CARD_SIZE.y * 0.5 - 30.0
	_card.offset_right = CARD_SIZE.x * 0.5
	_card.offset_bottom = CARD_SIZE.y * 0.5 - 30.0
	add_child(_card)

	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_size_override("font_size", 22)
	_desc_label.add_theme_color_override("font_color", Color("#ffffff"))
	_desc_label.add_theme_color_override("font_outline_color", Color("#141824"))
	_desc_label.add_theme_constant_override("outline_size", 5)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.anchor_left = 0.0
	_desc_label.anchor_right = 1.0
	_desc_label.anchor_top = 0.5
	_desc_label.anchor_bottom = 0.5
	_desc_label.offset_top = CARD_SIZE.y * 0.5 - 20.0
	_desc_label.offset_bottom = CARD_SIZE.y * 0.5 + 40.0
	add_child(_desc_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -60.0
	_hint_label.offset_bottom = -30.0
	_hint_label.text = LanguageManager.tr_ui("UI_TALENT_CLOSE_HINT")
	add_child(_hint_label)
	_start_hint_breathing()


func _start_hint_breathing() -> void:
	if _hint_label == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_hint_label, "modulate:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hint_label, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 左右箭头（自绘三角）
	_prev_btn = _make_arrow_button(false)
	_prev_btn.pressed.connect(_on_prev)
	add_child(_prev_btn)
	_next_btn = _make_arrow_button(true)
	_next_btn.pressed.connect(_on_next)
	add_child(_next_btn)


func _make_arrow_button(is_next: bool) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(64, 64)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.text = ""
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_top = -32.0
	btn.offset_bottom = 32.0
	if is_next:
		btn.anchor_left = 0.5
		btn.anchor_right = 0.5
		btn.offset_left = CARD_SIZE.x * 0.5 + 20.0
		btn.offset_right = CARD_SIZE.x * 0.5 + 84.0
	else:
		btn.anchor_left = 0.5
		btn.anchor_right = 0.5
		btn.offset_left = -CARD_SIZE.x * 0.5 - 84.0
		btn.offset_right = -CARD_SIZE.x * 0.5 - 20.0
	# 用自定义 Control 覆盖箭头图形
	var arrow := _ArrowDrawer.new()
	arrow.is_next = is_next
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(arrow)
	return btn


class _ArrowDrawer extends Control:
	var is_next: bool = true
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# 圆形底
		var center := Vector2(w * 0.5, h * 0.5)
		var r := minf(w, h) * 0.45
		draw_circle(center, r, Color(1, 1, 1, 0.85))
		draw_arc(center, r, 0.0, TAU, 24, Color(0.1, 0.1, 0.15, 0.9), 2.0)
		# 三角
		var tri: PackedVector2Array = []
		var tr := r * 0.55
		if is_next:
			tri.append(center + Vector2(tr * 0.6, 0))
			tri.append(center + Vector2(-tr * 0.4, -tr * 0.7))
			tri.append(center + Vector2(-tr * 0.4, tr * 0.7))
		else:
			tri.append(center + Vector2(-tr * 0.6, 0))
			tri.append(center + Vector2(tr * 0.4, -tr * 0.7))
			tri.append(center + Vector2(tr * 0.4, tr * 0.7))
		draw_colored_polygon(tri, Color(0.15, 0.18, 0.28, 0.95))


func _refresh_card() -> void:
	if _owned_ids.is_empty():
		_close()
		return
	_index = clampi(_index, 0, _owned_ids.size() - 1)
	var tid := _owned_ids[_index]
	var def := LobbyState.get_talent_def(tid)
	var lv := LobbyState.get_talent_level(tid)
	_card.set_data(def, lv)
	# 描述用"累计值"文案：get_talent_desc_at_level 直接把模板 {vN} 替换成 lv 缩放后的显示值
	# 只显示纯 desc，不加 LV/满级前缀（等级已经在卡片顶部标签显示）
	_desc_label.text = LobbyState.get_talent_desc_at_level(def, lv)
	_prev_btn.disabled = _owned_ids.size() <= 1
	_next_btn.disabled = _owned_ids.size() <= 1
	# 切换动画：整卡短暂闪一下
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.94, 0.94)
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)


func _on_prev() -> void:
	if _owned_ids.size() <= 1:
		return
	_index = (_index - 1 + _owned_ids.size()) % _owned_ids.size()
	_refresh_card()


func _on_next() -> void:
	if _owned_ids.size() <= 1:
		return
	_index = (_index + 1) % _owned_ids.size()
	_refresh_card()


func _on_overlay_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.0), HIDE_DURATION)
	tw.tween_callback(func():
		closed.emit()
		queue_free()
	)
