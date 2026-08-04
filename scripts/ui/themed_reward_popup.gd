extends Control
class_name ThemedRewardPopup

# 主题关（恶魔 / 天使）专属奖励 popup。
# 场景结构在 scenes/ui/themed_reward_popup.tscn：
#   - Panel (TextureRect)：texture 在 show_for_theme 里按主题切换 panel_shop_demon / panel_shop_angel
#   - TitleLabel / NameLabel / DescLabel（RichTextLabel）+ IconSlot（装卡片 icon）
#   - AcceptBtn (btn_blue) / DeclineBtn (btn_red) 两个 TextureButton
# 由 battle.gd 用 preload(tscn).instantiate() 实例化 + add_child 到 $UI。
# 弹出 / 消失走 tween（scale + modulate）；按钮按下走 scale 收缩。

const PixelCardIconT = preload("res://scripts/ui/pixel_card_icon.gd")
const DescFormatT = preload("res://scripts/utils/desc_format.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const CARD_ICON_SIZE := 96.0
const SHOW_DURATION := 0.34
const HIDE_DURATION := 0.20
const PRESS_DOWN_SCALE := 0.90
const PRESS_DOWN_TIME := 0.05
const PRESS_UP_TIME := 0.08

# 主题 → panel Texture2D / 标题 i18n key / 遮罩色
const THEME_PANEL_DEMON := preload("res://assets/ui/panels/panel_shop_demon.png")
const THEME_PANEL_ANGEL := preload("res://assets/ui/panels/panel_shop_angel.png")

signal reward_resolved(accepted: bool, upgrade: Dictionary)

var battle: Node
var _theme := ""           # "demon" / "angel"
var _upgrade: Dictionary = {}
var _active_tween: Tween = null
var _closing := false      # 渐出动画中（屏蔽按钮二次点击）

@onready var _dim: ColorRect = %Dim
@onready var _panel: TextureRect = %Panel
@onready var _title_label: Label = %TitleLabel
@onready var _name_label: Label = %NameLabel
@onready var _desc_label: RichTextLabel = %DescLabel
@onready var _icon_slot: Control = %IconSlot
@onready var _accept_btn: TextureButton = %AcceptBtn
@onready var _decline_btn: TextureButton = %DeclineBtn


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_texts()
	if not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	# 按钮按下 / 抬起弹性动画
	_accept_btn.button_down.connect(_on_btn_press.bind(_accept_btn))
	_accept_btn.button_up.connect(_on_btn_release.bind(_accept_btn))
	_accept_btn.pressed.connect(_on_accept)
	_decline_btn.button_down.connect(_on_btn_press.bind(_decline_btn))
	_decline_btn.button_up.connect(_on_btn_release.bind(_decline_btn))
	_decline_btn.pressed.connect(_on_decline)


func setup(battle_node: Node) -> void:
	# battle.gd 在 add_child（触发 _ready）之后调用，仅注入依赖；节点用 @onready 拿
	battle = battle_node


func _apply_texts() -> void:
	_title_label.text = LanguageManager.tr_ui(
		"UI_THEMED_ANGEL_TITLE" if _theme == "angel" else "UI_THEMED_DEMON_TITLE"
	)
	_accept_btn.get_node("Label").text = LanguageManager.tr_ui("UI_THEMED_ACCEPT")
	_decline_btn.get_node("Label").text = LanguageManager.tr_ui("UI_THEMED_DECLINE")


func _on_language_changed(_lang: String) -> void:
	_apply_texts()


func show_for_theme(theme: String, upgrade: Dictionary) -> void:
	_theme = theme
	_upgrade = upgrade
	_closing = false
	_apply_theme_palette()
	_apply_texts()
	_apply_upgrade_content()
	# 弹出动画：Dim 渐显 + Panel 从 0.55× 弹大到 1.0× 同时透明度 0→1
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.55, 0.55)
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	visible = true
	move_to_front()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_dim, "modulate:a", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_panel, "modulate:a", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_panel, "scale", Vector2.ONE, SHOW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_popup() -> void:
	# 立即隐藏（兜底；正常关闭走 _animate_close）
	visible = false


# 渐出动画：完成后 visible=false 并 emit 给定的回调
func _animate_close(then_emit: Callable) -> void:
	if _closing:
		return
	_closing = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_dim, "modulate:a", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_panel, "modulate:a", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_panel, "scale", Vector2(0.6, 0.6), HIDE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_active_tween.chain().tween_callback(func():
		visible = false
		_closing = false
		then_emit.call())


func _apply_theme_palette() -> void:
	# 切 panel 贴图 + 遮罩色；标题/文字色调由 tscn 默认（恶魔偏暖），天使略调
	if _theme == "demon":
		_panel.texture = THEME_PANEL_DEMON
		_dim.color = Color(0.18, 0.03, 0.05, 0.6)
		_title_label.modulate = Color(0.95, 0.85, 0.55)
		_name_label.modulate = Color(0.98, 0.94, 0.92)
		_desc_label.modulate = Color(0.98, 0.94, 0.92)
	else:
		_panel.texture = THEME_PANEL_ANGEL
		_dim.color = Color(0.55, 0.50, 0.22, 0.4)
		_title_label.modulate = Color(0.85, 0.70, 0.25)
		_name_label.modulate = Color(0.28, 0.20, 0.06)
		_desc_label.modulate = Color(0.28, 0.20, 0.06)


func _apply_upgrade_content() -> void:
	_name_label.text = LanguageManager.localize(_upgrade, "name")
	var raw_desc := LanguageManager.localize_field(_upgrade, "desc_cn_game_en", "desc_cn_game")
	if raw_desc.is_empty():
		raw_desc = LanguageManager.localize(_upgrade, "desc")
	DescFormatT.apply_to_rich_text(_desc_label, raw_desc, 20, true)
	# 重建 icon widget
	for child in _icon_slot.get_children():
		child.queue_free()
	# 优先：xlsx E 列 skill_XX 的 PNG + FRAME 边框
	var framed := UiStyle.build_reward_icon_with_frame(_upgrade, CARD_ICON_SIZE)
	if framed != null:
		_icon_slot.add_child(framed)
		return
	# fallback：程序化像素卡（emoji / 空 icon 卡走此路）
	var pixel := PixelCardIconT.new()
	pixel.upgrade = _upgrade
	pixel.icon_size = CARD_ICON_SIZE
	pixel.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
	pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_slot.add_child(pixel)


# 按钮按下：缩到 0.90（0.05s），抬起回弹到 1.0（0.08s）
func _on_btn_press(btn: TextureButton) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(PRESS_DOWN_SCALE, PRESS_DOWN_SCALE), PRESS_DOWN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_btn_release(btn: TextureButton) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE, PRESS_UP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_accept() -> void:
	if _closing:
		return
	var up := _upgrade
	_animate_close(func(): reward_resolved.emit(true, up))


func _on_decline() -> void:
	if _closing:
		return
	var up := _upgrade
	_animate_close(func(): reward_resolved.emit(false, up))
