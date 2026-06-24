extends Node2D
class_name LotteryPortal

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const TRIGGER_RADIUS := 36.0
const VISUAL_RADIUS := 28.0

var lifetime := 5.0
var _t := 0.0
var _consumed := false


func setup(pos: Vector2, life: float) -> void:
	global_position = pos
	lifetime = life
	z_index = 4
	queue_redraw()


func _process(delta: float) -> void:
	if _consumed:
		return
	lifetime -= delta
	_t += delta
	if lifetime <= 0.0:
		queue_free()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.player and battle.state == GameState.PLAYING and not battle.get("_portal_active_pause"):
		if global_position.distance_to(battle.player.global_position) <= TRIGGER_RADIUS:
			_consumed = true
			if battle.has_method("on_portal_entered"):
				battle.on_portal_entered(self)
			return
	queue_redraw()


func _draw() -> void:
	var flicker := (int(Time.get_ticks_msec() / 80) % 2) == 0
	# outer glow halo
	var halo_pulse := 0.35 + 0.25 * sin(_t * 6.0)
	draw_circle(Vector2.ZERO, VISUAL_RADIUS + 10.0, Color(0.55, 0.36, 1.0, halo_pulse * 0.45))
	draw_circle(Vector2.ZERO, VISUAL_RADIUS + 4.0, Color(0.65, 0.46, 1.0, 0.55))
	# pixel ring (dark→bright)
	var c_dark := Color("#2a1a55")
	var c_mid := Color("#5536a8")
	var c_high := Color("#8a5cff")
	var c_top := Color("#c8a8ff")
	_draw_ring(VISUAL_RADIUS, c_dark, 3.0)
	_draw_ring(VISUAL_RADIUS - 4.0, c_mid, 3.0)
	_draw_ring(VISUAL_RADIUS - 8.0, c_high, 2.0)
	# spinning core (8 pixel sparkles)
	var rot := _t * 2.5
	for i in range(6):
		var ang := rot + float(i) / 6.0 * TAU
		var r := VISUAL_RADIUS * 0.55 + (1.0 if flicker else 0.0)
		var p := Vector2(cos(ang), sin(ang)) * r
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), c_top)
	# center dot
	if flicker:
		draw_rect(Rect2(-3.0, -3.0, 6.0, 6.0), Color.WHITE)
	# countdown above portal
	var sec_left := int(ceil(lifetime))
	PixelUi.draw_pixel_text(
		self,
		"%ds" % sec_left,
		Vector2(0.0, -VISUAL_RADIUS - 18.0),
		12,
		Color("#ffe090") if sec_left > 2 else Color("#ff8080"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)


func _draw_ring(radius: float, color: Color, thickness: float) -> void:
	var r := radius
	for ang_i in range(36):
		var ang := float(ang_i) / 36.0 * TAU
		var p := Vector2(cos(ang), sin(ang)) * r
		draw_rect(Rect2(p - Vector2(thickness * 0.5, thickness * 0.5), Vector2(thickness, thickness)), color)
