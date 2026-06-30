extends Control
class_name PauseMenu

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const PixelCardIconT = preload("res://scripts/ui/pixel_card_icon.gd")

enum View { PAUSE, DEBUG, DEBUG_UPGRADES }

var battle
var view := View.PAUSE
var debug_level := 1
var debug_stage := 1
var debug_wood := 0
var debug_upgrade_levels: Dictionary = {}

# === 节点引用（_apply_texts / _sync_* 用） ===
var _title: Label
var _resume_btn: Button
var _debug_btn: Button
var _hint: Label
var _lang_label: Label
var _lang_zh_btn: Button
var _lang_en_btn: Button
var _lv_minus_btn: Button
var _lv_plus_btn: Button
var _level_label: Label
var _st_minus_btn: Button
var _st_plus_btn: Button
var _stage_label: Label
var _wd_minus_btn: Button
var _wd_plus_btn: Button
var _wood_label: Label
var _wd_plus_50_btn: Button
var _wd_plus_100_btn: Button
var _wd_zero_btn: Button
var _upgrades_btn: Button
var _apply_btn: Button
var _enter_house_btn: Button
var _back_btn: Button
var _upgrades_hint: Label
var _apply_upgrades_btn: Button
var _upgrades_back_btn: Button
var _upgrades_list: VBoxContainer


func setup(battle_node) -> void:
	battle = battle_node
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_texts()
	if not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	_sync_debug_labels()
	_refresh_upgrade_row_texts()
	_update_view()  # title 跟 view 变化


func _apply_texts() -> void:
	if _title:
		_title.text = LanguageManager.tr_ui("UI_PAUSE_TITLE")
	if _resume_btn:
		_resume_btn.text = LanguageManager.tr_ui("UI_PAUSE_RESUME")
	if _debug_btn:
		_debug_btn.text = LanguageManager.tr_ui("UI_PAUSE_DEBUG")
	if _hint:
		_hint.text = LanguageManager.tr_ui("UI_PAUSE_HINT")
	if _lang_label:
		_lang_label.text = LanguageManager.tr_ui("UI_PAUSE_LANG_LABEL")
	if _lang_zh_btn:
		_lang_zh_btn.text = LanguageManager.tr_ui("UI_PAUSE_LANG_ZH")
		_apply_lang_btn_state(_lang_zh_btn, LanguageManager.current_lang == "zh_CN")
	if _lang_en_btn:
		_lang_en_btn.text = LanguageManager.tr_ui("UI_PAUSE_LANG_EN")
		_apply_lang_btn_state(_lang_en_btn, LanguageManager.current_lang == "en")
	if _lv_minus_btn: _lv_minus_btn.text = LanguageManager.tr_ui("UI_DEBUG_LV_MINUS")
	if _lv_plus_btn: _lv_plus_btn.text = LanguageManager.tr_ui("UI_DEBUG_LV_PLUS")
	if _st_minus_btn: _st_minus_btn.text = LanguageManager.tr_ui("UI_DEBUG_STAGE_MINUS")
	if _st_plus_btn: _st_plus_btn.text = LanguageManager.tr_ui("UI_DEBUG_STAGE_PLUS")
	if _wd_minus_btn: _wd_minus_btn.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_MINUS")
	if _wd_plus_btn: _wd_plus_btn.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_PLUS")
	if _wd_plus_50_btn: _wd_plus_50_btn.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_PLUS50")
	if _wd_plus_100_btn: _wd_plus_100_btn.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_PLUS100")
	if _wd_zero_btn: _wd_zero_btn.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_ZERO")
	if _upgrades_btn: _upgrades_btn.text = LanguageManager.tr_ui("UI_DEBUG_UPGRADES_BTN")
	if _apply_btn: _apply_btn.text = LanguageManager.tr_ui("UI_DEBUG_APPLY_JUMP")
	if _enter_house_btn: _enter_house_btn.text = LanguageManager.tr_ui("UI_DEBUG_ENTER_HOUSE")
	if _back_btn: _back_btn.text = LanguageManager.tr_ui("UI_DEBUG_BACK")
	if _upgrades_hint: _upgrades_hint.text = LanguageManager.tr_ui("UI_DEBUG_UPGRADES_HINT")
	if _apply_upgrades_btn: _apply_upgrades_btn.text = LanguageManager.tr_ui("UI_DEBUG_APPLY_UPGRADES")
	if _upgrades_back_btn: _upgrades_back_btn.text = LanguageManager.tr_ui("UI_DEBUG_BACK")


func _apply_lang_btn_state(btn: Button, active: bool) -> void:
	# 当前语言按钮高亮，另一个变灰
	btn.modulate = Color(1.0, 1.0, 1.0) if active else Color(0.55, 0.55, 0.60)


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var panel_style := UiStyle.make_dialog_stylebox(Color(0.78, 0.78, 0.86, 1.0), 26)
	if panel_style != null:
		panel.add_theme_stylebox_override("panel", panel_style)
		panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0.08, 0.09, 0.13, 0.96)
		fb.border_color = Color(0.78, 0.65, 0.34, 1.0)
		fb.set_border_width_all(3)
		fb.set_corner_radius_all(10)
		fb.content_margin_left = 28
		fb.content_margin_right = 28
		fb.content_margin_top = 24
		fb.content_margin_bottom = 24
		panel.add_theme_stylebox_override("panel", fb)
	panel.custom_minimum_size = _panel_min_size()
	center.add_child(panel)

	var menu_theme := Theme.new()
	menu_theme.default_font_size = 22
	panel.theme = menu_theme

	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 14)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	root.add_child(_title)

	var pause_box := VBoxContainer.new()
	pause_box.name = "PauseBox"
	pause_box.add_theme_constant_override("separation", 12)
	root.add_child(pause_box)

	_resume_btn = Button.new()
	_resume_btn.custom_minimum_size = Vector2(0, 60)
	UiStyle.apply_primary_button(_resume_btn, Color("#4dd07a"), 12)
	_resume_btn.add_theme_color_override("font_color", Color(0.06, 0.10, 0.06))
	_resume_btn.pressed.connect(_on_resume_pressed)
	pause_box.add_child(_resume_btn)

	_debug_btn = Button.new()
	_debug_btn.custom_minimum_size = Vector2(0, 60)
	UiStyle.apply_primary_button(_debug_btn, Color(0.55, 0.60, 0.78), 12)
	_debug_btn.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	_debug_btn.pressed.connect(_open_debug)
	pause_box.add_child(_debug_btn)

	# === 语言切换行 ===
	var lang_row := HBoxContainer.new()
	lang_row.name = "LangRow"
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 10)
	pause_box.add_child(lang_row)

	_lang_label = Label.new()
	_lang_label.name = "LangLabel"
	_lang_label.add_theme_font_size_override("font_size", 18)
	lang_row.add_child(_lang_label)

	_lang_zh_btn = Button.new()
	_lang_zh_btn.name = "LangZhBtn"
	_lang_zh_btn.custom_minimum_size = Vector2(96, 40)
	UiStyle.apply_primary_button(_lang_zh_btn, Color(0.62, 0.72, 0.92), 8)
	_lang_zh_btn.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
	_lang_zh_btn.pressed.connect(func(): LanguageManager.set_language("zh_CN"))
	lang_row.add_child(_lang_zh_btn)

	_lang_en_btn = Button.new()
	_lang_en_btn.name = "LangEnBtn"
	_lang_en_btn.custom_minimum_size = Vector2(96, 40)
	UiStyle.apply_primary_button(_lang_en_btn, Color(0.62, 0.72, 0.92), 8)
	_lang_en_btn.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
	_lang_en_btn.pressed.connect(func(): LanguageManager.set_language("en"))
	lang_row.add_child(_lang_en_btn)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.modulate = Color(0.8, 0.8, 0.8)
	pause_box.add_child(_hint)

	var debug_box := VBoxContainer.new()
	debug_box.name = "DebugBox"
	debug_box.visible = false
	debug_box.add_theme_constant_override("separation", 8)
	root.add_child(debug_box)

	var lv_row := HBoxContainer.new()
	debug_box.add_child(lv_row)
	_lv_minus_btn = Button.new()
	_lv_minus_btn.pressed.connect(func(): _adjust_debug_level(-1))
	lv_row.add_child(_lv_minus_btn)
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_row.add_child(_level_label)
	_lv_plus_btn = Button.new()
	_lv_plus_btn.pressed.connect(func(): _adjust_debug_level(1))
	lv_row.add_child(_lv_plus_btn)

	var st_row := HBoxContainer.new()
	debug_box.add_child(st_row)
	_st_minus_btn = Button.new()
	_st_minus_btn.pressed.connect(func(): _adjust_debug_stage(-1))
	st_row.add_child(_st_minus_btn)
	_stage_label = Label.new()
	_stage_label.name = "StageLabel"
	_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_row.add_child(_stage_label)
	_st_plus_btn = Button.new()
	_st_plus_btn.pressed.connect(func(): _adjust_debug_stage(1))
	st_row.add_child(_st_plus_btn)

	var wd_row := HBoxContainer.new()
	debug_box.add_child(wd_row)
	_wd_minus_btn = Button.new()
	_wd_minus_btn.pressed.connect(func(): _adjust_debug_wood(-10))
	wd_row.add_child(_wd_minus_btn)
	_wood_label = Label.new()
	_wood_label.name = "WoodLabel"
	_wood_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wd_row.add_child(_wood_label)
	_wd_plus_btn = Button.new()
	_wd_plus_btn.pressed.connect(func(): _adjust_debug_wood(10))
	wd_row.add_child(_wd_plus_btn)

	var wd_quick_row := HBoxContainer.new()
	debug_box.add_child(wd_quick_row)
	_wd_plus_50_btn = Button.new()
	_wd_plus_50_btn.pressed.connect(func(): _adjust_debug_wood(50))
	wd_quick_row.add_child(_wd_plus_50_btn)
	_wd_plus_100_btn = Button.new()
	_wd_plus_100_btn.pressed.connect(func(): _adjust_debug_wood(100))
	wd_quick_row.add_child(_wd_plus_100_btn)
	_wd_zero_btn = Button.new()
	_wd_zero_btn.pressed.connect(_zero_debug_wood)
	wd_quick_row.add_child(_wd_zero_btn)

	_upgrades_btn = Button.new()
	_upgrades_btn.pressed.connect(_open_debug_upgrades)
	debug_box.add_child(_upgrades_btn)

	_apply_btn = Button.new()
	_apply_btn.pressed.connect(_apply_debug)
	debug_box.add_child(_apply_btn)

	_enter_house_btn = Button.new()
	_enter_house_btn.pressed.connect(_apply_enter_build_house)
	debug_box.add_child(_enter_house_btn)

	_back_btn = Button.new()
	_back_btn.pressed.connect(_close_debug)
	debug_box.add_child(_back_btn)

	var upgrades_box := VBoxContainer.new()
	upgrades_box.name = "UpgradesBox"
	upgrades_box.visible = false
	upgrades_box.add_theme_constant_override("separation", 8)
	root.add_child(upgrades_box)

	_upgrades_hint = Label.new()
	_upgrades_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrades_hint.add_theme_font_size_override("font_size", 12)
	_upgrades_hint.modulate = Color(0.78, 0.78, 0.78)
	upgrades_box.add_child(_upgrades_hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upgrades_box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_upgrades_list = list

	_apply_upgrades_btn = Button.new()
	_apply_upgrades_btn.pressed.connect(_apply_debug_upgrades)
	upgrades_box.add_child(_apply_upgrades_btn)

	_upgrades_back_btn = Button.new()
	_upgrades_back_btn.pressed.connect(_close_debug_upgrades)
	upgrades_box.add_child(_upgrades_back_btn)

	PixelUi.apply_ui_font_tree(self)


func _panel_min_size() -> Vector2:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := clampf(vp.x * 0.78, 320.0, 640.0)
	var h := clampf(vp.y * 0.62, 480.0, 980.0)
	return Vector2(w, h)


func _refresh_panel_size() -> void:
	var panel := get_node_or_null("Center/Panel") as PanelContainer
	if panel:
		panel.custom_minimum_size = _panel_min_size()


func open_menu() -> void:
	view = View.PAUSE
	_refresh_panel_size()
	_sync_debug_labels()
	_update_view()
	visible = true
	z_index = 200
	move_to_front()
	mouse_filter = Control.MOUSE_FILTER_STOP


func close_menu() -> void:
	visible = false


func _open_debug() -> void:
	if battle:
		debug_level = battle.experience.level
		debug_stage = battle.stage_index + 1
	debug_wood = LobbyState.wood
	_sync_debug_upgrade_levels()
	_sync_debug_labels()
	view = View.DEBUG
	_update_view()


func _open_debug_upgrades() -> void:
	_sync_debug_upgrade_levels()
	_rebuild_upgrade_rows()
	view = View.DEBUG_UPGRADES
	_update_view()


func _close_debug() -> void:
	view = View.PAUSE
	_update_view()


func _close_debug_upgrades() -> void:
	view = View.DEBUG
	_update_view()


func _update_view() -> void:
	var vbox := get_node_or_null("Center/Panel/Root") as VBoxContainer
	if vbox == null:
		return
	var pause_box := vbox.get_node_or_null("PauseBox")
	var debug_box := vbox.get_node_or_null("DebugBox")
	var upgrades_box := vbox.get_node_or_null("UpgradesBox")
	if pause_box:
		pause_box.visible = view == View.PAUSE
	if debug_box:
		debug_box.visible = view == View.DEBUG
	if upgrades_box:
		upgrades_box.visible = view == View.DEBUG_UPGRADES
	if _title:
		match view:
			View.DEBUG:
				_title.text = LanguageManager.tr_ui("UI_DEBUG_TITLE")
			View.DEBUG_UPGRADES:
				_title.text = LanguageManager.tr_ui("UI_DEBUG_UPGRADES_TITLE")
			_:
				_title.text = LanguageManager.tr_ui("UI_PAUSE_TITLE")


func _sync_debug_labels() -> void:
	if _level_label:
		_level_label.text = LanguageManager.tr_ui("UI_DEBUG_LEVEL_FMT") % debug_level
	if _stage_label:
		_stage_label.text = LanguageManager.tr_ui("UI_DEBUG_STAGE_FMT") % debug_stage
	if _wood_label:
		_wood_label.text = LanguageManager.tr_ui("UI_DEBUG_WOOD_FMT") % debug_wood


func _sync_debug_upgrade_levels() -> void:
	debug_upgrade_levels.clear()
	for u in GameConfig.upgrades:
		var id := str(u.get("id", ""))
		var lv := 0
		if battle and battle.player:
			lv = battle.player.get_upgrade_level(id)
		debug_upgrade_levels[id] = lv


func _rebuild_upgrade_rows() -> void:
	if _upgrades_list == null:
		return
	for child in _upgrades_list.get_children():
		child.queue_free()
	for u in GameConfig.upgrades:
		var id := str(u.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.set_meta("upgrade_id", id)

		var icon := PixelCardIconT.new()
		icon.upgrade = u
		icon.icon_size = 28.0
		icon.custom_minimum_size = Vector2(28, 28)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

		var name_box := VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rarity := str(u.get("rarity", "blue"))
		var rarity_color := Color(str(GameConfig.get_upgrade_fx(rarity).get("color_hex", "#ffffff")))
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = _upgrade_name(u, id)
		name_label.modulate = rarity_color
		name_box.add_child(name_label)
		var tier_label := Label.new()
		tier_label.name = "TierLabel"
		tier_label.text = _rarity_label(rarity)
		tier_label.add_theme_font_size_override("font_size", 11)
		tier_label.modulate = Color(0.72, 0.78, 0.86)
		name_box.add_child(tier_label)
		row.add_child(name_box)

		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(34, 34)
		minus.pressed.connect(func(): _adjust_debug_upgrade(id, -1))
		row.add_child(minus)

		var level_label := Label.new()
		level_label.custom_minimum_size = Vector2(28, 0)
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_label.text = str(int(debug_upgrade_levels.get(id, 0)))
		level_label.set_meta("upgrade_id", id)
		row.add_child(level_label)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 34)
		plus.pressed.connect(func(): _adjust_debug_upgrade(id, 1))
		row.add_child(plus)

		_upgrades_list.add_child(row)

	PixelUi.apply_ui_font_tree(_upgrades_list)


func _upgrade_name(u: Dictionary, fallback_id: String) -> String:
	var localized := LanguageManager.localize(u, "name")
	if localized == "":
		return fallback_id
	return localized


func _rarity_label(rarity: String) -> String:
	# rarity 是 "white"/"blue"/"purple"/"orange"，对应 UI_RARITY_WHITE/...
	var key := "UI_RARITY_" + rarity.to_upper()
	return LanguageManager.tr_ui(key, str(GameConfig.get_upgrade_fx(rarity).get("name_cn", rarity)))


func _refresh_upgrade_row_texts() -> void:
	# 切换语言后刷新已构建的 upgrade rows
	if _upgrades_list == null:
		return
	for row in _upgrades_list.get_children():
		if not (row is HBoxContainer) or not row.has_meta("upgrade_id"):
			continue
		var id := str(row.get_meta("upgrade_id"))
		var u := GameConfig.get_upgrade(id)
		var name_label := row.find_child("NameLabel", true, false) as Label
		var tier_label := row.find_child("TierLabel", true, false) as Label
		if name_label:
			name_label.text = _upgrade_name(u, id)
		if tier_label:
			tier_label.text = _rarity_label(str(u.get("rarity", "blue")))


func _adjust_debug_upgrade(id: String, delta: int) -> void:
	var def := GameConfig.get_upgrade(id)
	var max_lv := int(def.get("max_level", 9))
	debug_upgrade_levels[id] = clampi(int(debug_upgrade_levels.get(id, 0)) + delta, 0, max_lv)
	if _upgrades_list:
		for row in _upgrades_list.get_children():
			for child in row.get_children():
				if child is Label and child.has_meta("upgrade_id") and str(child.get_meta("upgrade_id")) == id:
					child.text = str(int(debug_upgrade_levels.get(id, 0)))


func _adjust_debug_level(delta: int) -> void:
	debug_level = clampi(debug_level + delta, 1, 30)
	_sync_debug_labels()


func _adjust_debug_stage(delta: int) -> void:
	var max_stage := maxi(1, GameConfig.stages.size())
	debug_stage = clampi(debug_stage + delta, 1, max_stage)
	_sync_debug_labels()


func _adjust_debug_wood(delta: int) -> void:
	debug_wood = clampi(debug_wood + delta, 0, 99999)
	LobbyState.set_wood(debug_wood)
	_sync_debug_labels()


func _zero_debug_wood() -> void:
	debug_wood = 0
	LobbyState.set_wood(0)
	_sync_debug_labels()


func _apply_debug_upgrades() -> void:
	if battle and battle.player:
		battle.player.rebuild_upgrades_from_stacks(debug_upgrade_levels, false)


func _apply_debug() -> void:
	if battle:
		if battle.player:
			battle.player.rebuild_upgrades_from_stacks(debug_upgrade_levels, true)
		battle.apply_debug_settings(debug_level, debug_stage - 1)
	close_menu()
	if battle:
		battle.resume_from_pause()


func _apply_enter_build_house() -> void:
	if battle == null:
		return
	if battle.player:
		battle.player.rebuild_upgrades_from_stacks(debug_upgrade_levels, true)
	battle.enter_build_house_debug(debug_stage - 1)
	close_menu()


func _on_resume_pressed() -> void:
	if battle:
		battle.resume_from_pause()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		match view:
			View.DEBUG_UPGRADES:
				_close_debug_upgrades()
			View.DEBUG:
				_close_debug()
			_:
				_on_resume_pressed()
		get_viewport().set_input_as_handled()
