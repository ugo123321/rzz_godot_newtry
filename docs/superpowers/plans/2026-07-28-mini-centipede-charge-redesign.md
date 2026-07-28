# 迷你千足虫冲锋重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `MINI_CENTIPEDE` 从远程弹幕怪 + 渐细拖尾改成直线冲锋撞击型飞行怪（12 节等大方块、共享血量、全身可击）。

**Architecture:** 照搬千足虫 boss 的「节段转发共享血量」模式——12 个隐形子节段节点注册进 `spawner.monsters`，每节小圆 hitbox + `take_damage_info`/元素状态转发到虫（头部）的 `_resolve_take_damage`。头部纯驱动，跑 `REPOSITION↔CHARGING` 两阶段冲锋状态机，在 `update_ai` 里像 JUMPER/LASER 那样提前分支跳过导航。

**Tech Stack:** Godot 4 / GDScript、`config/json/monsters.json`（权威源）、headless 场景测试（无 GUT，沿用 `tools/test_new_monsters.gd` 风格）。

**用户约束（重要）：** 未经用户确认**不要执行 `git commit`**。本计划每个任务的「Commit」步骤需先征得用户同意后再执行。

**参考 spec：** `docs/superpowers/specs/2026-07-28-mini-centipede-charge-redesign.md`

---

## File Structure

| 文件 | 责任 | 操作 |
|---|---|---|
| `scripts/entities/mini_centipede_segment.gd` | 节段命中节点：隐形 hitbox + 伤害/元素状态转发到虫 | 新建 |
| `scripts/entities/monster.gd` | 虫本体：Phase 状态机、`_update_mini_centipede`、`_apply_segment_hit`、节段生命周期、`_draw_mini_centipede` 重写 | 改 |
| `scripts/core/monster_spawner.gd` | 生成时为 MINI_CENTIPEDE 实例化 12 节段并注册 | 改 |
| `config/json/monsters.json` | MINI_CENTIPEDE 条目：去弹幕字段 + 加 json-only 新字段 | 改 |
| `tools/test_mini_centipede.gd` + `.tscn` | headless 回归测试 | 新建 |
| `config/excel/monsters.xlsx` | sync_json_to_excel 回写已有列 | 同步 |

---

## Task 1: 配置字段 + 失败测试骨架

**Files:**
- Modify: `config/json/monsters.json`（MINI_CENTIPEDE 条目，约 429-461 行）
- Create: `tools/test_mini_centipede.gd`
- Create: `tools/test_mini_centipede.tscn`

- [ ] **Step 1: 改 monsters.json MINI_CENTIPEDE 条目**

把 `config/json/monsters.json` 里 `MINI_CENTIPEDE` 整条改成（去掉弹幕字段、加新字段）：

```json
  {
    "kind_id": "MINI_CENTIPEDE",
    "spawn_order": 14,
    "unlock_at_stage": 12,
    "name_cn": "迷你千足虫",
    "hp": 130,
    "def": 4,
    "attack": 10,
    "attack_interval": 2.4,
    "size": 13,
    "speed": 30,
    "color_hex": "#7a5ab0",
    "grade": "A+",
    "can_move": 0,
    "attack_range": 0,
    "arrow_speed": 0,
    "ranged": 0,
    "ki_drain_on_hit": 0,
    "max_split_tier": 0,
    "split_count": 0,
    "exp_reward": 4,
    "character_folder": "",
    "sprite_prefix": "",
    "projectile_folder": "",
    "attack_pattern": "",
    "projectile_effect": "",
    "spread_count": 0,
    "spread_angle_deg": 0,
    "bounce_count": 0,
    "sprite_tint_hex": "",
    "elem_resist_poison": 0.3,
    "vuln_fire": 0.2,
    "segment_count": 12,
    "segment_size": 11,
    "segment_spacing": 11,
    "segment_hitbox": 6,
    "charge_speed": 260,
    "reposition_delay": 0.5,
    "name_en": "Mini Centipede"
  }
```

- [ ] **Step 2: 写失败测试骨架**

新建 `tools/test_mini_centipede.gd`：

```gdscript
extends Node
# 回归：迷你千足虫冲锋重构（12 节等大方块 + 共享血量 + 全身可击）
# 运行：godot --headless res://tools/test_mini_centipede.tscn
# 期望：打印 "MINI_CENTIPEDE_OK"

const MONSTER_SCENE := "res://scenes/entities/monster.tscn"

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
func is_in_bounds(p): return p.x >= -200 and p.y >= -200 and p.x <= 920 and p.y <= 1480
func shake_camera(_a, _b): pass
func is_bullet_blocked_at(_p): return false
func get_stage_theme(_i): return ""
"""

const COMBAT_SRC := """
extends Node
func should_monsters_attack(_p): return true
func schedule_death_fade(): return 0.0
func spawn_damage_number(_pos, _d, _a, _b, _c): pass
"""

# 子类 BattlePlayer 记录受击（绕过 iframe/心数制，便于确定性测试）
const PLAYER_SRC := """
extends BattlePlayer
var dmg_taken := 0.0
func take_damage(_amount):
	dmg_taken += 1.0
	return 1.0
"""

var _ok := true
var _report: Array = []

func _make_script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func _fail(msg: String) -> void:
	_ok = false
	_report.append("FAIL: " + msg)

func _ready() -> void:
	# 1) 配置加载
	var cfg := GameConfig.get_monster("MINI_CENTIPEDE")
	if cfg.is_empty():
		_fail("缺 MINI_CENTIPEDE 配置")
	else:
		if int(cfg.get("segment_count", -1)) != 12: _fail("segment_count!=12 got=%s" % cfg.get("segment_count"))
		if int(cfg.get("charge_speed", -1)) != 260: _fail("charge_speed!=260 got=%s" % cfg.get("charge_speed"))
		if int(cfg.get("ranged", -1)) != 0: _fail("ranged!=0 got=%s" % cfg.get("ranged"))
		if str(cfg.get("attack_pattern", "x")) != "": _fail("attack_pattern 非空 got=%s" % cfg.get("attack_pattern"))
		_report.append("ok: config segment_count=%s charge_speed=%s ranged=%s" % [cfg.get("segment_count"), cfg.get("charge_speed"), cfg.get("ranged")])

	for line in _report:
		print(line)
	print("MINI_CENTIPEDE_OK" if _ok else "MINI_CENTIPEDE_FAIL")
	get_tree().quit(0 if _ok else 1)
```

新建 `tools/test_mini_centipede.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/test_mini_centipede.gd" id="1"]

[node name="TestMiniCentipede" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑测试验证（配置部分应通过，其余待实现）**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: 打印 `ok: config ...` 和 `MINI_CENTIPEDE_OK`（此时只测配置，应通过）。

- [ ] **Step 4: Commit**（待用户确认）

```bash
git add config/json/monsters.json tools/test_mini_centipede.gd tools/test_mini_centipede.tscn
git commit -m "feat(monster): 迷你千足虫配置改为冲锋型 + headless 测试骨架"
```

---

## Task 2: 节段类 MiniCentipedeSegment

**Files:**
- Create: `scripts/entities/mini_centipede_segment.gd`

- [ ] **Step 1: 写节段类**

新建 `scripts/entities/mini_centipede_segment.gd`：

```gdscript
extends Node2D
class_name MiniCentipedeSegment

# 迷你千足虫的节段命中节点。隐形（虫身由头部 _draw_mini_centipede 统一绘制），
# 仅作为独立 hitbox + 伤害/元素状态转发层，把命中路由到虫的共享血量池。
# 与 CentipedeSegment（boss 用）平行，但指向 BattleMonster 而非 CentipedeBoss。

var worm: BattleMonster
var segment_index := 0
var alive := true
var dying := false


func get_hitbox_radius() -> float:
	if worm and is_instance_valid(worm):
		return worm._centi_segment_hitbox
	return 6.0


func is_combat_targetable() -> bool:
	return worm != null and is_instance_valid(worm) and worm.alive and not worm.dying and worm._centi_phase == BattleMonster.Phase.CHARGING


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	if worm == null or not is_instance_valid(worm):
		return {"damage": 0, "is_crit": false}
	return worm._apply_segment_hit(DamageInfo.legacy(raw_damage), self, from_pos)


func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if worm == null or not is_instance_valid(worm):
		return {"damage": 0, "is_crit": false}
	return worm._apply_segment_hit(info, self, from_pos)


# 元素状态转发：ElementEffectManager.try_apply 对目标节段调这些方法，必须路由到虫
func apply_burn_dot(duration: float, dps: int) -> void:
	if _worm_alive(): worm.apply_burn_dot(duration, dps)

func apply_burn_dot_with_snapshot(duration: float, dps: int, elem_pct: float) -> void:
	if _worm_alive(): worm.apply_burn_dot_with_snapshot(duration, dps, elem_pct)

func apply_burn_dot_v2(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if _worm_alive(): worm.apply_burn_dot_v2(snapshot_atk, elem_pct, proc_freq_pct)

func apply_freeze_slow(snapshot_atk: float, elem_pct: float, slow_bonus: float) -> void:
	if _worm_alive(): worm.apply_freeze_slow(snapshot_atk, elem_pct, slow_bonus)

func apply_poison_dot(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if _worm_alive(): worm.apply_poison_dot(snapshot_atk, elem_pct, proc_freq_pct)

func apply_paralyze(duration: float) -> void:
	if _worm_alive(): worm.apply_paralyze(duration)

func apply_petrify(duration: float) -> void:
	if _worm_alive(): worm.apply_petrify(duration)


func update_ai(_delta: float, _player: BattlePlayer, _battle: Node) -> void:
	pass

func update_death(_delta: float) -> void:
	pass

func die() -> void:
	pass


func _worm_alive() -> bool:
	return worm != null and is_instance_valid(worm) and worm.alive and not worm.dying
```

- [ ] **Step 2: 验证脚本可加载（编译无错）**

Run: `godot --headless --check-only res://scripts/entities/mini_centipede_segment.gd 2>&1 || godot --headless --quit`
Expected: 无解析错误（若 `--check-only` 不支持，跑 Task 3 的测试间接验证编译）。

- [ ] **Step 3: Commit**（待用户确认）

```bash
git add scripts/entities/mini_centipede_segment.gd
git commit -m "feat(monster): 新增 MiniCentipedeSegment 节段命中转发节点"
```

---

## Task 3: 虫本体状态字段 + setup 读配置 + 节段实例化 + 死亡清理

**Files:**
- Modify: `scripts/entities/monster.gd`（143-147 状态字段块、152-199 setup、545-581 begin_dying/_finish_death）
- Modify: `scripts/core/monster_spawner.gd`（378-384 _spawn_monster）
- Modify: `tools/test_mini_centipede.gd`（加节段创建/注册断言）

- [ ] **Step 1: 替换 monster.gd MINI_CENTIPEDE 状态字段块**

把 `scripts/entities/monster.gd` 143-147 行（旧 `_code_drawn` / `_centi_trail` / `CENTI_TRAIL_MAX` / `CENTI_SEG_SPACING`）替换为：

```gdscript
# === MINI_CENTIPEDE 迷你千足虫（直线冲锋撞击型，12 节等大方块，共享血量）===
enum Phase { REPOSITION, CHARGING }
var _code_drawn := false
var _centi_phase := Phase.REPOSITION
var _centi_segments: Array = []          # MiniCentipedeSegment 实例
var _centi_segment_count := 12
var _centi_segment_size := 11.0
var _centi_segment_spacing := 11.0
var _centi_segment_hitbox := 6.0
var _centi_charge_speed := 260.0
var _centi_reposition_delay := 0.5
var _centi_repos_timer := 0.3
var _charge_dir := Vector2.RIGHT
var _charge_entry := Vector2.ZERO
var _charge_target := Vector2.ZERO
var _has_hit_this_pass := false
```

- [ ] **Step 2: setup 里读新配置字段**

在 `monster.gd` `setup()` 函数里，`color = Color(...)`（约 192 行）之后、`global_position = spawn_pos`（约 193 行）之前插入：

```gdscript
	if kind_id == "MINI_CENTIPEDE":
		_centi_segment_count = int(stats.get("segment_count", 12))
		_centi_segment_size = float(stats.get("segment_size", 11.0))
		_centi_segment_spacing = float(stats.get("segment_spacing", 11.0))
		_centi_segment_hitbox = float(stats.get("segment_hitbox", 6.0))
		_centi_charge_speed = float(stats.get("charge_speed", 260.0))
		_centi_reposition_delay = float(stats.get("reposition_delay", 0.5))
```

- [ ] **Step 3: 加节段实例化方法**

在 `monster.gd` 末尾（`_draw_mini_centipede` 区块附近，旧函数已被 Task 7 替换前可先放这里）新增：

```gdscript
# MINI_CENTIPEDE：生成 N 个隐形节段命中节点并注册进 spawner.monsters
func _init_centipede_segments(spawner: Node, battle: Node) -> void:
	for seg in _centi_segments:
		if is_instance_valid(seg):
			seg.queue_free()
	_centi_segments.clear()
	var SegClass := load("res://scripts/entities/mini_centipede_segment.gd")
	for i in range(_centi_segment_count):
		var seg = SegClass.new()
		seg.worm = self
		seg.segment_index = i
		seg.alive = true
		seg.dying = false
		if battle and battle.has_method("get") and battle.get("monster_container") != null:
			battle.monster_container.add_child(seg)
		else:
			add_child(seg)
		seg.global_position = global_position
		_centi_segments.append(seg)
		if spawner and "monsters" in spawner:
			spawner.monsters.append(seg)
```

- [ ] **Step 4: 死亡清理 —— begin_dying 标记节段**

在 `monster.gd` `begin_dying()` 里，`dying = true`（约 548 行）之后插入：

```gdscript
	if kind_id == "MINI_CENTIPEDE":
		for seg in _centi_segments:
			if is_instance_valid(seg):
				seg.dying = true
				seg.alive = false
```

- [ ] **Step 5: 死亡清理 —— _finish_death 注销 + free 节段**

在 `monster.gd` `_finish_death()` 里，`alive = false` / `dying = false`（约 576-577 行）之后、`var battle := ...`（约 578 行）之前插入节段清理，并在末尾保留原有 self 注销。完整改写 `_finish_death` 为：

```gdscript
func _finish_death() -> void:
	alive = false
	dying = false
	var battle := get_tree().get_first_node_in_group("battle")
	if kind_id == "MINI_CENTIPEDE":
		for seg in _centi_segments:
			if is_instance_valid(seg):
				if battle and battle.has_method("get") and battle.get("spawner") != null:
					battle.spawner.unregister_monster(seg)
				seg.queue_free()
		_centi_segments.clear()
	if battle and battle.has_method("get") and battle.get("spawner") != null:
		battle.spawner.unregister_monster(self)
	queue_free()
```

> 注：用 `battle.has_method("get") and battle.get("spawner") != null` 防御 mock battle 无 spawner 的测试场景；真实 battle 一定有 spawner。

- [ ] **Step 6: spawner 生成时调节段实例化**

在 `scripts/core/monster_spawner.gd` `_spawn_monster()`（约 378-384 行）末尾追加：

```gdscript
	if kind_id == "MINI_CENTIPEDE":
		monster._init_centipede_segments(self, battle)
```

完整函数变为：

```gdscript
func _spawn_monster(kind_id: String, stage_index: int, battle: Node, elite_kind: String = "") -> void:
	var scene: PackedScene = load("res://scenes/entities/monster.tscn")
	var monster = scene.instantiate()
	battle.monster_container.add_child(monster)
	monster.setup(kind_id, stage_index, _pick_spawn_pos(battle), elite_kind)
	monster.begin_spawn()
	monsters.append(monster)
	if kind_id == "MINI_CENTIPEDE":
		monster._init_centipede_segments(self, battle)
```

- [ ] **Step 7: 写测试断言 —— 节段创建 + 注册**

在 `tools/test_mini_centipede.gd` `_ready()` 的配置断言之后、`for line in _report:` 之前，插入 battle/spawner/monster 搭建 + 节段断言：

```gdscript
	# 2) battle 替身 + spawner
	var battle = Node2D.new()
	battle.name = "Battle"
	battle.add_to_group("battle")
	battle.set_script(_make_script(BATTLE_SRC))
	battle.state = GameState.PLAYING
	add_child(battle)
	var mc := Node2D.new(); mc.name = "Monsters"; battle.add_child(mc)
	battle.monster_container = mc
	var combat = Node.new(); combat.set_script(_make_script(COMBAT_SRC)); battle.add_child(combat)
	battle.combat = combat
	var Spawner := load("res://scripts/core/monster_spawner.gd")
	var spawner = Spawner.new(); battle.add_child(spawner)
	battle.spawner = spawner

	# player：子类记录受击，放在场内会被冲锋撞到
	var player_script := _make_script(PLAYER_SRC)
	var player = player_script.new()
	player.global_position = Vector2(360, 640)
	battle.player = player

	# 3) 通过 spawner 生成（走完整 setup + begin_spawn + 节段实例化路径）
	var scene := load(MONSTER_SCENE) as PackedScene
	_ = scene
	spawner._spawn_monster("MINI_CENTIPEDE", 5, battle, "")
	# spawner._spawn_monster 会调 _pick_spawn_pos，需要 spawn_clusters —— 直接手动建一只避免依赖
	# 上一行若因 _pick_spawn_pos 抛错，改用下方手动路径：
	if spawner.monsters.is_empty():
		var m2 = (load(MONSTER_SCENE) as PackedScene).instantiate()
		mc.add_child(m2)
		m2.setup("MINI_CENTIPEDE", 5, Vector2(360, 300), "")
		m2.begin_spawn()
		spawner.monsters.append(m2)
		m2._init_centipede_segments(spawner, battle)

	# 找到虫本体（spawner.monsters 里第一个 BattleMonster）
	var worm = null
	for n in spawner.monsters:
		if n is BattleMonster:
			worm = n
			break
	if worm == null:
		_fail("没找到虫本体")
	else:
		if worm._centi_segments.size() != 12:
			_fail("节段数!=12 got=%d" % worm._centi_segments.size())
		var seg_count := 0
		for n in spawner.monsters:
			if n is MiniCentipedeSegment:
				seg_count += 1
		if seg_count != 12:
			_fail("spawner.monsters 里节段数!=12 got=%d" % seg_count)
		else:
			_report.append("ok: 12 节段已创建并注册")
		# 节段 hitbox + targetable 委托
		if worm._centi_segments.size() == 12:
			var s0 = worm._centi_segments[0]
			if absf(s0.get_hitbox_radius() - worm._centi_segment_hitbox) > 0.01:
				_fail("节段 hitbox 半径 != %f" % worm._centi_segment_hitbox)
			# 未进 CHARGING 前不应 targetable
			if s0.is_combat_targetable():
				_fail("REPOSITION 期间节段不应可击")
			worm._centi_phase = BattleMonster.Phase.CHARGING
			if not s0.is_combat_targetable():
				_fail("CHARGING 期间节段应可击")
			worm._centi_phase = BattleMonster.Phase.REPOSITION
```

> 注：`absf` 是 Godot 内置。`_ = scene` 消除未用变量警告。

- [ ] **Step 8: 跑测试**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: 打印 `ok: 12 节段已创建并注册` 和 `MINI_CENTIPEDE_OK`。若 `_pick_spawn_pos` 路径报错，手动路径兜底（已在测试里写）。

- [ ] **Step 9: Commit**（待用户确认）

```bash
git add scripts/entities/monster.gd scripts/core/monster_spawner.gd tools/test_mini_centipede.gd
git commit -m "feat(monster): 虫本体读配置 + 12 节段实例化注册 + 死亡清理"
```

---

## Task 4: 冲锋状态机 + 节段排位

**Files:**
- Modify: `scripts/entities/monster.gd`（update_ai 分支 + 新增 `_update_mini_centipede` 及辅助函数）
- Modify: `tools/test_mini_centipede.gd`（加状态机断言）

- [ ] **Step 1: 在 update_ai 里提前分支**

在 `scripts/entities/monster.gd` `update_ai()` 里，`hurt_reaction_timer` 块（约 599-600 行）之后、`var to_player := ...`（约 601 行）之前插入：

```gdscript
	if kind_id == "MINI_CENTIPEDE":
		_update_mini_centipede(delta, player, battle)
		return
```

- [ ] **Step 2: 删除旧拖尾采样调用**

删除 `monster.gd` 约 657-659 行的旧调用（已不可达，但清掉冗余）：

```gdscript
	# MINI_CENTIPEDE 拖尾采样（位移后记录头部位置，分段跟随）
	if kind_id == "MINI_CENTIPEDE":
		_update_centipede_trail()
```

（整段删除。）

- [ ] **Step 3: 实现 _update_mini_centipede 及辅助函数**

在 `monster.gd` 末尾（`_init_centipede_segments` 附近）新增：

```gdscript
# ===================== MINI_CENTIPEDE 冲锋状态机 =====================
func _update_mini_centipede(delta: float, player: BattlePlayer, _battle: Node) -> void:
	match _centi_phase:
		Phase.REPOSITION:
			_centi_repos_timer -= delta
			if _centi_repos_timer <= 0.0:
				_begin_charge_pass(player)
		Phase.CHARGING:
			_step_charge(delta, player)


func _begin_charge_pass(player: BattlePlayer) -> void:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var margin := 80.0
	var side := randi() % 4
	match side:
		0: _charge_entry = Vector2(MathUtils.rand_range(margin, w - margin), -margin)
		1: _charge_entry = Vector2(MathUtils.rand_range(margin, w - margin), h + margin)
		2: _charge_entry = Vector2(-margin, MathUtils.rand_range(margin, h - margin))
		_: _charge_entry = Vector2(w + margin, MathUtils.rand_range(margin, h - margin))
	_charge_target = player.global_position if player != null else Vector2(w * 0.5, h * 0.5)
	var d := _charge_target - _charge_entry
	_charge_dir = d.normalized() if d.length() > 0.001 else Vector2.RIGHT
	global_position = _charge_entry
	_has_hit_this_pass = false
	_centi_phase = Phase.CHARGING
	_position_segments()


func _step_charge(delta: float, player: BattlePlayer) -> void:
	var slow := clampf(slow_pct_active, 0.0, 0.95)
	var spd := _centi_charge_speed * (1.0 - slow)
	if paralyze_timer > 0.0 or petrify_timer > 0.0:
		spd = 0.0
	global_position += _charge_dir * spd * delta
	_position_segments()
	# 撞击：每轮一次接触伤害，不停不拐弯
	if not _has_hit_this_pass and player != null and float(player.get("hp")) > 0.0:
		var rr := player.get_effective_radius() + GameConfig.scale_world(6.0)
		if global_position.distance_to(player.global_position) <= rr:
			player.take_damage(attack)
			_has_hit_this_pass = true
	# 飞出对侧屏外 → 进入下一轮
	if _exited_screen():
		_has_hit_this_pass = false
		_centi_phase = Phase.REPOSITION
		_centi_repos_timer = _centi_reposition_delay


func _position_segments() -> void:
	for i in range(_centi_segments.size()):
		_centi_segments[i].global_position = global_position - _charge_dir * (float(i) * _centi_segment_spacing)


func _exited_screen() -> bool:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var m := 90.0
	var p := global_position
	if _charge_dir.x > 0.001 and p.x > w + m: return true
	if _charge_dir.x < -0.001 and p.x < -m: return true
	if _charge_dir.y > 0.001 and p.y > h + m: return true
	if _charge_dir.y < -0.001 and p.y < -m: return true
	return false
```

- [ ] **Step 4: 跳过进场缩放 tween**

在 `monster.gd` `begin_spawn()` 开头（约 240 行 `if duration < 0.0:` 之前）插入：

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

- [ ] **Step 5: 写状态机断言**

在 `tools/test_mini_centipede.gd` `_ready()` 节段断言之后、`for line in _report:` 之前，插入：

```gdscript
	# 4) 状态机：REPOSITION→CHARGING→飞出→REPOSITION
	if worm != null:
		worm._centi_repos_timer = 0.0  # 立刻进入 CHARGING
		var reached_charging := false
		var reached_reposition_again := false
		var seg_line_ok := true
		for _i in range(600):
			worm.update_ai(0.05, player, battle)
			worm.update_death(0.05)
			worm._draw()
			if worm._centi_phase == BattleMonster.Phase.CHARGING:
				reached_charging = true
				# 节段应在头部后方排成直线
				var head := worm.global_position
				var dir := worm._charge_dir
				for k in range(worm._centi_segments.size()):
					var expect := head - dir * (float(k) * worm._centi_segment_spacing)
					if worm._centi_segments[k].global_position.distance_to(expect) > 1.0:
						seg_line_ok = false
						break
			if reached_charging and worm._centi_phase == BattleMonster.Phase.REPOSITION:
				reached_reposition_again = true
				break
		if not reached_charging:
			_fail("未进入 CHARGING")
		if not reached_reposition_again:
			_fail("未飞出屏外回到 REPOSITION")
		if not seg_line_ok:
			_fail("节段未在头部后方排成直线")
		if not (reached_charging and reached_reposition_again and seg_line_ok):
			_fail("状态机断言失败")
		else:
			_report.append("ok: REPOSITION↔CHARGING 状态机 + 节段排直线")
```

- [ ] **Step 6: 跑测试**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: 打印 `ok: REPOSITION↔CHARGING 状态机 + 节段排直线` 和 `MINI_CENTIPEDE_OK`。

- [ ] **Step 7: Commit**（待用户确认）

```bash
git add scripts/entities/monster.gd tools/test_mini_centipede.gd
git commit -m "feat(monster): 迷你千足虫冲锋状态机 + 节段直线排位"
```

---

## Task 5: 撞击 + 共享血量命中转发 + 杀死发奖

**Files:**
- Modify: `scripts/entities/monster.gd`（新增 `_apply_segment_hit`）
- Modify: `tools/test_mini_centipede.gd`（加撞击 + 命中 + 杀死断言）

- [ ] **Step 1: 实现 _apply_segment_hit**

在 `monster.gd` `_init_centipede_segments` 附近新增：

```gdscript
# 节段命中转发：复用 _resolve_take_damage（已处理 def/vuln/抗性/暴击/死亡触发）。
# 节段不是 BattleMonster，battle._on_monster_killed 会忽略调用方对节段的 emit；
# 因此虫死亡时由虫自己 emit 一次 monster_killed(self)，保证经验/灵魂球/掉落正常。
func _apply_segment_hit(info: DamageInfo, _seg, from_pos: Vector2) -> Dictionary:
	var result := _resolve_take_damage(info, from_pos)
	if bool(result.get("started_dying", false)):
		EventBus.monster_killed.emit(self)
	return result
```

- [ ] **Step 2: 写撞击断言**

在 `tools/test_mini_centipede.gd` `_ready()` 状态机断言之后、`for line in _report:` 之前，插入：

```gdscript
	# 5) 撞击：冲锋应撞到玩家一次（player 在场内 360,640，子类记录 dmg_taken）
	if worm != null and player != null:
		var dmg_before := float(player.get("dmg_taken"))
		worm._centi_repos_timer = 0.0
		for _i in range(800):
			worm.update_ai(0.05, player, battle)
			worm.update_death(0.05)
			if float(player.get("dmg_taken")) > dmg_before:
				break
		if float(player.get("dmg_taken")) <= dmg_before:
			_fail("冲锋未撞到玩家")
		elif not worm._has_hit_this_pass:
			_fail("_has_hit_this_pass 未置位")
		else:
			_report.append("ok: 撞击一次 dmg_taken=%d" % int(player.get("dmg_taken")))
```

- [ ] **Step 3: 写共享血量命中 + 杀死断言**

紧接 Step 2 之后插入（用新虫，避免上一段把虫打死）：

```gdscript
	# 6) 节段命中 → 共享血量；杀死 → 虫 emit monster_killed 恰好一次
	var scene2 := load(MONSTER_SCENE) as PackedScene
	var worm2 = scene2.instantiate()
	mc.add_child(worm2)
	worm2.setup("MINI_CENTIPEDE", 5, Vector2(360, 300), "")
	worm2.begin_spawn()
	spawner.monsters.append(worm2)
	worm2._init_centipede_segments(spawner, battle)
	worm2._centi_phase = BattleMonster.Phase.CHARGING  # 让节段可击
	var hp_before := worm2.hp
	var seg6 = worm2._centi_segments[6]
	var hit_res := seg6.take_damage(50, worm2.global_position)
	if int(hit_res.get("damage", 0)) <= 0:
		_fail("节段命中未造成伤害")
	if worm2.hp >= hp_before:
		_fail("节段命中未扣虫血 hp_before=%d hp_after=%d" % [hp_before, worm2.hp])
	else:
		_report.append("ok: 节段命中扣共享血 %d→%d (dmg=%d)" % [hp_before, worm2.hp, int(hit_res.get("damage", 0))])
	# 杀死：监听 monster_killed，断言只 emit 虫一次
	var kill_count := 0
	var killed_who = null
	var _on_kill := func(monster):
		kill_count += 1
		killed_who = monster
	if not EventBus.monster_killed.is_connected(_on_kill):
		EventBus.monster_killed.connect(_on_kill)
	var seg0 = worm2._centi_segments[0]
	seg0.take_damage(99999, worm2.global_position)
	if not worm2.dying:
		_fail("节段命中杀死后虫未 dying")
	if kill_count != 1:
		_fail("杀死时 monster_killed emit 次数!=1 got=%d" % kill_count)
	elif killed_who != worm2:
		_fail("monster_killed emit 的不是虫")
	else:
		_report.append("ok: 节段击杀 emit 虫一次 kill_count=1")
	# 跑完死亡动画，确认节段被清理
	for _i in range(40):
		worm2.update_death(0.05)
	var seg_left := 0
	for n in spawner.monsters:
		if n is MiniCentipedeSegment:
			seg_left += 1
	if seg_left != 0:
		_fail("虫死后节段未清理剩=%d" % seg_left)
	else:
		_report.append("ok: 虫死后节段全部清理")
	EventBus.monster_killed.disconnect(_on_kill)
```

> 注：`func _on_kill := func(monster):` 是 Godot 4 lambda；`is_connected` 对 lambda 可能判 false，故用 `if not ...is_connected` 兜底直接 connect（重复连接会报错——若报错，去掉 is_connected 判断直接 connect 一次即可，测试为单次运行）。

- [ ] **Step 4: 跑测试**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: 打印 `ok: 撞击一次`、`ok: 节段命中扣共享血`、`ok: 节段击杀 emit 虫一次`、`ok: 虫死后节段全部清理`，最后 `MINI_CENTIPEDE_OK`。

- [ ] **Step 5: Commit**（待用户确认）

```bash
git add scripts/entities/monster.gd tools/test_mini_centipede.gd
git commit -m "feat(monster): 节段命中转发共享血量 + 击杀发奖 + 撞击伤害"
```

---

## Task 6: 视觉重写 — 12 等大方块

**Files:**
- Modify: `scripts/entities/monster.gd`（替换 `_update_centipede_trail` + `_draw_mini_centipede`）

- [ ] **Step 1: 删除旧 _update_centipede_trail 函数**

删除 `monster.gd` 约 901-911 行的整个 `_update_centipede_trail()` 函数（旧拖尾采样，已被状态机取代）。

- [ ] **Step 2: 重写 _draw_mini_centipede**

把 `monster.gd` 约 914-939 行的 `_draw_mini_centipede()` 整体替换为：

```gdscript
# 代码绘制：12 节等大紫色方块，沿冲锋方向排成直线；头节加高光点。
func _draw_mini_centipede() -> void:
	if not alive:
		return
	var alpha: float = modulate.a if dying else 1.0
	var body_col := Color("#7a5ab0")
	var edge_col := Color("#2e1f44")
	var ang := _charge_dir.angle()
	var half := _centi_segment_size * 0.5
	for i in range(_centi_segment_count):
		var local := -_charge_dir * (float(i) * _centi_segment_spacing)
		draw_set_transform(local, ang, Vector2.ONE)
		draw_rect(Rect2(-half, -half, _centi_segment_size, _centi_segment_size), Color(edge_col, alpha))
		draw_rect(Rect2(-half + 1.5, -half + 1.5, _centi_segment_size - 3.0, _centi_segment_size - 3.0), Color(body_col, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 头节高光
	draw_circle(Vector2.ZERO, half * 0.4, Color(1.0, 1.0, 1.0, 0.55 * alpha))
```

- [ ] **Step 3: 跑测试（_draw 在状态机测试里已被调用，应不崩）**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: 全部 ok + `MINI_CENTIPEDE_OK`（`_draw` 在 Task 4/5 的循环里已被调，此处确认重写后仍不崩）。

- [ ] **Step 4: Commit**（待用户确认）

```bash
git add scripts/entities/monster.gd
git commit -m "feat(monster): 迷你千足虫视觉重写为 12 等大方块"
```

---

## Task 7: xlsx 同步 + 全量回归

**Files:**
- Sync: `config/excel/monsters.xlsx`

- [ ] **Step 1: 跑 sync_json_to_excel 回写已有列**

Run: `python tools/sync_json_to_excel.py`
Expected: 把 monsters.json 已有列同步回 `config/excel/monsters.xlsx`；新 json-only 列（segment_count 等）不写进 xlsx（符合记忆 `reference_monsters_config_flow`）。若脚本报缺列错误，按脚本提示处理（不要跑 `export_config.py`——会洗掉 elem_resist/vuln/name_en）。

- [ ] **Step 2: 跑迷你千足虫专属回归**

Run: `godot --headless res://tools/test_mini_centipede.tscn`
Expected: `MINI_CENTIPEDE_OK`，所有 `ok:` 行通过。

- [ ] **Step 3: 跑 4 怪回归（确认没破坏其它怪）**

Run: `godot --headless res://tools/test_new_monsters.tscn`
Expected: `NEW_MONSTERS_OK`。

> 注：`test_new_monsters.gd` 仍按旧方式手动实例化 MINI_CENTIPEDE（不调 spawner._spawn_monster），所以不会自动建节段——但它只验证「setup/update_ai/_draw 不崩」。新代码下 update_ai 分支到 `_update_mini_centipede`，节段数组为空（手动实例化没调 `_init_centipede_segments`），`_position_segments` 遍历空数组不崩。若该测试因 MINI_CENTIPEDE 行为变化失败，需更新 `test_new_monsters.gd` 的 MINI_CENTIPEDE 断言（去掉对 attack_pattern="radial" 之类的旧断言）。

- [ ] **Step 4: 手动进游戏验证（用户执行）**

进游戏到 stage idx ≥11（`mini_centipede` 计数>0 的关）。确认：
- 虫从屏外直线飞入、撞玩家一次、直线飞出、~0.5s 换边再来。
- 普攻打虫身任意一节能扣血、虫身不缩短、HP 归零死亡掉灵魂球。
- 减速/燃烧/中毒/麻痹对虫生效（减速让冲锋变慢、麻痹定身、DoT 扣血）。
- 中英文虫名正常（`Mini Centipede` / `迷你千足虫`）。

- [ ] **Step 5: Commit**（待用户确认）

```bash
git add config/excel/monsters.xlsx tools/test_new_monsters.gd
git commit -m "test(monster): sync monsters.xlsx + 迷你千足虫回归通过"
```

---

## Self-Review

**1. Spec coverage:**
- 12 节等大方块 → Task 6（绘制）+ Task 1（segment_count=12）+ Task 3（实例化 12 节段）。✅
- 直线冲锋撞击、不拐弯、飞出反复 → Task 4（状态机）+ Task 5（撞击一次）。✅
- 每节可击、共享血量 → Task 2（节段类）+ Task 3（注册）+ Task 5（`_apply_segment_hit`）。✅
- 元素状态转发 → Task 2 Step 1（节段类 apply_* 转发）。✅
- 杀死发奖一次 → Task 5 Step 3（emit 虫一次断言）。✅
- 配置字段 + json-only → Task 1。✅
- 死亡清理节段 → Task 3 Step 4-5。✅
- 跳过进场 tween → Task 4 Step 4。✅
- xlsx 同步 → Task 7。✅
- AOE 多节命中风险 → spec 风险节已记，HP 调节为 playtest 项，不在本计划改。✅

**2. Placeholder scan:** 无 TBD/TODO；所有步骤含完整代码或确切命令。Task 7 Step 4 是用户手动验证（明确标注「用户执行」），非占位。

**3. Type consistency:**
- `Phase` 枚举 → `BattleMonster.Phase.CHARGING`（节段类与测试一致访问）。✅
- `_centi_segments` / `_centi_phase` / `_charge_dir` / `_centi_segment_spacing` / `_centi_segment_hitbox` / `_has_hit_this_pass` → Task 3 定义，Task 4/5/6 与测试一致使用。✅
- `_init_centipede_segments(spawner, battle)` → Task 3 定义，spawner Task 3 Step 6 调用一致。✅
- `_apply_segment_hit(info, seg, from_pos)` → Task 5 定义，节段类 Task 2 调用签名一致。✅
- `_update_mini_centipede(delta, player, battle)` → Task 4 定义，update_ai 分支调用一致。✅
- `MiniCentipedeSegment` class_name → Task 2 定义，Task 3 `load(...)` + 测试 `is MiniCentipedeSegment` 一致。✅
