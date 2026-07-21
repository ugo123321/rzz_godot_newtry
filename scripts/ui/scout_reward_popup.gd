@tool
extends Control
class_name ScoutRewardPopup

# 侦察挂机收益 popup（会话内累计金币）
# - 节点结构 / 贴图 / 字号 / 位置全部在 scout_reward_popup.tscn（引擎可编辑，策划可直接在编辑器里拖）
# - 本脚本只做：信号连接 + 淡入淡出动效 + 动态数值刷新（已侦察时长 / 每小时 / 待领数 / 槽位金币数）+ 领取逻辑 + i18n 文案
# - 由 main_menu.tscn 直接实例化挂在主菜单根节点下
# - @tool：让编辑器打开 scout_reward_popup.tscn 时也能套上文案（_ready → _apply_texts）
# - 领取按钮把 LobbyState.get_scout_pending_gold() 加到金币；无冷却，可反复领

const REFRESH_INTERVAL := 1.0
const CLAIMED_FLOAT_DURATION := 1.2
const SHOW_DURATION := 0.18
const HIDE_DURATION := 0.15
const PRESS_SCALE := 0.9

@onready var _overlay: ColorRect = %Overlay
@onready var _panel: Control = %Panel
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _elapsed_label: Label = %ElapsedLabel
@onready var _hourly_label: Label = %HourlyLabel
@onready var _hint_label: Label = %HintLabel
@onready var _claim_button: TextureButton = %ClaimButton
@onready var _claim_label: Label = get_node_or_null("Panel/ClaimButton/Label") as Label
@onready var _item_template: Control = %ItemTemplate
@onready var _close_hint_label: Label = %CloseHintLabel
@onready var _claimed_float_label: Label = %ClaimedFloatLabel

# 侦察可获得的道具列表（数据驱动）。
# 每项 = {icon: 道具 icon 贴图, get_count: 返回当前可领取数量}。
# 数量 > 0 的才依次放进 Slot_0..Slot_14；数量 = 0 的不出现（槽位空）。
# 未来新增侦察道具：在这里加一项即可，UI 自动从下一个空槽位开始放。
const GOLD_ICON := preload("res://assets/ui/icons/currency/icon_cur_gold.png")
const SLOT_COUNT := 15
var _scout_item_defs: Array = []

var _refresh_accum := 0.0
var _claimed_float_time := 0.0
var _active_tween: Tween = null
var _closing := false
var _claim_pressed := false
var _claim_base_scale := Vector2.ONE


func _ready() -> void:
	_build_scout_item_defs()
	_apply_texts()
	if _overlay != null and not _overlay.gui_input.is_connected(_on_overlay_input):
		_overlay.gui_input.connect(_on_overlay_input)
	if _claim_button != null:
		if not _claim_button.pressed.is_connected(_on_claim_pressed):
			_claim_button.pressed.connect(_on_claim_pressed)
		if not _claim_button.button_down.is_connected(_on_claim_button_down):
			_claim_button.button_down.connect(_on_claim_button_down)
		if not _claim_button.button_up.is_connected(_on_claim_button_up):
			_claim_button.button_up.connect(_on_claim_button_up)
		call_deferred("_cache_claim_button_pivot")
	if is_instance_valid(EventBus) and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	if not resized.is_connected(_on_root_resized):
		resized.connect(_on_root_resized)
	# 工具态：编辑器里也刷新一次文案，便于查看
	if Engine.is_editor_hint():
		_refresh_dynamic_labels()


# 领取按钮按下缩放（以中心为轴心），松开归位。基础 scale 来自 .tscn（编辑器里可调）。
func _cache_claim_button_pivot() -> void:
	if _claim_button == null or _claim_button.size.x <= 0.0:
		return
	_claim_button.pivot_offset = _claim_button.size * 0.5
	_claim_base_scale = _claim_button.scale
	_update_claim_button_scale()


func _on_claim_button_down() -> void:
	_claim_pressed = true
	_update_claim_button_scale()


func _on_claim_button_up() -> void:
	_claim_pressed = false
	_update_claim_button_scale()


func _update_claim_button_scale() -> void:
	if _claim_button == null:
		return
	_claim_button.scale = _claim_base_scale * (PRESS_SCALE if _claim_pressed else 1.0)


# 侦察可获得道具清单。当前只有金币；未来加新道具在此 append 一项即可。
func _build_scout_item_defs() -> void:
	if not _scout_item_defs.is_empty():
		return
	_scout_item_defs = [
		{"icon": GOLD_ICON, "get_count": Callable(self, "_get_pending_gold")},
	]


func _get_pending_gold() -> int:
	if not is_instance_valid(LobbyState):
		return 0
	return maxi(0, LobbyState.get_scout_pending_gold())


func setup() -> void:
	# 运行时由 main_menu._ready 调一次：归位全屏 + 隐藏。
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _overlay != null:
		_overlay.modulate.a = 0.0
	if _panel != null:
		_panel.modulate.a = 0.0
		_panel.scale = Vector2.ONE
	_apply_texts()


func show_popup() -> void:
	_sync_root_size()
	_apply_texts()
	_refresh_dynamic_labels()
	visible = true
	move_to_front()
	_closing = false
	_refresh_accum = 0.0
	_play_show_tween()


func hide_popup() -> void:
	if not visible:
		return
	if Engine.is_editor_hint():
		visible = false
		return
	_play_hide_tween()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_popup()


func _sync_root_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		size = vp


func _on_root_resized() -> void:
	if Engine.is_editor_hint():
		return
	_sync_root_size()


func _on_language_changed(_lang: String) -> void:
	_apply_texts()
	_refresh_dynamic_labels()


func _play_show_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	if _overlay != null:
		_overlay.modulate.a = 0.0
	if _panel != null:
		_panel.pivot_offset = _panel.size * 0.5
		_panel.scale = Vector2(0.92, 0.92)
		_panel.modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	if _overlay != null:
		_active_tween.tween_property(_overlay, "modulate:a", 1.0, SHOW_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _panel != null:
		_active_tween.tween_property(_panel, "modulate:a", 1.0, SHOW_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_panel, "scale", Vector2.ONE, SHOW_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_hide_tween() -> void:
	if _closing:
		return
	_closing = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	if _overlay != null:
		_active_tween.tween_property(_overlay, "modulate:a", 0.0, HIDE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _panel != null:
		_active_tween.tween_property(_panel, "modulate:a", 0.0, HIDE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_active_tween.tween_property(_panel, "scale", Vector2(0.96, 0.96), HIDE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.chain().tween_callback(func():
		visible = false
		_closing = false)


func _apply_texts() -> void:
	if not is_instance_valid(LanguageManager):
		return
	if _title_label != null:
		_title_label.text = LanguageManager.tr_ui("UI_SCOUT_TITLE")
	if _subtitle_label != null:
		_subtitle_label.text = LanguageManager.tr_ui("UI_SCOUT_SUBTITLE")
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
		var can_claim := pending > 0
		_claim_button.disabled = not can_claim
		# 暂无可领 → 整个按钮置灰（TextureButton 的 disabled 不自动灰化，手动 modulate）
		_claim_button.modulate = Color(0.35, 0.35, 0.35, 1.0) if not can_claim else Color.WHITE
		if _claim_label != null:
			_claim_label.text = LanguageManager.tr_ui("UI_SCOUT_CLAIM_BTN") if can_claim \
				else LanguageManager.tr_ui("UI_SCOUT_CLAIM_DISABLED")
	_refresh_slot_items()


# 把 "数量 > 0" 的可领取道具依次放进 Slot_0..Slot_14；数量 = 0 的不放（槽位空）。
# 每次 refresh 先清掉槽位里上次放的实例，再按当前数量重新放置。
func _refresh_slot_items() -> void:
	_clear_slot_items()
	if _item_template == null:
		return
	var slot_idx := 0
	for def in _scout_item_defs:
		if slot_idx >= SLOT_COUNT:
			break
		var count: int = maxi(0, int((def.get("get_count") as Callable).call()))
		if count <= 0:
			continue
		var icon_tex: Texture2D = def.get("icon") as Texture2D
		_place_item_in_slot(slot_idx, icon_tex, count)
		slot_idx += 1


func _clear_slot_items() -> void:
	for i in SLOT_COUNT:
		var slot := get_node_or_null("Panel/SlotsLayer/Slot_%d" % i) as Control
		if slot == null:
			continue
		for child in slot.get_children():
			child.queue_free()


# 复制 ItemTemplate（带 ItemIcon + CountLabel 的样式），铺满目标槽位，写入 icon 和数量文字。
func _place_item_in_slot(slot_idx: int, icon_tex: Texture2D, count: int) -> void:
	var slot := get_node_or_null("Panel/SlotsLayer/Slot_%d" % slot_idx) as Control
	if slot == null or _item_template == null:
		return
	var tpl := _item_template.duplicate()
	tpl.visible = true
	tpl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tpl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(tpl)
	var icon := tpl.get_node_or_null("ItemIcon") as TextureRect
	if icon != null and icon_tex != null:
		icon.texture = icon_tex
	var lbl := tpl.get_node_or_null("CountLabel") as Label
	if lbl != null:
		lbl.text = str(count)


func _on_claim_pressed() -> void:
	if not is_instance_valid(LobbyState):
		return
	var reward := LobbyState.claim_scout_reward()
	if reward <= 0:
		return
	_refresh_dynamic_labels()
	_show_claimed_float(reward)


func _show_claimed_float(_reward: int) -> void:
	if _claimed_float_label == null:
		return
	_claimed_float_label.text = LanguageManager.tr_ui("UI_SCOUT_CLAIMED_OK")
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
