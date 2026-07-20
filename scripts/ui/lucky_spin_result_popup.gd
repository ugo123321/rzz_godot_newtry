extends Control
class_name LuckySpinResultPopup

# 幸运转盘抽中后的结果弹窗：全屏 dim + 中央金币 icon + icon 下层旋转光效 + icon 上 "+N" 文字
# + 底部呼吸"点击空白处关闭"提示。结构与动效参考 talent_draw_result_popup。

signal closed()

const EFFECT_TEX := preload("res://assets/ui/effect/effect01.png")
const GOLD_TEX := preload("res://assets/ui/icons/currency/icon_cur_gold.png")

const ICON_SIZE := 220.0
const EFFECT_SIZE := 360.0
const SHOW_DURATION := 0.4
const HIDE_DURATION := 0.18
const EFFECT_SPIN_PERIOD := 6.0
const EFFECT_ALPHA := 0.9

var _gain := 0
var _overlay: ColorRect
var _effect: TextureRect
var _icon: TextureRect
var _amount_label: Label
var _hint_label: Label
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	# 每帧累加旋转（tween_property+set_loops 会因起始值重取而转一圈后停）
	if _effect != null:
		_effect.rotation += delta * (TAU / EFFECT_SPIN_PERIOD)


func show_result(gain: int) -> void:
	_gain = gain
	_build_ui()
	_play_show_anim()


func _build_ui() -> void:
	# 全屏置灰
	_overlay = ColorRect.new()
	_overlay.color = Color(0.15, 0.08, 0.28, 0.9)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_click_anywhere)
	add_child(_overlay)

	# 旋转光效（icon 下层，先 add 画在 icon 后面）
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
	_effect.offset_top = -EFFECT_SIZE * 0.5
	_effect.offset_bottom = EFFECT_SIZE * 0.5
	_effect.pivot_offset = Vector2(EFFECT_SIZE * 0.5, EFFECT_SIZE * 0.5)
	_effect.modulate = Color(1, 1, 1, EFFECT_ALPHA)
	add_child(_effect)

	# 金币 icon
	_icon = TextureRect.new()
	_icon.texture = GOLD_TEX
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.anchor_left = 0.5
	_icon.anchor_top = 0.5
	_icon.anchor_right = 0.5
	_icon.anchor_bottom = 0.5
	_icon.offset_left = -ICON_SIZE * 0.5
	_icon.offset_right = ICON_SIZE * 0.5
	_icon.offset_top = -ICON_SIZE * 0.5
	_icon.offset_bottom = ICON_SIZE * 0.5
	_icon.pivot_offset = Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	add_child(_icon)

	# icon 上方的 "+N" 奖励数额
	_amount_label = Label.new()
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.add_theme_font_size_override("font_size", 56)
	_amount_label.add_theme_color_override("font_color", Color("#fff4a0"))
	_amount_label.add_theme_color_override("font_outline_color", Color("#3a2408"))
	_amount_label.add_theme_color_override("font_shadow_color", Color("#3a2408"))
	_amount_label.add_theme_constant_override("outline_size", 8)
	_amount_label.add_theme_constant_override("shadow_outline_size", 6)
	_amount_label.add_theme_constant_override("shadow_offset_y", 2)
	_amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_amount_label.anchor_left = 0.5
	_amount_label.anchor_top = 0.5
	_amount_label.anchor_right = 0.5
	_amount_label.anchor_bottom = 0.5
	_amount_label.offset_left = -160.0
	_amount_label.offset_right = 160.0
	# 放在 icon 上方（icon 顶部 = -ICON_SIZE/2，再留 20px 间距）
	_amount_label.offset_top = -ICON_SIZE * 0.5 - 84.0
	_amount_label.offset_bottom = -ICON_SIZE * 0.5 - 20.0
	_amount_label.text = "+%d" % _gain
	add_child(_amount_label)

	# 底部呼吸关闭提示
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
	if _hint_label == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_hint_label, "modulate:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hint_label, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_show_anim() -> void:
	_icon.scale = Vector2(0.1, 0.1)
	_effect.scale = Vector2(0.5, 0.5)
	modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)
	# 单段回弹缩放，避免两段拼接顿挫（同 talent_draw_result_popup）
	tw.tween_property(_icon, "scale", Vector2.ONE, SHOW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_effect, "scale", Vector2.ONE, SHOW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _gui_input(event: InputEvent) -> void:
	_close_if_clicked(event)


func _on_click_anywhere(event: InputEvent) -> void:
	_close_if_clicked(event)


func _close_if_clicked(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.0), HIDE_DURATION)
	tw.tween_callback(func():
		closed.emit()
		queue_free()
	)
