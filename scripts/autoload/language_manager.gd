extends Node

# 中英文 i18n 管理器
# - UI 文本走 tr_ui(key) 查表（自定义字典，不走 Godot TranslationServer）
# - 卡片/怪/关卡 等记录走 localize(record, base_field)（读 record["<base>_en"] 或 ["<base>_cn"]）
# - 切换语言后 emit EventBus.language_changed，UI 监听后 _apply_texts 重渲染

const SETTINGS_PATH := "user://settings.cfg"
const I18N_DIR := "res://config/i18n/"
const SUPPORTED := ["zh_CN", "en"]
const DEFAULT_LANG := "zh_CN"

var current_lang: String = DEFAULT_LANG
var _ui_tables: Dictionary = {}  # {"zh_CN": {key: text}, "en": {key: text}}


func _ready() -> void:
	_load_tables()
	_load_settings()


func _load_tables() -> void:
	_ui_tables.clear()
	for lang in SUPPORTED:
		var path := "%sui_%s.json" % [I18N_DIR, lang]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("LanguageManager: missing i18n file %s" % path)
			_ui_tables[lang] = {}
			continue
		var raw := f.get_as_text()
		f.close()
		var data = JSON.parse_string(raw)
		_ui_tables[lang] = data if data is Dictionary else {}


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	var saved := str(cfg.get_value("i18n", "language", DEFAULT_LANG))
	if saved in SUPPORTED:
		current_lang = saved


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其它字段
	cfg.set_value("i18n", "language", current_lang)
	cfg.save(SETTINGS_PATH)


## 查 UI 字典；缺 key 时回落 zh_CN，再缺时返回 [key] 占位（开发期一眼可见漏 key）
func tr_ui(key: String, default := "") -> String:
	var t = _ui_tables.get(current_lang, {})
	if t.has(key):
		return str(t[key])
	if current_lang != DEFAULT_LANG:
		var fb = _ui_tables.get(DEFAULT_LANG, {})
		if fb.has(key):
			return str(fb[key])
	if default != "":
		return default
	return "[%s]" % key


## 卡片字段对称命名（name_cn / name_en、desc_cn / desc_en）
func localize(record: Dictionary, base_field: String) -> String:
	var key_en := "%s_en" % base_field
	var key_cn := "%s_cn" % base_field
	if current_lang == "en":
		var v := str(record.get(key_en, ""))
		if v != "":
			return v
	return str(record.get(key_cn, ""))


## 字段命名不对称时用（如 stages.display_name + display_name_en；或 rewards.desc_cn_game + desc_cn_game_en）
func localize_field(record: Dictionary, en_field: String, cn_field: String) -> String:
	if current_lang == "en":
		var v := str(record.get(en_field, ""))
		if v != "":
			return v
	return str(record.get(cn_field, ""))


func set_language(lang: String) -> void:
	if lang == current_lang or not lang in SUPPORTED:
		return
	current_lang = lang
	_save_settings()
	EventBus.language_changed.emit(lang)


func is_en() -> bool:
	return current_lang == "en"
