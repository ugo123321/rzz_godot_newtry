extends Node
## 主界面与战斗场景之间的启动参数（章节、关卡索引等）。

var stage_index: int = 0

# 玩家显示名（主界面信息卡）。no-savedata，会话内不变；后续接入存档/改名时改这里。
var player_name: String = "player001"
# 会话内最高到达关卡（1-based 计数；no-savedata，每次启动重置为 1）。
# battle stage_cleared 时推进；主界面进度条据此显示「当前/总数」。
var highest_stage_reached: int = 1

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
# 关卡编辑器「测试」模式：切到真实战斗场景跑当前布局；停止时回编辑器。
var editor_test_mode: bool = false
var editor_test_layout: String = ""  # 测试时载入的布局编号（编辑器自动保存到 user://levels/__editor_test__.json）
var editor_test_stage: int = 0  # 测试用关卡 index（默认 0，有怪物 counts）
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
	_grant_test_items()
	# 关卡通关 → 推进最高到达关卡（主界面进度条数据源）。
	if EventBus != null and not EventBus.stage_cleared.is_connected(_on_stage_cleared):
		EventBus.stage_cleared.connect(_on_stage_cleared)


# stage_idx_0based 通关 → 解锁下一关；highest_stage_reached 为 1-based 计数。
func _on_stage_cleared(stage_idx_0based: int) -> void:
	var unlocked := stage_idx_0based + 2
	if unlocked > highest_stage_reached:
		highest_stage_reached = unlocked


# 测试用：debug 构建启动时赠送 15 件随机装备 + 15 块随机技能石，供合成 / 技能石 / 装备页调试。
# release 导出不会触发。本分支 no-savedata，每次启动游戏 = 一次新会话。
func _grant_test_items() -> void:
	if not OS.is_debug_build():
		return
	var keys := equipment_defs.keys()
	if not keys.is_empty():
		for i in 15:
			var def_id := str(keys[randi() % keys.size()])
			var q := i % (QUALITY_LEGENDARY + 1)  # 0,1,2,3 循环 → 各品质约 4 件，便于测合成
			add_equipment(def_id, q, 1)
	for i in 15:
		roll_skill_stone_drop(true)   # boss 掉率，随机品质 + 词缀


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
	editor_test_mode = false  # 正常开战斗一定不是编辑器测试；编辑器 _start_test 在调用本函数后再置 true
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
	# 每条 = 一个 quality tier 的显示条目。数值型 tier 文本由绝对值换算为百分比
	# （白阶含 per_level 成长）；flag tier 用原 desc。
	var result: Array[Dictionary] = []
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		# 仍返回 4 个空条目，保持 UI 段数稳定
		for tier in range(QUALITY_COMMON, QUALITY_LEGENDARY + 1):
			result.append({
				"quality": tier,
				"quality_name": get_quality_name(tier),
				"text": LanguageManager.tr_ui("UI_EQUIP_UNDEFINED_SKILL"),
				"unlocked": tier <= int(item.get("quality", QUALITY_COMMON)),
			})
		return result
	var quality := int(item.get("quality", QUALITY_COMMON))
	var level := int(item.get("level", 1))
	var plv = def.get("per_level_bonuses", {})
	var plv_pcts = def.get("per_level_pcts", {})
	var tiers = def.get("tiers", [])
	if typeof(tiers) != TYPE_ARRAY:
		return result
	for tier in range(QUALITY_COMMON, QUALITY_LEGENDARY + 1):
		if tier >= tiers.size():
			break
		var tier_rec: Dictionary = tiers[tier]
		var flag = tier_rec.get("flag", null)
		var text := ""
		if flag != null:
			text = LanguageManager.localize_field(tier_rec, "effect_desc_en", "effect_desc_cn")
		else:
			var sb = tier_rec.get("stat_bonuses", {})
			var sp = tier_rec.get("stat_pcts", {})
			text = _equip_tier_display_text(sb, sp, tier, level, plv, plv_pcts)
		result.append({
			"quality": tier,
			"quality_name": get_quality_name(tier),
			"text": text,
			"unlocked": tier <= quality,
		})
	return result


# 装备 stat_key → (GameConfig base key, i18n stat 名 key)。
# base key 用于「百分比加成换算为 base × pct/100」（求和时累加不连乘）；
# name key 用于显示文案。显示不再查 base / 不再取整，直接显示 xlsx 原值。
const _EQUIP_STAT_META := {
	"attack":          ["base_attack",      "UI_EQUIP_STAT_ATTACK"],
	"max_hp":          ["base_hp",          "UI_EQUIP_STAT_MAX_HP"],
	"crit_rate":       ["base_crit_rate",   "UI_EQUIP_STAT_CRIT_RATE"],
	"crit_damage":     ["base_crit_damage", "UI_EQUIP_STAT_CRIT_DAMAGE"],
	"move_speed":      ["move_speed",       "UI_EQUIP_STAT_MOVE_SPEED"],
	"max_ki":          ["base_ki",          "UI_EQUIP_STAT_MAX_KI"],
	"ki_regen":        ["ki_regen_speed",   "UI_EQUIP_STAT_KI_REGEN"],
	"invincible_time": ["invincible_time",  "UI_EQUIP_STAT_INVINCIBLE_TIME"],
	"ki_per_pixel":    ["ki_per_pixel",     "UI_EQUIP_STAT_KI_PER_PIXEL"],
}


# 取某 stat 的基础值（用于百分比加成换算）。
func _equip_stat_base(stat_key: String) -> float:
	var meta = _EQUIP_STAT_META.get(stat_key, null)
	if meta == null:
		return 1.0
	var base := float(GameConfig.get_player_value(String(meta[0]), 1.0))
	return base if base != 0.0 else 1.0


# 数值格式化：保留 1 位小数，去尾 .0（3.0→"3", 0.5→"0.5", -5.0→"-5"）。
func _equip_fmt_num(v: float) -> String:
	var s := "%.1f" % v
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s


# 显示「stat 名 +N」或「stat 名 +N%」。is_pct=true 时尾部加 %。
# value 带符号；负值时 _equip_fmt_num 已含 -，sign 留空，得到 "stat -5%"。
func _equip_stat_display(stat_key: String, value: float, is_pct: bool) -> String:
	var meta = _EQUIP_STAT_META.get(stat_key, null)
	var name := stat_key if meta == null else String(LanguageManager.tr_ui(String(meta[1])))
	var num := _equip_fmt_num(value)
	var sign := "+" if value >= 0.0 else ""
	var tail := "%" if is_pct else ""
	return "%s %s%s%s" % [name, sign, num, tail]


# 把一个 tier 的 stat_bonuses（绝对值）+ stat_pcts（百分比）拼成显示文本。
# 白阶（tier 0）叠加 per_level×(level-1)（同类型相加）。
func _equip_tier_display_text(sb, sp, tier: int, level: int, plv, plv_pcts) -> String:
	var lines: PackedStringArray = []
	var is_white := tier == QUALITY_COMMON and level > 1
	# 绝对值条目
	if typeof(sb) == TYPE_DICTIONARY:
		for k in sb.keys():
			var key := str(k)
			var val := float(sb[k])
			if is_white and typeof(plv) == TYPE_DICTIONARY:
				val += float(plv.get(key, 0.0)) * float(level - 1)
			lines.append(_equip_stat_display(key, val, false))
	# 百分比条目
	if typeof(sp) == TYPE_DICTIONARY:
		for k in sp.keys():
			var key := str(k)
			var val := float(sp[k])
			if is_white and typeof(plv_pcts) == TYPE_DICTIONARY:
				val += float(plv_pcts.get(key, 0.0)) * float(level - 1)
			lines.append(_equip_stat_display(key, val, true))
	return "\n".join(lines)


func get_item_stat_bonus(item: Dictionary) -> Dictionary:
	# 累加 tier 0..quality 的 stat_bonuses（绝对值加法）+ stat_pcts（百分比 → base×pct/100 加法，
	# 各来源累加、不连乘）。per_level 同样拆 bonuses / pcts × (level-1) 叠加在顶层。
	# 最终 bonus 全部是绝对值，player.gd 直接加即可。
	var bonus := {
		"attack": 0.0,
		"max_hp": 0.0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"max_ki": 0.0,
		"ki_regen": 0.0,
		"invincible_time": 0.0,
		"ki_per_pixel": 0.0,
		"item_power": get_item_power(item),
	}
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		return bonus
	var quality := int(item.get("quality", QUALITY_COMMON))
	var tiers = def.get("tiers", [])
	if typeof(tiers) != TYPE_ARRAY:
		return bonus
	for t in range(min(tiers.size(), quality + 1)):
		var tier_rec: Dictionary = tiers[t]
		# 绝对值加成
		var sb = tier_rec.get("stat_bonuses", {})
		if typeof(sb) == TYPE_DICTIONARY:
			for k in sb.keys():
				var key := str(k)
				var val := float(sb[k])
				if bonus.has(key):
					bonus[key] += val
				else:
					push_warning("equip stat_bonus unknown key: %s" % key)
		# 百分比加成 → base × pct/100
		var sp = tier_rec.get("stat_pcts", {})
		if typeof(sp) == TYPE_DICTIONARY:
			for k in sp.keys():
				var key := str(k)
				if not bonus.has(key):
					push_warning("equip stat_pct unknown key: %s" % key)
					continue
				var base := _equip_stat_base(key)
				bonus[key] += base * float(sp[k]) / 100.0
	# G 列 per_level × (level-1) —— 数据驱动每级成长，替换旧硬编码
	var level := int(item.get("level", 1))
	if level > 1:
		var lv_factor := float(level - 1)
		# 绝对值每级
		var plv = def.get("per_level_bonuses", {})
		if typeof(plv) == TYPE_DICTIONARY:
			for k in plv.keys():
				var key := str(k)
				if not bonus.has(key):
					push_warning("equip per_level unknown key: %s" % key)
					continue
				bonus[key] += float(plv[k]) * lv_factor
		# 百分比每级 → base × pct/100 × (level-1)
		var plp = def.get("per_level_pcts", {})
		if typeof(plp) == TYPE_DICTIONARY:
			for k in plp.keys():
				var key := str(k)
				if not bonus.has(key):
					push_warning("equip per_level_pct unknown key: %s" % key)
					continue
				var base := _equip_stat_base(key)
				bonus[key] += base * float(plp[k]) / 100.0 * lv_factor
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
		"max_hp": 0.0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"max_ki": 0.0,
		"ki_regen": 0.0,
		"invincible_time": 0.0,
		"ki_per_pixel": 0.0,
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
		total.max_hp += float(bonus.get("max_hp", 0.0))
		total.crit_rate += float(bonus.get("crit_rate", 0.0))
		total.crit_damage += float(bonus.get("crit_damage", 0.0))
		total.move_speed += float(bonus.get("move_speed", 0.0))
		total.max_ki += float(bonus.get("max_ki", 0.0))
		total.ki_regen += float(bonus.get("ki_regen", 0.0))
		total.invincible_time += float(bonus.get("invincible_time", 0.0))
		total.ki_per_pixel += float(bonus.get("ki_per_pixel", 0.0))
		total.max_ki_pct += float(bonus.get("max_ki_pct", 0.0))
		total.ki_regen_pct += float(bonus.get("ki_regen_pct", 0.0))
		total.item_power += int(bonus.get("item_power", 0))
	return total


func get_battle_modifiers() -> Dictionary:
	# player.gd 直接消费；含所有 stat 通道。加法叠加已在 get_equipment_totals 完成。
	var totals := get_equipment_totals()
	return {
		"attack": float(totals.get("attack", 0.0)),
		"max_hp": float(totals.get("max_hp", 0.0)),
		"crit_rate": float(totals.get("crit_rate", 0.0)),
		"crit_damage": float(totals.get("crit_damage", 0.0)),       # 绝对加（v6）
		"move_speed": float(totals.get("move_speed", 0.0)),
		"max_ki": float(totals.get("max_ki", 0.0)),                  # 绝对（v6 新）
		"ki_regen": float(totals.get("ki_regen", 0.0)),              # 绝对（v6 新）
		"invincible_time": float(totals.get("invincible_time", 0.0)),    # 绝对（v6 新）
		"ki_per_pixel": float(totals.get("ki_per_pixel", 0.0)),      # 绝对，可为负（v6 新）
		# 旧 pct 路径保留（当前 json 不产出，forge/技能石 用 pct 走另一条线）
		"max_ki_pct": float(totals.get("max_ki_pct", 0.0)),
		"ki_regen_pct": float(totals.get("ki_regen_pct", 0.0)),
	}


func get_player_preview_attributes() -> Dictionary:
	# base 默认值对齐 player.json（旧代码残留 95/135 已过期）。
	var base_attack := float(GameConfig.get_player_value("base_attack", 52))
	var base_hp := float(GameConfig.get_player_value("base_hp", 3.0))
	var base_crit := float(GameConfig.get_player_value("base_crit_rate", 0.08))
	var base_move_speed := float(GameConfig.get_player_value("move_speed", 60))
	var base_crit_damage := float(GameConfig.get_player_value("base_crit_damage", 1.6))
	var base_ki := float(GameConfig.get_player_value("base_ki", 234))
	var base_ki_regen := float(GameConfig.get_player_value("ki_regen_speed", 60))
	var equip := get_equipment_totals()
	var equip_attack := float(equip.get("attack", 0.0))
	var equip_hp := float(equip.get("max_hp", 0.0))
	var equip_crit := float(equip.get("crit_rate", 0.0))
	var equip_move_speed := float(equip.get("move_speed", 0.0))
	# v6：crit_damage 装备为绝对加成（旧 pct 乘已废）
	var equip_crit_damage_add := float(equip.get("crit_damage", 0.0))
	# v6：max_ki / ki_regen 装备也为绝对加成（毛绒帽 / 丛林甲 等）
	var equip_max_ki_add := float(equip.get("max_ki", 0.0))
	var equip_ki_regen_add := float(equip.get("ki_regen", 0.0))
	# 旧 pct 路径保留（forge/技能石 走另一条线，装备 json 当前不产出）
	var equip_max_ki_pct := float(equip.get("max_ki_pct", 0.0))
	var equip_ki_regen_pct := float(equip.get("ki_regen_pct", 0.0))
	var final_attack := base_attack + equip_attack
	var final_hp := base_hp + equip_hp
	var final_crit := base_crit + equip_crit
	var final_move_speed := base_move_speed + equip_move_speed
	# 暴击伤害：绝对加（与 player.gd v6 一致）；气力上限 / 回复：绝对加 + 旧 pct 复合
	var final_crit_damage := base_crit_damage + equip_crit_damage_add
	var final_max_ki := (base_ki + equip_max_ki_add) * (1.0 + equip_max_ki_pct)
	var final_ki_regen := (base_ki_regen + equip_ki_regen_add) * (1.0 + equip_ki_regen_pct)
	var power := _calc_battle_power(final_attack, final_hp, final_crit, int(equip.get("item_power", 0)))
	return {
		"base_attack": base_attack,
		"base_hp": base_hp,
		"base_crit_rate": base_crit,
		"base_crit_damage": base_crit_damage,
		"base_ki": base_ki,
		"base_ki_regen": base_ki_regen,
		"equip_attack": equip_attack,
		"equip_hp": equip_hp,
		"equip_crit_rate": equip_crit,
		"equip_move_speed": equip_move_speed,
		"equip_crit_damage_pct": equip_crit_damage_add,  # 字段名保留（UI 模板用），v6 后语义为绝对加
		"equip_max_ki_pct": equip_max_ki_pct,
		"equip_ki_regen_pct": equip_ki_regen_pct,
		"attack": final_attack,
		"hp": final_hp,
		"crit_rate": final_crit,
		"move_speed": final_move_speed,
		"crit_damage": final_crit_damage,
		"max_ki": final_max_ki,
		"ki_regen": final_ki_regen,
		"battle_power": power,
	}


func _calc_battle_power(attack: float, hp: float, crit_rate: float, item_power: int) -> int:
	# 心数制：hp 从 ~100 缩到 ~3-10 颗心，系数从 1.1 提到 20.0 维持战力量级。
	return int(round(attack * 3.2 + hp * 20.0 + crit_rate * 100.0 + float(item_power)))


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

