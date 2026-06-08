extends Node2D
class_name GrassSystem

const GRASS_PALETTES := [
	[Color("#3a6838"), Color("#4a8048"), Color("#5a9858")],
	[Color("#3a6038"), Color("#4a7848"), Color("#5a9050")],
	[Color("#446840"), Color("#528050"), Color("#609860")],
]

var blades: Array = []
var field_ready := false


func init_field(world_w: float, world_h: float, play_area_bottom: float, safe_zone: Dictionary = {}) -> void:
	blades.clear()
	var max_clusters := int(GameConfig.get_tuning("grass_cluster_max", 22))
	var count := mini(max_clusters, int(floor(world_w * world_h / 45000.0)))
	var top_pad := maxf(100.0, world_h * 0.14)
	var grass_bottom := maxf(top_pad + 40.0, play_area_bottom - 16.0)
	var exclusion_pad := 12.0
	var max_attempts := count * 24
	var created := 0
	var attempts := 0
	while created < count and attempts < max_attempts:
		attempts += 1
		var x := MathUtils.rand_range(16.0, world_w - 16.0)
		var y := MathUtils.rand_range(top_pad, grass_bottom)
		if not safe_zone.is_empty():
			var dx := x - float(safe_zone.get("x", 0.0))
			var dy := y - float(safe_zone.get("y", 0.0))
			var rr := float(safe_zone.get("r", 0.0)) + exclusion_pad
			if dx * dx + dy * dy <= rr * rr:
				continue
		blades.append({
			"x": x,
			"y": y,
			"variant": randi() % 3,
			"scale": MathUtils.rand_range(2.5, 3.8),
			"height": int(floor(MathUtils.rand_range(3.5, 6.0))),
			"phase": MathUtils.rand_range(0.0, TAU),
			"speed": MathUtils.rand_range(1.4, 3.2),
			"sway_amp": MathUtils.rand_range(0.14, 0.28),
			"offset": MathUtils.rand_range(-1.0, 1.0),
		})
		created += 1
	field_ready = created > 0
	queue_redraw()


func update_field(delta: float) -> void:
	if not field_ready:
		return
	for blade in blades:
		blade.phase = float(blade.phase) + delta * float(blade.speed)
	queue_redraw()


func _draw() -> void:
	if not field_ready:
		return
	for blade in blades:
		_draw_tuft(blade)


func _draw_tuft(blade: Dictionary) -> void:
	var palette: Array = GRASS_PALETTES[int(blade.variant) % GRASS_PALETTES.size()]
	var s: float = float(blade.scale)
	var sway := sin(float(blade.phase)) * float(blade.sway_amp)
	var base_x := int(floor(float(blade.x)))
	var base_y := int(floor(float(blade.y)))
	var offset: float = float(blade.offset)
	var height: int = int(blade.height)

	for blade_idx in range(-1, 2):
		var lean := sway + float(blade_idx) * 0.08
		var origin := Vector2(base_x + offset * s, base_y)
		draw_set_transform(origin, lean + float(blade_idx) * 0.12, Vector2.ONE)
		for i in range(height):
			var color: Color = palette[mini(i, palette.size() - 1)]
			draw_rect(Rect2(-s * 0.5 + blade_idx, -float(i + 1) * s, s, s), color)
	draw_set_transform(Vector2(base_x + offset * s, base_y), 0.0, Vector2.ONE)
	draw_rect(Rect2(-s, 0.0, s * 2.0, s), palette[0])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
