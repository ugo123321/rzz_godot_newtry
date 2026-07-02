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
const EQUIPMENT_DROP_ENABLED := true

var gold: int = 0
var wood: int = 0
var equipment_inventory: Array[Dictionary] = []
var equipped_by_slot: Dictionary = {}
var _next_item_uid := 1

# Chapter-scoped tower persistence (build house phases accumulate within a chapter)
var chapter_active_id: int = 0  # 0 = no active chapter
var chapter_tower_height: float = 0.0
var chapter_tower_blocks: Array = []  # each: {pos: Vector2, angle: float}

const EQUIPMENTS_JSON_PATH := "res://config/json/equipments.json"
# def_id -> { def_id, name_cn, name_en, slot, icon_path, is_rare, base_power, tiers[4] }
# 由 config/json/equipments.json 加载。tools/export_equipments_json.py 从 xlsx 生成。
var equipment_defs: Dictionary = {}


func _ready() -> void:
	_load_equipment_defs()
	_ensure_slot_state()
	call_deferred("_emit_all_state")


func _load_equipment_defs() -> void:
	equipment_defs.clear()
	if not ResourceLoader.exists(EQUIPMENTS_JSON_PATH):
		push_warning("[LobbyState] equipments.json not found at %s" % EQUIPMENTS_JSON_PATH)
		return
	var f := FileAccess.open(EQUIPMENTS_JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("[LobbyState] failed to open %s" % EQUIPMENTS_JSON_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LobbyState] equipments.json is not a dict")
		return
	var arr = parsed.get("equipments", [])
	if typeof(arr) != TYPE_ARRAY:
		return
	for rec in arr:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var def_id := str(rec.get("def_id", ""))
		if def_id.is_empty():
			continue
		# base_power 未在 JSON 声明，用槽位默认值：weapon 38 / armor 32 / helmet 30 / shoes 28
		var slot_key := str(rec.get("slot", SLOT_WEAPON))
		var default_power := 30
		if slot_key == SLOT_WEAPON:
			default_power = 38
		elif slot_key == SLOT_ARMOR:
			default_power = 32
		elif slot_key == SLOT_HELMET:
			default_power = 30
		elif slot_key == SLOT_SHOES:
			default_power = 28
		elif slot_key == SLOT_NECKLACE or slot_key == SLOT_RING:
			default_power = 26
		var def: Dictionary = rec.duplicate(true)
		def["base_power"] = int(rec.get("base_power", default_power))
		equipment_defs[def_id] = def


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
		EventBus.wood_changed.emit(wood)
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


func add_wood(amount: int) -> void:
	if amount <= 0:
		return
	wood += amount
	if EventBus:
		EventBus.wood_changed.emit(wood)


func spend_wood(amount: int) -> bool:
	if amount <= 0:
		return true
	if wood < amount:
		return false
	wood -= amount
	if EventBus:
		EventBus.wood_changed.emit(wood)
	return true


func set_wood(amount: int) -> void:
	wood = maxi(0, amount)
	if EventBus:
		EventBus.wood_changed.emit(wood)


func reset_wood() -> void:
	set_wood(0)


func reset_chapter_tower(chapter_id: int) -> void:
	chapter_active_id = chapter_id
	chapter_tower_height = 0.0
	chapter_tower_blocks.clear()


func save_chapter_tower(height_m: float, blocks: Array) -> void:
	chapter_tower_height = height_m
	chapter_tower_blocks = blocks


func ensure_chapter_tower(chapter_id: int) -> void:
	if chapter_active_id != chapter_id:
		reset_chapter_tower(chapter_id)


func get_slot_display_name(slot: String) -> String:
	match slot:
		SLOT_WEAPON:
			return LanguageManager.tr_ui("UI_SLOT_WEAPON")
		SLOT_HELMET:
			return LanguageManager.tr_ui("UI_SLOT_HELMET")
		SLOT_NECKLACE:
			return LanguageManager.tr_ui("UI_SLOT_NECKLACE")
		SLOT_RING:
			return LanguageManager.tr_ui("UI_SLOT_RING")
		SLOT_ARMOR:
			return LanguageManager.tr_ui("UI_SLOT_ARMOR")
		SLOT_SHOES:
			return LanguageManager.tr_ui("UI_SLOT_SHOES")
	return LanguageManager.tr_ui("UI_SLOT_UNKNOWN")


func get_quality_name(quality: int) -> String:
	const KEYS := ["UI_QUALITY_COMMON", "UI_QUALITY_RARE", "UI_QUALITY_EPIC", "UI_QUALITY_LEGENDARY"]
	var idx := clampi(quality, 0, KEYS.size() - 1)
	return LanguageManager.tr_ui(KEYS[idx])


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
	if not EQUIPMENT_DROP_ENABLED:
		return {}
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
	var def_id := str(item.get("def_id", ""))
	var def := get_item_def(def_id)
	# JSON 里的 name_cn / name_en → LanguageManager.localize(def, "name")
	var name := LanguageManager.localize(def, "name")
	if name != "":
		return name
	return LanguageManager.tr_ui("UI_EQUIP_UNKNOWN_NAME", def_id)


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
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		return LanguageManager.tr_ui("UI_EQUIP_UNDEFINED_SKILL")
	var tiers = def.get("tiers", [])
	if typeof(tiers) != TYPE_ARRAY or tier < 0 or tier >= tiers.size():
		return LanguageManager.tr_ui("UI_EQUIP_UNDEFINED_SKILL")
	var tier_rec: Dictionary = tiers[tier]
	return LanguageManager.localize_field(tier_rec, "effect_desc_en", "effect_desc_cn")


func get_item_stat_bonus(item: Dictionary) -> Dictionary:
	# 累加 tier 0..quality 的 stat_bonuses（加法叠加，绝不连乘）。
	# 缺失键取 0；未识别的 key 也会被并入（future-proof）。
	var bonus := {
		"attack": 0.0,
		"max_hp": 0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"max_ki_pct": 0.0,
		"ki_regen_pct": 0.0,
		"item_power": get_item_power(item),
	}
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		return bonus
	var quality := int(item.get("quality", QUALITY_COMMON))
	var level := int(item.get("level", 1))
	var tiers = def.get("tiers", [])
	if typeof(tiers) != TYPE_ARRAY:
		return bonus
	for t in range(min(tiers.size(), quality + 1)):
		var tier_rec: Dictionary = tiers[t]
		var sb = tier_rec.get("stat_bonuses", {})
		if typeof(sb) != TYPE_DICTIONARY:
			continue
		for k in sb.keys():
			var key := str(k)
			var val := float(sb[k])
			match key:
				"attack":
					bonus.attack += val
				"max_hp":
					bonus.max_hp = int(bonus.max_hp) + int(val)
				"crit_rate":
					bonus.crit_rate += val
				"crit_damage":
					bonus.crit_damage += val
				"move_speed":
					bonus.move_speed += val
				"max_ki_pct":
					bonus.max_ki_pct += val
				"ki_regen_pct":
					bonus.ki_regen_pct += val
	# 强化等级：仅让"每级 +N"的通用 flat 加成生效 —— 目前 xlsx 未给出 per_lv 表达，
	# 沿用旧规则：level 每级给该件 base attack/hp/crit_rate 一个微增，避免强化毫无收益。
	if level > 1:
		var lv_bonus := level - 1
		bonus.attack += float(lv_bonus) * 2.0
		bonus.max_hp = int(bonus.max_hp) + lv_bonus * 2
		bonus.crit_rate += float(lv_bonus) * 0.01
	return bonus


func get_active_equipment_flags() -> Dictionary:
	# 遍历所有已装备物品的 tiers[0..quality]，收集所有 flag（非 null / 非空字符串）。
	# 目前所有 flag 都在 quality=3 才解锁 —— 但框架允许更低 tier 也带 flag。
	var flags: Dictionary = {}
	_ensure_slot_state()
	for slot in SLOT_ORDER:
		var item := get_equipped_item(slot)
		if item.is_empty():
			continue
		var def := get_item_def(str(item.get("def_id", "")))
		if def.is_empty():
			continue
		var quality := int(item.get("quality", QUALITY_COMMON))
		var tiers = def.get("tiers", [])
		if typeof(tiers) != TYPE_ARRAY:
			continue
		for t in range(min(tiers.size(), quality + 1)):
			var tier_rec: Dictionary = tiers[t]
			var flag = tier_rec.get("flag", null)
			if flag == null:
				continue
			var flag_str := str(flag)
			if flag_str.is_empty():
				continue
			flags[flag_str] = true
	return flags


func get_equipment_totals() -> Dictionary:
	_ensure_slot_state()
	var total := {
		"attack": 0.0,
		"max_hp": 0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"max_ki_pct": 0.0,
		"ki_regen_pct": 0.0,
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
		total.crit_damage += float(bonus.get("crit_damage", 0.0))
		total.move_speed += float(bonus.get("move_speed", 0.0))
		total.max_ki_pct += float(bonus.get("max_ki_pct", 0.0))
		total.ki_regen_pct += float(bonus.get("ki_regen_pct", 0.0))
		total.item_power += int(bonus.get("item_power", 0))
	return total


func get_battle_modifiers() -> Dictionary:
	# player.gd 直接消费；含所有 stat 通道。加法叠加已在 get_equipment_totals 完成。
	var totals := get_equipment_totals()
	return {
		"attack": float(totals.get("attack", 0.0)),
		"max_hp": int(totals.get("max_hp", 0)),
		"crit_rate": float(totals.get("crit_rate", 0.0)),
		"crit_damage": float(totals.get("crit_damage", 0.0)),
		"move_speed": float(totals.get("move_speed", 0.0)),
		"max_ki_pct": float(totals.get("max_ki_pct", 0.0)),
		"ki_regen_pct": float(totals.get("ki_regen_pct", 0.0)),
	}


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
