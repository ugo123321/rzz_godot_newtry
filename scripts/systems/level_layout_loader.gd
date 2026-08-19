extends Node
class_name LevelLayoutLoader

# 关卡编辑器保存的布局读写：res://config/levels/<编号>.json
# 格式：{"number": "3-1", "elements": [{type, col, row, facing}, ...]}
# 模板随项目走 git + 随导出包发行。注意：res:// 仅在「从 Godot 编辑器运行」时可写，
# 导出包内 res:// 只读 —— 编辑器入口已在 settings_popup 用 OS.has_feature("editor") 门控，
# 导出包不暴露编辑器，不会出现「在只读 res:// 上保存」。
# stage→编号 绑定属未来工作（在配置表里指定每关用哪个编号），battle._apply_level_layout 通过编号读取本文件。

const LEVELS_DIR := "res://config/levels"

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


# 删除已保存的布局文件。返回 {"ok", "path", "error"}。
static func delete_layout(number) -> Dictionary:
	var path := _path_for(number)
	var err := DirAccess.remove_absolute(path)
	return {"ok": err == OK, "path": path, "error": err}


# 重命名：以 new_num 保存一份 old_num 的元素副本，再删 old_num。
# new_num 已存在 / old_num 不存在 / 读回失败 / 保存失败 / 删旧失败 → 对应 error，不动旧文件。
static func rename_layout(old_num, new_num) -> Dictionary:
	var old_path := _path_for(old_num)
	var new_path := _path_for(new_num)
	if not FileAccess.file_exists(old_path):
		return {"ok": false, "error": "not_found"}
	if FileAccess.file_exists(new_path):
		return {"ok": false, "error": "exists"}
	var layout := load_layout(old_num)
	if layout.is_empty():
		return {"ok": false, "error": "empty_load"}
	# save_layout 内部 data["number"] 用传入的 new_num，避免文件内容仍指旧编号
	var saved := save_layout(new_num, layout.get("elements", []))
	if not saved.get("ok", false):
		return {"ok": false, "error": "save_failed"}
	var rm := delete_layout(old_num)
	if not rm.get("ok", false):
		return {"ok": false, "error": "delete_old_failed"}
	return {"ok": true, "new_path": new_path}
