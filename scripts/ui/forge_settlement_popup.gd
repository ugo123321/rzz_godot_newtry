extends Control
class_name ForgeSettlementPopup

# 属性打造关结算面板（v2）：
# - 10 块全落完 + 沉降后弹出
# - 显示：奖励品质（按剩余堆叠块数）、堆叠块数、各属性总加成
# - 单个「继续」按钮 → emit continue_pressed → battle 一次性 commit buff + 弹 3 选 1
# - 视觉参照 themed_reward_popup，紫色系（lottery_portal 风格）

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const PANEL_MARGIN := 36.0
const PANEL_MIN_SIZE := Vector2(380.0, 480.0)
const SHOW_DURATION := 0.32
const HIDE_DURATION := 0.18

signal continue_pressed

var battle: Node
var _rarity := "white"
var _stacked := 0
var _totals: Dictionary = {}    # {name_cn: total_delta}
var _anim_time := 0.0
var _draw_timer := 0.0
var _active_tween: Tween = null
var _closing := false

var _overlay: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _attr_list: VBoxContainer
var _continue_btn: Button


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
	_overlay.color = Color(0.05, 0.02, 0.12, 0.7)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(_vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_title_label)
	_title_label.add_theme_font_size_override("font_size", 32)
	_vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_subtitle_label)
	_subtitle_label.add_theme_font_size_override("font_size", 22)
	_vbox.add_child(_subtitle_label)

	# 属性列表容器
	_attr_list = VBoxContainer.new()
	_attr_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_attr_list.add_theme_constant_override("separation", 6)
	_vbox.add_child(_attr_list)

	# 「继续」按钮
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(btn_row)

	_continue_btn = Button.new()
	_continue_btn.text = LanguageManager.tr_ui("UI_FORGE_CONTINUE")
	_continue_btn.custom_minimum_size = Vector2(160, 52)
	PixelUi.apply_ui_font(_continue_btn)
	_continue_btn.add_theme_font_size_override("font_size", 26)
	_continue_btn.pressed.connect(_on_continue)
	btn_row.add_child(_continue_btn)


func show_for(rarity: String, stacked: int, totals: Dictionary) -> void:
	_rarity = rarity
	_stacked = stacked
	_totals = totals
	_anim_time = 0.0
	_closing = false
	_sync_root_size()
	_apply_palette()
	_apply_content()
	_relayout_panel()
	visible = true
	move_to_front()
	queue_redraw()
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
	visible = false


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


func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	size = vp


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


func _on_root_resized() -> void:
	_sync_root_size()
	_relayout_panel()


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"white":
			return Color("#ffffff")
		"blue":
			return Color("#5aa8e8")
		"purple":
			return Color("#8a5cff")
		"orange":
			return Color("#ff9820")
		_:
			return Color("#ffffff")


func _rarity_zh(rarity: String) -> String:
	match rarity:
		"white":
			return LanguageManager.tr_ui("UI_FORGE_RARITY_WHITE")
		"blue":
			return LanguageManager.tr_ui("UI_FORGE_RARITY_BLUE")
		"purple":
			return LanguageManager.tr_ui("UI_FORGE_RARITY_PURPLE")
		"orange":
			return LanguageManager.tr_ui("UI_FORGE_RARITY_ORANGE")
		_:
			return rarity


func _apply_palette() -> void:
	# v3：对齐 upgrade_popup 风格 — base_dark + 品质色微染 + 锐角像素感
	var accent := _rarity_color(_rarity)
	var base_dark := Color(0.10, 0.10, 0.18)
	var bg_tint_strength := float({
		"white": 0.08,
		"blue": 0.18,
		"purple": 0.28,
		"orange": 0.38,
	}.get(_rarity, 0.18))
	var bg_color := base_dark.lerp(accent, bg_tint_strength)
	bg_color.a = 0.96
	var border_w := int({"white": 2, "blue": 3, "purple": 4, "orange": 5}.get(_rarity, 3))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = bg_color
	panel_style.border_color = accent
	panel_style.set_border_width_all(border_w)
	panel_style.set_corner_radius_all(6)
	panel_style.shadow_color = Color(accent, 0.5)
	panel_style.shadow_size = 12
	panel_style.set_content_margin_all(22.0)
	_panel.add_theme_stylebox_override("panel", panel_style)

	_title_label.modulate = accent
	_subtitle_label.modulate = accent.lerp(Color(1, 1, 1), 0.55)

	# 继续按钮：风格匹配品质，深色字
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = bg_color.lerp(accent, 0.35)
	btn_style.border_color = accent
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(4)
	btn_style.shadow_color = Color(accent, 0.5)
	btn_style.shadow_size = 6
	btn_style.set_content_margin_all(10.0)
	_continue_btn.add_theme_stylebox_override("normal", btn_style)
	_continue_btn.add_theme_stylebox_override("hover", btn_style)
	_continue_btn.add_theme_stylebox_override("pressed", btn_style)
	_continue_btn.add_theme_color_override("font_color", Color(1, 1, 1))


func _apply_content() -> void:
	_title_label.text = LanguageManager.tr_ui("UI_FORGE_TITLE")
	_subtitle_label.text = LanguageManager.tr_ui("UI_FORGE_SUBTITLE_FMT") % [_stacked, _rarity_zh(_rarity)]
	# 清空旧 attr list
	for child in _attr_list.get_children():
		child.queue_free()
	# 按 name_cn 顺序固定排列（与 director FORGE_BUFF_TABLE 顺序一致），缺失的不显示
	var ordered_names := ["基础生命", "基础攻击力", "气力上限", "暴击率", "移速", "攻速", "气力恢复", "画线消耗"]
	var any_added := false
	for name_cn in ordered_names:
		if not _totals.has(name_cn):
			continue
		var total: float = float(_totals[name_cn])
		if abs(total) < 0.0001:
			continue
		_attr_list.add_child(_make_attr_row(name_cn, total))
		any_added = true
	if not any_added:
		var empty_label := Label.new()
		empty_label.text = LanguageManager.tr_ui("UI_FORGE_NO_BUFF")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		PixelUi.apply_ui_font(empty_label)
		empty_label.add_theme_font_size_override("font_size", 20)
		empty_label.modulate = Color(0.7, 0.65, 0.85)
		_attr_list.add_child(empty_label)


func _make_attr_row(name_cn: String, total_delta: float) -> Control:
	var row := Label.new()
	var sign_str := "+" if total_delta >= 0.0 else ""
	var pct := int(round(total_delta * 100.0))
	# name_cn 是中文 ID（贯穿 forge 数据流），UI 显示时翻译；缺 key 时回落原 name_cn
	var localized_name := LanguageManager.tr_ui("FORGE_ATTR_" + name_cn, name_cn)
	row.text = "%s   %s%d%%" % [localized_name, sign_str, pct]
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(row)
	row.add_theme_font_size_override("font_size", 22)
	# v3：用品质色（含正/负向区分）— 与升级 popup 的 name_label 风格一致
	var accent := _rarity_color(_rarity)
	if total_delta >= 0.0:
		row.modulate = accent.lerp(Color(1, 1, 1), 0.25)
	else:
		row.modulate = Color("#a8e8ff")
	return row


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
	# 背景品质光晕：脉冲圆
	var vp_size := get_viewport_rect().size
	var center := vp_size * 0.5
	var pulse: float = 0.85 + sin(_anim_time * 5.0) * 0.15
	var accent := _rarity_color(_rarity)
	draw_circle(center, maxf(vp_size.x, vp_size.y) * 0.55, Color(accent.r, accent.g, accent.b, 0.10 * pulse))


func _on_continue() -> void:
	if _closing:
		return
	_animate_close(func(): continue_pressed.emit())
