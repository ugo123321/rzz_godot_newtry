extends Node2D
class_name BuffOrbManager

var battle
var orbs: Array = []
var draw_session_eaten: Array = []
var pickup_flashes: Array = []
var notice := ""
var notice_timer := 0.0
var _spawn_queue: Array = []
var _spawn_timer := 0.0


func setup(battle_node) -> void:
	battle = battle_node


func reset() -> void:
	orbs.clear()
	_spawn_queue.clear()
	_spawn_timer = 0.0
	draw_session_eaten.clear()
	pickup_flashes.clear()
	notice = ""
	notice_timer = 0.0
	queue_redraw()


func spawn_for_stage(_stage_index: int, safe_zone: Vector2) -> void:
	reset()
	var cfg := GameConfig.buff_orbs
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var play_bottom := h - 120.0
	var base_types: Array = cfg.get("base_types", ["attack", "ki", "combo"])
	var max_per_type := int(cfg.get("max_per_type", 4))
	var extra_chance := float(cfg.get("extra_spawn_chance", 0.48))
	var spawn_chance: Dictionary = cfg.get("spawn_chance", {})
	var radius := float(cfg.get("radius", 13))

	var planned: Array = []
	for type_name in base_types:
		for i in range(max_per_type):
			var chance := float(spawn_chance.get(type_name, 0.0)) if i == 0 else extra_chance
			if randf() > chance:
				break
			var pos := _pick_spawn_pos(w, h, play_bottom, safe_zone, planned)
			_spawn_queue.append({"type": str(type_name), "pos": pos, "radius": radius})
			planned.append(pos)

	var min_ki := int(cfg.get("min_ki_per_stage", 2))
	var ki_count := 0
	for entry in _spawn_queue:
		if str(entry.type) == "ki":
			ki_count += 1
	while ki_count < min_ki:
		var pos := _pick_spawn_pos(w, h, play_bottom, safe_zone, planned)
		_spawn_queue.append({"type": "ki", "pos": pos, "radius": radius})
		planned.append(pos)
		ki_count += 1
	_spawn_queue.shuffle()
	_spawn_timer = _spawn_wave_delay()


func begin_draw_session(player: BattlePlayer) -> void:
	cancel_draw_session()
	if player == null:
		return
	player.draw_session_snapshot = {
		"ki": player.ki,
		"attack_mult": player.turn_buff_attack_mult,
		"combo_mult": player.turn_buff_combo_mult,
		"ice_ready": player.ice_ready,
	}
	player.collected_orb_buffs.clear()
	player.ki_at_draw_start = player.ki


func cancel_draw_session() -> void:
	var player: BattlePlayer = battle.player if battle else null
	if player and player.draw_session_snapshot:
		player.ki = float(player.draw_session_snapshot.ki)
		player.turn_buff_attack_mult = float(player.draw_session_snapshot.attack_mult)
		player.turn_buff_combo_mult = float(player.draw_session_snapshot.combo_mult)
		player.ice_ready = bool(player.draw_session_snapshot.ice_ready)
		player.draw_session_snapshot = null
	if player:
		player.collected_orb_buffs.clear()
	_restore_draw_session_orbs()
	pickup_flashes.clear()


func commit_draw_session() -> void:
	var player: BattlePlayer = battle.player if battle else null
	if player:
		player.draw_session_snapshot = null
	draw_session_eaten.clear()


func check_path_segment(from: Vector2, to: Vector2) -> void:
	var seg_len := from.distance_to(to)
	var steps := maxi(1, int(ceil(seg_len / 5.0)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var px := from.lerp(to, t)
		for o in orbs:
			if not bool(o.alive) or _is_orb_spawn_locked(o):
				continue
			if px.distance_to(o.pos) <= float(o.radius) + 10.0:
				_collect_orb(o)


func update(delta: float, player: BattlePlayer) -> void:
	_update_spawns(delta)
	if player == null:
		return
	for o in orbs:
		if not bool(o.alive):
			continue
		if _is_orb_spawn_locked(o):
			o.spawn_timer = maxf(0.0, float(o.spawn_timer) - delta)
			continue
		o.pulse = float(o.pulse) + delta * 4.2
		if player.state == BattlePlayer.State.ATTACKING:
			if player.global_position.distance_to(o.pos) <= player.get_effective_radius() + float(o.radius):
				_collect_orb(o)
	orbs = orbs.filter(func(o): return bool(o.alive))
	for i in range(pickup_flashes.size() - 1, -1, -1):
		pickup_flashes[i].timer -= delta
		if pickup_flashes[i].timer <= 0.0:
			pickup_flashes.remove_at(i)
	if notice_timer > 0.0:
		notice_timer -= delta
	queue_redraw()


func _spawn_orb(type_name: String, pos: Vector2, radius: float, animate: bool = true) -> void:
	var spawn_dur := 0.0
	if animate:
		spawn_dur = float(GameConfig.get_tuning("monster_spawn_anim", 0.6))
	orbs.append({
		"type": type_name,
		"pos": pos,
		"radius": radius,
		"pulse": randf() * TAU,
		"spawn_timer": spawn_dur,
		"spawn_dur": spawn_dur,
		"alive": true,
	})


func _update_spawns(delta: float) -> void:
	if _spawn_timer > 0.0:
		_spawn_timer = maxf(0.0, _spawn_timer - delta)
	if _spawn_queue.is_empty() or _spawn_timer > 0.0:
		return
	var entry: Dictionary = _spawn_queue.pop_front()
	_spawn_orb(str(entry.type), entry.pos, float(entry.radius))
	if not _spawn_queue.is_empty():
		_spawn_timer = _spawn_interval()


func _spawn_interval() -> float:
	return float(GameConfig.get_tuning("monster_spawn_interval", 0.05))


func _spawn_wave_delay() -> float:
	return float(GameConfig.get_tuning("monster_spawn_wave_delay", 0.55))


func _is_orb_spawn_locked(o: Dictionary) -> bool:
	return float(o.get("spawn_timer", 0.0)) > 0.0


func _orb_spawn_progress(o: Dictionary) -> float:
	var dur := maxf(0.001, float(o.get("spawn_dur", 0.0)))
	return clampf(1.0 - float(o.spawn_timer) / dur, 0.0, 1.0)


func _orb_spawn_alpha(o: Dictionary) -> float:
	if not _is_orb_spawn_locked(o):
		return 1.0
	return _orb_spawn_progress(o)


func _orb_spawn_scale(o: Dictionary) -> float:
	if not _is_orb_spawn_locked(o):
		return 1.0
	return lerpf(0.35, 1.0, _back_out_ease(_orb_spawn_progress(o)))


func _back_out_ease(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var u := t - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


func _pick_pos(w: float, h: float, play_bottom: float, safe_zone: Vector2) -> Vector2:
	var pad := 28.0
	var top := 92.0
	var bottom := maxf(top + 80.0, play_bottom - 30.0)
	for _i in range(80):
		var x := MathUtils.rand_range(pad, w - pad)
		var y := MathUtils.rand_range(top, bottom)
		if safe_zone == Vector2.ZERO or Vector2(x, y).distance_to(safe_zone) > 60.0:
			return Vector2(x, y)
	return Vector2(w * 0.5, (top + bottom) * 0.5)


func _pos_clear(pos: Vector2, min_dist: float, extra_positions: Array = []) -> bool:
	for o in orbs:
		if pos.distance_to(o.pos) < min_dist:
			return false
	for p in extra_positions:
		if pos.distance_to(p) < min_dist:
			return false
	return true


func _pick_spawn_pos(w: float, h: float, play_bottom: float, safe_zone: Vector2, extra_positions: Array = []) -> Vector2:
	for _i in range(50):
		var pos := _pick_pos(w, h, play_bottom, safe_zone)
		if _pos_clear(pos, 34.0, extra_positions):
			return pos
	return _pick_pos(w, h, play_bottom, safe_zone)


func _collect_orb(o: Dictionary) -> void:
	if not bool(o.alive) or _is_orb_spawn_locked(o):
		return
	var player: BattlePlayer = battle.player if battle else null
	if player and player.state == BattlePlayer.State.BULLET_TIME:
		draw_session_eaten.append(o.duplicate(true))
	o.alive = false
	_apply_orb(str(o.type))
	_emit_pickup_flash(o)


func _apply_orb(type_name: String) -> void:
	var player: BattlePlayer = battle.player if battle else null
	if player == null:
		return
	player.collected_orb_buffs.append(type_name)
	match type_name:
		"attack":
			player.turn_buff_attack_mult *= 1.3
			notice = "攻击+30%"
		"ki":
			var bonus: float = round(player.ki_max * 0.30)
			player.ki = minf(player.ki_max, player.ki + bonus)
			notice = "气力+30%"
		"combo":
			player.turn_buff_combo_mult *= 2.0
			notice = "连击×2"
		"ice":
			player.ice_ready = true
			notice = "冰冻球"
		_:
			return
	if battle:
		battle.shake_camera(4.0, 0.1)
		AudioManager.play_orb_pickup()
	notice_timer = 1.6


func _emit_pickup_flash(o: Dictionary) -> void:
	pickup_flashes.append({
		"pos": o.pos,
		"type": o.type,
		"timer": 0.5,
		"max_timer": 0.5,
	})


func _restore_draw_session_orbs() -> void:
	for snap in draw_session_eaten:
		_spawn_orb(str(snap.type), snap.pos, float(snap.radius), false)
		orbs.back()["pulse"] = snap.pulse
	draw_session_eaten.clear()


func _orb_palette(type_name: String) -> Dictionary:
	match type_name:
		"attack":
			return {"core": Color("#ff9a58"), "hi": Color("#ffd8a8"), "edge": Color("#7a2c10")}
		"ki":
			return {"core": Color("#58d0ff"), "hi": Color("#b8f0ff"), "edge": Color("#1e4e70")}
		"combo":
			return {"core": Color("#ffa0f8"), "hi": Color("#ffd8ff"), "edge": Color("#5a2a6a")}
		"ice":
			return {"core": Color("#80d8ff"), "hi": Color("#d8f6ff"), "edge": Color("#245a7a")}
	return {"core": Color("#f0d880"), "hi": Color("#ffe8a8"), "edge": Color("#6a4a18")}


func _draw() -> void:
	for o in orbs:
		if not bool(o.alive):
			continue
		var spawn_scale := _orb_spawn_scale(o)
		var spawn_alpha := _orb_spawn_alpha(o)
		var pulse := 0.86 + sin(float(o.pulse)) * 0.14
		var r := maxf(5.0, float(o.radius) * pulse * spawn_scale)
		var pal := _orb_palette(str(o.type))
		draw_circle(o.pos - global_position, r + 3.0, Color(pal.hi, 0.2 * spawn_alpha))
		draw_circle(o.pos - global_position, r, Color(pal.core, spawn_alpha))
		draw_arc(o.pos - global_position, r, 0.0, TAU, 32, Color(pal.edge, spawn_alpha), 2.0)
	for f in pickup_flashes:
		var t := 1.0 - float(f.timer) / float(f.max_timer)
		var pal := _orb_palette(str(f.type))
		var ring_r := 14.0 + t * 42.0
		var alpha := 1.0 - t
		draw_arc(f.pos - global_position, ring_r, 0.0, TAU, 32, Color(pal.hi, alpha * 0.85), 3.0)
