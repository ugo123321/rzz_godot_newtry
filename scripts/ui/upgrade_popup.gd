extends Control
class_name UpgradePopup

const ICON_SIZE := 48
const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const PixelCardIconT = preload("res://scripts/ui/pixel_card_icon.gd")
const DescFormatT = preload("res://scripts/utils/desc_format.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

signal upgrade_picked(index: int)

@onready var panel: Control = $Panel
@onready var title_label: Label = $Panel/CenterContainer/VBox/TitleLabel
@onready var rarity_label: Label = $Panel/CenterContainer/VBox/RarityLabel
@onready var cards: HBoxContainer = $Panel/CenterContainer/VBox/Cards

var battle: Node
var upgrade_manager: UpgradeManager
var _fx: Dictionary = {}
var _anim_time := 0.0
var _draw_timer := 0.0


func setup(battle_node: Node, manager: UpgradeManager) -> void:
	battle = battle_node
	upgrade_manager = manager
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_layout()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 14)
	_apply_label_font(title_label, 32)
	_apply_label_font(rarity_label, 22)


func _apply_label_font(label: Control, font_size: int) -> void:
	if label == null:
		return
	PixelUi.apply_ui_font(label)
	label.add_theme_font_size_override("font_size", font_size)


func _apply_panel_layout() -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 20.0
	panel.offset_top = 20.0
	panel.offset_right = -20.0
	panel.offset_bottom = -20.0


func show_popup() -> void:
	visible = true
	_anim_time = 0.0
	_fx = GameConfig.get_upgrade_fx(upgrade_manager.rolled_rarity)
	_apply_panel_layout()
	call_deferred("_rebuild_cards")
	queue_redraw()


func hide_popup() -> void:
	visible = false
	for child in cards.get_children():
		child.queue_free()


func _process(delta: float) -> void:
	if not visible:
		return
	_anim_time += delta
	_draw_timer -= delta
	if _draw_timer <= 0.0:
		_draw_timer = 0.033
		queue_redraw()


func _draw() -> void:
	if not visible or _fx.is_empty():
		return
	var size := get_viewport_rect().size
	var pop_t := _ease_out(clampf(_anim_time / 0.45, 0.0, 1.0))
	var tier_color := Color(str(_fx.get("color_hex", "#ffffff")))

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, float(_fx.get("overlay", 0.76)) * pop_t))

	var edge_glow := float(_fx.get("edge_glow", 0.0))
	if edge_glow > 0.0:
		var pulse := 1.0
		if int(_fx.get("pulse", 0)) != 0:
			pulse = 0.85 + sin(_anim_time * 8.0) * 0.15
		var center := size * 0.5
		var radius := maxf(size.x, size.y) * 0.72
		draw_circle(center, radius, Color(tier_color, edge_glow * 0.25 * pop_t * pulse))
		draw_arc(center, radius * 0.92, 0.0, TAU, 64, Color(tier_color, edge_glow * 0.45 * pop_t * pulse), 8.0)

	if int(_fx.get("rays", 0)) != 0:
		var center := size * 0.5
		for i in range(8):
			var ang := float(i) * TAU / 8.0 + _anim_time * 0.4
			var dir := Vector2(cos(ang), sin(ang))
			var p1 := center - dir * size.x * 0.1
			var p2 := center + dir * size.x * 0.55
			draw_line(p1, p2, Color(tier_color, 0.12 * pop_t), size.y * 0.12)

	var spark_count := int(_fx.get("spark_count", 0))
	if spark_count > 0:
		var seed := int(_anim_time * 8.0)
		for i in range(spark_count):
			var a := float((i * 47 + seed) % 360) / 360.0 * TAU
			var dist := float((i * 19 + seed) % 100) / 100.0
			var px := size.x * 0.5 + cos(a) * size.x * 0.38 * dist
			var py := size.y * 0.5 + sin(a) * size.y * 0.32 * dist
			var sz := 2.0 + float(i % 3)
			draw_rect(Rect2(px, py, sz, sz), Color(tier_color, 0.25 + float(i % 4) * 0.12))


func _calc_card_metrics(choice_count: int) -> Dictionary:
	var vp := get_viewport_rect().size
	var panel_w := vp.x - 40.0
	var panel_h := vp.y - 40.0
	var n := maxi(1, choice_count)
	var sep := 14.0
	var inner_pad := 18.0
	var card_w: float = floor((panel_w - inner_pad * 2.0 - sep * float(n - 1)) / float(n))
	card_w = clampf(card_w, 140.0, 260.0)
	var card_h: float = clampf(panel_h * 0.48, 280.0, 520.0)
	var preview_h: float = clampf(card_h * 0.42, 110.0, 200.0)
	return {
		"card_size": Vector2(card_w, card_h),
		"preview_h": preview_h,
		"icon_size": clampf(preview_h * 0.6, ICON_SIZE, 96.0),
		"name_font": 24 if card_w < 170.0 else 28,
		"desc_font": 18 if card_w < 170.0 else 22,
	}


func _create_icon_widget(upgrade: Dictionary, icon_size: float = float(ICON_SIZE)) -> Control:
	# 优先：xlsx E 列填了 skill_XX 的走 PNG + FRAME 边框
	var widget := UiStyle.build_reward_icon_with_frame(upgrade, icon_size)
	if widget != null:
		return widget

	# fallback：像素图标（按 id 前缀 + applies_<elem> 程序化绘制），用于 emoji / 空 icon 卡
	var box := CenterContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pixel := PixelCardIconT.new()
	pixel.upgrade = upgrade
	pixel.icon_size = icon_size
	pixel.custom_minimum_size = Vector2(icon_size, icon_size)
	pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pixel)
	return box


func _rebuild_cards() -> void:
	for child in cards.get_children():
		child.queue_free()

	title_label.text = LanguageManager.tr_ui("UI_UPGRADE_TITLE")
	var rarity_key := "UI_RARITY_" + str(_fx.get("rarity", "white")).to_upper()
	rarity_label.text = LanguageManager.tr_ui(rarity_key, str(_fx.get("name_cn", "")))
	rarity_label.modulate = Color(str(_fx.get("color_hex", "#ffffff")))

	var choice_count := upgrade_manager.choices.size()
	var metrics: Dictionary = _calc_card_metrics(choice_count)
	var card_size: Vector2 = metrics["card_size"]
	var preview_h: float = metrics["preview_h"]
	var icon_size: float = metrics["icon_size"]
	var name_font: int = metrics["name_font"]
	var desc_font: int = metrics["desc_font"]
	var card_glow := float(_fx.get("card_glow", 0.12))

	for i in range(choice_count):
		var upgrade: Dictionary = upgrade_manager.choices[i]
		var btn := Button.new()
		btn.custom_minimum_size = card_size
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_stretch_ratio = 1.0
		btn.text = ""
		_apply_label_font(btn, name_font)

		var vbox := VBoxContainer.new()
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 4)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(vbox)

		var icon_box := _create_icon_widget(upgrade, icon_size)
		icon_box.custom_minimum_size = Vector2(0, preview_h)
		vbox.add_child(icon_box)

		var stack := 0
		if battle and battle.player:
			stack = battle.player.get_upgrade_level(str(upgrade.get("id", "")))

		var name_label := Label.new()
		name_label.text = LanguageManager.localize(upgrade, "name")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_label_font(name_label, name_font)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_label)

		var desc_label := RichTextLabel.new()
		desc_label.bbcode_enabled = true
		desc_label.fit_content = true
		desc_label.scroll_active = false
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var raw_desc := LanguageManager.localize_field(upgrade, "desc_cn_game_en", "desc_cn_game")
		if raw_desc.is_empty():
			raw_desc = LanguageManager.localize(upgrade, "desc")
		if stack > 0:
			raw_desc += "\nLv.%d" % (stack + 1)
		DescFormatT.apply_to_rich_text(desc_label, raw_desc, desc_font, true)
		PixelUi.apply_ui_font(desc_label)
		desc_label.add_theme_font_size_override("normal_font_size", desc_font)
		desc_label.add_theme_font_size_override("bold_font_size", desc_font)
		desc_label.add_theme_font_size_override("italic_font_size", desc_font)
		desc_label.add_theme_font_size_override("bold_italic_font_size", desc_font)
		desc_label.add_theme_font_size_override("mono_font_size", desc_font)
		desc_label.modulate = Color(0.82, 0.82, 0.82)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(desc_label)

		var card_rarity := str(upgrade.get("rarity", "blue"))
		var card_fx: Dictionary = GameConfig.get_upgrade_fx(card_rarity)
		var rarity_color := Color(str(card_fx.get("color_hex", "#ffffff")))
		var card_card_glow := float(card_fx.get("card_glow", card_glow))
		name_label.modulate = rarity_color
		desc_label.modulate = rarity_color.lerp(Color(1, 1, 1), 0.55)
		# 卡片整体染色：背景在深色基底上向 rarity_color 偏，rarity 越高偏色越浓
		var bg_tint_strength := float({
			"white": 0.08,
			"blue": 0.18,
			"purple": 0.28,
			"orange": 0.38,
		}.get(card_rarity, 0.18))
		var base_dark := Color(0.10, 0.10, 0.18)
		var bg_color := base_dark.lerp(rarity_color, bg_tint_strength)
		bg_color.a = 0.96
		var border_w := int({"white": 2, "blue": 3, "purple": 4, "orange": 5}.get(card_rarity, 3))
		var style := StyleBoxFlat.new()
		style.bg_color = bg_color
		style.border_color = rarity_color
		style.set_border_width_all(border_w)
		style.set_corner_radius_all(6)
		style.shadow_color = Color(rarity_color, clampf(0.35 + card_card_glow * 0.6, 0.2, 0.95))
		style.shadow_size = int(6 + card_card_glow * 14)
		btn.add_theme_stylebox_override("normal", style)
		# hover/pressed 更亮，强化反馈
		var hover_style := style.duplicate() as StyleBoxFlat
		hover_style.bg_color = base_dark.lerp(rarity_color, minf(1.0, bg_tint_strength + 0.10))
		hover_style.bg_color.a = 0.96
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.modulate.a = 0.0

		var idx := i
		btn.pressed.connect(func(): _pick(idx))
		cards.add_child(btn)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pick(index: int) -> void:
	if not upgrade_manager.can_interact():
		return
	var player: BattlePlayer = battle.player
	var upgrade := upgrade_manager.select_upgrade(index, player)
	if upgrade.is_empty():
		return
	hide_popup()
	upgrade_picked.emit(index)


func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

