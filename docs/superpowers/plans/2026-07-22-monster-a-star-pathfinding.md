# 怪物 A* 网格寻路 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让怪物在玩家与自身之间隔有阻挡地块（pit / blocking_stone / 未解锁 locked_block）时，用 A* 网格寻路绕墙，而不是一直顶墙移动。

**Architecture:** 新增 `MonsterNavigator` 系统（battle 拥有，封装 Godot `AStarGrid2D`），在 40px 地块网格上把阻挡格标 solid，提供 `find_path_world(from, to)`。`update_ai` 的移动块从「直接朝玩家」改为「朝当前 waypoint 走 + 微碰撞滑步兜底」。repath 节奏 0.30s / 玩家格变 / 卡住超时。树不入网格，继续由现有 `_is_pos_blocked` 滑步处理。

**Tech Stack:** Godot 4.7（GDScript），内置 `AStarGrid2D`（4.3+）。无 GDScript 单测框架——验证用 headless 语法检查 + 手动 playtest。

**Spec:** `docs/superpowers/specs/2026-07-22-monster-a-star-pathfinding-design.md`

---

## File Structure

- **Create** `scripts/systems/monster_navigator.gd` — `MonsterNavigator`（Node）。持有 `AStarGrid2D`，solid 判定 = `terrain.is_blocking_for_movement(col,row) OR field_elements.has_move_blocking_at(col,row)`。懒重建（dirty 标志）。单一职责：把世界坐标转路径。
- **Modify** `scripts/systems/terrain_background.gd:272-273` 附近 — 加 `get_rows()` / `get_cols()` 公开访问器（navigator 读尺寸用）。其余不动。
- **Modify** `scripts/systems/field_element_registry.gd` — 加 `signal blocking_cells_changed`，在 `register` / `unregister` 末尾 emit（让 battle 把 navigator 标 dirty）。
- **Modify** `scripts/battle.gd` — 拥有 `_navigator`；`get_monster_navigator()` 懒创建+configure；stage 布局就绪后 `_invalidate_nav()`；`_ready` 连接 `field_elements.blocking_cells_changed`。
- **Modify** `scripts/entities/monster.gd` — 加 5 个 `_nav_*` 成员 + 3 个常量；`update_ai` 移动块（551-584 段）改用 `_nav_steer_target()`；新增 `_nav_steer_target()` 辅助。

---

## Task 1: TerrainBackground 暴露行列访问器

**Files:**
- Modify: `scripts/systems/terrain_background.gd`（在 `get_tile` 附近，约 324 行后）

- [ ] **Step 1: 加访问器**

在 `get_tile(col, row)` 函数后面追加：

```gdscript
func get_rows() -> int:
	return _rows


func get_cols() -> int:
	return _cols
```

- [ ] **Step 2: 语法检查**

Run: `cd /d/workspace/rzz_godot_newtry && /d/godot/godot --headless --check-only --quit 2>&1 | tail -5`
Expected: 无新错误（exit 0，可能打印已有的 autoload 警告，忽略）。

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/terrain_background.gd
git commit -m "feat(terrain): 暴露 get_rows/get_cols 供 navigator 读取网格尺寸"
```

---

## Task 2: FieldElementRegistry 加 blocking 变化信号

**Files:**
- Modify: `scripts/systems/field_element_registry.gd`

- [ ] **Step 1: 加信号 + emit**

在 `var _by_cell: Dictionary = {}` 那行（第 11 行）下面加信号声明：

```gdscript
signal blocking_cells_changed  # 注册/注销阻挡格时 emit，供 MonsterNavigator 标 dirty
```

在 `register(...)` 函数末尾（`_by_cell[key] = {...}` 赋值之后）加：

```gdscript
	blocking_cells_changed.emit()
```

在 `unregister(...)` 函数末尾（`_by_cell.erase(...)` 之后）加：

```gdscript
	blocking_cells_changed.emit()
```

在 `clear()` 函数末尾加：

```gdscript
	blocking_cells_changed.emit()
```

- [ ] **Step 2: 语法检查**

Run: `cd /d/workspace/rzz_godot_newtry && /d/godot/godot --headless --check-only --quit 2>&1 | tail -5`
Expected: exit 0。

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/field_element_registry.gd
git commit -m "feat(field_elements): 加 blocking_cells_changed 信号供 navigator 监听"
```

---

## Task 3: 创建 MonsterNavigator 系统

**Files:**
- Create: `scripts/systems/monster_navigator.gd`

- [ ] **Step 1: 写文件**

```gdscript
extends Node
class_name MonsterNavigator

# A* 网格寻路：为怪物在 40px 地块网格上算绕墙路径。
# solid 判定 = terrain.is_blocking_for_movement(col,row) OR field_elements.has_move_blocking_at(col,row)
# water 非 solid（怪物照走水，与现状一致）；树不入网格（由 monster 的微碰撞滑步处理）。
# battle 在 stage 布局就绪后 / field element 注册变化时 mark_dirty()，下次查询懒重建。

const TILE_SIZE := 40  # 与 TerrainBackground.TILE_SIZE 一致

var _astar: AStarGrid2D = null
var _terrain: Node = null        # TerrainBackground
var _field_elements: Node = null  # FieldElementRegistry
var _cols: int = 0
var _rows: int = 0
var _dirty: bool = true


func _ready() -> void:
	_astar = AStarGrid2D.new()
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_astar.offset = Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)  # 路径点 = 格中心 world 坐标
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_astar.jumping_enabled = false  # 不许贴角斜穿两个阻挡格


func configure(terrain: Node, field_elements: Node) -> void:
	_terrain = terrain
	_field_elements = field_elements
	_refresh_size()
	_dirty = true


func _refresh_size() -> void:
	if _terrain == null or not _terrain.has_method("get_rows") or not _terrain.has_method("get_cols"):
		_cols = 0
		_rows = 0
		_astar.region = Rect2i(0, 0, 1, 1)
		return
	_rows = _terrain.get_rows()
	_cols = _terrain.get_cols()
	_astar.region = Rect2i(0, 0, maxi(1, _cols), maxi(1, _rows))


func mark_dirty() -> void:
	_dirty = true


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / float(TILE_SIZE))), int(floor(world_pos.y / float(TILE_SIZE))))


func _cell_solid(col: int, row: int) -> bool:
	if col < 0 or col >= _cols or row < 0 or row >= _rows:
		return true  # 越界当 solid，逼路径留在场内
	if _terrain and _terrain.has_method("is_blocking_for_movement") and _terrain.is_blocking_for_movement(col, row):
		return true
	if _field_elements and _field_elements.has_method("has_move_blocking_at") and _field_elements.has_move_blocking_at(col, row):
		return true
	return false


func _flush_if_dirty() -> void:
	if not _dirty:
		return
	_refresh_size()
	_dirty = false
	for r in range(_rows):
		for c in range(_cols):
			_astar.set_point_solid(Vector2i(c, r), _cell_solid(c, r))


# from_world -> to_world 的世界坐标 waypoint 数组。起点/终点 solid 或无路径 → 空数组（调用方回落直冲玩家）。
func find_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()
	_flush_if_dirty()
	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)
	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return PackedVector2Array()
	if _astar.is_point_solid(from_cell) or _astar.is_point_solid(to_cell):
		return PackedVector2Array()
	return _astar.get_point_path(from_cell, to_cell)
```

- [ ] **Step 2: 生成 .uid + 语法检查**

Run: `cd /d/workspace/rzz_godot_newtry && /d/godot/godot --headless --quit 2>&1 | tail -8`
Expected: Godot 启动会自动为新 class_name 生成 `.uid`；无脚本错误退出。

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/monster_navigator.gd scripts/systems/monster_navigator.gd.uid
git commit -m "feat(navigator): 新增 MonsterNavigator（AStarGrid2D 封装）"
```

---

## Task 4: battle 拥有 + 接线 navigator

**Files:**
- Modify: `scripts/battle.gd`（`const FieldElementRegistryScript` 附近 + `var terrain` 字段附近 + `_ready` + 两个 stage setup 位置）

- [ ] **Step 1: 加 preload 常量 + 字段**

在 `scripts/battle.gd:23`（`const FieldElementRegistryScript = preload(...)` 那行）下面加：

```gdscript
const MonsterNavigatorScript = preload("res://scripts/systems/monster_navigator.gd")
```

在 `var field_elements: Node`（约第 97 行）附近加字段：

```gdscript
var _navigator: Node = null  # MonsterNavigator：怪物 A* 网格寻路（懒创建）
```

- [ ] **Step 2: 加 getter + invalidate 辅助**

在 `is_move_blocked_at(...)` 函数（约第 962 行）后面追加：

```gdscript
func get_monster_navigator() -> Node:
	if _navigator == null:
		_navigator = MonsterNavigatorScript.new()
		add_child(_navigator)
		_navigator.configure(terrain, field_elements)
	return _navigator


func _invalidate_nav() -> void:
	if _navigator != null and _navigator.has_method("mark_dirty"):
		_navigator.mark_dirty()
```

- [ ] **Step 3: _ready 连接 field_elements 信号**

找到 `_ready()`（第 158 行）里 `field_elements = FieldElementRegistryScript.new()` + `add_child(field_elements)`（第 270-271 行）那段，在 `add_child(field_elements)` 后面加：

```gdscript
	if field_elements.has_signal("blocking_cells_changed"):
		field_elements.blocking_cells_changed.connect(_invalidate_nav)
```

- [ ] **Step 4: stage 布局就绪后 invalidate**

找到 pre-populate 路径（约第 422-426 行）：

```gdscript
	if terrain:
		terrain.setup_for_stage(stage_index, _get_safe_zone())
	if water_overlay:
		water_overlay.refresh_from_terrain()
```

在其后（`_sync_background_layer()` 之前或之后均可，保持同函数内）加：

```gdscript
	_invalidate_nav()
```

找到 PLAYING 路径（约第 547-556 行），在 `_apply_stage_layout_if_any(stage_index)`（第 556 行）之后加：

```gdscript
	_invalidate_nav()
```

- [ ] **Step 5: 语法检查**

Run: `cd /d/workspace/rzz_godot_newtry && /d/godot/godot --headless --check-only --quit 2>&1 | tail -5`
Expected: exit 0。

- [ ] **Step 6: Commit**

```bash
git add scripts/battle.gd
git commit -m "feat(battle): 拥有 MonsterNavigator + stage 布局就绪/元素变化时标 dirty"
```

---

## Task 5: monster 用 navigator waypoint 寻路

**Files:**
- Modify: `scripts/entities/monster.gd`（常量区第 6 行后 + 成员区第 40 行后 + `update_ai` 移动块 551-584 + 新增 `_nav_steer_target` 辅助）

- [ ] **Step 1: 加常量**

在 `const MELEE_STOP_PAD := 2.0`（第 6 行）后加：

```gdscript
const NAV_REPATH_SEC := 0.30      # 路径重算间隔
const NAV_WP_REACH_PX := 20.0     # 距 waypoint 小于此值视为抵达（半格）
const NAV_STUCK_SEC := 0.60       # 连续被挡超此时 → 强制 repath
```

- [ ] **Step 2: 加成员变量**

在 `var path_target_hit_count := 0`（第 40 行）后加：

```gdscript
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_wp_idx: int = 0
var _nav_repath_timer: float = 0.0
var _nav_stuck_timer: float = 0.0
var _nav_last_player_cell: Vector2i = Vector2i(-1, -1)
```

- [ ] **Step 3: 替换移动块里 dir 的取法**

在 `update_ai` 内，找到第 560-562 行：

```gdscript
			var dir: Vector2 = to_player.normalized()
			var step_len: float = eff_speed * delta
			var next_pos := global_position + dir * step_len
			var blocked: bool = _is_pos_blocked(battle, next_pos)
```

替换为：

```gdscript
			var step_len: float = eff_speed * delta
			# A* 网格寻路：朝当前 waypoint 走，地块墙由路径绕开；树仍由下方微碰撞滑步兜底。
			# 注意传 scaled delta（battle._process 传 time-scaled delta，慢动作时 repath 节奏也跟着慢）。
			var steer_target := _nav_steer_target(delta, battle, player)
			var to_target: Vector2 = steer_target - global_position
			var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else to_player.normalized()
			var next_pos := global_position + dir * step_len
			var blocked: bool = _is_pos_blocked(battle, next_pos)
```

- [ ] **Step 4: 在 blocked 分支加 stuck 计时 + 强制 repath**

紧接着的 `if blocked:` 块（第 564 行起）。在 `if blocked:` 之后、`# 双向 perp 都试` 注释之前，插入 stuck 累计：

```gdscript
			if blocked:
				_nav_stuck_timer += delta
				if _nav_stuck_timer > NAV_STUCK_SEC:
					_nav_path.clear()
					_nav_repath_timer = 0.0
				# 双向 perp 都试：选可通且更靠近玩家的一边
```

然后在 `else:`（第 583 行 `else: global_position = next_pos`）里补 stuck 清零：

```gdscript
			else:
				_nav_stuck_timer = 0.0
				global_position = next_pos
```

- [ ] **Step 5: 加 `_nav_steer_target` 辅助函数**

在 `_is_pos_blocked`（第 906-913 行）函数后面追加：

```gdscript
# A* waypoint 转向目标：repath 节奏到 / 玩家格变 / 路径空 → 重算；推到首个未抵达 waypoint；
# 共线 lookahead 平滑（往后看最多 3 个，方向夹角 < ~15° 取更远）。无路径回落直冲玩家。
func _nav_steer_target(delta: float, battle: Node, player: BattlePlayer) -> Vector2:
	if player == null:
		return global_position
	if battle == null or not battle.has_method("get_monster_navigator"):
		return player.global_position
	var nav = battle.get_monster_navigator()
	if nav == null:
		return player.global_position
	_nav_repath_timer -= delta
	var pcell: Vector2i = nav.world_to_cell(player.global_position)
	if _nav_repath_timer <= 0.0 or _nav_path.is_empty() or pcell != _nav_last_player_cell:
		_nav_path = nav.find_path_world(global_position, player.global_position)
		_nav_wp_idx = 0
		_nav_repath_timer = NAV_REPATH_SEC
		_nav_last_player_cell = pcell
	var reach_px: float = GameConfig.scale_world(NAV_WP_REACH_PX)
	while _nav_wp_idx < _nav_path.size() and global_position.distance_to(_nav_path[_nav_wp_idx]) < reach_px:
		_nav_wp_idx += 1
	if _nav_wp_idx >= _nav_path.size():
		return player.global_position
	var target: Vector2 = _nav_path[_nav_wp_idx]
	var base_dir: Vector2 = (target - global_position).normalized()
	var lim: int = mini(_nav_wp_idx + 4, _nav_path.size())
	for i in range(_nav_wp_idx + 1, lim):
		var cand: Vector2 = _nav_path[i]
		var cand_dir: Vector2 = (cand - global_position).normalized()
		if base_dir.dot(cand_dir) > 0.966:  # cos15° ≈ 0.966
			target = cand
		else:
			break
	return target
```

- [ ] **Step 6: 语法检查**

Run: `cd /d/workspace/rzz_godot_newtry && /d/godot/godot --headless --check-only --quit 2>&1 | tail -5`
Expected: exit 0。

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/monster.gd
git commit -m "feat(monster): 移动改用 A* waypoint 寻路 + 共线平滑 + 卡住强制 repath"
```

---

## Task 6: 手动 playtest 验证

**Files:** 无（运行游戏观察）

> 项目无 GDScript 单测框架；以下为 spec §「测试 / 验证」的 playtest 检查点。用关卡编辑器摆布局触发场景。

- [ ] **Step 1: 启动游戏**

Run（编辑器内运行，或 MCP）: 用 `mcp__godot__run_project` 以 `projectPath = D:\workspace\rzz_godot_newtry` 启动；或手动在编辑器按 F5。
Expected: 正常进入第一关，无脚本错误中断。

- [ ] **Step 2: 空旷场无阻挡**

进任意无阻挡的关，观察怪物直线扑玩家，不停顿、不抖动、不绕大圈。
Expected: 行为与改动前一致（A* 在空旷场返回直线 waypoint，共线平滑后等同直冲）。

- [ ] **Step 3: 一堵阻挡石墙**

用关卡编辑器在玩家与怪物之间摆一整列 `blocking_stone`（横墙），运行该关。
Expected: 怪物沿墙滑到尽头再折向玩家，**不顶墙不动**。

- [ ] **Step 4: U 形墙 / 凹角**

摆 U 形阻挡石（开口朝怪物，玩家在 U 外侧底），运行。
Expected: 怪物不卡在凹角，从 U 口绕出再扑玩家（A* 出路在 U 口）。

- [ ] **Step 5: locked_block 未解锁→解锁**

摆 locked_block + 钥匙，玩家先无钥匙观察怪物绕行；拿到钥匙解锁后该格变通路。
Expected: 解锁后怪物路径刷新走直线（`blocking_cells_changed` → navigator dirty → 下次查询重建）。

- [ ] **Step 6: 怪物穿水**

摆水地块在路径上。
Expected: 怪物照常穿水（water 非 solid），与现状一致。

- [ ] **Step 7: 树旁经过**

怪朝玩家路径上有树。
Expected: 怪物贴树滑过去（现有 `_is_pos_blocked` 滑步），不绕大圈（树不入 A*）。

- [ ] **Step 8: 多怪不掉帧**

同关 5-9 只怪同帧 repath，观察帧率。
Expected: 无明显掉帧（0.30s/只 A*，网格 ~18×32）。

- [ ] **Step 9: 全部通过后 commit（如有 playtest 中修的小补丁）**

```bash
git add -A
git commit -m "test(monster): A* 寻路 playtest 通过（墙绕行/U 形/解锁/水/树/多怪）"
```

---

## Self-Review Notes

- **Spec coverage**: spec §1 MonsterNavigator → Task 3；§2 battle 接线 → Task 4；§3 monster 改造 → Task 5；§4 边界 → Task 3 的 `find_path_world` solid/越界回落 + Task 5 的 `_nav_path` 空回落；§5 平滑 → Task 5 共线 lookahead；§测试 → Task 6。全覆盖。
- **类型一致**: `world_to_cell` (Task 3) ↔ `nav.world_to_cell` (Task 5)；`find_path_world` (Task 3) ↔ `nav.find_path_world` (Task 5)；`mark_dirty` (Task 3) ↔ `_invalidate_nav`/`get_monster_navigator` (Task 4)；`get_rows/get_cols` (Task 1) ↔ `_refresh_size` (Task 3)；`blocking_cells_changed` (Task 2) ↔ `_ready` connect (Task 4)。命名一致。
- **`delta` 来源**: `update_ai` 由 `battle._process`（line 1758→1876）调用，传入的是 **time-scaled** `scaled_delta`（慢动作 time_scale<1 时 delta 被缩放）。故 `_nav_steer_target(delta, ...)` 接收并复用该 `delta`，不用 `get_process_delta_time()`（后者返回未缩放帧 delta，bullet-time 时 repath 节奏会与移动脱节）。
