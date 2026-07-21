extends Control
class_name ChestResultPopup

# 宝箱开启结果弹窗：全屏 dim + 中央像素 icon（银币 / 钥匙）+ icon 下层旋转光效 + "+N" 文字。
# 结构与动效参考 lucky_spin_result_popup；icon 用过程化 ImageTexture（CLAUDE.md §9），无外部素材。

signal closed()

const EFFECT_TEX := preload("res://assets/ui/effect/effect01.png")

const ICON_SIZE := 220.0
const EFFECT_SIZE := 360.0
const SHOW_DURATION := 0.4
const HIDE_DURATION := 0.18
const EFFECT_SPIN_PERIOD := 6.0
const EFFECT_ALPHA := 0.9
const ICON_TEX_PX := 64  # 过程化 icon 图像分辨率

var _amount := 0
var _kind := "silver"  # "silver" | "key"
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
	if _effect != null:
		_effect.rotation += delta * (TAU / EFFECT_SPIN_PERIOD)


func show_result(amount: int, kind: String) -> void:
	_amount = amount
	_kind = kind
	_build_ui()
	_play_show_anim()


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.12, 0.08, 0.22, 0.9)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_click_anywhere)
	add_child(_overlay)

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

	# 过程化像素 icon：Image + ImageTexture（CLAUDE.md §9 多色分层）
	_icon = TextureRect.new()
	_icon.texture = _build_icon_texture(_kind)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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

	var fmt_key := "UI_CHEST_RESULT_SILVER_FMT" if _kind == "silver" else "UI_CHEST_RESULT_KEY_FMT"
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
	_amount_label.offset_left = -200.0
	_amount_label.offset_right = 200.0
	_amount_label.offset_top = -ICON_SIZE * 0.5 - 84.0
	_amount_label.offset_bottom = -ICON_SIZE * 0.5 - 20.0
	_amount_label.text = LanguageManager.tr_ui(fmt_key) % _amount
	add_child(_amount_label)

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


# 用 Image.set_pixel 过程化绘制银币 / 钥匙像素图，返回 ImageTexture。
func _build_icon_texture(kind: String) -> ImageTexture:
	var img := Image.create(ICON_TEX_PX, ICON_TEX_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = ICON_TEX_PX * 0.5
	var cy: float = ICON_TEX_PX * 0.5
	if kind == "silver":
		_paint_silver_coin(img, cx, cy, ICON_TEX_PX * 0.42)
	else:
		_paint_key(img, cx, cy, ICON_TEX_PX * 0.42)
	return ImageTexture.create_from_image(img)


func _px(img: Image, x: float, y: float, c: Color) -> void:
	var ix := int(round(x))
	var iy := int(round(y))
	if ix < 0 or iy < 0 or ix >= ICON_TEX_PX or iy >= ICON_TEX_PX:
		return
	img.set_pixel(ix, iy, c)


func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			if x * x + y * y <= r * r:
				_px(img, cx + x, cy + y, c)


func _rect_px(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	for dy in range(int(h)):
		for dx in range(int(w)):
			_px(img, x + dx, y + dy, c)


func _paint_silver_coin(img: Image, cx: float, cy: float, r: float) -> void:
	var c_base := Color("#9aa0a8")
	var c_high := Color("#d0d6dc")
	var c_rim := Color("#3a3e44")
	var c_mark := Color("#5a5e64")
	# 外发光圆晕
	_disc(img, cx, cy, r * 1.18, Color(0.7, 0.75, 0.8, 0.18))
	# 主体
	_disc(img, cx, cy, r, c_base)
	# 描边圆环
	for a in range(0, 360, 6):
		var rad: float = deg_to_rad(a)
		_px(img, cx + cos(rad) * r, cy + sin(rad) * r, c_rim)
		_px(img, cx + cos(rad) * (r - 1), cy + sin(rad) * (r - 1), c_rim)
	# 内圈高光环
	for a in range(0, 360, 8):
		var rad: float = deg_to_rad(a)
		_px(img, cx + cos(rad) * r * 0.72, cy + sin(rad) * r * 0.72, c_high)
	# 中心十字刻印
	var n: float = r * 0.32
	_rect_px(img, cx - n * 0.2, cy - n, n * 0.4, n * 2.0, c_mark)
	_rect_px(img, cx - n, cy - n * 0.2, n * 2.0, n * 0.4, c_mark)
	# 高光月牙
	for a in range(195, 300, 6):
		var rad: float = deg_to_rad(a)
		_px(img, cx - r * 0.18 + cos(rad) * r * 0.35, cy - r * 0.18 + sin(rad) * r * 0.35, c_high)


func _paint_key(img: Image, cx: float, cy: float, s: float) -> void:
	var c_base := Color("#d8b850")
	var c_shade := Color("#9a7a30")
	var c_high := Color("#f0e090")
	var c_rim := Color("#4a3818")
	# 外发光
	_disc(img, cx, cy, s * 1.25, Color(0.85, 0.75, 0.4, 0.18))
	# 钥匙头：圆环
	_disc(img, cx, cy - s * 0.55, s * 0.45, c_base)
	for a in range(0, 360, 6):
		var rad: float = deg_to_rad(a)
		_px(img, cx + cos(rad) * s * 0.45, cy - s * 0.55 + sin(rad) * s * 0.45, c_rim)
	_disc(img, cx, cy - s * 0.55, s * 0.2, Color(0.12, 0.1, 0.16, 1.0))  # 孔
	# 杆
	_rect_px(img, cx - s * 0.12, cy - s * 0.1, s * 0.24, s * 0.95, c_base)
	# 齿
	_rect_px(img, cx + s * 0.12, cy + s * 0.45, s * 0.28, s * 0.18, c_base)
	# 高光
	_rect_px(img, cx - s * 0.09, cy - s * 0.05, s * 0.06, s * 0.85, c_high)


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
