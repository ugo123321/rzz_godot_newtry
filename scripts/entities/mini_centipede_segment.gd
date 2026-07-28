extends Node2D
class_name MiniCentipedeSegment

# 迷你千足虫的节段命中节点。隐形（虫身由头部 _draw_mini_centipede 统一绘制），
# 仅作为独立 hitbox + 伤害/元素状态转发层，把命中路由到虫的共享血量池。
# 与 CentipedeSegment（boss 用）平行，但指向 BattleMonster 而非 CentipedeBoss。

var worm: BattleMonster
var segment_index := 0
var alive := true
var dying := false


func get_hitbox_radius() -> float:
	if worm and is_instance_valid(worm):
		return worm._centi_segment_hitbox
	return 6.0


func is_combat_targetable() -> bool:
	return worm != null and is_instance_valid(worm) and worm.alive and not worm.dying and worm._centi_phase == BattleMonster.Phase.CHARGING


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	if worm == null or not is_instance_valid(worm):
		return {"damage": 0, "is_crit": false}
	return worm._apply_segment_hit(DamageInfo.legacy(raw_damage), self, from_pos)


func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if worm == null or not is_instance_valid(worm):
		return {"damage": 0, "is_crit": false}
	return worm._apply_segment_hit(info, self, from_pos)


# 元素状态转发：ElementEffectManager.try_apply 对目标节段调这些方法，必须路由到虫
func apply_burn_dot(duration: float, dps: int) -> void:
	if _worm_alive(): worm.apply_burn_dot(duration, dps)

func apply_burn_dot_with_snapshot(duration: float, dps: int, elem_pct: float) -> void:
	if _worm_alive(): worm.apply_burn_dot_with_snapshot(duration, dps, elem_pct)

func apply_burn_dot_v2(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if _worm_alive(): worm.apply_burn_dot_v2(snapshot_atk, elem_pct, proc_freq_pct)

func apply_freeze_slow(snapshot_atk: float, elem_pct: float, slow_bonus: float) -> void:
	if _worm_alive(): worm.apply_freeze_slow(snapshot_atk, elem_pct, slow_bonus)

func apply_poison_dot(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if _worm_alive(): worm.apply_poison_dot(snapshot_atk, elem_pct, proc_freq_pct)

func apply_paralyze(duration: float) -> void:
	if _worm_alive(): worm.apply_paralyze(duration)

func apply_petrify(duration: float) -> void:
	if _worm_alive(): worm.apply_petrify(duration)


func update_ai(_delta: float, _player: BattlePlayer, _battle: Node) -> void:
	pass

func update_death(_delta: float) -> void:
	pass

func die() -> void:
	pass


func _worm_alive() -> bool:
	return worm != null and is_instance_valid(worm) and worm.alive and not worm.dying
