extends FieldElement
class_name ChestNormal

# 普通宝箱：碰撞后打开。内容：70% 概率 1-3 银币，30% 概率 1 钥匙。开启后消失。
# 不阻挡移动/画线/子弹（玩家碰上去就开，参考 LotteryPortal 的 proximity 触发）。
# 对敌人无效（敌人不会触发）。

const TRIGGER_RADIUS := 30.0  # 约一格(40)的 0.75
const ChestResultPopupScript := preload("res://scripts/ui/chest_result_popup.gd")

var _t := 0.0


func setup_chest(col: int, row: int, p_kind: String) -> void:
	setup(col, row, p_kind, "up")
	_configure_blocking(false, false, false)  # 宝箱不阻挡


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
		_open()


func _open() -> void:
	if consumed:
		return
	# 70% 银 1-3；30% 钥 1
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
	# 过程化像素宝箱：箱体 + 盖 + 锁板 + 金边（CLAUDE.md §9 多色分层 + 呼吸闪烁）
	var s: float = 16.0
	var pulse: float = 0.85 + 0.15 * (0.5 + 0.5 * sin(_t * 4.0))
	var c_body := Color("#7a5028") * pulse
	var c_shade := Color("#5a3818") * pulse
	var c_lid := Color("#8a6030") * pulse
	var c_trim := Color("#d8a848") * pulse
	var c_lock := Color("#e0c060") * pulse
	var c_rim := Color("#2a1808") * pulse
	# 外发光圆晕
	draw_circle(Vector2.ZERO, s * 1.3, Color(0.85, 0.65, 0.3, 0.16))
	# 箱体
	draw_rect(Rect2(-s, -s * 0.2, s * 2.0, s * 1.2), c_body, true)
	draw_rect(Rect2(-s, -s * 0.2, s * 2.0, s * 1.2), c_rim, false, 2.0)
	# 盖
	draw_rect(Rect2(-s * 1.05, -s * 0.5, s * 2.1, s * 0.5), c_lid, true)
	draw_rect(Rect2(-s * 1.05, -s * 0.5, s * 2.1, s * 0.5), c_rim, false, 2.0)
	# 金边横带
	draw_rect(Rect2(-s, s * 0.1, s * 2.0, 4.0), c_trim, true)
	# 锁板
	draw_rect(Rect2(-4.0, -s * 0.05, 8.0, 10.0), c_lock, true)
	draw_rect(Rect2(-4.0, -s * 0.05, 8.0, 10.0), c_rim, false, 1.5)
	# 高光
	draw_rect(Rect2(-s * 0.8, -s * 0.35, s * 0.5, 3.0), c_trim, true)
