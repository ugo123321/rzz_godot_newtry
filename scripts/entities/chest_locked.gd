extends FieldElement
class_name ChestLocked

# 锁闭宝箱：玩家持有钥匙时碰撞才能打开；开启消耗 1 钥匙；内容同普通宝箱（70% 银 / 30% 钥）。
# 无钥匙时碰撞提示「需要钥匙」并不打开。对敌人无效。

const TRIGGER_RADIUS := 30.0
const ChestResultPopupScript := preload("res://scripts/ui/chest_result_popup.gd")

var _t := 0.0


func setup_chest(col: int, row: int, p_kind: String) -> void:
	setup(col, row, p_kind, "up")
	_configure_blocking(false, false, false)


func _process(delta: float) -> void:
	if consumed:
		return
	_t += delta
	if _battle == null:
		_battle = get_tree().get_first_node_in_group("battle")
	if _battle == null or _battle.player == null:
		return
	if _battle.state != GameState.PLAYING:
		return
	if global_position.distance_to(_battle.player.global_position) <= TRIGGER_RADIUS:
		if not _battle.player.has_key():
			if _battle.hud and _battle.hud.has_method("show_message"):
				_battle.hud.show_message(LanguageManager.tr_ui("UI_CHEST_LOCKED_NEED_KEY"), 1.2)
			# 短冷却避免刷屏（用 consumed 之外的简单计时）
			set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
			_battle.get_tree().create_timer(1.2).timeout.connect(_re_enable)
			return
		_battle.player.spend_key()
		_open()


func _re_enable() -> void:
	if consumed:
		return
	process_mode = Node.PROCESS_MODE_INHERIT


func _open() -> void:
	if consumed:
		return
	var is_key := randf() >= 0.7
	if is_key:
		_battle.player.add_key(1)
		_show_popup(1, "key")
	else:
		var n: int = 1 + (randi() % 3)
		_battle.player.add_silver(n)
		_show_popup(n, "silver")
	consume(_battle)


func _show_popup(amount: int, kind: String) -> void:
	var popup := ChestResultPopupScript.new()
	get_tree().current_scene.add_child(popup)
	popup.show_result(amount, kind)


func _draw() -> void:
	# 与普通宝箱同款，但锁板高亮 + 额外钥匙孔高光
	var s: float = 16.0
	var pulse: float = 0.85 + 0.15 * (0.5 + 0.5 * sin(_t * 4.0))
	var c_body := Color("#5a4028") * pulse
	var c_shade := Color("#3a2818") * pulse
	var c_lid := Color("#6a5030") * pulse
	var c_trim := Color("#c8a848") * pulse
	var c_lock := Color("#ffd060") * pulse
	var c_rim := Color("#1a1008") * pulse
	draw_circle(Vector2.ZERO, s * 1.3, Color(0.85, 0.7, 0.35, 0.18))
	draw_rect(Rect2(-s, -s * 0.2, s * 2.0, s * 1.2), c_body, true)
	draw_rect(Rect2(-s, -s * 0.2, s * 2.0, s * 1.2), c_rim, false, 2.0)
	draw_rect(Rect2(-s * 1.05, -s * 0.5, s * 2.1, s * 0.5), c_lid, true)
	draw_rect(Rect2(-s * 1.05, -s * 0.5, s * 2.1, s * 0.5), c_rim, false, 2.0)
	draw_rect(Rect2(-s, s * 0.1, s * 2.0, 4.0), c_trim, true)
	# 钥匙孔（更大更亮）
	draw_rect(Rect2(-5.0, -s * 0.05, 10.0, 12.0), c_lock, true)
	draw_rect(Rect2(-5.0, -s * 0.05, 10.0, 12.0), c_rim, false, 1.5)
	draw_circle(Vector2(0.0, s * 0.25), 2.0, c_rim)
