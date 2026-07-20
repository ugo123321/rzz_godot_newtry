extends Control
class_name TalentCardsPanel

# 天赋卡牌主面板：网格显示所有卡（拥有的显示等级 + icon，未拥有的显示 "?"），
# 下方抽卡按钮消耗金币抽卡；抽到卡后弹 TalentDrawResultPopup，关闭时若是重复卡触发升级动画。
# 点击已拥有卡片弹 TalentDetailPopup（左右切换观看）。

const TalentCardSlotT = preload("res://scenes/ui/talent_card_slot.tscn")
const TalentDrawResultPopupT = preload("res://scripts/ui/talent_draw_result_popup.gd")
const TalentDetailPopupT = preload("res://scripts/ui/talent_detail_popup.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const GRID_COLUMNS := 4
const GRID_ROWS := 5  # 20 卡 = 4 × 5；面板高度够就不出滚动条，不够 ScrollContainer 自动纵向滚动
const CARD_ASPECT := Vector2(130.0, 170.0)  # 参考比例
const CARD_H_MARGIN := 12.0
const CARD_V_MARGIN := 16.0
const DEBUG_BUTTON_TINT := Color("#efb840")

@onready var _title_label: Label = $Title
@onready var _scroll: ScrollContainer = $Scroll
@onready var _grid: GridContainer = $Scroll/CardGrid
@onready var _draw_button: TextureButton = $DrawButton
@onready var _cost_label: Label = get_node_or_null("DrawButton/VBox/GoldRow/CostLabel") as Label
@onready var _draw_label: Label = get_node_or_null("DrawButton/VBox/TitleLabel") as Label
@onready var _debug_unlock_btn: Button = $DebugUnlockButton

var _slot_by_id: Dictionary = {}   # id -> Control (TalentCardSlot)
var _placeholder_slots: Array = [] # 空槽
var _last_popup: Node = null


func _ready() -> void:
	if _grid == null:
		# 兜底：如果 .tscn 里字段名对不上，用代码生成
		_build_layout_from_code()
	else:
		_grid.columns = GRID_COLUMNS
		_fit_scroll_to_grid()
		_populate_grid()
	# 强制让 Title 不拦截鼠标（tscn 里的 mouse_filter=2 会被编辑器保存时抹掉，这里代码兜底）
	# Title 横贯顶部与右上 DebugUnlockButton y 范围重叠；默认 STOP 会吃掉 button 的点击
	if _title_label != null:
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 保底：DebugUnlockButton 明写 STOP + z_index 提到最上层，防止任何祖先 / 兄弟节点抢事件
	if _debug_unlock_btn != null:
		_debug_unlock_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_debug_unlock_btn.z_index = 5
		_debug_unlock_btn.disabled = false
	_apply_texts()
	_apply_button_style()
	_update_cost_visual()
	if _draw_button != null:
		_draw_button.pressed.connect(_on_draw_pressed)
		_setup_button_press(_draw_button)
	if _debug_unlock_btn != null:
		# pressed = 一次完整 down+up；button_down = 按下瞬间就触发，冗余以防事件被吞
		_debug_unlock_btn.pressed.connect(_on_debug_unlock_pressed)
		print("[TalentCardsPanel] DebugUnlockButton connected pressed. mouse_filter=%d disabled=%s size=%s pos=%s" % [
			_debug_unlock_btn.mouse_filter,
			str(_debug_unlock_btn.disabled),
			str(_debug_unlock_btn.size),
			str(_debug_unlock_btn.global_position),
		])
	if EventBus:
		EventBus.talent_changed.connect(_on_talent_changed)
		EventBus.gold_changed.connect(_on_gold_changed)
		EventBus.language_changed.connect(_on_language_changed)
	# 进场动效：每次面板可见时从右飞入（参考 lucky_spin_panel._play_intro，方向镜像）
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _apply_button_style() -> void:
	# DrawButton 现在是 btn_orange 贴图按钮，不走 9-slice 样式
	if _debug_unlock_btn != null:
		UiStyle.apply_primary_button(_debug_unlock_btn, DEBUG_BUTTON_TINT, 8)


# 按钮按下缩放效果（参考 equipment_panel._setup_action_button_press）
const _PRESS_SCALE := 0.9

# 进场飞入动效（参考 lucky_spin_panel，方向改为从右）
const INTRO_OFFSET_X := 600.0   # 飞入起点：原位右侧 600px
const INTRO_STEP := 0.06        # 每个元素错峰间隔（秒）
const INTRO_DURATION := 0.28    # 单元素飞入时长（秒）
var _intro_playing := false
var _intro_base_offsets: Dictionary = {}   # 元素 instance_id -> Vector2(offset_left, offset_right) 基准


func _on_visibility_changed() -> void:
	if visible:
		_play_intro(_collect_intro_elems())


func _collect_intro_elems() -> Array[Control]:
	# 顶层可见元素（从上到下：标题→调试按钮→卡牌区→抽取按钮）
	var elems: Array[Control] = []
	if _title_label != null:
		elems.append(_title_label)
	if _debug_unlock_btn != null:
		elems.append(_debug_unlock_btn)
	if _scroll != null:
		elems.append(_scroll)
	if _draw_button != null:
		elems.append(_draw_button)
	return elems


func _play_intro(elems: Array) -> void:
	if elems.is_empty():
		return
	_intro_playing = true
	# 首次记录各元素基准 offset（用于反复进出面板时复位）
	if _intro_base_offsets.is_empty():
		for c in elems:
			_intro_base_offsets[c.get_instance_id()] = Vector2(c.offset_left, c.offset_right)
	# 起点：offset_left / offset_right 同步右移 600（保持宽度不塌陷）+ 透明度 0
	for c in elems:
		var base: Vector2 = _intro_base_offsets[c.get_instance_id()]
		c.offset_left = base.x + INTRO_OFFSET_X
		c.offset_right = base.y + INTRO_OFFSET_X
		c.modulate.a = 0.0
	# 错峰飞入：左右 offset 平移回基准（宽度恒定）+ alpha 回 1
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(elems.size()):
		var c: Control = elems[i]
		var base: Vector2 = _intro_base_offsets[c.get_instance_id()]
		var delay := INTRO_STEP * float(i)
		tw.tween_property(c, "offset_left", base.x, INTRO_DURATION).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "offset_right", base.y, INTRO_DURATION).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "modulate:a", 1.0, INTRO_DURATION * 0.7).set_delay(delay)
	tw.chain().tween_callback(_on_intro_done)


func _on_intro_done() -> void:
	_intro_playing = false
	_update_cost_visual()

func _setup_button_press(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.button_down.connect(_on_draw_btn_down.bind(btn))
	btn.button_up.connect(_on_draw_btn_up.bind(btn))


func _on_draw_btn_down(btn: TextureButton) -> void:
	if btn == null or btn.disabled:
		return
	btn.pivot_offset = Vector2(floorf(btn.size.x * 0.5), floorf(btn.size.y * 0.5))
	btn.scale = Vector2.ONE * _PRESS_SCALE
	btn.modulate = Color(0.92, 0.92, 0.96)


func _on_draw_btn_up(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.scale = Vector2.ONE
	btn.modulate = Color.WHITE


func _build_layout_from_code() -> void:
	# 兜底：全代码构建，防止 .tscn 缺失时崩溃。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color("#ffffff"))
	_title_label.add_theme_color_override("font_outline_color", Color("#141824"))
	_title_label.add_theme_constant_override("outline_size", 6)
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.offset_top = 12.0
	_title_label.offset_bottom = 48.0
	add_child(_title_label)

	_grid = GridContainer.new()
	_grid.name = "CardGrid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", int(CARD_H_MARGIN))
	_grid.add_theme_constant_override("v_separation", int(CARD_V_MARGIN))
	_grid.anchor_left = 0.5
	_grid.anchor_right = 0.5
	_grid.anchor_top = 0.0
	_grid.offset_left = -278.0
	_grid.offset_right = 278.0
	_grid.offset_top = 60.0
	_grid.offset_bottom = 500.0
	add_child(_grid)

	_populate_grid()

	_draw_button = TextureButton.new()
	_draw_button.name = "DrawButton"
	_draw_button.custom_minimum_size = Vector2(240, 84)
	_draw_button.anchor_left = 0.5
	_draw_button.anchor_right = 0.5
	_draw_button.anchor_top = 1.0
	_draw_button.anchor_bottom = 1.0
	_draw_button.offset_left = -120.0
	_draw_button.offset_right = 120.0
	_draw_button.offset_top = -130.0
	_draw_button.offset_bottom = -46.0
	add_child(_draw_button)

	_draw_label = Label.new()
	_draw_label.name = "DrawLabel"
	_draw_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draw_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_draw_label.add_theme_font_size_override("font_size", 26)
	_draw_label.add_theme_color_override("font_color", Color("#ffffff"))
	_draw_label.add_theme_color_override("font_outline_color", Color("#2a1808"))
	_draw_label.add_theme_constant_override("outline_size", 4)
	_draw_label.anchor_left = 0.0
	_draw_label.anchor_right = 1.0
	_draw_label.anchor_top = 0.0
	_draw_label.anchor_bottom = 0.5
	_draw_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_button.add_child(_draw_label)

	_cost_label = Label.new()
	_cost_label.name = "CostLabel"
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", 20)
	_cost_label.add_theme_color_override("font_color", Color("#fff4a0"))
	_cost_label.add_theme_color_override("font_outline_color", Color("#3a2408"))
	_cost_label.add_theme_constant_override("outline_size", 4)
	_cost_label.anchor_left = 0.0
	_cost_label.anchor_right = 1.0
	_cost_label.anchor_top = 0.5
	_cost_label.anchor_bottom = 1.0
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_button.add_child(_cost_label)


class _DrawButtonBg extends Control:
	# 已弃用：现在用 UiStyleHelper.apply_primary_button 走项目 9-slice 主按钮规范。
	func _draw() -> void:
		pass


func _fit_scroll_to_grid() -> void:
	if _scroll == null:
		return
	# 让 ScrollContainer 宽度 = 网格内容宽度并水平居中。
	# 原因：GridContainer 在 ScrollContainer 内不靠 SHRINK_CENTER 居中（内容容器收缩到子节点尺寸并左对齐），
	# 直接让 Scroll 宽度 == 网格宽度，网格填满 Scroll，Scroll 本身居中 → 网格正中（与标题对齐）。
	var grid_w := CARD_ASPECT.x * float(GRID_COLUMNS) + CARD_H_MARGIN * float(GRID_COLUMNS - 1)
	_scroll.anchor_left = 0.5
	_scroll.anchor_right = 0.5
	_scroll.offset_left = -grid_w * 0.5
	_scroll.offset_right = grid_w * 0.5


func _populate_grid() -> void:
	# 清空
	for child in _grid.get_children():
		child.queue_free()
	_slot_by_id.clear()
	_placeholder_slots.clear()

	var ids := LobbyState.talent_order
	var real_count := ids.size()
	var min_cells: int = maxi(real_count, GRID_COLUMNS * GRID_ROWS)
	# 补齐到整行
	var rows := int(ceil(float(min_cells) / float(GRID_COLUMNS)))
	var total_cells := rows * GRID_COLUMNS

	for i in range(total_cells):
		var slot: Control = TalentCardSlotT.instantiate()
		slot.slot_size = CARD_ASPECT
		slot.custom_minimum_size = CARD_ASPECT
		_grid.add_child(slot)
		if i < real_count:
			var tid: String = ids[i]
			var def := LobbyState.get_talent_def(tid)
			var lv := LobbyState.get_talent_level(tid)
			slot.set_data(def, lv)
			slot.card_clicked.connect(_on_slot_clicked)
			_slot_by_id[tid] = slot
		else:
			slot.set_locked_placeholder()
			_placeholder_slots.append(slot)


func _apply_texts() -> void:
	if _title_label != null:
		_title_label.text = LanguageManager.tr_ui("UI_TALENT_TITLE")
	if _draw_label != null:
		_draw_label.text = LanguageManager.tr_ui("UI_DRAW_BTN")
	if _debug_unlock_btn != null:
		_debug_unlock_btn.text = LanguageManager.tr_ui("UI_TALENT_DEBUG_UNLOCK_ALL")
	_update_cost_visual()


func _update_cost_visual() -> void:
	var cost := LobbyState.TALENT_DRAW_COST
	var held := LobbyState.gold
	var affordable := held >= cost
	if _cost_label != null:
		_cost_label.text = "%d/%d" % [cost, held]
		_cost_label.add_theme_color_override("font_color", Color("#ff7070") if not affordable else Color(1, 1, 1))
	if _draw_button != null:
		_draw_button.disabled = not affordable
		# 进场飞入期间不覆盖 alpha（避免和 intro 的 modulate:a 打架）
		if not _intro_playing:
			_draw_button.modulate = Color(0.6, 0.6, 0.6) if not affordable else Color.WHITE


func _on_gold_changed(_g: int) -> void:
	_update_cost_visual()


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	for slot in _slot_by_id.values():
		if slot != null and slot.has_method("_refresh"):
			slot.call("_refresh")


func _on_draw_pressed() -> void:
	if _last_popup != null and is_instance_valid(_last_popup):
		return
	var result := LobbyState.draw_talent_card()
	if result.is_empty():
		# 金币不足
		_flash_button_red()
		return
	if result.get("status", "") == "max_all":
		_flash_button_red()
		return
	# 弹结果 popup（放到最顶层：main_menu 之上）
	var popup: Node = TalentDrawResultPopupT.new()
	_last_popup = popup
	popup.closed.connect(_on_draw_popup_closed)
	# 挂到 root 以覆盖底部选项卡
	var root_layer := get_tree().current_scene
	if root_layer != null:
		root_layer.add_child(popup)
	else:
		add_child(popup)
	popup.show_for_result(result)


func _on_draw_popup_closed(id: String, level_before: int, level_after: int, is_new: bool) -> void:
	_last_popup = null
	if id.is_empty():
		return
	var slot: Control = _slot_by_id.get(id) as Control
	if slot == null:
		return
	# 重新绑定 def + 新等级（触发内部 refresh）
	var def := LobbyState.get_talent_def(id)
	slot.set_data(def, level_after)
	# 新卡：整卡缩放；升级：LV 数字动画
	if is_new:
		slot.play_new_card_anim()
	else:
		slot.play_level_up_anim(level_before, level_after)


func _on_slot_clicked(id: String) -> void:
	if _last_popup != null and is_instance_valid(_last_popup):
		return
	var owned := LobbyState.get_owned_talent_ids()
	if owned.is_empty():
		return
	var popup: Node = TalentDetailPopupT.new()
	_last_popup = popup
	popup.closed.connect(func():
		_last_popup = null
	)
	var root_layer := get_tree().current_scene
	if root_layer != null:
		root_layer.add_child(popup)
	else:
		add_child(popup)
	popup.show_for_index(owned, id)


func _flash_button_red() -> void:
	if _draw_button == null:
		return
	var tw := create_tween()
	tw.tween_property(_draw_button, "modulate", Color("#ff6060"), 0.08)
	tw.tween_property(_draw_button, "modulate", Color.WHITE, 0.18)


func _on_debug_unlock_pressed() -> void:
	# 调试专用：一键把所有 unlock 卡（橙）置为 LV1；LobbyState 会循环发 talent_changed
	# 让每张卡对应的 slot 收到刷新（由 _on_talent_changed 承接）
	print("[TalentCardsPanel] _on_debug_unlock_pressed FIRED")
	# 先记录哪些卡在 unlock 前是未拥有的 orange —— 这些才需要播放动画
	var newly_unlocked_ids: Array[String] = []
	for tid in _slot_by_id:
		var def := LobbyState.get_talent_def(tid)
		if str(def.get("unlock_flag", "")).is_empty():
			continue
		if LobbyState.get_talent_level(tid) < 1:
			newly_unlocked_ids.append(tid)
	LobbyState.force_unlock_all_orange()
	# 全量 refresh + 对刚 unlock 的橙卡播 new_card 动画（让用户看到明显视觉反馈）
	var refreshed := 0
	for tid in _slot_by_id:
		var slot: Control = _slot_by_id[tid] as Control
		if slot == null:
			continue
		var def := LobbyState.get_talent_def(tid)
		var lv := LobbyState.get_talent_level(tid)
		slot.set_data(def, lv)
		refreshed += 1
		if newly_unlocked_ids.has(tid) and slot.has_method("play_new_card_anim"):
			slot.call("play_new_card_anim")
	# button 自己 flash 一下确认已被点
	if _debug_unlock_btn != null:
		var tw := create_tween()
		tw.tween_property(_debug_unlock_btn, "modulate", Color("#ffffcc"), 0.1)
		tw.tween_property(_debug_unlock_btn, "modulate", Color.WHITE, 0.2)
	print("[TalentCardsPanel] refreshed %d slots, %d newly unlocked" % [refreshed, newly_unlocked_ids.size()])


func _on_talent_changed(_id: String, _old: int, _new: int) -> void:
	# 抽卡内部走 _on_draw_popup_closed 触发升级动画；调试按钮走 _on_debug_unlock_pressed 全量刷新
	# 此信号回调只保底一次数据同步，不重复播动画
	if _id.is_empty():
		return
	var slot: Control = _slot_by_id.get(_id) as Control
	if slot == null:
		return
	var def := LobbyState.get_talent_def(_id)
	slot.set_data(def, _new)
