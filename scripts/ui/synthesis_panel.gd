extends Control
class_name SynthesisPanelView

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const BAG_SLOT_SCENE := preload("res://scenes/ui/bag_slot.tscn")

const SYNTH_SLOT_COUNT := 3
const BAG_COLUMNS := 5
const BAG_VISIBLE_ROWS := 4
const BAG_BASE_SLOTS := BAG_COLUMNS * BAG_VISIBLE_ROWS

# ── 装备格子视觉（与 equipment_panel 一致：品质背景 + 部位徽章 + 等级文字）──
# 背包空槽框图（合成槽位保留自带 synthesis_slot.png 框图）
const BAG_SLOT_TEX := preload("res://assets/ui/equipment/equipment_slot02.png")
# 槽位品质背景：0 白 / 1 蓝 / 2 紫 / 3 橙
const SLOT_BG_TEX := {
	0: preload("res://assets/ui/equipment/slot_bg_white.png"),
	1: preload("res://assets/ui/equipment/slot_bg_blue.png"),
	2: preload("res://assets/ui/equipment/slot_bg_purple.png"),
	3: preload("res://assets/ui/equipment/slot_bg_orange.png"),
}
# 部位 icon：slot_key → sort_icon
const SORT_ICON_TEX := {
	"weapon": preload("res://assets/ui/equipment/sort_icon_sord.png"),
	"helmet": preload("res://assets/ui/equipment/sort_icon_helmet.png"),
	"necklace": preload("res://assets/ui/equipment/sort_icon_neckless.png"),
	"ring": preload("res://assets/ui/equipment/sort_icon_ring.png"),
	"armor": preload("res://assets/ui/equipment/sort_icon_armor.png"),
	"shoes": preload("res://assets/ui/equipment/sort_icon_boot.png"),
}
const SORT_BG_TEX := preload("res://assets/ui/equipment/sort_bg.png")
const SORT_BADGE_SIZE := 33
const SORT_ICON_INNER := 20
const LEVEL_FONT_SIZE := 18
# 合成槽(107×107) / 背包槽(126×126) 内 部位徽章 与 等级文字 相对槽位左上角偏移
const _EQUIP_SORT_OFFSET := Vector2(4, 4)
const _EQUIP_LEVEL_OFFSET := Vector2(62, 78)
const _BAG_SORT_OFFSET := Vector2(4, 4)
const _BAG_LEVEL_OFFSET := Vector2(77, 92)

# 进场淡入（参考 skill_stone_panel / equipment_panel）
const INTRO_STEP := 0.018      # 每个元素错峰间隔（秒）
const INTRO_DURATION := 0.22   # 单元素显形时长（秒）
const INTRO_SCALE_FROM := 0.82

signal closed

@onready var _target_slot: TextureButton = %TargetSlot
@onready var _compose_button: TextureButton = %ComposeButton
@onready var _bag_grid: GridContainer = %BagGrid
@onready var _bag_scroll: ScrollContainer = $BagScroll
@onready var _back_button: TextureButton = %BackButton
@onready var _fly_layer: Control = %FlyLayer
@onready var _toast: Label = %Toast

var _material_slots: Array[TextureButton] = []

var _icon_cache: Dictionary = {}
var _synth_material_uids := [-1, -1, -1]
var _synth_target_def_id := ""
var _synth_target_quality := -1
var _synth_result_preview: Dictionary = {}
var _bag_slot_uids: Array[int] = []

var _toast_timer := 0.0
var _toast_duration := 1.9
var _toast_base_top := 150.0

var _intro_playing := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 根节点默认 LINEAR
	_material_slots = [%MaterialSlot0, %MaterialSlot1, %MaterialSlot2]
	for i in range(SYNTH_SLOT_COUNT):
		var slot_btn := _material_slots[i]
		if slot_btn != null:
			slot_btn.pressed.connect(_on_synth_material_slot_pressed.bind(i))
	if _compose_button != null:
		_compose_button.pressed.connect(_on_synth_compose_pressed)
	if _back_button != null:
		_back_button.pressed.connect(_on_back_pressed)

	PixelUi.apply_ui_font_tree(self)
	_apply_pixel_filter_tree(self)

	if EventBus:
		EventBus.equipment_changed.connect(_on_equipment_changed)
		EventBus.language_changed.connect(_on_language_changed)

	_apply_static_texts()
	_reset_state()
	_refresh_synthesis_view()
	set_process(true)
	# 进场动效：每次面板可见时所有区块快速依次淡入显形
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()   # 首次若已可见则立即播


func _on_language_changed(_lang: String) -> void:
	_apply_static_texts()
	_refresh_synthesis_view()


# ─── 进场动效：所有区块快速依次淡入显形（参考 skill_stone_panel）──
func _on_visibility_changed() -> void:
	if visible and not Engine.is_editor_hint():
		call_deferred("_play_intro")


func _play_intro() -> void:
	# 收集要"依次显形"的元素，按视觉从上到下排列（不含底部 HUD BottomBar）
	var elems: Array[Control] = []
	for p in [
		"TitleIcon", "Title", "DecoLine",
		"TargetSlot", "SynthPathDeco",
		"MaterialSlot0", "MaterialSlot1", "MaterialSlot2",
		"DecoLine02",
		"BagScroll", "ComposeButton",
	]:
		var c := get_node_or_null(p) as Control
		if c != null and c.visible:
			elems.append(c)
	if elems.is_empty():
		return
	_intro_playing = true
	# 起点：透明 + 轻微缩小（绕中心）
	for c in elems:
		c.modulate.a = 0.0
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(INTRO_SCALE_FROM, INTRO_SCALE_FROM)
	# 逐个错峰淡入 + 回弹归位
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(elems.size()):
		var c: Control = elems[i]
		var delay := INTRO_STEP * float(i)
		tw.tween_property(c, "modulate:a", 1.0, INTRO_DURATION).set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, INTRO_DURATION).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(Callable(self, "_on_intro_done"))


func _on_intro_done() -> void:
	_intro_playing = false


func _apply_static_texts() -> void:
	var title := get_node_or_null("%Title") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_SYNTH_TITLE")
	var compose_label := get_node_or_null("%ComposeButton/Label") as Label
	if compose_label != null:
		compose_label.text = LanguageManager.tr_ui("UI_SYNTH_TITLE")
	if _toast != null:
		# Toast 默认文本回到"合成成功"占位，实际使用时仍由 _show_synth_toast 覆盖
		_toast.text = LanguageManager.tr_ui("UI_SYNTH_SUCCESS")


func _exit_tree() -> void:
	if EventBus and EventBus.equipment_changed.is_connected(_on_equipment_changed):
		EventBus.equipment_changed.disconnect(_on_equipment_changed)


func _reset_state() -> void:
	_synth_material_uids = [-1, -1, -1]
	_synth_target_def_id = ""
	_synth_target_quality = -1
	_synth_result_preview = {}


func _apply_pixel_filter_tree(root: Node) -> void:
	# 默认 LINEAR（抗锯齿），像素贴图（ItemIcon / 品质背景 / 部位徽章）保 NEAREST
	if root is CanvasItem:
		var ci := root as CanvasItem
		var n := str(root.name)
		if n == "ItemIcon" or n == "SlotBg" or n == "SortIconBg" or n == "SortIcon":
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in root.get_children():
		_apply_pixel_filter_tree(child)


# ── 装备格子视觉：品质背景 + 部位徽章 + 等级文字（与 equipment_panel 一致）──
func _ensure_slot_parts(btn: TextureButton) -> void:
	if btn.get_node_or_null("SlotBg") == null:
		var bg := TextureRect.new()
		bg.name = "SlotBg"
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.texture = SLOT_BG_TEX[0]
		btn.add_child(bg)
		btn.move_child(bg, 0)  # 索引 0 → 最底
	if btn.get_node_or_null("SortIconBg") == null:
		var sbg := TextureRect.new()
		sbg.name = "SortIconBg"
		sbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sbg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		sbg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sbg.stretch_mode = TextureRect.STRETCH_SCALE
		sbg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sbg.texture = SORT_BG_TEX
		sbg.custom_minimum_size = Vector2(SORT_BADGE_SIZE, SORT_BADGE_SIZE)
		sbg.size = Vector2(SORT_BADGE_SIZE, SORT_BADGE_SIZE)
		btn.add_child(sbg)
		var icon := TextureRect.new()
		icon.name = "SortIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_preset(Control.PRESET_CENTER)
		var half := SORT_ICON_INNER * 0.5
		icon.offset_left = -half
		icon.offset_top = -half
		icon.offset_right = half
		icon.offset_bottom = half
		sbg.add_child(icon)
	if btn.get_node_or_null("LevelLabel") == null:
		var lbl := Label.new()
		lbl.name = "LevelLabel"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", LEVEL_FONT_SIZE)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		lbl.add_theme_constant_override("shadow_outline_size", 4)
		lbl.add_theme_constant_override("shadow_offset_x", 2)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
		lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.add_child(lbl)


# 按品质切 SlotBg + 设部位 icon + 显示等级；空槽露出根框图、无徽章无等级
# is_bag：背包槽(true,126) / 合成槽(false,107) 偏移不同
func _apply_slot_visual(btn: TextureButton, quality: int, has_item: bool,
		slot_key: String, level: int, is_bag: bool) -> void:
	_ensure_slot_parts(btn)
	# 动态创建的背包槽未被 _apply_pixel_filter_tree 覆盖到，这里强制 ItemIcon 走 NEAREST 保持像素清晰
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect != null:
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var slot_bg := btn.get_node_or_null("SlotBg") as TextureRect
	var sort_bg_rect := btn.get_node_or_null("SortIconBg") as TextureRect
	var sort_icon: TextureRect = null
	if sort_bg_rect != null:
		sort_icon = sort_bg_rect.get_node_or_null("SortIcon") as TextureRect
	var level_lbl := btn.get_node_or_null("LevelLabel") as Label
	var sort_offset := _BAG_SORT_OFFSET if is_bag else _EQUIP_SORT_OFFSET
	var level_offset := _BAG_LEVEL_OFFSET if is_bag else _EQUIP_LEVEL_OFFSET
	btn.self_modulate = Color.WHITE
	# 品质背景：仅有装备时显示（盖住根框图）；空槽不显示，露出原框图
	var q := quality if has_item else 0
	if slot_bg != null:
		slot_bg.texture = SLOT_BG_TEX.get(q, SLOT_BG_TEX[0])
		slot_bg.visible = has_item
	# 部位徽章：仅有装备且 slot_key 有效时显示
	var show_sort := slot_key != "" and has_item
	if sort_bg_rect != null:
		sort_bg_rect.visible = show_sort
		if show_sort:
			sort_bg_rect.offset_left = sort_offset.x
			sort_bg_rect.offset_top = sort_offset.y
			sort_bg_rect.offset_right = sort_offset.x + SORT_BADGE_SIZE
			sort_bg_rect.offset_bottom = sort_offset.y + SORT_BADGE_SIZE
			if sort_icon != null:
				sort_icon.texture = SORT_ICON_TEX.get(slot_key, null)
				sort_icon.visible = sort_icon.texture != null
	# 等级文字：仅有装备且 level>0 时显示
	if level_lbl != null:
		if has_item and level > 0:
			level_lbl.text = "LV.%d" % level
			level_lbl.visible = true
			level_lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
			level_lbl.offset_left = level_offset.x
			level_lbl.offset_top = level_offset.y
			level_lbl.offset_right = level_offset.x
			level_lbl.offset_bottom = level_offset.y
			level_lbl.grow_horizontal = Control.GROW_DIRECTION_END
			level_lbl.grow_vertical = Control.GROW_DIRECTION_END
		else:
			level_lbl.visible = false


func _on_equipment_changed() -> void:
	_refresh_synthesis_view()


func _on_back_pressed() -> void:
	closed.emit()
	queue_free()


func _refresh_synthesis_view() -> void:
	_rebuild_synth_target_from_materials()
	_recompute_synth_result_preview()
	_refresh_synthesis_slots()
	_refresh_synthesis_bag()
	_refresh_synthesis_compose_state()


func _set_slot_icon(slot: Control, tex: Texture2D, mod: Color) -> void:
	if slot == null:
		return
	var icon := slot.get_node_or_null("ItemIcon") as TextureRect
	if icon == null:
		return
	icon.texture = tex
	icon.visible = tex != null
	icon.modulate = mod


func _refresh_synthesis_slots() -> void:
	_refresh_synthesis_result_slot()
	for i in range(SYNTH_SLOT_COUNT):
		var slot_btn := _material_slots[i]
		var uid := int(_synth_material_uids[i])
		if uid >= 0:
			var item := LobbyState.get_item_by_uid(uid)
			if item.is_empty():
				_synth_material_uids[i] = -1
				_refresh_synthesis_slots()
				return
			# 有材料：品质背景 + 部位徽章 + 等级（合成槽 107×107 偏移）
			_apply_slot_visual(slot_btn, int(item.get("quality", 0)), true,
					str(item.get("slot", "")), int(item.get("level", 1)), false)
			_set_slot_icon(slot_btn, _get_item_icon(item), Color.WHITE)
			continue
		# 空槽：露出 synthesis_slot 框图
		_apply_slot_visual(slot_btn, 0, false, "", 0, false)
		if _has_synth_target():
			var ghost_item := {"def_id": _synth_target_def_id}
			_set_slot_icon(slot_btn, _get_item_icon(ghost_item), Color(1, 1, 1, 0.35))
		else:
			_set_slot_icon(slot_btn, null, Color(1, 1, 1, 1))


func _refresh_synthesis_result_slot() -> void:
	if _synth_result_preview.is_empty():
		_apply_slot_visual(_target_slot, 0, false, "", 0, false)
		_set_slot_icon(_target_slot, null, Color(1, 1, 1, 1))
		return
	# 结果预览：品质背景 + 等级（slot_key 空 → 不显示部位徽章，结果部位由材料决定）
	_apply_slot_visual(_target_slot,
			int(_synth_result_preview.get("quality", 0)), true,
			"", int(_synth_result_preview.get("level", 1)), false)
	_set_slot_icon(_target_slot, _get_item_icon(_synth_result_preview), Color.WHITE)


func _ensure_bag_slot_count(count: int) -> void:
	if _bag_grid == null:
		return
	while _bag_grid.get_child_count() < count:
		var index := _bag_grid.get_child_count()
		var btn := BAG_SLOT_SCENE.instantiate() as TextureButton
		if btn == null:
			break
		btn.name = "BagSlot%02d" % index
		# 背包空槽框图；有装备时 SlotBg 子节点按品质铺背景盖住
		btn.texture_normal = BAG_SLOT_TEX
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		btn.pressed.connect(_on_bag_slot_pressed.bind(index))
		_bag_grid.add_child(btn)
	while _bag_grid.get_child_count() > count:
		var extra := _bag_grid.get_child(_bag_grid.get_child_count() - 1)
		# remove_child 立即摘除（get_child_count 同步下降），
		# queue_free 延迟到帧末——只 queue_free 不 remove_child 会死循环。
		_bag_grid.remove_child(extra)
		extra.queue_free()


func _refresh_synthesis_bag() -> void:
	if _bag_grid == null:
		return
	var inventory := LobbyState.get_inventory_sorted()
	var slot_count := maxi(BAG_BASE_SLOTS, inventory.size())
	_ensure_bag_slot_count(slot_count)
	_bag_slot_uids.resize(slot_count)
	var has_empty_slot := _first_empty_synth_slot() >= 0
	for i in range(slot_count):
		var btn := _bag_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		if i >= inventory.size():
			_bag_slot_uids[i] = -1
			_apply_slot_visual(btn, 0, false, "", 0, true)
			_set_slot_icon(btn, null, Color(1, 1, 1, 1))
			btn.modulate = Color(1, 1, 1, 1)
			continue
		var item: Dictionary = inventory[i]
		var uid := int(item.get("uid", -1))
		_bag_slot_uids[i] = uid
		var quality := int(item.get("quality", 0))
		var already_selected := _is_uid_in_synth_materials(uid)
		var compatible := has_empty_slot and (not already_selected) and _is_item_compatible_for_current_target(item)
		# 品质背景 + 部位徽章 + 等级（背包槽 126×126 偏移）
		_apply_slot_visual(btn, quality, true,
				str(item.get("slot", "")), int(item.get("level", 1)), true)
		_set_slot_icon(btn, _get_item_icon(item), Color.WHITE)
		if already_selected:
			btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
		elif compatible:
			btn.modulate = Color(1, 1, 1, 1)
		else:
			btn.modulate = Color(0.46, 0.46, 0.46, 1.0)


func _refresh_synthesis_compose_state() -> void:
	if _compose_button == null:
		return
	var can_compose := not _synth_result_preview.is_empty()
	_compose_button.disabled = not can_compose
	_compose_button.modulate = Color(1, 1, 1, 1) if can_compose else Color(0.6, 0.6, 0.6, 1.0)


func _on_bag_slot_pressed(slot_index: int) -> void:
	if _bag_scroll is SpringScrollContainer and (_bag_scroll as SpringScrollContainer).was_scroll_gesture():
		return
	if slot_index < 0 or slot_index >= _bag_slot_uids.size():
		return
	var uid := int(_bag_slot_uids[slot_index])
	if uid < 0:
		return
	var item := LobbyState.get_item_by_uid(uid)
	if item.is_empty():
		return
	if _is_uid_in_synth_materials(uid):
		return
	if not _is_item_compatible_for_current_target(item):
		return
	var target_slot := _first_empty_synth_slot()
	if target_slot < 0:
		return
	_synth_material_uids[target_slot] = uid
	_rebuild_synth_target_from_materials()
	var source_btn := _bag_grid.get_child(slot_index) as Control
	_play_synth_fly_icon(item, source_btn, _material_slots[target_slot])
	_refresh_synthesis_view()


func _on_synth_material_slot_pressed(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= SYNTH_SLOT_COUNT:
		return
	if int(_synth_material_uids[slot_idx]) < 0:
		return
	_synth_material_uids[slot_idx] = -1
	_rebuild_synth_target_from_materials()
	_recompute_synth_result_preview()
	_refresh_synthesis_view()


func _on_synth_compose_pressed() -> void:
	if _synth_result_preview.is_empty():
		return
	var uids := []
	for uid in _synth_material_uids:
		uids.append(int(uid))
	var result := LobbyState.compose_three_items(uids)
	if result.is_empty():
		_refresh_synthesis_view()
		return
	_reset_state()
	_show_synth_toast(LanguageManager.tr_ui("UI_SYNTH_TOAST_FMT") % [
		LobbyState.get_item_name(result),
		int(result.get("level", 1)),
	])
	_refresh_synthesis_view()


func _rebuild_synth_target_from_materials() -> void:
	_synth_target_def_id = ""
	_synth_target_quality = -1
	for uid in _synth_material_uids:
		var item := LobbyState.get_item_by_uid(int(uid))
		if item.is_empty():
			continue
		_synth_target_def_id = str(item.get("def_id", ""))
		_synth_target_quality = int(item.get("quality", 0))
		return


func _recompute_synth_result_preview() -> void:
	_synth_result_preview.clear()
	if not LobbyState.can_compose_three(_synth_material_uids):
		return
	var first_item := LobbyState.get_item_by_uid(int(_synth_material_uids[0]))
	if first_item.is_empty():
		return
	var max_level := 1
	for uid in _synth_material_uids:
		var item := LobbyState.get_item_by_uid(int(uid))
		max_level = maxi(max_level, int(item.get("level", 1)))
	_synth_result_preview = {
		"def_id": str(first_item.get("def_id", "")),
		"quality": mini(LobbyState.QUALITY_LEGENDARY, int(first_item.get("quality", 0)) + 1),
		"level": max_level,
	}


func _has_synth_target() -> bool:
	return not _synth_target_def_id.is_empty() and _synth_target_quality >= 0


func _first_empty_synth_slot() -> int:
	for i in range(SYNTH_SLOT_COUNT):
		if int(_synth_material_uids[i]) < 0:
			return i
	return -1


func _is_item_compatible_for_current_target(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var quality := int(item.get("quality", 0))
	if quality >= LobbyState.QUALITY_LEGENDARY:
		return false
	if not _has_synth_target():
		return true
	return str(item.get("def_id", "")) == _synth_target_def_id and quality == _synth_target_quality


func _is_uid_in_synth_materials(uid: int) -> bool:
	for mat_uid in _synth_material_uids:
		if int(mat_uid) == uid:
			return true
	return false


func _get_item_icon(item: Dictionary) -> Texture2D:
	var path := LobbyState.get_item_icon_path(item)
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_icon_cache[path] = tex
	return tex


func _show_synth_toast(text: String) -> void:
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


func _play_synth_fly_icon(item: Dictionary, from_btn: Control, to_btn: Control) -> void:
	var icon := _get_item_icon(item)
	if icon == null or from_btn == null or to_btn == null or _fly_layer == null:
		return
	var fly := TextureRect.new()
	fly.texture = icon
	fly.custom_minimum_size = Vector2(40, 40)
	fly.size = Vector2(40, 40)
	fly.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fly_layer.add_child(fly)

	var from_center := from_btn.get_global_rect().position + from_btn.size * 0.5
	var to_center := to_btn.get_global_rect().position + to_btn.size * 0.5
	var layer_origin := _fly_layer.get_global_rect().position
	var from_local := from_center - layer_origin
	var to_local := to_center - layer_origin
	fly.position = from_local - fly.size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly, "position", to_local - fly.size * 0.5, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly, "scale", Vector2(0.82, 0.82), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly, "modulate:a", 0.8, 0.24)
	tween.finished.connect(fly.queue_free, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	_update_synth_toast(delta)


func _update_synth_toast(delta: float) -> void:
	if _toast == null or not _toast.visible:
		return
	_toast_timer -= delta
	if _toast_timer <= 0.0:
		_toast.visible = false
		return
	var life_t := clampf(_toast_timer / _toast_duration, 0.0, 1.0)
	var alpha := life_t
	if life_t > 0.65:
		alpha = clampf((1.0 - life_t) / 0.35, 0.0, 1.0)
	alpha = maxf(alpha, life_t)
	var rise := (1.0 - life_t) * 16.0
	_toast.offset_top = _toast_base_top - rise
	_toast.offset_bottom = _toast_base_top + 42.0 - rise
	_toast.modulate.a = alpha
