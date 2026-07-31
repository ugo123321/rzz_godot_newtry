extends Node

const CONFIG_DIR := "res://config/json/"
const BASE_LOGICAL_WIDTH := 390.0
const BASE_LOGICAL_HEIGHT := 700.0
const DEFAULT_LOGICAL_WIDTH := 720.0
const DEFAULT_LOGICAL_HEIGHT := 1280.0

var chapters: Array = []
var stages: Array = []
var monsters: Dictionary = {}
var player: Dictionary = {}
var upgrades: Array = []
var upgrades_by_id: Dictionary = {}
var upgrade_fx: Dictionary = {}
var tuning: Dictionary = {}
var asset_mapping: Array = []
var bosses: Dictionary = {}
var buff_orbs: Dictionary = {}
# 每关 HP 系数累积乘积缓存：_hp_scale_prefix[i] = ∏(stages[0..i].hp_coeff)。
# 第 N 关怪物 HP = base_hp × _hp_scale_prefix[N]，取代旧 pow(stage_hp_growth, N) 指数曲线。
# 由 stages.xlsx 每关 hp_coeff 列配置驱动（缺省 1.0）。
var _hp_scale_prefix: Array = []
# 技能石系统：config/json/skill_stones.json（rules + affix_display + stones 三段）
var skill_stones_config: Dictionary = {}
var skill_stones_by_id: Dictionary = {}


func _ready() -> void:
	reload()
	_apply_frame_settings() # after reload so target_fps from tuning applies
	PixelUiHelper.install_project_default_font()


func _apply_frame_settings() -> void:
	var fps := int(get_tuning("target_fps", 60))
	if fps > 0:
		Engine.max_fps = fps
		Engine.physics_ticks_per_second = fps
	else:
		Engine.max_fps = 0


func reload() -> void:
	chapters = _load_array("chapters")
	stages = _load_array("stages")
	_rebuild_hp_scales()
	monsters = {}
	for row in _load_array("monsters"):
		monsters[str(row.get("kind_id", ""))] = row
	player = {}
	for row in _load_array("player"):
		player[str(row.get("key", ""))] = row.get("value")
	upgrades = _load_array("rewards_v6")
	upgrades_by_id = {}
	for u in upgrades:
		upgrades_by_id[str(u.get("id", ""))] = u
	upgrade_fx = {}
	for row in _load_array("upgrade_fx"):
		upgrade_fx[str(row.get("rarity", "blue"))] = row
	tuning = {}
	for row in _load_array("game_tuning"):
		tuning[str(row.get("key", ""))] = row.get("value")
	asset_mapping = _load_array("asset_mapping")
	bosses = _load_dict("bosses")
	buff_orbs = _load_dict("buff_orbs")
	skill_stones_config = _load_dict("skill_stones")
	skill_stones_by_id = {}
	for s in skill_stones_config.get("stones", []):
		skill_stones_by_id[str(s.get("skill_id", ""))] = s


func get_tuning(key: String, default_value = null):
	return tuning.get(key, default_value)


func get_logical_size() -> Vector2:
	return Vector2(
		float(get_tuning("logical_width", DEFAULT_LOGICAL_WIDTH)),
		float(get_tuning("logical_height", DEFAULT_LOGICAL_HEIGHT))
	)


func get_world_scale() -> float:
	return maxf(0.1, float(get_tuning("world_scale", 1.0)))


func get_ui_scale() -> float:
	return maxf(0.1, float(get_tuning("ui_scale", 1.0)))


func get_resolution_scale() -> float:
	var logical := get_logical_size()
	var sx := logical.x / BASE_LOGICAL_WIDTH
	var sy := logical.y / BASE_LOGICAL_HEIGHT
	return maxf(0.1, minf(sx, sy))


## UI 布局比例：以当前 logical 相对设计分辨率 (720x1280) 缩放，避免改分辨率后界面被二次放大。
func get_ui_layout_scale() -> float:
	var logical := get_logical_size()
	var sx := logical.x / DEFAULT_LOGICAL_WIDTH
	var sy := logical.y / DEFAULT_LOGICAL_HEIGHT
	return maxf(0.1, minf(sx, sy)) * get_ui_scale()


func scale_world(value: float) -> float:
	return value * get_resolution_scale() * get_world_scale()


func scale_ui(value: float) -> float:
	return value * get_ui_layout_scale()


func get_player_value(key: String, default_value = null):
	return player.get(key, default_value)


func get_monster(kind_id: String) -> Dictionary:
	return monsters.get(kind_id, {})


func get_stage(index: int) -> Dictionary:
	if index < 0 or index >= stages.size():
		return {}
	return stages[index]


func get_upgrade(id: String) -> Dictionary:
	return upgrades_by_id.get(id, {})


# ---- 技能石配置 ----
func get_skill_stone_config() -> Dictionary:
	return skill_stones_config

func get_skill_stone_rules() -> Dictionary:
	return skill_stones_config.get("rules", {})

func get_skill_stone_def(skill_id: String) -> Dictionary:
	return skill_stones_by_id.get(skill_id, {})

func get_skill_stone_affix_display() -> Dictionary:
	return skill_stones_config.get("affix_display", {})


## 升级特效是否在怪物图层下方绘制（1=下方，0=上方）。
func upgrade_fx_below_monsters(upgrade_id: String) -> bool:
	return int(get_upgrade(upgrade_id).get("fx_below_monsters", 0)) != 0


## 按 category 筛选升级（如 "auto_bullet" = 普攻子弹系强化）。
func get_upgrades_by_category(category: String) -> Array:
	var result: Array = []
	for u in upgrades:
		if str(u.get("category", "")) == category:
			result.append(u)
	return result


func get_upgrade_fx(rarity: String) -> Dictionary:
	return upgrade_fx.get(rarity, upgrade_fx.get("blue", {}))


func get_chapter_for_stage(stage_index: int) -> Dictionary:
	var stage := get_stage(stage_index)
	var chapter_id := int(stage.get("chapter_id", 1))
	for c in chapters:
		if int(c.get("chapter_id", 0)) == chapter_id:
			return c
	return {}


func stage_stat_scale(stage_index: int) -> Dictionary:
	var def_growth := float(get_tuning("stage_def_growth", 1.1))
	var atk_growth := float(get_tuning("stage_atk_growth", 1.12))
	return {
		"hp": _hp_scale_for(stage_index),
		"def": pow(def_growth, stage_index),
		"atk": pow(atk_growth, stage_index),
	}


# 由 stages 每关 hp_coeff 累积乘积构建：第 i 关系数 = 第 i-1 关系数 × stages[i].hp_coeff。
# stages[0].hp_coeff 应为 1.0（第一关 = 怪物基础 HP）。缺省/非法值回落 1.0。
func _rebuild_hp_scales() -> void:
	_hp_scale_prefix.clear()
	var acc := 1.0
	for i in range(stages.size()):
		var v = stages[i].get("hp_coeff", 1.0)
		var c := 1.0
		if v is float or v is int:
			c = float(v)
		elif v is String and v.is_valid_float():
			c = float(v)
		if c <= 0.0:
			c = 1.0
		acc *= c
		_hp_scale_prefix.append(acc)


# 第 stage_index 关的 HP 系数。缓存为空或越界时回落到旧指数曲线（兜底）。
func _hp_scale_for(stage_index: int) -> float:
	if _hp_scale_prefix.is_empty() or stage_index < 0 or stage_index >= _hp_scale_prefix.size():
		return pow(float(get_tuning("stage_hp_growth", 1.2)), stage_index)
	return float(_hp_scale_prefix[stage_index])


func scaled_monster_stats(kind_id: String, stage_index: int) -> Dictionary:
	var base := get_monster(kind_id).duplicate(true)
	if base.is_empty():
		return {}
	var scale := stage_stat_scale(stage_index)
	base["hp"] = int(round(float(base.get("hp", 1)) * scale.hp))
	base["def"] = int(round(float(base.get("def", 0)) * scale.def))
	base["attack"] = int(round(float(base.get("attack", 1)) * scale.atk))
	var speed_mul := maxf(0.1, float(get_tuning("monster_speed_mul", 1.15)))
	base["speed"] = maxf(1.0, float(base.get("speed", 19)) * speed_mul)
	return base


func character_sprite_dir(folder: String, prefix: String) -> String:
	return "res://assets/Characters/Characters(100x100)/%s/%s" % [folder, prefix]


func _load_array(name: String) -> Array:
	var path := CONFIG_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("Missing config: %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _load_dict(name: String) -> Dictionary:
	var path := CONFIG_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("Missing config: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
