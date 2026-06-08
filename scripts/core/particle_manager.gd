extends Node2D
class_name ParticleManager

const POOL_SIZE := 500

var pool: Array = []
var lightning_bolts: Array = []


func _ready() -> void:
	for i in range(POOL_SIZE):
		pool.append({"active": false})


func clear() -> void:
	for p in pool:
		p.active = false
	lightning_bolts.clear()
	queue_redraw()


func has_active_effects() -> bool:
	if not lightning_bolts.is_empty():
		return true
	for p in pool:
		if p.active:
			return true
	return false


func emit_particle(x: float, y: float, vx: float, vy: float, life: float, size: float, color: Color, gravity: float = 0.0, shrink: bool = true, glow: bool = false) -> void:
	for p in pool:
		if p.active:
			continue
		p.active = true
		p.pos = Vector2(x, y)
		p.vel = Vector2(vx, vy)
		p.life = life
		p.max_life = life
		p.size = size
		p.color = color
		p.gravity = gravity
		p.shrink = shrink
		p.glow = glow
		return


func hit_spark(pos: Vector2, is_crit: bool) -> void:
	var count := 20 if is_crit else 10
	var colors: Array = [Color("#ffff00"), Color("#ff8800"), Color("#ff4444"), Color.WHITE] if is_crit else [Color.WHITE, Color("#ffff00"), Color("#aaddff")]
	for i in range(count):
		var a := randf() * TAU
		var speed := randf_range(60.0, 250.0 if is_crit else 150.0)
		emit_particle(
			pos.x, pos.y,
			cos(a) * speed, sin(a) * speed,
			randf_range(0.2, 0.5), randf_range(2.0, 6.0 if is_crit else 4.0),
			colors[randi() % colors.size()], 100.0, true, true
		)


func hit_blood_splash(pos: Vector2, from_angle: float, is_crit: bool = false) -> void:
	var colors: Array[Color] = [
		Color("#c22a20"),
		Color("#e84040"),
		Color("#8a1010"),
		Color("#ff7070"),
	]
	var count := 12 if is_crit else 8
	for i in range(count):
		var a := from_angle + randf_range(-1.0, 1.0)
		var speed := randf_range(55.0, 170.0 if is_crit else 120.0)
		emit_particle(
			pos.x + randf_range(-3.0, 3.0),
			pos.y + randf_range(-3.0, 3.0),
			cos(a) * speed,
			sin(a) * speed,
			randf_range(0.14, 0.32),
			randf_range(2.0, 5.0 if is_crit else 3.5),
			colors[randi() % colors.size()],
			140.0,
			true,
			false
		)


func lightning_effect(from_pos: Vector2, to_pos: Vector2) -> void:
	var dist := from_pos.distance_to(to_pos)
	var segments := maxi(18, int(floor(dist / 14.0)))
	var jitter := maxf(22.0, dist * 0.14)
	var life := clampf(0.75 + dist * 0.0022, 0.85, 1.25)
	var points := PackedVector2Array([from_pos])
	for i in range(1, segments):
		var t := float(i) / float(segments)
		points.append(Vector2(
			from_pos.x + (to_pos.x - from_pos.x) * t + randf_range(-jitter, jitter),
			from_pos.y + (to_pos.y - from_pos.y) * t + randf_range(-jitter, jitter)
		))
	points.append(to_pos)
	lightning_bolts.append({
		"points": points,
		"life": life,
		"max_life": life,
	})

	var spark_colors: Array[Color] = [
		Color("#ffff00"),
		Color.WHITE,
		Color("#88eeff"),
		Color("#cceeff"),
	]
	var spark_count := maxi(28, int(floor(dist / 10.0)))
	for i in range(spark_count + 1):
		var t := float(i) / float(spark_count)
		emit_particle(
			from_pos.x + (to_pos.x - from_pos.x) * t + randf_range(-14.0, 14.0),
			from_pos.y + (to_pos.y - from_pos.y) * t + randf_range(-14.0, 14.0),
			randf_range(-40.0, 40.0),
			randf_range(-40.0, 40.0),
			randf_range(0.35, 0.65),
			randf_range(5.0, 11.0),
			spark_colors[randi() % spark_colors.size()],
			0.0,
			true,
			true
		)

	for i in range(14):
		var a := float(i) / 14.0 * TAU
		var spd := randf_range(80.0, 180.0)
		emit_particle(
			from_pos.x, from_pos.y,
			cos(a) * spd, sin(a) * spd,
			randf_range(0.28, 0.5), randf_range(6.0, 12.0),
			Color.WHITE, 0.0, true, true
		)
		emit_particle(
			to_pos.x, to_pos.y,
			cos(a) * spd, sin(a) * spd,
			randf_range(0.28, 0.5), randf_range(6.0, 12.0),
			Color("#ffff00"), 0.0, true, true
		)


func slash_trail(pos: Vector2, ang: float) -> void:
	for i in range(6):
		var along := randf_range(-12.0, 18.0)
		var perp := ang + PI * 0.5
		var spread := randf_range(-14.0, 14.0)
		var px := pos.x + cos(ang) * along + cos(perp) * spread
		var py := pos.y + sin(ang) * along + sin(perp) * spread
		var speed := randf_range(80.0, 200.0)
		emit_particle(
			px, py,
			cos(ang + randf_range(-0.4, 0.4)) * speed,
			sin(ang + randf_range(-0.4, 0.4)) * speed,
			randf_range(0.12, 0.28), randf_range(3.0, 7.0),
			Color(0.95, 0.97, 1.0), 0.0, true, true
		)


func death_effect(pos: Vector2, color: Color, scale: float = 1.0) -> void:
	var s := clampf(scale, 0.75, 2.2)
	var bright := color.lerp(Color.WHITE, 0.45)
	var hot := color.lerp(Color("#fff4a8"), 0.55)
	var blood_colors: Array[Color] = [
		Color("#c22a20"),
		Color("#e84040"),
		Color("#ff7070"),
	]
	for i in range(int(10.0 * s)):
		var a := randf() * TAU
		var speed := randf_range(90.0, 220.0) * s
		emit_particle(
			pos.x + randf_range(-2.0, 2.0),
			pos.y + randf_range(-2.0, 2.0),
			cos(a) * speed,
			sin(a) * speed,
			randf_range(0.28, 0.55),
			randf_range(4.0, 9.0) * s,
			hot,
			80.0,
			true,
			true
		)
	for i in range(int(22.0 * s)):
		var a := randf() * TAU
		var speed := randf_range(55.0, 170.0) * s
		emit_particle(
			pos.x,
			pos.y,
			cos(a) * speed,
			sin(a) * speed,
			randf_range(0.35, 0.75),
			randf_range(3.5, 7.5) * s,
			bright if i % 3 == 0 else color,
			70.0,
			true,
			i % 4 == 0
		)
	for i in range(int(12.0 * s)):
		var a := randf_range(-PI * 0.85, -PI * 0.15)
		var speed := randf_range(40.0, 130.0) * s
		emit_particle(
			pos.x + randf_range(-4.0, 4.0),
			pos.y + randf_range(-4.0, 4.0),
			cos(a) * speed,
			sin(a) * speed,
			randf_range(0.3, 0.65),
			randf_range(2.5, 5.5) * s,
			blood_colors[randi() % blood_colors.size()],
			120.0,
			true,
			false
		)


func update_particles(delta: float) -> void:
	var any := false
	for p in pool:
		if not p.active:
			continue
		any = true
		p.pos += p.vel * delta
		p.vel.y += float(p.gravity) * delta
		p.life -= delta
		if p.life <= 0.0:
			p.active = false
	for i in range(lightning_bolts.size() - 1, -1, -1):
		any = true
		lightning_bolts[i].life -= delta
		if lightning_bolts[i].life <= 0.0:
			lightning_bolts.remove_at(i)
	if any:
		queue_redraw()


func _draw_lightning_bolts(canvas: Node2D, offset: Vector2) -> void:
	for bolt in lightning_bolts:
		var points: PackedVector2Array = bolt.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var t := clampf(float(bolt.life) / float(bolt.max_life), 0.0, 1.0)
		var local_points := PackedVector2Array()
		local_points.resize(points.size())
		for i in range(points.size()):
			local_points[i] = points[i] + offset

		var outer := Color(0.39, 0.78, 1.0, 0.65 * t)
		canvas.draw_polyline(local_points, outer, 16.0, true)
		canvas.draw_polyline(local_points, Color(1.0, 1.0, 1.0, t), 6.0, true)
		canvas.draw_polyline(local_points, Color(1.0, 0.91, 0.25, t), 3.0, true)


func draw_particles(canvas: Node2D) -> void:
	var offset := -canvas.global_position
	_draw_lightning_bolts(canvas, offset)
	for p in pool:
		if not p.active:
			continue
		var t := clampf(float(p.life) / float(p.max_life), 0.0, 1.0)
		var s := float(p.size) * t if bool(p.shrink) else float(p.size)
		var col: Color = p.color
		col.a = t
		var rect := Rect2(p.pos + offset - Vector2(s * 0.5, s * 0.5), Vector2(s, s))
		if bool(p.glow):
			var glow_col := col
			glow_col.a = t * 0.42
			var gs := s * 2.0
			canvas.draw_rect(Rect2(p.pos + offset - Vector2(gs * 0.5, gs * 0.5), Vector2(gs, gs)), glow_col)
		canvas.draw_rect(rect, col)
