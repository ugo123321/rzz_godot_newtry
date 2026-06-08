extends Node2D
class_name TerrainBackground

const PROP_TEXTURES: Array[String] = [
	"res://assets/Terrain/Rocks/6.png",
	"res://assets/Terrain/Rocks/7.png",
	"res://assets/Terrain/Rocks/8.png",
	"res://assets/Terrain/Rocks/9.png",
	"res://assets/Terrain/Trees/Tree1.png",
	"res://assets/Terrain/Trees/4.png",
	"res://assets/Terrain/Trees/5.png",
]

var _decor_root: Node2D


func setup_for_stage(_stage_index: int, safe_zone: Dictionary = {}) -> void:
	_clear_children()
	_spawn_props(safe_zone)


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_decor_root = null


func has_grass_tiles() -> bool:
	return false


func _spawn_props(safe_zone: Dictionary) -> void:
	_decor_root = Node2D.new()
	_decor_root.name = "Decorations"
	_decor_root.z_index = -1
	add_child(_decor_root)

	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var play_bottom := PixelUiHelper.get_play_area_bottom(h)
	var top_pad := maxf(100.0, h * 0.14)
	var placed: Array[Vector2] = []
	var prop_count := int(GameConfig.get_tuning("terrain_prop_count", 8))

	for i in range(prop_count):
		var min_dist := 70.0 if i < 4 else 58.0
		var pos := _pick_clear_pos(w, h, top_pad, play_bottom - 12.0, safe_zone, min_dist, placed, 120)
		if pos.x < 0.0:
			continue
		var path := PROP_TEXTURES[(i + stage_hash(i)) % PROP_TEXTURES.size()]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = true
		sprite.position = pos
		var scale_val := 1.0
		if path.contains("Rocks"):
			scale_val = MathUtils.rand_range(1.8, 2.3)
		else:
			scale_val = MathUtils.rand_range(1.7, 2.1)
		sprite.scale = Vector2.ONE * scale_val
		_decor_root.add_child(sprite)
		placed.append(pos)


func _pick_clear_pos(
	world_w: float,
	world_h: float,
	top_y: float,
	bottom_y: float,
	safe_zone: Dictionary,
	min_dist: float,
	placed: Array[Vector2],
	max_attempts: int
) -> Vector2:
	for _attempt in range(max_attempts):
		var pos := Vector2(
			MathUtils.rand_range(20.0, world_w - 20.0),
			MathUtils.rand_range(top_y, bottom_y)
		)
		if not _is_position_clear(pos, safe_zone, min_dist, placed):
			continue
		return pos
	return Vector2(-1.0, -1.0)


func _is_position_clear(pos: Vector2, safe_zone: Dictionary, min_dist: float, placed: Array[Vector2]) -> bool:
	if not safe_zone.is_empty():
		var dx := pos.x - float(safe_zone.get("x", 0.0))
		var dy := pos.y - float(safe_zone.get("y", 0.0))
		var pad := float(safe_zone.get("r", 0.0)) + 24.0
		if dx * dx + dy * dy <= pad * pad:
			return false
	for other in placed:
		if pos.distance_to(other) < min_dist:
			return false
	return true


func stage_hash(i: int) -> int:
	return (i * 17 + 3) % 997
