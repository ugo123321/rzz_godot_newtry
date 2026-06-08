# 特效系统使用说明

> **用途**：替换或新增战斗/升级特效时，让 AI 先读本文，再改代码与素材。  
> **核心入口**：`scripts/utils/effect_helper.gd`  
> **最后更新**：2026-05-25

---

## 1. 总览

本项目**不使用场景节点挂 AnimatedSprite2D 做战斗特效**，而是：

1. 在 `EffectHelper.EFFECT_ATLAS` 注册素材 key → 路径
2. 运行时 `build_effect_frames(key)` 得到 `SpriteFrames`（动画名固定为 `"preview"`）
3. 各 Manager 在 `_draw` / `draw_*` 里用 `SpriteHelper.draw_effect_texture*` 手动画图

```
素材 (assets/effects/...)
    ↓ EffectHelper.build_effect_frames("black_hole")
SpriteFrames  animation="preview"
    ↓ animation_frame_texture / projectile_frame_texture
Texture2D 单帧
    ↓ SpriteHelper.draw_effect_texture / draw_effect_texture_rect
CanvasItem 上绘制
```

**素材来源**：从 `D:\workspace\godot1\sucai` **复制**到 `assets/`，不要直接引用 sucai 路径。

---

## 2. 素材目录规范

推荐按 Gothicvania 包结构放置（与现有资源一致）：

```
assets/effects/<包名>/Magic Pack X files/
├── aseprite/          ← Aseprite 导出的 *.json（优先）
├── spritesheets/      ← 与 json 配套的横向/网格图集 *.png
└── sprites/<名>/      ← 单帧序列 fallback（vfx-d1.png, water1.png …）
```

### 2.1 方式 A：Aseprite JSON + 图集（推荐）

- `aseprite/foo.json`：`frames[]` 每帧含 `frame.x/y/w/h`、`duration`
- `spritesheets/foo.png`：图集 PNG
- json 内 `meta.image` 通常指向 `"../spritesheets/foo.png"`

参考：`assets/effects/13.Gothicvania Magic Pack 8/.../aseprite/water.json`

### 2.2 方式 B：PNG 序列目录（fallback）

- 目录内按 `name1.png`, `name2.png` … 或 `name01.png` 命名
- 仅需在 `EFFECT_ATLAS` 里配 `"fallback"`，不配 json/sheet 也可工作

参考：`smoke_hit`、`hit_a`

### 2.3 无 JSON 时手动生成

若 sucai 只有 `.ase` + 图集、没有 json，可参考 `tools/setup_vfx_d_black_hole.py`：
读取 PNG 尺寸 → 生成前 N 帧的 json → 复制图集与单帧到 `assets/`。

---

## 3. 在 `effect_helper.gd` 注册

在 `EFFECT_ATLAS` 增加或修改一项：

```gdscript
"my_effect": {
    "json": "res://assets/effects/.../aseprite/my_effect.json",   # 可选，有则优先
    "sheet": "res://assets/effects/.../spritesheets/my_effect.png",
    "fallback": "res://assets/effects/.../sprites/my_effect",     # json 失败时用
    "fps": 12.0,          # 可选，覆盖 json 推算的 fps
    "max_frames": 9,      # 可选，只取前 N 帧（黑洞 vfx-d 前 9 帧）
    "tail_frames": 2,     # 可选，只取最后 N 帧（水龙卷 tornado）
},
```

**加载顺序**（`build_effect_frames`）：

1. 有 `json` + `sheet` → `_load_aseprite_json_frames`
2. 失败 → `fallback` 目录 PNG 序列
3. 再失败 → `PREVIEW_PATHS` 硬编码路径
4. 再失败 → 在 `effect_pack` 目录里按 `SEARCH_ALIASES` 搜索

**透明处理**：图集/序列 PNG 加载时会做 black-key（RGB ≤ 0.11 → alpha 0），无需手动抠图。

**缓存**：静态 `_cache`；换素材后执行 `EffectHelper.clear_cache()` 或重启 Godot。

---

## 4. 当前已注册的战斗 key

| key | 用途 | 主要使用位置 |
|-----|------|-------------|
| `dart` | 飞镖 / 手里剑 | `ability_manager.gd` |
| `fire_missile` | 普攻火球 | `ability_manager.gd` |
| `giant_dart` | 巨大火球（与 lightning 共用 big-bolt 图） | 配置用，实际走 fire_missile 分支 |
| `ice` | 寒冰火球 | `ability_manager.gd` |
| `spirit_bomb` | 元气弹 | `ability_manager.gd` |
| `fireball` | 豪火球 | `ability_manager.gd` |
| `lightning` | 闪电链 | `ability_manager.gd` |
| `tornado` | 水龙卷 | `ability_manager.gd` → `_draw_water_tornado` |
| `black_hole` | 黑洞 | `ability_manager.gd` → `_draw_black_hole` |
| `whirl` | 刀阵旋风 | `ability_manager.gd` |
| `smoke_hit` | 命中烟雾 | `ability_manager.gd` |
| `hit_a` | 划线斩击命中 | `combat_director.gd` |
| `fire_pillar` | 地面火柱 | `ground_effect_manager.gd` |
| `air_slash` | 开始划线提示 | `player.gd` |

**仅升级预览 / 未进 EFFECT_ATLAS 的**（走 `PREVIEW_PATHS` + PNG 序列）：

| effect_name | 路径 alias |
|-------------|-----------|
| shuriken | spark 序列 |
| vine / heal | Cure 序列 |
| shield | flash 序列 |
| bat | slash 序列 |
| clone | wisp 序列 |
| thunder | thunder 序列 |

**宠物**（`is_pet: 1`）：走 `EffectHelper.build_character_frames`，素材在 `assets/Characters/`，不由 `EFFECT_ATLAS` 管。

---

## 5. 绘制模式（改特效大小/动画时看这里）

所有帧动画都用 `SpriteFrames` 的 **`"preview"`** 动画（`EffectHelper.ANIM_PREVIEW`）。

### 5.1 循环动画 + 时间驱动（推荐，水龙卷/黑洞）

```gdscript
# 每帧更新
obj["anim_t"] = float(obj.get("anim_t", 0.0)) + delta

# 绘制
var tex := EffectHelper.animation_frame_texture(frames, float(obj.anim_t))
var size := tex.get_size()
var draw_scale := (gameplay_radius * 2.0) / maxf(size.x, size.y)  # 直径 = 2*半径
var draw_size := size * draw_scale
SpriteHelper.draw_effect_texture_rect(canvas, tex, Rect2(local_pos - draw_size * 0.5, draw_size), modulate)
```

- **水龙卷**：固定视觉半径 `60 * FX_SCALE`，`draw_scale = (draw_r * 2.2) / max(size)`
- **黑洞**：`draw_scale = (bh.radius * 2.0) / max(size)`，与 gameplay 吸附半径一致
- **火柱**：`(r * 2.2) / max(size)`，略向上偏移

### 5.2 投射物 + 旋转选帧

```gdscript
var tex := EffectHelper.projectile_frame_texture(frames, spin)
SpriteHelper.draw_effect_texture(canvas, tex, local_pos, rot, Vector2.ONE * draw_scale, modulate)
```

用于：飞镖、豪火球、刀阵等（`ability_manager._draw_sprite_fx` / `_draw_animated_projectile`）。

### 5.3 一次性播放

```gdscript
var tex := EffectHelper.animation_frame_texture_once(frames, anim_t)
# anim_t >= 总时长时返回 null，特效结束
var duration := EffectHelper.one_shot_anim_duration(frames)
```

用于：斩击命中 `hit_a`、烟雾 `smoke_hit`、划线开始 `air_slash`。

### 5.4 常用缩放常量（`ability_manager.gd`）

| 常量 | 值 | 说明 |
|------|-----|------|
| `FX_SCALE` | 1.75 | 全局战斗特效缩放 |
| `PROJ_DRAW_SCALE` | 0.72 | 投射物基础缩放 |
| `AUTO_FIREBALL_DRAW_SCALE` | 0.78 | 普攻火球 |

---

## 6. 升级配置里的 effect 字段

`config/json/upgrades.json`（Excel 导出）相关字段：

| 字段 | 说明 |
|------|------|
| `effect_name` | 对应 `EFFECT_ATLAS` 的 key，或 `PREVIEW_PATHS` / 搜索 alias |
| `effect_pack` | 素材包相对路径 `effects/...`；`build_upgrade_preview_frames()` 用 |
| `icon_file` | 升级卡片静态图标（当前 UI 主要用这个） |

**注意**：升级弹窗 `_create_icon_widget` 目前显示的是 `icon_file` 静态图；`build_upgrade_preview_frames()` 已实现但 UI 未接动画预览。若以后要卡片内播动画，在 `upgrade_popup.gd` 接 `EffectHelper.build_upgrade_preview_frames(upgrade)`。

---

## 7. 替换已有特效（Checklist）

以把黑洞换成 Pack 7 的 vfx-d 为例：

- [ ] 从 sucai 复制 `aseprite/`、`spritesheets/`、`sprites/` 到 `assets/effects/...`
- [ ] 无 json 时用 `tools/setup_vfx_d_black_hole.py` 或 Aseprite 导出 json
- [ ] 修改 `effect_helper.gd` → `EFFECT_ATLAS["black_hole"]` 的 json/sheet/fallback/fps/max_frames
- [ ] 若只改素材、不改 key：**不必改** `ability_manager.gd`
- [ ] 同步 `config/json/upgrades.json` 与 `tools/export_config.py` 里的 `effect_pack`（防 Excel 重导覆盖）
- [ ] 若需去掉程序化绘制（圆/弧）：改对应 Manager 的 `_draw_*`，只保留 `SpriteHelper` 画精灵
- [ ] 若需与 gameplay 范围对齐：在 `_draw_*` 里用 `{半径} * 2 / tex.get_size()` 算 scale
- [ ] Godot 重载项目 → `EffectHelper.clear_cache()` → 进战斗验证

---

## 8. 新增战斗特效（Checklist）

- [ ] 复制素材到 `assets/effects/...`
- [ ] `effect_helper.gd` → `EFFECT_ATLAS` 新增 key
- [ ] 在使用处 `_ready`/`setup` 预加载：`var _foo_frames = EffectHelper.build_effect_frames("foo")`
- [ ] 在对应 Manager 增加 spawn / update / draw（选 5.1~5.3 一种模式）
- [ ] 需要升级关联时：在 `upgrades.json` 填 `effect_name` / `effect_pack`，必要时加 `PREVIEW_PATHS` / `SEARCH_ALIASES`
- [ ] 登记 `tools/copy_used_assets.py`（若项目有维护复制清单）

---

## 9. 各 Manager 职责

| 脚本 | 负责的特效 |
|------|-----------|
| `ability_manager.gd` | 飞镖、火球、连击技能（龙卷/黑洞/旋风/闪电/豪火球）、命中烟 |
| `combat_director.gd` | 划线斩击命中 `hit_a`、伤害飘字 |
| `ground_effect_manager.gd` | 地面火柱 `fire_pillar` |
| `summon_ability_manager.gd` | 天雷、宠物（角色 atlas） |
| `player.gd` | 划线开始 `air_slash`、角色 sprite |

新增「连击触发的地面/飞行特效」通常改 **`ability_manager.gd`**：
- `on_combo_hit()` 里触发 spawn
- `update()` 里更新 `anim_t` / 生命周期
- `draw_fx()` 里 `_draw_*`

---

## 10. 调试

```gdscript
# Godot 调试控制台
EffectHelper.clear_cache()
```

- 特效不显示：检查 `res://` 路径、Godot 是否已 import PNG、`_frames.get_frame_count("preview") > 0`
- 特效仍是旧图：清缓存或重启
- 特效过大/过小：改对应 `_draw_*` 里的 scale 公式，或 gameplay 里的 `radius` 常量
- 帧数不对：检查 `max_frames`、`tail_frames`、json 里 frames 数量

---

## 11. 参考文件

| 文件 | 说明 |
|------|------|
| `scripts/utils/effect_helper.gd` | 注册表、加载、缓存 |
| `scripts/utils/sprite_helper.gd` | `draw_effect_texture` / `draw_effect_texture_rect` |
| `scripts/core/ability_manager.gd` | 战斗技能特效主战场 |
| `tools/setup_vfx_d_black_hole.py` | 无 json 时生成 Aseprite json 示例 |
| `assets/effects/13.../aseprite/water.json` | 标准 Aseprite 导出 json 样例 |
| `assets/effects/10.../aseprite/vfx-d.json` | 截取前 N 帧的 json 样例 |

---

## 12. 给 AI 的简短指令模板

以后可直接说：

> 请读 `docs/EFFECTS.md`，把 `{key}` 的特效换成 `{sucai 路径}` 的 `{资源名}` 前 `{N}` 帧，Aseprite 方式，复制到 assets，并与 `{gameplay半径}` 对齐。

或：

> 请读 `docs/EFFECTS.md`，新增 `{key}` 特效，用于 `{技能名}`，绘制模式用 `{循环/一次性/投射物}`。
