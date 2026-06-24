extends Node2D
class_name BuildHouseDirector

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const WoodBlockScript = preload("res://scripts/entities/wood_block.gd")

enum Phase { IDLE, PLAYING, FINISHING, DONE }

var phase: int = Phase.IDLE
var blocks_left := 0
var blocks_dropped: Array = []
var target_height_m := 200.0  # chapter target
var max_height_m := 0.0
var ground_y := 0.0
var px_per_meter := 36.0
var block_size_px := 72.0
var swing_speed := 1.8
var swing_amplitude := 180.0
var swing_center_x := 360.0
var swing_t := 0.0
var rope_y := 80.0
var ground_static: StaticBody2D
var _ground_collision: CollisionShape2D
var _battle: Node = null
var _camera_target_y := 0.0
var _camera_y_max := 0.0
var _logical_w := 720.0
var _logical_h := 1280.0
var _phase_timer := 0.0
var _hud_visible := true
var _left_wall: StaticBody2D
var _right_wall: StaticBody2D
var _wood_per_block := 5
# Result reported back to battle after phase ends
var _final_height_m := 0.0


func reset() -> void:
	phase = Phase.IDLE
	blocks_left = 0
	for b in blocks_dropped:
		if is_instance_valid(b):
			b.queue_free()
	blocks_dropped.clear()
	max_height_m = 0.0
	_phase_timer = 0.0
	_camera_target_y = 0.0
	_camera_y_max = 0.0
	if is_instance_valid(ground_static):
		ground_static.queue_free()
	ground_static = null
	if is_instance_valid(_left_wall):
		_left_wall.queue_free()
	_left_wall = null
	if is_instance_valid(_right_wall):
		_right_wall.queue_free()
	_right_wall = null


func begin(battle: Node, chapter_target_m: float, restored_height_m: float, restored_blocks: Array) -> void:
	reset()
	_battle = battle
	target_height_m = maxf(1.0, chapter_target_m)
	px_per_meter = float(GameConfig.get_tuning("house_px_per_meter", 36))
	block_size_px = float(GameConfig.get_tuning("house_block_size_m", 2.0)) * px_per_meter
	swing_speed = float(GameConfig.get_tuning("house_swing_speed", 1.8))
	swing_amplitude = float(GameConfig.get_tuning("house_swing_amplitude_px", 180))
	_logical_w = float(GameConfig.get_tuning("logical_width", 720))
	_logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	swing_center_x = _logical_w * 0.5
	ground_y = _logical_h - 80.0
	max_height_m = restored_height_m
	_recompute_rope_y_initial()
	_setup_static_geometry()
	_spawn_restored_blocks(restored_blocks)
	var wood_per_block := int(GameConfig.get_tuning("wood_per_block", 20))
	_wood_per_block = maxi(1, wood_per_block)
	blocks_left = LobbyState.wood / _wood_per_block
	phase = Phase.PLAYING
	_phase_timer = 0.0
	swing_t = 0.0
	visible = true
	EventBus.tower_height_changed.emit(max_height_m, target_height_m)
	queue_redraw()


func _recompute_rope_y_initial() -> void:
	# Rope tip world y aligned to where _draw_swing_rope renders.
	# Initial camera will be set by _update_camera once tower top is known.
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	rope_y = cam_y - _logical_h * 0.42 + 220.0


func _recompute_rope_y() -> void:
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	rope_y = cam_y - _logical_h * 0.42 + 220.0


func _spawn_restored_blocks(blocks: Array) -> void:
	for entry in blocks:
		var pos: Vector2 = entry.get("pos", Vector2.ZERO)
		var ang: float = float(entry.get("angle", 0.0))
		var block = WoodBlockScript.new()
		add_child(block)
		block.setup(block_size_px)
		block.global_position = pos
		block.rotation = ang
		block.linear_velocity = Vector2.ZERO
		block.angular_velocity = 0.0
		block.is_settled = true
		blocks_dropped.append(block)


func _setup_static_geometry() -> void:
	ground_static = StaticBody2D.new()
	ground_static.name = "BuildGround"
	add_child(ground_static)
	var g_shape := RectangleShape2D.new()
	g_shape.size = Vector2(_logical_w * 1.5, 60.0)
	var g_coll := CollisionShape2D.new()
	g_coll.shape = g_shape
	ground_static.global_position = Vector2(_logical_w * 0.5, ground_y + 30.0)
	ground_static.add_child(g_coll)
	# Side walls so blocks don't fly off-screen on bounce
	_left_wall = _make_wall(Vector2(-30.0, ground_y - 4000.0 * 0.5), Vector2(60.0, 8000.0))
	_right_wall = _make_wall(Vector2(_logical_w + 30.0, ground_y - 4000.0 * 0.5), Vector2(60.0, 8000.0))


func _make_wall(pos: Vector2, sz: Vector2) -> StaticBody2D:
	var w := StaticBody2D.new()
	add_child(w)
	w.global_position = pos
	var shape := RectangleShape2D.new()
	shape.size = sz
	var coll := CollisionShape2D.new()
	coll.shape = shape
	w.add_child(coll)
	return w


func update(delta: float) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE:
		return
	swing_t += delta
	_compute_max_height()
	EventBus.tower_height_changed.emit(max_height_m, target_height_m)
	if phase == Phase.PLAYING:
		# End condition: 本次发的木块全部放完且已稳定 → 进入收尾
		if blocks_left <= 0 and _all_blocks_settled():
			phase = Phase.FINISHING
			_phase_timer = 0.0
		queue_redraw()
		_update_camera()
		_recompute_rope_y()
	elif phase == Phase.FINISHING:
		# 给物理多 0.5s 沉降，然后回报结果给 battle
		_phase_timer += delta
		queue_redraw()
		_update_camera()
		if _phase_timer >= 0.5:
			phase = Phase.DONE
			_final_height_m = max_height_m
			if _battle and _battle.has_method("on_build_house_phase_done"):
				_battle.on_build_house_phase_done(_final_height_m, serialize_blocks())


func serialize_blocks() -> Array:
	var result: Array = []
	for b in blocks_dropped:
		if not is_instance_valid(b):
			continue
		result.append({
			"pos": b.global_position,
			"angle": b.rotation,
		})
	return result


func handle_drop_click() -> void:
	if phase != Phase.PLAYING:
		return
	if blocks_left <= 0:
		return
	blocks_left -= 1
	LobbyState.spend_wood(_wood_per_block)
	var hang_x := _rope_tip_x()
	var hang_y := rope_y + 40.0
	var block = WoodBlockScript.new()
	add_child(block)
	block.setup(block_size_px)
	block.global_position = Vector2(hang_x, hang_y)
	block.linear_velocity = Vector2(0.0, 0.0)
	blocks_dropped.append(block)
	# subtle drop shake feel for next swing
	swing_t += 0.05
	queue_redraw()


func _rope_tip_x() -> float:
	return swing_center_x + sin(swing_t * swing_speed) * swing_amplitude


func _compute_max_height() -> void:
	var max_top_y := ground_y
	for b in blocks_dropped:
		if not is_instance_valid(b):
			continue
		if not b.is_settled:
			continue
		var top_y: float = b.global_position.y - block_size_px * 0.5
		if top_y < max_top_y:
			max_top_y = top_y
	var height_px := maxf(0.0, ground_y - max_top_y)
	# 实时反映堆叠当前高度（木块倒了高度会下降）
	max_height_m = height_px / px_per_meter


func _all_blocks_settled() -> bool:
	for b in blocks_dropped:
		if not is_instance_valid(b):
			continue
		if b.linear_velocity.length() > 8.0:
			return false
	return true


func _update_camera() -> void:
	if _battle == null or _battle.camera == null:
		return
	# Scroll up as tower grows: keep tower top roughly mid-screen
	var top_world_y := ground_y - max_height_m * px_per_meter
	var view_h := _logical_h
	var desired_cam_y := top_world_y + view_h * 0.35
	desired_cam_y = minf(desired_cam_y, _logical_h * 0.5)
	_camera_target_y = desired_cam_y
	_battle.camera.global_position.y = lerpf(_battle.camera.global_position.y, _camera_target_y, 0.04)


func _draw() -> void:
	if phase == Phase.IDLE:
		return
	# Sky background
	draw_rect(Rect2(-_logical_w, ground_y - 4000.0, _logical_w * 3.0, 4500.0), Color("#88c4e8"))
	# Ground grass
	_draw_ground()
	# Swinging rope + hanging block preview
	_draw_swing_rope()
	# HUD: current height / target
	_draw_height_hud()


func _draw_ground() -> void:
	draw_rect(Rect2(-_logical_w, ground_y, _logical_w * 3.0, 200.0), Color("#2f5a23"))
	draw_rect(Rect2(-_logical_w, ground_y, _logical_w * 3.0, 6.0), Color("#4d8a36"))
	# tufts of pixel grass
	for x in range(-int(_logical_w), int(_logical_w * 2), 16):
		var h := 3 + (x * 13) % 5
		draw_rect(Rect2(float(x), ground_y - float(h), 2.0, float(h)), Color("#7bbf52"))


func _draw_swing_rope() -> void:
	# Anchor at top center (relative to camera, but since we scroll camera, anchor moves with it)
	var cam_y: float = _battle.camera.global_position.y if (_battle and _battle.camera) else _logical_h * 0.5
	# Compute the rope tip in WORLD space directly relative to camera Y:
	var rope_anchor := Vector2(swing_center_x, cam_y - _logical_h * 0.42)
	var tip_x: float = _rope_tip_x()
	var rope_tip := Vector2(tip_x, rope_anchor.y + 220.0)
	# Draw rope as series of small pixel segments (dark→mid)
	var dark := Color("#2a1a10")
	var mid := Color("#5a3a22")
	var steps := 12
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := rope_anchor.lerp(rope_tip, t)
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), dark)
		if i % 2 == 0:
			draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), mid)
	# Draw hanging block preview (mini wood block)
	if blocks_left > 0 and phase == Phase.PLAYING:
		_draw_preview_block(rope_tip + Vector2(0.0, block_size_px * 0.5))


func _draw_preview_block(center: Vector2) -> void:
	var half := block_size_px * 0.5
	var dark := Color("#3a2010")
	var mid := Color("#5a3a22")
	var light := Color("#8a5a36")
	var hl := Color("#c08a52")
	draw_rect(Rect2(center.x - half, center.y - half, block_size_px, block_size_px), dark)
	draw_rect(Rect2(center.x - half + 2.0, center.y - half + 2.0, block_size_px - 4.0, block_size_px - 4.0), mid)
	draw_rect(Rect2(center.x - half + 4.0, center.y - half + 4.0, block_size_px - 8.0, block_size_px - 8.0), light)
	for i in range(1, 4):
		var y := center.y - half + block_size_px * (float(i) / 4.0)
		draw_rect(Rect2(center.x - half + 6.0, y, block_size_px - 12.0, 1.0), dark)
	draw_rect(Rect2(center.x - half + 4.0, center.y - half + 4.0, block_size_px - 8.0, 2.0), hl)


func _draw_height_hud() -> void:
	# Drawn in world-space; we want it screen-locked. Position relative to camera.
	if _battle == null or _battle.camera == null:
		return
	var cam_pos: Vector2 = _battle.camera.global_position
	var hud_x := cam_pos.x + _logical_w * 0.5 - 260.0
	var hud_y := cam_pos.y - _logical_h * 0.5 + 38.0
	PixelUi.draw_pixel_text(
		self,
		"高度 %.1f / %dm" % [max_height_m, int(target_height_m)],
		Vector2(hud_x, hud_y),
		28,
		Color("#ffe090"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)
	PixelUi.draw_pixel_text(
		self,
		"剩余木块 %d" % blocks_left,
		Vector2(hud_x, hud_y + 34.0),
		18,
		Color("#c08a52"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)


func _draw_dim_overlay() -> void:
	if _battle == null or _battle.camera == null:
		return
	var cam: Vector2 = _battle.camera.global_position
	draw_rect(
		Rect2(cam.x - _logical_w, cam.y - _logical_h, _logical_w * 2.0, _logical_h * 2.0),
		Color(0.0, 0.0, 0.0, 0.55)
	)
