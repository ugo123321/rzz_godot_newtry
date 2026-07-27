# 关卡编辑器：已保存关卡管理（载入 / 重命名 / 删除）设计

- 日期：2026-07-27
- 关联代码：`scripts/ui/level_editor.gd`、`scripts/systems/level_layout_loader.gd`
- 入口：主界面 → 设置 → 关卡编辑器 → ☰ 菜单

## 1. 背景与目标

关卡编辑器当前（`scripts/ui/level_editor.gd`）能放置元素/地块、设编号、保存到
`user://levels/<编号>.json`，但保存后**没有**任何回看/管理入口——已写的
`LevelLayoutLoader.list_numbers()` 注释明说"供编辑器'加载已有'用"却无人调用，
也缺 `delete_layout` / `rename_layout`。

目标：在 ☰ 菜单加「管理」入口，弹对话框列出所有已保存关卡，每行提供
**载入（继续编辑）/ 重命名 / 删除** 三项操作。

非目标（YAGNI）：复制、缩略图预览、拖拽排序、关卡内容 JSON 文本编辑。
用户已明确选择"载入+删除+重命名"范围，不做复制。

## 2. 方案选择

采用**方案 A：复用 `ConfirmationDialog` + 可滚动 `VBoxContainer` 行列表**。
理由：与编辑器现有 `_on_options_pressed` / `_open_add_list` 的对话框驱动交互完全一致；
`list_numbers()` / `load_layout()` 已就绪，仅需补 `delete_layout()` + `rename_layout()`；
工作量小、风格统一、关卡数量级（个位数）下无需复杂列表组件。

否决方案 B（自定义全屏面板，工作量大 3-5×，超 YAGNI）和
方案 C（原生 `ItemList` + 底部按钮，行内放不下"元素数"且重命名需另弹对话框）。

## 3. 组件改动

### 3.1 `scripts/systems/level_layout_loader.gd`（新增 2 个 static API）

```gdscript
static func delete_layout(number) -> Dictionary:
    var path := _path_for(number)
    var err := DirAccess.remove_absolute(path)
    # remove_absolute 返回 Error 枚举（OK = 0）
    return {"ok": err == OK, "path": path, "error": err}

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
    # 注意：save_layout 内部 data["number"] 用传入的 new_num，避免文件内容仍指旧编号
    var saved := save_layout(new_num, layout.get("elements", []))
    if not saved.get("ok", false):
        return {"ok": false, "error": "save_failed"}
    var rm := delete_layout(old_num)
    if not rm.get("ok", false):
        return {"ok": false, "error": "delete_old_failed"}
    return {"ok": true, "new_path": new_path}
```

`list_numbers()` / `save_layout()` / `load_layout()` 不动。

### 3.2 `scripts/ui/level_editor.gd`（1 个入口 + 1 个对话框 + 3 个回调）

**入口**：`_on_options_pressed` 的 `VBox` 里，在「保存」按钮下方追加一个
`_make_menu_button(tr_ui("UI_LEVEL_EDITOR_MANAGE"), _open_manage_dialog)`。

**`_open_manage_dialog()`**（照 `_on_options_pressed` 写法）：
- 弹 `ConfirmationDialog`，`title = UI_LEVEL_EDITOR_MANAGE_TITLE`，
  `ok_button_text = UI_LEVEL_EDITOR_CLOSE`（或直接复用 cancel）。
- 内容：一个 `ScrollContainer`（`custom_minimum_size = Vector2(560, 360)`）包
  `VBoxContainer`。
- 调 `LevelLayoutLoader.list_numbers()`：
  - 空数组 → VBox 里放一个居中 `Label`，文本 `UI_LEVEL_EDITOR_MANAGE_EMPTY`。
  - 非空 → 每个编号生成一行 `_make_manage_row(num)`。
- `dlg.confirmed` / `dlg.canceled` 都 `dlg.queue_free()`。
- 用 `_ui_layer.add_child(dlg)` + `popup_centered()`，与现有对话框一致。

**`_make_manage_row(num) -> HBoxContainer`**：
- 先 `load_layout(num)` 读元素数（失败按 0）。
- `Label`：编号（粗体）。
- `Label`：`"%d 个元素" % count`（用 `UI_LEVEL_EDITOR_ELEM_COUNT_FMT` 模板走 i18n）。
- `Button`「载入」→ `_on_load_existing(num)`，`UiStyle.apply_primary_button(_, #5fa060, 8)`。
- `Button`「重命名」→ `_on_rename_existing(num, row)`，配色 `#5a6a90`。
- `Button`「删除」→ `_on_delete_existing(num)`，配色 `#a05050`。
- 全部 `PixelUi.apply_ui_font`。
- 返回的 row HBox 持有原编号作 metadata（`row.set_meta("num", num)`）便于重命名后定位。

**`_on_load_existing(num)`**：
- 若 `_elements` 或 `_tile_overrides` 非空 → 弹 `ConfirmationDialog`，
  `dialog_text = tr_ui("UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT") % num`，
  `ok_button_text = UI_LEVEL_EDITOR_LOAD` / `cancel_button_text = UI_LEVEL_EDITOR_CANCEL`。
  confirmed → 执行载入；canceled → 仅关确认框。
- 载入流程：`_reset_all()`（清元素 + 地块 + 画草地，已存在）→ `_load_layout(num)`
  （已存在，重建 `_tile_overrides` + `_elements`）→ 关管理对话框 →
  toast `UI_LEVEL_EDITOR_LOADED_FMT % [num, count]`。
- 若 `load_layout` 返回空（文件被外部删）：维持 reset 后空草地，toast 报
  `UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT % num`。

**`_on_rename_existing(num, row)`**：
- 把行内 `Label`(编号) 隐藏，插入一个 `LineEdit`（预填 `num`，全选）+ 一个「✓」小按钮。
- ✓ 按下或 LineEdit `text_submitted` → 读 `new_num = text.strip_edges()`：
  - 空 → toast `UI_LEVEL_EDITOR_RENAME_INVALID`，保留编辑态。
  - `new_num == num` → 直接还原行（无操作）。
  - 否则 `rename_layout(num, new_num)`：
    - `ok` → toast `UI_LEVEL_EDITOR_RENAME_DONE_FMT % [num, new_num]` → 关管理对话框 →
      重建对话框刷新列表（`_open_manage_dialog` 再调一次）。
    - `error == "exists"` → toast `UI_LEVEL_EDITOR_RENAME_EXISTS_FMT % new_num`。
    - 其他 error → toast `UI_LEVEL_EDITOR_RENAME_FAILED_FMT`。
- ESC / 失焦 → 还原行（取消重命名）。

**`_on_delete_existing(num)`**：
- 弹 `ConfirmationDialog`，`dialog_text = tr_ui("UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT") % num`，
  `ok_button_text = UI_LEVEL_EDITOR_DELETE` / `cancel_button_text = UI_LEVEL_EDITOR_CANCEL`。
- confirmed → `delete_layout(num)`：
  - `ok` → toast `UI_LEVEL_EDITOR_DELETE_DONE_FMT % num` → 关对话框 → 重建管理对话框刷新。
  - 否则 toast `UI_LEVEL_EDITOR_DELETE_FAILED_FMT`。

### 3.3 i18n（`config/i18n/ui_zh_CN.json` + `ui_en.json`，中英双语）

新增 key（前缀 `UI_LEVEL_EDITOR_*`，模板整句含 `%`）：

| key | zh_CN | en |
|---|---|---|
| `UI_LEVEL_EDITOR_MANAGE` | 管理 | Manage |
| `UI_LEVEL_EDITOR_MANAGE_TITLE` | 已保存关卡 | Saved Levels |
| `UI_LEVEL_EDITOR_MANAGE_EMPTY` | 还没有保存的关卡 | No saved levels yet |
| `UI_LEVEL_EDITOR_ELEM_COUNT_FMT` | %d 个元素 | %d elements |
| `UI_LEVEL_EDITOR_LOAD` | 载入 | Load |
| `UI_LEVEL_EDITOR_RENAME` | 重命名 | Rename |
| `UI_LEVEL_EDITOR_DELETE` | 删除 | Delete |
| `UI_LEVEL_EDITOR_CLOSE` | 关闭 | Close |
| `UI_LEVEL_EDITOR_LOADED_FMT` | 已载入 %s（%d 个元素） | Loaded %s (%d elements) |
| `UI_LEVEL_EDITOR_LOAD_NOT_FOUND_FMT` | 找不到关卡 %s | Level %s not found |
| `UI_LEVEL_EDITOR_LOAD_DISCARD_CONFIRM_FMT` | 载入 %s 会丢弃当前画布上未保存的改动，继续？ | Loading %s discards unsaved canvas changes. Continue? |
| `UI_LEVEL_EDITOR_RENAME_DONE_FMT` | 已重命名 %s → %s | Renamed %s → %s |
| `UI_LEVEL_EDITOR_RENAME_EXISTS_FMT` | 编号 %s 已存在 | Number %s already exists |
| `UI_LEVEL_EDITOR_RENAME_INVALID` | 编号不能为空 | Number cannot be empty |
| `UI_LEVEL_EDITOR_RENAME_FAILED_FMT` | 重命名失败 | Rename failed |
| `UI_LEVEL_EDITOR_DELETE_CONFIRM_FMT` | 确认删除关卡 %s？此操作不可撤销。 | Delete level %s? This cannot be undone. |
| `UI_LEVEL_EDITOR_DELETE_DONE_FMT` | 已删除 %s | Deleted %s |
| `UI_LEVEL_EDITOR_DELETE_FAILED_FMT` | 删除失败 | Delete failed |

`_apply_texts()` 不需要改（管理对话框是按需创建的，创建时直接读 `tr_ui`，
和 `_open_add_list` 一致）。但为保险，`EventBus.language_changed` 期间若管理对话框
还开着，重建一次最简单——可选优化，初版可不做（用户切语言时关掉重开即可）。

## 4. 数据流

```
☰ 菜单 → 管理
  └─ list_numbers() ──▶ VBox 行列表（编号 + 元素数 + 三按钮）
       ├─ 载入 ──▶ [画布非空?] ──▶ 二次确认 ──▶ _reset_all() + _load_layout(num) + toast
       ├─ 重命名 ──▶ 行内 LineEdit + ✓ ──▶ rename_layout(old,new) ──▶ 刷新列表
       └─ 删除 ──▶ 二次确认 ──▶ delete_layout(num) ──▶ 刷新列表
```

磁盘格式不变：`{"number": "...", "elements": [...]}`，仍由 `save_layout` 写。
重命名只换文件名 stem + 内部 `number` 字段，元素数组原样搬运。

## 5. 边界与错误处理

- **空目录 / 首次使用**：`list_numbers()` 返回 `[]`（`DirAccess.open` 失败也返回 `[]`）
  → 显示 `MANAGE_EMPTY`，无行。
- **重命名目标已存在**：`rename_layout` 返回 `error="exists"`，不动旧文件，toast 提示。
- **重命名输入空**：拦在 UI 层，不进 `rename_layout`。
- **载入的文件已被外部删除**：`load_layout` 返回空 dict → `_load_layout` 直接 return
  （画布维持 reset 后空草地）→ toast `LOAD_NOT_FOUND_FMT`。
- **删除失败**（权限 / 文件被占用）：`delete_layout` 返回 `ok=false` → toast `DELETE_FAILED_FMT`，
  不刷新列表。
- **画布非空载入**：必弹丢弃确认，避免静默销毁用户当前未保存编辑。
- **重命名中途关掉管理对话框**：行内 LineEdit 失焦即取消，无脏状态。
- **i18n 缺 key 回落**：`tr_ui` 会回落中文 + `push_warning`，但视觉残留中文是 bug，
  本 spec 列了全部双语 key，提交时两份 JSON 必须同步。

## 6. 遵守 CLAUDE.md 硬约束

- **第十三条 i18n**：所有新增可见文字（按钮、提示、对话框标题）全部走
  `LanguageManager.tr_ui` + 双语 JSON；`.gd` 内禁止裸中文 `.text = "..."`。
- **第十二条 desc_cn_game / desc_format**：本功能不涉及卡牌描述，无影响。
- **第十一条 pool_weight**：本功能不涉及奖励池，无影响。
- 不触碰 rewards / element / summon 等敏感配置流。

## 7. 测试（手动，编辑器无单测框架）

1. 保存 2-3 个不同编号关卡（含不同元素数）→ 打开管理 → 看到对应行数 + 元素数正确。
2. 载入其中一个 → 画布恢复其元素/地块 → 在编辑器里改两笔 → 保存覆盖 → 管理列表里该行元素数更新。
3. 重命名 → 列表刷新出现新编号、旧编号消失；磁盘 `user://levels/` 下文件名变了。
4. 重命名为已存在编号 → toast 报已存在，旧文件不动。
5. 删除 → 二次确认 → 列表刷新；磁盘文件没了。
6. 空目录（清空 `user://levels/`）→ 管理面板显示 `MANAGE_EMPTY`。
7. 切英文 → 全部按钮/提示/对话框英文；切回中文无 `[UI_XXX]` 占位。
8. 载入时画布非空 → 弹丢弃确认；取消则画布不动，管理对话框仍在。
9. 重命名输入空 → toast 报无效，停留在编辑态。
10. 载入不存在的编号（外部删文件后列表未刷新场景不出现，因每次开管理都重新 `list_numbers`；但手动构造：在管理开着时外部删文件再点载入）→ toast 报 `LOAD_NOT_FOUND_FMT`。

## 8. 范围与非目标

- 不做复制（用户已排除）。
- 不做缩略图预览 / 元素清单详情 / 拖拽排序。
- 不做撤销栈（载入即覆盖画布，由"丢弃确认"兜底）。
- 不做"另存为"独立入口——重命名 + 现有保存已覆盖该用法。
- 语言切换时打开的管理对话框不实时刷新（关掉重开即可），属可接受边界。
