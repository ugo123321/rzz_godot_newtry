extends Node2D
class_name FixedPortal

# 固定抽奖传送门：与随机刷出的 LotteryPortal 效果一致，但无倒计时、固定存在。
# 碰撞后进入抽奖页面（battle.on_portal_entered → reward_wheel 流程），碰撞后传送门消失。
# 销毁交给 battle._on_lottery_exit_complete 处理（与 LotteryPortal 一致）。
# 由关卡编辑器 / battle._apply_level_layout 放置。

const PortalVisualsScript := preload("res://scripts/utils/portal_visuals.gd")

const TRIGGER_RADIUS := 56.0
const VISUAL_RADIUS := 48.0

var _t := 0.0
var _consumed := false
var stored_position: Vector2 = Vector2.ZERO


func setup(pos: Vector2) -> void:
	global_position = pos
	stored_position = pos
	z_index = 4
	queue_redraw()


func _process(delta: float) -> void:
	if _consumed:
		return
	_t += delta
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.player and battle.state == GameState.PLAYING and not battle.get("_portal_active_pause"):
		if global_position.distance_to(battle.player.global_position) <= TRIGGER_RADIUS:
			_consumed = true
			stored_position = global_position
			visible = false  # 销毁由 battle.play_exit 完成回调处理
			if battle.has_method("on_portal_entered"):
				battle.on_portal_entered(self)
			return
	queue_redraw()


func _draw() -> void:
	# 与 LotteryPortal 同款像素环 + 旋转 sparkle + 中心闪光，但不画倒计时文字（固定存在）。
	var c_dark := Color("#2a1a55")
	var c_mid := Color("#5536a8")
	var c_high := Color("#8a5cff")
	var c_top := Color("#c8a8ff")
	PortalVisualsScript.draw_halo(self, _t, VISUAL_RADIUS, Color(0.55, 0.36, 1.0))
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS, c_dark, 5.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 6.0, c_mid, 5.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 13.0, c_high, 4.0)
	PortalVisualsScript.draw_sparkles(self, _t, VISUAL_RADIUS * 0.55, 6, c_top, 5.0)
	PortalVisualsScript.draw_core_flash(self, 5.0)
