# 怪物 A* 网格寻路 — Design

日期：2026-07-22
分支：server-version

## 背景 / 问题

怪物移动是纯贪心（`scripts/entities/monster.gd:551-584`）：每帧 `dir = 朝玩家方向`，下一步被挡时只试左右两个垂直方向各一步、每帧重选，两边都挡则退到「远离树的推力」脱困（`_escape_dir_from_trees`）。

症状：玩家和怪物之间隔一整堵阻挡地块（pit / blocking_stone / 未解锁 locked_block）时，怪物卡死——垂直方向只看一步会反复横跳；凹角两边都堵直接停；玩家正对墙后时贴墙绕不到尽头。

地块是 40px 网格，`terrain.is_blocking_for_movement(col,row)` 和 `field_elements.has_move_blocking_at(col,row)` 现成。怪物种群小（每簇 5-9 只）。

## 目标

用 Godot 内置 `AStarGrid2D` 在地块网格上为怪物做真寻路，正确绕 U 形墙 / 凹角 / 迷宫布局。

## 非目标（YAGNI）

- 树不纳入 A*：树是动态圆形障碍、可被砍倒，现有 `_is_pos_blocked` 左右滑步能贴树滑过去，足够。树变化不触发 grid rebuild。
- 不做 flow-field / 多目标避让 / 群体分离。
- 不改玩家寻路（`path_input` 那套独立）。
- **不保留 LOS 快捷**：空旷场也走 A* waypoint，不做「直线无遮挡就跳过 A* 直冲玩家」的短路。

## 架构

### 1. 新系统 `MonsterNavigator`（battle 拥有）

新文件 `scripts/systems/monster_navigator.gd`，`extends Node`。持有一个 `AStarGrid2D`。

API：
- `configure(terrain: TerrainBackground, field_elements: FieldElementRegistry) -> void`：缓存引用；读 terrain 行列数初始化 AStarGrid2D 尺寸 + `cell_size = Vector2(40,40)` + `offset = Vector2(20,20)`（格中心对齐 world）。设 `_dirty = true`。
- `rebuild() -> void`：设 `_dirty = true`（懒重建：下次查询前刷新）。
- `_flush_if_dirty() -> void`：dirty 时遍历全部格子 `set_point_solid(cell, _cell_solid(c,r))`；清 dirty。
- `_cell_solid(col, row) -> bool`：越界 → true；否则 `terrain.is_blocking_for_movement(col,row) OR field_elements.has_move_blocking_at(col,row)`。water 非 solid。
- `find_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array`：flush_if_dirty；world→cell；起/终点 solid 或 `get_point_path` 返回空 → 返回空数组；否则把 `get_point_path` 结果原样返回（已是 world 坐标，因 cell_size+offset 配置）。

访问器补充：若 `TerrainBackground` 未暴露行列数，加 `get_rows() -> int` / `get_cols() -> int`。

### 2. battle 侧接线（`scripts/battle.gd`）

- 地形/元素就绪后（`_build_grid` 完成或战斗开始处）：`_navigator = MonsterNavigator.new()`；`add_child(_navigator)`；`_navigator.configure(terrain, field_elements)`。
- 暴露 `get_monster_navigator() -> MonsterNavigator`。
- 调 `_navigator.rebuild()` 的时机（在已有回调点加一行）：
  1. 战斗开始、地形烘焙完成后；
  2. `locked_block` 解锁时；
  3. `arrow_block` 放置 / 移除时；
  4. `blocking_stone` 变动时。
  （树变化不触发。）

### 3. monster 侧移动改造（`scripts/entities/monster.gd`，`update_ai` 内 551-584 段）

新增成员：
- `var _nav_path: PackedVector2Array = PackedVector2Array()` — 缓存路径（world 坐标 waypoint）
- `var _nav_wp_idx: int = 0` — 当前目标 waypoint 下标
- `var _nav_repath_timer: float = 0.0`
- `var _nav_stuck_timer: float = 0.0` — 被挡累计，超阈值强制 repath

常量：`const NAV_REPATH_SEC := 0.30`、`const NAV_WP_REACH_PX := 20.0`（过 `GameConfig.scale_world`）、`const NAV_STUCK_SEC := 0.60`。

新移动逻辑（替换 `dir = to_player.normalized()` 块）：

```
1. _nav_repath_timer -= delta
   触发 repath 条件（任一）：timer <= 0、玩家格变化、_nav_path 为空
     → _nav_path = navigator.find_path_world(global_position, player.global_position)
     → _nav_wp_idx = 0；_nav_repath_timer = NAV_REPATH_SEC
2. 取 steer_target：
     若 _nav_path 为空 → steer_target = player.global_position（回落直冲，交给微碰撞）
     否则：
       while _nav_wp_idx < len 且 distance(global_position, path[_nav_wp_idx]) < reach_px：
         _nav_wp_idx += 1
       若 _nav_wp_idx >= len → steer_target = player.global_position（到末尾收尾）
       否则 → steer_target = path[_nav_wp_idx]
3. dir = (steer_target - global_position).normalized()
   next_pos = global_position + dir * step_len
4. blocked = _is_pos_blocked(battle, next_pos)   # 保留微碰撞（树 + 块体边缘）
   if blocked:
     _nav_stuck_timer += delta
     # 现有左右 perp 滑步 + _escape_dir_from_trees 原样保留
     ...
     if _nav_stuck_timer > NAV_STUCK_SEC:   # 卡住超时强制重算
       _nav_path.clear(); _nav_repath_timer = 0.0
   else:
     _nav_stuck_timer = 0.0
     global_position = next_pos
```

其余（减速 eff_slow、stop_dist、ranged stop、动画播放）逻辑不变。

### 4. 边界

- 玩家格 solid（踩 pit 边沿等）→ A* 返回空 → 回落直冲玩家，微碰撞兜。
- 怪物自身在 solid 格（出生擦边）→ 起点 solid → 路径空 → 回落直冲。
- water 非 solid → A* 穿水寻路，和现有「怪物走水」一致。
- AStarGrid2D 的 `get_point_path` 在起/终点 solid 时返回空数组，已覆盖。

### 5. 平滑

waypoint 是格中心，直线路径上会有 ±20px 锯齿。用「共线 lookahead」平滑：从 `_nav_wp_idx` 起向后看最多 3 个 waypoint，若 `dir_to(path[i+1])` 与 `dir_to(path[i])` 夹角 < ~15°，steer 直接取更远的那个。共线向量点乘判定，不走 LOS / Bresenham（尊重「不保留 LOS 快捷」）。

## 测试 / 验证

- 手摆一堵 blocking_stone 墙横在玩家与怪物之间，验证怪物沿墙绕到尽头再扑玩家，不卡墙。
- U 形墙：怪在 U 口、玩家在 U 底外侧，验证不卡凹角（A* 出口在 U 口两侧）。
- locked_block 未解锁时挡路、解锁后路径刷新。
- 空旷场无阻挡：路径退化为直线 waypoint，行为与现状一致（无停顿、无抖动）。
- 怪物穿水正常。
- 树旁经过：贴树滑过，不绕大圈。
- 多怪同帧 repath 无掉帧（每簇 5-9 只，0.3s 一发 A*）。

## 风险

- AStarGrid2D 自 Godot 4.3 起可用；项目 `.uid` 文件表明 4.4+，可用。若版本不符退到自写 A*（极少可能）。
- `get_point_path` 返回 world 坐标依赖 `cell_size+offset` 配置；需在实现时验证坐标对齐。
- rebuild 时机遗漏某个阻挡元素变动 → 路径陈旧；首版覆盖 locked_block / arrow_block / blocking_stone 三类。
