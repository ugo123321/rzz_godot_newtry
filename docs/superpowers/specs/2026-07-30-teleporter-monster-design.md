# 瞬移怪（TELEPORTER / Blink Mage）设计

> 日期：2026-07-30
> 状态：已确认，待实现
> 相关：参考 JUMPER / LASER / DASHER 状态机写法；子弹像素绘制参考 enemy_arrow `PIXEL_ORB`

## 一、目标

新增怪物 `TELEPORTER`（瞬移怪）。外观用 `assets/Characters/Characters(100x100)/Necromancer`，攻击动画用 `Attack02`。攻击距离远，只靠瞬移换位不走路；出现即向玩家发射一发暗紫魔法弹，2 秒后消失，1.5 秒后在屏幕边缘重新出现，反复。瞬移动画用死亡动画前 5 帧：消失正放、出现倒放。

## 二、行为状态机（monster.gd）

新增 `kind_id == "TELEPORTER"` 分支，常量驱动（仿 JUMPER/LASER）。

常量：
```
TELEPORT_APPEAR_SEC := 0.35
TELEPORT_VISIBLE_SEC := 2.0
TELEPORT_DISAPPEAR_SEC := 0.35
TELEPORT_GONE_SEC := 1.5
TELEPORT_EDGE_MARGIN := 60.0      # 距屏边的内缩量
TELEPORT_MIN_PLAYER_DIST := 160.0 # 出现点离玩家最小距离
TELEPORT_TELEGRAPH_SEC := 0.30    # GONE 末尾画预警圈的时长
```

状态枚举（int 0..3）：
```
0 APPEAR    现身：modulate.a=1，播放 teleport_in，倒计时 APPEAR_SEC
1 VISIBLE   进入瞬间发 1 发子弹 + 播 attack，转 idle，倒计时 VISIBLE_SEC
2 DISAPPEAR 播 teleport_out，倒计时 DISAPPEAR_SEC
3 GONE      modulate.a=0，隐形 + 不可选 + 免疫；末尾 TELEGRAPH_SEC 画紫色脉动圈在将出现点；倒计时 GONE_SEC → 重新选位 → APPEAR
```

- `can_move = 0`：通用移动块 `if can_move and not frozen:` 自然跳过；update_ai 里在通用移动块之后、attack_timer 段之前 `if kind_id == "TELEPORTER": _update_teleporter(delta, player, battle); return`（与 JUMPER/LASER/DASHER 分支同位置）。注意：`frozen` 判定不含 TELEPORTER（不需要，can_move=0 已跳过移动）。
- 子弹发射：`battle.spawn_arrow(global_position, player.global_position, attack, arrow_speed, projectile_effect, sprite_tint)`，每周期仅 1 发。
- `is_combat_targetable()`：仅 GONE 返回 false（隐形免伤）。APPEAR/VISIBLE/DISAPPEAR 可击。
- `_resolve_take_damage()`：开头加 `if _teleport_state == 3: return {"damage":0,"is_crit":false}`（GONE 免疫兜底，防止接触/范围伤害穿透）。
- 死亡走通用 `begin_dying` / death 淡出；dying 期间 `_update_teleporter` 不推进（`if not alive or dying: return` 已在 update_ai 顶部）。

## 三、重新出现位置（屏幕边缘随机）

GONE→APPEAR 切换时在 `_pick_teleport_pos(battle)` 选位：
- 屏宽高取 `GameConfig.get_tuning("logical_width"/"logical_height")`。
- 随机选 4 边之一，沿该边在屏内 `TELEPORT_EDGE_MARGIN` 处取随机点。
- 最多 20 次尝试，拒绝距玩家 < `TELEPORT_MIN_PLAYER_DIST` 的点；失败兜底取 `(w*0.5, h*0.25)`。
- 地形避让：可选调用 `battle.is_move_blocked_at` 跳过（与 _pick_spawn_pos 一致），失败次数内重试。

## 四、瞬移动画（运行时从 death 帧派生）

`_apply_sprite()` 末尾：`if kind_id == "TELEPORTER": _build_teleport_anims(anim_sprite)`。

`_build_teleport_anims(anim_sprite)`：
- 取 `anim_sprite.sprite_frames`；若 `has_animation("death")` 且帧数 ≥ 5 且尚未 `has_animation("teleport_out")`：
  - `teleport_out` = death 第 0..4 帧（正序）
  - `teleport_in` = death 第 4..0 帧（倒序）
- 用 `frames.get_frame_texture("death", i)` + `frames.add_frame("teleport_out"/"teleport_in", tex, dur)`。
- 设速度 14 fps、不循环（`SpriteHelper.configure_animation` 风格，但名字不在常量表，手动 set）。
- 幂等：缓存对象上重复添加安全（多实例共享 SpriteFrames）。

动画名常量：在 monster.gd 本地定义 `ANIM_TELEPORT_IN := "teleport_in"` / `ANIM_TELEPORT_OUT := "teleport_out"`（不加进 SpriteHelper 全局常量，避免污染）。

## 五、Necromancer 精灵图集（新建 atlas）

现有 `assets/Characters/atlases/` 无 Necromancer；条带回退 `_load_character_strip_frames` 的文件名映射用连字符（`Prefix-Attack02.png`），与 Necromancer 实际文件名下划线（`Necromancer_Attack02.png` / `Necromancer_DEATH.png`）不匹配，回退会失败。故新建正式 atlas。

### 生成脚本 `tools/build_necromancer_atlas.py`（PIL）

输入（`assets/Characters/Characters(100x100)/Necromancer/Necromancer/`）：
| 动画 tag | 源文件 | 帧数 |
|---|---|---|
| Idle | Necromancer_Idle.png | 6 |
| Walk | Necromancer_Walk.png | 6 |
| Attack | Necromancer_Attack02.png | 10 |
| Hurt | Necromancer_Hurt.png | 4 |
| Death | Necromancer_DEATH.png | 9 |
| Attack01 | Necromancer_Attack01.png | 9 |

输出：
- `assets/Characters/atlases/sheets/Necromancer.png`：每动画一行，1000×600（宽=该行动画数×100，高=6 行×100）。
- `assets/Characters/atlases/json/Necromancer.json`：Aseprite 导出格式：
  - `frames[]`：按行优先顺序（Idle 0-5, Walk 6-11, Attack 12-21, Hurt 22-25, Death 26-34, Attack01 35-43），每帧 `frame{x,y,w=100,h=100}` + `duration=100`。
  - `meta.frameTags`：`{name:"Idle",from:0,to:5}` … `{name:"Attack01",from:35,to:43}`。

`EffectHelper._character_tag_to_anim` 映射：Attack→ANIM_ATTACK、Attack01→ANIM_ATTACK01、Idle/Walk/Hurt/Death 标准映射。`_character_frames_complete` 通过（idle/attack/hurt/death 齐全）。

> 新 png 需在 Godot 编辑器打开一次以生成 `.import`/ctex；运行时 `load()` 才生效。

## 六、攻击子弹（enemy_arrow.gd 新增 PIXEL_BOLT）

新增 `DrawStyle.PIXEL_BOLT` + `_draw_pixel_bolt()`，由 `effect_key == "enemy_teleport_bolt"` 触发。

`_ready()` 末尾分支（与 PIXEL_ORB/SQUARE/SNAKE 同构）：
```
if _effect_key == "enemy_teleport_bolt":
    _draw_style = DrawStyle.PIXEL_BOLT
    set_process(true); queue_redraw(); return
```

`_draw_pixel_bolt()`（豪火球术配方 / 同 PIXEL_ORB 风格）：
- 调色板 5 档（暗紫）：`#2a1438` → `#4a2a6a` → `#6a3a98` → `#9a5ad0` → `#c898ff`（核心）
  - 用 `_pixel_palette(base)` 机制，base = `Color("#6a3a98")`（_tint!=WHITE 时用 _tint 派生）。
- 外发光圆晕两层（alpha 0.28 / 0.14，半径递增）。
- 主体：方块圆盘，按到中心距离取色（`_orb_block_color`），半径 4 block，80ms 闪烁。
- 核心 2×2 高光，闪烁时 lerp 白。
- 尾迹：`self.rotation = velocity.angle()`（local +x = 前进方向），在 -x 方向画 3 节递减半径/alpha 小圆，模拟运动残影。
- `_process`：闪烁重画（同其它 PIXEL_* 风格）。
- 命中沿用 `particles.hit_spark`（与现有像素子弹一致，不另写 hit burst）。

## 七、配置

### monsters.json 新增
```json
{
  "kind_id": "TELEPORTER",
  "spawn_order": 16,
  "unlock_at_stage": 6,
  "name_cn": "瞬移怪",
  "name_en": "Blink Mage",
  "hp": 80, "def": 2, "attack": 12, "attack_interval": 2.0,
  "size": 12, "speed": 0, "color_hex": "#5a3a7a", "grade": "A",
  "can_move": 0, "attack_range": 320, "arrow_speed": 140, "ranged": 1,
  "ki_drain_on_hit": 0, "max_split_tier": 0, "split_count": 0,
  "exp_reward": 3,
  "character_folder": "Necromancer", "sprite_prefix": "Necromancer",
  "projectile_folder": "",
  "attack_pattern": "",
  "projectile_effect": "enemy_teleport_bolt",
  "spread_count": 0, "spread_angle_deg": 0, "bounce_count": 0,
  "sprite_tint_hex": ""
}
```

### stages.json
- 给若干中后期关加 `"teleporter": 1`（建议 stage 6、8、11、14），json-only 补加列（同 dasher/jumper/laser）。

### monster_spawner.gd
- `_spawn_stage_content` 与 `_refill_queue_for_infinite` 的 counts dict 各加：
  `"TELEPORTER": maxi(0, int(stage.get("teleporter", 0)))`

### xlsx 同步
- 跑 `python tools/sync_json_to_excel.py` 回写 monsters.xlsx / stages.xlsx。
- kind 专属时序字段为 json-only（不入 MONSTER_HEADERS），符合 [[reference_monsters_config_flow]] 流程。

## 八、i18n / 约束符合

- 怪物名走配置 `name_cn`/`name_en` 双列（沿用现有怪物模式，无新增裸中文 UI 文字）。
- 子弹/瞬移视觉纯代码绘制，无可见文字。
- 不触碰元素衍生效果（Sheet4）、不碰奖励表、不引入 special_rule。
- 新增可见像素视觉遵循 CLAUDE.md 第九条「豪火球术配方」数据驱动 idiom。

## 九、涉及文件清单

- `scripts/entities/monster.gd`：状态机 + 选位 + teleport anim 派生 + is_combat_targetable/take_damage 门控
- `scripts/entities/enemy_arrow.gd`：PIXEL_BOLT draw style + _draw_pixel_bolt + _ready 分支
- `scripts/core/monster_spawner.gd`：两处 counts dict 加 TELEPORTER
- `config/json/monsters.json`：TELEPORTER 条目
- `config/json/stages.json`：teleporter 计数列
- `tools/build_necromancer_atlas.py`：新生成脚本
- `assets/Characters/atlases/json/Necromancer.json` + `sheets/Necromancer.png`：新 atlas 产物（脚本生成）

## 十、验证

1. 跑 `python tools/build_necromancer_atlas.py` 生成 atlas；打开 Godot 编辑器一次让 png 导入。
2. 跑 `python tools/sync_json_to_excel.py`。
3. 进游戏到 stage 6+：确认瞬移怪出现 → 现身动画（倒放死亡帧）→ 发射暗紫子弹 → 2s 后消失（正放死亡帧）→ 1.5s 后在屏边重现身 → 循环。
4. 验证：GONE 期间不可选中/不受伤；VISIBLE 期间可被击杀；死亡正常淡出。
5. 验证子弹：暗紫光球 + 尾迹 + 闪烁 + 外发光，命中玩家掉血 + hit_spark。
