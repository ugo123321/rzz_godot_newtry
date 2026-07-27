# 关卡编辑器管理功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在关卡编辑器 ☰ 菜单加「管理」入口，弹对话框列出所有已保存关卡，每行提供 载入 / 重命名 / 删除 三项操作。

**Architecture:** 复用现有 `LevelLayoutLoader`（补 `delete_layout` / `rename_layout` 两个 static API）+ 编辑器现有 `ConfirmationDialog` + `ScrollContainer`/`VBoxContainer` 对话框写法（参考 `_on_options_pressed` / `_open_add_list`）。所有可见文字走 `LanguageManager.tr_ui` + 双语 JSON（CLAUDE.md 第十三条）。磁盘格式不变。

**Tech Stack:** Godot 4.x / GDScript / 已有 `UiStyle.apply_primary_button` + `PixelUi.apply_ui_font` / i18n JSON。

**测试说明:** 本项目无 GDScript 单测框架（spec §7 明示手动测试）。每个 task 的 "验证" 步骤是在 Godot 编辑器内运行项目、按描述操作、目视确认行为。最终集成测试在 Task 4。

**关联 spec:** `docs/superpowers/specs/2026-07-27-level-editor-management-design.md`

---

## File Structure

- `scripts/systems/level_layout_loader.gd` — 新增 `delete_layout()` / `rename_layout()` 两个 static 函数。`list_numbers()` / `save_layout()` / `load_layout()` / `_path_for()` 不动。
- `config/i18n/ui_zh_CN.json` — 新增 17 个 `UI_LEVEL_EDITOR_*` key（在 `UI_LEVEL_EDITOR_RESET_DONE` 行后插入）。
- `config/i18n/ui_en.json` — 同步新增 17 个英文 key。
- `scripts/ui/level_editor.gd` — `_on_options_pressed` 的 VBox 加一项「管理」按钮；新增 `_open_manage_dialog()` / `_make_manage_row()` / `_on_load_existing()` / `_on_rename_existing()` / `_on_delete_existing()` 五个函数。

---

### Task 1: LevelLayoutLoader 新增 delete_layout / rename_layout

**Files:**
- Modify: `scripts/systems/level_layout_loader.gd`（在文件末尾 `list_numbers()` 之后追加）

- [ ] **Step 1: 在 `level_layout_loader.gd` 末尾（`list_numbers()` 函数之后，文件最后一行 `}` 之后）追加两个 static 函数**

在 `scripts/systems/level_layout_loader.gd` 末尾追加：

```gdscript


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
```

- [ ] **Step 2: 静态自检——在 Godot 编辑器打开项目，确认无解析错误**

Run: 在 Godot 编辑器打开项目 → 切到 `Scripts/systems/level_layout_loader.gd` → 看底部输出面板。
Expected: 无 "Parse Error" / "Identifier not found"；`OK` 是 Godot 内置 Error 枚举的 0 值，可直接用。

- [ ] **Step 3: 集成验证（延后到 Task 4 一起测，这里先 commit）**

Task 4 会通过编辑器管理 UI 端到端调用这两个函数。本 task 不单独跑运行时验证（无测试桩）。

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/level_layout_loader.gd
git commit -m "feat(loader): LevelLayoutLoader 新增 delete_layout / rename_layout"
```

---

### Task 2: i18n 双语 key（zh_CN + en 同步）

**Files:**
- Modify: `config/i18n/ui_zh_CN.json`（在 `UI_LEVEL_EDITOR_RESET_DONE` 行后插入）
- Modify: `config/i18n/ui_en.json`（同位置插入）

- [ ] **Step 1: 在 `config/i18n/ui_zh_CN.json` 第 269 行 `"UI_LEVEL_EDITOR_RESET_DONE": "已清空所有元素",` 之后插入 17 个 key**

把第 269 行
```
	"UI_LEVEL_EDITOR_RESET_DONE": "已清空所有元素",
```
改成
```
	"UI_LEVEL_EDITOR_RESET_DONE": "已清空所有元素",
	"UI_LEVEL_EDITOR_MANAGE": "管理",
	"UI_LEVEL_EDITOR_MANAGE_TITLE": "已保存关卡",
	"UI_LEVEL_EDITOR_MANAGE_EMPTY": "还没有保存的关卡",
	"UI_LEVEL_EDITOR_ELEM_COUNT_FMT": "%d 个元素",
	"UI_LEVEL_EDITOR_LOAD": "载入",
	"UI_LEVEL_EDITOR_RENAME": "重命名",
	"UI_LEVEL_EDITOR_DELETE": "删除",
	"UI_LEVEL_EDITOR_CLOSE": "关闭",
	"UI_LEVEL_EDITOR_LOADED_FMT": "已载入 %s（%d 个元素）",
	"UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT": "找不到关卡 %s",
	"UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT": "载入 %s 会丢弃当前画布上未保存的改动，继续？",
	"UI_LEVEL_EDITOR_RENAME_DONE_FMT": "已重命名 %s → %s",
	"UI_LEVEL_EDITOR_RENAME_EXISTS_FMT": "编号 %s 已存在",
	"UI_LEVEL_EDITOR_RENAME_INVALID": "编号不能为空",
	"UI_LEVEL_EDITOR_RENAME_FAILED_FMT": "重命名失败",
	"UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT": "确认删除关卡 %s？此操作不可撤销。",
	"UI_LEVEL_EDITOR_DELETE_DONE_FMT": "已删除 %s",
	"UI_LEVEL_EDITOR_DELETE_FAILED_FMT": "删除失败",
```

- [ ] **Step 2: 在 `config/i18n/ui_en.json` 第 269 行 `"UI_LEVEL_EDITOR_RESET_DONE": "Cleared all elements",` 之后插入对应 17 个英文 key**

把第 269 行
```
	"UI_LEVEL_EDITOR_RESET_DONE": "Cleared all elements",
```
改成
```
	"UI_LEVEL_EDITOR_RESET_DONE": "Cleared all elements",
	"UI_LEVEL_EDITOR_MANAGE": "Manage",
	"UI_LEVEL_EDITOR_MANAGE_TITLE": "Saved Levels",
	"UI_LEVEL_EDITOR_MANAGE_EMPTY": "No saved levels yet",
	"UI_LEVEL_EDITOR_ELEM_COUNT_FMT": "%d elements",
	"UI_LEVEL_EDITOR_LOAD": "Load",
	"UI_LEVEL_EDITOR_RENAME": "Rename",
	"UI_LEVEL_EDITOR_DELETE": "Delete",
	"UI_LEVEL_EDITOR_CLOSE": "Close",
	"UI_LEVEL_EDITOR_LOADED_FMT": "Loaded %s (%d elements)",
	"UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT": "Level %s not found",
	"UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT": "Loading %s discards unsaved canvas changes. Continue?",
	"UI_LEVEL_EDITOR_RENAME_DONE_FMT": "Renamed %s → %s",
	"UI_LEVEL_EDITOR_RENAME_EXISTS_FMT": "Number %s already exists",
	"UI_LEVEL_EDITOR_RENAME_INVALID": "Number cannot be empty",
	"UI_LEVEL_EDITOR_RENAME_FAILED_FMT": "Rename failed",
	"UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT": "Delete level %s? This cannot be undone.",
	"UI_LEVEL_EDITOR_DELETE_DONE_FMT": "Deleted %s",
	"UI_LEVEL_EDITOR_DELETE_FAILED_FMT": "Delete failed",
```

- [ ] **Step 3: 验证 JSON 合法**

Run: `python -c "import json; json.load(open('config/i18n/ui_zh_CN.json', encoding='utf-8')); json.load(open('config/i18n/ui_en.json', encoding='utf-8')); print('OK')"`
Expected: 输出 `OK`（两个文件都是合法 JSON）。若报错，检查逗号 / 引号。

- [ ] **Step 4: Commit**

```bash
git add config/i18n/ui_zh_CN.json config/i18n/ui_en.json
git commit -m "feat(i18n): 关卡编辑器管理面板新增中英双语 key"
```

---

### Task 3: 编辑器管理 UI（入口 + 对话框 + 三回调）

**Files:**
- Modify: `scripts/ui/level_editor.gd`
  - `_on_options_pressed`：在「保存」按钮行后插入「管理」按钮
  - 文件末尾新增 `_open_manage_dialog` / `_make_manage_row` / `_on_load_existing` / `_on_rename_existing` / `_on_delete_existing` 五个函数

- [ ] **Step 1: 在 `_on_options_pressed` 的 VBox 里、「保存」按钮之后加「管理」按钮**

在 `scripts/ui/level_editor.gd` 的 `_on_options_pressed` 函数内，找到这一行（约 275 行）：
```gdscript
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_SAVE"), _on_save_pressed))
```
在其后插入一行：
```gdscript
	vbox.add_child(_make_menu_button(LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE"), _open_manage_dialog))
```

- [ ] **Step 2: 在 `level_editor.gd` 文件末尾（`_show_toast` 函数之后）追加管理对话框 + 三个回调**

在 `scripts/ui/level_editor.gd` 末尾追加：

```gdscript


# === 管理：列出已保存关卡，每行 载入 / 重命名 / 删除 ===
func _open_manage_dialog() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE_TITLE")
	dlg.dialog_text = ""
	dlg.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CLOSE")
	dlg.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	# 可滚动列表容器
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 360)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	dlg.add_child(scroll)
	var numbers: Array = LevelLayoutLoaderScript.list_numbers()
	if numbers.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_MANAGE_EMPTY")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		PixelUi.apply_ui_font(empty_lbl)
		empty_lbl.add_theme_font_size_override("font_size", 20)
		vbox.add_child(empty_lbl)
	else:
		for num in numbers:
			vbox.add_child(_make_manage_row(String(num)))
	_ui_layer.add_child(dlg)
	dlg.popup_centered()
	# ok / cancel 都只是关对话框
	dlg.confirmed.connect(func():
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)


func _make_manage_row(num: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_meta("num", num)
	# 元素数（读回布局；失败按 0）
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(num)
	var count: int = int(layout.get("elements", []).size()) if not layout.is_empty() else 0
	var name_lbl := Label.new()
	name_lbl.text = num
	name_lbl.custom_minimum_size = Vector2(140, 0)
	name_lbl.add_theme_font_size_override("font_size", 18)
	PixelUi.apply_ui_font(name_lbl)
	row.add_child(name_lbl)
	var cnt_lbl := Label.new()
	cnt_lbl.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_ELEM_COUNT_FMT") % count
	cnt_lbl.custom_minimum_size = Vector2(110, 0)
	cnt_lbl.add_theme_font_size_override("font_size", 16)
	PixelUi.apply_ui_font(cnt_lbl)
	row.add_child(cnt_lbl)
	# 载入
	var load_btn := Button.new()
	load_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
	PixelUi.apply_ui_font(load_btn)
	load_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(load_btn, Color("#5fa060"), 8)
	load_btn.pressed.connect(func(): _on_load_existing(num, row))
	row.add_child(load_btn)
	# 重命名
	var rename_btn := Button.new()
	rename_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME")
	PixelUi.apply_ui_font(rename_btn)
	rename_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(rename_btn, Color("#5a6a90"), 8)
	rename_btn.pressed.connect(func(): _on_rename_existing(num, row))
	row.add_child(rename_btn)
	# 删除
	var del_btn := Button.new()
	del_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	PixelUi.apply_ui_font(del_btn)
	del_btn.add_theme_font_size_override("font_size", 16)
	UiStyle.apply_primary_button(del_btn, Color("#a05050"), 8)
	del_btn.pressed.connect(func(): _on_delete_existing(num, row))
	row.add_child(del_btn)
	return row


# 载入：画布非空先弹丢弃确认 → _reset_all + _load_layout → 关对话框 + toast
func _on_load_existing(num: String, row: HBoxContainer) -> void:
	var has_unsaved: bool = not _elements.is_empty() or not _tile_overrides.is_empty()
	if has_unsaved:
		var confirm := ConfirmationDialog.new()
		confirm.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
		confirm.dialog_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT") % num
		confirm.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD")
		confirm.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
		_ui_layer.add_child(confirm)
		confirm.popup_centered()
		confirm.confirmed.connect(func():
			confirm.queue_free()
			_do_load_existing(num)
		)
		confirm.canceled.connect(confirm.queue_free)
		return
	_do_load_existing(num)


func _do_load_existing(num: String) -> void:
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(num)
	if layout.is_empty():
		_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT") % num)
		return
	_reset_all()
	_load_layout(num)  # 已存在函数，重建 _tile_overrides + _elements
	var count: int = int(layout.get("elements", []).size())
	_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_LOADED_FMT") % [num, count])
	# 关掉管理对话框：找 UI 层里最顶部的 ConfirmationDialog（即管理面板）
	for c in _ui_layer.get_children():
		if c is ConfirmationDialog:
			c.queue_free()


# 重命名：行内把 name_lbl 换成 LineEdit + ✓ → rename_layout → 刷新列表
func _on_rename_existing(num: String, row: HBoxContainer) -> void:
	# 行内 name_lbl 是第 0 个子节点
	var name_lbl: Label = row.get_child(0)
	name_lbl.visible = false
	var edit := LineEdit.new()
	edit.text = num
	edit.editable = true
	edit.select_all()
	edit.custom_minimum_size = Vector2(140, 0)
	PixelUi.apply_ui_font(edit)
	edit.add_theme_font_size_override("font_size", 18)
	row.add_child(edit)
	row.move_child(edit, 0)  # 排在 name_lbl 之前
	edit.grab_focus()
	# ✓ 按钮
	var ok_btn := Button.new()
	ok_btn.text = "✓"
	ok_btn.add_theme_font_size_override("font_size", 18)
	UiStyle.apply_primary_button(ok_btn, Color("#5fa060"), 6)
	PixelUi.apply_ui_font(ok_btn)
	row.add_child(ok_btn)
	var commit := func() -> void:
		var new_num: String = edit.text.strip_edges()
		if new_num.is_empty():
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_INVALID"))
			return
		if new_num == num:
			_restore_rename_row(row, edit, ok_btn, name_lbl)
			return
		var res: Dictionary = LevelLayoutLoaderScript.rename_layout(num, new_num)
		if res.get("ok", false):
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_DONE_FMT") % [num, new_num])
			# 关管理对话框后重建刷新
			for c in _ui_layer.get_children():
				if c is ConfirmationDialog:
					c.queue_free()
			_open_manage_dialog()
		else:
			var err: String = String(res.get("error", ""))
			if err == "exists":
				_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_EXISTS_FMT") % new_num)
			else:
				_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_RENAME_FAILED_FMT"))
	ok_btn.pressed.connect(commit)
	edit.text_submitted.connect(func(_s: String): commit.call())


func _restore_rename_row(row: HBoxContainer, edit: LineEdit, ok_btn: Button, name_lbl: Label) -> void:
	row.remove_child(edit)
	row.remove_child(ok_btn)
	edit.queue_free()
	ok_btn.queue_free()
	name_lbl.visible = true


# 删除：二次确认 → delete_layout → 刷新列表
func _on_delete_existing(num: String, row: HBoxContainer) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.title = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	confirm.dialog_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT") % num
	confirm.ok_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE")
	confirm.cancel_button_text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_CANCEL")
	_ui_layer.add_child(confirm)
	confirm.popup_centered()
	confirm.confirmed.connect(func():
		confirm.queue_free()
		var res: Dictionary = LevelLayoutLoaderScript.delete_layout(num)
		if res.get("ok", false):
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_DONE_FMT") % num)
			for c in _ui_layer.get_children():
				if c is ConfirmationDialog:
					c.queue_free()
			_open_manage_dialog()
		else:
			_show_toast(LanguageManager.tr_ui("UI_LEVEL_EDITOR_DELETE_FAILED_FMT"))
	)
	confirm.canceled.connect(confirm.queue_free)
```

- [ ] **Step 3: 静态自检——Godot 编辑器内确认无解析错误**

Run: 在 Godot 编辑器打开 `scripts/ui/level_editor.gd` → 看底部输出面板。
Expected: 无 "Parse Error"。重点检查：
- `LevelLayoutLoaderScript`（已在文件顶部 `const`，无需新增）
- `Color` / `HBoxContainer` / `LineEdit` / `ScrollContainer` / `ConfirmationDialog` 都是 Godot 内置类型
- `row.set_meta` / `row.get_meta` 是 Object 内置方法
- `move_child` 是 Node 内置方法

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/level_editor.gd
git commit -m "feat(editor): 关卡编辑器加管理面板（载入/重命名/删除已保存关卡）"
```

---

### Task 4: 端到端集成手动测试

**Files:** 无改动，纯运行验证

- [ ] **Step 1: 启动项目，进编辑器，造测试数据**

Run: Godot 编辑器 → F5 运行项目 → 主界面 → 设置 → 关卡编辑器。
- 放几个不同元素 → 编号栏输入 `t1` → 保存 → 清空 → 再放不同数量 → 编号 `t2` → 保存 → 编号 `t3`（空关卡）→ 保存。
Expected: 三次保存都 toast "已保存编号 tN（共 X 个元素）"。

- [ ] **Step 2: 打开管理面板，确认列表正确**

☰ → 管理。
Expected: 弹出 "已保存关卡" 对话框，三行 t1/t2/t3，每行有编号 + "X 个元素" + 载入/重命名/删除 三按钮。元素数与保存时一致。

- [ ] **Step 3: 测载入（含画布非空丢弃确认）**

先在画布上随便放一个元素（让画布非空）→ ☰ → 管理 → 点 t1 的「载入」。
Expected: 弹丢弃确认 "载入 t1 会丢弃当前画布上未保存的改动，继续？"。
- 点取消 → 画布不动，管理对话框还在。
- 再点 t1 载入 → 点确认 → 画布恢复 t1 的元素 → toast "已载入 t1（X 个元素）" → 管理对话框关闭。

- [ ] **Step 4: 测重命名**

☰ → 管理 → 点 t2「重命名」。
Expected: t2 行的编号变成 LineEdit（预填 t2，全选）+ ✓ 按钮。
- 输入 `t2_renamed` → 回车 / 点 ✓ → toast "已重命名 t2 → t2_renamed" → 管理对话框刷新，列表出现 t2_renamed，t2 消失。
- 点 t2_renamed「重命名」→ 输入 `t1`（已存在）→ ✓ → toast "编号 t1 已存在"，旧文件不动，行保持编辑态。
- 点重命名 → 清空 → ✓ → toast "编号不能为空"，保持编辑态。

- [ ] **Step 5: 测删除**

☰ → 管理 → 点 t3「删除」。
Expected: 弹确认 "确认删除关卡 t3？此操作不可撤销。"。
- 点取消 → 不删。
- 再点 t3 删除 → 确认 → toast "已删除 t3" → 列表刷新，t3 消失。

- [ ] **Step 6: 测空目录**

手动清空 `user://levels/`（Windows: `%APPDATA%\Godot\app_userdata\<项目名>\levels\` 删光 json）→ ☰ → 管理。
Expected: 对话框显示居中提示 "还没有保存的关卡" / "No saved levels yet"，无行。

- [ ] **Step 7: 测中英文切换**

☰ 不行（菜单里没语言切换）→ 退出编辑器回主界面 → 暂停菜单 / 设置里切 English → 再进编辑器 → ☰ → Manage。
Expected: 所有按钮 / 提示 / 对话框标题全英文，无中文残留、无 `[UI_XXX]` 占位。切回中文同样无占位。

- [ ] **Step 8: 测试通过 → 最终 commit（若有改动，否则跳过）**

本 task 通常不改代码。若测试中发现 bug 修复了，再 commit；否则无需 commit。

---

## Self-Review 记录

- **Spec 覆盖**：spec §3.1（loader 两 API）→ Task 1；§3.3（i18n 17 key）→ Task 2；§3.2（编辑器入口+对话框+三回调）→ Task 3；§5 边界（空目录/重命名已存在/载入非空确认/删除二次确认/载入不存在）→ 散落在 Task 3 代码 + Task 4 验证；§7 测试 → Task 4。✅ 无遗漏。
- **Placeholder 扫描**：无 TBD/TODO，所有代码块完整。✅
- **类型一致性**：`_on_load_existing(num: String, row)` / `_on_rename_existing(num, row)` / `_on_delete_existing(num, row)` 三处签名一致；`rename_layout(old_num, new_num)` 与 spec §3.1 一致（已避开 `new` 关键字）；`_do_load_existing` / `_restore_rename_row` 是从主回调拆出的辅助函数，签名自洽。✅
