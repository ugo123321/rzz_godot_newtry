@tool
extends Control
class_name ScoutRewardPopup

# 侦察挂机收益 popup（会话内累计金币）
# - 节点结构在 scout_reward_popup.tscn；本脚本只做程序化样式（9-slice stylebox / 字体）+ 信号 + 刷新
# - 由 main_menu.tscn 直接实例化挂在主菜单根节点下
# - @tool：让编辑器打开 scout_reward_popup.tscn 时也能看到完整样式（_ready 套 stylebox + 文案）
# - 领取按钮把 LobbyState.get_scout_pending_gold() 加到金币；无冷却，可反复领
# - 参考 UI：cankao/11.jpg（主题 = 侦察收益 / 已侦察 hh:mm:ss / 187 每小时 / 领取按钮）

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const PANEL_MARGIN := 48.0
const PANEL_MIN_SIZE := Vector2(420.0, 560.0)
const REFRESH_INTERVAL := 1.0
const CLAIMED_FLOAT_DURATION := 1.2

@onready var _overlay: ColorRect = %Overlay
@onready var _panel: PanelContainer = %Panel
@onready var _vbox: VBoxContainer = %VBox
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _elapsed_label: Label = %ElapsedLabel
@onready var _hourly_icon: TextureRect = %HourlyIcon
@onready var _hourly_label: Label = %HourlyLabel
@onready var _item_slot: PanelContainer = %ItemSlot
@onready var _item_empty_label: Label = %ItemEmptyLabel
@onready var _hint_label: Label = %HintLabel
@onready var _claim_button: Button = %ClaimButton
@onready var _close_hint_label: Label = %CloseHintLabel
@onready var _claimed_float_label: Label = %ClaimedFloatLabel

var _refresh_accum := 0.0
var _claimed_float_time := 0.0


func _ready() -> void:
	# @tool：编辑器里也套程序化 stylebox + 文案 + 连信号，这样打开 tscn 能看到完整 popup。
	_apply_runtime_styling()
	if _overlay != null and not _overlay.gui_input.is_connected(_on_overlay_input):
		_overlay.gui_input.connect(_on_overlay_input)
	if _claim_button != null and not _claim_button.pressed.is_connected(_on_claim_pressed):
		_claim_button.pressed.connect(_on_claim_pressed)
	if not resized.is_connected(_on_root_resized):
		resized.connect(_on_root_resized)
	if is_instance_valid(EventBus) and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	_apply_texts()


func setup() -> void:
	# 运行时由 main_menu._ready 调一次：归位全屏 + 隐藏（样式/信号已在 _ready 处理）。
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_texts()


# 节点结构已在 scout_reward_popup.tscn；这里只套 .tscn 表达不了的程序化 stylebox / 字体。
func _apply_runtime_styling() -> void:
	if _panel != null:
		var panel_style := UiStyle.make_dialog_stylebox(Color.WHITE, 24)
		if panel_style != null:
			_panel.add_theme_stylebox_override("panel", panel_style)
			_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _item_slot != null:
		var slot_style := UiStyle.make_tooltip_stylebox(Color(0.92, 0.83, 0.62, 1.0), 16)
		if slot_style != null:
			_item_slot.add_theme_stylebox_override("panel", slot_style)
		else:
			var fb := StyleBoxFlat.new()
			fb.bg_color = Color(0.88, 0.76, 0.5, 1.0)
			fb.set_corner_radius_all(10)
			fb.set_content_margin_all(16.0)
			_item_slot.add_theme_stylebox_override("panel", fb)
	if _claim_button != null:
		UiStyle.apply_primary_button(_claim_button, Color("#efb840"), 12)
		_claim_button.add_theme_color_override("font_color", Color("#3b2612"))
		PixelUi.apply_ui_font(_claim_button)
	for lbl in [_title_label, _subtitle_label, _elapsed_label, _hourly_label, \
			_item_empty_label, _hint_label, _close_hint_label, _claimed_float_label]:
		if lbl != null:
			PixelUi.apply_ui_font(lbl)


func show_popup() -> void:
	_sync_root_size()
	_apply_texts()
	_refresh_dynamic_labels()
	_relayout_panel()
	visible = true
	move_to_front()
	_refresh_accum = 0.0


func hide_popup() -> void:
	visible = false


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_popup()


func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		size = vp


func _relayout_panel() -> void:
	if _panel == null:
		return
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size
	var panel_size := Vector2(
		clampf(vp.x - PANEL_MARGIN * 2.0, PANEL_MIN_SIZE.x, vp.x),
		clampf(vp.y * 0.70, PANEL_MIN_SIZE.y, vp.y - PANEL_MARGIN * 2.0)
	)
	var center := vp * 0.5
	_panel.position = center - panel_size * 0.5
	_panel.size = panel_size


func _on_root_resized() -> void:
	# 编辑器里保持场景里 Panel 的静态锚点（preset 8 居中 + min_size），不按视口重排。
	if Engine.is_editor_hint():
		return
	_sync_root_size()
	_relayout_panel()


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	_refresh_dynamic_labels()


func _apply_texts() -> void:
	if not is_instance_valid(LanguageManager):
		return
	if _title_label != null:
		_title_label.text = LanguageManager.tr_ui("UI_SCOUT_TITLE")
	if _subtitle_label != null:
		_subtitle_label.text = LanguageManager.tr_ui("UI_SCOUT_SUBTITLE")
	if _item_empty_label != null:
		_item_empty_label.text = LanguageManager.tr_ui("UI_SCOUT_ITEM_EMPTY")
	if _hint_label != null:
		_hint_label.text = LanguageManager.tr_ui("UI_SCOUT_HINT_HIGHER")
	if _close_hint_label != null:
		_close_hint_label.text = LanguageManager.tr_ui("UI_SCOUT_CLOSE_HINT")


func _refresh_dynamic_labels() -> void:
	if not is_instance_valid(LobbyState):
		return
	var elapsed := LobbyState.get_scout_accumulated_seconds()
	var hourly := LobbyState.get_scout_hourly_gold()
	var pending := LobbyState.get_scout_pending_gold()
	if _elapsed_label != null:
		_elapsed_label.text = "%s  %s" % [LanguageManager.tr_ui("UI_SCOUT_ELAPSED_LABEL"), _fmt_hms(elapsed)]
	if _hourly_label != null:
		_hourly_label.text = LanguageManager.tr_ui("UI_SCOUT_HOURLY_FMT") % hourly
	if _claim_button != null:
		if pending > 0:
			_claim_button.disabled = false
			_claim_button.text = LanguageManager.tr_ui("UI_SCOUT_CLAIM_BTN")
		else:
			_claim_button.disabled = true
			_claim_button.text = LanguageManager.tr_ui("UI_SCOUT_CLAIM_DISABLED")


func _on_claim_pressed() -> void:
	if not is_instance_valid(LobbyState):
		return
	var reward := LobbyState.claim_scout_reward()
	if reward <= 0:
		return
	_refresh_dynamic_labels()
	_show_claimed_float(reward)


func _show_claimed_float(reward: int) -> void:
	if _claimed_float_label == null:
		return
	_claimed_float_label.text = LanguageManager.tr_ui("UI_SCOUT_CLAIMED_FMT") % reward
	# 从领取按钮上方开始
	var start_pos := Vector2(size.x * 0.5, size.y * 0.5)
	if _claim_button != null:
		var rect := _claim_button.get_global_rect()
		start_pos = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 24.0)
	_claimed_float_label.position = start_pos - _claimed_float_label.size * 0.5
	_claimed_float_label.modulate.a = 1.0
	_claimed_float_label.visible = true
	_claimed_float_time = CLAIMED_FLOAT_DURATION


func _process(delta: float) -> void:
	if not visible:
		return
	if Engine.is_editor_hint():
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_dynamic_labels()
	if _claimed_float_time > 0.0 and _claimed_float_label != null and _claimed_float_label.visible:
		_claimed_float_time -= delta
		var t := clampf(1.0 - _claimed_float_time / CLAIMED_FLOAT_DURATION, 0.0, 1.0)
		_claimed_float_label.position.y -= delta * 32.0
		_claimed_float_label.modulate.a = 1.0 - t
		if _claimed_float_time <= 0.0:
			_claimed_float_label.visible = false


static func _fmt_hms(secs: int) -> String:
	var s := maxi(0, secs)
	var h := s / 3600
	var m := (s / 60) % 60
	var sec := s % 60
	return "%02d:%02d:%02d" % [h, m, sec]
