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
const SLOT_TEX := preload("res://assets/ui/equipment_skills/skills_slot.png")
const BAG_SLOT_SIZE := Vector2(104, 104)
const CIRCLE_SHADER := preload("res://shaders/ui/skill_stone_icon.gdshader")
# 槽位品质背景贴图（同装备界面 equipment_panel.SLOT_BG_TEX），按品质铺底盖住空槽框
const SLOT_BG_TEX := {
	0: preload("res://assets/ui/equipment/slot_bg_white.png"),
	1: preload("res://assets/ui/equipment/slot_bg_blue.png"),
	2: preload("res://assets/ui/equipment/slot_bg_purple.png"),
	3: preload("res://assets/ui/equipment/slot_bg_orange.png"),
}
const ICON_INSET_STONE := 7  # StoneSlot icon inset（圆形 icon 留一圈品质底）
const ICON_INSET_BAG := 5    # 背包槽（104px）按比例缩小后的 inset
# 详情弹窗贴图（面板/装饰带在 tscn 里；按钮蓝红 / 品质装饰带 / 品质底由代码按状态切换）
const BTN_BLUE_TEX := preload("res://assets/ui/buttons/btn_blue.png")   # 装备
const BTN_RED_TEX := preload("res://assets/ui/buttons/btn_red.png")    # 卸下
const QUALITY_DECO_TEX := {
	0: preload("res://assets/ui/decorations/deco_rare_common.png"),
	1: preload("res://assets/ui/decorations/deco_rare_rare.png"),
	2: preload("res://assets/ui/decorations/deco_rare_epic.png"),
	3: preload("res://assets/ui/decorations/deco_rare_legendary.png"),
}
# 详情弹窗文字配色：深棕（同装备详情正文）/ 深绿（同装备生效属性）/ 红
const _AFFIX_COLOR_BROWN := "#341b19"   # = Color(0.204, 0.106, 0.098)
const _AFFIX_COLOR_GREEN := "#1c8a3d"   # = Color(0.12, 0.54, 0.24) 装备生效属性深绿
const _AFFIX_COLOR_RED := "#ff2a2a"

# 6 个属性信息栏对应的 stat_key（与场景 StatBar0..5 一一对应）
const _STAT_BAR_KEYS := ["atk_pct", "bullet_range_pct", "ki_regen_pct", "crit_rate", "crit_damage", "move_speed_pct"]

# 进场淡入（参考 equipment_panel）/ 按钮按下（参考 main_menu 开始按钮）
const INTRO_STEP := 0.018      # 每个元素错峰间隔（秒）
const INTRO_DURATION := 0.22   # 单元素显形时长（秒）
const INTRO_SCALE_FROM := 0.82
const _ACTION_BTN_PRESS_SCALE := 0.9

signal closed

@onready var _stone_slots: Array[TextureButton] = []
@onready var _bag_grid: GridContainer = %BagGrid
@onready var _bag_scroll: ScrollContainer = $BagScroll
@onready var _back_button: TextureButton = %BackButton
@onready var _decompose_btn: TextureButton = %DecomposeBtn
@onready var _decompose_label: Label = %DecomposeBtn/Label
@onready var _confirm_btn: TextureButton = %ConfirmBtn
@onready var _cancel_btn: TextureButton = %CancelBtn
@onready var _confirm_label: Label = %ConfirmBtn/Content/TextLabel
@onready var _cancel_label: Label = %CancelBtn/Label
@onready var _stat_bars: Array[Control] = []
@onready var _fly_layer: Control = %FlyLayer
@onready var _toast: Label = %Toast

var _icon_cache: Dictionary = {}
var _circle_mat: ShaderMaterial = null
var _bag_slot_uids: Array[int] = []
var _multi_select := false
var _selected_uids: Dictionary = {}   # uid(int) -> true

# 详情弹窗节点：布局在 skill_stone_panel.tscn 的 DetailPopup 子树里，可在编辑器调位置
@onready var _detail_popup: Control = %DetailPopup
@onready var _detail_dim: ColorRect = %Dim
@onready var _detail_panel: TextureRect = %Panel
@onready var _detail_quality_deco: TextureRect = %QualityDeco
@onready var _detail_icon_slot: TextureButton = %DetailIconSlot
@onready var _detail_name_label: Label = %DetailNameLabel
@onready var _detail_skill_rt: RichTextLabel = %DetailSkillRT
@onready var _detail_tip_label: Label = %DetailTipLabel
@onready var _detail_affix_rt: RichTextLabel = %DetailAffixRT
@onready var _detail_action_btn: TextureButton = %ActionBtn
# 子节点（名字与别处冲突，不设 unique_name，按父节点取）
var _detail_icon_rect: TextureRect = null
var _detail_bg_rect: TextureRect = null
var _detail_action_label: Label = null
var _detail_uid: int = -1
var _detail_slot: int = -1   # -1 = 来自背包（action=装备）；>=0 = 已装备槽（action=卸下）

var _toast_timer := 0.0
var _toast_duration := 1.9
var _toast_base_top := 150.0

var _intro_playing := false

# 详情弹窗弹出 / 弹回动效（同装备信息面板：Panel 中心缩放 + Dim 淡入淡出）
const _DETAIL_POP_TIME := 0.18
const _DETAIL_POP_SCALE := Vector2(0.82, 0.82)
var _detail_tween: Tween = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_stone_slots = [%StoneSlot0, %StoneSlot1, %StoneSlot2]
	for i in range(EQUIP_SLOT_COUNT):
		var btn := _stone_slots[i]
		if btn != null:
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			btn.pressed.connect(_on_stone_slot_pressed.bind(i))
			_apply_circle_to_icon(btn)
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

	# 收集 6 个属性信息栏
	var stat_bars_node := get_node_or_null("StatBars")
	if stat_bars_node != null:
		for c in stat_bars_node.get_children():
			if c is Control:
				_stat_bars.append(c as Control)

	# 动作按钮：分解 / 确认 / 取消 均为贴图按钮，由 texture_normal 提供外观
	if _decompose_btn != null:
		_decompose_btn.ignore_texture_size = true
	if _confirm_btn != null:
		_confirm_btn.ignore_texture_size = true
	if _cancel_btn != null:
		_cancel_btn.ignore_texture_size = true

	# 动作按钮按下效果（参考 main_menu 开始按钮：scale 0.9 + 轻微暗化）
	_setup_action_button_press(_decompose_btn)
	_setup_action_button_press(_confirm_btn)
	_setup_action_button_press(_cancel_btn)
	_setup_action_button_press(_back_button)

	_setup_detail_popup()

	if EventBus:
		EventBus.skill_stones_changed.connect(_on_skill_stones_changed)
		EventBus.gold_changed.connect(_on_gold_changed)
		EventBus.language_changed.connect(_on_language_changed)

	_apply_static_texts()
	_refresh()
	set_process(true)
	# 进场动效：每次面板可见时所有区块快速依次淡入显形
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()   # 首次若已可见则立即播


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


# ─── 按钮按下效果（参考 main_menu 开始按钮）─────────────────
func _setup_action_button_press(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.button_down.connect(_on_action_btn_down.bind(btn))
	btn.button_up.connect(_on_action_btn_up.bind(btn))


func _on_action_btn_down(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.pivot_offset = Vector2(floorf(btn.size.x * 0.5), floorf(btn.size.y * 0.5))
	btn.scale = Vector2.ONE * _ACTION_BTN_PRESS_SCALE
	btn.modulate = Color(0.92, 0.92, 0.96)


func _on_action_btn_up(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.scale = Vector2.ONE
	btn.modulate = Color.WHITE


# ─── 进场动效：所有区块快速依次淡入显形 ───────────────────
func _on_visibility_changed() -> void:
	if visible and not Engine.is_editor_hint():
		call_deferred("_play_intro")


func _play_intro() -> void:
	# 收集要"依次显形"的元素，按视觉从上到下排列（不含底部 HUD BottomBar）
	var elems: Array[Control] = []
	for p in [
		"TitleIcon", "Title", "DecoLine",
		"StoneSlot0", "StoneSlot1", "StoneSlot2",
		"DecoLine02",
		"BagScroll", "DecomposeBtn",
	]:
		var c := get_node_or_null(p) as Control
		if c != null and c.visible:
			elems.append(c)
	# StatBars 里的 6 个信息栏单独追加（细粒度级联）
	for bar in _stat_bars:
		if bar != null and bar.visible:
			elems.append(bar)
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



func _on_skill_stones_changed() -> void:
	_refresh()


func _on_gold_changed(_v: int) -> void:
	# 金币变化时刷新分解确认按钮的预估金币
	_refresh_action_buttons()


func _apply_static_texts() -> void:
	var title := get_node_or_null("Title") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_SKILL_STONE_TITLE")
	if _cancel_label != null:
		_cancel_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_CANCEL")
	if _decompose_label != null:
		_decompose_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_DECOMPOSE")
	if _detail_tip_label != null:
		_detail_tip_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_AFFIX_HEADER")
	if _detail_action_btn != null:
		_refresh_detail_action_text()


func _apply_pixel_filter_tree(root: Node) -> void:
	if root is CanvasItem:
		var ci := root as CanvasItem
		# 像素艺术：ItemIcon / 品质底 SlotBg 走 NEAREST，其余抗锯齿
		if str(root.name) == "ItemIcon" or str(root.name) == "SlotBg":
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
	_ensure_slot_bg(btn)
	# 同装备界面：不再用 self_modulate 染槽框；品质色由 SlotBg 贴图承担
	btn.self_modulate = Color.WHITE
	var slot_bg := btn.get_node_or_null("SlotBg") as TextureRect
	if slot_bg != null:
		slot_bg.texture = SLOT_BG_TEX.get(quality, SLOT_BG_TEX[0])
		slot_bg.visible = has_item
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect != null:
		# 动态创建的背包槽未被 _apply_pixel_filter_tree 覆盖到，强制 NEAREST 保持像素清晰
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.texture = tex
		icon_rect.visible = tex != null


func _refresh_bag() -> void:
	if _bag_grid == null:
		return
	var inventory := LobbyState.get_skill_stone_inventory_sorted()
	# 现在背包不显示空槽：只渲染已拥有的技能石
	var slot_count := inventory.size()
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
		# 背包槽用技能石槽贴图 + 104 尺寸（与装备槽同形状）
		btn.texture_normal = SLOT_TEX
		btn.custom_minimum_size = BAG_SLOT_SIZE
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		btn.pressed.connect(_on_bag_slot_pressed.bind(index))
		_apply_circle_to_icon(btn, ICON_INSET_BAG)
		_bag_grid.add_child(btn)
	while _bag_grid.get_child_count() > count:
		var extra := _bag_grid.get_child(_bag_grid.get_child_count() - 1)
		# remove_child 立即从父节点摘除（get_child_count 同步下降），
		# queue_free 延迟到帧末真正释放——避免在信号/绘制途中 free 出问题。
		# 之前只 queue_free 不 remove_child，get_child_count 不变 → 死循环。
		_bag_grid.remove_child(extra)
		extra.queue_free()


func _refresh_info_panel() -> void:
	# 6 个属性信息栏：已装备技能石 affix 求和 → 每个栏的 icon/name/value
	var totals: Dictionary = LobbyState.get_skill_stone_affix_totals()
	for i in range(_STAT_BAR_KEYS.size()):
		if i >= _stat_bars.size():
			break
		var bar := _stat_bars[i]
		var key: String = _STAT_BAR_KEYS[i]
		var v := float(totals.get(key, 0.0))
		var name_label := bar.get_node_or_null("NameLabel") as Label
		var value_label := bar.get_node_or_null("ValueLabel") as Label
		if name_label != null:
			name_label.text = _affix_name(key)
		if value_label != null:
			value_label.text = _format_affix_value(v)
			# 颜色规律同详情词条：增加深绿 / 减少红 / 0% 深棕
			var color: Color
			var pct := int(round(v * 100.0))
			if pct == 0:
				color = Color(_AFFIX_COLOR_BROWN)
			elif pct > 0:
				color = Color(_AFFIX_COLOR_GREEN)
			else:
				color = Color(_AFFIX_COLOR_RED)
			value_label.add_theme_color_override("font_color", color)


func _format_affix_value(value: float) -> String:
	var pct := int(round(value * 100.0))
	if pct == 0:
		return "0%"
	var sign := "+" if pct > 0 else "-"
	return "%s%d%%" % [sign, abs(pct)]


func _format_affix_line(stat_key: String, value: float) -> String:
	# 属性词条：整行变色 —— 增加深绿 / 减少红 / 0% 深棕；不走升级奖励的三角箭头渲染
	var pct := int(round(value * 100.0))
	var name := _affix_name(stat_key)
	if pct == 0:
		return "[color=%s]%s 0%%[/color]" % [_AFFIX_COLOR_BROWN, name]
	var sign := "+" if pct > 0 else "-"
	var color := _AFFIX_COLOR_GREEN if pct > 0 else _AFFIX_COLOR_RED
	return "[color=%s]%s %s%d%%[/color]" % [color, name, sign, abs(pct)]


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
		if _confirm_label != null:
			_confirm_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_DECOMPOSE_FMT") % gold
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


# ─── 详情弹窗：节点在 skill_stone_panel.tscn 的 DetailPopup 子树里（编辑器可调位置）；
#     这里只做运行时接线 —— 挂圆形 shader、取子节点引用、连信号 ────
func _setup_detail_popup() -> void:
	if _detail_popup == null:
		return
	# 取子节点引用（ItemIcon/SlotBg/Label 名字与背包槽/按钮冲突，不设 unique_name）
	if _detail_icon_slot != null:
		_detail_icon_rect = _detail_icon_slot.get_node_or_null("ItemIcon") as TextureRect
		_detail_bg_rect = _detail_icon_slot.get_node_or_null("SlotBg") as TextureRect
	if _detail_action_btn != null:
		_detail_action_label = _detail_action_btn.get_node_or_null("Label") as Label
	# 详情 icon 套圆形 + 黑边 shader（材质在代码建/缓存，编辑器只调位置）
	if _detail_icon_rect != null:
		_detail_icon_rect.material = _get_circle_material()
	# 信号（gui_input / pressed 也可在 tscn 里连，这里防御性再连一次避免漏接）
	if _detail_dim != null and not _detail_dim.gui_input.is_connected(_on_detail_outside_clicked):
		_detail_dim.gui_input.connect(_on_detail_outside_clicked)
	if _detail_action_btn != null and not _detail_action_btn.pressed.is_connected(_on_detail_action_pressed):
		_detail_action_btn.pressed.connect(_on_detail_action_pressed)


func _on_detail_outside_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_close_detail()


func _kill_detail_tween() -> void:
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_tween = null


# 弹出动效：Panel 从 0.82 回弹到 1（BACK）+ Dim 0→0.4
func _play_detail_open() -> void:
	if _detail_popup == null:
		return
	_kill_detail_tween()
	_detail_popup.visible = true
	if _detail_panel != null:
		_detail_panel.pivot_offset = _detail_panel.size * 0.5
		_detail_panel.scale = _DETAIL_POP_SCALE
	if _detail_dim != null:
		_detail_dim.modulate = Color(1, 1, 1, 0.0)
	_detail_tween = create_tween()
	_detail_tween.set_parallel(true)
	if _detail_dim != null:
		_detail_tween.tween_property(_detail_dim, "modulate:a", 0.4, _DETAIL_POP_TIME)
	if _detail_panel != null:
		_detail_tween.tween_property(_detail_panel, "scale", Vector2.ONE, _DETAIL_POP_TIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


# 弹回动效：Panel 缩回 0.82（CUBIC）+ Dim→0，完成后隐藏
func _play_detail_close() -> void:
	if _detail_popup == null or not _detail_popup.visible:
		return
	_kill_detail_tween()
	if _detail_panel != null:
		_detail_panel.pivot_offset = _detail_panel.size * 0.5
	_detail_tween = create_tween()
	_detail_tween.set_parallel(true)
	if _detail_dim != null:
		_detail_tween.tween_property(_detail_dim, "modulate:a", 0.0, _DETAIL_POP_TIME)
	if _detail_panel != null:
		_detail_tween.tween_property(_detail_panel, "scale", _DETAIL_POP_SCALE, _DETAIL_POP_TIME) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_detail_tween.chain().tween_callback(_hide_detail_after_close)


func _hide_detail_after_close() -> void:
	if _detail_popup != null:
		_detail_popup.visible = false
	_detail_uid = -1
	_detail_slot = -1


func _open_detail(uid: int, slot: int) -> void:
	if _detail_popup == null:
		return
	var stone := LobbyState.get_skill_stone_by_uid(uid)
	if stone.is_empty():
		return
	_detail_uid = uid
	_detail_slot = slot
	var q := int(stone.get("quality", 0))
	# 顶部品质装饰带
	if _detail_quality_deco != null:
		_detail_quality_deco.texture = QUALITY_DECO_TEX.get(q, QUALITY_DECO_TEX[0])
	# icon 槽：品质 SlotBg + 圆形 icon（无部位徽章）
	var icon := _get_stone_icon(stone)
	if _detail_icon_rect != null:
		_detail_icon_rect.texture = icon
		_detail_icon_rect.visible = icon != null
	if _detail_bg_rect != null:
		_detail_bg_rect.texture = SLOT_BG_TEX.get(q, SLOT_BG_TEX[0])
		_detail_bg_rect.visible = true
	# 名字
	if _detail_name_label != null:
		_detail_name_label.text = LobbyState.get_skill_stone_name(stone)
	# 技能介绍正文（= 对应升级奖励的游戏内描述；字号 22 与原段头一致）
	if _detail_skill_rt != null:
		DescFormat.apply_to_rich_text(_detail_skill_rt, LobbyState.get_skill_stone_desc(stone), 22, false)
	# "属性加成" 段头
	if _detail_tip_label != null:
		_detail_tip_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_AFFIX_HEADER")
	# 属性词条：增加深绿 / 减少红 / 0% 深棕（直接百分比数值带色，不走升级奖励三角箭头）
	if _detail_affix_rt != null:
		var affixes = stone.get("affixes", [])
		var lines: Array[String] = []
		if typeof(affixes) == TYPE_ARRAY:
			for a in affixes:
				if typeof(a) != TYPE_DICTIONARY:
					continue
				lines.append(_format_affix_line(str(a.get("stat_key", "")), float(a.get("value", 0.0))))
		var txt := ""
		if lines.is_empty():
			# 无属性加成：深棕
			txt = "[color=%s]%s[/color]" % [_AFFIX_COLOR_BROWN, LanguageManager.tr_ui("UI_SKILL_STONE_NO_AFFIX")]
		else:
			txt = "\n".join(lines)
		_detail_affix_rt.text = txt
	_refresh_detail_action_text()
	_play_detail_open()


func _refresh_detail_action_text() -> void:
	if _detail_action_btn == null:
		return
	# 已装备槽 -> 卸下（红）；来自背包 -> 装备（蓝）
	if _detail_slot >= 0:
		_detail_action_btn.texture_normal = BTN_RED_TEX
		if _detail_action_label != null:
			_detail_action_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_UNEQUIP")
	else:
		_detail_action_btn.texture_normal = BTN_BLUE_TEX
		if _detail_action_label != null:
			_detail_action_label.text = LanguageManager.tr_ui("UI_SKILL_STONE_EQUIP")


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
	_play_detail_close()


# ─── 图标 / Toast ──────────────────────────────────────────
func _get_circle_material() -> ShaderMaterial:
	if _circle_mat == null:
		_circle_mat = ShaderMaterial.new()
		_circle_mat.shader = CIRCLE_SHADER
		# radius/border_width/edge_aa 用 shader 默认值（见 skill_stone_icon.gdshader）
	return _circle_mat


# 给槽位 ItemIcon 套圆形 + 黑边 shader，并收 inset 让圆形 icon 留一圈品质底
func _apply_circle_to_icon(btn: TextureButton, inset_px: int = -1) -> void:
	if btn == null:
		return
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect == null:
		return
	icon_rect.material = _get_circle_material()
	if inset_px >= 0:
		# anchors_preset = 15（full rect），正负对称 offset 把 icon 内缩 inset_px
		icon_rect.offset_left = float(inset_px)
		icon_rect.offset_top = float(inset_px)
		icon_rect.offset_right = float(-inset_px)
		icon_rect.offset_bottom = float(-inset_px)


# 在槽位内确保一个 SlotBg 子节点（品质背景，铺底盖住空槽框），插在最底（索引 0）→ ItemIcon 在其之上
func _ensure_slot_bg(btn: TextureButton) -> void:
	if btn.get_node_or_null("SlotBg") != null:
		return
	var bg := TextureRect.new()
	bg.name = "SlotBg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 0
	bg.offset_top = 0
	bg.offset_right = 0
	bg.offset_bottom = 0
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.texture = SLOT_BG_TEX[0]
	bg.visible = false
	btn.add_child(bg)
	btn.move_child(bg, 0)   # 索引 0 → 最底


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
