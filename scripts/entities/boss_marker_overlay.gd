extends Node2D
class_name BossMarkerOverlay

# 绘制在 boss 精灵"之上"的画线攻击标记圆圈。
# 父节点(Node2D)的 _draw 永远画在子节点(AnimatedSprite2D)后面,所以标记圆圈若画在
# 父 _draw 里会被龙身盖住。这个 overlay 作为排在精灵之后的子节点,画在顶层。
# 字段(count / hitbox_radius / 可攻击性)从父 boss 读,保持与 boss 状态同步。

func _draw() -> void:
	var p = get_parent()
	if p == null or not is_instance_valid(p):
		return
	# 只在 boss 当前可被攻击(ACTIVE 且非起跳空中)时画
	if not bool(p.call("is_combat_targetable")):
		return
	var count: int = int(p.get("path_target_hit_count"))
	if count <= 0:
		return
	var hr: float = float(p.get("hitbox_radius"))
	var ring := CombatDirector.path_preview_ring_color(count)
	var fill := ring
	fill.a = 0.12 + mini(count, 4) * 0.04
	var r := hr + GameConfig.scale_world(5.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ring, GameConfig.scale_world(3.0))
	draw_circle(Vector2.ZERO, r * 0.55, fill)
