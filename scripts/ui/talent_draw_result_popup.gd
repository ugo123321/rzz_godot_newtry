extends Control
class_name TalentDrawResultPopup

# 抽卡结果弹窗：全屏 dim + 中央大卡 + 描述 + 点击关闭。
# 由 TalentCardsPanel 用 .new() + add_child 实例化，弹一次用一次（关闭后自动 queue_free）。
# emit closed(id, level_before, level_after, is_new)。

signal closed(id: String, level_before: int, level_after: int, is_new: bool)

const TalentCardSlotT = preload("res://scenes/ui/talent_card_slot.tscn")
const EFFECT_TEX := preload("res://assets/ui/effect/effect01.png")

const CARD_SIZE := Vector2(300.0, 400.0)
const SHOW_DURATION := 0.35
const HIDE_DURATION := 0.18
# 卡牌背后的旋转光效（effect01.png）
const EFFECT_SIZE := 520.0
const EFFECT_SPIN_PERIOD := 6.0
const EFFECT_ALPHA := 0.9

var _result: Dictionary = {}
var _overlay: ColorRect
var _effect: TextureRect
var _effect_spin: Tween
var _card: Control
var _desc_label: Label
var _hint_label: Label
var _pity_label: Label
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_for_result(result: Dictionary) -> void:
	_result = result
	_build_ui()
	_play_show_anim()


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.15, 0.08, 0.28, 0.9)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点击 overlay 关闭（overlay STOP 会吞事件，需要在 overlay 本身接收 gui_input）
	_overlay.gui_input.connect(_on_click_anywhere)
	add_child(_overlay)

	# ? 图案背景装饰（简单半透纹路，用 draw 实现于 overlay 之下的 Control）
	# 保持简单：仅用纯色 overlay

	# 卡牌背后的旋转光效（在 _card 之前 add_child，画在卡牌下层）
	_effect = TextureRect.new()
	_effect.texture = EFFECT_TEX
	_effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_effect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect.anchor_left = 0.5
	_effect.anchor_top = 0.5
	_effect.anchor_right = 0.5
	_effect.anchor_bottom = 0.5
	_effect.offset_left = -EFFECT_SIZE * 0.5
	_effect.offset_right = EFFECT_SIZE * 0.5
	_effect.offset_top = -EFFECT_SIZE * 0.5 - 30.0
	_effect.offset_bottom = EFFECT_SIZE * 0.5 - 30.0
	_effect.pivot_offset = Vector2(EFFECT_SIZE * 0.5, EFFECT_SIZE * 0.5)
	_effect.modulate = Color(1, 1, 1, EFFECT_ALPHA)
	add_child(_effect)

	_card = TalentCardSlotT.instantiate()
	_card.slot_size = CARD_SIZE
	_card.custom_minimum_size = CARD_SIZE
	_card.size = CARD_SIZE
	# 让卡片区域也点得穿，click on card 同样关闭
	_card.interactive = false
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.anchor_right = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -CARD_SIZE.x * 0.5
	_card.offset_top = -CARD_SIZE.y * 0.5 - 30.0
	_card.offset_right = CARD_SIZE.x * 0.5
	_card.offset_bottom = CARD_SIZE.y * 0.5 - 30.0
	add_child(_card)

	var def: Dictionary = _result.get("def", {})
	var level_after := int(_result.get("level_after", 1))
	_card.set_data(def, level_after)

	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_size_override("font_size", 24)
	_desc_label.add_theme_color_override("font_color", Color("#ffffff"))
	_desc_label.add_theme_color_override("font_outline_color", Color("#141824"))
	_desc_label.add_theme_constant_override("outline_size", 5)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.anchor_left = 0.0
	_desc_label.anchor_right = 1.0
	_desc_label.anchor_top = 0.5
	_desc_label.anchor_bottom = 0.5
	_desc_label.offset_top = CARD_SIZE.y * 0.5 - 20.0
	_desc_label.offset_bottom = CARD_SIZE.y * 0.5 + 40.0
	# 使用累计值描述（get_talent_desc_at_level 会用 level_after 缩放 {vN}）
	_desc_label.text = LobbyState.get_talent_desc_at_level(def, level_after)
	add_child(_desc_label)

	# 保底提示：抽卡结果 dict 里 is_pity 为 true 时才显示
	if bool(_result.get("is_pity", false)):
		_pity_label = Label.new()
		_pity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pity_label.add_theme_font_size_override("font_size", 22)
		_pity_label.add_theme_color_override("font_color", Color("#ffe066"))
		_pity_label.add_theme_color_override("font_outline_color", Color("#3a2408"))
		_pity_label.add_theme_constant_override("outline_size", 4)
		_pity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pity_label.anchor_left = 0.0
		_pity_label.anchor_right = 1.0
		_pity_label.anchor_top = 0.5
		_pity_label.anchor_bottom = 0.5
		_pity_label.offset_top = -CARD_SIZE.y * 0.5 - 90.0
		_pity_label.offset_bottom = -CARD_SIZE.y * 0.5 - 60.0
		_pity_label.text = LanguageManager.tr_ui("UI_TALENT_PITY_HIT")
		add_child(_pity_label)
		# 保底提示淡入 + 缩放动画
		_pity_label.modulate.a = 0.0
		_pity_label.pivot_offset = Vector2(CARD_SIZE.x * 0.5, 15)
		_pity_label.scale = Vector2(0.7, 0.7)
		var pt := create_tween()
		pt.set_parallel(true)
		pt.tween_property(_pity_label, "modulate:a", 1.0, 0.35).set_delay(0.2)
		pt.tween_property(_pity_label, "scale", Vector2(1.15, 1.15), 0.3).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.chain().tween_property(_pity_label, "scale", Vector2.ONE, 0.2)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -60.0
	_hint_label.offset_bottom = -30.0
	_hint_label.text = LanguageManager.tr_ui("UI_TALENT_CLOSE_HINT")
	add_child(_hint_label)
	_start_hint_breathing()


func _start_hint_breathing() -> void:
	# 呼吸循环：透明度 0.4 ↔ 1.0，2 秒一个周期
	if _hint_label == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_hint_label, "modulate:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hint_label, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_show_anim() -> void:
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.05, 0.05)
	modulate = Color(1, 1, 1, 0.0)
	# 光效随卡牌一起从小放大
	if _effect != null:
		_effect.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)
	# 单段带回弹的缩放：TRANS_BACK 会先冲过 1.0 再回落，一气呵成，避免两段拼接在峰值处顿一下
	tw.tween_property(_card, "scale", Vector2.ONE, SHOW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if _effect != null:
		tw.tween_property(_effect, "scale", Vector2.ONE, SHOW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_start_effect_spin()


func _start_effect_spin() -> void:
	if _effect == null:
		return
	if _effect_spin != null and _effect_spin.is_valid():
		_effect_spin.kill()
	_effect_spin = create_tween()
	# 线性无限旋转一圈（TAU 与 0 视觉等价，loop 无跳变）
	_effect_spin.set_loops()
	_effect_spin.tween_property(_effect, "rotation", TAU, EFFECT_SPIN_PERIOD).set_trans(Tween.TRANS_LINEAR)


func _gui_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _on_click_anywhere(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.0), HIDE_DURATION)
	tw.tween_callback(func():
		closed.emit(
			str(_result.get("id", "")),
			int(_result.get("level_before", 0)),
			int(_result.get("level_after", 0)),
			bool(_result.get("is_new", false)),
		)
		queue_free()
	)
