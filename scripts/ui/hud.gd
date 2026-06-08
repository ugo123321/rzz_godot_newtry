extends Control
class_name GameHud

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiSprites := preload("res://scripts/utils/ui_sprite_helper.gd")

const PAUSE_BTN_SIZE := 18.0
const PAUSE_BTN_MARGIN := 12.0
const PAUSE_BTN_TOP := 6.0
const PAUSE_BTN_PRESSED_SCALE := 0.88

var _stage_text := "第1关"
var _exp_level := 1
var _exp_value := 0
var _exp_to_next := 100
var _message_text := ""
var _message_timer := 0.0
var _message_persistent := false
var _pause_btn: TextureButton
var _pause_btn_pressed := false
var _last_ki_draw := -1.0
var _redraw_timer := 0.0
var _gold := 0
var _coin_icon: Texture2D


func _ui_scale() -> float:
	return GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()


func _scaled(v: float) -> float:
	return v * _ui_scale()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 20
	EventBus.exp_changed.connect(_on_exp_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_healed.connect(_on_player_healed)
	_load_coin_icon()
	_sync_gold_from_lobby()
	_build_pause_button()
	call_deferred("_sync_exp_from_battle")


func _build_pause_button() -> void:
	_pause_btn = TextureButton.new()
	_pause_btn.name = "PauseButton"
	var btn_size := Vector2(_scaled(PAUSE_BTN_SIZE), _scaled(PAUSE_BTN_SIZE))
	_pause_btn.custom_minimum_size = btn_size
	_pause_btn.size = btn_size
	_pause_btn.pivot_offset = btn_size * 0.5
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_top = 0.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.anchor_bottom = 0.0
	_pause_btn.offset_left = -_scaled(PAUSE_BTN_MARGIN) - _scaled(PAUSE_BTN_SIZE)
	_pause_btn.offset_top = _scaled(PAUSE_BTN_TOP)
	_pause_btn.offset_right = -_scaled(PAUSE_BTN_MARGIN)
	_pause_btn.offset_bottom = _scaled(PAUSE_BTN_TOP) + _scaled(PAUSE_BTN_SIZE)
	_pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_btn.z_index = 50
	_pause_btn.focus_mode = Control.FOCUS_NONE
	UiSprites.style_pause_button(_pause_btn)
	_pause_btn.visible = false
	_pause_btn.button_down.connect(_on_pause_button_down)
	_pause_btn.button_up.connect(_on_pause_button_up)
	_pause_btn.pressed.connect(_on_pause_pressed)
	add_child(_pause_btn)


func _sync_exp_from_battle() -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.experience:
		_on_exp_changed(battle.experience.level, battle.experience.exp, battle.experience.exp_to_next)


func _load_coin_icon() -> void:
	var path := "res://assets/icons/equipment/icon_coin_pixel.svg"
	if ResourceLoader.exists(path):
		_coin_icon = load(path) as Texture2D


func _sync_gold_from_lobby() -> void:
	if LobbyState:
		_gold = int(LobbyState.gold)
		queue_redraw()


func is_pause_button_at(screen_pos: Vector2) -> bool:
	if _pause_btn == null or not _pause_btn.visible:
		return false
	return _pause_btn.get_global_rect().has_point(screen_pos)


func _on_pause_button_down() -> void:
	_pause_btn_pressed = true
	_update_pause_button_scale()


func _on_pause_button_up() -> void:
	_pause_btn_pressed = false
	_update_pause_button_scale()


func _update_pause_button_scale() -> void:
	if _pause_btn == null:
		return
	var scale := PAUSE_BTN_PRESSED_SCALE if _pause_btn_pressed else 1.0
	_pause_btn.scale = Vector2.ONE * scale
	if _pause_btn_pressed:
		_pause_btn.modulate = Color(0.92, 0.92, 0.96)
	else:
		_pause_btn.modulate = Color.WHITE


func _on_pause_pressed() -> void:
	var battle: Node = get_tree().get_first_node_in_group("battle")
	if battle == null:
		return
	if battle.has_method("pause_game"):
		battle.pause_game()


func bind_player(_player: BattlePlayer) -> void:
	queue_redraw()


func set_stage_text(text: String) -> void:
	_stage_text = text
	queue_redraw()


func show_message(text: String, duration: float = 1.2) -> void:
	_message_text = text
	_message_persistent = duration >= 900.0
	_message_timer = duration if not _message_persistent else 1.0
	queue_redraw()


func hide_message() -> void:
	_message_text = ""
	_message_timer = 0.0
	_message_persistent = false
	queue_redraw()


func _process(delta: float) -> void:
	var need_redraw := false
	if not _message_persistent and _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_text = ""
		need_redraw = true
	_redraw_timer -= delta
	var battle := get_tree().get_first_node_in_group("battle") as BattleController
	if battle and _pause_btn:
		var show_pause: bool = (
			battle.state == GameState.PLAYING or battle.state == GameState.STAGE_INTRO
		)
		if _pause_btn.visible != show_pause:
			_pause_btn.visible = show_pause
	if battle and battle.player:
		var ki_snap := snappedf(battle.player.ki, 0.5)
		if ki_snap != _last_ki_draw:
			_last_ki_draw = ki_snap
			need_redraw = true
		if battle.player.is_combo_display_visible():
			need_redraw = true
		if battle.player.is_ki_full():
			need_redraw = true
	if need_redraw or _redraw_timer <= 0.0:
		_redraw_timer = 0.033
		queue_redraw()


func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size

	_draw_gold_widget()

	var battle := get_tree().get_first_node_in_group("battle")
	var player: BattlePlayer = battle.player if battle else null
	var boss: Node = null
	if battle and battle.spawner:
		boss = battle.spawner.boss

	PixelUi.draw_pixel_text(
		self,
		_stage_text,
		Vector2(viewport_size.x * 0.5, _scaled(14.0)),
		PixelUi.snap_pixel_font_size(int(round(_scaled(11.0)))),
		Color("#ffe8c8"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)

	var layout := PixelUi.compute_hud_layout(viewport_size, player, boss)

	if player:
		var ki_ratio := clampf(player.ki / maxf(1.0, player.ki_max), 0.0, 1.0)
		var ki_ready := player.is_ki_full()
		UiSprites.draw_ki_bar(
			self,
			float(layout.get("ki_x", 0.0)),
			float(layout.get("ki_y", 0.0)),
			float(layout.get("ki_w", 0.0)),
			float(layout.get("ki_h", 0.0)),
			ki_ratio,
			ki_ready
		)

	PixelUi.draw_boss_hp_bar(self, boss, layout)
	if player:
		PixelUi.draw_turn_buff_icons(self, player, layout)
		PixelUi.draw_combo_banner(self, player, layout, viewport_size.x)

	if battle and battle.buff_orbs and battle.buff_orbs.notice_timer > 0.0:
		var notice_alpha := clampf(battle.buff_orbs.notice_timer / 1.6, 0.0, 1.0)
		PixelUi.draw_buff_notice(self, battle.buff_orbs.notice, viewport_size, notice_alpha)

	if not _message_text.is_empty():
		var msg_alpha := 1.0
		if not _message_persistent:
			msg_alpha = clampf(_message_timer / 1.25, 0.0, 1.0)
		var exp_reserve := _scaled(34.0)
		var msg_y := viewport_size.y - exp_reserve - _scaled(36.0)
		PixelUi.draw_message_panel(self, _message_text, Vector2(viewport_size.x * 0.5, msg_y), msg_alpha)

	# 经验条最后绘制，避免被提示条遮挡
	UiSprites.draw_exp_bar(self, viewport_size, _exp_level, _exp_value, _exp_to_next)


func _draw_gold_widget() -> void:
	var icon_rect := Rect2(_scaled(12.0), _scaled(10.0), _scaled(18.0), _scaled(18.0))
	if _coin_icon != null:
		draw_texture_rect(_coin_icon, icon_rect, false)
	PixelUi.draw_pixel_text(
		self,
		str(_gold),
		Vector2(_scaled(34.0), _scaled(19.0)),
		PixelUi.snap_pixel_font_size(int(round(_scaled(10.0)))),
		Color("#ffe090"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER
	)


func _on_exp_changed(level: int, exp_value: int, exp_to_next: int) -> void:
	_exp_level = level
	_exp_value = exp_value
	_exp_to_next = exp_to_next
	queue_redraw()


func _on_gold_changed(total_gold: int) -> void:
	_gold = total_gold
	queue_redraw()


func _on_player_damaged(_amount: int, remaining: int) -> void:
	show_message("受到攻击！剩余 %d HP" % remaining, 0.8)


func _on_player_healed(amount: int, remaining: int) -> void:
	show_message("回复 %d HP（%d）" % [amount, remaining], 0.8)
