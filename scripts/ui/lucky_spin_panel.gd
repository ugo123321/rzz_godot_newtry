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

# 背景浮动光点（和主界面同款氛围）。纯代码生成，复用金币 icon 当贴图。
const FLOAT_COUNT := 14
const FLOAT_TEX_PATH := "res://assets/ui/icons/currency/icon_cur_gold.png"
var _float_layer: Control = null
var _float_tex: Texture2D = null
var _motes: Array = []   # 每项 {node, phase, speed, sway, sway_speed, base_x}

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
	_build_float_motes()

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


# ─── 背景浮动光点 ──────────────────────────────────────────
func _build_float_motes() -> void:
	_float_layer = get_node_or_null("FloatLayer") as Control
	if _float_layer == null:
		return
	if ResourceLoader.exists(FLOAT_TEX_PATH):
		_float_tex = load(FLOAT_TEX_PATH) as Texture2D
	# 无贴图也能跑：draw 时如果 tex==null 就跳过
	for i in range(FLOAT_COUNT):
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var size := randf_range(10.0, 22.0)
		t.custom_minimum_size = Vector2(size, size)
		t.size = Vector2(size, size)
		t.texture = _float_tex
		t.modulate = Color(1.0, 0.92, 0.55, 0.0)   # 金色，初始透明
		_float_layer.add_child(t)
		_motes.append({
			"node": t,
			"phase": randf() * 6.28,          # 随机起始相位
			"speed": randf_range(14.0, 34.0), # 上浮速度 px/s
			"sway": randf_range(10.0, 26.0),  # 左右漂移幅度
			"sway_speed": randf_range(0.6, 1.4),
			"base_x": 0.0,
			"life": randf() * 4.0,            # 当前生命周期计时（错峰）
			"max_life": randf_range(5.0, 9.0),
		})
	# 放入层后先摆随机位置
	_layout_motes_initial()


func _layout_motes_initial() -> void:
	var area := _float_layer.size if _float_layer != null else Vector2(720, 1280)
	if area.x <= 1.0 or area.y <= 1.0:
		area = Vector2(720, 1280)
	for m in _motes:
		var base_x := randf() * area.x
		m.base_x = base_x
		m.life = randf() * float(m.max_life)
		var y := area.y - (randf() * area.y * 0.6)   # 散布在下半到上
		(m.node as TextureRect).position = Vector2(base_x, y)


func _process(delta: float) -> void:
	_update_float_motes(delta)
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


func _update_float_motes(delta: float) -> void:
	if _float_layer == null or _motes.is_empty():
		return
	var area := _float_layer.size
	if area.x <= 1.0 or area.y <= 1.0:
		return
	for m in _motes:
		var node: TextureRect = m.node
		if node == null or not is_instance_valid(node):
			continue
		m.life += delta
		var t := float(m.life) / float(m.max_life)   # 0..1
		# 透明度：前 20% 淡入、后 25% 淡出
		var a: float
		if t < 0.2:
			a = t / 0.2
		elif t > 0.75:
			a = (1.0 - t) / 0.25
		else:
			a = 1.0
		# 上浮：y 从底部到顶部
		var y := area.y * (1.0 - t)
		# 左右漂移
		m.phase += delta * float(m.sway_speed)
		var x: float = float(m.base_x) + sin(m.phase) * float(m.sway)
		node.position = Vector2(x - node.size.x * 0.5, y - node.size.y * 0.5)
		var col := Color(1.0, 0.92, 0.55, a * 0.55)
		node.modulate = col
		# 一轮结束：重置到底部，随机 x / 相位，制造源源不断
		if m.life >= float(m.max_life):
			m.life = 0.0
			m.base_x = randf() * area.x
			m.phase = randf() * 6.28



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
