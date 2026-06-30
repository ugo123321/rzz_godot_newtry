extends Node2D
class_name SoulOrb

# 怪物死亡掉落的"灵魂粒子球"：地上短停顿 → 飞向 HUD 经验条 → 命中后真正加经验
# 设计文档：C:/Users/admin/.claude/plans/icon-ui-photoshop-ui-polymorphic-haven.md
# 数据驱动绘制范式遵循 CLAUDE.md 第九条（参考 summon_ability_manager.gd SUMMON_DRAW_DATA）

const PHASE_SPAWN := 0     # 0.15s 上跳 + 落回
const PHASE_IDLE := 1      # ~0.25s 悬浮 + 闪烁
const PHASE_FLY := 2       # 0.45s Tween 飞向经验条
const PHASE_IMPACT := 3    # 0.10s 命中爆 → queue_free

const SPAWN_DUR := 0.15
const SPAWN_RISE := 8.0
const IDLE_DUR := 0.25
const IDLE_BOB_AMP := 2.0
const FLY_DUR := 0.45
const IMPACT_DUR := 0.10

const SOUL_ORB_DRAW_DATA := {
	"core_palette": [
		Color("#a8ff7a"),   # 0 高光
		Color("#62e84a"),   # 1 主色
		Color("#2eb02a"),   # 2 中暗
		Color("#0a5018"),   # 3 最深
	],
	"core_radius": 5.0,
	"core_flicker_ms": 80,
	"glow_r1": 16.0,
	"glow_r2": 9.0,
	"glow_outer_color": Color(0.45, 1.0, 0.45, 0.22),
	"glow_inner_color": Color(0.85, 1.0, 0.65, 0.42),
	"trail_color": Color(0.55, 1.0, 0.4, 0.45),
	"trail_max": 8,
	"hit_dust_color": Color("#a8ff7a"),
	"hit_dust_count": 12,
}

var exp_amount: int = 0
var _phase: int = PHASE_SPAWN
var _phase_t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO
var _on_arrive: Callable = Callable()
var _trail: Array[Vector2] = []
var _impact_burst: Array[Dictionary] = []   # [{pos, vel, life}]


func setup(start_pos: Vector2, p_exp: int, p_on_arrive: Callable) -> void:
	global_position = start_pos
	_base_pos = start_pos
	exp_amount = maxi(0, p_exp)
	_on_arrive = p_on_arrive
	z_index = 5    # 在血迹 (-4) 之上，UI 之下


func _process(delta: float) -> void:
	_phase_t += delta
	match _phase:
		PHASE_SPAWN:
			# 上抛 + 阻尼落回（用正弦半周期模拟弹跳）
			var t := clampf(_phase_t / SPAWN_DUR, 0.0, 1.0)
			var rise := sin(t * PI) * SPAWN_RISE
			global_position = _base_pos + Vector2(0.0, -rise)
			if _phase_t >= SPAWN_DUR:
				_enter(PHASE_IDLE)
				_base_pos = global_position
		PHASE_IDLE:
			# 悬浮微浮 + 闪烁（_draw 里读 ticks）
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
	# 算 HUD 经验条中心（屏幕坐标 → 世界坐标）
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
	# 复用 ui_sprite_helper.gd:261-284 的经验条位置公式
	var ui_scale := 1.0
	if GameConfig.has_method("get_resolution_scale"):
		ui_scale = GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()
	var pad := 10.0 * ui_scale
	var bar_h := 18.0 * ui_scale   # UiSpriteHelper.BAR_VISUAL_HEIGHT
	var vp := get_viewport_rect().size
	var bar_center_screen := Vector2(vp.x * 0.5, vp.y - bar_h * 0.5 - pad)
	# 屏幕 → 世界（battle.gd:2074 同款）
	var xform := get_viewport().get_canvas_transform()
	return xform.affine_inverse() * bar_center_screen


func _on_fly_finished() -> void:
	_finish_arrival()


func _finish_arrival() -> void:
	if _on_arrive.is_valid():
		_on_arrive.call(exp_amount)
	# 启动 impact 粒子爆
	_impact_burst.clear()
	var count := int(SOUL_ORB_DRAW_DATA["hit_dust_count"])
	for i in range(count):
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
	var max_n := int(SOUL_ORB_DRAW_DATA["trail_max"])
	while _trail.size() > max_n:
		_trail.pop_front()


func _draw() -> void:
	if _phase == PHASE_IMPACT:
		_draw_impact_burst()
		return
	# 飞行尾迹（FLY phase 才有）
	if _phase == PHASE_FLY and _trail.size() >= 2:
		var trail_col: Color = SOUL_ORB_DRAW_DATA["trail_color"]
		for i in range(_trail.size() - 1):
			var t := float(i) / float(_trail.size())
			var a := lerpf(0.0, trail_col.a, t)
			var col := Color(trail_col.r, trail_col.g, trail_col.b, a)
			# trail 用全局坐标，需转本地
			var p1 := to_local(_trail[i])
			var p2 := to_local(_trail[i + 1])
			draw_line(p1, p2, col, 2.0 + t * 2.0)
	# 双层外发光圆晕
	var glow_r1: float = SOUL_ORB_DRAW_DATA["glow_r1"]
	var glow_r2: float = SOUL_ORB_DRAW_DATA["glow_r2"]
	var glow_outer: Color = SOUL_ORB_DRAW_DATA["glow_outer_color"]
	var glow_inner: Color = SOUL_ORB_DRAW_DATA["glow_inner_color"]
	# IDLE 期间圆晕呼吸
	var pulse := 1.0
	if _phase == PHASE_IDLE:
		pulse = 0.85 + sin(_phase_t * 8.0) * 0.15
	draw_circle(Vector2.ZERO, glow_r1 * pulse, glow_outer)
	draw_circle(Vector2.ZERO, glow_r2 * pulse, glow_inner)
	_draw_pixel_core()


func _draw_pixel_core() -> void:
	# 像素核心：5×5 网格，按闪烁周期切换调色板（CLAUDE.md 第九条 50-150ms）
	var palette: Array = SOUL_ORB_DRAW_DATA["core_palette"]
	var flicker_ms: int = int(SOUL_ORB_DRAW_DATA["core_flicker_ms"])
	var phase_idx := int(Time.get_ticks_msec() / flicker_ms) % 2
	# 5×5 网格：1=主, 2=中暗, 3=最深, 0=高光（闪烁时高光位置切换）
	var grid_a := [
		[3, 2, 2, 2, 3],
		[2, 1, 1, 1, 2],
		[2, 1, 0, 1, 2],
		[2, 1, 1, 1, 2],
		[3, 2, 2, 2, 3],
	]
	var grid_b := [
		[3, 2, 2, 2, 3],
		[2, 1, 0, 1, 2],
		[2, 0, 1, 0, 2],
		[2, 1, 0, 1, 2],
		[3, 2, 2, 2, 3],
	]
	var grid: Array = grid_b if phase_idx == 1 else grid_a
	var px := 2.0   # 每格 2px（视觉直径 10px）
	var origin := Vector2(-2.5 * px, -2.5 * px)
	for y in range(5):
		for x in range(5):
			var idx: int = grid[y][x]
			var col: Color = palette[idx]
			draw_rect(Rect2(origin + Vector2(x * px, y * px), Vector2(px, px)), col)


func _draw_impact_burst() -> void:
	var col: Color = SOUL_ORB_DRAW_DATA["hit_dust_color"]
	for p in _impact_burst:
		var life: float = p["life"]
		if life <= 0.0:
			continue
		var a := clampf(life / IMPACT_DUR, 0.0, 1.0)
		var c := Color(col.r, col.g, col.b, a)
		var sz := 1.5 + 1.5 * a
		var pos: Vector2 = p["pos"]
		draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)
