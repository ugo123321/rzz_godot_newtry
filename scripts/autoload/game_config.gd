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
var upgrade_fx: Dictionary = {}
var tuning: Dictionary = {}
var asset_mapping: Array = []
var bosses: Dictionary = {}
var buff_orbs: Dictionary = {}


func _ready() -> void:
	reload()
	_apply_frame_settings() # after reload so target_fps from tuning applies


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
	monsters = {}
	for row in _load_array("monsters"):
		monsters[str(row.get("kind_id", ""))] = row
	player = {}
	for row in _load_array("player"):
		player[str(row.get("key", ""))] = row.get("value")
	upgrades = _load_array("upgrades")
	upgrade_fx = {}
	for row in _load_array("upgrade_fx"):
		upgrade_fx[str(row.get("rarity", "blue"))] = row
	tuning = {}
	for row in _load_array("game_tuning"):
		tuning[str(row.get("key", ""))] = row.get("value")
	asset_mapping = _load_array("asset_mapping")
	bosses = _load_dict("bosses")
	buff_orbs = _load_dict("buff_orbs")


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
	for u in upgrades:
		if str(u.get("id", "")) == id:
			return u
	return {}


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
	var hp_growth := float(get_tuning("stage_hp_growth", 1.2))
	var def_growth := float(get_tuning("stage_def_growth", 1.1))
	var atk_growth := float(get_tuning("stage_atk_growth", 1.12))
	return {
		"hp": pow(hp_growth, stage_index),
		"def": pow(def_growth, stage_index),
		"atk": pow(atk_growth, stage_index),
	}


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
