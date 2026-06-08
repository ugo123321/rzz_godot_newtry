extends Control
class_name SynthesisPanelView

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const BAG_SLOT_SCENE := preload("res://scenes/ui/bag_slot.tscn")

const SYNTH_SLOT_COUNT := 3
const BAG_COLUMNS := 5
const BAG_VISIBLE_ROWS := 4
const BAG_BASE_SLOTS := BAG_COLUMNS * BAG_VISIBLE_ROWS

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


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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

	_reset_state()
	_refresh_synthesis_view()
	set_process(true)


func _exit_tree() -> void:
	if EventBus and EventBus.equipment_changed.is_connected(_on_equipment_changed):
		EventBus.equipment_changed.disconnect(_on_equipment_changed)


func _reset_state() -> void:
	_synth_material_uids = [-1, -1, -1]
	_synth_target_def_id = ""
	_synth_target_quality = -1
	_synth_result_preview = {}


func _apply_pixel_filter_tree(root: Node) -> void:
	if root is CanvasItem:
		(root as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for child in root.get_children():
		_apply_pixel_filter_tree(child)


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
			_set_slot_icon(
				slot_btn,
				_get_item_icon(item),
				LobbyState.get_quality_color(int(item.get("quality", 0)))
			)
			continue
		if _has_synth_target():
			var ghost_item := {"def_id": _synth_target_def_id}
			_set_slot_icon(slot_btn, _get_item_icon(ghost_item), Color(1, 1, 1, 0.35))
		else:
			_set_slot_icon(slot_btn, null, Color(1, 1, 1, 1))


func _refresh_synthesis_result_slot() -> void:
	if _synth_result_preview.is_empty():
		_set_slot_icon(_target_slot, null, Color(1, 1, 1, 1))
		return
	_set_slot_icon(
		_target_slot,
		_get_item_icon(_synth_result_preview),
		LobbyState.get_quality_color(int(_synth_result_preview.get("quality", 0)))
	)


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
			_set_slot_icon(btn, null, Color(1, 1, 1, 1))
			btn.modulate = Color(1, 1, 1, 1)
			continue
		var item: Dictionary = inventory[i]
		var uid := int(item.get("uid", -1))
		_bag_slot_uids[i] = uid
		var quality := int(item.get("quality", 0))
		var already_selected := _is_uid_in_synth_materials(uid)
		var compatible := has_empty_slot and (not already_selected) and _is_item_compatible_for_current_target(item)
		_set_slot_icon(btn, _get_item_icon(item), LobbyState.get_quality_color(quality))
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
	_show_synth_toast("合成成功！获得 %s Lv.%d" % [
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
