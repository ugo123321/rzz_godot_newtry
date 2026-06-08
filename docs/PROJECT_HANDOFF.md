# 忍者斩 (renzhezhan) — 项目交接文档

> **用途**：新开 Cursor 对话时，让 AI 先读取本文件，即可无缝继续开发。  
> **最后更新**：2026-05-23（UI/输入/连击/特效素材与子弹时间暂停规则）

---

## 1. 项目目标

将前端 HTML5 游戏 **「忍者斩」**（参考项目 `D:\workspace\godot1\cankao`）移植为 **Godot 4.6 + GDScript** 移动端竖屏 Roguelite。

**核心玩法**：气力满 → 在主角白圈内划线 → 子弹时间 → 沿路径冲刺攻击 → 连击结算 → 杀怪升级三选一 → 8 关 + Boss。

**配置驱动**：章节/关卡/怪物/主角/升级/特效 用 **Excel 编辑 → 导出 JSON → 运行时 GameConfig 读取**。

**美术素材**：项目内 `res://assets/` 为**真实目录**（仅含游戏实际用到的素材）。  
**引用素材库**：`D:\workspace\godot1\sucai`（完整素材库，不直接联接进项目）。

> **开发规矩（必守）**：需要新素材时，先到 `D:\workspace\godot1\sucai` 查找，确认路径后**复制**到 `renzhezhan/assets/` 对应位置，并在 `tools/copy_used_assets.py` 的 `USED_PATHS` / `CHARACTERS` 中登记，再执行 `python tools/copy_used_assets.py`。只有 sucai 中确实没有对应资源时，才用程序化绘制或临时占位，并在交接文档中注明。

---

## 2. 目录结构

```
renzhezhan/
├── assets/              游戏实际用到的素材（从 sucai 复制，非 junction）
├── config/
│   ├── excel/           ← 人工编辑（player.xlsx, stages.xlsx, upgrades.xlsx …）
│   └── json/            ← 运行时读取（export_config.py 生成）
├── docs/
│   └── PROJECT_HANDOFF.md   ← 本文件
├── scenes/
│   ├── main.tscn        → battle.tscn
│   ├── battle/battle.tscn
│   └── entities/        player.tscn, monster.tscn
├── scripts/
│   ├── autoload/        game_config.gd, event_bus.gd, audio_manager.gd
│   ├── battle.gd        战斗总控
│   ├── core/            combat, spawner, upgrades, buff_orbs, abilities, summons,
│   │                    particles, blood_stain_manager, ground_effect_manager …
│   ├── entities/        player, monster, centipede_boss …
│   ├── systems/         path_input, terrain_background, grass_system, sakura_system,
│   │                    stage_fail_animator
│   ├── ui/              hud, upgrade_popup, pause_menu, level_overlay, damage_numbers
│   └── utils/           sprite_helper, effect_helper, ui_sprite_helper, pixel_ui_helper
├── tools/
│   ├── export_config.py
│   ├── export_config.bat
│   └── copy_used_assets.py   ← 从 sucai 复制已登记素材到 assets/
└── project.godot
```

**入口**：`res://scenes/main.tscn` → `battle.tscn`  
**逻辑分辨率**：390×700，窗口 780×1400（2× 整数缩放，像素风）

---

## 3. 配置工作流

```bat
# 改 Excel 后执行
D:\workspace\godot1\renzhezhan\tools\export_config.bat

# 首次生成 / 重置 Excel 模板（会覆盖 excel/）
python D:\workspace\godot1\renzhezhan\tools\export_config.py --init-excel
```

| Excel | JSON | 用途 |
|-------|------|------|
| chapters.xlsx | chapters.json | 章节 |
| stages.xlsx | stages.json | 8 关怪物数量、boss_id、splitter 等 |
| monsters.xlsx | monsters.json | 7 种怪 + SPLITTER |
| player.xlsx | player.json | 主角数值、sprite_scale |
| upgrades.xlsx | upgrades.json | 22 个升级 |
| upgrade_fx.xlsx | upgrade_fx.json | 升级弹窗稀有度特效 |
| game_tuning.xlsx | game_tuning.json | 屏宽、zoom、火柱参数 … |

**当前缩放（像素清晰）**：`sprite_scale=2`，`monster_sprite_scale=2`，**`camera_zoom=1`**（正常显示；改大后会整体放大）。缩放请用 **0.5 步进**，camera_zoom 用 **整数**。

**game_tuning**（Excel ↔ JSON，45 项）：除分辨率/缩放/经验/火柱外，还包含 **关卡 intro**（`stage_intro_*`）、**失败动画**（`fail_death_*`）、**过关/失败 UI**（`stage_clear_flash_duration`、`stage_fail_*`）、**连击结算**（`combat_*`）、**草樱地形**（`grass_cluster_max`、`sakura_*`、`terrain_prop_count`）、`monster_spawn_anim`。改 Excel 后执行 `tools\export_config.bat`（或 `python tools/export_config.py`）；脚本会自动 **merge 缺失 key** 到已有 `game_tuning.xlsx`，不覆盖你已改的值。

**火柱示例**：`fire_pillar_radius=60`，`fire_pillar_warning_time=1.1`，`fire_pillar_active_time=0.5`，`fire_pillar_fade_time=0.3`。

---

## 4. 已实现功能 ✅

### 核心战斗
- [x] 划线路径、气力消耗、子弹时间、路径冲刺攻击
- [x] **划线松手攻击**（气力途中耗尽时沿已画路径立即出手）
- [x] **子弹时间路径预览**（将被命中的怪物/Boss 节段黄色高亮）
- [x] 连击顺序结算、暴击、伤害飘字
- [x] **盾牌格挡**（首次命中飘字 0、蓝灰色，不连击）
- [x] 8 关卡流程、关卡 intro（滑入动画 + **樱花飘落/草地**）
- [x] 7 种怪物 AI；**火焰法师地火柱**（预警圈 → 爆发伤害，非箭矢）
- [x] 经验升级 + 三选一强化 UI（稀有度 roll + **effect_pack 序列帧预览**）

### 系统
- [x] 增益球 buff_orb_manager（attack/ki/combo/ice）
- [x] 自动飞镖 + 连击技能（手里剑/豪火球/闪电链/水龙卷/黑洞/刀刃旋风）
- [x] 飞镖变体、影分身、冰冻、千足虫 Boss、分裂怪
- [x] 召唤系（天雷 + 宠物 + 养育之心）、吸血蝙蝠群攻
- [x] **血渍持久化** blood_stain_manager（击杀/失败/Boss 击破）
- [x] **地面特效** ground_effect_manager（火柱，素材 `effects/2.Gothicvania Magic Pack N2 - Fire/.../fire/`）
- [x] 粒子系统、屏幕震动、**场景草地分层**、像素渲染
- [x] 过关/失败/通关 UI、**失败动画完整版**（windup→投矛→插矛→倒地 freeze）
- [x] **Boss 千足虫 warning**（脉冲红框 + 中央倒计时）
- [x] **暂停菜单调试**（跳关/改等级 + **逐项升级 +/-**）
- [x] **怪物出生动画**（淡入弹出）
- [x] 音效钩子 audio_manager（**占位，素材待接**）
- [x] Ki 回复结算期间暂停、火法师 vs 弓箭投射物区分（弓箭仍保留给 ARCHER）

### 升级（22 个均已接逻辑）
全部 upgrades.json 中的升级均有对应运行时逻辑。

### 近期完成（2026-05-23 批次 · UI / 战斗 / 特效）

**UI（`ui_sprite_helper.gd` + `pixel_ui_helper.gd` + `hud.gd`）**
- [x] HUD 图集统一为 **`res://assets/ui/UI assets (1x).png`**（勿用 2x）
- [x] 气力/经验条：**单段连续**九宫格拉伸（勿用 `0,50,144,13` 三连段整条）
- [x] 满气力：天蓝填充 + 条形状光晕（非矩形 `draw_rect`）
- [x] 暂停：`TextureButton` + 图集 `||` 区 `(210,740,12,12)`；主菜单隐藏，战斗中显示
- [x] 像素字体：8 的倍数字号 + 整数坐标；`draw_centered_text` 按 ascent/descent 居中
- [x] 增益球提示：仅屏幕**上方** `draw_buff_notice`；下方 `show_message` 已去掉
- [x] 连击 UI：显示**实际命中次数**；`+N%` 仍按内部加权连击算伤害加成
- [x] 去掉「气力满后划线」常驻提示、连击底板（仅文字 + 细描边）

**输入（`battle.gd`）**
- [x] 开局/重开/跳过 intro：`battle._input`（早于 GUI）
- [x] 战斗中划线：`battle._input`（`time_scale < 1` 时 `summons`/`ground_effects` 等 `delta=0`）
- [x] 暂停按钮区域点击不触发划线（`hud.is_pause_button_at`）

**战斗逻辑**
- [x] 连击：同一次攻击对同一怪物只计 1 次（`hit_monsters_this_attack` + `queue_hit` 去重）
- [x] 子弹时间：怪物 AI、火柱、天雷/召唤 **`delta=0`**（`player.BULLET_TIME`）
- [x] 关卡 intro 点击跳过：`level_overlay.clear_stage_intro()`，避免「第 N 关」常驻
- [x] 攻击残影：`combat_afterimages.gd` 列表清空后**再绘一帧**清屏

**升级特效（`ability_manager.gd` + `summon_ability_manager.gd`）**
- [x] 连击技能多用 sucai 序列帧 + `FX_SCALE≈1.75`；触发时粒子/震屏（按技能调色）
- [x] **水龙卷**：`effects/13.Gothicvania Magic Pack 8/.../sprites/water`（`water1~18.png`），**已删**程序化蓝圆/弧线
- [x] 天雷震屏减弱（约 `1.8+lv*0.15`，0.07s）；子弹时间期间天雷暂停

**其它历史批次（仍有效）**
- [x] 血渍、升级弹窗序列帧、Boss warning、暂停调试、火柱、路径预览、失败动画、草樱地形、game_tuning 45 项等（见 git / 上文章节）

---

## 4.2 UI 图集与 HUD 踩坑

| 项目 | 正确做法 | 错误示例 |
|------|----------|----------|
| UI 图集 | `UI assets (1x).png` | 2x 图集、`(0,50,144,13)` 当整条气力条 |
| 暂停图标 | `(210,740)` 附近 `||` | `(287,785)` 横条、`(48,176)` 大块 |
| 气力满色 | `KI_FILL_FULL` 天蓝 + 条形状光晕 | 方形 `draw_rect` 光晕 |
| 提示框文字 | `draw_centered_text` + 显式 `Vector2` | `draw_string` 用 `size.y*0.5` 当居中 |
| 连击数字 | `combo_hit_count`（命中数） | `int(combo_count)`（含多重连击倍率） |

**经验条**：由 `ui_sprite_helper.draw_exp_bar` 绘制（非 `pixel_ui_helper` 底部条）。

---

## 4.3 子弹时间下的暂停规则

`battle._update_playing` 中当 `time_scale < 1.0`（子弹时间）时，下列系统使用 **`delta = 0`**：

| 系统 | 脚本 |
|------|------|
| 怪物 AI | `monster.update_ai(0)` |
| 地面火柱 | `ground_effect_manager` |
| 召唤/天雷 | `summon_ability_manager`（且 `BULLET_TIME` 直接 return） |

仍用 **真实 `real_delta`**：环境草樱、飘字、粒子、自动飞镖结算、路径预览等（按当前实现为准）。

---

## 4.4 特效素材路径

**完整说明见 [`docs/EFFECTS.md`](EFFECTS.md)**（注册、绘制模式、替换/新增 Checklist）。

| key | sucai 路径（相对 `assets/`） |
|-----|------------------------------|
| tornado（水龙卷） | `effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/sprites/water` |
| black_hole（黑洞） | `effects/10.GothicVania Magic Pack 7/Magic Pack 7 files/sprites/vfx-d`（Aseprite json + 前 9 帧） |
| fireball | `effects/5.../fireball/sprites` |
| fire_pillar | `effects/2.../sprites/fire` |
| dart / lightning / … | 见 `effect_helper.gd` 内 `EFFECT_ATLAS` 与 `PREVIEW_PATHS` |

**换特效后仍显示旧图**：调试控制台执行 `EffectHelper.clear_cache()`，或重启 Godot（`static var _cache`）。

`upgrades.json` 中 `water_tornado` 的 `effect_pack` 已指向 Pack 8；`black_hole` 指向 Pack 7 vfx-d。重导 Excel 时以 `tools/export_config.py` 为准。

---

## 4.5 代码注意（Godot 4 严格类型）

- `Dictionary` 取 `pos` 画 UI/特效时需 `Vector2(x.pos)`，并写 `var p: Vector2 = ...`
- 勿在同一函数内重复 `var lv :=`（如 `_update_thunder` 曾因此无法 preload）
- 勿用参数名 `s` 再声明 `var s :=`（如 `_draw_god_sword`）

---

## 4.1 场景草地 / 地形（当前方案）

**三层叠加**（`battle.gd` 在 `_ready` / `_start_stage` 中初始化）：

| 层级 | 节点 | z_index | 说明 |
|------|------|---------|------|
| 底 | `battle.tscn` → `Background`（ColorRect） | -100 | 纯色草地绿 `#4c8050` 近似色，作为全屏底 |
| 低 | `TerrainBackground`（`terrain_background.gd`） | -5 | **稀疏 sucai 独立 PNG**：岩石 + 灌木，约 8 个/关，避开主角安全区 |
| 中 | `GrassSystem`（`grass_system.gd`） | -4 | **程序化**摇摆小草丛，约 22 簇（对齐 `cankao/js/grass.js`） |
| 高 | `SakuraSystem`（`sakura_system.gd`） | -2 | 关卡 intro 樱花飘落（非常驻） |

**`_sync_background_layer()`**：保证 `Background` 始终可见且在最低层；地形加载成功时**不再**隐藏 Background（Background 就是草地底色）。

### ⚠️ 已知踩坑：`Tile.png` 不可 16×16 平铺

`assets/Terrain/Tiles/Tile.png`（240×192）是**不规则图集**（大块水塘/土坡/过渡块 + 零散小花蘑菇），**不是**均匀草地瓦片表。

曾尝试用 `TileMap` 按 16×16 铺满全屏 → 图集乱切 → 满屏花斑噪声。**勿再使用此方案**。

若未来要做真实草地纹理：
- 优先在 sucai 中找**独立**草地平铺图或已切好的 `.tres` TileSet；
- 或继续「纯色底 + 程序化草簇 + 稀疏 props」的当前方案。

### sucai 地形装饰路径（`terrain_background.gd` 当前使用）

```
res://assets/Terrain/Rocks/6.png ~ 9.png
res://assets/Terrain/Trees/Tree1.png, 4.png, 5.png
```

---

## 5. 未完成 / 待做 ❌

### 低优先级 / polish
- [ ] **音效素材** 接入 audio_manager（sucai 仅有特效包附带 BGM/Magic Fx，无战斗 SFX；需专用音效文件后再接 `audio_manager.gd`）

---

## 6. 关键脚本速查

| 文件 | 职责 |
|------|------|
| `scripts/battle.gd` | 状态机、输入、关卡推进、失败/过关、震动、**场景 ambience（草/樱/地形）** |
| `scripts/systems/path_input.gd` | 划线输入、子弹时间进出、气力消耗 |
| `scripts/entities/player.gd` | 主角 FSM、升级 rebuild、影分身、**攻击路径线（top_level 世界坐标）** |
| `scripts/core/combat_director.gd` | 连击结算、路径预览、clone/ice burst、**残影/死亡错峰** |
| `scripts/systems/stage_fail_animator.gd` | 失败动画（windup/投矛/插矛/倒地/freeze） |
| `scripts/systems/terrain_background.gd` | **稀疏 sucai 地形装饰**（岩石/灌木 PNG，非 TileMap 平铺） |
| `scripts/systems/grass_system.gd` | 程序化像素草簇（~22 簇，随风摇摆） |
| `scripts/systems/sakura_system.gd` | 关卡 intro 樱花飘落 |
| `scripts/core/ground_effect_manager.gd` | 火柱预警/爆发/淡出 |
| `scripts/core/blood_stain_manager.gd` | 地面血渍 |
| `scripts/core/ability_manager.gd` | 飞镖/连击技能 VFX（序列帧 + 震屏粒子；水龙卷仅 sprite） |
| `scripts/core/summon_ability_manager.gd` | 天雷 + 宠物（子弹时间暂停） |
| `scripts/ui/combat_afterimages.gd` | 攻击残影绘制；清空后需 `queue_redraw` |
| `scripts/utils/ui_sprite_helper.gd` | Franuka 1x UI 图集：气力/经验条、暂停按钮 |
| `scripts/core/particle_manager.gd` | 粒子特效 |
| `scripts/core/buff_orb_manager.gd` | 增益球 |
| `scripts/core/monster_spawner.gd` | 刷怪、Boss、分裂子体 |
| `scripts/utils/effect_helper.gd` | 特效序列帧加载 + **`clear_cache()`** |
| `scripts/ui/hud.gd` | HUD 绘制、暂停按钮、输入区域检测 |
| `scripts/utils/pixel_ui_helper.gd` | 像素字体/连击条/消息框/增益提示 |
| `scripts/ui/level_overlay.gd` | 关卡 intro/过关/失败/通关 UI |
| `scripts/ui/pause_menu.gd` | 暂停 + 调试跳关 + 升级调试 |
| `scripts/ui/upgrade_popup.gd` | 升级三选一 + 稀有度 VFX + 序列帧 |
| `scripts/autoload/audio_manager.gd` | 音效钩子（占位） |
| `scripts/autoload/game_config.gd` | JSON 配置加载 |

**GameState 枚举**（`game_state.gd`）：MENU, STAGE_INTRO, PLAYING, LEVEL_UP, STAGE_CLEAR, FAIL_DEATH, STAGE_FAIL, FAIL, COMPLETE, PAUSED

---

## 7. 参考前端对照

| 前端文件 | Godot 对应 |
|----------|-----------|
| `cankao/js/input.js` | path_input.gd |
| `cankao/js/main.js` | battle.gd |
| `cankao/js/player.js` | player.gd |
| `cankao/js/combat.js` | combat_director.gd |
| `cankao/js/abilities.js` | ability_manager.gd |
| `cankao/js/summonAbilities.js` | summon_ability_manager.gd |
| `cankao/js/buffOrbs.js` | buff_orb_manager.gd |
| `cankao/js/bossCentipede.js` | centipede_boss.gd |
| `cankao/js/upgrades.js` | upgrade_popup.gd + upgrade_manager.gd |
| `cankao/js/failDeath.js` | stage_fail_animator.gd |
| `cankao/js/levelManager.js` | level_overlay.gd |
| `cankao/js/grass.js` | grass_system.gd |
| `cankao/js/sakura.js` | sakura_system.gd |
| `cankao/js/ui.js` | hud.gd + pixel_ui_helper.gd |
| `cankao/js/pauseMenu.js` | pause_menu.gd |
| `cankao/js/particles.js` | particle_manager.gd |
| `cankao/js/bloodStains.js` | blood_stain_manager.gd |
| `cankao/js/groundEffects.js` | ground_effect_manager.gd |
| `cankao/js/audio.js` | audio_manager.gd |
| `cankao/js/renderer.js` shake | battle.gd shake_camera |

---

## 8. 开发与验证

**Godot 路径**：`D:\godot\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe`

```powershell
# 无界面验证项目能加载
& "D:\godot\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path "D:\workspace\godot1\renzhezhan" --quit-after 2
```

**注意**：不要用 `--script` 单独测 gd 文件（不会加载 autoload，会误报 GameConfig 找不到）。

**MCP**：`user-godot-mcp` 需 Godot 编辑器打开项目且 godot_mcp 插件启用。

**操作**：
- F5 → 点击屏幕开始 → 气力满后白圈内划线 → 松手攻击
- 主菜单/战斗中应看到：**绿底 + 少量摇摆草簇 + 零星岩石灌木**（非满屏花纹）
- 划线路径上可看到**黄色命中预览**；路径线应**固定在划线路径**，不随主角冲刺移动
- 子弹时间：怪物/火柱/天雷应**冻结**；松手后恢复正常
- 连击 ≥2：显示「连击×N」（N=命中数），无底板；残影攻击结束后应消失
- 第 3 关起火焰法师 → 脚下**红圈预警**后火柱（sucai fire 序列帧）
- 水龙卷（连击每 +3）：Pack 8 `water` 动画，**无蓝色实心圆**
- 右上角暂停（战斗中）；Esc 亦可暂停
- 吃增益球：仅**上方**短提示（如「气力+30%」）
- Esc → 调试 → 升级奖励 / 跳关

---

## 9. 建议下一批任务（按顺序）

1. **音效素材**（准备 hit/slash/death/level_up 等 SFX 后放入 `res://assets/audio/`，再接 `audio_manager.gd`）

---

## 10. 新对话如何继续

```
请先阅读 D:\workspace\godot1\renzhezhan\docs\PROJECT_HANDOFF.md，
然后继续实现第 9 节的下一项：________
```

替换最后一行为具体任务即可。需要新美术素材时，从 `D:\workspace\godot1\sucai` 查找并复制到 `assets/`，登记后运行 `python tools/copy_used_assets.py`；缺素材时才程序化绘制并记入文档。
