class_name PortalVisuals
extends RefCounted

# 传送门通用视觉 helper（静态方法）：像素圆环 + 旋转 sparkle + 外光晕。
# 被 LotteryPortal / ForgePortal 共用，避免每个 portal 重复一份"画环"的代码。
# 用法（在 portal 实体的 _draw 里）：
#   PortalVisuals.draw_halo(self, _t, VISUAL_RADIUS, Color("#8e6cff"))
#   PortalVisuals.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS,      c_dark, 5.0)
#   PortalVisuals.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 6.0, c_mid,  5.0)
#   PortalVisuals.draw_pixel_ring(self, Vector2.ZERO, VISUAL_RADIUS - 13.0, c_high, 4.0)
#   PortalVisuals.draw_sparkles(self, _t, VISUAL_RADIUS * 0.55, 6, c_top)


# 在 canvas 中心画一个由像素方块拼成的圆环。
# steps 跟周长走，避免大半径出现缝隙。
static func draw_pixel_ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var steps: int = maxi(36, int(ceil(TAU * radius / maxf(thickness, 1.5))))
	for ang_i in range(steps):
		var ang := float(ang_i) / float(steps) * TAU
		var p := center + Vector2(cos(ang), sin(ang)) * radius
		canvas.draw_rect(Rect2(p - Vector2(thickness * 0.5, thickness * 0.5), Vector2(thickness, thickness)), color)


# 在传送门中心绕一圈画旋转的 sparkle 像素点（每个 80ms 闪烁一档）。
# count 决定散落几颗，radius_factor 控制散落到中心 radius 的比例（通常 0.55 = VISUAL_RADIUS 的内侧）。
static func draw_sparkles(canvas: CanvasItem, t: float, radius: float, count: int, color: Color, size: float = 5.0) -> void:
	var flicker := (int(Time.get_ticks_msec() / 80) % 2) == 0
	var rot := t * 2.5
	for i in range(count):
		var ang := rot + float(i) / float(count) * TAU
		var r := radius + (1.5 if flicker else 0.0)
		var p := Vector2(cos(ang), sin(ang)) * r
		canvas.draw_rect(Rect2(p - Vector2(size * 0.5, size * 0.5), Vector2(size, size)), color)


# 外光晕（两层圆，按 t 呼吸）。color 是基础色，alpha 由内部脉冲计算。
static func draw_halo(canvas: CanvasItem, t: float, visual_radius: float, color: Color) -> void:
	var pulse := 0.35 + 0.25 * sin(t * 6.0)
	var outer := Color(color.r, color.g, color.b, pulse * 0.45)
	var inner := Color(color.r * 1.18, color.g * 1.28, color.b * 1.0, 0.55)
	canvas.draw_circle(Vector2.ZERO, visual_radius + 16.0, outer)
	canvas.draw_circle(Vector2.ZERO, visual_radius + 6.0, inner)


# 中心闪烁的核心方块（每个 80ms 闪烁，flicker 时画白色高光）。
static func draw_core_flash(canvas: CanvasItem, half_size: float = 5.0) -> void:
	var flicker := (int(Time.get_ticks_msec() / 80) % 2) == 0
	if flicker:
		canvas.draw_rect(Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0), Color.WHITE)
