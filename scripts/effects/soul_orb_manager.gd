extends Node2D
class_name SoulOrbManager

# 灵魂粒子球 spawn 工厂 — 怪物死亡 → spawn(pos, exp) → orb 飞达 HUD 经验条 → 真正 add_exp
# battle.gd 在 _ready 实例化并 add_child；与 equipment_drop_fx 同级
# 设计文档：C:/Users/admin/.claude/plans/icon-ui-photoshop-ui-polymorphic-haven.md

const SoulOrbScript = preload("res://scripts/effects/soul_orb.gd")

var battle: Node = null


func setup(battle_node: Node) -> void:
	battle = battle_node


func spawn(world_pos: Vector2, exp_amount: int) -> void:
	if exp_amount <= 0 or battle == null:
		return
	var orb: Node2D = SoulOrbScript.new()
	# 加到自己（SoulOrbManager 在 battle 下，与世界坐标一致），_on_arrive 走管理器持有的 experience
	add_child(orb)
	orb.setup(world_pos, exp_amount, _on_orb_arrive)


func clear() -> void:
	for child in get_children():
		child.queue_free()


# orb 命中经验条时回调（在 SoulOrb._finish_arrival 里调用）
func _on_orb_arrive(amount: int) -> void:
	if battle == null:
		return
	if battle.experience == null:
		return
	battle.experience.add_exp(amount)
