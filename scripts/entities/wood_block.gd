extends RigidBody2D
class_name WoodBlock

const SETTLE_VEL := 25.0
const SETTLE_TIME := 0.35

var size_px := 72.0
var max_y := 0.0
var is_settled := false
var _low_v_t := 0.0
var _flicker_seed := 0.0


func setup(size: float) -> void:
	size_px = size
	_flicker_seed = randf() * TAU
	gravity_scale = 1.6
	mass = 1.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.95
	physics_material_override.bounce = 0.05
	contact_monitor = false
	can_sleep = true
	# Build collision shape
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size_px, size_px)
	var coll := CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)


func _physics_process(delta: float) -> void:
	if is_settled:
		return
	if linear_velocity.length() < SETTLE_VEL and absf(angular_velocity) < 1.0:
		_low_v_t += delta
		if _low_v_t >= SETTLE_TIME:
			is_settled = true
	else:
		_low_v_t = 0.0


func _draw() -> void:
	var half := size_px * 0.5
	var dark := Color("#3a2010")
	var mid := Color("#5a3a22")
	var light := Color("#8a5a36")
	var hl := Color("#c08a52")
	# outer block
	draw_rect(Rect2(-half, -half, size_px, size_px), dark)
	draw_rect(Rect2(-half + 2.0, -half + 2.0, size_px - 4.0, size_px - 4.0), mid)
	draw_rect(Rect2(-half + 4.0, -half + 4.0, size_px - 8.0, size_px - 8.0), light)
	# wood grain (4 horizontal lines)
	for i in range(1, 4):
		var y := -half + size_px * (float(i) / 4.0)
		draw_rect(Rect2(-half + 6.0, y, size_px - 12.0, 1.0), dark)
	# corner highlight
	draw_rect(Rect2(-half + 4.0, -half + 4.0, size_px - 8.0, 2.0), hl)
	draw_rect(Rect2(-half + 4.0, -half + 4.0, 2.0, size_px - 8.0), hl)
