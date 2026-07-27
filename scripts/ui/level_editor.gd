extends Node2D
class_name LevelEditor

# 关卡编辑器：在场地上放置特殊地块/元素，设编号，保存到 user://levels/<编号>.json。
# 入口：主界面右上角设置 → 关卡编辑器（main_menu._on_level_editor_pressed）。
#
# 顶栏（右上角）选项按钮 → 菜单：退出 / 添加 / 编号栏 / 保存。
# 添加 → 弹元素列表选 1 种 → 元素以"编辑模式"出现（跟随鼠标，上方浮确认/取消按钮）；
# 确认 → snap 到最近格中心放置；取消 → 删除。点击场上已放置元素 → 重入编辑模式。
# 箭块编辑模式另加 4 朝向按钮。保存只保存场上元素 + 编号。

const TerrainBackgroundScript := preload("res://scripts/systems/terrain_background.gd")
const LevelLayoutLoaderScript := preload("res://scripts/systems/level_layout_loader.gd")
const FieldElementScript := preload("res://scripts/entities/field_element.gd")
const ArrowBlockScript := preload("res://scripts/entities/arrow_block.gd")
const LockedBlockScript := preload("res://scripts/entities/locked_block.gd")
const FixedPortalScript := preload("res://scripts/entities/fixed_portal.gd")
const ChestNormalScript := preload("res://scripts/entities/chest_normal.gd")
const ChestLockedScript := preload("res://scripts/entities/chest_locked.gd")
const PitBlockScript := preload("res://scripts/entities/pit_block.gd")
const BlockingStoneBlockScript := preload("res://scripts/entities/blocking_stone_block.gd")
const PlacedTreeScript := preload("res://scripts/entities/placed_tree.gd")
const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const TILE_SIZE := 40
const FIELD_W := 720
const FIELD_H := 1280
# 玩家起始位置（与 battle.gd:360 player.global_position = Vector2(w*0.5, h*0.58) 对齐）
const PLAYER_START := Vector2(360.0, 742.0)

# 元素类型列表（key = kind / tile type；label i18n key）
const ELEMENT_KINDS := [
	{"type": "arrow_single", "label": "UI_LEVEL_ELEM_ARROW_SINGLE"},
	{"type": "arrow_cross", "label": "UI_LEVEL_ELEM_ARROW_CROSS"},
	{"type": "blocking_stone", "label": "UI_LEVEL_ELEM_BLOCKING_STONE"},
	{"type": "pit", "label": "UI_LEVEL_ELEM_PIT"},
	{"type": "stone_floor", "label": "UI_LEVEL_ELEM_STONE_FLOOR"},
	{"type": "water", "label": "UI_LEVEL_ELEM_WATER"},
	{"type": "locked_block", "label": "UI_LEVEL_ELEM_LOCKED_BLOCK"},
	{"type": "fixed_portal", "label": "UI_LEVEL_ELEM_FIXED_PORTAL"},
	{"type": "chest_normal", "label": "UI_LEVEL_ELEM_CHEST_NORMAL"},
	{"type": "chest_locked", "label": "UI_LEVEL_ELEM_CHEST_LOCKED"},
	{"type": "tree", "label": "UI_LEVEL_ELEM_TREE"},
]
const FACINGS := ["up", "down", "left", "right"]
# 地板类（水地板 / 石地板）：作为底面 terrain 画上去，不占格 —— 可在其上放其他地块/元素。
const TILE_PLACEMENT_TYPES := ["water", "stone_floor"]

var _field: Node2D  # TerrainBackground 实例容器
var _terrain: Node
var _ui_layer: CanvasLayer
var _elements: Array = []  # 已放置的 FieldElement 实体
var _tile_overrides: Array = []  # [{col,row,type}]
var _editing_element: Node = null  # 当前编辑（移动）的已放置元素
var _editing_orig_cell := Vector2i(-1, -1)  # 编辑前原格（取消时回退）
# 画笔模式：选了元素类型后左键拖动连续绘制（不覆盖已有元素/地块）；右键退出画笔。
var _brush_kind := ""
var _brush_facing := "up"
var _painting := false
var _number_edit: LineEdit
var _options_btn: Button
var _edit_confirm_btn: Button
var _edit_cancel_btn: Button
var _facing_btns: Array = []
var _brush_hint: Label


func _ready() -> void:
	_build_field()
	_build_ui()
	_apply_texts()
	EventBus.language_changed.connect(_on_language_changed)
	# 从战斗测试返回（editor_test_mode 仍为 true）→ 恢复测试前的布局；否则空场地。
	if LobbyState and LobbyState.editor_test_mode:
		_load_layout("__editor_test__")
		LobbyState.editor_test_mode = false  # 恢复后清标记，避免后续正常开战斗误判
	# _build_field 已是 fresh 草地；_load_layout 会在此之上叠加保存的元素/地块


# 「测试」：保存当前布局到 __editor_test__ → 切到真实战斗场景跑（真玩家+真怪物AI+真战斗+地块生效）。
# 战斗里点「停止测试」回到本编辑器并恢复布局。
func _start_test() -> void:
	# 先把当前布局（含未编号）保存到固定测试编号
	var arr: Array = []
	for ov in _tile_overrides:
		arr.append({"type": String(ov.type), "col": int(ov.col), "row": int(ov.row), "facing": "up"})
	for e in _elements:
		if is_instance_valid(e) and e is FieldElement:
			arr.append(e.serialize())
	LevelLayoutLoaderScript.save_layout("__editor_test__", arr)
	LobbyState.request_battle_launch(0)  # 正常开战斗（会清 editor_test_mode）
	LobbyState.editor_test_mode = true   # 再标记为编辑器测试，让战斗载入 __editor_test__ 布局 + 显示停止按钮
	LobbyState.editor_test_layout = "__editor_test__"
	LobbyState.editor_test_stage = 0
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")


# 从布局文件载入并重建 _tile_overrides + _elements（测试返回时恢复编辑现场）。
func _load_layout(number) -> void:
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(number)
	if layout.is_empty():
		return
	# 清空当前现场
	for e in _elements:
		if is_instance_valid(e):
			e.queue_free()
	_elements.clear()
	_tile_overrides.clear()
	var elements: Array = layout.get("elements", [])
	for elem in elements:
		if not (elem is Dictionary):
			continue
		var t: String = String(elem.get("type", ""))
		var col: int = int(elem.get("col", 0))
		var row: int = int(elem.get("row", 0))
		var facing: String = String(elem.get("facing", "up"))
		if TILE_PLACEMENT_TYPES.has(t):
			_terrain.set_tile(col, row, t)
			_tile_overrides.append({"col": col, "row": row, "type": t})
			continue
		var e: Node = _instantiate_element(t)
		if e == null:
			continue
		e.cell_col = col
		e.cell_row = row
		e.global_position = _cell_center(col, row)
		if e is ArrowBlock:
			e.set_facing(facing)
		_field.add_child(e)
		_elements.append(e)


func _build_field() -> void:
	# 地形（中性草地）—— 必须先加入场景树再 setup_for_stage（内部 get_tree() 查 battle 组）
	_field = Node2D.new()
	_field.name = "Field"
	add_child(_field)
	_terrain = TerrainBackgroundScript.new()
	_terrain.z_index = -5  # 与 battle.gd 一致，让根 _draw 的标记画在地形之上
	_field.add_child(_terrain)
	_terrain.setup_for_stage(0, {})
	z_index = 1  # 让根 _draw 的场地边框画在地形(z=-5)之上


func _draw() -> void:
	# 场地边框（地形 terrain 已覆盖 720×1280，不画 bg 填充以免盖住草地）
	draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), Color("#3a3a44"), false, 3.0)
	# 玩家起始位置标记（绿色双环 + 中心点 + 十字），提示编辑时避免在出生点放阻挡块
	draw_arc(PLAYER_START, 22.0, 0.0, TAU, 36, Color("#5fd96c"), 3.0)
	draw_arc(PLAYER_START, 14.0, 0.0, TAU, 24, Color("#5fd96c"), 2.0)
	draw_circle(PLAYER_START, 4.0, Color("#5fd96c"))
	# 十字准星
	draw_line(PLAYER_START - Vector2(30, 0), PLAYER_START + Vector2(30, 0), Color("#5fd96c"), 1.5)
	draw_line(PLAYER_START - Vector2(0, 30), PLAYER_START + Vector2(0, 30), Color("#5fd96c"), 1.5)
	# 编辑中的元素高亮环（黄色脉动）
	if _editing_element != null and is_instance_valid(_editing_element):
		var ep: Vector2 = _editing_element.global_position
		var pulse: float = 22.0 + 3.0 * sin(Time.get_ticks_msec() * 0.008)
		draw_arc(ep, pulse, 0.0, TAU, 36, Color("#ffd060"), 3.0)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# 顶栏右上角选项按钮
	_options_btn = Button.new()
	_options_btn.text = "☰"
	_options_btn.add_theme_font_size_override("font_size", 22)
	_options_btn.offset_left = FIELD_W - 90.0
	_options_btn.offset_top = 12.0
	_options_btn.offset_right = FIELD_W - 20.0
	_options_btn.offset_bottom = 56.0
	UiStyle.apply_primary_button(_options_btn, Color("#5a6a90"), 8)
	PixelUi.apply_ui_font(_options_btn)
	_options_btn.pressed.connect(_on_options_pressed)
	_ui_layer.add_child(_options_btn)

	# 画笔模式提示（选中元素后显示，提示左键拖动绘制 / 右键退出）
	_brush_hint = Label.new()
	_brush_hint.add_theme_font_size_override("font_size", 18)
	_brush_hint.add_theme_color_override("font_color", Color("#fff4a0"))
	_brush_hint.add_theme_color_override("font_outline_color", Color("#1a1208"))
	_brush_hint.add_theme_constant_override("outline_size", 5)
	PixelUi.apply_ui_font(_brush_hint)
	_brush_hint.visible = false
	_brush_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brush_hint.anchor_left = 0.0
	_brush_hint.anchor_right = 1.0
	_brush_hint.anchor_top = 0.0
	_brush_hint.anchor_bottom = 0.0
	_brush_hint.offset_top = 12.0
	_brush_hint.offset_left = 12.0
	_brush_hint.offset_right = -100.0
	_brush_hint.offset_bottom = 44.0
	_ui_layer.add_child(_brush_hint)

	# 编辑模式浮动按钮（确认 / 取消），初始隐藏
	_edit_confirm_btn = Button.new()
	_edit_confirm_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CONFIRM")
	PixelUi.apply_ui_font(_edit_confirm_btn)
	_edit_confirm_btn.add_theme_font_size_override("font_size", 18)
	UiStyle.apply_primary_button(_edit_confirm_btn, Color("#5fa060"), 8)
	_edit_confirm_btn.visible = false
	_edit_confirm_btn.pressed.connect(_on_edit_confirm)
	_ui_layer.add_child(_edit_confirm_btn)

	_edit_cancel_btn = Button.new()
	_edit_cancel_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	PixelUi.apply_ui_font(_edit_cancel_btn)
	_edit_cancel_btn.add_theme_font_size_override("font_size", 18)
	UiStyle.apply_primary_button(_edit_cancel_btn, Color("#a05050"), 8)
	_edit_cancel_btn.visible = false
	_edit_cancel_btn.pressed.connect(_on_edit_cancel)
	_ui_layer.add_child(_edit_cancel_btn)

	# 朝向按钮（箭块编辑模式），初始隐藏
	for i in range(4):
		var b := Button.new()
		b.text = LanguageManager.tr_ui("UI_FACING_" + ["UP", "DOWN", "LEFT", "RIGHT"][i])
		PixelUi.apply_ui_font(b)
		b.add_theme_font_size_override("font_size", 16)
		UiStyle.apply_primary_button(b, Color("#8a7a40"), 6)
		b.visible = false
		var idx := i
		b.pressed.connect(func(): _on_facing_picked(FACINGS[idx]))
		_ui_layer.add_child(b)
		_facing_btns.append(b)


func _apply_texts() -> void:
	if _options_btn:
		_options_btn.tooltip_text = LanguageManager.tr_ui("UI_SETTINGS_TITLE")
	if _edit_confirm_btn:
		_edit_confirm_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CONFIRM")
	if _edit_cancel_btn:
		_edit_cancel_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	for i in range(4):
		if _facing_btns[i]:
			_facing_btns[i].text = LanguageManager.tr_ui("UI_FACING_" + ["UP", "DOWN", "LEFT", "RIGHT"][i])
	if _brush_hint and _brush_hint.visible:
		_brush_hint.text = _brush_hint_text()


func _on_language_changed(_lang: String) -> void:
	_apply_texts()


# === 选项菜单 ===
func _on_options_pressed() -> void:
	# 用 AcceptDialog 作为简易菜单
	var dlg := ConfirmationDialog.new()
	dlg.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_TITLE")
	dlg.dialog_text = ""
	dlg.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_ADD")
	# 自定义内容：4 个按钮 + 编号 LineEdit
	var vbox := VBoxContainer.new()
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_EXIT"), _on_exit_pressed))
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_TEST"), _start_test))
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RESET"), _reset_all))
	# 编号栏
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_NUMBER")
	PixelUi.apply_ui_font(lbl)
	_number_edit = LineEdit.new()
	_number_edit.placeholder_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_NUMBER_HINT")
	_number_edit.custom_minimum_size = Vector2(160, 0)
	hbox.add_child(lbl)
	hbox.add_child(_number_edit)
	vbox.add_child(hbox)
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_SAVE"), _on_save_pressed))
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE"), _open_manage_dialog))
	dlg.add_child(vbox)
	# 把 ADD/Cancel 按钮文案改：ok=添加，cancel=关闭
	_ui_layer.add_child(dlg)
	dlg.popup_centered()
	# ok = 添加（ConfirmationDialog 默认 OK）
	dlg.confirmed.connect(func():
		dlg.queue_free()
		_open_add_list()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)
	# 编号栏输入时即时缓存
	if not _number_edit.text_changed.is_connected(_on_number_changed):
		_number_edit.text_changed.connect(_on_number_changed)


func _on_number_changed(_new_text: String) -> void:
	# 编号即时缓存（不做事，保存时直接读 _number_edit）
	pass


func _commit_number_from_edit() -> void:
	# 占位：编号在 _on_save_pressed 时直接从 _number_edit 读
	pass


func _make_menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	PixelUi.apply_ui_font(b)
	UiStyle.apply_primary_button(b, Color("#5a6a90"), 8)
	b.pressed.connect(cb)
	return b


# 恢复初始状态：清空所有已放置元素 + 地块覆盖，地形回草地，退出画笔/编辑。
func _reset_all() -> void:
	_exit_brush()
	_exit_edit_mode(false)
	for e in _elements:
		if is_instance_valid(e):
			e.queue_free()
	_elements.clear()
	_tile_overrides.clear()
	# 地形整片重画为草地（只烘焙一次）
	_terrain.clear_all_tiles(TerrainBackgroundScript.TYPE_GRASS)
	_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RESET_DONE"))


func _on_exit_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_EXIT")
	dlg.dialog_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_EXIT_CONFIRM")
	dlg.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_EXIT")
	dlg.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	_ui_layer.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	dlg.canceled.connect(dlg.queue_free)


# === 添加元素 → 进入画笔模式 ===
func _open_add_list() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_ADD_TITLE")
	dlg.dialog_text = ""
	dlg.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CONFIRM")
	dlg.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(300, 240)
	for kind in ELEMENT_KINDS:
		list.add_item(LanguageManager.tr_ui(kind.label))
		list.set_item_metadata(list.item_count - 1, kind.type)
	dlg.add_child(list)
	_ui_layer.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		var sel: Array = list.get_selected_items()
		if sel.is_empty():
			dlg.queue_free()
			return
		var kind_type: String = list.get_item_metadata(sel[0])
		dlg.queue_free()
		_set_brush(kind_type)
	)
	dlg.canceled.connect(dlg.queue_free)


func _set_brush(kind: String) -> void:
	_exit_edit_mode(false)
	_brush_kind = kind
	_painting = false
	_show_brush_ui(true)


func _exit_brush() -> void:
	_brush_kind = ""
	_painting = false
	_show_brush_ui(false)


# 显示画笔提示 + 朝向按钮（箭块画笔时）；画笔模式浮动按钮用固定位置（顶部），不跟鼠标。
func _show_brush_ui(show: bool) -> void:
	if _brush_hint == null:
		return
	_brush_hint.visible = show
	var is_arrow := show and (_brush_kind == "arrow_single" or _brush_kind == "arrow_cross")
	for b in _facing_btns:
		b.visible = is_arrow
	if show:
		_brush_hint.text = _brush_hint_text()
		_brush_hint.anchor_left = 0.0
		_brush_hint.anchor_right = 1.0
		_brush_hint.anchor_top = 0.0
		_brush_hint.anchor_bottom = 0.0
		_brush_hint.offset_top = 12.0
		_brush_hint.offset_left = 12.0
		_brush_hint.offset_right = -100.0
		_brush_hint.offset_bottom = 44.0
		var fx0 := Vector2(12.0, 48.0)
		for i in range(4):
			_facing_btns[i].global_position = fx0 + Vector2(i * 64, 0)


func _brush_hint_text() -> String:
	if _brush_kind == "":
		return ""
	for kind in ELEMENT_KINDS:
		if kind.type == _brush_kind:
			return LanguageManager.tr_ui(kind.label) + " | " + \
				LanguageManager.tr_ui("UI_LEVEL_EDITOR_BRUSH_HINT")
	return ""


# === 画笔绘制：在 (col,row) 放置当前画笔元素/地块；不覆盖已有元素或地块覆盖 ===
# 放大后的特殊实体种类：放置时强制 3×3 间隔（不能紧贴另一个实体）。
const BIG_ENTITY_KINDS := ["arrow_single", "arrow_cross", "blocking_stone", "locked_block", "chest_normal", "chest_locked"]


func _paint_at(col: int, row: int) -> void:
	if _brush_kind == "":
		return
	if not _cell_in_bounds(col, row):
		return
	if _cell_occupied(col, row):
		return  # 不覆盖
	if TILE_PLACEMENT_TYPES.has(_brush_kind):
		_terrain.set_tile(col, row, _brush_kind)
		_tile_overrides.append({"col": col, "row": row, "type": _brush_kind})
		return
	# 放大实体相邻可紧贴放置（不强制间隔），靠 1 格 no-overlap 规则避免重叠同格
	var elem: Node = _instantiate_element(_brush_kind)
	if elem == null:
		return
	elem.cell_col = col
	elem.cell_row = row
	elem.global_position = _cell_center(col, row)
	if elem is ArrowBlock:
		elem.set_facing(_brush_facing)
	_field.add_child(elem)
	_elements.append(elem)


# 3×3 范围内是否已有实体（保留备用，当前放置不强制间隔 —— 相邻紧贴）。
func _entity_nearby_3x3(col: int, row: int) -> bool:
	for dc in range(-1, 2):
		for dr in range(-1, 2):
			if _element_at(col + dc, row + dr) != null:
				return true
	return false


func _cell_occupied(col: int, row: int) -> bool:
	# 实体（含飞箭块/锁定块/深坑/阻挡石/宝箱/传送门）占格
	for e in _elements:
		if is_instance_valid(e) and e is FieldElement:
			if e.cell_col == col and e.cell_row == row:
				return true
	# 地板类覆盖（水/石地板）不占格 —— 可在其上叠放其他地块/元素
	for ov in _tile_overrides:
		if int(ov.col) == col and int(ov.row) == row:
			return false  # 地板不阻挡后续放置
	return false


func _cell_in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < FIELD_W / TILE_SIZE and row >= 0 and row < FIELD_H / TILE_SIZE


func _instantiate_element(kind_type: String) -> Node:
	match kind_type:
		"arrow_single", "arrow_cross":
			var b := ArrowBlockScript.new()
			b.setup_block(0, 0, kind_type, "up")
			return b
		"locked_block":
			var b := LockedBlockScript.new()
			b.setup_block(0, 0)
			return b
		"pit":
			var b := PitBlockScript.new()
			b.setup_block(0, 0)
			return b
		"blocking_stone":
			var b := BlockingStoneBlockScript.new()
			b.setup_block(0, 0)
			return b
		"tree":
			var t := PlacedTreeScript.new()
			t.setup_tree(0, 0)
			return t
		"fixed_portal":
			var p := FixedPortalScript.new()
			p.setup_portal(0, 0)
			return p
		"chest_normal":
			var c := ChestNormalScript.new()
			c.setup_chest(0, 0, "chest_normal")
			return c
		"chest_locked":
			var c := ChestLockedScript.new()
			c.setup_chest(0, 0, "chest_locked")
			return c
	return null


# === 编辑已放置元素（移动/删除） ===
func _begin_edit_existing(e: Node) -> void:
	_elements.erase(e)
	_editing_element = e
	_editing_orig_cell = Vector2i(e.cell_col, e.cell_row)
	# 元素跟随鼠标，按钮点不到 → 不显示浮动按钮，只显示顶部提示
	_edit_confirm_btn.visible = false
	_edit_cancel_btn.visible = false
	for b in _facing_btns:
		b.visible = false
	_set_hint(LanguageManager.tr_ui("UI_LEVEL_EDITOR_EDIT_HINT"))


func _set_hint(text: String) -> void:
	if _brush_hint == null:
		return
	_brush_hint.visible = text != ""
	_brush_hint.text = text


func _on_edit_confirm() -> void:
	if _editing_element == null:
		return
	var pos: Vector2 = _editing_element.global_position
	var col := int(clamp(pos.x / TILE_SIZE, 0, FIELD_W / TILE_SIZE - 1))
	var row := int(clamp(pos.y / TILE_SIZE, 0, FIELD_H / TILE_SIZE - 1))
	# 目标格被占用（除自己原格）→ 不放置，回退原格
	var occupied_other := _cell_occupied(col, row) and not (col == _editing_orig_cell.x and row == _editing_orig_cell.y)
	if occupied_other:
		col = _editing_orig_cell.x
		row = _editing_orig_cell.y
	_editing_element.global_position = _cell_center(col, row)
	_editing_element.cell_col = col
	_editing_element.cell_row = row
	_elements.append(_editing_element)
	_editing_element = null
	_editing_orig_cell = Vector2i(-1, -1)
	_set_hint("")


func _on_edit_cancel() -> void:
	_exit_edit_mode(false)


# 编辑模式下右键删除：直接 queue_free 当前元素，不回退到 _elements。
func _delete_editing_element() -> void:
	if _editing_element == null:
		return
	_editing_element.queue_free()
	_editing_element = null
	_editing_orig_cell = Vector2i(-1, -1)
	_set_hint("")
	_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_ELEM_REMOVED"))


func _exit_edit_mode(commit: bool) -> void:
	if not commit and _editing_element != null:
		# 取消 = 回退到原格（不删除已放置元素）
		if _editing_orig_cell.x >= 0:
			_editing_element.global_position = _cell_center(_editing_orig_cell.x, _editing_orig_cell.y)
			_editing_element.cell_col = _editing_orig_cell.x
			_editing_element.cell_row = _editing_orig_cell.y
			_elements.append(_editing_element)
		else:
			_editing_element.queue_free()
	_editing_element = null
	_editing_orig_cell = Vector2i(-1, -1)
	_edit_confirm_btn.visible = false
	_edit_cancel_btn.visible = false
	for b in _facing_btns:
		b.visible = false
	_set_hint("")


func _on_facing_picked(facing: String) -> void:
	if _brush_kind != "":
		_brush_facing = facing
	elif _editing_element != null and _editing_element is ArrowBlock:
		_editing_element.set_facing(facing)


func _show_edit_buttons(_show: bool, _show_facing: bool) -> void:
	# 编辑模式下不显示浮动按钮（元素跟鼠标，按钮点不到）；保留函数签名给 _show_brush_ui 之外的旧调用兼容。
	pass


func _process(_delta: float) -> void:
	queue_redraw()  # 驱动玩家标记脉动 + 编辑高亮环刷新
	# 编辑模式：元素跟随鼠标
	if _editing_element != null:
		var mp := _mouse_world()
		_editing_element.global_position = mp
		_position_edit_buttons()  # 朝向按钮随元素位置刷新


func _position_edit_buttons() -> void:
	# 确认/取消固定在屏幕底部居中，始终可见（不跟鼠标，避免元素在顶部时按钮出屏）
	var base_y: float = FIELD_H - 64.0
	_edit_confirm_btn.global_position = Vector2(FIELD_W * 0.5 - 170.0, base_y)
	_edit_cancel_btn.global_position = Vector2(FIELD_W * 0.5 + 20.0, base_y)
	# 朝向按钮（箭块编辑时）固定在编辑元素上方
	if _editing_element != null:
		var ep: Vector2 = _editing_element.global_position
		var fy: float = maxf(12.0, ep.y - 70.0)
		var fx0 := Vector2(ep.x - 160.0, fy)
		for i in range(4):
			_facing_btns[i].global_position = fx0 + Vector2(i * 64, 0)


# === 输入 ===
func _unhandled_input(event: InputEvent) -> void:
	# 编辑模式：左键确认放置（移动），右键删除元素，"取消"按钮放弃移动保留原位
	if _editing_element != null:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_on_edit_confirm()
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_delete_editing_element()
				get_viewport().set_input_as_handled()
		return
	# 画笔模式
	if _brush_kind != "":
		# 右键退出画笔
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_brush()
			get_viewport().set_input_as_handled()
			return
		# 左键按下：点中已有实体 → 进编辑模式；否则开始绘制（地板上可叠放，不删除地板）
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mp := _mouse_world()
			var col := int(mp.x / TILE_SIZE)
			var row := int(mp.y / TILE_SIZE)
			var hit := _element_at(col, row)
			if hit != null:
				_exit_brush()
				_begin_edit_existing(hit)
				get_viewport().set_input_as_handled()
				return
			# 地板（水/石地板）不占格 → 直接在其上绘制：实体叠在地板上，地板类覆盖替换底面
			_painting = true
			_paint_at(col, row)
			get_viewport().set_input_as_handled()
			return
		# 左键抬起：停止绘制（画笔保留，可再画）
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_painting = false
			return
		# 左键按住拖动：每进新格画一格（空格才画）
		if _painting and event is InputEventMouseMotion:
			var mp := _mouse_world()
			var col := int(mp.x / TILE_SIZE)
			var row := int(mp.y / TILE_SIZE)
			_paint_at(col, row)
			get_viewport().set_input_as_handled()
			return
		return
	# 无画笔无编辑：左键点中实体 → 进编辑模式；点中已放置地块 → 删除
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := _mouse_world()
		var col := int(mp.x / TILE_SIZE)
		var row := int(mp.y / TILE_SIZE)
		var hit := _element_at(col, row)
		if hit != null:
			_begin_edit_existing(hit)
			get_viewport().set_input_as_handled()
			return
		var ov := _tile_override_at(col, row)
		if not ov.is_empty():
			_remove_tile_override(col, row)
			get_viewport().set_input_as_handled()


func _element_at(col: int, row: int) -> Node:
	for e in _elements:
		if is_instance_valid(e) and e is FieldElement:
			if e.cell_col == col and e.cell_row == row:
				return e
	return null


func _tile_override_at(col: int, row: int) -> Dictionary:
	for ov in _tile_overrides:
		if int(ov.col) == col and int(ov.row) == row:
			return ov
	return {}


func _remove_tile_override(col: int, row: int) -> void:
	for i in range(_tile_overrides.size()):
		var ov: Dictionary = _tile_overrides[i]
		if int(ov.col) == col and int(ov.row) == row:
			_tile_overrides.remove_at(i)
			_terrain.set_tile(col, row, TerrainBackgroundScript.TYPE_GRASS)
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_TILE_REMOVED"))
			return


# === 保存 ===
func _on_save_pressed() -> void:
	var number: String = ""
	if _number_edit:
		number = _number_edit.text.strip_edges()
	if number.is_empty():
		number = "default"
	var arr: Array = []
	# 地块覆盖
	for ov in _tile_overrides:
		arr.append({"type": String(ov.type), "col": int(ov.col), "row": int(ov.row), "facing": "up"})
	# 实体
	for e in _elements:
		if is_instance_valid(e) and e is FieldElement:
			arr.append(e.serialize())
	var res: Dictionary = LevelLayoutLoaderScript.save_layout(number, arr)
	var msg: String = LanguageManager.tr_ui("UI_LEVEL_EDITOR_SAVED_FMT") % [number, arr.size()]
	_show_toast(msg)


# === 工具 ===
func _mouse_world() -> Vector2:
	var vp := get_viewport().get_mouse_position()
	# 场地以左上角为原点，viewport 坐标即世界坐标（编辑器无相机变换）
	return Vector2(clamp(vp.x, 0, FIELD_W), clamp(vp.y, 0, FIELD_H))


func _cell_center(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * TILE_SIZE, (row + 0.5) * TILE_SIZE)


func _show_toast(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	PixelUi.apply_ui_font(lbl)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color("#fff4a0"))
	lbl.add_theme_color_override("font_outline_color", Color("#3a2408"))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.0
	lbl.offset_top = 80.0
	lbl.offset_left = -260.0
	lbl.offset_right = 260.0
	_ui_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)


# === 管理：列出已保存关卡，每行 载入 / 重命名 / 删除 ===
func _close_all_confirm_dialogs() -> void:
	for c in _ui_layer.get_children():
		if c is ConfirmationDialog:
			c.queue_free()


func _open_manage_dialog() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE_TITLE")
	dlg.dialog_text = ""
	dlg.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CLOSE")
	dlg.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	# 可滚动列表容器
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 360)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	dlg.add_child(scroll)
	var numbers: Array = LevelLayoutLoaderScript.list_numbers()
	if numbers.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE_EMPTY")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		PixelUi.apply_ui_font(empty_lbl)
		empty_lbl.add_theme_font_size_override("font_size", 20)
		vbox.add_child(empty_lbl)
	else:
		for num in numbers:
			vbox.add_child(_make_manage_row(String(num)))
	_ui_layer.add_child(dlg)
	dlg.popup_centered()
	# ok / cancel 都只是关对话框
	dlg.confirmed.connect(func():
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)


func _make_manage_row(num: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_meta("num", num)
	# 元素数（读回布局；失败按 0）
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(num)
	var count: int = int(layout.get("elements", []).size()) if not layout.is_empty() else 0
	var name_lbl := Label.new()
	name_lbl.text = num
	name_lbl.custom_minimum_size = Vector2(140, 0)
	name_lbl.add_theme_font_size_override("font_size", 18)
	PixelUi.apply_ui_font(name_lbl)
	row.add_child(name_lbl)
	var cnt_lbl := Label.new()
	cnt_lbl.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_ELEM_COUNT_FMT") % count
	cnt_lbl.custom_minimum_size = Vector2(110, 0)
	cnt_lbl.add_theme_font_size_override("font_size", 16)
	PixelUi.apply_ui_font(cnt_lbl)
	row.add_child(cnt_lbl)
	# 载入
	var load_btn := Button.new()
	load_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
	PixelUi.apply_ui_font(load_btn)
	load_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(load_btn, Color("#5fa060"), 8)
	load_btn.pressed.connect(func(): _on_load_existing(num))
	row.add_child(load_btn)
	# 重命名
	var rename_btn := Button.new()
	rename_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME")
	PixelUi.apply_ui_font(rename_btn)
	rename_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(rename_btn, Color("#5a6a90"), 8)
	rename_btn.pressed.connect(func(): _on_rename_existing(num, row))
	row.add_child(rename_btn)
	# 删除
	var del_btn := Button.new()
	del_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	PixelUi.apply_ui_font(del_btn)
	del_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(del_btn, Color("#a05050"), 8)
	del_btn.pressed.connect(func(): _on_delete_existing(num))
	row.add_child(del_btn)
	return row


# 载入：画布非空先弹丢弃确认 → _reset_all + _load_layout → 关对话框 + toast
func _on_load_existing(num: String) -> void:
	var has_unsaved: bool = not _elements.is_empty() or not _tile_overrides.is_empty()
	if has_unsaved:
		var confirm := ConfirmationDialog.new()
		confirm.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
		confirm.dialog_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT") % num
		confirm.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
		confirm.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
		_ui_layer.add_child(confirm)
		confirm.popup_centered()
		confirm.confirmed.connect(func():
			_do_load_existing(num)
		)
		confirm.canceled.connect(confirm.queue_free)
		return
	_do_load_existing(num)


func _do_load_existing(num: String) -> void:
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(num)
	if layout.is_empty():
		_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT") % num)
		return
	_reset_all()
	_load_layout(num)  # 已存在函数，重建 _tile_overrides + _elements
	var count: int = int(layout.get("elements", []).size())
	_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOADED_FMT") % [num, count])
	# 关掉管理对话框：找 UI 层里最顶部的 ConfirmationDialog（即管理面板）
	_close_all_confirm_dialogs()


# 重命名：行内把 name_lbl 换成 LineEdit + ✓ → rename_layout → 刷新列表
func _on_rename_existing(num: String, row: HBoxContainer) -> void:
	# 行内 name_lbl 是第 0 个子节点
	var name_lbl: Label = row.get_child(0)
	name_lbl.visible = false
	var edit := LineEdit.new()
	edit.text = num
	edit.editable = true
	edit.select_all()
	edit.custom_minimum_size = Vector2(140, 0)
	PixelUi.apply_ui_font(edit)
	edit.add_theme_font_size_override("font_size", 18)
	row.add_child(edit)
	row.move_child(edit, 0)  # 排在 name_lbl 之前
	edit.grab_focus()
	# ✓ 按钮
	var ok_btn := Button.new()
	ok_btn.text = "✓"
	ok_btn.add_theme_font_size_override("font_size", 18)
	UiStyle.apply_primary_button(ok_btn, Color("#5fa060"), 6)
	PixelUi.apply_ui_font(ok_btn)
	row.add_child(ok_btn)
	var commit := func() -> void:
		var new_num: String = edit.text.strip_edges()
		if new_num.is_empty():
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_INVALID"))
			return
		if new_num == num:
			_restore_rename_row(row, edit, ok_btn, name_lbl)
			return
		var res: Dictionary = LevelLayoutLoaderScript.rename_layout(num, new_num)
		if res.get("ok", false):
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_DONE_FMT") % [num, new_num])
			# 关管理对话框后重建刷新
			_close_all_confirm_dialogs()
			_open_manage_dialog()
		else:
			var err: String = String(res.get("error", ""))
			if err == "exists":
				_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_EXISTS_FMT") % new_num)
			else:
				_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_FAILED_FMT"))
	ok_btn.pressed.connect(commit)
	edit.text_submitted.connect(commit)
	edit.focus_exited.connect(func(): _restore_rename_row(row, edit, ok_btn, name_lbl))


func _restore_rename_row(row: HBoxContainer, edit: LineEdit, ok_btn: Button, name_lbl: Label) -> void:
	row.remove_child(edit)
	row.remove_child(ok_btn)
	edit.queue_free()
	ok_btn.queue_free()
	name_lbl.visible = true


# 删除：二次确认 → delete_layout → 刷新列表
func _on_delete_existing(num: String) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	confirm.dialog_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT") % num
	confirm.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	confirm.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	_ui_layer.add_child(confirm)
	confirm.popup_centered()
	confirm.confirmed.connect(func():
		var res: Dictionary = LevelLayoutLoaderScript.delete_layout(num)
		if res.get("ok", false):
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_DONE_FMT") % num)
			_close_all_confirm_dialogs()
			_open_manage_dialog()
		else:
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_FAILED_FMT"))
	)
	confirm.canceled.connect(confirm.queue_free)
