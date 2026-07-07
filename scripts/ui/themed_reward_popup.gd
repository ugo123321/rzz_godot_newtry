extends Control
class_name ThemedRewardPopup

# 主题关（恶魔 / 天使）专属奖励 popup。
# - 完全 script-built（节点都在 _build_ui 里 add_child），不依赖 .tscn
# - 由 battle.gd 用 `ThemedRewardPopup.new()` 实例化 + add_child 到 $UI
# - 主题在 show_for_theme(theme) 切换：demon → 血红，angel → 浅黄圣光
# - 单卡 + 接受 / 放弃 二选一；选择后 emit reward_resolved(accepted, upgrade)

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const PixelCardIconT = preload("res://scripts/ui/pixel_card_icon.gd")
const DescFormatT = preload("res://scripts/utils/desc_format.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const PANEL_MARGIN := 36.0
const PANEL_MIN_SIZE := Vector2(360.0, 540.0)
const CARD_ICON_SIZE := 96.0
const SHOW_DURATION := 0.32
const HIDE_DURATION := 0.18

signal reward_resolved(accepted: bool, upgrade: Dictionary)

var battle: Node
var _theme := ""           # "demon" / "angel"
var _upgrade: Dictionary = {}
var _anim_time := 0.0
var _draw_timer := 0.0
var _active_tween: Tween = null
var _closing := false      # 渐出动画中（屏蔽按钮二次点击）

var _overlay: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _name_label: Label
var _desc_label: RichTextLabel
var _icon_widget: Control
var _accept_btn: Button
var _decline_btn: Button


func setup(battle_node: Node) -> void:
	battle = battle_node
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	resized.connect(_on_root_resized)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# 主面板：尺寸跟随 viewport（GameConfig.logical_size 决定），始终居中
	# 不用 PRESET_CENTER（只 anchor 不 size），改用 _relayout_panel 在 show 时手动放
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(_vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_title_label)
	_title_label.add_theme_font_size_override("font_size", 30)
	_vbox.add_child(_title_label)

	# 卡片视觉容器：icon + name + desc
	var card_box := VBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 10)
	_vbox.add_child(card_box)

	var icon_center := CenterContainer.new()
	icon_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.add_child(icon_center)
	_icon_widget = Control.new()
	_icon_widget.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
	icon_center.add_child(_icon_widget)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PixelUi.apply_ui_font(_name_label)
	_name_label.add_theme_font_size_override("font_size", 28)
	card_box.add_child(_name_label)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PixelUi.apply_ui_font(_desc_label)
	_desc_label.add_theme_font_size_override("normal_font_size", 20)
	_desc_label.add_theme_font_size_override("bold_font_size", 20)
	_desc_label.add_theme_font_size_override("italic_font_size", 20)
	_desc_label.add_theme_font_size_override("bold_italic_font_size", 20)
	_desc_label.add_theme_font_size_override("mono_font_size", 20)
	_desc_label.custom_minimum_size = Vector2(PANEL_MIN_SIZE.x - 60.0, 0)
	card_box.add_child(_desc_label)

	# 接受 / 放弃 按钮
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	_vbox.add_child(btn_row)

	_accept_btn = Button.new()
	_accept_btn.text = LanguageManager.tr_ui("UI_THEMED_ACCEPT")
	_accept_btn.custom_minimum_size = Vector2(120, 48)
	PixelUi.apply_ui_font(_accept_btn)
	_accept_btn.add_theme_font_size_override("font_size", 24)
	_accept_btn.pressed.connect(_on_accept)
	btn_row.add_child(_accept_btn)

	_decline_btn = Button.new()
	_decline_btn.text = LanguageManager.tr_ui("UI_THEMED_DECLINE")
	_decline_btn.custom_minimum_size = Vector2(120, 48)
	PixelUi.apply_ui_font(_decline_btn)
	_decline_btn.add_theme_font_size_override("font_size", 24)
	_decline_btn.pressed.connect(_on_decline)
	btn_row.add_child(_decline_btn)


func show_for_theme(theme: String, upgrade: Dictionary) -> void:
	_theme = theme
	_upgrade = upgrade
	_anim_time = 0.0
	_closing = false
	_sync_root_size()
	_apply_theme_palette()
	_apply_upgrade_content()
	_relayout_panel()
	visible = true
	move_to_front()
	queue_redraw()
	# 弹出动画：overlay 渐显 + 主面板从 0.82× 放大到 1.0× 同时透明度 0→1
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.82, 0.82)
	_panel.modulate.a = 0.0
	_overlay.modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_overlay, "modulate:a", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_panel, "modulate:a", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_panel, "scale", Vector2.ONE, SHOW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_popup() -> void:
	# 立即隐藏（兜底；正常关闭走 _animate_close）
	visible = false


# 渐出动画：完成后 visible=false 并 emit 给定的回调
func _animate_close(then_emit: Callable) -> void:
	if _closing:
		return
	_closing = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_overlay, "modulate:a", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_panel, "modulate:a", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_panel, "scale", Vector2(0.88, 0.88), HIDE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.chain().tween_callback(func():
		visible = false
		_closing = false
		then_emit.call())


# 跟随 viewport：项目改分辨率时（GameConfig.get_logical_size 变化）自动撑满
func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	size = vp


# 居中 + 按 viewport 留 margin；既不会卡到右下角也不会被压成 min_size
func _relayout_panel() -> void:
	if _panel == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	var panel_size := Vector2(
		clampf(vp.x - PANEL_MARGIN * 2.0, PANEL_MIN_SIZE.x, vp.x),
		clampf(vp.y * 0.62, PANEL_MIN_SIZE.y, vp.y - PANEL_MARGIN * 2.0)
	)
	var center := vp * 0.5
	_panel.position = center - panel_size * 0.5
	_panel.size = panel_size
	# desc_label 最大宽度跟着 panel 走
	if _desc_label != null:
		_desc_label.custom_minimum_size = Vector2(panel_size.x - 80.0, 0.0)


func _on_root_resized() -> void:
	_sync_root_size()
	_relayout_panel()


func _apply_theme_palette() -> void:
	# 面板 / 按钮走标准 9-slice（panel_dialog_9s / btn_primary_9s），只在色调上区分主题。
	# 面板 tint 保持较高亮度，避免把 9-slice 底纹压成一片死色；主题氛围交给 title / accept 按钮 / overlay。
	var panel_tint: Color
	var accent: Color
	var accept_font: Color
	var title_text: String
	if _theme == "demon":
		panel_tint = Color(0.68, 0.42, 0.44, 1.0)   # 灰烬玫瑰底纹（暗红但保留 panel 结构）
		accent = Color("#c63e3e")                    # 主色（title / name / accept 按钮）
		accept_font = Color(0.98, 0.96, 0.96)
		title_text = LanguageManager.tr_ui("UI_THEMED_DEMON_TITLE")
		_overlay.color = Color(0.18, 0.03, 0.05, 0.6)
	else:
		panel_tint = Color(0.90, 0.84, 0.66, 1.0)   # 圣光米黄
		accent = Color("#efb840")                    # 与其他 popup 主按钮同款金
		accept_font = Color(0.12, 0.08, 0.03)
		title_text = LanguageManager.tr_ui("UI_THEMED_ANGEL_TITLE")
		_overlay.color = Color(0.55, 0.50, 0.22, 0.38)

	var panel_style := UiStyle.make_dialog_stylebox(panel_tint, 20)
	if panel_style != null:
		_panel.add_theme_stylebox_override("panel", panel_style)
		_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_title_label.text = title_text
	_title_label.modulate = accent
	_name_label.modulate = accent
	if _theme == "demon":
		_desc_label.modulate = Color(0.98, 0.94, 0.92)
	else:
		_desc_label.modulate = Color(0.28, 0.20, 0.06)

	UiStyle.apply_primary_button(_accept_btn, accent, 10)
	_accept_btn.add_theme_color_override("font_color", accept_font)

	UiStyle.apply_primary_button(_decline_btn, Color(0.55, 0.60, 0.78), 10)
	_decline_btn.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))


func _apply_upgrade_content() -> void:
	_name_label.text = LanguageManager.localize(_upgrade, "name")
	var raw_desc := LanguageManager.localize_field(_upgrade, "desc_cn_game_en", "desc_cn_game")
	if raw_desc.is_empty():
		raw_desc = LanguageManager.localize(_upgrade, "desc")
	DescFormatT.apply_to_rich_text(_desc_label, raw_desc, 20, true)
	# 重建 icon widget
	for child in _icon_widget.get_children():
		child.queue_free()
	# 优先：xlsx E 列 skill_XX 的 PNG + FRAME 边框
	var framed := UiStyle.build_reward_icon_with_frame(_upgrade, CARD_ICON_SIZE)
	if framed != null:
		_icon_widget.add_child(framed)
		return
	# fallback：程序化像素卡（emoji / 空 icon 卡走此路）
	var pixel := PixelCardIconT.new()
	pixel.upgrade = _upgrade
	pixel.icon_size = CARD_ICON_SIZE
	pixel.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
	pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_widget.add_child(pixel)


func _process(delta: float) -> void:
	if not visible:
		return
	_anim_time += delta
	_draw_timer -= delta
	if _draw_timer <= 0.0:
		_draw_timer = 0.06
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	# 主题氛围光晕：恶魔血红脉冲、天使圣光放射
	var size := get_viewport_rect().size
	var center := size * 0.5
	var pulse: float = 0.85 + sin(_anim_time * 5.0) * 0.15
	if _theme == "demon":
		var col := Color(0.8, 0.1, 0.08, 0.25 * pulse)
		draw_circle(center, maxf(size.x, size.y) * 0.6, col)
	elif _theme == "angel":
		var col2 := Color(1.0, 0.92, 0.55, 0.22 * pulse)
		draw_circle(center, maxf(size.x, size.y) * 0.6, col2)
		# 圣光放射线
		for i in range(8):
			var ang := float(i) * TAU / 8.0 + _anim_time * 0.3
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(center - dir * size.x * 0.05, center + dir * size.x * 0.5,
				Color(1.0, 0.95, 0.65, 0.12 * pulse), size.y * 0.06)


func _on_accept() -> void:
	if _closing:
		return
	var up := _upgrade
	_animate_close(func(): reward_resolved.emit(true, up))


func _on_decline() -> void:
	if _closing:
		return
	var up := _upgrade
	_animate_close(func(): reward_resolved.emit(false, up))
