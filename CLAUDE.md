# CLAUDE.md — rewards_v6_compact 工作硬约束

本项目 `tools/build_rewards_v6_compact.py` 生成 `config/excel/rewards_v6_compact.xlsx`（给程序员评审的奖励配置表）。改这份生成器时，**以下规则不可违反**——下次大重构 / 全表过 plan 时也得严格遵守。

## 一、元素衍生效果**绝对不允许**重复表达

火 → 燃烧 DoT / 冰 → 减速冰冻 / 雷 → 雷链麻痹 / 毒 → 中毒 DoT —— 这 4 大元素的衍生状态效果**只在 Sheet4 `element_effects` 配一次**，框架靠 `applies_<elem>` 布尔列自动应用。

**禁止在以下位置重复写元素衍生效果**：
- elem_fire_bullet / elem_thunder_bullet / elem_poison_bullet / elem_ice_bullet
- sword_flame / sword_thunder / sword_poison / sword_frost
- orb_fire / orb_ice / orb_poison / orb_thunder
- summon_king / summon_god / summon_gorilla / summon_thunder / summon_bear / summon_snake / summon_fire

以上 19 张卡，它们的：
- `special_values` 数组 **绝不能** 出现 chain_targets / slow_pct / slow_sec / burn_atk_per_sec / poison_atk_per_sec / freeze_sec / applies_status flag 等元素衍生字段
- `desc_cn` 描述里 **绝不能** 出现「附加燃烧/雷链/中毒/减速/冰冻」这类元素自带效果的说明（这些是 Sheet4 已写过的）
- 元素信息只通过 `applies_<elem>` 布尔列 + 元素剑/球的 `element` 字段表达

如果策划描述里出现了元素衍生词（如 trail_thunder_field 明写「眩晕」，trail_frost 明写「减速 40%」是 override），那是**非元素自带的额外控制 / override**，才能在 special_values 写覆盖值。判断标准：「这个效果是这个元素本身就会自动给的吗？是 → 不写；不是 → 才写」。

## 二、召唤物默认行为：跟随玩家身后，全是**远程**攻击

7 张召唤单位卡（summon_king/god/gorilla/thunder/bear/snake/fire）的 mechanic 字段：
- **只允许** 用 `ranged_single` / `ranged_aoe` / `ranged_taunt` / `random_aoe` 这 4 个值之一
- **禁止** 使用 `single_target` / `melee_*` / `single_slow` / `single_dot` 等可能让人误读为近战或带状态后缀的命名
- desc_cn 描述里禁止出现「近战」字样；默认所有召唤物都跟随玩家身后远程攻击

## 三、子弹附带元素伤害是**必带**效果，不是概率触发

4 张元素子弹卡（elem_fire_bullet / elem_thunder_bullet / elem_poison_bullet / elem_ice_bullet）：
- `special_rule` = 0（机制完全由 `applies_<elem>` 布尔列驱动，不需要 dispatcher 写专属代码 — 命中时 `ability_manager.gd:1235 ElementEffectManager.try_apply` 自动应用 Sheet4 元素状态）
- `proc_chance` 列保持空（不要写 0.45 这种概率值）
- desc_cn 描述按 `PER_ID_DESC_OVERRIDE` 字典中的策划版本：「子弹附 X 普攻触发 X 效果」，**不要**写「N% 概率」「+X%/级」这类伪概率文本
- `special_values` 保持空 `[]`
- applies_<elem> 布尔列 = 1（这是触发 Sheet4 元素状态的唯一开关）

## 四、`desc_cn` 描述以 `PER_ID_DESC_OVERRIDE` 字典为准

策划手编的描述全部硬编码在 `tools/build_rewards_v6_compact.py:618 PER_ID_DESC_OVERRIDE` 字典里。生成器读源表 `ys构思_v6.xlsx` 后，**必须**通过该字典把策划改过的描述覆盖回去 — 不要保留源表里旧的「2.5×ATK 雷链 ×3 目标」「45% 概率」这种含元素衍生 / 含概率的旧文案。

下次要改某张卡的 desc：直接编辑 `PER_ID_DESC_OVERRIDE[rid]` 即可，然后重跑 `python tools/build_rewards_v6_compact.py` + `python tools/export_rewards_v6_compact_json.py`。

## 五、不要在大重构时回退已修过的内容

每次「全表重过 plan」前，**先**读这份 CLAUDE.md + 上一轮的 git diff，把已经修过的地方列在 plan 的「禁触清单」里，写明「这次 plan 不允许修改的卡和列」。否则模型容易凭"自然印象"重新把元素衍生效果、概率值等填回去。

## 六、什么时候 `special_rule` 应该是 0

`special_rule != 0` 的含义是**这张卡需要 GDScript 写专属机制**，单纯有触发条件 / 单纯属性叠加都**不构成** special_rule。判断准则：

| 情况 | special_rule | 例 |
|---|---|---|
| 效果完全 = `trigger_type` + `trigger_value` + 属性槽数值 | **0** | basic_berserker（hp_below 触发的属性 buff） |
| 体型、移速等通用属性，已有 attr_code | **0** | basic_giant_might 的 size_pct（v7 后） |
| 攻速换攻击 / 攻击换攻速这类纯属性互换 | **0** | bullet_swift_shoot（atk_speed +30%/lv, atk -10%/lv） |
| 需要叠层 / 限时窗口 / iframe / 复活 / 召唤实体 | **非 0** | basic_demon_hunter / basic_wounded / sv_revive / 7 张召唤卡 |
| 需要特殊弹道 / 分裂 / 弹射 / 镜像 / 穿障碍 | **非 0** | bullet_split / bullet_bounce / trail_pierce |
| 需要场域 / 印记 / 球生成调度等框架配合 | **非 0** | trail_fire_wall / orb_tide / sword_rage |

**HP 阈值触发常驻属性 ≠ special_rule** —— `trigger_type=hp_below + trigger_value` 已经完整表达了，sr=0。

设计新卡时如果一开始想标 sr!=0，先问：能否仅靠 trigger + 属性槽表达？能 → sr=0。

## 七、属性槽现在是 4 个；sr 与属性槽**独立判断**

`PER_ID_ATTRS` 每张卡最多 4 个 `(en_key, base, per_lv)` 元组（v7 扩展）。

- 属性数与 sr 选择**独立判断**：能用属性槽表达的尽量走属性槽（最多 4 个），但 **sr=0 vs sr≠0 仍按第六条机制需求来定** — 不是"属性槽满了的退路"。
- 例：7 张召唤卡只有 1-2 个属性槽但 sr=45（因为需要 spawn 实体）；bullet_swift_shoot 有 2 个属性但 sr=0（纯属性互换无机制）。
- 真正属性 ≥ 5 且无专属机制的情况极少见 — 优先考虑能否合并到 4 个内。

**sr 数字含义清单**：见 `tools/build_rewards_v6_compact.py:138 SPECIAL_RULE_CODES`（每条 sr 的 schema 和数值含义）+ `scripts/core/special_rule_dispatcher.gd:24 IMPLEMENTED_SR`（已实现的 sr code 集合）。

## 八、`per_lv × max_level` 的上限是冗余信息，不写

某属性「+10%/级」配上「max_level=4」，最大就是 +40%。这是**框架自动算出来的**，描述里的「（最 +40%）」、special_values 里的 `[per_lv, max]` 第二位都是冗余：
- desc_cn 中不能出现 `（最 +X%）` / `（最 +XX%）` / `（max N）` 这类括号注释（build_row 自动 regex 清除）
- special_values 中不能出现「等于 per_lv × max_level」的 max 字段
- 写在 SPECIAL_RULE_CODES 的 schema 中也不要列 `XX_max` / `XX_pct_max` / `max_bounces` 这种字段

例外：上限不是 per_lv × max_level，而是独立游戏机制（如 basic_demon_hunter 的 max_stacks=5 = 击杀叠层上限、bullet_split 的 count=3 = 命中分裂数）才保留。

判断准则：「这个 max 是不是等于 per_lv × max_level？是 → 删；不是 → 留」。

## 九、新增召唤物 / 技能视觉走"豪火球术配方"数据驱动

参考 `ability_manager.gd:1597 _draw_pixel_fireball` + `:1585 _fireball_block_color` 这套"自定义像素 + 多色分层 + 周期闪烁 + 外发光圆晕 + 命中爆"配方。**禁止**用 5~10 行 `draw_circle` / `draw_colored_polygon` 拼几何图形了事。

7 张召唤物的统一接口在 `summon_ability_manager.gd:SUMMON_DRAW_DATA` 字典 + 4 个数据驱动函数（`_summon_color` / `_draw_summon_grid` / `_draw_pixel_summon_body` / `_draw_pixel_summon_projectile` / `_summon_hit_burst`）。新增召唤物只需在 `SUMMON_DRAW_DATA` 加一份配置（body_grid / rock_grid / palette / glow / flicker_ms / hit_*），不需要写新函数。

新增**非召唤物**技能视觉（combo_*、orb_*、sword_*、trail_*、bullet_*）：照 `_draw_pixel_fireball` 同款写法 — 自定义 `_draw_pixel_<name>(canvas, world_pos, rot, life_t)`，调色板 4-5 档（最深→核心高光），闪烁周期 50-150ms（视觉冲击力越强、周期越短），外发光圆晕 + 命中粒子 + 屏幕抖。

## 十、主题关专属奖励池（恶魔 / 天使）

每 4 关（stage idx 3/7/11/15…）会被 `scripts/battle.gd:778 get_stage_theme` 随机分配为 demon 或 angel 主题，并在 `_themed_stage_overrides` 字典里持久化。**完成主题关后弹出对应主题的专属奖励 popup**（不走通用 3 选 1 升级），玩家面对一张随机抽出的同主题卡 + **接受 / 放弃** 二选一。

**池子隔离信号**：所有主题卡都用 `group = 10 (恶魔) | 11 (天使)` + `pool_weight = 0`。`upgrade_manager._build_pool()` 必须按 `pool_weight == 0` 过滤掉这两组，确保主题卡不会出现在普通升级池里。

**风格区分**：恶魔 = 血红色 UI + 全部带「最大生命 -X%」惩罚；天使 = 浅黄圣光色 UI + 无惩罚。恶魔卡 `desc_cn` **必须显式包含「最大生命 -X%」尾巴**（不靠 attr 列默默扣血，玩家必须看见惩罚）。

**新 group code (build_rewards_v6_compact.py `GROUP_CODES`)**：
- 10 = 恶魔（icon: 👹）
- 11 = 天使（icon: 😇）

**新 attr code (build_rewards_v6_compact.py `ATTR_CODES`)**：
- 43 = summon_demon_baby_count_add（恶魔宝宝召唤数）
- 44 = summon_angel_baby_count_add（天使宝宝召唤数）
- 45 = sword_spear_count_add（命运之矛数量）

**新 special_rule (build_rewards_v6_compact.py `SPECIAL_RULE_CODES`)**：
- 46 `scythe_on_slash_end` `[atk_mult, pierce]` — 死神镰刀：on_slash_end 在终点释放贯通投掷物
- 47 `periodic_laser` `[atk_mult_per_tick, tick_interval_sec, element]` — 硫磺火：cd 走 attr 40 / 持续走 attr 41 / 元素状态由 Sheet4 自动应用
- 48 `multi_revive` `[extra_lives, max_hp_after_revive_abs]` — 九命猫：复活后绝对 HP（1 = 1HP，不是百分比）
- 49 `blood_bullet` `[pierce, range_mult]` — 血飞刀：替换普攻；攻速/攻击调整走 attr 1 / attr 2
- 50 `proximity_slow` `[aura_radius_px, max_slow_pct]` — 无下限术式：近距离怪物按距离线性减速

**sr=45 mechanic 枚举扩展**：原 `ranged_single/ranged_aoe/ranged_taunt/random_aoe` 追加 `ranged_laser`（持续穿透激光，用于恶魔宝宝 demon_baby）。

**圣盾去重**：原 `sv_holy_guard`（神圣守护，sr=6，每关 1 层挡致死护盾）效果与策划版圣盾完全一致 → 直接复用，仅在源表 `ys构思_v6.xlsx` 把它的 `name_cn`/`group`/`pool_weight` 改成 圣盾 / 天使 / 0，不新建第二张同效果卡。

## 十一、`pool_weight = 0` 是"不入常规升级池"的**唯一开关**

「这张卡参不参加 `upgrade_manager._build_pool()` 的常规随机？」只看 `pool_weight`：

- `pool_weight == 0` → 不入池
- `pool_weight > 0` → 入池，且作为权重参与加权随机

**禁止**在 `upgrade_manager.gd` 里按 group 名 / id 前缀写硬编码黑名单（之前 "强化球" 用过这种方式，已删）。

### 配置源是 `rewards_v6_compact.xlsx`，不是 `ys构思_v6.xlsx`

历史流程是：
```
ys构思_v6.xlsx  ──build_rewards_v6_compact.py──▶  rewards_v6_compact.xlsx  ──export_*.py──▶  rewards_v6.json
```
**`ys构思_v6.xlsx` 只是历史源，已停用**。游戏运行时实际读 `config/json/rewards_v6.json`，json 从 `config/excel/rewards_v6_compact.xlsx` 直接 export 生成。

日常改奖励数值/desc/pool_weight：
1. **直接编辑 `config/excel/rewards_v6_compact.xlsx`**
2. 跑 `python tools/export_rewards_v6_compact_json.py` 重生 json
3. **不要跑 `build_rewards_v6_compact.py`** — 它会从 `ys构思_v6.xlsx` 重生 compact，覆盖你的策划手编值

`build_rewards_v6_compact.py` 仅在需要从 ys 构思源表完整重建 compact 时使用（罕见，且需要先把策划手编值同步回 ys 构思 / 工具的 `PER_ID_*` 字典）。

### 工具级硬规则（在 build_rewards 里强制 pool_weight=0）

只有"整组卡永远不入常规池"的规则放在生成器里。当前只剩两组：

- group code 6（强化球 orb_*）—— 系统暂未启用
- group code 10、11（恶魔 / 天使主题关）—— 只走主题专属弹窗

见 `tools/build_rewards_v6_compact.py:FORCE_NOT_IN_POOL_GROUP_CODES`。

个别基础卡（神速 / 四叶草 / 运气 / 负伤战士 / 移动加速 / 战士之息）的 `pool_weight=0` 由 compact.xlsx 自身控制 — **不在生成器里硬编码**，避免重跑 build_rewards 时覆盖策划改动。

## 十二、玩家面向描述以 `desc_cn_game` 为准，箭头由 `desc_format.gd` 自动渲染

compact.xlsx 末尾的 `desc_cn_game` 列（AI 列，索引 `r[34]`，中文 header "游戏内展示用描述"）是**玩家在升级 / 主题关弹窗里看到的简化文案**，目的是降低阅读压力。

**读取规则**：
- 程序优先读 `desc_cn_game`；为空则回落到 `desc_cn`
- 两个来源都经过 `scripts/utils/desc_format.gd`（`DescFormat.apply_to_rich_text()`）：
  - 正则匹配 `[+-]\d+(\.\d+)?%`（**必须带正负号**，裸百分比如 `50%` 是阈值 / 概率，原样保留）
  - 用 RichTextLabel `add_text` / `add_image` 直接 push，不走 BBCode 解析
  - `+` → 绿 `#5fd96c` ▲ 像素箭头；`-` → 红 `#ef5b5b` ▼ 像素箭头
  - 箭头是运行时用 `Image.set_pixel` 手绘 9×11 瘦实心三角 + 柄、算法外圈加 1px 纯黑描边，缓存为 `ImageTexture`
  - 多个箭头并排时拼到同一张 Image（每个 +1px 间隙），`texture_filter = NEAREST` 保持像素 sharp
  - 显示尺寸 = `base_font_size × 1.4`，嵌入文字基线
  - 档位（按绝对值）：`|n|≤10` → 1 个；`10<|n|≤25` → 2 个；`>25` → 3 个
  - 非百分号数字（`3s` / `×2` / `+1/级`）原样保留
- 两个 popup 的描述 Label 已改成 `RichTextLabel`，居中由 `push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)` 处理

**职责分工**：
- `desc_cn`（F 列）保持"策划手册版"语义 — 咱俩沟通 / plan / commit / 第四条 `PER_ID_DESC_OVERRIDE` 都仍以这一列为准
- `desc_cn_game`（AI 列）只影响玩家视觉，**不影响功能 / 不影响 sr 判定**

**显示路径**：
- `scripts/ui/upgrade_popup.gd` 升级 3 选 1
- `scripts/ui/themed_reward_popup.gd` 主题关弹窗
- 暂停菜单调试列表不显示 desc，不受影响

**风险**：跑 `build_rewards_v6_compact.py` 会清空整列 `desc_cn_game`（同 `pool_weight` 一样，属于生成器视为"策划手编值"而留空的字段）。日常仍按第十一条 — 直接改 compact.xlsx + 跑 export，**不要跑 build_rewards**。


主题关专属弹窗（`get_themed_pool` 按 group 抽）**不看** `pool_weight`，所以主题卡 `pool_weight=0` 不影响主题关本身正常出。

