# 装备绝对值 + 百分比显示 + 每级成长 改造设计

日期：2026-07-24
范围：全量（显示 + 战斗数值数据驱动）

## 一、背景与目标

`config/excel/equipments.xlsx` 已由策划改版：
- **F 列「实际效果」**：属性加成改为**绝对值**（如「攻击力+5」「生命+0.5」「气力上限+10」「受击无敌时间+0.05」「划线气力消耗-0.01」），并新增了绝对值形态的 `气力上限` / `气力回复速度`、全新的 `受击无敌时间` / `划线气力消耗`。
- 删除了旧的 UI 展示列。
- **G 列「升级每级实际效果」**（新增）：每件装备一份，4 行相同，表示每次升级在白阶属性上叠加的绝对值（如「攻击力+1」）。

目标：
1. 游戏内 UI 文字把绝对值**换算为基础值的百分比**显示，整数、小数点**向上取整（ceil）**，负值用标准 ceil（`ceil(-5.56) = -5`）。
2. 装备信息面板「基础属性」（白阶）行**加上升级效果**：显示值 = `(F白 + G×(level-1)) / base × 100`；蓝/紫/橙行不加升级效果。
3. **数据驱动战斗**：G 列每级效果替换 `lobby_state.gd` 现有硬编码每级加成（+2atk/+0.5hp/+0.01crit）；新绝对值属性（max_ki / ki_regen / invincible_time / ki_per_pixel）接进 `player.gd` 实际生效；`crit_damage` 语义从「pct 乘」改为「绝对加」。

## 二、玩家基础值（换算基准，来自 `config/json/player.json`）

| stat | key | base |
|---|---|---|
| attack | base_attack | 52 |
| max_hp（心数） | base_hp | 3.0 |
| max_ki | base_ki | 234 |
| crit_rate | base_crit_rate | 0.08 |
| crit_damage | base_crit_damage | 1.6 |
| move_speed | move_speed | 60 |
| ki_regen | ki_regen_speed | 60 |
| invincible_time | invincible_time | 0.45 |
| ki_per_pixel | ki_per_pixel | 0.18 |

百分比 = `ceil(绝对值 / base × 100)`，带符号。运行时读 `GameConfig.get_player_value`，不烤进 json（base 改了显示自动同步）。

## 三、8 件装备的 F（白阶绝对值）/ G（每级绝对值）/ 显示%

每件装备 4 行（白/蓝/紫/橙），G 在 4 行相同。下面只列白阶 F、G，以及换算后的显示百分比（ceil）。

| 装备 | 白阶 F（绝对） | G（每级绝对） | 白阶显示% | 每级显示% |
|---|---|---|---|---|
| 铁制短刀 | 攻击力+5 | 攻击力+1 | +10% (9.6→10) | +2%/级 (1.92→2) |
| 轻布甲 | 受击无敌时间+0.05 | 受击无敌时间+0.01 | +12% (11.1→12) | +3%/级 (2.22→3) |
| 硬木鞋 | 暴击率+0.05 | 暴击率+0.01 | +63% (62.5→63) | +13%/级 (12.5→13) |
| 毛绒帽 | 气力上限+10 | 气力上限+2 | +5% (4.27→5) | +1%/级 (0.85→1) |
| 暴风大剑 | 攻击力+10 | 攻击力+1 | +20% (19.2→20) | +2%/级 |
| 轻灵之靴 | 移动速度+10 | 移动速度+2 | +17% (16.7→17) | +4%/级 (3.33→4) |
| 丛林甲 | 气力回复速度+3 | 气力回复速度+0.8 | +5% (5.0) | +2%/级 (1.33→2) |
| 坚固头盔 | 划线气力消耗-0.01 | 划线气力消耗-0.002 | -5% (-5.56→-5) | -1%/级 (-1.11→-1) |

蓝/紫/橙 F（不重复列）：每行 = `ceil(F_tier / base × 100)%`，无 per_level。例如暴风大剑蓝阶「暴击伤害倍率基础值+0.3」→ +19%（0.3/1.6=18.75→19）。

flag 行（橙阶纯机制）：保留原 desc 文案，不换算。

## 四、数据层改造（`tools/export_equipments_json.py`）

重写解析：
- 列映射 A–G；新增读 G 列。
- `EFFECT_PATTERNS` 重写为新文案（去 `基础值` 后缀），值取绝对浮点：
  - `攻击力+(N)` → `attack: N`
  - `生命+(N)` → `max_hp: N`
  - `暴击率+(N)` → `crit_rate: N`（0–1）
  - `暴击伤害倍率基础值+(N)` → `crit_damage: N`（绝对）
  - `移动速度+(N)` → `move_speed: N`
  - `气力上限+(N)` → `max_ki: N`（绝对，**新 key**，旧是 max_ki_pct）
  - `气力回复速度+(N)` → `ki_regen: N`（绝对，**新 key**，旧是 ki_regen_pct）
  - `受击无敌时间+(N)` → `invincible_time: N`（全新）
  - `划线气力消耗+(N)` → `ki_per_pixel: N`（可为负，全新）
  - 4 个 flag 原样
- G 列解析为 `per_level_bonuses`（与 F 同一 stat 集合），存到装备记录顶层（4 行相同，取第一行即可，校验其余一致）。
- json schema：
  - 装备记录新增 `per_level_bonuses: {attack:1}` 等。
  - tier.stat_bonuses 用新 key（`max_ki`/`ki_regen` 替代旧 `max_ki_pct`/`ki_regen_pct`；`crit_damage` 绝对值）。
  - 数值型 tier 不再写 `effect_desc_cn/en`（运行时算）；flag tier 保留 desc。
- 重跑：`python tools/export_equipments_json.py` → 重生 `config/json/equipments.json`。

## 五、状态层改造（`scripts/autoload/lobby_state.gd`）

- `get_item_stat_bonus`（801-852）：
  - `match` 加新 key 绝对累加：`max_ki` / `ki_regen` / `invincible_time` / `ki_per_pixel`。
  - `crit_damage` 分支从 `crit_damage *= (1+val)`（pct 乘）改为 `crit_damage += val`（绝对加）。注意：`get_item_stat_bonus` 当前对 crit_damage 的处理是累加 pct 进 `bonus.crit_damage`，再由 player.gd 乘。改为 bonus.crit_damage 直接累加绝对值，player.gd 也改为绝对加（见六）。
  - **删除** 845-852 硬编码每级（+2atk/+0.5hp/+0.01crit），替换为：
    `for k,v in per_level_bonuses: bonus[k] += v × (level-1)`。
- `get_battle_modifiers`（911-922）：透传新 key（`max_ki`/`ki_regen`/`invincible_time`/`ki_per_pixel`）给 player.gd。
- `get_item_skill_entries`（777-787）+ `_skill_text_for_quality`（790-798）：
  - 改为**计算显示文本**而非直返 raw desc。对每个 tier：
    - 数值型：白阶 = `ceil((F白 + G×(level-1)) / base × 100)`% 文本；非白阶 = `ceil(F_tier / base × 100)`% 文本。
    - flag：保留原 desc。
  - 文案格式走 i18n key（见七），中英双语。
  - 供详情弹窗 + 属性弹窗 active 列表共用，保证两处一致。
- `get_item_power`：不受影响（基于 slot base + level + quality）。

## 六、战斗层改造（`scripts/entities/player.gd`）

`_load_base_stats`（369-404）+ `_rebuild_upgrades`（1430-1463）的 equip 应用段：
- **crit_damage**：`crit_damage += float(equip.crit_damage)`（绝对加）。**删除** 387-389 与 1436-1438 的 `crit_damage += crit_damage * pct` 两处。
- **max_ki**：新增 `base_ki += float(equip.max_ki)`（绝对，与 `talent_max_ki_add` 1459 同层；pct 路径 `equip_max_ki_pct` 保留给 forge/技能石，但装备 json 不再产出 pct）。
- **ki_regen**：新增 `ki_regen_speed += float(equip.ki_regen)`（绝对，在 `ki_regen_mult` 乘之前加，与 1460 talent 同层）。
- **invincible_time**：新增玩家字段 `equip_invincible_time_add`，在受击无敌逻辑处 `invincible_time = base + equip_invincible_time_add`（base 来自 GameConfig）。
- **ki_per_pixel**：新增玩家字段 `equip_ki_per_pixel_add`（负=降消耗），在划线消耗处 `ki_per_pixel = base + equip_ki_per_pixel_add`。
- 受击无敌/划线消耗的读取点需在实现时定位（player.gd 内 `invincible_time` 与 `ki_per_pixel` 的使用处），集中在一处 apply。

## 七、显示层改造（`scripts/ui/equipment_panel.gd`）

- `_refresh_detail_content`（923-976）：行文本现由 `get_item_skill_entries` 返回的 pct 文本（含白阶升级成长）；渲染结构不变（基础属性 / 品质奖励属性 两段、字号、绿色、圆圈规则保持上一轮改动）。
- `_build_active_effect_lines`（1010-1028）：同用 `get_item_skill_entries` 的 pct 文本。
- 不再读 `effect_desc_cn/en` 直显（数值型）。

## 八、i18n（CLAUDE.md 第十三条强制）

新增 stat 显示名 key（`config/i18n/ui_zh_CN.json` + `ui_en.json`，两份都填）：
`UI_EQUIP_STAT_ATTACK / MAX_HP / CRIT_RATE / CRIT_DAMAGE / MOVE_SPEED / MAX_KI / KI_REGEN / INVINCIBLE_TIME / KI_PER_PIXEL`。

文本格式模板 key（带 `%`，整句含占位符，按 CLAUDE.md 规范）：
- 正值：`UI_EQUIP_STAT_PLUS_FMT = "{stat} +{n}%"` / `"{stat} +{n}%"`
- 负值：`UI_EQUIP_STAT_MINUS_FMT = "{stat} {n}%"` / `"{stat} {n}%"`（n 带负号）
- 白阶含每级：白阶文本额外用 `UI_EQUIP_STAT_PLUS_PERLV_FMT = "{stat} +{n}%（每级 +{plv}%）"`（中英），负值同理。

flag 行沿用原 desc（已有或补 i18n）。

## 九、顺手清理（可选，已与用户确认纳入）

- `get_player_preview_attributes`（lobby_state.gd 925-932）stale 默认值对齐 player.json：`base_attack 95→52`、`ki_regen 135→60`。避免预览面板与实战不一致。

## 十、不做的事

- 不动 max level cap（仍无上限）。
- 不动升级金币公式（`30 + level×15 + quality×25`）。
- 不动 flag 机制（tree_x2 / shock_aura / bullet_homing / hit_dodge_5pct）。
- 不动打造关 / 技能石 / 天赋卡 的 pct 路径。

## 十一、验证

1. 跑 `python tools/export_equipments_json.py`，检查 json 新 key 与 per_level_bonuses。
2. 进游戏装备页，点开每件装备，核对白阶显示%（含等级成长）与蓝紫橙显示% 与本设计第三节表一致。
3. 升级一件装备，白阶% 应随等级增长。
4. 装备各件进入战斗，核对攻击/生命/气力/移速/暴击/暴伤/无敌时间/划线消耗 实际生效。
5. 切 English，核对所有 stat 文本无中文残留。

## 十二、风险

- **G 列 stat 与白阶 F 一致（已核对 8 件装备全部一致）**：故白阶显示（含 per_level）与实战白阶贡献完全对得上；蓝/紫/橙行显示 = 该 tier 绝对值（无 per_level），实战中 per_level 只加在 G 的 stat 上（= 白阶 stat），不影响蓝/紫/橙行。若未来 G 与白阶 stat 不一致，白阶显示会与实战脱节，需重新设计显示规则。
- `crit_damage` 语义翻转（pct 乘 → 绝对加）：暴风大剑蓝阶 +0.3 → 实战 1.6→1.9x（旧 1.6×1.1=1.76x）。数值变强，需平衡确认（已与用户确认 +0.3 是 intentional）。
- 百分比运行时算：若 `GameConfig` 在装备页加载时未就绪，需回落到 player.json 默认（设计已含）。
- 白阶升级成长依赖运行时 level，不可预烤进 json（已确认走运行时算）。
