extends RefCounted
class_name DamageInfo

# 一次伤害事件的载体。v2 8 层公式启用以下全部快照字段。
#
# category:
#   "physical" | "slash" | "bullet" | "combo" | "trail" | "sword" | "summon" | "dot"
# element:
#   "" | "fire" | "ice" | "thunder" | "poison"
# source: 自由文本(e.g. "slash_main", "bullet_auto", "combo_blackhole")，用于 dev overlay/伤害染色

var source: String = ""
var category: String = "physical"
var element: String = ""
var weapon_mult: float = 1.0
var can_crit: bool = true
var is_dot: bool = false
var is_extra: bool = false  # 武器额外伤害(extra_damage)标记，不暴击不联动

# raw 整数 ATK 层基线（Sheet3 L1：base_attack；分层乘子由 resolver 计算）
var raw_amount: int = 0
# resolver 计算暴击后回填，用于伤害数字着色 / 相机震动
var is_crit_resolved: bool = false

# === Sheet3 8 层公式快照(发射时刻冻结) ===
# L1: ATK 层最终值 = base_attack × (1 + atk_pct_total) × buff
var snapshot_atk_with_pct: float = 0.0
# L3: DMG 层加和（emitter 按 category 选）
var snapshot_dmg_all_pct: float = 0.0
var snapshot_dmg_source_pct: float = 0.0
# L4: COMBO 层倍率（slash 才 >1；其他来源 = 1.0）
var snapshot_combo_mult: float = 1.0
# L5: CRIT 层；resolver 内基于这两个 roll
var snapshot_crit_rate: float = 0.0
var snapshot_crit_dmg: float = 0.0
# L8: ELEM 层（emitter 按 element 类型选；非元素伤害 = 0）
var snapshot_elem_pct: float = 0.0
# 兼容字段（暂留）：旧版"通用 buff 倍率"，已被 dmg_all_pct 替代；保留 1.0 以免空快照
var snapshot_buff_mult: float = 1.0

# === v2 元素状态注入（Sheet4 element_effects）===
# 按 emitter 所在 category 取 player.current_applies[category][elem] 写入
var applies_fire: bool = false
var applies_ice: bool = false
var applies_thunder: bool = false
var applies_poison: bool = false
# 元素 proc 频率/减速/雷链目标 快照（ElementEffectManager 用）
var snapshot_elem_proc_freq_pct: float = 0.0
var snapshot_slow_pct_bonus: float = 0.0
var snapshot_chain_targets_bonus: int = 0


# 构造一个仅承载旧整数伤害的 DamageInfo，用于不走 8 层的轻量发射点
# （例如 monster._update_status_effects DoT tick 内部再次回调）
static func legacy(raw: int) -> RefCounted:
	var d := DamageInfo.new()
	d.raw_amount = raw
	return d


# 构造常规伤害事件
static func make(p_source: String, p_category: String, p_weapon_mult: float, p_element: String = "", p_can_crit: bool = true, p_is_dot: bool = false) -> RefCounted:
	var d := DamageInfo.new()
	d.source = p_source
	d.category = p_category
	d.weapon_mult = p_weapon_mult
	d.element = p_element
	d.can_crit = p_can_crit
	d.is_dot = p_is_dot
	return d


func duplicate_info() -> RefCounted:
	var d := DamageInfo.new()
	d.source = source
	d.category = category
	d.element = element
	d.weapon_mult = weapon_mult
	d.can_crit = can_crit
	d.is_dot = is_dot
	d.is_extra = is_extra
	d.raw_amount = raw_amount
	d.is_crit_resolved = is_crit_resolved
	d.snapshot_atk_with_pct = snapshot_atk_with_pct
	d.snapshot_dmg_all_pct = snapshot_dmg_all_pct
	d.snapshot_dmg_source_pct = snapshot_dmg_source_pct
	d.snapshot_combo_mult = snapshot_combo_mult
	d.snapshot_crit_rate = snapshot_crit_rate
	d.snapshot_crit_dmg = snapshot_crit_dmg
	d.snapshot_elem_pct = snapshot_elem_pct
	d.snapshot_buff_mult = snapshot_buff_mult
	d.applies_fire = applies_fire
	d.applies_ice = applies_ice
	d.applies_thunder = applies_thunder
	d.applies_poison = applies_poison
	d.snapshot_elem_proc_freq_pct = snapshot_elem_proc_freq_pct
	d.snapshot_slow_pct_bonus = snapshot_slow_pct_bonus
	d.snapshot_chain_targets_bonus = snapshot_chain_targets_bonus
	return d

