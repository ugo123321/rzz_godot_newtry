extends Node
class_name LevelLayoutLoader

# 关卡编辑器保存的布局读写：user://levels/<编号>.json
# 格式：{"number": "3-1", "elements": [{type, col, row, facing}, ...]}
# 这是项目首个 JSON 写盘路径（此前只读 res://config/json/*.json + 写 user://settings.cfg ConfigFile）。
# stage→编号 绑定属未来工作（在配置表里指定每关用哪个编号），battle._apply_level_layout 通过编号读取本文件。

const LEVELS_DIR := "user://levels"

# 编号 → 文件名（统一小写、去掉路径分隔符，避免恶意路径）。
static func _path_for(number) -> String:
	var s := String(number).strip_edges().to_lower()
	s = s.replace("/", "_").replace("\\", "_").replace(":", "_")
	if s.is_empty():
		s = "default"
	return "%s/%s.json" % [LEVELS_DIR, s]


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)


static func save_layout(number, elements: Array) -> Dictionary:
	_ensure_dir()
	var path := _path_for(number)
	var data := {
		"number": String(number),
		"elements": elements,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("LevelLayoutLoader: cannot write %s (err %d)" % [path, FileAccess.get_open_error()])
		return {"ok": false, "path": path, "error": FileAccess.get_open_error()}
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return {"ok": true, "path": path, "count": elements.size()}


# 返回布局 dict；文件缺失/解析失败返回空 dict。
static func load_layout(number) -> Dictionary:
	var path := _path_for(number)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	return parsed


# 列出已保存的编号（文件名 stem），供编辑器"加载已有"用。
static func list_numbers() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(name.substr(0, name.length() - 5))
		name = dir.get_next()
	out.sort()
	return out
