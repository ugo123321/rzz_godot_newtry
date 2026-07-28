# 迷你千足虫重构 — Design

日期：2026-07-28
分支：server-version

## 背景 / 问题

迷你千足虫（`MINI_CENTIPEDE`）当前是 `scripts/entities/monster.gd` 里的普通怪：

- 外观：`_draw_mini_centipede`（monster.gd:915）画了 ~9 节**渐细**的拖尾分段，靠 `_update_centipede_trail`（:903）记录头部历史位置让节段跟随。
- 行为：跟普通远程怪一样——`monsters.json` 里 `ranged=1`、`attack_pattern="radial"`、`spread_count=8`，走到攻击范围内对玩家打 8 向弹幕（`_perform_attack` :732）。

策划要的是另一种东西：

> 一条由 **12 节尺寸相同的方块**组成的虫。攻击方式 = 从屏幕外随机位置直线飞入、**撞击玩家时不会拐弯**，然后继续直线飞出屏幕外，反复。**每一节都能够受到伤害。**

现实现两个都不对：行为是打弹幕不是冲锋撞击；外观是渐细拖尾不是等大方块。

千足虫 boss（`scripts/entities/centipede_boss.gd` / `scripts/entities/centipede_segment.gd`）正好是「分段 + 每节独立 hitbox + 共享血量」的现成参考：boss 的节段由 `monster_spawner.get_active_monsters()`（spawner.gd:188-196）返回，每节是小圆 hitbox，`take_damage_info` 转发到 boss 的共享 HP 池。本设计照搬这套到小怪上。

## 已确认需求

- **伤害模型**：共享血量·全身可击（任意节命中都扣整条虫的 HP，虫不会变短，HP 归零才死）。
- **虫身**：12 节 × 每节 11px 方块。
- **速度**：中速 ~260 px/s，可反应闪避。
- **撞击**：穿过玩家造成**一次**接触伤害，不停、不拐弯，继续飞出屏幕外。

## 目标

把 `MINI_CENTIPEDE` 从「远程弹幕怪 + 渐细拖尾」改成：

1. 直线冲锋撞击型飞行怪（从屏外飞入 → 撞玩家 → 飞出屏外 → 反复）。
2. 12 节等大方块虫身，全部可被玩家攻击命中（共享血量）。
3. 复用 boss 千足虫的「节段转发共享血量」命中模式，不改引擎其余 ~15 处 `get_hitbox_radius()` 单圆判定。

## 非目标（YAGNI）

- **不做节段独立血量 / 击毁节段使虫变短**（用户选了共享血量模型，虫始终保持 12 节直到死）。
- **不拐弯**：冲锋方向在飞入时就锁定，中途不追玩家、不修正航向（即使玩家走开，虫沿原方向飞出屏外再开下一轮）。
- **不做冲锋预警 telegraph**（中速可闪避，不需要预警条/红框）。
- **不做分体**（不 split）。
- 不改千足虫 boss。
- 不改 `monsters.json` 的 schema 校验脚本（新字段是 json-only 补加列，按记忆 `reference_monsters_config_flow` 走）。

## 架构

### 1. 伤害模型 — 节段转发共享血量

虫 = 一个 `BattleMonster`（头部），持有共享 HP 池（`hp/def/attack` 来自 `monsters.json`，按 stage 缩放，逻辑同现状）。头部纯驱动，**不**作为伤害目标。

12 个子节段节点：新增内部类 `MiniCentipedeSegment extends Node2D`（写在 `monster.gd` 同文件，紧跟 `_draw_mini_centipede` 区块；或独立文件 `scripts/entities/mini_centipede_segment.gd`——见实现计划决定）。每个节段：

- 字段：`worm: BattleMonster`（弱引用）、`segment_index: int`、`alive := true`、`dying := false`（与 `CentipedeSegment` 对齐，召唤物/DoT 系统靠 `bool(m.get("dying"))` 过滤）。
- `get_hitbox_radius() -> float`：返回 `GameConfig.scale_world(SEG_HITBOX)`，`SEG_HITBOX ≈ 6.0`（11px 方块的近似内切圆，让命中手感贴着方块）。
- `is_combat_targetable() -> bool`：`return worm != null and is_instance_valid(worm) and worm.alive and not worm.dying and worm._centi_phase == Phase.CHARGING`。REPOSITION 期间虫在屏外，节段不可击。
- `global_position`：每帧由虫的 `_update_mini_centipede` 直接写入（沿 `dir` 排成直线），节段本身不做移动。
- `take_damage(raw_damage, from_pos)` / `take_damage_info(info, from_pos)`：转发到 `worm._apply_segment_hit(info, self, from_pos)`。
- **元素状态转发**：`ElementEffectManager.try_apply(target, info, player)`（element_effect_manager.gd:31）在命中后对**目标本身**调 `apply_burn_dot_v2` / `apply_freeze_slow` / `apply_poison_dot` / `apply_paralyze`。目标若是节段，这些方法必须转发到虫，否则元素 DoT / 减速 / 麻痹打在虫身上无效。节段因此**显式转发全部 `apply_*` 方法**到虫（签名一一对应）：
  - `apply_burn_dot(duration, dps)` → `worm.apply_burn_dot(...)`
  - `apply_burn_dot_with_snapshot(duration, dps, elem_pct)` → `worm.apply_burn_dot_with_snapshot(...)`
  - `apply_burn_dot_v2(snapshot_atk, elem_pct, proc_freq_pct)` → `worm.apply_burn_dot_v2(...)`
  - `apply_freeze_slow(snapshot_atk, elem_pct, slow_bonus)` → `worm.apply_freeze_slow(...)`
  - `apply_poison_dot(snapshot_atk, elem_pct, proc_freq_pct)` → `worm.apply_poison_dot(...)`
  - `apply_paralyze(duration)` → `worm.apply_paralyze(...)`
  - `apply_petrify(duration)` → `worm.apply_petrify(...)`
  - （虫侧这些方法都已存在，见 monster.gd:403/461/466/472/487/511/524）
- `update_ai`/`update_death`/`die`：空实现（占位，满足 `for m in spawner.monsters: m.update_ai(...)` 之类遍历不报错；与 `CentipedeSegment` 一致）。
- `_draw()`：空（虫身由头部统一绘制，节段隐形，避免重叠绘制）。

虫侧新增 `Phase` 枚举（`REPOSITION` / `CHARGING`）和 `_apply_segment_hit`：

```
func _apply_segment_hit(info: DamageInfo, _seg, from_pos: Vector2) -> Dictionary:
    # 复用现有 _resolve_take_damage（已处理 def/vuln/抗性/stage 缩放/暴击/死亡触发）
    var result := _resolve_take_damage(info, from_pos)
    # _resolve_take_damage 内部 hp<=0 时会 begin_dying 并把 started_dying 置 true
    if bool(result.get("started_dying", false)):
        # 节段是非 BattleMonster，调用方（ability_manager 等）不会替它 emit；
        # 这里由虫自己 emit 一次，保证经验/灵魂球/掉落走 battle._on_monster_killed
        EventBus.monster_killed.emit(self)
    return result
```

注意：现有 `_resolve_take_damage`（monster.gd:418）在 `hp<=0` 时调 `begin_dying` 并返回 `started_dying=true`，但**不**自己 emit `monster_killed`——emit 是各调用方（ability_manager / combat_director 等）在拿到 `started_dying=true` 后做的。那些调用方对**节段**调 `take_damage_info` 拿到 `started_dying=true` 后会 `EventBus.monster_killed.emit(m)`（m 是节段），而 `battle._on_monster_killed` 第 1633 行 `if not (monster is BattleMonster): return` 会直接忽略节段。所以必须在 `_apply_segment_hit` 里由**虫**补一次 emit。同时让节段的 `started_dying` 返回值**保持 true** 是安全的——调用方对节段 emit 的事件被 `_on_monster_killed` 静默丢弃，不会重复发奖。

死亡清理：`begin_dying`（:545）里追加 MINI_CENTIPEDE 分支——把所有节段 `dying=true`（让它们立刻从 `get_active_monsters` 消失）；`_finish_death`（:575）里追加——注销并 `queue_free` 所有节段。spawner 的 `_purge_inactive_monsters`（spawner.gd:138）兜底回收游离节段。

### 2. 移动 — 冲锋状态机

在 `monster.gd` 顶部 MINI_CENTIPEDE 区块（:143）新增状态字段，仿 JUMPER/LASER 的分支写法。

`update_ai`（:584）开头，`_update_status_effects` 之后插入：

```
if kind_id == "MINI_CENTIPEDE":
    _update_mini_centipede(delta, player, battle)
    return   # 跳过导航/普攻/树碰撞——它是飞的
```

`_update_mini_centipede(delta, player, battle)`：

- **REPOSITION**：
  - 倒计时 `_reposition_timer -= delta`；>0 时直接 return（虫在屏外不可见）。
  - ≤0 时开新一轮：随机选边（上/下/左/右），入口点 = 该边屏外 ~80px（用 `logical_width/height`，参考 boss `_build_crawl_path` centipede_boss.gd:110 的边距做法）。
  - `_charge_target = player.global_position`（飞入瞬间锁定玩家位置）。
  - `_charge_dir = (_charge_target - _entry_pos).normalized()`。
  - `_centi_phase = CHARGING`。
  - 头部 `global_position = _entry_pos`。
- **CHARGING**：
  - 受减速状态影响：`var spd := _charge_speed * (1.0 - slow_pct_active)`；雷麻痹 / 石化（`paralyze_timer>0` / `petrify_timer>0`）期间 `spd=0`（静止，但仍可被击）。burn/poison DoT 正常 tick。
  - 头部 `global_position += _charge_dir * spd * delta`。
  - 排节段：`for i in 12: segments[i].global_position = head_pos - _charge_dir * (i+1) * SEG_SPACING`（`SEG_SPACING = 11`，虫身≈132px）。
  - 撞击：若 `_has_hit_this_pass == false` 且头部到玩家距离 ≤ `player.get_effective_radius() + GameConfig.scale_world(6.0)` → `player.take_damage(attack)`（一次，已 stage 缩放）、`_has_hit_this_pass = true`。
  - 飞出判定：头部越过对侧屏边 ~80px（按 `_charge_dir` 分量判断）→ `_has_hit_this_pass = false`、`_centi_phase = REPOSITION`、`_reposition_timer = _reposition_delay`（0.5s）。

生成入场：MINI_CENTIPEDE 跳过 `begin_spawn` 的缩放进场 tween（或调用一个不播 tween 的轻量版），直接 `_centi_phase = REPOSITION`、`_reposition_timer = 0.3`（首轮延迟，避免刷出来秒撞）。`modulate.a = 1.0`、`scale = Vector2.ONE`。

绕过地形/树碰撞：因 `update_ai` 提前 return，不走 `_is_pos_blocked` / 树推力路径（airborne）。

### 3. 视觉 — `_draw_mini_centipede` 重写

头部 `_draw`（:1049）里 `_code_drawn` 分支调 `_draw_mini_centipede`，重写为画 12 个等大方块（替换现有渐细拖尾）：

- 配色保持紫色系：body `#7a5ab0`、edge `#2e1f44`（同现状，不动 monsters.json `color_hex`）。
- 每节：`draw_set_transform(seg_local, _charge_dir.angle(), Vector2.ONE)` → 画 edge 方块（11px）+ 内缩 1.5px 的 body 方块。
- 头节（index 0）加一个白色高光小圆点。
- alpha：受死亡淡出 `modulate.a` 控制（`update_death` 已经在改 `modulate`）。
- HP 条：`_should_show_hp_bar()` 已有；`_draw_hp_bar`（:1027）用 `get_head_top_global_position()`，但精灵隐藏后该函数返回的 `SpriteHelper.get_character_head_top_global` 可能失效——改为用 `global_position + Vector2(0, -hitbox_radius*2)` 作为条锚点（MINI_CENTIPEDE 专用，或在 `get_head_top_global_position` 里给 `_code_drawn` 加分支）。实现计划里定。

### 4. 配置改动

`config/json/monsters.json` 的 `MINI_CENTIPEDE` 条目（:429-461）：

- 改：`ranged: 0`、`attack_pattern: ""`、`projectile_effect: ""`、`spread_count: 0`、`spread_angle_deg: 0`、`bounce_count: 0`、`arrow_speed: 0`、`attack_range: 0`、`can_move: 0`（飞行怪不走通用移动）。
- 新增 json-only 补加列（按记忆 `reference_monsters_config_flow`，不写进 sync 脚本的 header 白名单）：
  - `segment_count: 12`
  - `segment_size: 11`
  - `segment_spacing: 11`
  - `charge_speed: 260`
  - `reposition_delay: 0.5`
  - `segment_hitbox: 6`（节段命中半径，可选；缺省 6）
- 保留不动：`hp: 130`、`def: 4`、`attack: 10`、`attack_interval`、`size: 13`、`speed: 30`（speed 字段对飞行怪无用但保留以免破坏 schema）、`color_hex`、`grade`、`ki_drain_on_hit`、`max_split_tier`、`split_count`、`exp_reward: 4`、`character_folder`、`sprite_prefix`、`projectile_folder`、`sprite_tint_hex`、`elem_resist_poison: 0.3`、`vuln_fire: 0.2`、`name_cn`、`name_en`、`spawn_order`、`unlock_at_stage: 12`。
- `name_en` 保持 `Mini Centipede`（已是英文，无需新增 i18n——这是配置表记录字段，已走 `localize` 读 `name_cn/name_en`）。

`monster.gd` 的 `setup`（:152）读这些新字段到实例变量；缺省值兼容老存档。

回写：跑 `sync_json_to_excel` 把现有列同步回 `monsters.xlsx`（新 json-only 列不回写，符合预期）。

### 5. 接线点清单（实现时逐一确认）

| 文件 | 改动 |
|---|---|
| `scripts/entities/monster.gd` | 新增 `Phase` / 状态字段；`MiniCentipedeSegment` 内部类（或新文件）；`setup` 读新字段；`update_ai` 分支；`_update_mini_centipede`；`_apply_segment_hit`；`begin_dying` / `_finish_death` 清理节段；`_apply_sprite` 已隐藏精灵（:261）保留；`_draw_mini_centipede` 重写；HP 条锚点修正；生成入场跳过 tween |
| `scripts/core/monster_spawner.gd` | `_spawn_monster`（:378）后追加：若 `kind_id=="MINI_CENTIPEDE"`，实例化 12 节段 `add_child` 到 `monster_container` 并 `monsters.append(seg)` |
| `config/json/monsters.json` | 上述字段改动 |
| `config/excel/monsters.xlsx` | `sync_json_to_excel` 回写（仅已有列） |

## 风险 / 已知边界

- **AOE / 穿透类攻击多节命中**：一次 AOE 事件半径覆盖多节时，每节各调一次 `take_damage_info`，虫最多吃 ~12 倍伤害（对 AOE / 穿透 / 雷链脆弱）。**缓解 = 调 HP**（现 130，stage 缩放）。标为 playtest 项；若太极端，后续上「事件级去重」（设计讨论里的方案 C）。
- **雷链在虫自身节段间跳**：`_find_nearest_unvisited`（element_effect_manager.gd:87）会把同虫其他节段当跳目标，观感 OK，伤害叠加同上。
- **`spawner.monsters` 列表膨胀**：每只虫 +12 节段（每关≤2 只 = +24），`get_active_monsters` 遍历成本可忽略；`_pick_spawn_pos` 的「与现有怪距离≥20」判定会多扫 24 个屏外节段，但节段在 REPOSITION 时位于屏外不影响生成点选择。
- **`all_dead()` / `has_pending_death_presentation`**：节段正确上报 `alive/dying`，虫死后节段被 `_finish_death` 注销，不卡关。
- **节段 `global_position` 由虫每帧写入**：节段不进 SceneTree 的 physics，纯被动定位，无冲突。
- **生成位置**：`_pick_spawn_pos` 给虫选的初始位置对飞行怪无意义（虫立刻进 REPOSITION 跳屏外），但 `setup` 仍需要个合法坐标——沿用即可。

## 测试 / 验证

- 进游戏到 unlock_at_stage=12 之后的关（stages.json 里 `mini_centipede` 计数>0 的关，如 stage idx 11+）。
- 观察：虫从屏外直线飞入、撞玩家一次、直线飞出、~0.5s 后换边再来。
- 用普攻/弹幕打虫身任意一节都能扣血（伤害数字弹出），虫身不缩短，HP 归零死亡并掉灵魂球/经验。
- AOE 技能命中多节时观察伤害是否过高（确认风险项的实际倍率）。
- 减速/麻痹/燃烧/中毒状态对虫生效（减速让冲锋变慢、麻痹定身、DoT 扣血）。
- 多只虫同时在场不互相干扰。
- 切中英文，虫名 `Mini Centipede` / `迷你千足虫` 正常（走 `localize`，无需新增 i18n key）。
