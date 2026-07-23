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
