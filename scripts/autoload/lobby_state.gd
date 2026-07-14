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

var gold: int = 5000
var wood: int = 0
var equipment_inventory: Array[Dictionary] = []
var equipped_by_slot: Dictionary = {}
var _next_item_uid := 1

# ─── 技能石系统（no-savedata 分支，仅会话内存）─────────────────────
# 每块 stone: {uid:int, skill_id:String, quality:int(0-3), affixes:Array[{stat_key,value}]}
# skill 部分 = 进入战斗自动 apply_upgrade(skill_id)（等同一次升级奖励）；
# 属性部分 = affixes 求和进 player 的 *_pct_total（crit_damage 走乘法）。
var skill_stone_inventory: Array[Dictionary] = []
var skill_stone_equipped: Array[int] = [-1, -1, -1]
var _next_skill_stone_uid := 1

# Chapter-scoped tower persistence (build house phases accumulate within a chapter)
var chapter_active_id: int = 0  # 0 = no active chapter
var chapter_tower_height: float = 0.0
var chapter_tower_blocks: Array = []  # each: {pos: Vector2, angle: float}

const EQUIPMENTS_JSON_PATH := "res://config/json/equipments.json"
# def_id -> { def_id, name_cn, name_en, slot, icon_path, is_rare, base_power, tiers[4] }
# 由 config/json/equipments.json 加载。tools/export_equipments_json.py 从 xlsx 生成。
var equipment_defs: Dictionary = {}

# 天赋卡牌（config/excel/card.xlsx → config/json/talents.json）
const TALENTS_JSON_PATH := "res://config/json/talents.json"
const TALENT_DRAW_COST := 100
var talent_defs: Dictionary = {}           # id -> def dict（含 effects[] / display[] / unlock_flag / pity_target 等）
var talent_order: Array[String] = []       # 保持 xlsx 顺序，供 UI 网格排列
var talents_owned: Dictionary = {}         # id -> level (int, 1..max_level)
var talent_pity_counters: Dictionary = {}  # id -> 连续未抽到该卡的次数（选中归零；不入 pool 的卡不动）
var _first_reward_given_this_run: bool = false  # 先发制人卡的 per-run flag，由 request_battle_launch 重置

# 侦察挂机（会话内累计，本分支 no-savedata，不写盘）
const SCOUT_BASE_HOURLY_GOLD := 100          # 第 1 章基础每小时金币
const SCOUT_PER_CHAPTER_BONUS := 80          # 每提升 1 章 +80/小时
const SCOUT_MAX_ACCUMULATE_SECONDS := 86400  # 24 小时上限
var _scout_last_settle_unix: int = 0         # 上次结算/领取时的 unix 秒；启动时初始化


func _ready() -> void:
	_load_equipment_defs()
	_load_talent_defs()
	_ensure_slot_state()
	_scout_last_settle_unix = int(Time.get_unix_time_from_system())
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


func _load_talent_defs() -> void:
	talent_defs.clear()
	talent_order.clear()
	if not ResourceLoader.exists(TALENTS_JSON_PATH):
		push_warning("[LobbyState] talents.json not found at %s" % TALENTS_JSON_PATH)
		return
	var f := FileAccess.open(TALENTS_JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("[LobbyState] failed to open %s" % TALENTS_JSON_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LobbyState] talents.json is not a dict")
		return
	var arr = parsed.get("talents", [])
	if typeof(arr) != TYPE_ARRAY:
		return
	for rec in arr:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var tid := str(rec.get("id", ""))
		if tid.is_empty():
			continue
		talent_defs[tid] = rec.duplicate(true)
		talent_order.append(tid)


func get_talent_def(id: String) -> Dictionary:
	var src: Dictionary = talent_defs.get(id, {})
	return src.duplicate(true)


func get_talent_level(id: String) -> int:
	return int(talents_owned.get(id, 0))


func get_owned_talent_ids() -> Array[String]:
	var result: Array[String] = []
	for tid in talent_order:
		if int(talents_owned.get(tid, 0)) > 0:
			result.append(tid)
	return result


# 结果 dict：
#   {}                              = 抽卡失败（余额不足）
#   {status:"max_all", id:""}       = 全部满级；不扣款
#   {status:"ok", id, level_before, level_after, is_new, is_pity, def}
func draw_talent_card() -> Dictionary:
	if talent_order.is_empty():
		return {}
	# 先收集所有未满级候选（保底 counter 只对未满级卡生效）
	var pool: Array[String] = []
	var weights: Array[int] = []
	var total_weight := 0
	for tid in talent_order:
		var def: Dictionary = talent_defs[tid]
		var max_lv := int(def.get("max_level", 1))
		var cur_lv := int(talents_owned.get(tid, 0))
		if cur_lv >= max_lv:
			continue
		var w := int(def.get("weight", 1))
		if w <= 0:
			continue
		pool.append(tid)
		weights.append(w)
		total_weight += w
	if pool.is_empty():
		return {"status": "max_all", "id": ""}
	if gold < TALENT_DRAW_COST:
		return {}
	if not spend_gold(TALENT_DRAW_COST):
		return {}
	# 保底检查：任何 candidate 的 counter+1 >= pity_target 就强制中它（多张时选 counter 最大）
	var picked_id := ""
	var is_pity := false
	var pity_champ := ""
	var pity_champ_counter := -1
	for tid in pool:
		var def: Dictionary = talent_defs[tid]
		var pity_target := int(def.get("pity_target", 0))
		if pity_target <= 0:
			continue
		var counter := int(talent_pity_counters.get(tid, 0))
		# 本次抽卡未中就会 +1，所以判断 counter+1 >= pity_target 即为触发
		if counter + 1 >= pity_target and counter > pity_champ_counter:
			pity_champ = tid
			pity_champ_counter = counter
	if pity_champ != "":
		picked_id = pity_champ
		is_pity = true
	else:
		# 正常加权随机
		var roll := randi_range(1, total_weight)
		var acc := 0
		picked_id = pool[0]
		for i in range(pool.size()):
			acc += weights[i]
			if roll <= acc:
				picked_id = pool[i]
				break
	# counter 更新：未选中 → +1；选中 → 归零
	for tid in pool:
		if tid == picked_id:
			talent_pity_counters[tid] = 0
		else:
			talent_pity_counters[tid] = int(talent_pity_counters.get(tid, 0)) + 1
	var level_before := int(talents_owned.get(picked_id, 0))
	var level_after := level_before + 1
	talents_owned[picked_id] = level_after
	if EventBus:
		EventBus.talent_changed.emit(picked_id, level_before, level_after)
	return {
		"status": "ok",
		"id": picked_id,
		"level_before": level_before,
		"level_after": level_after,
		"is_new": level_before == 0,
		"is_pity": is_pity,
		"def": talent_defs[picked_id].duplicate(true),
	}


# 是否已解锁指定 unlock_flag（橙卡 unlock_flag 非空 + level >= 1）
func has_unlock(flag: String) -> bool:
	if flag.is_empty():
		return false
	for tid in talents_owned.keys():
		if int(talents_owned[tid]) < 1:
			continue
		var def: Dictionary = talent_defs.get(tid, {})
		if str(def.get("unlock_flag", "")) == flag:
			return true
	return false


# 调试专用：一键把所有 unlock 卡设为 LV1（发 talent_changed 循环让 UI refresh）
func force_unlock_all_orange() -> void:
	for tid in talent_order:
		var def: Dictionary = talent_defs.get(tid, {})
		if str(def.get("unlock_flag", "")).is_empty():
			continue
		var old_lv := int(talents_owned.get(tid, 0))
		if old_lv >= 1:
			continue
		talents_owned[tid] = 1
		if EventBus:
			EventBus.talent_changed.emit(tid, old_lv, 1)


# 累加所有已拥有卡片的当前等级效果 → 属性通道字典
func get_talent_modifiers() -> Dictionary:
	var mods := {
		"attack": 0.0,
		"max_hp": 0,
		"max_ki": 0.0,
		"ki_regen": 0.0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"attack_interval": 0.0,   # 累加负值 → 减少 attack_interval → 提升攻速
		"bullet_range": 0.0,      # 累加子弹有效射程 (px)
	}
	for tid in talents_owned.keys():
		var level := int(talents_owned[tid])
		if level <= 0:
			continue
		var def: Dictionary = talent_defs.get(tid, {})
		if def.is_empty():
			continue
		var effects_arr = def.get("effects", [])
		if typeof(effects_arr) != TYPE_ARRAY:
			continue
		for e in effects_arr:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var key := str(e.get("key", ""))
			if not mods.has(key):
				continue
			var per_lv := float(e.get("per_level", 0.0))
			var total := per_lv * float(level)
			if key == "max_hp":
				mods[key] = int(mods[key]) + int(round(total))
			else:
				mods[key] = float(mods[key]) + total
	return mods


func get_talent_name(id: String) -> String:
	var def := get_talent_def(id)
	return LanguageManager.localize(def, "name")


# 按 desc_template + display[] 生成"累计值"描述文案。
# desc_template_cn/en 里的 {v0}/{v1} → display[i].per_level × level（若 pct=true 则再拼 `%`）
# 未拥有的卡传 level=0 → 显示"每级增量"（即 v0 = display.per_level × 1）。
func get_talent_desc_at_level(id_or_def, level: int) -> String:
	var def: Dictionary
	if typeof(id_or_def) == TYPE_STRING:
		def = get_talent_def(str(id_or_def))
	elif typeof(id_or_def) == TYPE_DICTIONARY:
		def = id_or_def
	else:
		return ""
	if def.is_empty():
		return ""
	var tmpl := LanguageManager.localize_field(def, "desc_template_en", "desc_template_cn")
	var display_arr = def.get("display", [])
	if typeof(display_arr) != TYPE_ARRAY or display_arr.is_empty():
		return tmpl  # 橙卡等无属性文案，模板本身就是完整描述
	var factor := maxi(level, 1)
	for i in range(display_arr.size()):
		var d = display_arr[i]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var per_lv := float(d.get("per_level", 0.0))
		var is_pct := bool(d.get("pct", false))
		var v := per_lv * float(factor)
		var v_str := ""
		if abs(v - round(v)) < 0.01:
			v_str = "%d" % int(round(v))
		else:
			v_str = ("%.1f" % v).trim_suffix(".0")
		if is_pct:
			v_str += "%"
		tmpl = tmpl.replace("{v%d}" % i, v_str)
	return tmpl


func request_battle_launch(p_stage_index: int) -> void:
	stage_index = maxi(0, p_stage_index)
	_pending_launch = true
	_first_reward_given_this_run = false  # 每次新一局重置先发制人 flag


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


# ─── 侦察挂机 ─────────────────────────────────────────────
# 章节获取：目前只有 1 章，且无"最高通关章节"记录 → 用当前所选 stage 所在章节。
# 后续接入存档 / 加"highest_chapter" 字段时，只改这一处返回值即可。
func get_scout_chapter_id() -> int:
	if not is_instance_valid(GameConfig):
		return 1
	var chap := GameConfig.get_chapter_for_stage(stage_index)
	if chap.is_empty():
		return 1
	return int(chap.get("chapter_id", 1))


func get_scout_hourly_gold() -> int:
	var cid := get_scout_chapter_id()
	return SCOUT_BASE_HOURLY_GOLD + maxi(0, cid - 1) * SCOUT_PER_CHAPTER_BONUS


func get_scout_accumulated_seconds() -> int:
	var now := int(Time.get_unix_time_from_system())
	var delta := now - _scout_last_settle_unix
	if delta < 0:
		delta = 0
	return mini(delta, SCOUT_MAX_ACCUMULATE_SECONDS)


func get_scout_pending_gold() -> int:
	var secs := get_scout_accumulated_seconds()
	if secs <= 0:
		return 0
	return int(floor(float(secs) / 3600.0 * float(get_scout_hourly_gold())))


func claim_scout_reward() -> int:
	var reward := get_scout_pending_gold()
	if reward <= 0:
		return 0
	add_gold(reward)
	_scout_last_settle_unix = int(Time.get_unix_time_from_system())
	if EventBus:
		EventBus.scout_claimed.emit(reward)
	return reward


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


# ════════════════════════════════════════════════════════════════
# 技能石系统
# ════════════════════════════════════════════════════════════════

const RARITY_TO_QUALITY := {
	"white": 0,
	"blue": 1,
	"purple": 2,
	"orange": 3,
}

const QUALITY_TO_RARITY := ["white", "blue", "purple", "orange"]


func _ss_rule(key: String, default_value = null):
	var rules: Dictionary = GameConfig.get_skill_stone_rules()
	return rules.get(key, default_value)


func _ensure_skill_stone_slots() -> void:
	var count := int(_ss_rule("equipped_slot_count", 3))
	if count < 1:
		count = 1
	while skill_stone_equipped.size() < count:
		skill_stone_equipped.append(-1)
	while skill_stone_equipped.size() > count:
		skill_stone_equipped.pop_back()


func rarity_to_quality(rarity: String) -> int:
	return int(RARITY_TO_QUALITY.get(rarity, QUALITY_COMMON))


## 返回该品质下的可选技能石 def 列表（已 enabled 且 rarity 匹配；来自 GameConfig）。
func get_skill_stone_pool(quality: int) -> Array:
	var out: Array = []
	var rarity_key := str(QUALITY_TO_RARITY[clampi(quality, 0, QUALITY_TO_RARITY.size() - 1)])
	var cfg: Dictionary = GameConfig.get_skill_stone_config()
	var stones = cfg.get("stones", [])
	if typeof(stones) != TYPE_ARRAY:
		return out
	for s in stones:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("rarity", "")) == rarity_key:
			out.append(s)
	return out


## 掷一次掉落。返回 stone dict（含 fx 需要的 icon_path / quality）；未掉落返回 {}。
func roll_skill_stone_drop(is_boss: bool) -> Dictionary:
	var rate := float(_ss_rule("boss_drop_rate" if is_boss else "small_drop_rate", 1.0 if is_boss else 0.01))
	if randf() > rate:
		return {}
	var quality := _roll_skill_stone_quality()
	var pool := get_skill_stone_pool(quality)
	if pool.is_empty():
		# 兜底：放宽到全池
		pool = GameConfig.get_skill_stone_config().get("stones", [])
	if pool.is_empty():
		return {}
	var def: Dictionary = pool[randi() % pool.size()]
	var skill_id := str(def.get("skill_id", ""))
	if skill_id.is_empty():
		return {}
	var affixes := _roll_skill_stone_affixes(quality)
	var stone := add_skill_stone(skill_id, quality, affixes)
	if stone.is_empty():
		return {}
	# 给 fx 用：附带 icon_path + quality（fx._get_equipment_icon 优先读 icon_path）
	stone["icon_path"] = get_skill_stone_icon_path(stone)
	return stone


func _roll_skill_stone_quality() -> int:
	var w := float(_ss_rule("rarity_white", 0.50))
	var b := float(_ss_rule("rarity_blue", 0.30))
	var p := float(_ss_rule("rarity_purple", 0.15))
	var o := float(_ss_rule("rarity_orange", 0.05))
	var total := w + b + p + o
	if total <= 0.0:
		return QUALITY_COMMON
	var roll := randf() * total
	if roll < w:
		return QUALITY_COMMON
	if roll < w + b:
		return QUALITY_RARE
	if roll < w + b + p:
		return QUALITY_EPIC
	return QUALITY_LEGENDARY


func _roll_skill_stone_affixes(quality: int) -> Array:
	var rarity_key := str(QUALITY_TO_RARITY[clampi(quality, 0, QUALITY_TO_RARITY.size() - 1)])
	var count := int(_ss_rule("affix_count_%s" % rarity_key, 0))
	var stat_pool: Array = _ss_rule("affix_stats", [])
	if typeof(stat_pool) != TYPE_ARRAY or stat_pool.is_empty() or count <= 0:
		return []
	# 不放回采样 count 个不同 stat_key
	var available: Array = []
	for s in stat_pool:
		available.append(str(s))
	available.shuffle()
	count = mini(count, available.size())
	var lo := float(_ss_rule("affix_min", -0.10))
	var hi := float(_ss_rule("affix_max", 0.10))
	var out: Array = []
	for i in range(count):
		var v := randf_range(lo, hi)
		# 保留两位小数，便于展示
		v = round(v * 100.0) / 100.0
		out.append({"stat_key": available[i], "value": v})
	return out


## 新增一块技能石到背包。affixes: [{stat_key, value}]。
func add_skill_stone(skill_id: String, quality: int, affixes: Array) -> Dictionary:
	var stone: Dictionary = {
		"uid": _next_skill_stone_uid,
		"skill_id": skill_id,
		"quality": clampi(quality, QUALITY_COMMON, QUALITY_LEGENDARY),
		"affixes": affixes.duplicate(true),
	}
	_next_skill_stone_uid += 1
	skill_stone_inventory.append(stone)
	_emit_skill_stones_changed()
	return stone.duplicate(true)


func _find_skill_stone_index(uid: int) -> int:
	for i in range(skill_stone_inventory.size()):
		if int(skill_stone_inventory[i].get("uid", -1)) == uid:
			return i
	return -1


func get_skill_stone_by_uid(uid: int) -> Dictionary:
	var idx := _find_skill_stone_index(uid)
	if idx < 0:
		return {}
	return skill_stone_inventory[idx].duplicate(true)


func is_skill_stone_equipped(uid: int) -> bool:
	_ensure_skill_stone_slots()
	for v in skill_stone_equipped:
		if int(v) == uid:
			return true
	return false


## 装备到指定槽；slot=-1 自动找第一个空槽。返回槽号，失败返回 -1。
func equip_skill_stone(uid: int, slot: int = -1) -> int:
	_ensure_skill_stone_slots()
	if _find_skill_stone_index(uid) < 0:
		return -1
	if is_skill_stone_equipped(uid):
		return -1
	if slot < 0:
		for i in range(skill_stone_equipped.size()):
			if int(skill_stone_equipped[i]) < 0:
				slot = i
				break
	if slot < 0 or slot >= skill_stone_equipped.size():
		return -1
	if int(skill_stone_equipped[slot]) >= 0:
		return -1
	skill_stone_equipped[slot] = uid
	_emit_skill_stones_changed()
	return slot


func unequip_skill_stone(slot: int) -> bool:
	_ensure_skill_stone_slots()
	if slot < 0 or slot >= skill_stone_equipped.size():
		return false
	if int(skill_stone_equipped[slot]) < 0:
		return false
	skill_stone_equipped[slot] = -1
	_emit_skill_stones_changed()
	return true


## 分解多块。仅未装备的允许；返回总金币（已 add_gold）。失败返回 -1。
func decompose_skill_stones(uids: Array) -> int:
	var parsed: Array[int] = []
	for raw in uids:
		var uid := int(raw)
		if uid < 0:
			continue
		if parsed.has(uid):
			continue
		if _find_skill_stone_index(uid) < 0:
			continue
		if is_skill_stone_equipped(uid):
			continue
		parsed.append(uid)
	if parsed.is_empty():
		return -1
	var total := 0
	for uid in parsed:
		var idx := _find_skill_stone_index(uid)
		if idx < 0:
			continue
		var stone: Dictionary = skill_stone_inventory[idx]
		total += get_skill_stone_decompose_gold(stone)
		skill_stone_inventory.remove_at(idx)
	if total > 0:
		add_gold(total)
	_emit_skill_stones_changed()
	return total


## 背包未装备的技能石（按 quality 降序 + uid）。
func get_skill_stone_inventory_sorted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stone in skill_stone_inventory:
		var uid := int(stone.get("uid", -1))
		if is_skill_stone_equipped(uid):
			continue
		out.append(stone.duplicate(true))
	out.sort_custom(_sort_skill_stone)
	return out


func _sort_skill_stone(a: Dictionary, b: Dictionary) -> bool:
	var qa := int(a.get("quality", 0))
	var qb := int(b.get("quality", 0))
	if qa != qb:
		return qa > qb
	return int(a.get("uid", 0)) < int(b.get("uid", 0))


func get_equipped_skill_stones() -> Array[Dictionary]:
	_ensure_skill_stone_slots()
	var out: Array[Dictionary] = []
	for v in skill_stone_equipped:
		var uid := int(v)
		if uid < 0:
			continue
		var stone := get_skill_stone_by_uid(uid)
		if stone.is_empty():
			continue
		out.append(stone)
	return out


## 3 个已装备技能石 affixes 求和 → {stat_key: sum_value}。
func get_skill_stone_affix_totals() -> Dictionary:
	var totals: Dictionary = {}
	for stone in get_equipped_skill_stones():
		var affixes = stone.get("affixes", [])
		if typeof(affixes) != TYPE_ARRAY:
			continue
		for a in affixes:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var key := str(a.get("stat_key", ""))
			if key.is_empty():
				continue
			var v := float(a.get("value", 0.0))
			totals[key] = float(totals.get(key, 0.0)) + v
	return totals


func get_skill_stone_def(skill_id: String) -> Dictionary:
	return GameConfig.get_skill_stone_def(skill_id)


func get_skill_stone_name(stone: Dictionary) -> String:
	var def := get_skill_stone_def(str(stone.get("skill_id", "")))
	if def.is_empty():
		return str(stone.get("skill_id", ""))
	# 配置表字段：name_cn / name_en → localize
	var name := LanguageManager.localize_field(def, "name_en", "name_cn")
	if name == "":
		name = str(def.get("name_cn", ""))
	return name


func get_skill_stone_icon_path(stone: Dictionary) -> String:
	var def := get_skill_stone_def(str(stone.get("skill_id", "")))
	var icon := str(def.get("icon", ""))
	if icon.is_empty() or not icon.begins_with("skill_"):
		return ""
	return "res://assets/ui/icons/upgrades/" + icon + ".png"


func get_skill_stone_desc(stone: Dictionary) -> String:
	var def := get_skill_stone_def(str(stone.get("skill_id", "")))
	return LanguageManager.localize_field(def, "desc_cn_game_en", "desc_cn_game")


func get_skill_stone_decompose_gold(stone: Dictionary) -> int:
	var def := get_skill_stone_def(str(stone.get("skill_id", "")))
	var v = def.get("decompose_gold", null)
	if v != null:
		return maxi(0, int(v))
	return maxi(0, int(_ss_rule("decompose_gold_default", 5)))


func _emit_skill_stones_changed() -> void:
	if EventBus:
		EventBus.skill_stones_changed.emit()

