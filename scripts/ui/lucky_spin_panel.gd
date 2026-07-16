extends Control
class_name LuckySpinPanelView

# 旋转逻辑照抄 reward_wheel_popup.gd（局内抽奖关），不改原文件。
const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const SLOT_COUNT := 6
const SLOT_ANGLE := TAU / float(SLOT_COUNT)
const SPIN_DURATION := 2.7
# 暂定：旋转消耗 10 金币，6 格金币奖励 10/20/30/40/50/60。后续可抽 game_tuning.json。
const SPIN_COST := 10
const REWARDS := [10, 20, 30, 40, 50, 60]
const WHEEL_PAD := 4.0
# 单个扇区 slot 的尺寸（容纳放大的 icon+数字）。改这里或编辑器里 Icon/Amount 都能调大小。
const SLOT_SIZE := Vector2(120.0, 116.0)
# slot 圆环半径占转盘半径的比例（越小越靠中心）
const SLOT_RING_RATIO := 0.52

signal closed

@onready var _wheel_wrap: Control = %WheelWrap
@onready var _wheel: Control = %Wheel
@onready var _slots: Control = %Slots
@onready var _pointer: TextureRect = %Pointer
@onready var _spin_btn: Button = %SpinBtn
@onready var _result_label: Label = %ResultLabel
@onready var _decoration: TextureRect = get_node_or_null("WheelWrap/Decoration") as TextureRect

var _slot_nodes: Array[Control] = []
var _selected_index := -1
var _spinning := false
var _wheel_radius := 124.0
var _intro_playing := false
var _breath_phase := 0.0
const INTRO_OFFSET_X := 600.0   # 飞入起点：原位左侧 600px
const INTRO_STEP := 0.06        # 每个元素错峰间隔（秒）
const INTRO_DURATION := 0.28    # 单元素飞入时长（秒）

# 装饰灯呼吸（轻微明暗循环）
const BREATH_SPEED := 2.0        # 呼吸角速度（越大越快）
const BREATH_MIN := 0.45        # 最暗 modulate
const BREATH_MAX := 1.0         # 最亮 modulate


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_slot_nodes = [%Slot0, %Slot1, %Slot2, %Slot3, %Slot4, %Slot5]
	# 金额标签写入数字（数据驱动；icon/字体可在编辑器里改）
	for i in range(_slot_nodes.size()):
		var amt_label := _slot_nodes[i].get_node_or_null("Amount") as Label
		if amt_label != null and i < REWARDS.size():
			amt_label.text = str(REWARDS[i])

	UiStyle.apply_primary_button(_spin_btn, Color("#efb840"), 10)
	_apply_pixel_filter_tree(self)

	if _spin_btn != null:
		_spin_btn.pressed.connect(_on_spin_pressed)

	if EventBus:
		EventBus.gold_changed.connect(_on_gold_changed)
		EventBus.language_changed.connect(_on_language_changed)

	_apply_texts()
	_refresh_cost()
	# 等 WheelWrap 布局出 size 再摆 slot 圆环
	call_deferred("_layout_wheel_area")
	_wheel_wrap.resized.connect(_layout_wheel_area)
	# 进场动效：每次面板可见时从左飞入
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()   # 首次 _ready（若已可见）立刻播


func _exit_tree() -> void:
	if EventBus:
		if EventBus.gold_changed.is_connected(_on_gold_changed):
			EventBus.gold_changed.disconnect(_on_gold_changed)
		if EventBus.language_changed.is_connected(_on_language_changed):
			EventBus.language_changed.disconnect(_on_language_changed)


func _process(delta: float) -> void:
	_update_decoration_breath(delta)


func _update_decoration_breath(delta: float) -> void:
	if _decoration == null or not is_instance_valid(_decoration):
		return
	# 进场动效期间不动装饰 modulate（避免和飞入淡入打架）
	if _intro_playing:
		return
	_breath_phase += delta * BREATH_SPEED
	var t: float = (sin(_breath_phase) * 0.5 + 0.5)   # 0..1
	_decoration.modulate = Color(1.0, 1.0, 1.0, lerpf(BREATH_MIN, BREATH_MAX, t))


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	_refresh_cost()


func _on_gold_changed(_g: int) -> void:
	_refresh_cost()


func _apply_texts() -> void:
	var title := get_node_or_null("Title") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_LUCKY_SPIN_TITLE")
	if _result_label != null and _result_label.text == "":
		_result_label.text = LanguageManager.tr_ui("UI_LUCKY_SPIN_TIP")


func _apply_pixel_filter_tree(root: Node) -> void:
	if root is CanvasItem:
		var ci := root as CanvasItem
		var n := str(root.name)
		if n in ["WheelTex", "Decoration", "Pointer", "Icon"]:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in root.get_children():
		_apply_pixel_filter_tree(child)


# ─── 布局：slot 圆环排列（照抄 reward_wheel_popup._layout_slots）──────────
func _layout_wheel_area() -> void:
	if _wheel_wrap == null or _wheel == null:
		return
	var wrap_size := _wheel_wrap.size
	if wrap_size.x <= 0.0 or wrap_size.y <= 0.0:
		return
	_wheel.size = wrap_size
	_wheel.pivot_offset = _wheel.size * 0.5
	_wheel_radius = maxf(1.0, minf(wrap_size.x, wrap_size.y) * 0.5 - WHEEL_PAD)
	_layout_slots()


func _layout_slots() -> void:
	var center := _wheel.size * 0.5
	var ring_r := _wheel_radius * SLOT_RING_RATIO
	for i in range(_slot_nodes.size()):
		var node := _slot_nodes[i]
		if node == null:
			continue
		var ang := -PI * 0.5 + SLOT_ANGLE * float(i)
		var pos := center + Vector2(cos(ang), sin(ang)) * ring_r
		# 强制 slot 尺寸（覆盖 .tscn offset 固定值），pivot 取中心；rotation 让 VBox 的"下"(数字)朝圆心、icon 朝外
		node.size = SLOT_SIZE
		node.pivot_offset = node.size * 0.5
		node.position = pos - node.size * 0.5
		node.rotation = ang + PI * 0.5


# ─── 旋转（照抄 reward_wheel_popup._on_spin_pressed）──────────────────────
func _on_spin_pressed() -> void:
	if _spinning:
		return
	if not LobbyState.spend_gold(SPIN_COST):
		if _result_label != null:
			_result_label.text = LanguageManager.tr_ui("UI_LUCKY_SPIN_NO_GOLD")
		return
	_spinning = true
	_spin_btn.disabled = true
	_result_label.text = LanguageManager.tr_ui("UI_LUCKY_SPIN_SPINNING")
	_selected_index = randi() % SLOT_COUNT

	# desired_mod = -idx * SLOT_ANGLE：转盘顺时针转(rotation+)，选中格要负角度对齐 12 点指针
	var desired_mod := -float(_selected_index) * SLOT_ANGLE
	var current := _wheel.rotation
	var align_delta := fposmod(desired_mod - current, TAU)
	# 附加圈数必须是 TAU 整数倍，否则偏移 mod TAU 使指针指向格和 _selected_index 对不上
	var extra_spins := 4 + (randi() % 2)
	var target := current + TAU * float(extra_spins) + align_delta

	var tween := create_tween()
	tween.tween_property(_wheel, "rotation", target, SPIN_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_spin_finished)


func _on_spin_finished() -> void:
	_spinning = false
	if _selected_index < 0 or _selected_index >= REWARDS.size():
		_refresh_cost()
		return
	var gain := int(REWARDS[_selected_index])
	LobbyState.add_gold(gain)
	if _result_label != null:
		_result_label.text = LanguageManager.tr_ui("UI_LUCKY_SPIN_RESULT_FMT") % gain
	_refresh_cost()


func _refresh_cost() -> void:
	if _spin_btn == null:
		return
	_spin_btn.text = str(SPIN_COST)
	if not _spinning:
		_spin_btn.disabled = LobbyState.gold < SPIN_COST
		if not _intro_playing:
			_spin_btn.modulate = Color(1, 1, 1, 1) if LobbyState.gold >= SPIN_COST else Color(0.6, 0.6, 0.6, 1.0)


# ─── 进场动效：元素从左飞入 ───────────────────────────────
func _on_visibility_changed() -> void:
	if visible:
		_play_intro()


func _play_intro() -> void:
	# 收集顶层可见元素（从上到下：标题→转盘→结果→按钮）
	var elems: Array[Control] = []
	var title := get_node_or_null("Title") as Control
	if title != null:
		elems.append(title)
	if _wheel_wrap != null:
		elems.append(_wheel_wrap)
	if _result_label != null:
		elems.append(_result_label)
	if _spin_btn != null:
		elems.append(_spin_btn)
	if elems.is_empty():
		return
	_intro_playing = true
	# 先把按钮置灰态压住（避免飞入时被 _refresh_cost 覆盖 alpha）
	# 起点：每个元素 position.x 偏左、透明度 0
	for c in elems:
		c.modulate.a = 0.0
		c.position.x -= INTRO_OFFSET_X
	# 错峰飞入：position 平移回原位 + alpha 回 1
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(elems.size()):
		var c: Control = elems[i]
		var end_x: float = c.position.x + INTRO_OFFSET_X
		var delay := INTRO_STEP * float(i)
		tw.tween_property(c, "position:x", end_x, INTRO_DURATION).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "modulate:a", 1.0, INTRO_DURATION * 0.7).set_delay(delay)
	tw.chain().tween_callback(Callable(self, "_on_intro_done"))


func _on_intro_done() -> void:
	_intro_playing = false
	_refresh_cost()
