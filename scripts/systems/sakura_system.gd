extends Node2D
class_name SakuraSystem

const PETAL_COLORS := [
	Color("#ffb7c5"),
	Color("#ffc8d8"),
	Color("#f8a0b0"),
	Color("#ffe8ee"),
	Color("#f5c6d0"),
]

var petals: Array = []
var active := false
var timer := 0.0
var duration := 5.5
var fade_out_duration := 1.8
var _petal_count := 42
var _world_size := Vector2.ZERO


func start_field(world_w: float, world_h: float, field_duration: float = -1.0) -> void:
	petals.clear()
	active = true
	_world_size = Vector2(world_w, world_h)
	duration = float(GameConfig.get_tuning("sakura_default_duration", 5.5))
	fade_out_duration = float(GameConfig.get_tuning("sakura_fade_out_duration", 1.8))
	_petal_count = int(GameConfig.get_tuning("sakura_petal_count", 42))
	if field_duration >= 0.0:
		duration = field_duration
	timer = duration
	for i in range(_petal_count):
		petals.append({
			"x": MathUtils.rand_range(0.0, world_w),
			"y": MathUtils.rand_range(-world_h * 0.25, world_h * 0.08),
			"vx": MathUtils.rand_range(-18.0, 18.0),
			"vy": MathUtils.rand_range(28.0, 62.0),
			"rot": MathUtils.rand_range(0.0, TAU),
			"spin": MathUtils.rand_range(-1.8, 1.8),
			"sway": MathUtils.rand_range(0.8, 2.2),
			"sway_phase": MathUtils.rand_range(0.0, TAU),
			"size": MathUtils.rand_range(3.0, 7.0),
			"color": PETAL_COLORS[randi() % PETAL_COLORS.size()],
		})
	queue_redraw()


func stop_field() -> void:
	active = false
	petals.clear()
	timer = 0.0
	queue_redraw()


func update_field(delta: float, world_w: float, world_h: float) -> void:
	if not active:
		return
	_world_size = Vector2(world_w, world_h)
	timer -= delta
	if timer <= 0.0:
		stop_field()
		return
	var fading := timer <= fade_out_duration
	for p in petals:
		p.sway_phase = float(p.sway_phase) + delta * float(p.sway)
		p.x = float(p.x) + (float(p.vx) + sin(float(p.sway_phase)) * 22.0) * delta
		p.y = float(p.y) + float(p.vy) * delta
		p.rot = float(p.rot) + float(p.spin) * delta
		if not fading and float(p.y) > world_h + 20.0:
			p.y = MathUtils.rand_range(-40.0, -8.0)
			p.x = MathUtils.rand_range(0.0, world_w)
		if float(p.x) < -20.0:
			p.x = world_w + 10.0
		if float(p.x) > world_w + 20.0:
			p.x = -10.0
	queue_redraw()


func _draw() -> void:
	if not active or petals.is_empty():
		return
	var master_alpha := _get_fade_alpha()
	if master_alpha <= 0.0:
		return
	var layer_alpha := (0.4 + master_alpha * 0.5) * master_alpha
	for p in petals:
		_draw_petal(p, master_alpha * layer_alpha)


func _get_fade_alpha() -> float:
	if timer <= fade_out_duration:
		return clampf(timer / fade_out_duration, 0.0, 1.0)
	return 1.0


func _draw_petal(p: Dictionary, master_alpha: float) -> void:
	var s: float = float(p.size)
	var pos := Vector2(float(p.x), float(p.y))
	var color: Color = p.color
	color.a = 0.82 * master_alpha
	draw_set_transform(pos, float(p.rot), Vector2.ONE)
	for i in range(5):
		draw_set_transform(pos, float(p.rot) + float(i) / 5.0 * TAU, Vector2.ONE)
		_draw_ellipse(Vector2.ZERO, Vector2(s * 0.38, s * 0.72), Vector2(0.0, -s * 0.55), color)
	var center := Color("#fff5f8")
	center.a = 0.55 * master_alpha
	draw_circle(Vector2.ZERO, s * 0.18, center)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ellipse(center: Vector2, radius: Vector2, offset: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 12
	for i in range(steps):
		var ang := float(i) / float(steps) * TAU
		points.append(center + offset + Vector2(cos(ang) * radius.x, sin(ang) * radius.y))
	draw_colored_polygon(points, color)
