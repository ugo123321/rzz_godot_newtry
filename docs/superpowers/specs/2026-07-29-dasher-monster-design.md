# 冲刺怪（DASHER）设计文档

日期：2026-07-29
状态：已批准，待写实施计划

## 目标

新增一种怪物「冲刺怪」，外观复用 bat 素材。行为特点：玩家进入其攻击范围后停下蓄力（蓄力时变红），然后锁定方向朝玩家快速冲刺一段固定距离。冲刺命中玩家造成伤害，每轮冲刺只命中一次，命中不停止、继续冲完固定距离。

出现关卡 unlock_at_stage=3，hp 偏低、速度中等，作为中前期机制怪让玩家学习走位躲避。

## 上下文（探索结论）

- 运行时权威源：`config/json/monsters.json`，由 `scripts/autoload/game_config.gd:40-45` 加载到 `monsters` 字典。excel → json 走 `tools/export_config.py`，但运行时只读 json。
- 怪物主脚本：`scripts/entities/monster.gd`（`class_name BattleMonster`）。场景 `scenes/entities/monster.tscn`（Node2D + AnimatedSprite2D，无 Area2D，攻击范围纯距离判定）。
- 主驱动：`update_ai(delta, player, battle)` `monster.gd:626`，由 `battle.gd:2042-2047` 每帧调用。
- 现有特殊怪在 `update_ai` 里按 `kind_id` 硬编码分支（`monster.gd:643-645, 703-708`）。JUMPER / LASER / MINI_CENTIPEDE 各用局部状态字段，无统一 enum 状态机。
- **JUMPER**（`_update_jumper` `monster.gd:802-858`）是「停下→蓄力→攻击」模板：`_jumper_state`(0 idle/1 windup/2 airborne/3 land_recover)，windup 2s 用 `scale` 下沉 + `ANIM_HURT` 当 telegraph。`_jumper_state != 0` 作为定身标志（`monster.gd:653`）。
- **MINI_CENTIPEDE**（`_step_charge` `monster.gd:996-1015`）是「朝目标冲一段距离」模板：`global_position += _charge_dir * _centi_charge_speed * delta * (1-slow)`，撞击判定 `dist <= player.get_effective_radius() + scale_world(6)` → `player.take_damage(attack)` + `_has_hit_this_pass = true`（每轮一次）。扩展字段读取见 `monster.gd:204-210`。
- 变色：`_apply_status_tint` `monster.gd:1291-1314` 每帧按优先级覆盖 `anim_sprite.modulate`。burn 分支（`monster.gd:1300-1302`）`base_tint.lerp(Color(1.0,0.42,0.36,1), 0.42)` 是现成变红参考。**蓄力变色必须加在该函数里，否则每帧被覆盖回 baseline。**
- bat 美术：`assets/Characters/Characters(100x100)/Bat/Bat/` 下有 `Bat.png`、`Bat_Attack01.png`、`Bat_Attack02.png`、`Bat_Death.png`、`Bat_Flying.png`、`Bat_Hurt.png`（下划线命名），以及 `Bat.aseprite` 源文件。`assets/Characters/atlases/json/` 与 `atlases/sheets/` 下无 Bat。现有 strip loader 期望连字符文件名（`effect_helper.gd:666-674`），无法识别 `Bat_Flying.png`。
- 怪物名 i18n：走 monsters.json 的 `name_cn`/`name_en`，`LanguageManager.localize(record, "name")` 自动切换，不进 ui_*.json。
- 玩家 HP 是心数制：受击固定掉 0.5 心，忽略怪物 attack 数值（见 project 记忆 [[project_heart_hp_system]]）。冲刺命中走 `player.take_damage(attack)` 同一通道即可。

## 行为状态机

仿 JUMPER/LASER 三段式 + MINI_CENTIPEDE 冲刺，新增局部状态字段：

```
_dasher_state: int  # 0=IDLE, 1=WINDUP, 2=DASH, 3=RECOVER
_dasher_windup_t: float
_dasher_dash_dist_acc: float   # 本轮已推进距离
_dash_dir: Vector2
_has_hit_this_dash: bool
_dasher_cooldown_t: float      # IDLE 内下次可触发倒计时
```

### IDLE
- 走通用移动朝玩家接近（用现有 `_nav_steer_target` / `_is_pos_blocked`，speed 字段驱动）。
- 每帧检测 `global_position.distance_to(player.global_position) <= _dasher_trigger_range`。
- 触发条件成立且 `_dasher_cooldown_t <= 0` → 进入 WINDUP：重置 windup/dash 累计/hit 标志，锁定方向 `_dash_dir = (player.global_position - global_position).normalized()`。

### WINDUP（蓄力，windup_sec）
- 停止移动（`_dasher_state != 0` → frozen，不走通用移动，仿 `monster.gd:653`）。
- 播放 `ANIM_HURT` 当 telegraph 动作（bat 无 charge 帧，仿 JUMPER:814）。
- 变红由 `_apply_status_tint` 的新 windup 分支处理：`anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.3, 0.3, 1.0), windup_progress)`，`windup_progress = _dasher_windup_t / windup_sec`。
- windup 结束 → 进入 DASH。方向在 windup 结束瞬间**不再重新锁定**（保持 IDLE→WINDUP 时锁定的方向），符合「锁定方向」。

### DASH（冲刺，dash_speed × 累计至 dash_distance）
- `global_position += _dash_dir * _dash_dash_speed * delta`（受 slow/paralyze 影响，仿 `_step_charge:997-1001`：乘 `(1 - slow_pct_active)`，paralyze 期间不推进）。
- 累计 `_dasher_dash_dist_acc += _dasher_dash_speed * delta * (1-slow)`；达 `dash_distance` → 进入 RECOVER。
- 撞击判定（每帧）：`global_position.distance_to(player.global_position) <= player.get_effective_radius() + scale_world(6)` 且 `not _has_hit_this_dash` → `player.take_damage(attack)` + `_has_hit_this_dash = true`。命中不停止冲刺，继续冲完固定距离。

### RECOVER（recover_sec）
- 停在原地，不动不变色（tint 回 baseline）。
- 结束 → 回 IDLE，`_dasher_cooldown_t = cooldown_sec`。

### 通用约束
- 状态受 spawn_lock / paralyze / frozen 状态效果影响同其他怪（`update_ai` 顶部 `_update_status_effects` 仍先跑）。
- 死亡（任何状态）走 `begin_dying` / `_finish_death`，与现有怪一致。

## 代码改动点

### 1. `scripts/entities/monster.gd`
- 新增成员字段（仿 `_jumper_state`/`_laser_state` 在 `:118-141` 的位置）：
  - `_dasher_state := 0`、`_dasher_windup_t := 0.0`、`_dasher_dash_dist_acc := 0.0`、`_dash_dir := Vector2.ZERO`、`_has_hit_this_dash := false`、`_dasher_cooldown_t := 0.0`。
- 新增常量（仿 `JUMPER_TRIGGER_RANGE` `:127`）：本怪数值用 json 扩展字段读，不硬编码常量。
- `setup()`（`:163`）：读 json 扩展字段（仿 `:204-210` 读 centipede 字段）：`_dasher_trigger_range`、`_dasher_windup_sec`、`_dasher_dash_speed`、`_dasher_dash_distance`、`_dasher_recover_sec`、`_dasher_cooldown_sec`。从 `stats` 字典读，缺省给安全默认值。
- `update_ai()`（`:626`）：在 `:643` 附近 kind 分支里加：
  ```
  if kind_id == "DASHER":
      _update_dasher(delta, player, battle)
      return
  ```
- 新增 `_update_dasher(delta, player, battle)`：实现上面四状态机。
- `_apply_status_tint()`（`:1291`）：在优先级链**最高**位置加 windup 分支：
  ```
  if _dasher_state == 1:
      var p = clampf(_dasher_windup_t / maxf(_dasher_windup_sec, 0.001), 0.0, 1.0)
      anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.3, 0.3, 1.0), p)
      return
  ```
  （放在石化/burn/paralyze/poison/slow 之前，确保蓄力红不被状态 tint 覆盖；DASH/RECOVER 状态回落到 baseline 由现有逻辑处理。）
- 撞击判定复用 `_step_charge:1004-1008` 同款距离阈值与 `take_damage` 调用。

### 2. `config/json/monsters.json`
新增条目（字段顺序与现有怪对齐）：
```json
{
  "kind_id": "DASHER",
  "spawn_order": 15,
  "unlock_at_stage": 3,
  "name_cn": "冲刺怪",
  "name_en": "Dasher",
  "hp": 10,
  "def": 0,
  "attack": 1.0,
  "attack_interval": 1.0,
  "size": 8,
  "speed": 70,
  "can_move": 1,
  "ranged": 0,
  "attack_range": 0,
  "color_hex": "#8B0000",
  "character_folder": "Bat",
  "sprite_prefix": "Bat",
  "sprite_tint_hex": "",
  "trigger_range": 180,
  "windup_sec": 0.6,
  "dash_speed": 320,
  "dash_distance": 220,
  "recover_sec": 0.5,
  "cooldown_sec": 1.5,
  "exp_reward": 3,
  "grade": "C"
}
```
- `spawn_order` 取现有最大值 +1（实施时确认现有列表顺序）。
- `attack_range=0`（近战语义；实际触发由 `trigger_range` 扩展字段驱动，不走通用远程/近战 attack 路径，因为 `_update_dasher` 提前 return）。

### 3. `scripts/core/monster_spawner.gd`
- `_spawn_stage_content`（`:163-178`）counts 字典加：`"DASHER": maxi(0, int(stage.get("dasher", 0))),`。
- `_refill_queue_for_infinite`（`:106-121`）counts 字典同样加一行 `"DASHER"`。

### 4. `config/json/stages.json`
给 stage 3 及之后若干关加 `"dasher": N`（小数量，如 1-2）。具体关卡在实施时与现有刷怪节奏对齐。

### 5. `tools/test_new_monsters.gd`
`kinds` 数组加 `"DASHER"`（regression 覆盖）。

### 6. excel 同步
`config/excel/monsters.xlsx` 加对应行，字段与 json 对齐，防止下次跑 `export_config.py` 覆盖丢失。用 excel-mcp 写入。

## bat 美术接入（Aseprite 方式）

目标：让运行时走现有 atlas loader（`effect_helper.gd:_load_character_atlas_frames` `:602`），与其他怪一致。

产物：
- `assets/Characters/atlases/json/Bat.json`（frame rect 描述 + tag→anim 映射）
- `assets/Characters/atlases/sheets/Bat.png`（拼合 sheet）
- tag 命名匹配 `_character_tag_to_anim`（`effect_helper.gd:574-599`）：`idle`、`walk`、`attack`、`hurt`、`death`。

帧来源映射（bat 现有 PNG → tag）：
- `Bat.png` → idle（fallback 兜底，见 `effect_helper.gd:140`）
- `Bat_Flying.png` → walk
- `Bat_Attack01.png`（或 `Bat_Attack02.png`）→ attack
- `Bat_Hurt.png` → hurt
- `Bat_Death.png` → death

主路径：Aseprite CLI 从 `Bat.aseprite` 导出 sheet+json（若本机装了 Aseprite 且 aseprite 文件已有对应 tag）。

兜底路径（不依赖 Aseprite GUI/CLI）：手搓——把上述 PNG 拼成一张 sheet PNG（横排，每帧 100×100），手写 `Bat.json` 描述每个 tag 的 frame rect。运行时走同一 atlas loader，效果一致。

实施时先试 Aseprite CLI，不可用走兜底，不阻塞功能。

## i18n

monsters.json 同条目已填 `name_cn`/`name_en`，`LanguageManager.localize(monster_record, "name")` 自动按语言切换。不新增 ui_*.json key。

## 初始数值（可调）

| 字段 | 值 | 说明 |
|---|---|---|
| hp | 10 | 偏低，中前期怪 |
| speed | 70 | 通用移动速度，中等 |
| attack | 1.0 | take_damage 通道；玩家受击固定 0.5 心 |
| size | 8 | hitbox 半径基数 |
| trigger_range | 180 | 进入即触发蓄力（JUMPER 用 200） |
| windup_sec | 0.6 | 蓄力时长，短于 JUMPER 的 2s，更脆快 |
| dash_speed | 320 | 冲刺速度（centipede 260） |
| dash_distance | 220 | 固定冲刺距离 |
| recover_sec | 0.5 | 冲刺后硬直 |
| cooldown_sec | 1.5 | IDLE 内下次触发间隔 |
| exp_reward | 3 | 经验 |
| unlock_at_stage | 3 | 中前期出现 |

## 验证

- 进游戏，stage 3 起，看是否正常刷出冲刺怪（bat 外观、idle/walk 动画正常）。
- 玩家靠近 trigger_range → 怪停下变红 0.6s → 朝触发时玩家方向冲刺一段距离。
- 冲刺路径上撞到玩家掉 0.5 心，每轮冲刺只掉一次。
- 命中后继续冲完距离，然后停 0.5s 恢复，再 1.5s 冷却后可再触发。
- 横向走位可躲（锁定方向不追踪）。
- 切英文，名字显示 "Dasher"。
- `tools/test_new_monsters.gd` regression 通过。

## 禁触清单（本项目硬约束）

- 不改 `ys构思_v6.xlsx` / 不跑 `build_rewards_v6_compact.py`（与本怪无关，但避免误触）。
- 不在 `upgrade_manager.gd` 写 group/前缀黑名单（与本怪无关）。
- 不硬编码裸中文：怪物名走 `name_cn`/`name_en`，UI 文案若新增走 `tr_ui`。
