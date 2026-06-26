extends Control
class_name PauseMenu

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const PixelCardIconT = preload("res://scripts/ui/pixel_card_icon.gd")

enum View { PAUSE, DEBUG, DEBUG_UPGRADES }

var battle
var view := View.PAUSE
var debug_level := 1
var debug_stage := 1
var debug_wood := 0
var debug_upgrade_levels: Dictionary = {}
var _level_label: Label
var _stage_label: Label
var _wood_label: Label
var _upgrades_list: VBoxContainer


func setup(battle_node) -> void:
	battle = battle_node
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


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
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.13, 0.96)
	panel_style.border_color = Color(0.78, 0.65, 0.34, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
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

	var title := Label.new()
	title.name = "Title"
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var pause_box := VBoxContainer.new()
	pause_box.name = "PauseBox"
	pause_box.add_theme_constant_override("separation", 12)
	root.add_child(pause_box)

	var resume_btn := Button.new()
	resume_btn.text = "继续游戏"
	resume_btn.custom_minimum_size = Vector2(0, 60)
	resume_btn.pressed.connect(_on_resume_pressed)
	pause_box.add_child(resume_btn)

	var debug_btn := Button.new()
	debug_btn.text = "调试"
	debug_btn.custom_minimum_size = Vector2(0, 60)
	debug_btn.pressed.connect(_open_debug)
	pause_box.add_child(debug_btn)

	var hint := Label.new()
	hint.text = "按 Esc 也可继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.8, 0.8, 0.8)
	pause_box.add_child(hint)

	var debug_box := VBoxContainer.new()
	debug_box.name = "DebugBox"
	debug_box.visible = false
	debug_box.add_theme_constant_override("separation", 8)
	root.add_child(debug_box)

	var lv_row := HBoxContainer.new()
	debug_box.add_child(lv_row)
	var lv_minus := Button.new()
	lv_minus.text = "Lv-"
	lv_minus.pressed.connect(func(): _adjust_debug_level(-1))
	lv_row.add_child(lv_minus)
	var lv_label := Label.new()
	lv_label.name = "LevelLabel"
	lv_label.text = "等级: 1"
	lv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_row.add_child(lv_label)
	_level_label = lv_label
	var lv_plus := Button.new()
	lv_plus.text = "Lv+"
	lv_plus.pressed.connect(func(): _adjust_debug_level(1))
	lv_row.add_child(lv_plus)

	var st_row := HBoxContainer.new()
	debug_box.add_child(st_row)
	var st_minus := Button.new()
	st_minus.text = "关-"
	st_minus.pressed.connect(func(): _adjust_debug_stage(-1))
	st_row.add_child(st_minus)
	var st_label := Label.new()
	st_label.name = "StageLabel"
	st_label.text = "关卡: 1"
	st_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_row.add_child(st_label)
	_stage_label = st_label
	var st_plus := Button.new()
	st_plus.text = "关+"
	st_plus.pressed.connect(func(): _adjust_debug_stage(1))
	st_row.add_child(st_plus)

	var wd_row := HBoxContainer.new()
	debug_box.add_child(wd_row)
	var wd_minus := Button.new()
	wd_minus.text = "木-10"
	wd_minus.pressed.connect(func(): _adjust_debug_wood(-10))
	wd_row.add_child(wd_minus)
	var wd_label := Label.new()
	wd_label.name = "WoodLabel"
	wd_label.text = "木材: 0"
	wd_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wd_row.add_child(wd_label)
	_wood_label = wd_label
	var wd_plus := Button.new()
	wd_plus.text = "木+10"
	wd_plus.pressed.connect(func(): _adjust_debug_wood(10))
	wd_row.add_child(wd_plus)

	var wd_quick_row := HBoxContainer.new()
	debug_box.add_child(wd_quick_row)
	var wd_plus_50 := Button.new()
	wd_plus_50.text = "+50"
	wd_plus_50.pressed.connect(func(): _adjust_debug_wood(50))
	wd_quick_row.add_child(wd_plus_50)
	var wd_plus_100 := Button.new()
	wd_plus_100.text = "+100"
	wd_plus_100.pressed.connect(func(): _adjust_debug_wood(100))
	wd_quick_row.add_child(wd_plus_100)
	var wd_zero := Button.new()
	wd_zero.text = "清零"
	wd_zero.pressed.connect(_zero_debug_wood)
	wd_quick_row.add_child(wd_zero)

	var upgrades_btn := Button.new()
	upgrades_btn.text = "升级奖励"
	upgrades_btn.pressed.connect(_open_debug_upgrades)
	debug_box.add_child(upgrades_btn)

	var apply_btn := Button.new()
	apply_btn.text = "应用并跳关"
	apply_btn.pressed.connect(_apply_debug)
	debug_box.add_child(apply_btn)

	var enter_house_btn := Button.new()
	enter_house_btn.text = "直接进入盖房子阶段"
	enter_house_btn.pressed.connect(_apply_enter_build_house)
	debug_box.add_child(enter_house_btn)

	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.pressed.connect(_close_debug)
	debug_box.add_child(back_btn)

	var upgrades_box := VBoxContainer.new()
	upgrades_box.name = "UpgradesBox"
	upgrades_box.visible = false
	upgrades_box.add_theme_constant_override("separation", 8)
	root.add_child(upgrades_box)

	var upgrades_hint := Label.new()
	upgrades_hint.text = "点击 +/- 调整各强化等级"
	upgrades_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrades_hint.add_theme_font_size_override("font_size", 12)
	upgrades_hint.modulate = Color(0.78, 0.78, 0.78)
	upgrades_box.add_child(upgrades_hint)

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

	var apply_upgrades_btn := Button.new()
	apply_upgrades_btn.text = "应用强化"
	apply_upgrades_btn.pressed.connect(_apply_debug_upgrades)
	upgrades_box.add_child(apply_upgrades_btn)

	var upgrades_back_btn := Button.new()
	upgrades_back_btn.text = "返回"
	upgrades_back_btn.pressed.connect(_close_debug_upgrades)
	upgrades_box.add_child(upgrades_back_btn)

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
	var title := vbox.get_node_or_null("Title") as Label
	if pause_box:
		pause_box.visible = view == View.PAUSE
	if debug_box:
		debug_box.visible = view == View.DEBUG
	if upgrades_box:
		upgrades_box.visible = view == View.DEBUG_UPGRADES
	if title:
		match view:
			View.DEBUG:
				title.text = "调试"
			View.DEBUG_UPGRADES:
				title.text = "升级奖励"
			_:
				title.text = "暂停"


func _sync_debug_labels() -> void:
	if _level_label:
		_level_label.text = "等级: %d" % debug_level
	if _stage_label:
		_stage_label.text = "关卡: %d" % debug_stage
	if _wood_label:
		_wood_label.text = "木材: %d" % debug_wood


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
		name_label.text = str(u.get("name_cn", id))
		name_label.modulate = rarity_color
		name_box.add_child(name_label)
		var tier_label := Label.new()
		tier_label.text = str(GameConfig.get_upgrade_fx(rarity).get("name_cn", rarity))
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
