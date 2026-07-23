# 左上角货币 HUD + 宝箱飞行拾取效果 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除局内左上角金币显示；银币/钥匙改用 .png icon 常驻横向显示（初始 0）；开宝箱时对应 icon 发光掉地→短暂停留→蓝色粒子飞向左上角 icon→到达后计数改变（复刻 SoulOrb 经验效果）。

**Architecture:** 新建数据驱动的 `PickupOrb` + `PickupOrbManager`（kind 注册表，复刻 `soul_orb.gd` 四阶段、蓝色调色板、本体=icon 贴图）。HUD 删金币 widget、换 .png icon、横向常驻、新增 `get_pickup_icon_screen_pos(kind)` 供 orb 取目标。宝箱 `_open()` 改为 `spawn_burst`，货币入账延后到 orb 到达回调。

**Tech Stack:** Godot 4.x, GDScript, 无单元测试框架——验证靠跑游戏 + 观察控制台/视觉。

**Spec:** `docs/superpowers/specs/2026-07-23-hud-currency-pickup-orbs-design.md`

---

### Task 1: 创建 `scripts/effects/pickup_orb.gd`

**Files:**
- Create: `scripts/effects/pickup_orb.gd`

- [ ] **Step 1: 写 orb 脚本（复刻 soul_orb.gd 四阶段，蓝色，本体=icon 贴图）**

Create `scripts/effects/pickup_orb.gd` with full content:

```gdscript
extends Node2D
class_name PickupOrb

# 宝箱/掉落物飞行拾取球：地上短停 → 飞向左上角对应 icon → 命中后真正加货币
# 复刻 soul_orb.gd 四阶段，本体= icon 贴图 + 蓝色发光，粒子蓝色
# 数据驱动：kind 由 PickupOrbManager 注册表决定 icon + 入账回调

const PHASE_SPAWN := 0     # 0.15s 上跳 + 落回
const PHASE_IDLE := 1      # ~0.25s 悬浮 + 闪烁
const PHASE_FLY := 2       # 0.45s Tween 飞向左上角 icon
const PHASE_IMPACT := 3    # 0.10s 命中爆 → queue_free

const SPAWN_DUR := 0.15
const SPAWN_RISE := 8.0
const IDLE_DUR := 0.25
const IDLE_BOB_AMP := 2.0
const FLY_DUR := 0.45
const IMPACT_DUR := 0.10

const PICKUP_ORB_DRAW_DATA := {
	"icon_size": 18.0,
	"glow_r1": 16.0,
	"glow_r2": 9.0,
	"glow_outer_color": Color(0.30, 0.60, 1.00, 0.22),
	"glow_inner_color": Color(0.50, 0.80, 1.00, 0.42),
	"trail_color": Color(0.40, 0.70, 1.00, 0.45),
	"trail_max": 8,
	"hit_dust_color": Color("#7ab8ff"),
	"hit_dust_count": 12,
}

var _kind: String = ""
var _amount: int = 1
var _phase: int = PHASE_SPAWN
var _phase_t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO
var _on_arrive: Callable = Callable()
var _icon: Texture2D = null
var _trail: Array[Vector2] = []
var _impact_burst: Array[Dictionary] = []   # [{pos, vel, life}]


func setup(start_pos: Vector2, kind: String, amount: int, on_arrive: Callable, icon: Texture2D) -> void:
	global_position = start_pos
	_base_pos = start_pos
	_kind = kind
	_amount = maxi(1, amount)
	_on_arrive = on_arrive
	_icon = icon
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5    # 在血迹 (-4) 之上，UI 之下


func _process(delta: float) -> void:
	_phase_t += delta
	match _phase:
		PHASE_SPAWN:
			# 上抛 + 阻尼落回（正弦半周期模拟弹跳）
			var t := clampf(_phase_t / SPAWN_DUR, 0.0, 1.0)
			var rise := sin(t * PI) * SPAWN_RISE
			global_position = _base_pos + Vector2(0.0, -rise)
			if _phase_t >= SPAWN_DUR:
				_enter(PHASE_IDLE)
				_base_pos = global_position
		PHASE_IDLE:
			# 悬浮微浮 + 闪烁（_draw 里读 phase_t）
			var bob := sin(_phase_t * TAU / 0.4) * IDLE_BOB_AMP
			global_position = _base_pos + Vector2(0.0, bob)
			if _phase_t >= IDLE_DUR:
				_start_fly()
		PHASE_FLY:
			# 位置由 Tween 推动；这里收集尾迹
			_push_trail(global_position)
		PHASE_IMPACT:
			# 粒子爆炸 + 短暂停留后销毁
			for p in _impact_burst:
				p["pos"] += p["vel"] * delta
				p["vel"] *= 0.88
				p["life"] -= delta
			if _phase_t >= IMPACT_DUR:
				queue_free()
				return
	queue_redraw()


func _enter(new_phase: int) -> void:
	_phase = new_phase
	_phase_t = 0.0


func _start_fly() -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null:
		# 兜底：没拿到 battle 也不能死循环，直接命中回调
		_finish_arrival()
		return
	var target_world := _calc_target_world_pos(battle)
	_enter(PHASE_FLY)
	var tw := create_tween()
	tw.tween_property(self, "global_position", target_world, FLY_DUR).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.finished.connect(_on_fly_finished)


func _calc_target_world_pos(battle: Node) -> Vector2:
	# HUD 提供 icon 屏幕中心；这里屏幕 → 世界（与 soul_orb.gd:107-118 同款）
	if battle.hud == null or not battle.hud.has_method("get_pickup_icon_screen_pos"):
		return _base_pos
	var screen_pos: Vector2 = battle.hud.get_pickup_icon_screen_pos(_kind)
	var xform := get_viewport().get_canvas_transform()
	return xform.affine_inverse() * screen_pos


func _on_fly_finished() -> void:
	_finish_arrival()


func _finish_arrival() -> void:
	if _on_arrive.is_valid():
		_on_arrive.call(_amount)
	# 启动 impact 粒子爆
	_impact_burst.clear()
	var count := int(PICKUP_ORB_DRAW_DATA["hit_dust_count"])
	for _i in range(count):
		var ang := randf() * TAU
		var spd := randf_range(40.0, 110.0)
		_impact_burst.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": IMPACT_DUR,
		})
	_enter(PHASE_IMPACT)


func _push_trail(p: Vector2) -> void:
	_trail.append(p)
	var max_n := int(PICKUP_ORB_DRAW_DATA["trail_max"])
	while _trail.size() > max_n:
		_trail.pop_front()


func _draw() -> void:
	if _phase == PHASE_IMPACT:
		_draw_impact_burst()
		return
	# 飞行尾迹（FLY phase 才有）
	if _phase == PHASE_FLY and _trail.size() >= 2:
		var trail_col: Color = PICKUP_ORB_DRAW_DATA["trail_color"]
		for i in range(_trail.size() - 1):
			var t := float(i) / float(_trail.size())
			var a := lerpf(0.0, trail_col.a, t)
			var col := Color(trail_col.r, trail_col.g, trail_col.b, a)
			var p1 := to_local(_trail[i])
			var p2 := to_local(_trail[i + 1])
			draw_line(p1, p2, col, 2.0 + t * 2.0)
	# 双层外发光圆晕（蓝色）
	var glow_r1: float = PICKUP_ORB_DRAW_DATA["glow_r1"]
	var glow_r2: float = PICKUP_ORB_DRAW_DATA["glow_r2"]
	var glow_outer: Color = PICKUP_ORB_DRAW_DATA["glow_outer_color"]
	var glow_inner: Color = PICKUP_ORB_DRAW_DATA["glow_inner_color"]
	# IDLE 期间圆晕呼吸
	var pulse := 1.0
	if _phase == PHASE_IDLE:
		pulse = 0.85 + sin(_phase_t * 8.0) * 0.15
	draw_circle(Vector2.ZERO, glow_r1 * pulse, glow_outer)
	draw_circle(Vector2.ZERO, glow_r2 * pulse, glow_inner)
	_draw_icon_body()


func _draw_icon_body() -> void:
	# 本体 = icon 贴图（缩放到 icon_size），无贴图兜底蓝色方块
	var sz: float = PICKUP_ORB_DRAW_DATA["icon_size"]
	if _icon == null:
		draw_rect(Rect2(-sz * 0.5, -sz * 0.5, sz, sz), Color("#7ab8ff"))
		return
	draw_texture_rect(_icon, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false)


func _draw_impact_burst() -> void:
	var col: Color = PICKUP_ORB_DRAW_DATA["hit_dust_color"]
	for p in _impact_burst:
		var life: float = p["life"]
		if life <= 0.0:
			continue
		var a := clampf(life / IMPACT_DUR, 0.0, 1.0)
		var c := Color(col.r, col.g, col.b, a)
		var sz := 1.5 + 1.5 * a
		var pos: Vector2 = p["pos"]
		draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/effects/pickup_orb.gd
git commit -m "feat(pickup): 新增 PickupOrb 飞行拾取球（复刻 SoulOrb，蓝色，icon 本体）"
```

---

### Task 2: 创建 `scripts/effects/pickup_orb_manager.gd`

**Files:**
- Create: `scripts/effects/pickup_orb_manager.gd`

- [ ] **Step 1: 写 manager 脚本（kind 注册表 + spawn_burst 逐个掉 + 到达入账）**

Create `scripts/effects/pickup_orb_manager.gd`:

```gdscript
extends Node2D
class_name PickupOrbManager

# 通用飞行拾取工厂：spawn_burst(pos, kind, count) → 多个 PickupOrb 逐个掉 → 飞达左上角 icon → 入账
# kind 注册表驱动 icon + credit；新增掉落物只加一行
# battle.gd 在 _ready 实例化并 add_child；与 SoulOrbManager 同级

const PickupOrbScript = preload("res://scripts/effects/pickup_orb.gd")

const KEY_ICON := preload("res://assets/ui/icons/system/icon_key.png")
const SILVER_ICON := preload("res://assets/ui/icons/currency/icon_cur_silver.png")

var battle: Node = null
var _registry: Dictionary = {}   # kind -> { icon: Texture2D, credit: Callable }


func setup(battle_node: Node) -> void:
	battle = battle_node
	_registry["key"] = {
		"icon": KEY_ICON,
		"credit": func(amount: int) -> void: _credit_key(amount),
	}
	_registry["silver"] = {
		"icon": SILVER_ICON,
		"credit": func(amount: int) -> void: _credit_silver(amount),
	}


func spawn_burst(world_pos: Vector2, kind: String, count: int) -> void:
	if count <= 0 or battle == null:
		return
	if not _registry.has(kind):
		push_warning("PickupOrbManager: unknown kind %s" % kind)
		return
	var icon: Texture2D = _registry[kind]["icon"]
	for i in range(count):
		# 逐个掉：小幅位置抖动 + 错开起飞延迟
		var jitter := Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		var pos := world_pos + jitter
		var delay := float(i) * 0.09
		if delay <= 0.0:
			_instantiate_orb(pos, kind, 1, icon)
		else:
			var t := get_tree().create_timer(delay)
			t.timeout.connect(_instantiate_orb.bind(pos, kind, 1, icon))


func _instantiate_orb(pos: Vector2, kind: String, amount: int, icon: Texture2D) -> void:
	if not is_instance_valid(self) or battle == null:
		return
	var orb: Node2D = PickupOrbScript.new()
	add_child(orb)
	orb.setup(pos, kind, amount, _make_arrive_callable(kind), icon)


func _make_arrive_callable(kind: String) -> Callable:
	# orb 在 _finish_arrival 里以 on_arrive.call(amount) 回调；这里把 kind 绑进去
	return func(amount: int) -> void: _on_arrive(kind, amount)


func _on_arrive(kind: String, amount: int) -> void:
	if battle == null or battle.player == null:
		return
	if not _registry.has(kind):
		return
	var credit: Callable = _registry[kind]["credit"]
	credit.call(amount)


func _credit_key(amount: int) -> void:
	if battle and battle.player:
		battle.player.add_key(amount)


func _credit_silver(amount: int) -> void:
	if battle and battle.player:
		battle.player.add_silver(amount)


func clear() -> void:
	for child in get_children():
		child.queue_free()
```

- [ ] **Step 2: Commit**

```bash
git add scripts/effects/pickup_orb_manager.gd
git commit -m "feat(pickup): 新增 PickupOrbManager（kind 注册表 + spawn_burst 逐个掉 + 到达入账）"
```

---

### Task 3: 在 `scripts/battle.gd` 接线 PickupOrbManager

**Files:**
- Modify: `scripts/battle.gd:13`（加 preload）
- Modify: `scripts/battle.gd:75`（加 var）
- Modify: `scripts/battle.gd:204-207`（实例化 + setup）
- Modify: `scripts/battle.gd:389-392, 415-418, 464-467, 2009-2012`（clear 调用）

- [ ] **Step 1: 加 preload（紧挨 SoulOrbManagerScript 之后）**

In `scripts/battle.gd`, after line 13 (`const SoulOrbManagerScript = ...`), add:

```gdscript
const PickupOrbManagerScript = preload("res://scripts/effects/pickup_orb_manager.gd")
```

- [ ] **Step 2: 加成员变量（紧挨 soul_orb_manager 之后）**

After line 75 (`var soul_orb_manager: SoulOrbManager`), add:

```gdscript
var pickup_orb_manager: PickupOrbManager
```

- [ ] **Step 3: 实例化 + setup（紧挨 soul_orb_manager setup 之后，line 207 后）**

After the block at lines 204-207:
```gdscript
	soul_orb_manager = SoulOrbManagerScript.new()
	soul_orb_manager.name = "SoulOrbManager"
	add_child(soul_orb_manager)
	soul_orb_manager.setup(self)
```
append:
```gdscript
	pickup_orb_manager = PickupOrbManagerScript.new()
	pickup_orb_manager.name = "PickupOrbManager"
	add_child(pickup_orb_manager)
	pickup_orb_manager.setup(self)
```

- [ ] **Step 4: 在每处 soul_orb_manager.clear() 旁加 pickup_orb_manager.clear()**

共 4 处（约 line 391-392、417-418、466-467、2011-2012）。每处形如：
```gdscript
	if soul_orb_manager:
		soul_orb_manager.clear()
```
在其后追加：
```gdscript
	if pickup_orb_manager:
		pickup_orb_manager.clear()
```
（用 Edit 工具逐处精确替换；因 4 处文本相同，用 `replace_all: true` 一次替换，old_string 为上面两行、new_string 为四行。）

- [ ] **Step 5: Commit**

```bash
git add scripts/battle.gd
git commit -m "feat(battle): 实例化 PickupOrbManager 并随关卡重置 clear"
```

---

### Task 4: HUD 改造（`scripts/ui/hud.gd`）

**Files:**
- Modify: `scripts/ui/hud.gd:24,28`（删 `_gold`/`_coin_icon`，加 `_key_icon`/`_silver_icon`）
- Modify: `scripts/ui/hud.gd:51,61-62`（删 gold 连接 + coin/gold 初始化，换加载 pickup icons）
- Modify: `scripts/ui/hud.gd:100-109`（删 `_load_coin_icon`/`_sync_gold_from_lobby`，加 `_load_pickup_icons`）
- Modify: `scripts/ui/hud.gd:283`（删 `_draw_gold_widget()` 调用）
- Modify: `scripts/ui/hud.gd:351-422`（删 `_draw_gold_widget`，重写 `_draw_key_widget`/`_draw_silver_widget` 为 .png 横向常驻）
- Modify: `scripts/ui/hud.gd:513-515`（删 `_on_gold_changed`）
- Add: `get_pickup_icon_screen_pos(kind)` 方法

- [ ] **Step 1: 成员变量：删金币、加 icon 字段**

Edit `scripts/ui/hud.gd`:
- 删 line 24 `var _gold := 0`（保留 `_wood`/`_keys`/`_silver`）。
- 把 line 28 `var _coin_icon: Texture2D` 替换为：
```gdscript
var _key_icon: Texture2D
var _silver_icon: Texture2D
```

- [ ] **Step 2: `_ready`：删金币连接 + 初始化，换 pickup icon 加载**

Edit `_ready()`（line 50-65 区）。删 line 51 `EventBus.gold_changed.connect(_on_gold_changed)`。把 line 61-62 的：
```gdscript
	_load_coin_icon()
	_sync_gold_from_lobby()
```
替换为：
```gdscript
	_load_pickup_icons()
```
（`_sync_wood_from_lobby()` 保留不动。）

- [ ] **Step 3: 删 `_load_coin_icon`/`_sync_gold_from_lobby`，加 `_load_pickup_icons`**

把 line 100-109 的：
```gdscript
func _load_coin_icon() -> void:
	var path := "res://assets/ui/icons/currency/icon_cur_gold.png"
	if ResourceLoader.exists(path):
		_coin_icon = load(path) as Texture2D


func _sync_gold_from_lobby() -> void:
	if LobbyState:
		_gold = int(LobbyState.gold)
		queue_redraw()
```
替换为：
```gdscript
func _load_pickup_icons() -> void:
	var key_path := "res://assets/ui/icons/system/icon_key.png"
	if ResourceLoader.exists(key_path):
		_key_icon = load(key_path) as Texture2D
	var silver_path := "res://assets/ui/icons/currency/icon_cur_silver.png"
	if ResourceLoader.exists(silver_path):
		_silver_icon = load(silver_path) as Texture2D
```

- [ ] **Step 4: `_draw`：删金币 widget 调用**

Edit line 283-285：
```gdscript
	_draw_gold_widget()
	_draw_key_widget()
	_draw_silver_widget()
```
替换为：
```gdscript
	_draw_key_widget()
	_draw_silver_widget()
```

- [ ] **Step 5: 删 `_draw_gold_widget`，重写 key/silver widget 为 .png 横向常驻**

把 line 351-422 的整段（`_draw_gold_widget` + `_draw_key_widget` + `_draw_silver_widget` 三个函数）替换为：

```gdscript
# 钥匙 widget：icon_key.png + 数量。横向布局，常驻显示（初始 0）。
func _draw_key_widget() -> void:
	var ix := _scaled(12.0)
	var iy := _scaled(10.0)
	var isz := _scaled(18.0)
	if _key_icon != null:
		draw_texture_rect(_key_icon, Rect2(ix, iy, isz, isz), false)
	PixelUi.draw_pixel_text(
		self,
		str(_keys),
		Vector2(ix + isz + _scaled(4.0), iy + isz * 0.5),
		PixelUi.snap_pixel_font_size(int(round(_scaled(10.0)))),
		Color("#ffe090"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER
	)


# 银币 widget：icon_cur_silver.png + 数量。横向布局（钥匙右侧），常驻显示（初始 0）。
func _draw_silver_widget() -> void:
	var ix := _scaled(72.0)
	var iy := _scaled(10.0)
	var isz := _scaled(18.0)
	if _silver_icon != null:
		draw_texture_rect(_silver_icon, Rect2(ix, iy, isz, isz), false)
	PixelUi.draw_pixel_text(
		self,
		str(_silver),
		Vector2(ix + isz + _scaled(4.0), iy + isz * 0.5),
		PixelUi.snap_pixel_font_size(int(round(_scaled(10.0)))),
		Color("#e8eef2"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER
	)


# 供 PickupOrb 取飞行目标：返回该 kind icon 屏幕中心（viewport 系，与 draw 同坐标基）。
func get_pickup_icon_screen_pos(kind: String) -> Vector2:
	var iy := _scaled(10.0)
	var isz := _scaled(18.0)
	match kind:
		"key":
			return Vector2(_scaled(12.0) + isz * 0.5, iy + isz * 0.5)
		"silver":
			return Vector2(_scaled(72.0) + isz * 0.5, iy + isz * 0.5)
		_:
			push_warning("HUD: unknown pickup kind %s" % kind)
			return Vector2(_scaled(72.0) + isz * 0.5, iy + isz * 0.5)
```

- [ ] **Step 6: 删 `_on_gold_changed`**

把 line 513-515 的：
```gdscript
func _on_gold_changed(total_gold: int) -> void:
	_gold = total_gold
	queue_redraw()


```
（含尾随空行）整段删除。

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/hud.gd
git commit -m "feat(hud): 删金币 widget；钥匙/银币换 .png 横向常驻；新增 get_pickup_icon_screen_pos"
```

---

### Task 5: 宝箱改造（`chest_normal.gd` / `chest_locked.gd`）

**Files:**
- Modify: `scripts/entities/chest_normal.gd:11,46-69`
- Modify: `scripts/entities/chest_locked.gd:10,59-80`

- [ ] **Step 1: `chest_normal.gd` — 删 popup const，改 `_open`，删 `_show_popup`**

Edit `scripts/entities/chest_normal.gd`:

(a) 删 line 11：
```gdscript
const ChestResultPopupScript := preload("res://scripts/ui/chest_result_popup.gd")
```

(b) 把 `_open()`（line 46-63）：
```gdscript
func _open() -> void:
	if consumed:
		return
	consumed = true
	# 70% 银 1-3；30% 钥 1
	var is_key := randf() >= 0.7
	if is_key:
		_battle.player.add_key(1)
		_show_popup(1, "key")
	else:
		var n: int = 1 + (randi() % 3)
		_battle.player.add_silver(n)
		_show_popup(n, "silver")
	# 切开盖帧 → 计时消失（宝箱本就不阻挡，unregister 只是清理注册表）
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()
```
替换为：
```gdscript
func _open() -> void:
	if consumed:
		return
	consumed = true
	# 70% 银 1-3；30% 钥 1。货币入账延后到 orb 飞达左上角 icon（pickup_orb_manager._on_arrive）
	var is_key := randf() >= 0.7
	if _battle and _battle.pickup_orb_manager:
		if is_key:
			_battle.pickup_orb_manager.spawn_burst(global_position, "key", 1)
		else:
			var n: int = 1 + (randi() % 3)
			_battle.pickup_orb_manager.spawn_burst(global_position, "silver", n)
	# 切开盖帧 → 计时消失（宝箱本就不阻挡，unregister 只是清理注册表）
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()
```

(c) 删 `_show_popup`（line 66-69）：
```gdscript
func _show_popup(amount: int, kind: String) -> void:
	var popup := ChestResultPopupScript.new()
	get_tree().current_scene.add_child(popup)
	popup.show_result(amount, kind)


```
（含尾随空行）整段删除。

- [ ] **Step 2: `chest_locked.gd` — 同样处理**

Edit `scripts/entities/chest_locked.gd`:

(a) 删 line 10：
```gdscript
const ChestResultPopupScript := preload("res://scripts/ui/chest_result_popup.gd")
```

(b) 把 `_open()`（line 59-74）：
```gdscript
func _open() -> void:
	if consumed:
		return
	consumed = true
	var is_key := randf() >= 0.7
	if is_key:
		_battle.player.add_key(1)
		_show_popup(1, "key")
	else:
		var n: int = 1 + (randi() % 3)
		_battle.player.add_silver(n)
		_show_popup(n, "silver")
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()
```
替换为：
```gdscript
func _open() -> void:
	if consumed:
		return
	consumed = true
	var is_key := randf() >= 0.7
	if _battle and _battle.pickup_orb_manager:
		if is_key:
			_battle.pickup_orb_manager.spawn_burst(global_position, "key", 1)
		else:
			var n: int = 1 + (randi() % 3)
			_battle.pickup_orb_manager.spawn_burst(global_position, "silver", n)
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()
```

(c) 删 `_show_popup`（line 77-80）：
```gdscript
func _show_popup(amount: int, kind: String) -> void:
	var popup := ChestResultPopupScript.new()
	get_tree().current_scene.add_child(popup)
	popup.show_result(amount, kind)


```
（含尾随空行）整段删除。

（注：`chest_locked.gd` 缺钥匙时的 `UI_CHEST_LOCKED_NEED_KEY` 提示与 `spend_key()` 保持不动。）

- [ ] **Step 3: Commit**

```bash
git add scripts/entities/chest_normal.gd scripts/entities/chest_locked.gd
git commit -m "feat(chest): 开箱改用 PickupOrb 飞行拾取，移除 ChestResultPopup 弹窗"
```

---

### Task 6: 跑游戏验证

**Files:** 无（运行验证）

- [ ] **Step 1: 跑项目，确认无脚本错误**

Run（用 godot MCP `run_project` 或本机 Godot 启动）：
```
projectPath = D:\workspace\rzz_godot_newtry
```
Expected: 控制台无 `script error` / `parse error` / `Could not preload` 报错；游戏正常进入战斗。

- [ ] **Step 2: 视觉验证 — 左上角 HUD**

进入战斗后观察左上角：
- 无金币 widget。
- 钥匙 icon（icon_key.png）与银币 icon（icon_cur_silver.png）横向并排，各自数字初始为 `0`。

- [ ] **Step 3: 视觉验证 — 普通宝箱银币**

走到普通宝箱触发：
- 1-3 个银币 icon 从宝箱位置发光（蓝色外发光）抛起+落回 → 短暂停留（~0.25s 上下浮动）→ 蓝色拖尾飞向左上角银币 icon → 蓝色粒子爆裂 → 银币计数 +N。
- 无居中 +N 弹窗。

- [ ] **Step 4: 视觉验证 — 钥匙宝箱**

触发钥匙奖励：钥匙 icon 同流程飞向左上角钥匙 icon → 计数 +1。

- [ ] **Step 5: 视觉验证 — 锁定宝箱**

无钥匙撞锁定宝箱：显示 `UI_CHEST_LOCKED_NEED_KEY`，不打开。
持有钥匙撞锁定宝箱：钥匙计数即时 -1（spend_key），随后开出 reward 飞行 +N（钥匙或银币）。

- [ ] **Step 6: i18n 检查**

暂停菜单切 English：HUD 数字正常显示，无中文残留、无 `[UI_XXX]` 占位。（本任务无新增文字，应全部通过。）

- [ ] **Step 7: 多次开箱稳定性**

连续开 5+ 宝箱：计数累计正确、无 orb 残留、无报错刷屏。

- [ ] **Step 8: Commit 验证记录（可选）**

如一切正常，无需额外 commit；若过程中修了小 bug，按修改单独 commit。

---

## Self-Review（已完成）

- **Spec 覆盖**：删金币✓(Task4)、.png icon✓(Task4)、横向常驻初始0✓(Task4)、宝箱飞行拾取蓝色复刻SoulOrb✓(Task1+2+5)、移除popup✓(Task5)、battle接线✓(Task3)、icon尺寸调整✓(Task4 isz=18 + Task1 icon_size=18)。全部覆盖。
- **占位符扫描**：无 TBD/TODO；每步含完整代码。
- **类型一致**：`setup(start_pos, kind, amount, on_arrive, icon)`（Task1）↔ manager 调用 `orb.setup(pos, kind, amount, _make_arrive_callable(kind), icon)`（Task2）一致；`spawn_burst(world_pos, kind, count)`（Task2）↔ 宝箱调用 `_battle.pickup_orb_manager.spawn_burst(global_position, "key"/"silver", n)`（Task5）一致；`get_pickup_icon_screen_pos(kind)`（Task4）↔ orb `battle.hud.get_pickup_icon_screen_pos(_kind)`（Task1）一致；`pickup_orb_manager` 成员（Task3）↔ 宝箱 `_battle.pickup_orb_manager`（Task5）一致。
