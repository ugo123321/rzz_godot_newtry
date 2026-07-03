extends Control
class_name TalentCardSlot

# 单张天赋卡组件 —— 全程序化绘制：
#   - 卡片外框（品质色）+ 圆角背景
#   - 顶部 LV 标签（或"?"如果未拥有）
#   - 中央 icon（TalentPixelIcon）
#   - 底部名字丝带
# 点击时 emit card_clicked(id)。
# 升级时 play_level_up_anim(old, new) 播放缩放+闪光动画。

signal card_clicked(id: String)

const TalentPixelIconT = preload("res://scripts/ui/talent_pixel_icon.gd")

# 品质颜色（卡框描边 & 顶部星带）
const QUALITY_FRAME_COLORS := [
	Color("#dcdce6"), # 白
	Color("#58a8ff"), # 蓝
	Color("#b172ff"), # 紫
	Color("#ffa640"), # 橙
]
const QUALITY_BG_TINT := [
	Color("#3a3d55"),
	Color("#1e3a68"),
	Color("#3a1e68"),
	Color("#5a3a1c"),
]

@export var slot_size: Vector2 = Vector2(130.0, 170.0)
@export var interactive: bool = true  # false = 展示用，clicks 穿透（弹窗里放大卡用）

var _def: Dictionary = {}
var _level: int = 0
var _locked: bool = true
var _icon: Control
var _lv_label: Label
var _name_label: Label
var _lv_tween: Tween
var _pressed: bool = false


func _ready() -> void:
	custom_minimum_size = slot_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive else Control.MOUSE_FILTER_STOP
	_build_children()
	if EventBus:
		EventBus.language_changed.connect(_on_language_changed)


func set_data(def: Dictionary, level: int) -> void:
	_def = def
	_level = level
	_locked = def.is_empty() or level <= 0
	_refresh()


func set_locked_placeholder() -> void:
	_def = {}
	_level = 0
	_locked = true
	_refresh()


func get_talent_id() -> String:
	return str(_def.get("id", ""))


func get_level() -> int:
	return _level


func _build_children() -> void:
	_icon = TalentPixelIconT.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.anchor_left = 0.5
	_icon.anchor_top = 0.5
	_icon.anchor_right = 0.5
	_icon.anchor_bottom = 0.5
	add_child(_icon)

	_lv_label = Label.new()
	_lv_label.text = ""
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lv_label.add_theme_font_size_override("font_size", 18)
	_lv_label.add_theme_color_override("font_color", Color("#fff4a0"))
	_lv_label.add_theme_color_override("font_outline_color", Color("#2a1608"))
	_lv_label.add_theme_constant_override("outline_size", 4)
	_lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lv_label.anchor_left = 0.0
	_lv_label.anchor_right = 1.0
	_lv_label.offset_top = 6.0
	_lv_label.offset_bottom = 30.0
	_lv_label.pivot_offset = Vector2.ZERO
	add_child(_lv_label)

	_name_label = Label.new()
	_name_label.text = ""
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color("#ffffff"))
	_name_label.add_theme_color_override("font_outline_color", Color("#141824"))
	_name_label.add_theme_constant_override("outline_size", 4)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.anchor_left = 0.0
	_name_label.anchor_right = 1.0
	_name_label.anchor_top = 1.0
	_name_label.anchor_bottom = 1.0
	_name_label.offset_top = -34.0
	_name_label.offset_bottom = -6.0
	add_child(_name_label)


func _refresh() -> void:
	# 排布 icon 大小 = slot 宽的 60%
	var s := minf(size.x, slot_size.x)
	if s <= 0.0:
		s = slot_size.x
	var icon_s := s * 0.62
	_icon.icon_size = icon_s
	_icon.custom_minimum_size = Vector2(icon_s, icon_s)
	_icon.size = Vector2(icon_s, icon_s)
	_icon.offset_left = -icon_s * 0.5
	_icon.offset_top = -icon_s * 0.5 - 6.0
	_icon.offset_right = icon_s * 0.5
	_icon.offset_bottom = icon_s * 0.5 - 6.0
	if _locked:
		_icon.set_locked(true)
		_lv_label.text = ""
		_name_label.text = ""
	else:
		_icon.locked = false
		_icon.set_talent(str(_def.get("id", "")), int(_def.get("quality", 0)))
		var max_lv := int(_def.get("max_level", 1))
		if _level >= max_lv:
			_lv_label.text = LanguageManager.tr_ui("UI_TALENT_MAX_LEVEL")
		else:
			_lv_label.text = LanguageManager.tr_ui("UI_TALENT_LV_FMT") % _level
		_name_label.text = LanguageManager.localize(_def, "name")
	queue_redraw()


func _process(_dt: float) -> void:
	# slot 大小可能被 GridContainer 动态调整，需要每帧同步 icon 位置
	if _icon != null:
		var s := minf(size.x, size.y * 0.75)
		var icon_s := s * 0.62
		if abs(_icon.icon_size - icon_s) > 0.5:
			_icon.icon_size = icon_s
			_icon.custom_minimum_size = Vector2(icon_s, icon_s)
			_icon.size = Vector2(icon_s, icon_s)
			_icon.offset_left = -icon_s * 0.5
			_icon.offset_top = -icon_s * 0.5 - 6.0
			_icon.offset_right = icon_s * 0.5
			_icon.offset_bottom = icon_s * 0.5 - 6.0
			_icon.queue_redraw()
			queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var frame_color: Color
	var bg_tint: Color
	if _locked:
		frame_color = Color("#4a4f5c")
		bg_tint = Color("#282b38")
	else:
		var q := clampi(int(_def.get("quality", 0)), 0, QUALITY_FRAME_COLORS.size() - 1)
		frame_color = QUALITY_FRAME_COLORS[q]
		bg_tint = QUALITY_BG_TINT[q]

	# 圆角矩形背景（分层：外框 + 内亮层 + 深色底）
	var outer := Rect2(2, 2, w - 4, h - 4)
	draw_rect(outer, frame_color, true)
	var inner_pad := 4.0
	var inner := Rect2(2 + inner_pad, 2 + inner_pad, w - 4 - inner_pad * 2, h - 4 - inner_pad * 2)
	draw_rect(inner, bg_tint, true)

	# 顶部 LV 带（较亮丝带）
	if not _locked:
		var ribbon := Rect2(4, 4, w - 8, 26)
		var ribbon_col := Color(frame_color.r * 0.5, frame_color.g * 0.5, frame_color.b * 0.5, 0.85)
		draw_rect(ribbon, ribbon_col, true)

	# 底部名字丝带
	var name_ribbon := Rect2(4, h - 34, w - 8, 30)
	var name_col := Color(0.12, 0.14, 0.22, 0.9)
	draw_rect(name_ribbon, name_col, true)


func _draw_star(center: Vector2, radius: float, fill: Color, outline: Color) -> void:
	var pts: PackedVector2Array = []
	for i in range(10):
		var ang := deg_to_rad(-90.0 + float(i) * 36.0)
		var r := radius if (i % 2) == 0 else radius * 0.45
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, outline, 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if _locked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				scale = Vector2(0.95, 0.95)
			else:
				scale = Vector2.ONE
				if _pressed and get_local_mouse_position().x >= 0 and get_local_mouse_position().x <= size.x:
					card_clicked.emit(str(_def.get("id", "")))
				_pressed = false


func play_level_up_anim(old_lv: int, new_lv: int) -> void:
	# LV 数字滚动 + 缩放 + 描边金光
	if _lv_tween != null and _lv_tween.is_valid():
		_lv_tween.kill()
	_lv_label.pivot_offset = _lv_label.size * 0.5
	_lv_label.scale = Vector2.ONE
	_lv_tween = create_tween()
	_lv_tween.set_parallel(true)
	_lv_tween.tween_property(_lv_label, "scale", Vector2(1.7, 1.7), 0.18)
	_lv_tween.tween_property(_lv_label, "modulate", Color("#fff040"), 0.18)
	_lv_tween.chain().tween_property(_lv_label, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT)
	_lv_tween.parallel().tween_property(_lv_label, "modulate", Color.WHITE, 0.22)
	# 中途更新文字（0.18s 时切数字，满级时切"满级"文案）
	var to_lv := new_lv
	var to_max := int(_def.get("max_level", 1))
	_lv_tween.parallel().tween_callback(func():
		_level = to_lv
		if _level >= to_max:
			_lv_label.text = LanguageManager.tr_ui("UI_TALENT_MAX_LEVEL")
		else:
			_lv_label.text = LanguageManager.tr_ui("UI_TALENT_LV_FMT") % _level
	).set_delay(0.18)


func play_new_card_anim() -> void:
	# 首次获得：整卡缩放脉冲
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN)


func _on_language_changed(_lang: String) -> void:
	_refresh()
