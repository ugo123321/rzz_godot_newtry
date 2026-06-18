extends RefCounted
class_name ElementEffectManager

# Sheet4 element_effects 统一注入器：
#   命中后由 emitter 调 try_apply(monster, info, player) 一次；
#   按 info.applies_<elem> 把火/冰/雷/毒状态注入 monster。
#
# 火 burn：DoT，tick = atk × 0.30 × 0.5（每 0.5s 一次），持续 2.0s
# 冰 freeze+slow：立即一次 atk × 0.30 元素伤；slow_pct = 0.30 + slow_pct_bonus，持续 1.5s
# 雷 chain：从 monster 出发广播扫描，跳到 (3 + chain_targets_bonus) 个最近未链怪，每跳 atk × 0.60；链尾 paralyze 0.5s
# 毒 poison：DoT，tick = atk × 0.30 × 1.0（每 1s 一次），持续 3.0s

const BURN_ATK_PER_SEC_BASE := 0.30
const BURN_DURATION_BASE := 2.0
const BURN_TICK_INTERVAL_BASE := 0.5

const ICE_HIT_ATK_MULT_BASE := 0.30
const ICE_SLOW_PCT_BASE := 0.30
const ICE_SLOW_DURATION_BASE := 1.5

const THUNDER_CHAIN_TARGETS_BASE := 3
const THUNDER_CHAIN_ATK_MULT_BASE := 0.60
const THUNDER_PARALYZE_DURATION_BASE := 0.5
const THUNDER_CHAIN_RANGE_PX := 200.0

const POISON_ATK_PER_SEC_BASE := 0.30
const POISON_DURATION_BASE := 3.0
const POISON_TICK_INTERVAL_BASE := 1.0


static func try_apply(monster, info, player) -> void:
	if monster == null or info == null:
		return
	if not is_instance_valid(monster) or not bool(monster.get("alive")) or monster.get("dying") == true:
		return
	if bool(info.applies_fire) and monster.has_method("apply_burn_dot_v2"):
		monster.apply_burn_dot_v2(
			float(info.snapshot_atk_with_pct),
			float(info.snapshot_elem_pct),
			float(info.snapshot_elem_proc_freq_pct)
		)
	if bool(info.applies_ice) and monster.has_method("apply_freeze_slow"):
		monster.apply_freeze_slow(
			float(info.snapshot_atk_with_pct),
			float(info.snapshot_elem_pct),
			float(info.snapshot_slow_pct_bonus)
		)
	if bool(info.applies_poison) and monster.has_method("apply_poison_dot"):
		monster.apply_poison_dot(
			float(info.snapshot_atk_with_pct),
			float(info.snapshot_elem_pct),
			float(info.snapshot_elem_proc_freq_pct)
		)
	if bool(info.applies_thunder):
		_execute_chain(monster, info, player)


# 雷链：从 origin_monster 广播扫描最近的 chain_targets 个 monster（含 origin），逐个施加伤害；链尾 paralyze。
static func _execute_chain(origin_monster, info, player) -> void:
	var chain_count := THUNDER_CHAIN_TARGETS_BASE + int(info.snapshot_chain_targets_bonus)
	chain_count = clampi(chain_count, 1, 8)
	# 找战场上的怪
	var battle = origin_monster.get_tree().get_first_node_in_group("battle") if origin_monster.is_inside_tree() else null
	var monsters: Array = []
	if battle != null and battle.spawner != null and battle.spawner.has_method("get_active_monsters"):
		monsters = battle.spawner.get_active_monsters()
	if monsters.is_empty():
		return
	var visited: Dictionary = {}
	visited[origin_monster.get_instance_id()] = true
	var current = origin_monster
	for i in range(chain_count):
		# 第 0 跳 = 命中点（已经被 emitter 算过了），从下一跳开始注入伤害
		if i == 0:
			continue
		var next_target = _find_nearest_unvisited(current, monsters, visited, THUNDER_CHAIN_RANGE_PX)
		if next_target == null:
			break
		visited[next_target.get_instance_id()] = true
		_apply_chain_hit(next_target, info, player)
		current = next_target
	# 链尾麻痹（最后一个 current 即链尾；若链长为 0 则 origin 麻痹）
	if current != null and current.has_method("apply_paralyze"):
		current.apply_paralyze(THUNDER_PARALYZE_DURATION_BASE)


static func _find_nearest_unvisited(from_monster, monsters: Array, visited: Dictionary, max_range: float):
	var best = null
	var best_dist := max_range * max_range
	var from_pos: Vector2 = from_monster.global_position
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		if visited.get(m.get_instance_id(), false):
			continue
		var d2: float = from_pos.distance_squared_to(m.global_position)
		if d2 < best_dist:
			best_dist = d2
			best = m
	return best


static func _apply_chain_hit(monster, info, player) -> void:
	# 链跳伤害：snapshot_atk × 0.60 × ELEM_layer，独立从 player 走 ability_damage 工厂保证暴击/dmg 层一致
	if player == null:
		return
	var chain_info = player.make_ability_damage(
		"elem_thunder_chain",
		THUNDER_CHAIN_ATK_MULT_BASE,
		"bullet",
		"thunder",
		false,
		false
	)
	# 链跳本身不应该再触发雷链（避免无限链）
	chain_info.applies_thunder = false
	chain_info.applies_fire = false
	chain_info.applies_ice = false
	chain_info.applies_poison = false
	if monster.has_method("take_damage_info"):
		monster.take_damage_info(chain_info, monster.global_position)
