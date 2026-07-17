extends Control
class_name TalentCardSlot

# 单张天赋卡组件 —— 场景驱动（scenes/ui/talent_card_slot.tscn）：
#   - Background TextureRect：按品质切 card_*_bg.png；未解锁用 card_back_bg.png
#   - Icon TextureRect：按 def.icon（来自 talents.json，源自 card.xlsx B 列）加载 assets/ui/icons/cards/*.png
#   - 顶部 LVLabel / 底部 NameLabel
# 点击 emit card_clicked(id)；升级时 play_level_up_anim / play_new_card_anim 播动画。
# 子节点位置/锚点全在 .tscn 里调，这里只负责数据→贴图/文案的刷新。

signal card_clicked(id: String)

# 品质 → 背景贴图（0 白 / 1 蓝 / 2 紫 / 3 橙）
const QUALITY_BG_TEX := [
	preload("res://assets/ui/cards/card_white_bg.png"),
	preload("res://assets/ui/cards/card_blue_bg.png"),
	preload("res://assets/ui/cards/card_purple_bg.png"),
	preload("res://assets/ui/cards/card_orange_bg.png"),
]
const BACK_TEX := preload("res://assets/ui/cards/card_back_bg.png")

# 文字字号 / 边距以 130×170 小卡为基准，按卡牌尺寸等比缩放（大卡 300×400 ≈ 2.31×）。
const REF_SMALL_W := 130.0
const LV_FONT_BASE := 18
const NAME_FONT_BASE := 16
const LV_OFF_TOP := 6.0
const LV_OFF_BOTTOM := 30.0
const NAME_OFF_TOP := -34.0
const NAME_OFF_BOTTOM := -6.0

@export var slot_size: Vector2 = Vector2(130.0, 170.0):
	set(v):
		slot_size = v
		custom_minimum_size = v
		if is_inside_tree():
			_refresh()

@export var interactive: bool = true  # false = 展示用，clicks 穿透（弹窗里放大卡用）

@onready var _bg: TextureRect = $Background
@onready var _icon: TextureRect = $Icon
@onready var _lv_label: Label = $LVLabel
@onready var _name_label: Label = $NameLabel

var _def: Dictionary = {}
var _level: int = 0
var _locked: bool = true
var _lv_tween: Tween
var _pressed: bool = false
var _icon_cache: Dictionary = {}  # icon name -> Texture2D


func _ready() -> void:
	custom_minimum_size = slot_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive else Control.MOUSE_FILTER_STOP
	if EventBus:
		EventBus.language_changed.connect(_on_language_changed)
	# 卡牌尺寸变化时重排文字（网格容器 / 弹窗赋尺寸后会触发）
	if not resized.is_connected(_apply_text_layout):
		resized.connect(_apply_text_layout)
	_apply_text_layout()


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


func _icon_tex(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var t := load("res://assets/ui/icons/cards/%s.png" % icon_name)
	if t != null:
		_icon_cache[icon_name] = t
	return t


func _refresh() -> void:
	if _bg == null:
		return
	_apply_text_layout()
	if _locked:
		_bg.texture = BACK_TEX
		_icon.visible = false
		_lv_label.text = ""
		_name_label.text = ""
		return
	_bg.texture = QUALITY_BG_TEX[clampi(int(_def.get("quality", 0)), 0, QUALITY_BG_TEX.size() - 1)]
	_icon.texture = _icon_tex(str(_def.get("icon", "")))
	_icon.visible = _icon.texture != null
	var max_lv := int(_def.get("max_level", 1))
	if _level >= max_lv:
		_lv_label.text = LanguageManager.tr_ui("UI_TALENT_MAX_LEVEL")
	else:
		_lv_label.text = LanguageManager.tr_ui("UI_TALENT_LV_FMT") % _level
	_name_label.text = LanguageManager.localize(_def, "name")


func _apply_text_layout() -> void:
	if _lv_label == null or _name_label == null:
		return
	# 等比缩放因子：以 130 宽小卡为 1.0；尺寸未就绪时回落 1.0（用场景默认字号/边距）
	var w := size.x
	var sc: float = w / REF_SMALL_W if w > 0.0 else 1.0
	if sc < 0.1:
		sc = 1.0
	_lv_label.add_theme_font_size_override("font_size", maxi(8, int(round(LV_FONT_BASE * sc))))
	_lv_label.offset_top = LV_OFF_TOP * sc
	_lv_label.offset_bottom = LV_OFF_BOTTOM * sc
	_name_label.add_theme_font_size_override("font_size", maxi(8, int(round(NAME_FONT_BASE * sc))))
	_name_label.offset_top = NAME_OFF_TOP * sc
	_name_label.offset_bottom = NAME_OFF_BOTTOM * sc


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
