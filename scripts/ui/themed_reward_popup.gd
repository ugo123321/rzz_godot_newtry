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

const PANEL_MARGIN := 36.0
const PANEL_MIN_SIZE := Vector2(360.0, 540.0)
const CARD_ICON_SIZE := 128.0
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
	_accept_btn.text = "接受"
	_accept_btn.custom_minimum_size = Vector2(120, 48)
	PixelUi.apply_ui_font(_accept_btn)
	_accept_btn.add_theme_font_size_override("font_size", 24)
	_accept_btn.pressed.connect(_on_accept)
	btn_row.add_child(_accept_btn)

	_decline_btn = Button.new()
	_decline_btn.text = "放弃"
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
	var bg: Color
	var accent: Color
	var title_text: String
	if _theme == "demon":
		bg = Color(0.18, 0.04, 0.05, 0.97)
		accent = Color(0.92, 0.18, 0.15, 1.0)
		title_text = "恶魔的契约"
		_overlay.color = Color(0.15, 0.0, 0.0, 0.7)
	else:
		bg = Color(0.96, 0.92, 0.72, 0.97)
		accent = Color(0.78, 0.62, 0.18, 1.0)
		title_text = "天使的祝福"
		_overlay.color = Color(0.6, 0.55, 0.25, 0.45)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = bg
	panel_style.border_color = accent
	panel_style.set_border_width_all(4)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(accent, 0.65)
	panel_style.shadow_size = 18
	panel_style.set_content_margin_all(20.0)
	_panel.add_theme_stylebox_override("panel", panel_style)

	_title_label.text = title_text
	_title_label.modulate = accent
	_name_label.modulate = accent
	if _theme == "demon":
		_desc_label.modulate = Color(1.0, 0.85, 0.8)
	else:
		_desc_label.modulate = Color(0.32, 0.22, 0.05)

	# Accept 按钮主题：恶魔血红、天使圣金
	var accept_style := StyleBoxFlat.new()
	accept_style.bg_color = accent
	accept_style.set_corner_radius_all(6)
	accept_style.shadow_color = Color(accent, 0.5)
	accept_style.shadow_size = 6
	accept_style.set_content_margin_all(10.0)
	_accept_btn.add_theme_stylebox_override("normal", accept_style)
	_accept_btn.add_theme_stylebox_override("hover", accept_style)
	_accept_btn.add_theme_stylebox_override("pressed", accept_style)
	_accept_btn.modulate = Color(1, 1, 1)
	_accept_btn.add_theme_color_override("font_color", Color(0.05, 0.04, 0.04))

	var decline_style := StyleBoxFlat.new()
	decline_style.bg_color = Color(0.15, 0.15, 0.2, 0.85)
	decline_style.border_color = Color(0.5, 0.5, 0.55)
	decline_style.set_border_width_all(2)
	decline_style.set_corner_radius_all(6)
	decline_style.set_content_margin_all(10.0)
	_decline_btn.add_theme_stylebox_override("normal", decline_style)
	_decline_btn.add_theme_stylebox_override("hover", decline_style)
	_decline_btn.add_theme_stylebox_override("pressed", decline_style)
	_decline_btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))


func _apply_upgrade_content() -> void:
	_name_label.text = str(_upgrade.get("name_cn", ""))
	var raw_desc := str(_upgrade.get("desc_cn_game", ""))
	if raw_desc.is_empty():
		raw_desc = str(_upgrade.get("desc_cn", ""))
	DescFormatT.apply_to_rich_text(_desc_label, raw_desc, 20, true)
	# 重建 icon widget
	for child in _icon_widget.get_children():
		child.queue_free()
	var icon_path := str(_upgrade.get("icon_file", ""))
	if not icon_path.is_empty():
		var texture := load(icon_path) as Texture2D
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_icon_widget.add_child(icon)
			return
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
