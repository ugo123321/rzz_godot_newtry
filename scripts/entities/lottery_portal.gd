extends Node2D
class_name LotteryPortal

# 抽奖传送门。
# v3：触发后不立即 queue_free —— 改为 visible=false 保留对象，
# 让 battle 端的 portal_traverse.play_exit 用 stored_position 落地。
# 销毁交给 battle._on_lottery_exit_complete 处理。

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const PortalVisualsScript := preload("res://scripts/utils/portal_visuals.gd")

const TRIGGER_RADIUS := 56.0
const VISUAL_RADIUS := 48.0

var lifetime := 5.0
var _t := 0.0
var _consumed := false
var stored_position: Vector2 = Vector2.ZERO


func setup(pos: Vector2, life: float) -> void:
	global_position = pos
	stored_position = pos
	lifetime = life
	z_index = 0  # 容器(Portals z=-1)已沉到怪物/玩家之下；传送门自身 z=0 → 有效 z=-1
	queue_redraw()


func _process(delta: float) -> void:
	if _consumed:
		return
	lifetime -= delta
	_t += delta
	if lifetime <= 0.0:
		queue_free()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.player and battle.state == GameState.PLAYING and not battle.get("_portal_active_pause"):
		if global_position.distance_to(battle.player.global_position) <= TRIGGER_RADIUS:
			_consumed = true
			stored_position = global_position
			visible = false  # v3：不销毁，只隐藏；销毁由 battle.play_exit 完成回调处理
			if battle.has_method("on_portal_entered"):
				battle.on_portal_entered(self)
			return
	queue_redraw()


func _draw() -> void:
	# v3：用 PortalVisuals helper 替换原有 _draw_ring 自绘
	var c_dark := Color("#2a1a55")
	var c_mid := Color("#5536a8")
	var c_high := Color("#8a5cff")
	var c_top := Color("#c8a8ff")
	# 外光晕（呼吸）
	PortalVisualsScript.draw_halo(self, _t, VISUAL_RADIUS, Color(0.55, 0.36, 1.0))
	# 像素环（外深 → 内亮）
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS, c_dark, 5.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 6.0, c_mid, 5.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 13.0, c_high, 4.0)
	# 6 个旋转 sparkle
	PortalVisualsScript.draw_sparkles(self, _t, VISUAL_RADIUS * 0.55, 6, c_top, 5.0)
	# 中心闪烁高光
	PortalVisualsScript.draw_core_flash(self, 5.0)
	# 倒计时
	var sec_left := int(ceil(lifetime))
	PixelUi.draw_pixel_text(
		self,
		"%ds" % sec_left,
		Vector2(0.0, -VISUAL_RADIUS - 28.0),
		22,
		Color("#ffe090") if sec_left > 2 else Color("#ff8080"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)
