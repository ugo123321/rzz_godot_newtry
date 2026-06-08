extends Node
## 主界面与战斗场景之间的启动参数（章节、关卡索引等）。

var stage_index: int = 0

var _pending_launch := false

const SLOT_WEAPON := "weapon"
const SLOT_HELMET := "helmet"
const SLOT_NECKLACE := "necklace"
const SLOT_RING := "ring"
const SLOT_ARMOR := "armor"
const SLOT_SHOES := "shoes"

const SLOT_ORDER := [
	SLOT_WEAPON,
	SLOT_HELMET,
	SLOT_NECKLACE,
	SLOT_RING,
	SLOT_ARMOR,
	SLOT_SHOES,
]

const QUALITY_COMMON := 0
const QUALITY_RARE := 1
const QUALITY_EPIC := 2
const QUALITY_LEGENDARY := 3

const QUALITY_NAMES := ["普通", "稀有", "史诗", "传奇"]
const QUALITY_COLORS := ["#f2f2f2", "#57a8ff", "#b172ff", "#ffa640"]

const DROP_RATE := 0.10

var gold: int = 0
var equipment_inventory: Array[Dictionary] = []
var equipped_by_slot: Dictionary = {}
var _next_item_uid := 1

var equipment_defs := {
	"short_dagger": {
		"name": "短刀",
		"slot": SLOT_WEAPON,
		"base_power": 38,
		"icon_path": "res://assets/icons/equipment/icon_equip_dagger_pixel.svg",
	},
	"cloth_armor": {
		"name": "布甲",
		"slot": SLOT_ARMOR,
		"base_power": 32,
		"icon_path": "res://assets/icons/equipment/icon_equip_cloth_armor_pixel.svg",
	},
	"wood_shoes": {
		"name": "木鞋",
		"slot": SLOT_SHOES,
		"base_power": 28,
		"icon_path": "res://assets/icons/equipment/icon_equip_wood_shoes_pixel.svg",
	},
}


func _ready() -> void:
	_ensure_slot_state()
	call_deferred("_emit_all_state")


func request_battle_launch(p_stage_index: int) -> void:
	stage_index = maxi(0, p_stage_index)
	_pending_launch = true


func consume_battle_launch() -> bool:
	if not _pending_launch:
		return false
	_pending_launch = false
	return true


func _emit_all_state() -> void:
	if EventBus:
		EventBus.gold_changed.emit(gold)
		EventBus.equipment_changed.emit()


func _ensure_slot_state() -> void:
	for slot in SLOT_ORDER:
		if not equipped_by_slot.has(slot):
			equipped_by_slot[slot] = -1


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	if EventBus:
		EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	if EventBus:
		EventBus.gold_changed.emit(gold)
	return true


func get_slot_display_name(slot: String) -> String:
	match slot:
		SLOT_WEAPON:
			return "武器"
		SLOT_HELMET:
			return "头盔"
		SLOT_NECKLACE:
			return "项链"
		SLOT_RING:
			return "戒指"
		SLOT_ARMOR:
			return "衣服"
		SLOT_SHOES:
			return "鞋"
	return "未知"


func get_quality_name(quality: int) -> String:
	var idx := clampi(quality, 0, QUALITY_NAMES.size() - 1)
	return QUALITY_NAMES[idx]


func get_quality_color(quality: int) -> Color:
	var idx := clampi(quality, 0, QUALITY_COLORS.size() - 1)
	return Color(QUALITY_COLORS[idx])


func get_item_def(def_id: String) -> Dictionary:
	var src: Dictionary = equipment_defs.get(def_id, {})
	return src.duplicate(true)


func add_equipment(def_id: String, quality: int = QUALITY_COMMON, level: int = 1) -> Dictionary:
	var def := get_item_def(def_id)
	if def.is_empty():
		return {}
	var item: Dictionary = {
		"uid": _next_item_uid,
		"def_id": def_id,
		"slot": str(def.get("slot", SLOT_WEAPON)),
		"quality": clampi(quality, QUALITY_COMMON, QUALITY_LEGENDARY),
		"level": maxi(1, level),
	}
	_next_item_uid += 1
	equipment_inventory.append(item)
	if EventBus:
		EventBus.equipment_changed.emit()
	return item.duplicate(true)


func try_drop_random_equipment() -> Dictionary:
	if randf() > DROP_RATE:
		return {}
	var keys := equipment_defs.keys()
	if keys.is_empty():
		return {}
	var quality_roll := randf()
	var quality := QUALITY_COMMON
	if quality_roll >= 0.99:
		quality = QUALITY_LEGENDARY
	elif quality_roll >= 0.95:
		quality = QUALITY_EPIC
	elif quality_roll >= 0.85:
		quality = QUALITY_RARE
	var picked := str(keys[randi() % keys.size()])
	return add_equipment(picked, quality, 1)


func get_inventory_sorted() -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for item in equipment_inventory:
		var uid := int(item.get("uid", -1))
		if is_item_equipped(uid):
			continue
		copied.append(item.duplicate(true))
	copied.sort_custom(_sort_inventory_item)
	return copied


func _sort_inventory_item(a: Dictionary, b: Dictionary) -> bool:
	var qa := int(a.get("quality", 0))
	var qb := int(b.get("quality", 0))
	if qa != qb:
		return qa > qb
	var la := int(a.get("level", 1))
	var lb := int(b.get("level", 1))
	if la != lb:
		return la > lb
	var na := get_item_name(a)
	var nb := get_item_name(b)
	if na != nb:
		return na.naturalnocasecmp_to(nb) < 0
	return int(a.get("uid", 0)) < int(b.get("uid", 0))


func _find_item_index(uid: int) -> int:
	for i in range(equipment_inventory.size()):
		if int(equipment_inventory[i].get("uid", -1)) == uid:
			return i
	return -1


func get_item_by_uid(uid: int) -> Dictionary:
	var idx := _find_item_index(uid)
	if idx < 0:
		return {}
	return equipment_inventory[idx].duplicate(true)


func get_item_name(item: Dictionary) -> String:
	var def := get_item_def(str(item.get("def_id", "")))
	return str(def.get("name", "未知装备"))


func get_item_icon_path(item: Dictionary) -> String:
	var def := get_item_def(str(item.get("def_id", "")))
	return str(def.get("icon_path", ""))


func equip_item(uid: int) -> bool:
	var idx := _find_item_index(uid)
	if idx < 0:
		return false
	var slot := str(equipment_inventory[idx].get("slot", ""))
	if slot.is_empty():
		return false
	equipped_by_slot[slot] = uid
	if EventBus:
		EventBus.equipment_changed.emit()
	return true


func unequip_slot(slot: String) -> bool:
	if not equipped_by_slot.has(slot):
		return false
	if int(equipped_by_slot.get(slot, -1)) < 0:
		return false
	equipped_by_slot[slot] = -1
	if EventBus:
		EventBus.equipment_changed.emit()
	return true


func is_item_equipped(uid: int) -> bool:
	for slot in SLOT_ORDER:
		if int(equipped_by_slot.get(slot, -1)) == uid:
			return true
	return false


func get_equipped_item(slot: String) -> Dictionary:
	var uid := int(equipped_by_slot.get(slot, -1))
	if uid < 0:
		return {}
	return get_item_by_uid(uid)


func get_upgrade_cost(item: Dictionary) -> int:
	var level := int(item.get("level", 1))
	var quality := int(item.get("quality", QUALITY_COMMON))
	return 30 + level * 15 + quality * 25


func upgrade_item(uid: int) -> Dictionary:
	var idx := _find_item_index(uid)
	if idx < 0:
		return {}
	var item: Dictionary = equipment_inventory[idx]
	var cost := get_upgrade_cost(item)
	if not spend_gold(cost):
		return {}
	item["level"] = int(item.get("level", 1)) + 1
	equipment_inventory[idx] = item
	if EventBus:
		EventBus.equipment_changed.emit()
	return item.duplicate(true)


func remove_item(uid: int) -> Dictionary:
	var idx := _find_item_index(uid)
	if idx < 0:
		return {}
	var item := equipment_inventory[idx].duplicate(true)
	equipment_inventory.remove_at(idx)
	return item


func can_compose_three(uids: Array) -> bool:
	if uids.size() != 3:
		return false
	var parsed: Array[int] = []
	for raw_uid in uids:
		var uid := int(raw_uid)
		if uid < 0:
			return false
		if parsed.has(uid):
			return false
		var item := get_item_by_uid(uid)
		if item.is_empty():
			return false
		if is_item_equipped(uid):
			return false
		parsed.append(uid)
	var base_item := get_item_by_uid(parsed[0])
	var base_def := str(base_item.get("def_id", ""))
	var base_quality := int(base_item.get("quality", QUALITY_COMMON))
	if base_quality >= QUALITY_LEGENDARY:
		return false
	for i in range(1, parsed.size()):
		var item := get_item_by_uid(parsed[i])
		if str(item.get("def_id", "")) != base_def:
			return false
		if int(item.get("quality", QUALITY_COMMON)) != base_quality:
			return false
	return true


func compose_three_items(uids: Array) -> Dictionary:
	if not can_compose_three(uids):
		return {}
	var parsed: Array[int] = []
	var max_level := 1
	for raw_uid in uids:
		var uid := int(raw_uid)
		parsed.append(uid)
		var item := get_item_by_uid(uid)
		max_level = maxi(max_level, int(item.get("level", 1)))
	var base_item := get_item_by_uid(parsed[0])
	var def_id := str(base_item.get("def_id", ""))
	var next_quality := mini(QUALITY_LEGENDARY, int(base_item.get("quality", QUALITY_COMMON)) + 1)
	for uid in parsed:
		remove_item(uid)
	var result := add_equipment(def_id, next_quality, max_level)
	if EventBus:
		EventBus.equipment_changed.emit()
	return result


func get_item_power(item: Dictionary) -> int:
	var def := get_item_def(str(item.get("def_id", "")))
	var base_power := int(def.get("base_power", 25))
	var level := int(item.get("level", 1))
	var quality := int(item.get("quality", QUALITY_COMMON))
	return base_power + (level - 1) * 8 + quality * 24


func get_item_skill_entries(item: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quality := int(item.get("quality", QUALITY_COMMON))
	for tier in range(QUALITY_COMMON, QUALITY_LEGENDARY + 1):
		result.append({
			"quality": tier,
			"quality_name": get_quality_name(tier),
			"text": _skill_text_for_quality(item, tier),
			"unlocked": tier <= quality,
		})
	return result


func _skill_text_for_quality(item: Dictionary, tier: int) -> String:
	var def_id := str(item.get("def_id", ""))
	var level := int(item.get("level", 1))
	match def_id:
		"short_dagger":
			match tier:
				QUALITY_COMMON:
					var value := 10 + (level - 1) * 2
					return "攻击力 +%d（每级 +2）" % value
				QUALITY_RARE:
					return "命中敌人 50%% 概率造成额外伤害（攻击力的 20%%）"
				QUALITY_EPIC:
					return "攻击力 +30"
				QUALITY_LEGENDARY:
					return "攻击力 +50"
		"cloth_armor":
			match tier:
				QUALITY_COMMON:
					var hp_value := 10 + (level - 1) * 2
					return "最大生命 +%d（每级 +2）" % hp_value
				QUALITY_RARE:
					return "最大生命 +20"
				QUALITY_EPIC:
					return "最大生命 +30"
				QUALITY_LEGENDARY:
					return "最大生命 +40"
		"wood_shoes":
			match tier:
				QUALITY_COMMON:
					var crit_value := 5 + (level - 1)
					return "暴击率 +%d%%（每级 +1%%）" % crit_value
				QUALITY_RARE:
					return "暴击率 +5%%"
				QUALITY_EPIC:
					return "暴击率 +5%%"
				QUALITY_LEGENDARY:
					return "暴击率 +5%%"
	return "未定义技能"


func get_item_stat_bonus(item: Dictionary) -> Dictionary:
	var def_id := str(item.get("def_id", ""))
	var level := int(item.get("level", 1))
	var quality := int(item.get("quality", QUALITY_COMMON))
	var bonus := {
		"attack": 0.0,
		"max_hp": 0,
		"crit_rate": 0.0,
		"item_power": get_item_power(item),
	}
	match def_id:
		"short_dagger":
			if quality >= QUALITY_COMMON:
				bonus.attack += 10 + (level - 1) * 2
			if quality >= QUALITY_EPIC:
				bonus.attack += 30
			if quality >= QUALITY_LEGENDARY:
				bonus.attack += 50
		"cloth_armor":
			if quality >= QUALITY_COMMON:
				bonus.max_hp += 10 + (level - 1) * 2
			if quality >= QUALITY_RARE:
				bonus.max_hp += 20
			if quality >= QUALITY_EPIC:
				bonus.max_hp += 30
			if quality >= QUALITY_LEGENDARY:
				bonus.max_hp += 40
		"wood_shoes":
			if quality >= QUALITY_COMMON:
				bonus.crit_rate += 0.05 + float(level - 1) * 0.01
			if quality >= QUALITY_RARE:
				bonus.crit_rate += 0.05
			if quality >= QUALITY_EPIC:
				bonus.crit_rate += 0.05
			if quality >= QUALITY_LEGENDARY:
				bonus.crit_rate += 0.05
	return bonus


func get_equipment_totals() -> Dictionary:
	_ensure_slot_state()
	var total := {
		"attack": 0.0,
		"max_hp": 0,
		"crit_rate": 0.0,
		"item_power": 0,
	}
	for slot in SLOT_ORDER:
		var item := get_equipped_item(slot)
		if item.is_empty():
			continue
		var bonus := get_item_stat_bonus(item)
		total.attack += float(bonus.get("attack", 0.0))
		total.max_hp += int(bonus.get("max_hp", 0))
		total.crit_rate += float(bonus.get("crit_rate", 0.0))
		total.item_power += int(bonus.get("item_power", 0))
	return total


func get_battle_modifiers() -> Dictionary:
	var totals := get_equipment_totals()
	return {
		"attack": float(totals.get("attack", 0.0)),
		"max_hp": int(totals.get("max_hp", 0)),
		"crit_rate": float(totals.get("crit_rate", 0.0)),
	}


func get_weapon_extra_damage_effect() -> Dictionary:
	var weapon := get_equipped_item(SLOT_WEAPON)
	if weapon.is_empty():
		return {}
	if str(weapon.get("def_id", "")) != "short_dagger":
		return {}
	if int(weapon.get("quality", QUALITY_COMMON)) < QUALITY_RARE:
		return {}
	return {
		"chance": 0.5,
		"ratio": 0.2,
	}


func roll_weapon_extra_damage(base_damage: int) -> int:
	if base_damage <= 0:
		return 0
	var fx := get_weapon_extra_damage_effect()
	if fx.is_empty():
		return 0
	if randf() > float(fx.get("chance", 0.0)):
		return 0
	return maxi(1, int(round(float(base_damage) * float(fx.get("ratio", 0.0)))))


func get_player_preview_attributes() -> Dictionary:
	var base_attack := float(GameConfig.get_player_value("base_attack", 95))
	var base_hp := int(GameConfig.get_player_value("base_hp", 100))
	var base_crit := float(GameConfig.get_player_value("base_crit_rate", 0.08))
	var equip := get_equipment_totals()
	var final_attack := base_attack + float(equip.get("attack", 0.0))
	var final_hp := base_hp + int(equip.get("max_hp", 0))
	var final_crit := base_crit + float(equip.get("crit_rate", 0.0))
	var power := _calc_battle_power(final_attack, final_hp, final_crit, int(equip.get("item_power", 0)))
	return {
		"base_attack": base_attack,
		"base_hp": base_hp,
		"base_crit_rate": base_crit,
		"equip_attack": float(equip.get("attack", 0.0)),
		"equip_hp": int(equip.get("max_hp", 0)),
		"equip_crit_rate": float(equip.get("crit_rate", 0.0)),
		"attack": final_attack,
		"hp": final_hp,
		"crit_rate": final_crit,
		"battle_power": power,
	}


func _calc_battle_power(attack: float, hp: int, crit_rate: float, item_power: int) -> int:
	return int(round(attack * 3.2 + float(hp) * 1.1 + crit_rate * 100.0 + float(item_power)))
