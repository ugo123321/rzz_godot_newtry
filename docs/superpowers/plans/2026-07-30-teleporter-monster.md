# 瞬移怪（TELEPORTER）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增瞬移怪 `TELEPORTER`，外观用 Necromancer、攻击用 attack02，只瞬移不走路，现身发 1 发暗紫魔法弹，2s 后消失，1.5s 后在屏幕边缘重现身，循环。

**Architecture:** 三块新增：(1) Python 脚本生成 Necromancer 精灵图集（atlas json+png）；(2) `enemy_arrow.gd` 新增 `PIXEL_BOLT` 像素绘制；(3) `monster.gd` 新增 4 状态瞬移状态机 + 运行时从 death 帧派生 teleport_in/out 动画 + GONE 免疫门控。配置走 monsters.json/stages.json（json 权威源）+ sync 回写 xlsx。回归用 `tools/test_new_monsters` headless 场景。

**Tech Stack:** Godot 4（GDScript）、Python+PIL（atlas 生成）、config/json 权威 + sync_json_to_excel 回写。

**Spec:** `docs/superpowers/specs/2026-07-30-teleporter-monster-design.md`

---

## 文件结构

- **Create** `tools/build_necromancer_atlas.py` — PIL 脚本：读 6 张条带 PNG → 生成 `sheets/Necromancer.png` + `json/Necromancer.json`
- **Create** `assets/Characters/atlases/json/Necromancer.json`（脚本产物）
- **Create** `assets/Characters/atlases/sheets/Necromancer.png`（脚本产物）
- **Modify** `scripts/entities/enemy_arrow.gd` — 新增 `DrawStyle.PIXEL_BOLT` + `_draw_pixel_bolt()` + `_ready` 分支
- **Modify** `scripts/entities/monster.gd` — TELEPORTER 常量/状态机/选位/动画派生/门控
- **Modify** `scripts/core/monster_spawner.gd` — 两处 counts dict 加 TELEPORTER
- **Modify** `config/json/monsters.json` — 新增 TELEPORTER 条目
- **Modify** `config/json/stages.json` — 若干关加 `teleporter` 计数
- **Modify** `tools/test_new_monsters.gd` — 把 TELEPORTER 加入回归 kinds 列表

---

### Task 1: 生成 Necromancer 精灵图集

**Files:**
- Create: `tools/build_necromancer_atlas.py`
- Create: `assets/Characters/atlases/json/Necromancer.json`（脚本生成）
- Create: `assets/Characters/atlases/sheets/Necromancer.png`（脚本生成）

- [ ] **Step 1: 写 atlas 生成脚本**

创建 `tools/build_necromancer_atlas.py`：

```python
"""生成 Necromancer 角色图集（atlas json + 合并 sheet png）。
读取 assets/Characters/Characters(100x100)/Necromancer/Necromancer/ 下的条带 PNG，
按"每动画一行"拼成单张 sheet，并输出 Aseprite 导出格式 json 供
EffectHelper._load_character_atlas_frames 加载。

运行：python tools/build_necromancer_atlas.py
产物：
  assets/Characters/atlases/sheets/Necromancer.png
  assets/Characters/atlases/json/Necromancer.json
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "assets/Characters/Characters(100x100)/Necromancer/Necromancer"
OUT_SHEET = ROOT / "assets/Characters/atlases/sheets/Necromancer.png"
OUT_JSON = ROOT / "assets/Characters/atlases/json/Necromancer.json"

FRAME = 100  # 100x100

# (tag_name, 源文件名, 帧数)
ANIMS = [
    ("Idle",     "Necromancer_Idle.png",     6),
    ("Walk",     "Necromancer_Walk.png",     6),
    ("Attack",   "Necromancer_Attack02.png", 10),
    ("Hurt",     "Necromancer_Hurt.png",     4),
    ("Death",    "Necromancer_DEATH.png",     9),
    ("Attack01", "Necromancer_Attack01.png",  9),
]


def main() -> int:
    if not SRC_DIR.is_dir():
        raise SystemExit(f"源目录不存在: {SRC_DIR}")

    # 1) 读每张条带，按声明的帧数切片（每帧 FRAME 宽）
    rows: list[list[Image.Image]] = []
    for tag, fname, count in ANIMS:
        path = SRC_DIR / fname
        if not path.exists():
            raise SystemExit(f"缺少素材: {path}")
        sheet = Image.open(path).convert("RGBA")
        if sheet.height < FRAME:
            raise SystemExit(f"{fname} 高度 {sheet.height} < {FRAME}")
        frames: list[Image.Image] = []
        for i in range(count):
            x = i * FRAME
            if x + FRAME > sheet.width:
                raise SystemExit(f"{fname} 第 {i} 帧越界 (sheet宽={sheet.width})")
            frames.append(sheet.crop((x, 0, x + FRAME, FRAME)))
        rows.append(frames)

    # 2) 拼成单张 sheet：每动画一行，宽 = 最大帧数 * FRAME
    cols = max(len(r) for r in rows)
    sheet_w = cols * FRAME
    sheet_h = len(rows) * FRAME
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    frame_list: list[dict] = []  # 行优先顺序的 Aseprite frame 描述
    frame_tags: list[dict] = []
    idx = 0
    for row_idx, row in enumerate(rows):
        tag_name = ANIMS[row_idx][0]
        start_idx = idx
        for col_idx, frame_img in enumerate(row):
            x = col_idx * FRAME
            y = row_idx * FRAME
            sheet.paste(frame_img, (x, y))
            frame_list.append({
                "filename": f"Necromancer {idx}.aseprite",
                "frame": {"x": x, "y": y, "w": FRAME, "h": FRAME},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": FRAME, "h": FRAME},
                "sourceSize": {"w": FRAME, "h": FRAME},
                "duration": 100,
            })
            idx += 1
        frame_tags.append({"name": tag_name, "from": start_idx, "to": idx - 1})

    OUT_SHEET.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_SHEET)

    doc = {
        "frames": frame_list,
        "meta": {
            "image": OUT_SHEET.name,
            "size": {"w": sheet_w, "h": sheet_h},
            "frameTags": frame_tags,
        },
    }
    OUT_JSON.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"sheet: {OUT_SHEET} ({sheet_w}x{sheet_h})")
    print(f"json : {OUT_JSON} ({len(frame_list)} frames, {len(frame_tags)} tags)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: 运行脚本生成产物**

Run: `python tools/build_necromancer_atlas.py`
Expected output:
```
sheet: D:\workspace\rzz_godot_newtry\assets\Characters\atlases\sheets\Necromancer.png (1000x600)
json : D:\workspace\rzz_godot_newtry\assets\Characters\atlases\json\Necromancer.json (44 frames, 6 tags)
```

- [ ] **Step 3: 校验产物结构**

Run: `python -c "import json; d=json.load(open('assets/Characters/atlases/json/Necromancer.json',encoding='utf-8')); print(len(d['frames']), [t['name'] for t in d['meta']['frameTags']])"`
Expected: `44 ['Idle', 'Walk', 'Attack', 'Hurt', 'Death', 'Attack01']`

Run: `python -c "from PIL import Image; im=Image.open('assets/Characters/atlases/sheets/Necromancer.png'); print(im.size)"`
Expected: `(1000, 600)`

- [ ] **Step 4: 提交**

```bash
git add tools/build_necromancer_atlas.py assets/Characters/atlases/json/Necromancer.json assets/Characters/atlases/sheets/Necromancer.png
git commit -m "feat(assets): 生成 Necromancer 精灵图集 atlas"
```

> 注：新 png 需在 Godot 编辑器打开一次以生成 `.import`/ctex。后续 Task 验证前先开一次编辑器。

---

### Task 2: enemy_arrow 新增 PIXEL_BOLT 暗紫魔法弹

**Files:**
- Modify: `scripts/entities/enemy_arrow.gd:5` (枚举)
- Modify: `scripts/entities/enemy_arrow.gd:279-287` (`_draw` match)
- Modify: `scripts/entities/enemy_arrow.gd:422-437` (`_ready` 分支)
- Add: `_draw_pixel_bolt()` 函数（紧随 `_draw_pixel_snake` 之后）

- [ ] **Step 1: 给 DrawStyle 枚举加 PIXEL_BOLT**

`scripts/entities/enemy_arrow.gd:5` 当前：
```gdscript
enum DrawStyle { SPRITE, PIXEL_ORB, PIXEL_SQUARE, PIXEL_SNAKE }
```
改为：
```gdscript
enum DrawStyle { SPRITE, PIXEL_ORB, PIXEL_SQUARE, PIXEL_SNAKE, PIXEL_BOLT }
```

- [ ] **Step 2: 给 `_draw()` match 加分支**

`scripts/entities/enemy_arrow.gd:279` 当前：
```gdscript
func _draw() -> void:
	match _draw_style:
		DrawStyle.PIXEL_ORB:
			_draw_pixel_orb()
		DrawStyle.PIXEL_SQUARE:
			_draw_pixel_square()
		DrawStyle.PIXEL_SNAKE:
			_draw_pixel_snake()
```
在 `DrawStyle.PIXEL_SNAKE` 分支后追加：
```gdscript
		DrawStyle.PIXEL_BOLT:
			_draw_pixel_bolt()
```

- [ ] **Step 3: 在 `_ready()` 加 effect_key 分支**

`scripts/entities/enemy_arrow.gd:433-437` 当前（PIXEL_SNAKE 分支）：
```gdscript
	if _effect_key == "enemy_snake_bullet":
		_draw_style = DrawStyle.PIXEL_SNAKE
		set_process(true)
		queue_redraw()
		return
```
紧随其后追加：
```gdscript
	if _effect_key == "enemy_teleport_bolt":
		_draw_style = DrawStyle.PIXEL_BOLT
		set_process(true)
		queue_redraw()
		return
```

- [ ] **Step 4: 写 `_draw_pixel_bolt()`**

在 `_draw_pixel_snake()` 函数体结束之后（`scripts/entities/enemy_arrow.gd:378` 之后）追加：

```gdscript

# ------ 像素暗紫魔法弹（teleporter）— 死灵系光球 + 尾迹 ------
# self.rotation 已在 _create 里设为速度方向，所以 local +x = 前进方向，-x = 尾部。
func _draw_pixel_bolt() -> void:
	var base := _tint if _tint != Color.WHITE else Color("#6a3a98")
	var palette := _pixel_palette(base)
	var px := _pixel_size()
	var rb := float(ORB_RADIUS_BLOCKS)
	var flicker := int(Time.get_ticks_msec() / FLICKER_INTERVAL_MS) % 2 == 0
	# 外发光晕（两层圆晕）
	var halo := base
	halo.a = 0.28
	draw_circle(Vector2.ZERO, (rb + 1.6) * px, halo)
	halo.a = 0.14
	draw_circle(Vector2.ZERO, (rb + 3.0) * px, halo)
	# 尾迹：沿 -x 方向 3 节递减半径/alpha 小圆，模拟运动残影
	for i in range(3):
		var t := float(i + 1) / 3.0
		var tx := lerpf(-1.5, -5.5, t) * px
		var trad := lerpf(3.0, 1.2, t) * px
		var tcol := palette[1].lerp(palette[0], t)
		tcol.a = lerpf(0.55, 0.18, t)
		draw_circle(Vector2(tx, 0.0), trad, tcol)
	# 主体：每方块按到中心距离取色
	for by in range(-int(rb), int(rb) + 1):
		for bx in range(-int(rb), int(rb) + 1):
			var d := sqrt(float(bx * bx + by * by))
			if d > rb + 0.3:
				continue
			var ratio := d / rb
			var col := _orb_block_color(ratio, flicker and ratio > 0.5, palette)
			draw_rect(Rect2(bx * px - px * 0.5, by * px - px * 0.5, px, px), col)
	# 核心 2x2 高光
	var core: Color = palette[4] if not flicker else palette[4].lerp(Color.WHITE, 0.5)
	draw_rect(Rect2(-px, -px, px, px), core)
	draw_rect(Rect2(0.0, -px, px, px), core)
	draw_rect(Rect2(-px, 0.0, px, px), core)
	draw_rect(Rect2(0.0, 0.0, px, px), core)
```

- [ ] **Step 5: headless 验证 PIXEL_BOLT 不崩**

在 `tools/test_new_monsters.gd:115`（radial 那行）之后追加一行 TELEPORTER 子弹验证：
```gdscript
	EnemyArrow.spawn(battle, Vector2(100, 100), Vector2(300, 300), 10, 140.0, "enemy_teleport_bolt", Color("#6a3a98"))
```
（这行先只验证 spawn 不崩；Task 7 会把 TELEPORTER 怪本体也加入 kinds。）

Run: `godot --headless res://tools/test_new_monsters.tscn`
Expected: 末行打印 `NEW_MONSTERS_OK`，且无 GDScript error。

- [ ] **Step 6: 提交**

```bash
git add scripts/entities/enemy_arrow.gd tools/test_new_monsters.gd
git commit -m "feat(enemy_arrow): 新增 PIXEL_BOLT 暗紫魔法弹（teleporter 子弹）"
```

---

### Task 3: monster.gd 新增 TELEPORTER 状态机

**Files:**
- Modify: `scripts/entities/monster.gd`（新增常量、状态字段、`_apply_sprite` 派生、`is_combat_targetable`、`_resolve_take_damage` 门控、`update_ai` 分支、`_update_teleporter`、`_pick_teleport_pos`、`_build_teleport_anims`、`_draw` 预警圈）

- [ ] **Step 1: 加 TELEPORTER 常量与状态字段**

在 `scripts/entities/monster.gd` 的 DASHER 常量块之后（约 `:157` `_dasher_cooldown_sec := 1.5` 之后、`MINI_CENTIPEDE` 块之前 `:159`）插入：

```gdscript
# === TELEPORTER 瞬移怪状态机 ===
# 0=APPEAR(现身,播 teleport_in) 1=VISIBLE(发1发子弹+播attack,停2s)
# 2=DISAPPEAR(播 teleport_out) 3=GONE(隐形免疫1.5s,末尾画预警圈,再选位→APPEAR)
var _teleport_state := 0
var _teleport_timer := 0.0
var _teleport_next_pos := Vector2.ZERO
const TELEPORT_APPEAR_SEC := 0.35
const TELEPORT_VISIBLE_SEC := 2.0
const TELEPORT_DISAPPEAR_SEC := 0.35
const TELEPORT_GONE_SEC := 1.5
const TELEPORT_EDGE_MARGIN := 60.0
const TELEPORT_MIN_PLAYER_DIST := 160.0
const TELEPORT_TELEGRAPH_SEC := 0.30
const ANIM_TELEPORT_IN := "teleport_in"
const ANIM_TELEPORT_OUT := "teleport_out"
```

- [ ] **Step 2: `_apply_sprite` 末尾派生 teleport 动画**

`scripts/entities/monster.gd:329` 当前 `_apply_sprite()` 末尾：
```gdscript
	if not anim_sprite.animation_finished.is_connected(_on_animation_finished):
		anim_sprite.animation_finished.connect(_on_animation_finished)
```
在其后追加：
```gdscript
	if kind_id == "TELEPORTER":
		_build_teleport_anims(anim_sprite)
```

- [ ] **Step 3: 写 `_build_teleport_anims`**

在 `_apply_sprite()` 函数之后（`_on_animation_finished` 之前，约 `:332`）插入：

```gdscript
# TELEPORTER：从 death 动画前 5 帧派生 teleport_out(正放)/teleport_in(倒放)。
# 在缓存 SpriteFrames 对象上幂等添加，多实例共享安全。
func _build_teleport_anims(anim_sprite: AnimatedSprite2D) -> void:
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	var frames := anim_sprite.sprite_frames
	if not frames.has_animation(SpriteHelper.ANIM_DEATH):
		return
	var n := frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if n < 5:
		return
	if not frames.has_animation(ANIM_TELEPORT_OUT):
		frames.add_animation(ANIM_TELEPORT_OUT)
		for i in range(5):
			frames.add_frame(
				ANIM_TELEPORT_OUT,
				frames.get_frame_texture(SpriteHelper.ANIM_DEATH, i),
				frames.get_frame_duration(SpriteHelper.ANIM_DEATH, i)
			)
		frames.set_animation_speed(ANIM_TELEPORT_OUT, 14.0)
		frames.set_animation_loop(ANIM_TELEPORT_OUT, false)
	if not frames.has_animation(ANIM_TELEPORT_IN):
		frames.add_animation(ANIM_TELEPORT_IN)
		for i in range(4, -1, -1):
			frames.add_frame(
				ANIM_TELEPORT_IN,
				frames.get_frame_texture(SpriteHelper.ANIM_DEATH, i),
				frames.get_frame_duration(SpriteHelper.ANIM_DEATH, i)
			)
		frames.set_animation_speed(ANIM_TELEPORT_IN, 14.0)
		frames.set_animation_loop(ANIM_TELEPORT_IN, false)
```

- [ ] **Step 4: `is_combat_targetable` 加 GONE 门控**

`scripts/entities/monster.gd:407-415` 当前：
```gdscript
func is_combat_targetable() -> bool:
	# JUMPER 起跳后离屏，不可被攻击
	if _jumper_state == 2:
		return false
	# MINI_CENTIPEDE 头部纯驱动（画 12 节 + 状态机）；伤害目标只有 12 个节段，
	# 节段 0 已在头部位置，头部不再独立可击，避免一次命中双重扣血。
	if kind_id == "MINI_CENTIPEDE":
		return false
	return alive and not dying and spawn_lock_timer <= 0.0
```
在 JUMPER 判断之后追加 TELEPORTER GONE 判断：
```gdscript
	# TELEPORTER 隐形期间不可选中
	if kind_id == "TELEPORTER" and _teleport_state == 3:
		return false
```

- [ ] **Step 5: `_resolve_take_damage` 加 GONE 免疫兜底**

`scripts/entities/monster.gd:471-473` 当前：
```gdscript
func _resolve_take_damage(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if not alive or dying:
		return {"damage": 0, "is_crit": false}
```
改为：
```gdscript
func _resolve_take_damage(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if not alive or dying:
		return {"damage": 0, "is_crit": false}
	# TELEPORTER GONE 隐形期间免疫（防止接触/范围伤害穿透）
	if kind_id == "TELEPORTER" and _teleport_state == 3:
		return {"damage": 0, "is_crit": false}
```

- [ ] **Step 6: `update_ai` 加 TELEPORTER 分支**

`scripts/entities/monster.gd:732-734` 当前：
```gdscript
	if kind_id == "DASHER":
		_update_dasher(delta, player, battle)
		return
```
紧随其后追加：
```gdscript
	if kind_id == "TELEPORTER":
		_update_teleporter(delta, player, battle)
		return
```

- [ ] **Step 7: 写 `_update_teleporter` 状态机**

在 `_update_dasher()` 函数之后（约 `:970` `_apply_laser_damage` 之前）插入：

```gdscript
# ===================== TELEPORTER 瞬移怪 =====================
# APPEAR(现身,teleport_in) → VISIBLE(发1发子弹+attack,停2s)
# → DISAPPEAR(teleport_out) → GONE(隐形免疫1.5s,末尾画预警圈,再选位→APPEAR)
func _update_teleporter(delta: float, player: BattlePlayer, battle: Node) -> void:
	if player == null:
		return
	_teleport_timer -= delta
	match _teleport_state:
		0:  # APPEAR
			if _teleport_timer <= 0.0:
				_teleport_state = 1
				_teleport_timer = TELEPORT_VISIBLE_SEC
				# 进入 VISIBLE 立即向玩家发射 1 发暗紫魔法弹
				facing = 1.0 if player.global_position.x >= global_position.x else -1.0
				var anim_sprite := _get_sprite()
				if anim_sprite:
					anim_sprite.flip_h = facing < 0
				_play_anim(SpriteHelper.ANIM_ATTACK, true)
				if battle and battle.has_method("spawn_arrow"):
					battle.spawn_arrow(
						global_position,
						player.global_position,
						attack,
						arrow_speed,
						projectile_effect,
						sprite_tint
					)
		1:  # VISIBLE 停留
			if _teleport_timer <= 0.0:
				_teleport_state = 2
				_teleport_timer = TELEPORT_DISAPPEAR_SEC
				_play_anim(ANIM_TELEPORT_OUT, true)
		2:  # DISAPPEAR
			if _teleport_timer <= 0.0:
				_teleport_state = 3
				_teleport_timer = TELEPORT_GONE_SEC
				modulate.a = 0.0
				_teleport_next_pos = _pick_teleport_pos(battle, player)
		3:  # GONE 隐形免疫；末尾画预警圈
			if _teleport_timer <= 0.0:
				global_position = _teleport_next_pos
				modulate.a = 1.0
				_teleport_state = 0
				_teleport_timer = TELEPORT_APPEAR_SEC
				_play_anim(ANIM_TELEPORT_IN, true)
			else:
				queue_redraw()  # 维持预警圈重绘
```

- [ ] **Step 8: 写 `_pick_teleport_pos`**

在 `_update_teleporter` 之后插入：

```gdscript
# 屏幕边缘随机选位：4 边中随机一边，沿边内缩 EDGE_MARGIN 处取点；
# 拒绝距玩家 < MIN_PLAYER_DIST 的点；失败兜底屏幕中上部。
func _pick_teleport_pos(battle: Node, player: BattlePlayer) -> Vector2:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var m := TELEPORT_EDGE_MARGIN
	var safe := player.global_position if player != null else Vector2(w * 0.5, h * 0.5)
	for _i in range(20):
		var edge := randi() % 4
		var pos := Vector2.ZERO
		match edge:
			0: pos = Vector2(MathUtils.rand_range(m, w - m), m)
			1: pos = Vector2(MathUtils.rand_range(m, w - m), h - m)
			2: pos = Vector2(m, MathUtils.rand_range(m, h - m))
			_: pos = Vector2(w - m, MathUtils.rand_range(m, h - m))
		if MathUtils.dist(pos, safe) < TELEPORT_MIN_PLAYER_DIST:
			continue
		if battle and battle.has_method("is_move_blocked_at") and battle.is_move_blocked_at(pos, hitbox_radius):
			continue
		return pos
	return Vector2(w * 0.5, h * 0.25)
```

- [ ] **Step 9: `begin_spawn` 兼容 TELEPORTER**

`scripts/entities/monster.gd:281-300` 的 `begin_spawn` 通用路径会设 `modulate.a=0` + spawn tween。TELEPORTER 首次出生应走 APPEAR 而非通用 spawn tween。在 `begin_spawn` 开头 MINI_CENTIPEDE 早退之后插入：

当前 `:282-289`：
```gdscript
	if kind_id == "MINI_CENTIPEDE":
		spawn_lock_timer = 0.0
		attack_timer = attack_interval
		modulate.a = 1.0
		scale = target_scale
		_centi_phase = Phase.REPOSITION
		_centi_repos_timer = 0.3
		return
```
紧随其后追加：
```gdscript
	if kind_id == "TELEPORTER":
		spawn_lock_timer = 0.0
		attack_timer = attack_interval
		modulate.a = 1.0
		scale = target_scale
		_teleport_state = 0
		_teleport_timer = TELEPORT_APPEAR_SEC
		_play_anim(ANIM_TELEPORT_IN, true)
		return
```

- [ ] **Step 10: `_draw` 加 GONE 末尾预警圈**

`scripts/entities/monster.gd:1249` `_draw()` 开头：
```gdscript
func _draw() -> void:
	if _code_drawn:
		_draw_mini_centipede()
	_draw_theme_aura()
```
在 `_draw_theme_aura()` 之后插入：
```gdscript
	if kind_id == "TELEPORTER" and _teleport_state == 3 and _teleport_timer <= TELEPORT_TELEGRAPH_SEC:
		# GONE 末尾：在将出现点画紫色脉动预警圈
		var local := to_local(_teleport_next_pos)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.020)
		var r := GameConfig.scale_world(hitbox_radius + 6.0)
		var c := Color("#9a5ad0")
		c.a = 0.30 + 0.30 * pulse
		draw_circle(local, r, c)
		c.a = 0.55
		draw_arc(local, r, 0.0, TAU, 28, c, GameConfig.scale_world(2.0))
```

- [ ] **Step 11: headless 回归验证 TELEPORTER 不崩**

（Task 7 会正式把 TELEPORTER 加入 kinds；此处先用临时一行验证。）

在 `tools/test_new_monsters.gd:38` 的 `kinds` 列表末尾加 `"TELEPORTER"`：
```gdscript
	var kinds := ["SNAKE_SHOOTER", "JUMPER", "LASER", "MINI_CENTIPEDE", "DASHER", "TELEPORTER"]
```

Run: `godot --headless res://tools/test_new_monsters.tscn`
Expected: 报告里出现 `ok: setup TELEPORTER ...`、`ok: 6 怪 ...`，末行 `NEW_MONSTERS_OK`，无 GDScript error。

> 若报 `attempt to call function 'spawn_arrow' on a null instance`：headless battle 替身 `BATTLE_SRC` 缺 `spawn_arrow`。补一行到 `BATTLE_SRC`：`func spawn_arrow(_f,_t,_d,_s,_e,_c): pass`（Step 12 处理）。

- [ ] **Step 12: 给 headless battle 替身补 `spawn_arrow` 桩**

`tools/test_new_monsters.gd:19-27` 的 `BATTLE_SRC`：
```gdscript
const BATTLE_SRC := """
extends Node2D
var player
var projectiles
var ground_effects
var particles
var combat
var spawner
var monster_container
var state := 0
func is_in_bounds(p): return p.x >= -50 and p.y >= -50 and p.x <= 770 and p.y <= 1330
func shake_camera(_a, _b): pass
func is_bullet_blocked_at(_p): return false
"""
```
在 `func is_bullet_blocked_at(_p): return false` 之后追加：
```gdscript
func spawn_arrow(_f, _t, _d, _s, _e, _c): pass
```

Run: `godot --headless res://tools/test_new_monsters.tscn`
Expected: `NEW_MONSTERS_OK`，TELEPORTER 行无 error。

- [ ] **Step 13: 提交**

```bash
git add scripts/entities/monster.gd tools/test_new_monsters.gd
git commit -m "feat(monster): 新增 TELEPORTER 瞬移怪状态机 + teleport 动画派生"
```

---

### Task 4: monster_spawner 接入 TELEPORTER

**Files:**
- Modify: `scripts/core/monster_spawner.gd:169-185` (`_spawn_stage_content` counts dict)
- Modify: `scripts/core/monster_spawner.gd:108-124` (`_refill_queue_for_infinite` counts dict)

- [ ] **Step 1: `_spawn_stage_content` counts dict 加 TELEPORTER**

`scripts/core/monster_spawner.gd:184` 当前：
```gdscript
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
	}
	_init_clusters(battle)
```
改为：
```gdscript
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
		"TELEPORTER": maxi(0, int(stage.get("teleporter", 0))),
	}
	_init_clusters(battle)
```

- [ ] **Step 2: `_refill_queue_for_infinite` counts dict 加 TELEPORTER**

`scripts/core/monster_spawner.gd:123` 当前：
```gdscript
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
	}
	var has_any := false
```
改为：
```gdscript
		"DASHER": maxi(0, int(stage.get("dasher", 0))),
		"TELEPORTER": maxi(0, int(stage.get("teleporter", 0))),
	}
	var has_any := false
```

- [ ] **Step 3: 提交**

```bash
git add scripts/core/monster_spawner.gd
git commit -m "feat(spawner): 接入 TELEPORTER 计数（stage.teleporter）"
```

---

### Task 5: monsters.json 新增 TELEPORTER 配置

**Files:**
- Modify: `config/json/monsters.json`（追加一条 TELEPORTER，spawn_order=16）

- [ ] **Step 1: 追加 TELEPORTER 条目**

在 `config/json/monsters.json` 数组末尾（DASHER 条目之后）追加：
```json
,
{
 "kind_id": "TELEPORTER",
 "spawn_order": 16,
 "unlock_at_stage": 6,
 "name_cn": "瞬移怪",
 "hp": 80,
 "def": 2,
 "attack": 12,
 "attack_interval": 2.0,
 "size": 12,
 "speed": 0,
 "color_hex": "#5a3a7a",
 "grade": "A",
 "can_move": 0,
 "attack_range": 320,
 "arrow_speed": 140,
 "ranged": 1,
 "ki_drain_on_hit": 0,
 "max_split_tier": 0,
 "split_count": 0,
 "exp_reward": 3,
 "character_folder": "Necromancer",
 "sprite_prefix": "Necromancer",
 "projectile_folder": "",
 "attack_pattern": "",
 "projectile_effect": "enemy_teleport_bolt",
 "spread_count": 0,
 "spread_angle_deg": 0,
 "bounce_count": 0,
 "sprite_tint_hex": "",
 "name_en": "Blink Mage"
}
```

- [ ] **Step 2: 校验 JSON 合法 + GameConfig 可读**

Run: `python -c "import json,io; d=json.load(io.open('config/json/monsters.json',encoding='utf-8')); t=[m for m in d if m['kind_id']=='TELEPORTER'][0]; print('ok', t['name_cn'], t['name_en'], 'ranged=',t['ranged'],'eff=',t['projectile_effect'],'folder=',t['character_folder'])"`
Expected: `ok 瞬移怪 Blink Mage ranged= 1 eff= enemy_teleport_bolt folder= Necromancer`

- [ ] **Step 3: 提交**

```bash
git add config/json/monsters.json
git commit -m "feat(config): 新增 TELEPORTER 怪物配置"
```

---

### Task 6: stages.json 给若干关加 teleporter 计数

**Files:**
- Modify: `config/json/stages.json`（给 stage 6 / 8 / 11 / 14 各加 `"teleporter": 1`）

- [ ] **Step 1: 给 4 个关卡加 teleporter 计数**

用 Python 脚本就地修改（避免手编 JSON 逗号/编码出错）：

Run:
```bash
python - <<'PY'
import json, io
p = 'config/json/stages.json'
d = json.load(io.open(p, encoding='utf-8'))
for s in d:
    if s['stage_index'] in (6, 8, 11, 14):
        s['teleporter'] = 1
io.open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=1))
print('done')
PY
```
Expected: `done`

- [ ] **Step 2: 校验**

Run: `python -c "import json,io; d=json.load(io.open('config/json/stages.json',encoding='utf-8')); print([(s['stage_index'],s.get('teleporter',0)) for s in d if s.get('teleporter',0)])"`
Expected: `[(6, 1), (8, 1), (11, 1), (14, 1)]`

- [ ] **Step 3: 提交**

```bash
git add config/json/stages.json
git commit -m "feat(stages): stage 6/8/11/14 加入 teleporter 计数"
```

---

### Task 7: sync xlsx + 端到端验证

**Files:**
- Modify: `config/excel/monsters.xlsx`（sync 写回）
- Modify: `config/excel/stages.xlsx`（sync 写回）

- [ ] **Step 1: 跑 sync 回写 xlsx**

Run: `python tools/sync_json_to_excel.py`
Expected: 无报错，monsters.xlsx 含 TELEPORTER 行（MONSTER_HEADERS 列）、stages.xlsx 重写完成。kind 专属时序字段为 json-only，不入 xlsx，符合流程。

- [ ] **Step 2: 打开 Godot 编辑器一次，让 Necromancer.png 生成 .import**

打开 Godot 编辑器 → 编辑器会扫描 `assets/Characters/atlases/sheets/Necromancer.png` 并生成 `.import` + ctex。确认 `assets/Characters/atlases/sheets/Necromancer.png.import` 出现。

- [ ] **Step 3: headless 回归**

Run: `godot --headless res://tools/test_new_monsters.tscn`
Expected: 末行 `NEW_MONSTERS_OK`，TELEPORTER 行 `ok: setup TELEPORTER alive=true hp=80/80 code_drawn=false`，6 怪跑完无崩溃。

- [ ] **Step 4: 进游戏端到端验证**

运行游戏到 stage 6+（或调试直接 `append_stage` 跳到含 teleporter 的关）。观察：
1. 瞬移怪在屏幕边缘现身，播放 `teleport_in`（死亡帧倒放）。
2. 现身后立即向玩家发射一发暗紫魔法弹（`PIXEL_BOLT`：光球 + 尾迹 + 闪烁 + 外发光）。
3. 子弹命中玩家掉血 + hit_spark。
4. 2 秒后怪物播放 `teleport_out`（死亡帧正放）消失。
5. GONE 期间（1.5s）怪物隐形、不可选中、不受伤；末尾 0.3s 在将出现点显示紫色脉动预警圈。
6. 在新屏幕边缘点重现身，循环。
7. VISIBLE 期间可被玩家击杀，死亡正常走 death 淡出。

- [ ] **Step 5: 提交 xlsx 产物**

```bash
git add config/excel/monsters.xlsx config/excel/stages.xlsx
git commit -m "chore(excel): sync monsters/stages xlsx（含 TELEPORTER）"
```

---

## Self-Review 记录

- **Spec 覆盖**：状态机（Task 3 Step 7）、选位（Step 8）、teleport 动画派生（Step 3）、atlas（Task 1）、PIXEL_BOLT（Task 2）、配置（Task 5/6）、spawner（Task 4）、i18n 双语字段（Task 5 name_cn/name_en）、验证（Task 7）。全部覆盖。
- **占位符**：无 TBD/TODO。
- **类型一致**：`_teleport_state` / `_teleport_timer` / `_teleport_next_pos` / `ANIM_TELEPORT_IN/OUT` 在所有 Task 间命名一致；`_pick_teleport_pos(battle, player)` 签名统一；`_build_teleport_anims(anim_sprite)` 一致。
