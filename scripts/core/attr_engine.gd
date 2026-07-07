extends RefCounted
class_name AttrEngine

# 表驱动 attr_code -> player 字段映射。
# rewards_v6_compact.xlsx Sheet2 attr_codes 一共 42 个 code，
# Phase 1 仅落地 29 张 sr=0 卡用到的 20 个 code；其余 code 加进表里
# 留 TODO，后续相补 player 字段时直接接通。
#
# kind:
#   passive_pct_add: 每张卡 base + per_lv*(level-1) 加到对应 player 浮点字段
#   passive_int_add: 同上但加到整数字段
#   event_amount   : 不写 player 字段，仅由 TriggerDispatcher 在事件回调里读取
#                   amount = base + per_lv * (level - 1)

const SCHEMA: Dictionary = {
	# ---- 面板 ----
	1:  {"field": "atk_pct_total",        "kind": "passive_pct_add"},
	2:  {"field": "atk_speed_pct_total",  "kind": "passive_pct_add"},
	3:  {"field": "move_speed_pct_total", "kind": "passive_pct_add"},
	4:  {"field": "max_hp_pct_total",     "kind": "passive_pct_add"},
	5:  {"field": "ki_max_pct_total",     "kind": "passive_pct_add"},
	6:  {"field": "ki_regen_pct_total",   "kind": "passive_pct_add"},
	7:  {"field": "crit_rate",            "kind": "passive_pct_add"},  # additive bump on base crit_rate
	8:  {"field": "dodge_pct_total",      "kind": "passive_pct_add"},
	9:  {"field": "luck_pct_total",       "kind": "passive_pct_add"},
	10: {"field": "size_pct_total",       "kind": "passive_pct_add"},
	11: {"field": "bonus_damage_reduction", "kind": "passive_pct_add"},
	# ---- 计数 ----
	12: {"field": "bullet_count_bonus",   "kind": "passive_int_add"},
	# ---- 剑（Phase 7） ----
	13: {"field": "sword_guard_count",   "kind": "passive_int_add"},
	14: {"field": "sword_blood_count",   "kind": "passive_int_add"},
	15: {"field": "sword_flame_count",   "kind": "passive_int_add"},
	16: {"field": "sword_thunder_count", "kind": "passive_int_add"},
	17: {"field": "sword_poison_count",  "kind": "passive_int_add"},
	18: {"field": "sword_frost_count",   "kind": "passive_int_add"},
	# ---- 生存 ----
	19: {"field": "heal_pct",             "kind": "event_amount"},
	20: {"field": "kill_heal_pct",        "kind": "event_amount"},
	# ---- 召唤 ----
	21: {"field": "dmg_summon_pct",       "kind": "passive_pct_add"},
	22: {"field": "summon_king_count",    "kind": "passive_int_add"},
	23: {"field": "summon_god_count",     "kind": "passive_int_add"},
	24: {"field": "summon_gorilla_count", "kind": "passive_int_add"},
	25: {"field": "summon_thunder_count", "kind": "passive_int_add"},
	26: {"field": "summon_bear_count",    "kind": "passive_int_add"},
	27: {"field": "summon_snake_count",   "kind": "passive_int_add"},
	28: {"field": "summon_fire_count",    "kind": "passive_int_add"},
	# ---- 元素 ----
	29: {"field": "elem_fire_pct",        "kind": "passive_pct_add"},
	30: {"field": "elem_ice_pct",         "kind": "passive_pct_add"},
	31: {"field": "elem_thunder_pct",     "kind": "passive_pct_add"},
	32: {"field": "elem_poison_pct",      "kind": "passive_pct_add"},
	33: {"field": "elem_proc_freq_pct",   "kind": "passive_pct_add"},
	34: {"field": "slow_pct_bonus",       "kind": "passive_pct_add"},
	35: {"field": "chain_targets_bonus",  "kind": "passive_int_add"},
	36: {"field": "elem_fire_attach_atk_mult",    "kind": "passive_pct_add"},
	37: {"field": "elem_ice_attach_atk_mult",     "kind": "passive_pct_add"},
	38: {"field": "elem_thunder_attach_atk_mult", "kind": "passive_pct_add"},
	39: {"field": "elem_poison_attach_atk_mult",  "kind": "passive_pct_add"},
	# ---- 计时 ----
	40: {"field": "cooldown_sec_total",   "kind": "passive_pct_add"},
	41: {"field": "duration_sec_total",   "kind": "passive_pct_add"},
	42: {"field": "tick_interval_sec_total", "kind": "passive_pct_add"},
	# ---- 主题召唤 / 主题剑（恶魔/天使主题关）----
	43: {"field": "summon_demon_baby_count", "kind": "passive_int_add"},
	44: {"field": "summon_angel_baby_count", "kind": "passive_int_add"},
	45: {"field": "sword_spear_count",       "kind": "passive_int_add"},
	46: {"field": "shield_orbit_count",      "kind": "passive_int_add"},
}


# 取卡上某槽位的总值: base + per_lv * (level - 1)
static func _slot_total(slot: Dictionary, level: int) -> float:
	var base := float(slot.get("value", 0.0))
	var per_lv = slot.get("per_lv")
	if per_lv == null:
		return base
	return base + float(per_lv) * float(maxi(0, level - 1))


# 是否当前帧应该把这张卡的 attr 写到 player（trigger=hp_below 时按条件）
static func _is_card_active(card_def: Dictionary, player: Node) -> bool:
	var trig := str(card_def.get("trigger", "passive"))
	if trig == "passive":
		return true
	if trig == "hp_below":
		var threshold := float(card_def.get("trigger_value", 0.5))
		var ratio: float = 1.0
		if player != null and "max_hp" in player and float(player.max_hp) > 0.0:
			ratio = float(player.hp) / float(player.max_hp)
		return ratio <= threshold
	# on_kill / on_pickup / 其它触发型卡的 attr 不在 passive rebuild 里写入
	# （event_amount 槽位由 TriggerDispatcher 在事件里现取）
	return false


# 主入口：每次 player._rebuild_upgrades() 调用一次
# stacks: { id: level } （level >= 1）
# defs_by_id: { id: card_def(Dict) }
static func apply_cards(player: Node, stacks: Dictionary, defs_by_id: Dictionary) -> void:
	for id in stacks.keys():
		var level := int(stacks[id])
		if level <= 0:
			continue
		var def: Dictionary = defs_by_id.get(id, {})
		if def.is_empty():
			continue
		if not _is_card_active(def, player):
			continue
		for slot in def.get("attrs", []):
			var aid := int(slot.get("id", 0))
			var meta: Dictionary = SCHEMA.get(aid, {})
			if meta.is_empty():
				continue
			var kind := str(meta.get("kind", ""))
			var field := str(meta.get("field", ""))
			if kind == "event_amount":
				continue
			if field.begins_with("TODO_"):
				continue  # Phase 2+ 才接通
			if not (field in player):
				push_warning("[AttrEngine] player missing field '%s' for attr %d (card %s)" % [field, aid, id])
				continue
			var amount := _slot_total(slot, level)
			if kind == "passive_int_add":
				player.set(field, int(player.get(field)) + int(round(amount)))
			else:
				player.set(field, float(player.get(field)) + amount)


# 给 TriggerDispatcher 用：列出当前 stacks 里所有 trigger != passive 的卡
# 返回 [{"id": ..., "trigger": ..., "proc_chance": ..., "level": ..., "attrs":[...]}, ...]
static func collect_trigger_bindings(stacks: Dictionary, defs_by_id: Dictionary) -> Array:
	var out: Array = []
	for id in stacks.keys():
		var level := int(stacks[id])
		if level <= 0:
			continue
		var def: Dictionary = defs_by_id.get(id, {})
		if def.is_empty():
			continue
		var trig := str(def.get("trigger", "passive"))
		if trig == "passive":
			continue
		out.append({
			"id": id,
			"trigger": trig,
			"proc_chance": def.get("proc_chance"),
			"trigger_value": def.get("trigger_value"),
			"level": level,
			"attrs": def.get("attrs", []),
		})
	return out


# 工具：取某 attr_code 在卡上的 amount(供 TriggerDispatcher 用)；不存在返回 0
static func get_attr_amount(binding: Dictionary, attr_id: int) -> float:
	for slot in binding.get("attrs", []):
		if int(slot.get("id", 0)) == attr_id:
			return _slot_total(slot, int(binding.get("level", 1)))
	return 0.0
