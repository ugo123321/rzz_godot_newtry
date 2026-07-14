extends Control
class_name SkillStonePanelView

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")
const DescFormat := preload("res://scripts/utils/desc_format.gd")
const BAG_SLOT_SCENE := preload("res://scenes/ui/bag_slot.tscn")

const BAG_COLUMNS := 5
const BAG_VISIBLE_ROWS := 4
const BAG_BASE_SLOTS := BAG_COLUMNS * BAG_VISIBLE_ROWS
const EQUIP_SLOT_COUNT := 3

signal closed

@onready var _stone_slots: Array[TextureButton] = []
@onready var _bag_grid: GridContainer = %BagGrid
@onready var _bag_scroll: ScrollContainer = $BagScroll
@onready var _back_button: TextureButton = %BackButton
@onready var _decompose_btn: Button = %DecomposeBtn
@onready var _confirm_btn: Button = %ConfirmBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _affix_total_rt: RichTextLabel = %AffixTotalRT
@onready var _equipped_skills_rt: RichTextLabel = %EquippedSkillsRT
@onready var _fly_layer: Control = %FlyLayer
@onready var _toast: Label = %Toast

var _icon_cache: Dictionary = {}
var _bag_slot_uids: Array[int] = []
var _multi_select := false
var _selected_uids: Dictionary = {}   # uid(int) -> true

var _detail_popup: PopupPanel = null
var _detail_icon_rect: TextureRect = null
var _detail_name_label: Label = null
var _detail_quality_label: Label = null
var _detail_skill_rt: RichTextLabel = null
var _detail_affix_rt: RichTextLabel = null
var _detail_action_btn: Button = null
var _detail_close_btn: Button = null
var _detail_uid: int = -1
var _detail_slot: int = -1   # -1 = 来自背包（action=装备）；>=0 = 已装备槽（action=卸下）

var _toast_timer := 0.0
var _toast_duration := 1.9
var _toast_base_top := 150.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stone_slots = [%StoneSlot0, %StoneSlot1, %StoneSlot2]
	for i in range(EQUIP_SLOT_COUNT):
		var btn := _stone_slots[i]
		if btn != null:
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			btn.pressed.connect(_on_stone_slot_pressed.bind(i))
	if _back_button != null:
		_back_button.pressed.connect(_on_back_pressed)
	if _decompose_btn != null:
		_decompose_btn.pressed.connect(_on_decompose_pressed)
	if _confirm_btn != null:
		_confirm_btn.pressed.connect(_on_confirm_decompose_pressed)
	if _cancel_btn != null:
		_cancel_btn.pressed.connect(_on_cancel_decompose_pressed)

	PixelUi.apply_ui_font_tree(self)
	_apply_pixel_filter_tree(self)

	# InfoPanel 背景样式
	var info_panel := get_node_or_null("InfoPanel") as Panel
	if info_panel != null:
		info_panel.add_theme_stylebox_override("panel", UiStyle.make_dialog_stylebox(Color(0.18, 0.14, 0.10, 0.92), 16))
	# 动作按钮样式
	if _decompose_btn != null:
		UiStyle.apply_primary_button(_decompose_btn, Color("#c84040"), 10)   # 红：分解
	if _confirm_btn != null:
		UiStyle.apply_primary_button(_confirm_btn, Color("#efb840"), 10)      # 金：确认分解
	if _cancel_btn != null:
		UiStyle.apply_primary_button(_cancel_btn, Color(0.55, 0.60, 0.78), 10)  # 蓝灰：取消

	_build_detail_popup()

	if EventBus:
		EventBus.skill_stones_changed.connect(_on_skill_stones_changed)
		EventBus.gold_changed.connect(_on_gold_changed)
		EventBus.language_changed.connect(_on_language_changed)

	_apply_static_texts()
	_refresh()
	set_process(true)


func _exit_tree() -> void:
	if EventBus:
		if EventBus.skill_stones_changed.is_connected(_on_skill_stones_changed):
			EventBus.skill_stones_changed.disconnect(_on_skill_stones_changed)
		if EventBus.language_changed.is_connected(_on_language_changed):
			EventBus.language_changed.disconnect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	_apply_static_texts()
	_refresh()
	if _detail_popup != null and _detail_popup.visible:
		_open_detail(_detail_uid, _detail_slot)


func _on_skill_stones_changed() -> void:
	_refresh()


func _on_gold_changed(_v: int) -> void:
	# 金币变化时刷新分解确认按钮的预估金币
	_refresh_action_buttons()


func _apply_static_texts() -> void:
	var title := get_node_or_null("HeaderBoard/Title") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_SKILL_STONE_TITLE")
	var at := get_node_or_null("InfoPanel/VBox/AffixTitleLabel") as Label
	if at != null:
		at.text = LanguageManager.tr_ui("UI_SKILL_STONE_AFFIX_TOTAL")
	var st := get_node_or_null("InfoPanel/VBox/SkillsTitleLabel") as Label
	if st != null:
		st.text = LanguageManager.tr_ui("UI_SKILL_STONE_EQUIPPED_SKILLS")
	if _decompose_btn != null:
		_decompose_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_DECOMPOSE")
	if _cancel_btn != null:
		_cancel_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_CANCEL")
	if _detail_action_btn != null:
		_refresh_detail_action_text()
	if _detail_close_btn != null:
		_detail_close_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_CLOSE")


func _apply_pixel_filter_tree(root: Node) -> void:
	if root is CanvasItem:
		var ci := root as CanvasItem
		if str(root.name) == "ItemIcon":
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in root.get_children():
		_apply_pixel_filter_tree(child)


func _on_back_pressed() -> void:
	closed.emit()
	queue_free()


# ─── 刷新 ─────────────────────────────────────────────────
func _refresh() -> void:
	_refresh_equipped_slots()
	_refresh_bag()
	_refresh_info_panel()
	_refresh_action_buttons()


func _refresh_equipped_slots() -> void:
	var equipped := LobbyState.get_equipped_skill_stones()
	# equipped 数组按槽顺序（get_equipped_skill_stones 遍历 skill_stone_equipped）
	var by_slot: Dictionary = {}
	for i in range(LobbyState.skill_stone_equipped.size()):
		var uid := int(LobbyState.skill_stone_equipped[i])
		if uid >= 0:
			by_slot[i] = uid
	for i in range(EQUIP_SLOT_COUNT):
		var btn := _stone_slots[i]
		if btn == null:
			continue
		var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
		if not by_slot.has(i):
			_set_slot_visual(btn, null, 0, false)
			continue
		var uid := int(by_slot[i])
		var stone := LobbyState.get_skill_stone_by_uid(uid)
		if stone.is_empty():
			_set_slot_visual(btn, null, 0, false)
			continue
		_set_slot_visual(btn, _get_stone_icon(stone), int(stone.get("quality", 0)), true)


func _set_slot_visual(btn: TextureButton, tex: Texture2D, quality: int, has_item: bool) -> void:
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = tex
		icon_rect.visible = tex != null
	btn.self_modulate = LobbyState.get_quality_color(quality) if has_item else Color.WHITE


func _refresh_bag() -> void:
	if _bag_grid == null:
		return
	var inventory := LobbyState.get_skill_stone_inventory_sorted()
	var slot_count := maxi(BAG_BASE_SLOTS, inventory.size())
	_ensure_bag_slot_count(slot_count)
	_bag_slot_uids.resize(slot_count)
	for i in range(slot_count):
		var btn := _bag_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		if i >= inventory.size():
			_bag_slot_uids[i] = -1
			_set_slot_visual(btn, null, 0, false)
			btn.modulate = Color(1, 1, 1, 1)
			continue
		var stone: Dictionary = inventory[i]
		var uid := int(stone.get("uid", -1))
		_bag_slot_uids[i] = uid
		var quality := int(stone.get("quality", 0))
		_set_slot_visual(btn, _get_stone_icon(stone), quality, true)
		if _multi_select and _selected_uids.has(uid):
			btn.modulate = Color(1.0, 0.85, 0.4, 1.0)   # 选中：金色调
		else:
			btn.modulate = Color(1, 1, 1, 1)


func _ensure_bag_slot_count(count: int) -> void:
	if _bag_grid == null:
		return
	while _bag_grid.get_child_count() < count:
		var index := _bag_grid.get_child_count()
		var btn := BAG_SLOT_SCENE.instantiate() as TextureButton
		if btn == null:
			break
		btn.name = "BagSlot%02d" % index
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		btn.pressed.connect(_on_bag_slot_pressed.bind(index))
		_bag_grid.add_child(btn)
	while _bag_grid.get_child_count() > count:
		_bag_grid.get_child(_bag_grid.get_child_count() - 1).queue_free()


func _refresh_info_panel() -> void:
	# 词条总和（3 个已装备 stone 的 affix 求和）
	var totals: Dictionary = LobbyState.get_skill_stone_affix_totals()
	var display: Dictionary = GameConfig.get_skill_stone_affix_display()
	var order: Array = GameConfig.get_skill_stone_rules().get("affix_stats", [])
	var lines: Array[String] = []
	for stat_key in order:
		var s := str(stat_key)
		if not totals.has(s):
			continue
		var v := float(totals[s])
		if abs(v) < 0.0001:
			continue   # 0 不显示
		lines.append(_format_affix_line(s, v))
	# affix_stats 之外可能的 key（兜底）
	for s in totals.keys():
		if order.has(s):
			continue
		var v := float(totals[s])
		if abs(v) < 0.0001:
			continue
		lines.append(_format_affix_line(str(s), v))
	var affix_text := "\n".join(lines) if not lines.is_empty() else LanguageManager.tr_ui("UI_SKILL_STONE_NO_AFFIX")
	DescFormat.apply_to_rich_text(_affix_total_rt, affix_text, 16, false)

	# 已装备技能列表
	var equipped := LobbyState.get_equipped_skill_stones()
	var skill_lines: Array[String] = []
	for stone in equipped:
		var nm := LobbyState.get_skill_stone_name(stone)
		if nm == "":
			nm = str(stone.get("skill_id", ""))
		skill_lines.append("• " + nm)
	_equipped_skills_rt.text = ("\n".join(skill_lines)) if not skill_lines.is_empty() else LanguageManager.tr_ui("UI_SKILL_STONE_NO_STONE_EQUIPPED")


func _format_affix_line(stat_key: String, value: float) -> String:
	var pct := int(round(value * 100.0))
	var sign := "+" if pct >= 0 else "-"
	return "%s %s%d%%" % [_affix_name(stat_key), sign, abs(pct)]


func _affix_name(stat_key: String) -> String:
	var display: Dictionary = GameConfig.get_skill_stone_affix_display()
	var d: Dictionary = display.get(stat_key, {})
	var nm := LanguageManager.localize_field(d, "name_en", "name_cn")
	if nm == "":
		nm = str(stat_key)
	return nm


func _refresh_action_buttons() -> void:
	var normal_mode := not _multi_select
	if _decompose_btn != null:
		_decompose_btn.visible = normal_mode
	if _confirm_btn != null:
		_confirm_btn.visible = not normal_mode
	if _cancel_btn != null:
		_cancel_btn.visible = not normal_mode
	if not normal_mode and _confirm_btn != null:
		var gold := _estimate_decompose_gold()
		_confirm_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_DECOMPOSE_FMT") % gold
		_confirm_btn.disabled = _selected_uids.is_empty()
		_confirm_btn.modulate = Color(1, 1, 1, 1) if not _selected_uids.is_empty() else Color(0.6, 0.6, 0.6, 1)


func _estimate_decompose_gold() -> int:
	var total := 0
	for uid in _selected_uids.keys():
		var stone := LobbyState.get_skill_stone_by_uid(int(uid))
		if stone.is_empty():
			continue
		total += LobbyState.get_skill_stone_decompose_gold(stone)
	return total


# ─── 交互 ─────────────────────────────────────────────────
func _on_stone_slot_pressed(slot: int) -> void:
	if slot < 0 or slot >= EQUIP_SLOT_COUNT:
		return
	var uid := int(LobbyState.skill_stone_equipped[slot]) if slot < LobbyState.skill_stone_equipped.size() else -1
	if uid < 0:
		return
	_open_detail(uid, slot)


func _on_bag_slot_pressed(slot_index: int) -> void:
	if _bag_scroll is SpringScrollContainer and (_bag_scroll as SpringScrollContainer).was_scroll_gesture():
		return
	if slot_index < 0 or slot_index >= _bag_slot_uids.size():
		return
	var uid := int(_bag_slot_uids[slot_index])
	if uid < 0:
		return
	if _multi_select:
		if _selected_uids.has(uid):
			_selected_uids.erase(uid)
		else:
			_selected_uids[uid] = true
		_refresh_bag()
		_refresh_action_buttons()
	else:
		_open_detail(uid, -1)


func _on_decompose_pressed() -> void:
	_multi_select = true
	_selected_uids.clear()
	_refresh_bag()
	_refresh_action_buttons()
	_show_toast(LanguageManager.tr_ui("UI_SKILL_STONE_MULTI_SELECT_HINT"))


func _on_confirm_decompose_pressed() -> void:
	if _selected_uids.is_empty():
		return
	var uids: Array = []
	for k in _selected_uids.keys():
		uids.append(int(k))
	var gained := LobbyState.decompose_skill_stones(uids)
	_multi_select = false
	_selected_uids.clear()
	if gained > 0:
		_show_toast(LanguageManager.tr_ui("UI_SKILL_STONE_DECOMPOSE_OK_FMT") % gained)
	_refresh()
	_refresh_action_buttons()


func _on_cancel_decompose_pressed() -> void:
	_multi_select = false
	_selected_uids.clear()
	_refresh_bag()
	_refresh_action_buttons()


# ─── 详情弹窗 ─────────────────────────────────────────────
func _build_detail_popup() -> void:
	var popup := PopupPanel.new()
	popup.name = "DetailPopup"
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 12)
	vbox.add_child(head)

	var icon_rect := TextureRect.new()
	icon_rect.name = "DetailIcon"
	icon_rect.custom_minimum_size = Vector2(64, 64)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(icon_rect)

	var head_col := VBoxContainer.new()
	head_col.name = "HeadCol"
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 2)
	head.add_child(head_col)

	var name_label := Label.new()
	name_label.name = "DetailName"
	name_label.add_theme_font_size_override("font_size", 22)
	head_col.add_child(name_label)

	var quality_label := Label.new()
	quality_label.name = "DetailQuality"
	quality_label.add_theme_font_size_override("font_size", 16)
	head_col.add_child(quality_label)

	var skill_rt := RichTextLabel.new()
	skill_rt.name = "DetailSkillRT"
	skill_rt.bbcode_enabled = true
	skill_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_rt.custom_minimum_size = Vector2(380, 70)
	skill_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(skill_rt)

	var affix_rt := RichTextLabel.new()
	affix_rt.name = "DetailAffixRT"
	affix_rt.bbcode_enabled = true
	affix_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	affix_rt.custom_minimum_size = Vector2(380, 60)
	affix_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(affix_rt)

	var action_row := HBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	vbox.add_child(action_row)

	var action_btn := Button.new()
	action_btn.name = "ActionBtn"
	action_btn.custom_minimum_size = Vector2(150, 52)
	action_row.add_child(action_btn)

	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.custom_minimum_size = Vector2(120, 52)
	action_row.add_child(close_btn)

	popup.wrap_controls = true
	add_child(popup)

	_detail_popup = popup
	_detail_icon_rect = icon_rect
	_detail_name_label = name_label
	_detail_quality_label = quality_label
	_detail_skill_rt = skill_rt
	_detail_affix_rt = affix_rt
	_detail_action_btn = action_btn
	_detail_close_btn = close_btn

	UiStyle.apply_primary_button(action_btn, Color("#4dd07a"), 10)
	UiStyle.apply_primary_button(close_btn, Color(0.55, 0.60, 0.78), 10)
	popup.add_theme_stylebox_override("panel", UiStyle.make_dialog_stylebox(Color(0.18, 0.14, 0.10, 0.97), 18))

	action_btn.pressed.connect(_on_detail_action_pressed)
	close_btn.pressed.connect(_close_detail)


func _open_detail(uid: int, slot: int) -> void:
	if _detail_popup == null:
		return
	var stone := LobbyState.get_skill_stone_by_uid(uid)
	if stone.is_empty():
		return
	_detail_uid = uid
	_detail_slot = slot
	var icon := _get_stone_icon(stone)
	if _detail_icon_rect != null:
		_detail_icon_rect.texture = icon
		_detail_icon_rect.visible = icon != null
	if _detail_name_label != null:
		_detail_name_label.text = LobbyState.get_skill_stone_name(stone)
	if _detail_quality_label != null:
		var q := int(stone.get("quality", 0))
		_detail_quality_label.text = LobbyState.get_quality_name(q)
		_detail_quality_label.modulate = LobbyState.get_quality_color(q)
	# 技能描述（= 对应升级奖励的游戏内描述）
	if _detail_skill_rt != null:
		DescFormat.apply_to_rich_text(_detail_skill_rt, LobbyState.get_skill_stone_desc(stone), 16, false)
	# 属性词条
	if _detail_affix_rt != null:
		var affixes = stone.get("affixes", [])
		var lines: Array[String] = []
		if typeof(affixes) == TYPE_ARRAY:
			for a in affixes:
				if typeof(a) != TYPE_DICTIONARY:
					continue
				lines.append(_format_affix_line(str(a.get("stat_key", "")), float(a.get("value", 0.0))))
		var txt := "\n".join(lines) if not lines.is_empty() else LanguageManager.tr_ui("UI_SKILL_STONE_NO_AFFIX")
		DescFormat.apply_to_rich_text(_detail_affix_rt, txt, 16, false)
	_refresh_detail_action_text()
	_detail_popup.popup_centered(Vector2i(440, 360))


func _refresh_detail_action_text() -> void:
	if _detail_action_btn == null:
		return
	if _detail_slot >= 0:
		_detail_action_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_UNEQUIP")
	else:
		_detail_action_btn.text = LanguageManager.tr_ui("UI_SKILL_STONE_EQUIP")


func _on_detail_action_pressed() -> void:
	if _detail_uid < 0:
		return
	if _detail_slot >= 0:
		LobbyState.unequip_skill_stone(_detail_slot)
		_show_toast(LanguageManager.tr_ui("UI_SKILL_STONE_UNEQUIP_OK"))
	else:
		var slot := LobbyState.equip_skill_stone(_detail_uid)
		if slot >= 0:
			_show_toast(LanguageManager.tr_ui("UI_SKILL_STONE_EQUIP_OK"))
		else:
			_show_toast(LanguageManager.tr_ui("UI_SKILL_STONE_EQUIP_FAIL"))
	_close_detail()
	_refresh()


func _close_detail() -> void:
	if _detail_popup != null:
		_detail_popup.hide()
	_detail_uid = -1
	_detail_slot = -1


# ─── 图标 / Toast ──────────────────────────────────────────
func _get_stone_icon(stone: Dictionary) -> Texture2D:
	var path := LobbyState.get_skill_stone_icon_path(stone)
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_icon_cache[path] = tex
	return tex


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast.modulate = Color("#fff4be")
	_toast.scale = Vector2(0.86, 0.86)
	_toast.offset_top = _toast_base_top + 10.0
	_toast.offset_bottom = _toast_base_top + 52.0
	_toast_timer = _toast_duration
	var tween := create_tween()
	tween.tween_property(_toast, "scale", Vector2(1.04, 1.04), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_toast, "scale", Vector2(1.0, 1.0), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if _toast != null and _toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
		else:
			var life_t := clampf(_toast_timer / _toast_duration, 0.0, 1.0)
			var alpha := life_t
			if life_t > 0.65:
				alpha = clampf((1.0 - life_t) / 0.35, 0.0, 1.0)
			alpha = maxf(alpha, life_t)
			_toast.modulate.a = alpha
