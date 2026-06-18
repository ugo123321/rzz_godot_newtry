extends RefCounted
class_name DamageResolver

# Sheet3 8 层伤害公式（rewards_v6_compact.xlsx Sheet3 damage_formula）。
#
# 实现说明：
#   L1 ATK + L2 WEAPON 已被 emitter 端折叠进 info.raw_amount（既往 v5 写法）：
#     raw_amount = base_attack × (1 + atk_pct_total) × attack_power_scale × bonus_attack_mult × weapon_mult
#   resolver 在此基础上独立计算 L3-L8 6 层：
#     final = max(1, round( raw_amount × DMG × COMBO × CRIT × DEF × VULN × ELEM ))
#
# 层级:
#   [L3] DMG    : 1 + 通用增伤% + 路径增伤%                      → info.snapshot_dmg_all_pct + snapshot_dmg_source_pct
#   [L4] COMBO  : 1 + combo_damage_bonus × combo（仅 slash 吃）  → info.snapshot_combo_mult
#   [L5] CRIT   : 1 或 (1 + crit_dmg)；resolver 内 roll           → info.snapshot_crit_rate / crit_dmg
#   [L6] DEF    : 1 - def / (def + K), K = K_base + K_per_stage × stage
#   [L7] VULN   : 1 + vuln_<type> (+ 1.0 若 vulnerable_mark 命中此次)
#   [L8] ELEM   : 1 + max(0, snapshot_elem_pct - elem_resist_<type>)（仅元素伤害）
#
# 玩家受击（敌→玩家）: max(1, round(raw × max(0.2, 1 - dmg_reduction)))

const PHYSICAL_DR_FLOOR := 0.2  # 玩家最多减 80%


static func compute_damage(target_stats: Dictionary, info) -> Dictionary:
	var raw: float = float(info.raw_amount)

	# L3 DMG
	var dmg_layer: float = 1.0 + float(info.snapshot_dmg_all_pct) + float(info.snapshot_dmg_source_pct)
	dmg_layer = maxf(0.0, dmg_layer)
	# L4 COMBO
	var combo_layer: float = maxf(0.0, float(info.snapshot_combo_mult))
	# L5 CRIT（resolver 一次性 roll；is_crit_resolved 已置位的（旧 emitter 已 roll）跳过）
	var is_crit := bool(info.is_crit_resolved)
	var crit_layer := 1.0
	if not is_crit and bool(info.can_crit) and not bool(info.is_dot):
		if randf() < float(info.snapshot_crit_rate):
			is_crit = true
	if is_crit:
		crit_layer = 1.0 + float(info.snapshot_crit_dmg)

	var atk_total: float = raw * dmg_layer * combo_layer * crit_layer

	# L6 DEF
	var def_layer := _def_layer(target_stats)
	# L7 VULN
	var vuln_layer := _vuln_layer(target_stats, info)
	# L8 ELEM
	var elem_layer := _elem_layer(target_stats, info)

	var final_f: float = atk_total * def_layer * vuln_layer * elem_layer
	var actual: int = maxi(1, int(round(final_f)))
	return {
		"damage": actual,
		"is_crit": is_crit,
		"vuln_consumed": bool(target_stats.get("vulnerable_mark", false)),
	}


static func _def_layer(target_stats: Dictionary) -> float:
	var defense := float(target_stats.get("defense", 0.0))
	var stage_idx := int(target_stats.get("stage_index", 0))
	var K_base := float(GameConfig.get_tuning("def_softening_K_base", 100))
	var K_per := float(GameConfig.get_tuning("def_softening_K_per_stage", 20))
	var K := K_base + K_per * float(stage_idx)
	var def_layer := 1.0 - defense / maxf(1.0, defense + K)
	return clampf(def_layer, 0.0, 1.0)


static func _vuln_layer(target_stats: Dictionary, info) -> float:
	var vuln_pct := 0.0
	if str(info.element) == "":
		vuln_pct = float(target_stats.get("vuln_physical", 0.0))
	else:
		vuln_pct = float(target_stats.get("vuln_" + str(info.element), 0.0))
	if bool(target_stats.get("vulnerable_mark", false)):
		vuln_pct += 1.0  # 印记 ≡ 易伤 +100%，命中即消耗
	return maxf(0.0, 1.0 + vuln_pct)


static func _elem_layer(target_stats: Dictionary, info) -> float:
	if str(info.element) == "":
		return 1.0
	var resist := float(target_stats.get("elem_resist_" + str(info.element), 0.0))
	var elem_eff_pct: float = float(info.snapshot_elem_pct) - resist
	return maxf(0.0, 1.0 + elem_eff_pct)


# 敌→玩家：Sheet3 第 4 段公式
static func compute_player_incoming(raw_amount: int, bonus_damage_reduction: float) -> int:
	return int(max(1, round(float(raw_amount) * maxf(PHYSICAL_DR_FLOOR, 1.0 - bonus_damage_reduction))))
