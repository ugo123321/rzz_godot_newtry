extends Control
class_name EnergyInfoPopup

# 体力说明弹窗（场景 scenes/ui/energy_info_popup.tscn）：点 EnergyBar 弹出。
# 全屏置灰 overlay + 中央 popup02 面板 + 一句说明 + 底部"点击空白关闭"呼吸提示。
# 节点在场景里可视化，可直接拖尺寸/位置/字号。逻辑/动画参考 talent_draw_result_popup.gd。
# 点击 overlay / 根 任意位置 → 关闭。弹一次用一次（关闭后 queue_free）。

const SHOW_DURATION := 0.32
const HIDE_DURATION := 0.18

@onready var _overlay: ColorRect = $Overlay
@onready var _panel: Control = $Panel
@onready var _info_label: Label = %InfoLabel
@onready var _hint_label: Label = %HintLabel

var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Overlay 吞点击 → 关闭；Panel 用 IGNORE 让点击穿透到 overlay。
	if _overlay != null and not _overlay.gui_input.is_connected(_on_click_anywhere):
		_overlay.gui_input.connect(_on_click_anywhere)
	# 说明文字 / 关闭提示走 i18n（场景里的中文是占位，运行时覆盖）。
	if _info_label != null:
		_info_label.text = LanguageManager.tr_ui("UI_ENERGY_INFO_TEXT")
	if _hint_label != null:
		_hint_label.text = LanguageManager.tr_ui("UI_TALENT_CLOSE_HINT")
	_start_hint_breathing()


func show_info() -> void:
	_play_show_anim()


func _start_hint_breathing() -> void:
	if _hint_label == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_hint_label, "modulate:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_hint_label, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_show_anim() -> void:
	if _panel != null:
		_panel.pivot_offset = _panel.size * 0.5
		_panel.scale = Vector2(0.05, 0.05)
	modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)
	# TRANS_BACK 回弹：先冲过 1.0 再回落，一气呵成。
	if _panel != null:
		tw.tween_property(_panel, "scale", Vector2.ONE, SHOW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


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
		queue_free()
	)
