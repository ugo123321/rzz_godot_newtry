extends Control
class_name ScoutRewardPopup

# 侦察挂机收益 popup（会话内累计金币）
# - 全脚本构建，不依赖 .tscn
# - 由 main_menu.gd 用 ScoutRewardPopup.new() + add_child 挂到主菜单
# - 领取按钮把 LobbyState.get_scout_pending_gold() 加到金币；无冷却，可反复领
# - 参考 UI：cankao/11.jpg（主题 = 侦察收益 / 已侦察 hh:mm:ss / 187 每小时 / 领取按钮）

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const PANEL_MARGIN := 48.0
const PANEL_MIN_SIZE := Vector2(420.0, 560.0)
const REFRESH_INTERVAL := 1.0
const CLAIMED_FLOAT_DURATION := 1.2

var _overlay: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _elapsed_label: Label
var _hourly_icon: TextureRect
var _hourly_label: Label
var _item_slot: PanelContainer
var _item_empty_label: Label
var _hint_label: Label
var _claim_button: Button
var _close_hint_label: Label
var _claimed_float_label: Label

var _refresh_accum := 0.0
var _claimed_float_time := 0.0


func setup() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	resized.connect(_on_root_resized)
	if EventBus and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)


func _build_ui() -> void:
	# 半透明遮罩 —— 点击关闭
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := UiStyle.make_dialog_stylebox(Color.WHITE, 24)
	if panel_style != null:
		_panel.add_theme_stylebox_override("panel", panel_style)
		_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(_vbox)

	# 标题
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_title_label)
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", Color("#3b2612"))
	_vbox.add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_subtitle_label)
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color("#7a5a2a"))
	_vbox.add_child(_subtitle_label)

	# 已侦察时长
	_elapsed_label = Label.new()
	_elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_elapsed_label)
	_elapsed_label.add_theme_font_size_override("font_size", 24)
	_elapsed_label.add_theme_color_override("font_color", Color("#2c1c0a"))
	_vbox.add_child(_elapsed_label)

	# 每小时产量（金币图标 + 数字）
	var hourly_row := HBoxContainer.new()
	hourly_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hourly_row.add_theme_constant_override("separation", 10)
	_vbox.add_child(hourly_row)

	_hourly_icon = TextureRect.new()
	_hourly_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hourly_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hourly_icon.custom_minimum_size = Vector2(36, 36)
	_hourly_icon.texture = load("res://assets/ui/icons/currency/icon_cur_gold.png") as Texture2D
	_hourly_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hourly_row.add_child(_hourly_icon)

	_hourly_label = Label.new()
	_hourly_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_hourly_label)
	_hourly_label.add_theme_font_size_override("font_size", 22)
	_hourly_label.add_theme_color_override("font_color", Color("#2c1c0a"))
	hourly_row.add_child(_hourly_label)

	# 道具栏（暂未获得任何道具）
	_item_slot = PanelContainer.new()
	_item_slot.custom_minimum_size = Vector2(0, 200)
	_item_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot_style := UiStyle.make_tooltip_stylebox(Color(0.92, 0.83, 0.62, 1.0), 16)
	if slot_style != null:
		_item_slot.add_theme_stylebox_override("panel", slot_style)
	else:
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0.88, 0.76, 0.5, 1.0)
		fb.set_corner_radius_all(10)
		fb.set_content_margin_all(16.0)
		_item_slot.add_theme_stylebox_override("panel", fb)
	_vbox.add_child(_item_slot)

	var item_center := CenterContainer.new()
	item_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_slot.add_child(item_center)

	_item_empty_label = Label.new()
	_item_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_item_empty_label)
	_item_empty_label.add_theme_font_size_override("font_size", 22)
	_item_empty_label.add_theme_color_override("font_color", Color("#7a5a2a"))
	item_center.add_child(_item_empty_label)

	# 提示：章节越高，收益越大
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_hint_label)
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color("#8a5518"))
	_vbox.add_child(_hint_label)

	# 领取按钮
	var claim_row := CenterContainer.new()
	claim_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(claim_row)

	_claim_button = Button.new()
	_claim_button.custom_minimum_size = Vector2(220, 60)
	PixelUi.apply_ui_font(_claim_button)
	_claim_button.add_theme_font_size_override("font_size", 26)
	UiStyle.apply_primary_button(_claim_button, Color("#efb840"), 12)
	_claim_button.add_theme_color_override("font_color", Color("#3b2612"))
	_claim_button.pressed.connect(_on_claim_pressed)
	claim_row.add_child(_claim_button)

	# 关闭提示：点击空白处
	_close_hint_label = Label.new()
	_close_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_close_hint_label)
	_close_hint_label.add_theme_font_size_override("font_size", 16)
	_close_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	# 放到 overlay 层的底部 —— 与主面板同级
	add_child(_close_hint_label)
	_close_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_close_hint_label.offset_top = -60
	_close_hint_label.offset_bottom = -20
	_close_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 飘字（领取后 "+g 金币" 上浮淡出）
	_claimed_float_label = Label.new()
	_claimed_float_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_claimed_float_label)
	_claimed_float_label.add_theme_font_size_override("font_size", 28)
	_claimed_float_label.add_theme_color_override("font_color", Color("#f6c04d"))
	_claimed_float_label.add_theme_color_override("font_outline_color", Color("#3b2612"))
	_claimed_float_label.add_theme_constant_override("outline_size", 4)
	_claimed_float_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claimed_float_label.visible = false
	add_child(_claimed_float_label)

	_apply_texts()


func show_popup() -> void:
	_sync_root_size()
	_apply_texts()
	_refresh_dynamic_labels()
	_relayout_panel()
	visible = true
	move_to_front()
	_refresh_accum = 0.0


func hide_popup() -> void:
	visible = false


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_popup()


func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		size = vp


func _relayout_panel() -> void:
	if _panel == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	var panel_size := Vector2(
		clampf(vp.x - PANEL_MARGIN * 2.0, PANEL_MIN_SIZE.x, vp.x),
		clampf(vp.y * 0.70, PANEL_MIN_SIZE.y, vp.y - PANEL_MARGIN * 2.0)
	)
	var center := vp * 0.5
	_panel.position = center - panel_size * 0.5
	_panel.size = panel_size


func _on_root_resized() -> void:
	_sync_root_size()
	_relayout_panel()


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	_refresh_dynamic_labels()


func _apply_texts() -> void:
	if _title_label != null:
		_title_label.text = LanguageManager.tr_ui("UI_SCOUT_TITLE")
	if _subtitle_label != null:
		_subtitle_label.text = LanguageManager.tr_ui("UI_SCOUT_SUBTITLE")
	if _item_empty_label != null:
		_item_empty_label.text = LanguageManager.tr_ui("UI_SCOUT_ITEM_EMPTY")
	if _hint_label != null:
		_hint_label.text = LanguageManager.tr_ui("UI_SCOUT_HINT_HIGHER")
	if _close_hint_label != null:
		_close_hint_label.text = LanguageManager.tr_ui("UI_SCOUT_CLOSE_HINT")


func _refresh_dynamic_labels() -> void:
	if not is_instance_valid(LobbyState):
		return
	var elapsed := LobbyState.get_scout_accumulated_seconds()
	var hourly := LobbyState.get_scout_hourly_gold()
	var pending := LobbyState.get_scout_pending_gold()
	if _elapsed_label != null:
		_elapsed_label.text = "%s  %s" % [LanguageManager.tr_ui("UI_SCOUT_ELAPSED_LABEL"), _fmt_hms(elapsed)]
	if _hourly_label != null:
		_hourly_label.text = LanguageManager.tr_ui("UI_SCOUT_HOURLY_FMT") % hourly
	if _claim_button != null:
		if pending > 0:
			_claim_button.disabled = false
			_claim_button.text = LanguageManager.tr_ui("UI_SCOUT_CLAIM_BTN")
		else:
			_claim_button.disabled = true
			_claim_button.text = LanguageManager.tr_ui("UI_SCOUT_CLAIM_DISABLED")


func _on_claim_pressed() -> void:
	if not is_instance_valid(LobbyState):
		return
	var reward := LobbyState.claim_scout_reward()
	if reward <= 0:
		return
	_refresh_dynamic_labels()
	_show_claimed_float(reward)


func _show_claimed_float(reward: int) -> void:
	if _claimed_float_label == null:
		return
	_claimed_float_label.text = LanguageManager.tr_ui("UI_SCOUT_CLAIMED_FMT") % reward
	# 从领取按钮上方开始
	var start_pos := Vector2(size.x * 0.5, size.y * 0.5)
	if _claim_button != null:
		var rect := _claim_button.get_global_rect()
		start_pos = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 24.0)
	_claimed_float_label.position = start_pos - _claimed_float_label.size * 0.5
	_claimed_float_label.modulate.a = 1.0
	_claimed_float_label.visible = true
	_claimed_float_time = CLAIMED_FLOAT_DURATION


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_dynamic_labels()
	if _claimed_float_time > 0.0 and _claimed_float_label != null and _claimed_float_label.visible:
		_claimed_float_time -= delta
		var t := clampf(1.0 - _claimed_float_time / CLAIMED_FLOAT_DURATION, 0.0, 1.0)
		_claimed_float_label.position.y -= delta * 32.0
		_claimed_float_label.modulate.a = 1.0 - t
		if _claimed_float_time <= 0.0:
			_claimed_float_label.visible = false


static func _fmt_hms(secs: int) -> String:
	var s := maxi(0, secs)
	var h := s / 3600
	var m := (s / 60) % 60
	var sec := s % 60
	return "%02d:%02d:%02d" % [h, m, sec]
