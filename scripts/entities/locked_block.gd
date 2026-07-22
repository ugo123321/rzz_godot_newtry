extends FieldElement
class_name LockedBlock

# 锁定块（块上是钥匙 icon）：玩家持有钥匙时碰撞才会解锁开，每次解锁消耗 1 钥匙。
# 未解锁时与阻挡石块效果一致：阻挡移动 + 画线 + 子弹。解锁后消失（变空地）。
# 对敌人无效（敌人撞上也不会解锁，但敌人本身不会在此格刷出 / 不受地块影响）。

const TRIGGER_RADIUS := 38.0  # 玩家进入该格内时解锁（< 一格 40）

var _t := 0.0


func setup_block(col: int, row: int) -> void:
	setup(col, row, "locked_block", "up")
	_configure_blocking(true, true, true)  # 未解锁：line/move/bullet 全阻挡


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
	if not _battle.player.has_key():
		return
	if global_position.distance_to(_battle.player.global_position) <= TRIGGER_RADIUS:
		# 持钥匙 + 碰撞 → 解锁（消耗 1 钥匙，块消失）
		if _battle.player.spend_key():
			consume(_battle)


func _draw() -> void:
	# 阻挡石块底 + 像素钥匙 icon + 外发光（CLAUDE.md §9 多色分层 + 呼吸闪烁）
	var s: float = 20.0  # 填满一格（40px）：相邻块边对边贴着
	var pulse: float = 0.85 + 0.15 * (0.5 + 0.5 * sin(_t * 4.5))
	var c_body := Color("#5a4838") * pulse
	var c_shade := Color("#3a2c20") * pulse
	var c_high := Color("#7a6048") * pulse
	var c_rim := Color("#1a1208") * pulse
	var c_key := Color("#ffd060") * pulse
	var c_keyshade := Color("#9a7a30") * pulse
	# 外发光（金色调，提示"可解锁"）
	draw_circle(Vector2.ZERO, s * 1.4, Color(0.9, 0.75, 0.35, 0.14))
	# 块体
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c_body, true)
	# 内部块状纹理
	draw_rect(Rect2(-s * 0.6, -s * 0.6, s * 0.5, s * 0.5), c_shade, true)
	draw_rect(Rect2(s * 0.1, s * 0.1, s * 0.5, s * 0.5), c_shade, true)
	# 高光
	draw_rect(Rect2(-s, -s, s * 2.0, 4.0), c_high, true)
	draw_rect(Rect2(-s, -s, 4.0, s * 2.0), c_high, true)
	# 描边
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c_rim, false, 2.5)
	# 中心钥匙 icon
	_draw_key_icon(0.0, 0.0, s * 0.45, c_key, c_keyshade, c_rim)


func _draw_key_icon(cx: float, cy: float, s: float, c_base: Color, c_shade: Color, c_rim: Color) -> void:
	draw_circle(Vector2(cx, cy - s * 0.55), s * 0.45, c_base)
	draw_arc(Vector2(cx, cy - s * 0.55), s * 0.45, 0.0, TAU, 24, c_rim, 2.0)
	draw_circle(Vector2(cx, cy - s * 0.55), s * 0.18, c_shade)
	draw_rect(Rect2(cx - s * 0.1, cy - s * 0.1, s * 0.2, s * 0.95), c_base, true)
	draw_rect(Rect2(cx + s * 0.1, cy + s * 0.45, s * 0.25, s * 0.16), c_base, true)
