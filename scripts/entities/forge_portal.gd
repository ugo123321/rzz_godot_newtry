extends Node2D
class_name ForgePortal

# 打造关传送门。区别于 LotteryPortal：
#   - 无 lifetime 计时（关卡地标，不会自动消失）
#   - 无距离自动触发（玩家进入由 battle._begin_forge_stage 显式调用 portal_traverse.play_enter）
#   - 视觉同 lottery 风格但色调更深紫 + 橙色高光（呼应强化块）
# 由 battle._prespawn_next_stage_world 在打造关 PRESPAWN 阶段实例化到场景中心。

const PortalVisualsScript := preload("res://scripts/utils/portal_visuals.gd")

const VISUAL_RADIUS := 56.0

var stored_position: Vector2 = Vector2.ZERO
var consumed := false
var _t := 0.0


func setup(local_pos: Vector2) -> void:
	# 注意：PRESPAWN 阶段 NextStageRoot 在 y=-1280，必须用 LOCAL position 而非 global。
	# REBASE 后由 battle 调用 sync_stored_global() 同步 stored_position 为正确的 global 坐标。
	position = local_pos
	stored_position = local_pos
	z_index = 4
	queue_redraw()


# REBASE 后由 battle 调用，把 stored_position 更新为当前 global 坐标（供 play_exit 用）。
func sync_stored_global() -> void:
	stored_position = global_position


func _process(delta: float) -> void:
	# 没有 lifetime 衰减；不主动检测距离触发。
	# 仅用于自身视觉动画（_t 推进 → 旋转 sparkle / 呼吸 halo）。
	_t += delta
	if not consumed:
		queue_redraw()


func _draw() -> void:
	# 深紫主色 + 橙色高光（呼应强化块的紫橙调）
	var halo_color := Color(0.45, 0.28, 1.0, 1.0)
	PortalVisualsScript.draw_halo(self, _t, VISUAL_RADIUS, halo_color)
	# 像素环（外深 → 内亮 → 顶高光）
	var c_dark := Color("#1f0e44")
	var c_mid := Color("#4828a0")
	var c_high := Color("#7a4cff")
	var c_top := Color("#ff9820")  # 橙色高光
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS, c_dark, 6.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 7.0, c_mid, 5.0)
	PortalVisualsScript.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 14.0, c_high, 4.0)
	# 8 个旋转橙色 sparkle，比 lottery 多 2 个、稍大
	PortalVisualsScript.draw_sparkles(self, _t, VISUAL_RADIUS * 0.58, 8, c_top, 5.5)
	# 中心闪烁的白色高光
	PortalVisualsScript.draw_core_flash(self, 5.0)
