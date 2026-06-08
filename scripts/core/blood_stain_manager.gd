extends Node2D
class_name BloodStainManager

const MAX_STAINS := 220
const FADE_DURATION := 10.0
const MIN_ALPHA := 0.22
const FADE_REBUILD_INTERVAL := 0.12

const COLORS: Array[Color] = [
	Color("#f0a8a8"),
	Color("#e89090"),
	Color("#ffc8c8"),
]

var stains: Array = []

var _world_size := Vector2(720.0, 1280.0)
var _cache_image: Image
var _cache_texture: ImageTexture
var _cache_ready := false
var _fade_timer := 0.0


func configure(world_w: float, world_h: float) -> void:
	_world_size = Vector2(world_w, world_h)
	_reset_cache()


func clear() -> void:
	stains.clear()
	_fade_timer = 0.0
	if _cache_ready:
		_cache_image.fill(Color(0, 0, 0, 0))
		_cache_texture.update(_cache_image)
	queue_redraw()


func update_stains(delta: float) -> void:
	if stains.is_empty():
		return
	var removed := false
	var i := stains.size() - 1
	while i >= 0:
		var s: Dictionary = stains[i]
		var age := float(s.get("age", 0.0)) + delta
		if age >= FADE_DURATION:
			stains.remove_at(i)
			removed = true
		else:
			s["age"] = age
			stains[i] = s
		i -= 1
	if removed:
		_trim()
		_rebuild_cache()
		queue_redraw()
		_fade_timer = FADE_REBUILD_INTERVAL
		return
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		_fade_timer = FADE_REBUILD_INTERVAL
		_rebuild_cache()
		queue_redraw()


func spawn(x: float, y: float, intensity: float = 1.0, from_angle = null) -> void:
	var base_ang := randf() * TAU if from_angle == null else float(from_angle)
	var drops: Array = []
	var drop_count := int(floor(6.0 + 9.0 * intensity))
	for i in range(drop_count):
		var a := base_ang + randf_range(-1.2, 1.2)
		var d := randf_range(3.0, 28.0 * intensity)
		drops.append({
			"x": cos(a) * d,
			"y": sin(a) * d * 0.75,
			"r": randf_range(1.2, 3.8) * intensity,
			"c": COLORS[randi() % COLORS.size()],
		})
	stains.append({"x": x, "y": y, "drops": drops, "age": 0.0})
	if stains.size() > MAX_STAINS:
		_trim()
		_rebuild_cache()
	elif _cache_ready:
		_paint_stain(stains[stains.size() - 1])
		_cache_texture.update(_cache_image)
	queue_redraw()


func _draw() -> void:
	if _cache_ready:
		draw_texture(_cache_texture, Vector2.ZERO)


func _reset_cache() -> void:
	var w := maxi(1, int(_world_size.x))
	var h := maxi(1, int(_world_size.y))
	_cache_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_cache_image.fill(Color(0, 0, 0, 0))
	_cache_texture = ImageTexture.create_from_image(_cache_image)
	_cache_ready = true
	if not stains.is_empty():
		_rebuild_cache()


func _rebuild_cache() -> void:
	if not _cache_ready:
		return
	_cache_image.fill(Color(0, 0, 0, 0))
	for s in stains:
		_paint_stain(s)
	_cache_texture.update(_cache_image)


func _paint_stain(stain: Dictionary) -> void:
	var alpha := _alpha(float(stain.get("age", 0.0)))
	if alpha <= 0.001:
		return
	var ox := int(round(float(stain.x)))
	var oy := int(round(float(stain.y)))
	for d in stain.drops:
		var col: Color = d.c
		col.a = alpha * col.a
		_blit_circle(
			ox + int(round(float(d.x))),
			oy + int(round(float(d.y))),
			int(max(1.0, round(float(d.r)))),
			col
		)


func _blit_circle(cx: int, cy: int, radius: int, col: Color) -> void:
	if col.a <= 0.001:
		return
	var img_w := _cache_image.get_width()
	var img_h := _cache_image.get_height()
	var r2 := radius * radius
	var y0 := maxi(0, cy - radius)
	var y1 := mini(img_h - 1, cy + radius)
	var x0 := maxi(0, cx - radius)
	var x1 := mini(img_w - 1, cx + radius)
	for y in range(y0, y1 + 1):
		var dy := y - cy
		var dy2 := dy * dy
		for x in range(x0, x1 + 1):
			var dx := x - cx
			if dx * dx + dy2 <= r2:
				var existing := _cache_image.get_pixel(x, y)
				_cache_image.set_pixel(x, y, _blend(existing, col))


func _blend(dst: Color, src: Color) -> Color:
	var src_a := src.a
	if src_a <= 0.001:
		return dst
	var dst_a := dst.a
	var out_a := src_a + dst_a * (1.0 - src_a)
	if out_a <= 0.001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var out_rgb := (src * src_a + dst * dst_a * (1.0 - src_a)) / out_a
	out_rgb.a = out_a
	return out_rgb


func _trim() -> void:
	while stains.size() > MAX_STAINS:
		stains.remove_at(0)


func _alpha(age: float) -> float:
	if age >= FADE_DURATION:
		return MIN_ALPHA
	var t := age / FADE_DURATION
	return MIN_ALPHA + (1.0 - MIN_ALPHA) * (1.0 - t)
