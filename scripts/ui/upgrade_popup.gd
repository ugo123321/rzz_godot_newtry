extends Control
class_name UpgradePopup

const ICON_SIZE := 48
const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

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
	_apply_label_font(title_label, 22)
	_apply_label_font(rarity_label, 16)


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
	card_w = clampf(card_w, 118.0, 188.0)
	var card_h: float = clampf(panel_h * 0.52, 144.0, 220.0)
	return {
		"card_size": Vector2(card_w, card_h),
		"preview_h": clampf(card_h * 0.4, 64.0, 86.0),
		"name_font": 16 if card_w < 150.0 else 18,
		"desc_font": 12 if card_w < 150.0 else 14,
	}


func _create_icon_widget(upgrade: Dictionary) -> Control:
	var box := CenterContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon_path := str(upgrade.get("icon_file", ""))
	if icon_path.is_empty():
		var fallback := Label.new()
		fallback.text = str(upgrade.get("icon", "?"))
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_label_font(fallback, 26)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(fallback)
		return box

	var texture := load(icon_path) as Texture2D
	if texture == null:
		var missing := Label.new()
		missing.text = str(upgrade.get("icon", "?"))
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_label_font(missing, 26)
		missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(missing)
		return box

	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	return box


func _rebuild_cards() -> void:
	for child in cards.get_children():
		child.queue_free()

	title_label.text = "升级！选择一个强化"
	rarity_label.text = str(_fx.get("name_cn", "普通"))
	rarity_label.modulate = Color(str(_fx.get("color_hex", "#ffffff")))

	var choice_count := upgrade_manager.choices.size()
	var metrics: Dictionary = _calc_card_metrics(choice_count)
	var card_size: Vector2 = metrics["card_size"]
	var preview_h: float = metrics["preview_h"]
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

		var icon_box := _create_icon_widget(upgrade)
		icon_box.custom_minimum_size = Vector2(0, preview_h)
		vbox.add_child(icon_box)

		var stack := 0
		if battle and battle.player:
			stack = battle.player.get_upgrade_level(str(upgrade.get("id", "")))

		var name_label := Label.new()
		name_label.text = str(upgrade.get("name_cn", ""))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_label_font(name_label, name_font)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = str(upgrade.get("desc_cn", ""))
		if stack > 0:
			desc_label.text += "\nLv.%d" % (stack + 1)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_label_font(desc_label, desc_font)
		desc_label.modulate = Color(0.82, 0.82, 0.82)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_label)

		var rarity_color := Color(
			str(GameConfig.get_upgrade_fx(str(upgrade.get("rarity", "blue"))).get("color_hex", "#ffffff"))
		)
		name_label.modulate = rarity_color
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.24, 0.96)
		style.border_color = rarity_color
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.shadow_color = Color(rarity_color, card_glow * 0.6)
		style.shadow_size = int(4 + card_glow * 8)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
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
