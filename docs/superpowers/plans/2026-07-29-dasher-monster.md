# 冲刺怪（DASHER）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增怪物「冲刺怪」（bat 外观）：玩家进入攻击范围后停下蓄力变红，然后锁定方向朝玩家直线冲刺一段固定距离，命中每轮只掉一次血。

**Architecture:** 仿现有 JUMPER（停下→蓄力）+ MINI_CENTIPEDE（直线冲刺）模式：在 `monster.gd` 加局部状态机 `_dasher_state`(0 idle/1 windup/2 dash/3 recover) + `_update_dasher()`，在 `update_ai` 加 kind 分支，在 `_apply_status_tint` 加 windup 变红分支。bat 美术走现有 atlas 管线（`atlases/json/Bat.json` + `atlases/sheets/Bat.png`），与其他怪一致。配置走 `monsters.json`（运行时权威源），spawner counts 两处加 `"DASHER"`，stages.json 给目标关加数量。

**Tech Stack:** Godot 4.7（GDScript）、Python+PIL（拼 atlas sheet）、现有 `tools/sync_json_to_excel.py`（json→excel 回写）、`tools/test_new_monsters.tscn`（headless 回归）。

设计文档：`docs/superpowers/specs/2026-07-29-dasher-monster-design.md`

## 文件结构

- **新建** `tools/build_bat_atlas.py` — 一次性脚本：把现有 bat strip PNG 拼成单张 sheet + 生成 atlas JSON。保留在 repo 便于以后重跑。
- **新建** `assets/Characters/atlases/sheets/Bat.png` — 拼合后的 sprite sheet（脚本生成）。
- **新建** `assets/Characters/atlases/json/Bat.json` — atlas 帧描述 + frameTags（脚本生成）。
- **修改** `config/json/monsters.json` — 末尾加 `DASHER` 条目。
- **修改** `config/json/stages.json` — 给 `stage_index` 3/6/10 加 `"dasher"` 数量。
- **修改** `scripts/entities/monster.gd` — 加状态字段 + setup 读扩展字段 + `update_ai` frozen/分支 + `_update_dasher` + `_apply_status_tint` windup 分支。
- **修改** `scripts/core/monster_spawner.gd` — counts 字典两处加 `"DASHER"`。
- **修改** `tools/test_new_monsters.gd` — `kinds` 数组加 `"DASHER"`。
- **重生成** `config/excel/monsters.xlsx` — 由 `sync_json_to_excel.py` 从 json 回写（防 export_config 覆盖）。

关键既有锚点（行号以当前 main 为准）：
- `monster.gd:118-141` JUMPER/LASER 状态字段块（DASHER 字段加在这后面）
- `monster.gd:204-210` setup 读 MINI_CENTIPEDE 扩展字段（DASHER 同款写法）
- `monster.gd:626` `update_ai`；`:643-645` MINI_CENTIPEDE 早 return；`:653` `frozen :=`；`:703-708` JUMPER/LASER 分支
- `monster.gd:802-858` `_update_jumper`（状态机 + telegraph 参考）
- `monster.gd:996-1015` `_step_charge`（冲刺位移 + 撞击判定参考）
- `monster.gd:1291-1314` `_apply_status_tint`（变红分支入口）
- `monster_spawner.gd:106-121` `_refill_queue_for_infinite` counts；`:163-178` `_spawn_stage_content` counts
- `effect_helper.gd:221-236` `build_character_frames`（atlas 优先、strip 兜底）；`:567-572` `_character_frames_complete`（要求 IDLE/ATTACK/HURT/DEATH 齐）；`:602-660` `_load_character_atlas_frames`（atlas 格式）；`:574-599` tag→anim 映射

---

### Task 1: 生成 bat atlas（sheet + json）

bat 现有 PNG 是 strip（每帧 100×100）：`Bat_Flying.png` 600×100（6 帧，飞行）、`Bat_Attack01.png` 600×100（6 帧）、`Bat_Attack02.png` 700×100（7 帧）、`Bat_Hurt.png` 400×100（4 帧）、`Bat_Death.png` 400×100（4 帧）。`Bat.png`（700×500）是合成总图，歧义大，不用。

atlas 需含 IDLE/ATTACK/HURT/DEATH（`_character_frames_complete` 强校验）。帧序列设计（共 27 帧，9 列×3 行 sheet）：

| 帧索引 | 来源 strip | 帧内序号 | tag | → anim |
|---|---|---|---|---|
| 0 | Bat_Flying | 0 | Idle | ANIM_IDLE |
| 0-5 | Bat_Flying | 0-5 | Walk | ANIM_WALK |
| 6-11 | Bat_Attack01 | 0-5 | Attack01 | ANIM_ATTACK01 |
| 12-18 | Bat_Attack02 | 0-6 | Attack | ANIM_ATTACK |
| 19-22 | Bat_Hurt | 0-3 | Hurt | ANIM_HURT |
| 23-26 | Bat_Death | 0-3 | Death | ANIM_DEATH |

注意：Idle 与 Walk 共享 Bat_Flying[0]（frameTags 允许重叠索引，loader 按 tag 范围各加一次）。

**Files:**
- Create: `tools/build_bat_atlas.py`
- Create: `assets/Characters/atlases/sheets/Bat.png`
- Create: `assets/Characters/atlases/json/Bat.json`

- [ ] **Step 1: 写 `tools/build_bat_atlas.py`**

```python
#!/usr/bin/env python3
"""把 bat 的 strip PNG 拼成单张 atlas sheet + 生成 Aseprite-hash 格式 JSON。
运行：python tools/build_bat_atlas.py
产物：assets/Characters/atlases/sheets/Bat.png + atlases/json/Bat.json
被 effect_helper._load_character_atlas_frames 加载，与其他怪一致。
"""
from __future__ import annotations
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BAT_DIR = ROOT / "assets/Characters/Characters(100x100)/Bat/Bat"
SHEET_DIR = ROOT / "assets/Characters/atlases/sheets"
JSON_DIR = ROOT / "assets/Characters/atlases/json"
FRAME = 100  # 每帧 100x100

# strip 文件名 + 对应 tag 名（tag 名经 effect_helper._character_tag_to_anim 映射）
# tag 顺序决定 frames 数组顺序；Walk 复用 Flying 第一帧，故 Flying 排最前。
STRIPS = [
    ("Bat_Flying.png", "Walk", 0, 6),     # 6 帧飞 → Walk
    ("Bat_Attack01.png", "Attack01", 6, 6),
    ("Bat_Attack02.png", "Attack", 12, 7),
    ("Bat_Hurt.png", "Hurt", 19, 4),
    ("Bat_Death.png", "Death", 23, 4),
]
# Idle 用 Flying 第 0 帧（bats hover），独立 tag 指向 frame index 0
IDLE_FRAME_INDEX = 0

def main() -> None:
    SHEET_DIR.mkdir(parents=True, exist_ok=True)
    JSON_DIR.mkdir(parents=True, exist_ok=True)

    # 1) 收集所有帧：按设计帧序号 0..26
    frames_meta = {}  # idx -> (strip_file, sub_index)
    for fname, _tag, start, count in STRIPS:
        for i in range(count):
            frames_meta[start + i] = (fname, i)
    total = max(frames_meta) + 1  # 27

    cols = 9
    rows = (total + cols - 1) // cols
    sheet_w = cols * FRAME
    sheet_h = rows * FRAME
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    frames_arr = []
    for idx in range(total):
        fname, sub = frames_meta[idx]
        strip = Image.open(BAT_DIR / fname).convert("RGBA")
        # strip 是 100 高、N*100 宽；按 sub 取第 sub 帧
        cell = strip.crop((sub * FRAME, 0, (sub + 1) * FRAME, FRAME))
        cx = (idx % cols) * FRAME
        cy = (idx // cols) * FRAME
        sheet.paste(cell, (cx, cy))
        frames_arr.append({
            "filename": "Bat %d.aseprite" % idx,
            "frame": {"x": cx, "y": cy, "w": FRAME, "h": FRAME},
            "rotated": False,
            "trimmed": False,
            "spriteSourceSize": {"x": 0, "y": 0, "w": FRAME, "h": FRAME},
            "sourceSize": {"w": FRAME, "h": FRAME},
            "duration": 100,
        })

    sheet_path = SHEET_DIR / "Bat.png"
    sheet.save(sheet_path)
    print("sheet:", sheet_path, sheet.size)

    # tag 列表（from/to 是 frames 数组索引）
    # Idle 单帧（hover），Walk 6 帧（飞行）
    tags = [
        {"name": "Idle", "from": 0, "to": 0, "direction": "forward", "color": "#000000ff"},
        {"name": "Walk", "from": 0, "to": 5, "direction": "forward", "color": "#000000ff"},
        {"name": "Attack01", "from": 6, "to": 11, "direction": "forward", "color": "#000000ff"},
        {"name": "Attack", "from": 12, "to": 18, "direction": "forward", "color": "#000000ff"},
        {"name": "Hurt", "from": 19, "to": 22, "direction": "forward", "color": "#000000ff"},
        {"name": "Death", "from": 23, "to": 26, "direction": "forward", "color": "#000000ff"},
    ]
    data = {
        "frames": frames_arr,
        "meta": {
            "app": "https://www.aseprite.org/",
            "version": "1.3.12-x64",
            "image": "../sheets/Bat.png",
            "format": "RGBA8888",
            "size": {"w": sheet_w, "h": sheet_h},
            "scale": "1",
            "frameTags": tags,
        },
    }
    json_path = JSON_DIR / "Bat.json"
    json_path.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    print("json:", json_path)

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 运行脚本生成 sheet + json**

Run: `python tools/build_bat_atlas.py`
Expected: 打印 `sheet: .../atlases/sheets/Bat.png (900, 300)` 和 `json: .../atlases/json/Bat.json`

- [ ] **Step 3: 让 Godot 导入新资源（生成 .import）**

新建的 `Bat.png` / `Bat.json` 需 Godot 生成 `.import` 才能在运行时加载。

Run: `godot --headless --import --path D:/workspace/rzz_godot_newtry`
Expected: 命令正常退出；`assets/Characters/atlases/sheets/Bat.png.import` 与 `atlases/json/Bat.json.import` 出现。

- [ ] **Step 4: 确认 atlas 可被加载（手写一次性 GDScript 校验跳过，靠 Task 9 的 headless 测试一并覆盖）**

- [ ] **Step 5: Commit**

```bash
git add tools/build_bat_atlas.py assets/Characters/atlases/sheets/Bat.png assets/Characters/atlases/sheets/Bat.png.import assets/Characters/atlases/json/Bat.json assets/Characters/atlases/json/Bat.json.import
git commit -m "feat(art): 生成 bat atlas（sheet+json）供冲刺怪使用"
```

---

### Task 2: monsters.json 加 DASHER 条目

**Files:**
- Modify: `config/json/monsters.json`（在最后一个 `}` 后追加新对象）

- [ ] **Step 1: 在 `monsters.json` 末尾（MINI_CENTIPEDE 条目之后）追加 DASHER 条目**

把文件结尾：
```
    "reposition_delay": 0.5,
    "name_en": "Mini Centipede"
  }
]
```
改成：
```
    "reposition_delay": 0.5,
    "name_en": "Mini Centipede"
  },
  {
    "kind_id": "DASHER",
    "spawn_order": 15,
    "unlock_at_stage": 3,
    "name_cn": "冲刺怪",
    "hp": 10,
    "def": 0,
    "attack": 1,
    "attack_interval": 1.0,
    "size": 8,
    "speed": 70,
    "color_hex": "#8B0000",
    "grade": "C",
    "can_move": 1,
    "attack_range": 0,
    "arrow_speed": 0,
    "ranged": 0,
    "ki_drain_on_hit": 0,
    "max_split_tier": 0,
    "split_count": 0,
    "exp_reward": 3,
    "character_folder": "Bat",
    "sprite_prefix": "Bat",
    "projectile_folder": "",
    "attack_pattern": "",
    "projectile_effect": "",
    "spread_count": 0,
    "spread_angle_deg": 0,
    "bounce_count": 0,
    "sprite_tint_hex": "",
    "trigger_range": 180,
    "windup_sec": 0.6,
    "dash_speed": 320,
    "dash_distance": 220,
    "recover_sec": 0.5,
    "cooldown_sec": 1.5,
    "name_en": "Dasher"
  }
]
```

说明：`trigger_range`/`windup_sec`/`dash_speed`/`dash_distance`/`recover_sec`/`cooldown_sec` 是 DASHER 专属扩展字段（同 MINI_CENTIPEDE 的 `segment_count`/`charge_speed` 等不进 MONSTER_HEADERS、json-only 列），由 `monster.gd:setup` 读取。`attack_range=0`（近战语义；实际触发由 `trigger_range` 驱动，`_update_dasher` 提前 return 不走通用 attack 路径）。`name_cn`/`name_en` 双语。

- [ ] **Step 2: 校验 JSON 合法**

Run: `python -c "import json;json.load(open('config/json/monsters.json',encoding='utf-8'));print('OK',len(_:=json.load(open('config/json/monsters.json',encoding='utf-8'))),'monsters')"`
Expected: `OK 15 monsters`

- [ ] **Step 3: Commit**

```bash
git add config/json/monsters.json
git commit -m "feat(monsters): 新增冲刺怪 DASHER 配置"
```

---

### Task 3: monster.gd 加 DASHER 状态字段 + setup 读扩展字段

**Files:**
- Modify: `scripts/entities/monster.gd:141`（LASER 字段块之后加 DASHER 字段块）
- Modify: `scripts/entities/monster.gd:204-210`（MINI_CENTIPEDE setup 分支之后加 DASHER setup 分支）

- [ ] **Step 1: 在 LASER 状态字段块之后（`monster.gd:141` `LASER_DAMAGE_MUL := 1.4` 那行之后、MINI_CENTIPEDE 注释之前）插入 DASHER 字段**

找到：
```
const LASER_DAMAGE_MUL := 1.4

# === MINI_CENTIPEDE 迷你千足虫（直线冲锋撞击型，12 节等大方块，共享血量）===
```
在中间插入：
```
const LASER_DAMAGE_MUL := 1.4

# === DASHER 冲刺怪状态机 ===
# 0=idle(接近+冷却) 1=windup(蓄力变红,锁定方向) 2=dash(直线冲刺固定距离) 3=recover
var _dasher_state := 0
var _dasher_timer := 0.0          # windup/recover 通用倒计时
var _dasher_dash_dist_acc := 0.0  # 本轮已推进距离
var _dash_dir := Vector2.ZERO
var _has_hit_this_dash := false
var _dasher_cooldown_t := 0.0     # idle 内下次可触发倒计时
# json 扩展字段（setup 读取；缺省给安全默认）
var _dasher_trigger_range := 180.0
var _dasher_windup_sec := 0.6
var _dasher_dash_speed := 320.0
var _dasher_dash_distance := 220.0
var _dasher_recover_sec := 0.5
var _dasher_cooldown_sec := 1.5

# === MINI_CENTIPEDE 迷你千足虫（直线冲锋撞击型，12 节等大方块，共享血量）===
```

- [ ] **Step 2: 在 setup() 的 MINI_CENTIPEDE 分支之后加 DASHER 分支**

找到（`monster.gd:204-210`）：
```
	if kind_id == "MINI_CENTIPEDE":
		_centi_segment_count = int(stats.get("segment_count", 12))
		_centi_segment_size = float(stats.get("segment_size", 11.0))
		_centi_segment_spacing = float(stats.get("segment_spacing", 11.0))
		_centi_segment_hitbox = float(stats.get("segment_hitbox", 6.0))
		_centi_charge_speed = float(stats.get("charge_speed", 260.0))
		_centi_reposition_delay = float(stats.get("reposition_delay", 0.5))
	global_position = spawn_pos
```
改成（在 centipede 块和 `global_position` 之间插一个 DASHER 块）：
```
	if kind_id == "MINI_CENTIPEDE":
		_centi_segment_count = int(stats.get("segment_count", 12))
		_centi_segment_size = float(stats.get("segment_size", 11.0))
		_centi_segment_spacing = float(stats.get("segment_spacing", 11.0))
		_centi_segment_hitbox = float(stats.get("segment_hitbox", 6.0))
		_centi_charge_speed = float(stats.get("charge_speed", 260.0))
		_centi_reposition_delay = float(stats.get("reposition_delay", 0.5))
	if kind_id == "DASHER":
		_dasher_trigger_range = float(stats.get("trigger_range", 180.0))
		_dasher_windup_sec = float(stats.get("windup_sec", 0.6))
		_dasher_dash_speed = float(stats.get("dash_speed", 320.0))
		_dasher_dash_distance = float(stats.get("dash_distance", 220.0))
		_dasher_recover_sec = float(stats.get("recover_sec", 0.5))
		_dasher_cooldown_sec = float(stats.get("cooldown_sec", 1.5))
	global_position = spawn_pos
```

- [ ] **Step 3: Commit**

```bash
git add scripts/entities/monster.gd
git commit -m "feat(monster): DASHER 状态字段与 setup 扩展字段读取"
```

---

### Task 4: monster.gd 加 _update_dasher + update_ai 分支

**Files:**
- Modify: `scripts/entities/monster.gd:653`（frozen 条件加 `_dasher_state != 0`）
- Modify: `scripts/entities/monster.gd:706-708`（LASER 分支之后加 DASHER 分支）
- Modify: `scripts/entities/monster.gd`（在 `_update_laser` 函数之后新增 `_update_dasher`）

- [ ] **Step 1: frozen 条件加 `_dasher_state != 0`**

找到（`monster.gd:652-653`）：
```
	# JUMPER/LASER 进入非 idle 状态时定身（酝酿/起跳/激光预警/发射期间不移动）
	var frozen := _jumper_state != 0 or _laser_state != 0
```
改成：
```
	# JUMPER/LASER/DASHER 进入非 idle 状态时定身（酝酿/起跳/激光预警/发射/蓄力/冲刺/恢复期间不走通用移动）
	var frozen := _jumper_state != 0 or _laser_state != 0 or _dasher_state != 0
```

- [ ] **Step 2: 在 LASER 分支之后加 DASHER 分支**

找到（`monster.gd:706-708`）：
```
	if kind_id == "LASER":
		_update_laser(delta, player, battle)
		return
```
改成：
```
	if kind_id == "LASER":
		_update_laser(delta, player, battle)
		return
	if kind_id == "DASHER":
		_update_dasher(delta, player, battle)
		return
```

- [ ] **Step 3: 新增 `_update_dasher` 函数**

在 `_update_laser`（`monster.gd:863-896`）函数结束之后、`# 玩家到激光射线...` 注释（`:899`）之前，插入：

```
# ===================== DASHER 冲刺怪 =====================
# 进入触发范围 → 蓄力 windup_sec（定身+渐变变红,modulate 由 _apply_status_tint 处理）
# → 锁定方向直线冲刺 dash_distance（每轮命中玩家一次,不停不拐弯）→ 恢复 recover_sec → 回 idle 冷却。
func _update_dasher(delta: float, player: BattlePlayer, _battle: Node) -> void:
	match _dasher_state:
		0:  # idle：通用移动已在外层处理；这里只做冷却+触发范围检测
			if _dasher_cooldown_t > 0.0:
				_dasher_cooldown_t = maxf(0.0, _dasher_cooldown_t - delta)
			if player == null or _dasher_cooldown_t > 0.0:
				return
			if global_position.distance_to(player.global_position) <= _dasher_trigger_range:
				_dasher_state = 1
				_dasher_timer = _dasher_windup_sec
				_dasher_dash_dist_acc = 0.0
				_has_hit_this_dash = false
				var d := player.global_position - global_position
				_dash_dir = d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
				_play_anim(SpriteHelper.ANIM_HURT, true)
		1:  # windup 蓄力：定身变红（tint 在 _apply_status_tint）
			_dasher_timer -= delta
			if _dasher_timer <= 0.0:
				_dasher_state = 2
				_play_anim(SpriteHelper.ANIM_ATTACK01, true)
		2:  # dash 直线冲刺固定距离（受 slow/paralyze/petrify 影响,同 _step_charge）
			var slow := clampf(slow_pct_active, 0.0, 0.95)
			var spd := _dasher_dash_speed * (1.0 - slow)
			if paralyze_timer > 0.0 or petrify_timer > 0.0:
				spd = 0.0
			global_position += _dash_dir * spd * delta
			_dasher_dash_dist_acc += spd * delta
			# 撞击：每轮一次接触伤害,不停不拐弯（仿 _step_charge:1004-1008）
			if not _has_hit_this_dash and player != null and player.hp > 0.0:
				var rr := player.get_effective_radius() + GameConfig.scale_world(6.0)
				if global_position.distance_to(player.global_position) <= rr:
					player.take_damage(attack)
					_has_hit_this_dash = true
			if _dasher_dash_dist_acc >= _dasher_dash_distance:
				_dasher_state = 3
				_dasher_timer = _dasher_recover_sec
				_play_anim(SpriteHelper.ANIM_IDLE)
		3:  # recover
			_dasher_timer -= delta
			if _dasher_timer <= 0.0:
				_dasher_state = 0
				_dasher_cooldown_t = _dasher_cooldown_sec


```

- [ ] **Step 4: Commit**

```bash
git add scripts/entities/monster.gd
git commit -m "feat(monster): DASHER update_ai 分支与 _update_dasher 状态机"
```

---

### Task 5: monster.gd _apply_status_tint 加 windup 变红分支

`_apply_status_tint` 每帧覆盖 `anim_sprite.modulate`，所以蓄力变红必须加在这个函数里，否则被覆盖回 baseline。放在最高优先级（petrify 之前）：被 CC 命中时 CC tint 不生效是已知次要行为（dasher 蓄力期间被石化/麻痹会仍显红而非灰/金），符合设计文档「最高优先级」。

**Files:**
- Modify: `scripts/entities/monster.gd:1295-1299`（base_tint 之后、petrify 之前插入 windup 分支）

- [ ] **Step 1: 在 base_tint 赋值之后、petrify 分支之前插入 windup 分支**

找到（`monster.gd:1295-1299`）：
```
	var base_tint: Color = sprite_tint if sprite_tint != Color.WHITE else Color.WHITE
	# sr=51 念力石化：优先级最高，覆盖所有其它 tint
	if petrify_timer > 0.0:
		anim_sprite.modulate = Color(0.55, 0.55, 0.6, 1.0)
		return
```
改成：
```
	var base_tint: Color = sprite_tint if sprite_tint != Color.WHITE else Color.WHITE
	# DASHER 蓄力：最高优先级，按进度渐变变红 telegraph（windup 期间每帧重算）
	if _dasher_state == 1:
		var p := 1.0 - clampf(_dasher_timer / maxf(_dasher_windup_sec, 0.001), 0.0, 1.0)
		anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.3, 0.3, 1.0), p)
		return
	# sr=51 念力石化：优先级最高，覆盖所有其它 tint
	if petrify_timer > 0.0:
		anim_sprite.modulate = Color(0.55, 0.55, 0.6, 1.0)
		return
```

- [ ] **Step 2: Commit**

```bash
git add scripts/entities/monster.gd
git commit -m "feat(monster): DASHER 蓄力渐变变红 tint 分支"
```

---

### Task 6: monster_spawner.gd 两处 counts 加 DASHER

spawner 从 stages.json 读 `stage.get("dasher", 0)`，漏改任一处 → 常规关或无限模式不刷该怪。

**Files:**
- Modify: `scripts/core/monster_spawner.gd:120`（`_refill_queue_for_infinite` counts）
- Modify: `scripts/core/monster_spawner.gd:177`（`_spawn_stage_content` counts）

- [ ] **Step 1: `_refill_queue_for_infinite` counts 字典加 DASHER**

找到（`monster_spawner.gd:119-121`）：
```
		"LASER": maxi(0, int(stage.get("laser", 0))),
		"MINI_CENTIPEDE": maxi(0, int(stage.get("mini_centipede", 0))),
	}
```
改成：
```
		"LASER": maxi(0, int(stage.get("laser", 0))),
		"MINI_CENTIPEDE": maxi(0, int(stage.get("mini_centipede", 0))),
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
	}
```

- [ ] **Step 2: `_spawn_stage_content` counts 字典加 DASHER**

找到（`monster_spawner.gd:176-178`）：
```
		"LASER": maxi(0, int(stage.get("laser", 0))),
		"MINI_CENTIPEDE": maxi(0, int(stage.get("mini_centipede", 0))),
	}
	_init_clusters(battle)
```
改成：
```
		"LASER": maxi(0, int(stage.get("laser", 0))),
		"MINI_CENTIPEDE": maxi(0, int(stage.get("mini_centipede", 0))),
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
	}
	_init_clusters(battle)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/core/monster_spawner.gd
git commit -m "feat(spawner): counts 字典两处加 DASHER"
```

---

### Task 7: stages.json 给目标关加 dasher 数量

DASHER `unlock_at_stage=3`，从 `stage_index=3`（第4关·铁盾试练）起若干关加入小数量。spawner 读 `stage.get("dasher", 0)`，缺省 0，所以只需在选中的关加键。给 stage_index 3/6/10 各加 1-2 只。

**Files:**
- Modify: `config/json/stages.json`（stage_index 3、6、10 三个对象）

- [ ] **Step 1: stage_index 3（第4关·铁盾试练）加 `"dasher": 1`**

stage_index 3 的对象以 `"bounce_slime": 0,` + `"boss_id": "",` + `"display_name_en": "Stage 4·Shield Trial"` 结尾。找到（唯一）：
```
    "cross_shooter": 0,
    "bounce_slime": 0,
    "boss_id": "",
    "display_name_en": "Stage 4·Shield Trial"
  },
```
改成：
```
    "cross_shooter": 0,
    "bounce_slime": 0,
    "dasher": 1,
    "boss_id": "",
    "display_name_en": "Stage 4·Shield Trial"
  },
```

- [ ] **Step 2: stage_index 6（第7关）加 `"dasher": 2`**

先打开 `config/json/stages.json`，定位 `stage_index` 为 6 的对象（搜 `"stage_index": 6,`），在其 `"bounce_slime": 0,` 行之后、`"boss_id"` 行之前插入 `"dasher": 2,`。具体改法：读出该对象尾部，把：
```
    "bounce_slime": 0,
    "boss_id": "",
```
中 `bounce_slime": 0,` 后追加新行 `"dasher": 2,`。由于该两行在多关重复，用该关独有的 `"display_name_en": "Stage 7·..."` 行向上定位，确保只改 stage_index 6 那一处。

- [ ] **Step 3: stage_index 10（第11关）加 `"dasher": 2`**

同 Step 2 方法，定位 `"stage_index": 10,` 对象，在 `"bounce_slime": 0,` 后插入 `"dasher": 2,`。

- [ ] **Step 4: 校验 JSON 合法**

Run: `python -c "import json;d=json.load(open('config/json/stages.json',encoding='utf-8'));print('OK',len(d),'stages;','dasher in',[s['stage_index'] for s in d if s.get('dasher',0)>0])"`
Expected: `OK 30 stages; dasher in [3, 6, 10]`

- [ ] **Step 5: Commit**

```bash
git add config/json/stages.json
git commit -m "feat(stages): 第4/7/11关加入冲刺怪"
```

---

### Task 8: test_new_monsters.gd 加 DASHER 回归

回归脚本以场景方式 headless 跑：配置可加载、setup 不崩、update_ai 多帧推进状态机不崩、_draw 不崩。把 DASHER 加进 kinds 数组。

**Files:**
- Modify: `tools/test_new_monsters.gd:2,42`

- [ ] **Step 1: kinds 数组加 DASHER**

找到（`tools/test_new_monsters.gd:42`）：
```
	var kinds := ["SNAKE_SHOOTER", "JUMPER", "LASER", "MINI_CENTIPEDE"]
```
改成：
```
	var kinds := ["SNAKE_SHOOTER", "JUMPER", "LASER", "MINI_CENTIPEDE", "DASHER"]
```

- [ ] **Step 2: 更新文件头注释的怪种数（4 → 5）**

找到（`tools/test_new_monsters.gd:2`）：
```
# 回归：4 种新怪（SNAKE_SHOOTER / JUMPER / LASER / MINI_CENTIPEDE）
```
改成：
```
# 回归：5 种新怪（SNAKE_SHOOTER / JUMPER / LASER / MINI_CENTIPEDE / DASHER）
```

- [ ] **Step 3: 更新结尾报告行**

找到（`tools/test_new_monsters.gd:105`）：
```
	report.append("ok: 4 怪 update_ai/update_death/_draw 跑完无崩溃")
```
改成：
```
	report.append("ok: 5 怪 update_ai/update_death/_draw 跑完无崩溃")
```

- [ ] **Step 4: Commit**

```bash
git add tools/test_new_monsters.gd
git commit -m "test(monsters): 回归脚本加 DASHER"
```

---

### Task 9: excel 同步 + headless 回归验证

`sync_json_to_excel.py` 从 monsters.json 回写 monsters.xlsx（只写 MONSTER_HEADERS 列，扩展字段如 trigger_range/name_cn 等是 json-only，与 MINI_CENTIPEDE 同模式，不进 xlsx）。这步防下次误跑 export_config.py 丢条目。

**Files:**
- Regenerate: `config/excel/monsters.xlsx`

- [ ] **Step 1: 回写 excel**

Run: `python tools/sync_json_to_excel.py`
Expected: 打印 `Excel: .../config/excel/monsters.xlsx`（及其它 sheet）。

- [ ] **Step 2: 确认 excel 含 DASHER 行**

Run: `python -c "from openpyxl import load_workbook;ws=load_workbook('config/excel/monsters.xlsx').active;rows=list(ws.iter_rows(values_only=True));print('rows',len(rows)-1);print([r[0] for r in rows if r[0]=='DASHER'])"`
Expected: `rows 15` 和 `['DASHER']`

- [ ] **Step 3: headless 跑回归脚本**

Run: `godot --headless res://tools/test_new_monsters.tscn --path D:/workspace/rzz_godot_newtry`
Expected: 末行打印 `NEW_MONSTERS_OK`，report 行里含 `ok: config DASHER hp=10 pattern=` 和 `ok: setup DASHER alive=True ...`，无 GDScript 报错。

- [ ] **Step 4: 若报错「could not load Bat.png」等导入问题，重跑 `godot --headless --import --path D:/workspace/rzz_godot_newtry` 再回 Step 3**

- [ ] **Step 5: Commit**

```bash
git add config/excel/monsters.xlsx
git commit -m "chore(excel): sync monsters.xlsx 从 json（含 DASHER）"
```

---

### Task 10: 进游戏手动验证

headless 脚本只验不崩 + 配置加载；行为正确性（蓄力变红→锁定方向冲刺→命中一次→恢复）必须进游戏肉眼看。

- [ ] **Step 1: 启动游戏到第4关（stage_index 3）**

用 godot MCP `run_project` 或 `godot --path D:/workspace/rzz_godot_newtry` 开编辑器运行。跳到第4关（或调试直接加载到该关）。

- [ ] **Step 2: 观察冲刺怪外观**

确认 bat 外观正常：idle 静态 hover，移动时 6 帧飞行动画，朝向翻转正确。

- [ ] **Step 3: 观察蓄力→冲刺行为**

把角色移到冲刺怪 trigger_range(180px) 内：
1. 怪停下，0.6s 内从原色渐变变红
2. 朝触发瞬间玩家所在方向直线冲刺
3. 冲刺路径上撞到玩家 → 掉血（心数制：0.5 心），本轮只掉一次
4. 命中后继续冲完固定距离（不即停、不拐弯）
5. 停 0.5s 恢复（变回原色）→ 1.5s 冷却 → 可再触发

- [ ] **Step 4: 横向走位躲闪验证**

蓄力锁定方向后横向移动，确认冲刺不追踪、能躲开（不会被转向跟过来）。

- [ ] **Step 5: 切英文确认名字**

暂停菜单切 English，确认该怪名显示 "Dasher"（非中文残留、非 `[...]` 占位）。

- [ ] **Step 6: 无需 commit（纯验证步）**

---

## Self-Review 结果

**1. Spec 覆盖：**
- 状态机 IDLE/WINDUP/DASH/RECOVER → Task 4 `_update_dasher` 四 match 分支 ✓
- 蓄力变红 → Task 5 tint 分支 ✓
- 锁定方向+冲固定距离+每轮命中一次+不停 → Task 4 state 2 ✓
- cooldown → Task 4 state 0/3 ✓
- bat atlas（Aseprite 方式，CLI 不可用走手搓兜底）→ Task 1 ✓
- monsters.json DASHER 条目 + 扩展字段 + name 双语 → Task 2 ✓
- spawner counts 两处 → Task 6 ✓
- stages.json unlock_at_stage=3 → Task 7（stage_index 3 起）✓
- test_new_monsters.gd 回归 → Task 8 ✓
- excel 同步 → Task 9 ✓
- 数值（hp=10/speed=70/windup 0.6/dash 320/距离 220/recover 0.5/cooldown 1.5/trigger 180）→ Task 2 json + Task 3 字段 ✓

**2. Placeholder 扫描：** 无 TBD/TODO；Task 7 Step 2/3 的 stages.json 改法给出了定位方法 + 校验命令兜底（display_name_en 定位唯一），可执行。Task 1 atlas 脚本完整可跑。

**3. 类型/命名一致性：** `_dasher_state`/`_dasher_timer`/`_dash_dir`/`_has_hit_this_dash`/`_dasher_cooldown_t`/`_dasher_trigger_range`/`_dasher_windup_sec`/`_dasher_dash_speed`/`_dasher_dash_distance`/`_dasher_recover_sec`/`_dasher_cooldown_sec` 在 Task 3 声明、Task 4 使用、Task 5 使用 `_dasher_timer`/`_dasher_windup_sec`，命名一致。json 字段名 `trigger_range`/`windup_sec`/`dash_speed`/`dash_distance`/`recover_sec`/`cooldown_sec`（Task 2）与 setup 读取的 `stats.get(...)` key（Task 3）逐字一致。`_update_dasher(delta, player, _battle)` 签名与 JUMPER/LASER 一致。`_play_anim`/`SpriteHelper.ANIM_*`/`GameConfig.scale_world`/`slow_pct_active`/`paralyze_timer`/`petrify_timer`/`player.take_damage`/`player.get_effective_radius` 均为既有 API。

**已知次要行为（设计文档已批注「最高优先级」）：** DASHER 蓄力期间被石化/麻痹命中时，因 windup tint 分支在 petrify/paralyze 之前 return，怪物仍显红而非灰/金。这是 spec 批准的行为，不修。
