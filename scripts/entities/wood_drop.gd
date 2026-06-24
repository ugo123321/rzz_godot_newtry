extends Node2D
class_name WoodDrop

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const PICKUP_RADIUS := 42.0
const ATTRACT_RADIUS := 120.0
const ATTRACT_SPEED := 360.0

var amount := 5
var lifetime := 30.0
var _spawn_t := 0.0
var _picked := false
var _drift_dir := Vector2.ZERO
var _drift_speed := 70.0


func setup(pos: Vector2, p_amount: int) -> void:
	global_position = pos
	amount = maxi(1, p_amount)
	z_index = 2
	scale = Vector2.ONE * 1.8
	var ang := randf() * TAU
	_drift_dir = Vector2(cos(ang), sin(ang))
	_drift_speed = randf_range(40.0, 80.0)


func _process(delta: float) -> void:
	if _picked:
		return
	_spawn_t += delta
	if _spawn_t < 0.45:
		global_position += _drift_dir * _drift_speed * delta
		_drift_speed = maxf(0.0, _drift_speed - 220.0 * delta)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.player == null:
		queue_redraw()
		return
	var player_pos: Vector2 = battle.player.global_position
	var dist := global_position.distance_to(player_pos)
	if dist <= PICKUP_RADIUS:
		_picked = true
		LobbyState.add_wood(amount)
		if battle.has_method("spawn_wood_popup"):
			battle.spawn_wood_popup(global_position, amount)
		queue_free()
		return
	if dist <= ATTRACT_RADIUS:
		var to := (player_pos - global_position).normalized()
		var t := 1.0 - clampf(dist / ATTRACT_RADIUS, 0.0, 1.0)
		global_position += to * ATTRACT_SPEED * t * delta
	queue_redraw()


func _draw() -> void:
	var bob := sin(Time.get_ticks_msec() / 200.0) * 1.5
	# crossed sticks
	_draw_stick(Vector2(-7.0, bob), Vector2(7.0, bob - 1.0), 4.0)
	_draw_stick(Vector2(-6.0, bob + 4.0), Vector2(7.0, bob + 2.0), 4.0)


func _draw_stick(p1: Vector2, p2: Vector2, thickness: float) -> void:
	var dark := Color("#3a2010")
	var mid := Color("#5a3a22")
	var light := Color("#a06a3a")
	var hl := Color("#c08a52")
	var dir := (p2 - p1).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var len := p1.distance_to(p2)
	var steps := maxi(2, int(len))
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var center := p1.lerp(p2, t)
		for o in range(int(thickness)):
			var off := o - thickness * 0.5
			var col := dark
			if int(o) == 0 or int(o) == int(thickness) - 1:
				col = mid
			elif int(o) == int(thickness) - 2:
				col = light
			elif int(o) == 1:
				col = hl
			draw_rect(Rect2(center + nrm * off, Vector2.ONE), col)
