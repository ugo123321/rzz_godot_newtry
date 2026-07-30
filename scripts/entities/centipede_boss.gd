extends Node2D
class_name CentipedeBoss

enum Phase { WARNING, ACTIVE, DEAD }

var battle
var stage_index := 0
var cfg: Dictionary = {}
var phase := Phase.WARNING
var warning_timer := 3.0
var warning_pulse := 0.0
var segments: Array = []
var bullets: Array = []
var crawl_progress := 0.0
var crawl_pause := 0.0
var crawl_speed := 240.0
var shoot_timer := 0.0
var defeated := false
var defeat_rewarded := false
var hp := 0
var max_hp := 0
var defense := 0
var segment_radius := 23.0
var death_fade_timer := 0.0
var death_fade_dur := 0.35

# v2 元素抗性/易伤(从 bosses.json 加载)
var elem_resist_fire := 0.0
var elem_resist_ice := 0.0
var elem_resist_thunder := 0.0
var elem_resist_poison := 0.0
var vuln_physical := 0.0
var vuln_fire := 0.0
var vuln_ice := 0.0
var vuln_thunder := 0.0
var vuln_poison := 0.0

var path_start := Vector2.ZERO
var path_end := Vector2.ZERO
var path_length := 1.0
var body_span := 0.85
var play_top := 88.0
var play_bottom := 580.0
var logical_w := 720.0
var logical_h := 1280.0


func is_boss_active() -> bool:
	return phase == Phase.ACTIVE


func get_hp_ratio() -> float:
	return clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)


func get_display_name() -> String:
	return str(cfg.get("name", "Boss"))


func setup(battle_node, p_stage_index: int) -> void:
	battle = battle_node
	stage_index = p_stage_index
	cfg = GameConfig.bosses.get("centipede", {})
	logical_w = float(GameConfig.get_tuning("logical_width", 720))
	logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	play_bottom = logical_h - 120.0
	segment_radius = float(cfg.get("segment_radius", 23))
	crawl_speed = float(cfg.get("crawl_speed", 240))
	warning_timer = float(cfg.get("warning_time", 1.0))
	phase = Phase.WARNING
	defeated = false
	defeat_rewarded = false
	_init_segments()
	_build_crawl_path()
	_update_segment_positions()


func _init_segments() -> void:
	for child in get_children():
		child.queue_free()
	segments.clear()
	var play_h := play_bottom - play_top
	var spacing := 28.0
	var count := maxi(12, int(floor(play_h / spacing)))
	var scale := GameConfig.stage_stat_scale(stage_index)
	var hp_each := int(round(float(cfg.get("segment_hp", 320)) * scale.hp))
	defense = maxi(1, int(round(float(cfg.get("segment_def", 3)) * scale.def)))
	# v2 元素抗性/易伤(默认 0 = 中立)
	elem_resist_fire = float(cfg.get("elem_resist_fire", 0.0))
	elem_resist_ice = float(cfg.get("elem_resist_ice", 0.0))
	elem_resist_thunder = float(cfg.get("elem_resist_thunder", 0.0))
	elem_resist_poison = float(cfg.get("elem_resist_poison", 0.0))
	vuln_physical = float(cfg.get("vuln_physical", 0.0))
	vuln_fire = float(cfg.get("vuln_fire", 0.0))
	vuln_ice = float(cfg.get("vuln_ice", 0.0))
	vuln_thunder = float(cfg.get("vuln_thunder", 0.0))
	vuln_poison = float(cfg.get("vuln_poison", 0.0))
	var hp_scale := float(cfg.get("hp_scale", 3.5))
	max_hp = int(round(count * hp_each * hp_scale))
	hp = max_hp
	for i in range(count):
		var seg := CentipedeSegment.new()
		seg.boss_ref = self
		seg.segment_index = i
		add_child(seg)
		segments.append(seg)
	body_span = (count - 1) * spacing / maxf(1.0, path_length) if count > 1 else 0.5


func _build_crawl_path() -> void:
	var safe: Vector2 = battle.player.home_position if battle and battle.player else Vector2(logical_w * 0.5, logical_h * 0.58)
	var margin := 58.0
	var px: float = safe.x
	var py: float = safe.y
	var side := randi() % 4
	var ex := 0.0
	var ey := 0.0
	match side:
		0:
			ex = MathUtils.rand_range(margin, logical_w - margin)
			ey = play_top - margin
		1:
			ex = MathUtils.rand_range(margin, logical_w - margin)
			ey = play_bottom + margin
		2:
			ex = -margin
			ey = MathUtils.rand_range(play_top + margin, play_bottom - margin)
		_:
			ex = logical_w + margin
			ey = MathUtils.rand_range(play_top + margin, play_bottom - margin)
	var ang := atan2(py - ey, px - ex)
	var back := margin + 45.0
	var forward := (play_bottom - play_top) + margin * 2.0 + 100.0
	path_start = Vector2(ex - cos(ang) * back, ey - sin(ang) * back)
	path_end = Vector2(ex + cos(ang) * forward, ey + sin(ang) * forward)
	path_length = maxf(80.0, path_start.distance_to(path_end))
	var spacing := 28.0
	var count := segments.size()
	body_span = (count - 1) * spacing / path_length if count > 1 else 0.5


func _pos_on_path(t: float) -> Vector2:
	var tt := clampf(t, 0.0, 1.0)
	return path_start.lerp(path_end, tt)


func get_segment_angle(index: int) -> float:
	var n := maxi(1, segments.size() - 1)
	var t0 := clampf(crawl_progress - (float(index) / float(n)) * body_span, 0.0, 1.0)
	var t1 := clampf(t0 + 0.02, 0.0, 1.0)
	var p0 := _pos_on_path(t0)
	var p1 := _pos_on_path(t1)
	return atan2(p1.y - p0.y, p1.x - p0.x)


func _update_segment_positions() -> void:
	var n := segments.size()
	for i in range(n):
		var offset := (float(i) / float(maxi(1, n - 1))) * body_span if n > 1 else 0.0
		var t := clampf(crawl_progress - offset, 0.0, 1.0)
		segments[i].global_position = _pos_on_path(t)


func apply_damage(raw_damage: int, hit_segment, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(DamageInfo.legacy(raw_damage), hit_segment, _from_pos)


# 新路径：接收 DamageInfo (供 v2 emitter 用)
func apply_damage_info(info: DamageInfo, hit_segment, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(info, hit_segment, _from_pos)


func _resolve_apply_damage(info: DamageInfo, hit_segment, _from_pos: Vector2) -> Dictionary:
	if defeated or phase != Phase.ACTIVE:
		return {"damage": 0, "is_crit": false}
	var target_stats := {
		"defense": defense,
		"vulnerable_mark": hit_segment.vulnerable_mark,
		"vuln_physical": vuln_physical,
		"vuln_fire": vuln_fire,
		"vuln_ice": vuln_ice,
		"vuln_thunder": vuln_thunder,
		"vuln_poison": vuln_poison,
		"elem_resist_fire": elem_resist_fire,
		"elem_resist_ice": elem_resist_ice,
		"elem_resist_thunder": elem_resist_thunder,
		"elem_resist_poison": elem_resist_poison,
		"stage_index": stage_index,
	}
	var res: Dictionary = DamageResolver.compute_damage(target_stats, info)
	if bool(res.get("vuln_consumed", false)):
		hit_segment.vulnerable_mark = false
	var actual := int(res.get("damage", 0))
	hp = maxi(0, hp - actual)
	if hp <= 0:
		_defeat()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false))}


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func get_body_draw_alpha() -> float:
	match phase:
		Phase.ACTIVE:
			return 1.0
		Phase.DEAD:
			return clampf(death_fade_timer / death_fade_dur, 0.0, 1.0)
		_:
			return 0.0


func is_segment_frozen(_seg) -> bool:
	return false


func is_defeated() -> bool:
	return defeated


func get_active_segments() -> Array:
	if phase != Phase.ACTIVE:
		return []
	var result: Array = []
	for seg in segments:
		if seg.alive:
			result.append(seg)
	return result


func activate() -> void:
	phase = Phase.ACTIVE
	crawl_progress = 0.0
	crawl_pause = 0.0
	_build_crawl_path()
	_update_segment_positions()


func update_boss(delta: float, player: BattlePlayer) -> void:
	match phase:
		Phase.WARNING:
			warning_timer -= delta
			warning_pulse += delta * 5.0
			if warning_timer <= 0.0:
				activate()
			queue_redraw()
		Phase.DEAD:
			death_fade_timer -= delta
			for seg in segments:
				seg.queue_redraw()
			queue_redraw()
		Phase.ACTIVE:
			if crawl_pause > 0.0:
				crawl_pause -= delta
			else:
				crawl_progress += (delta * crawl_speed) / path_length
				if crawl_progress >= 1.0 + body_span:
					crawl_progress = 0.0
					crawl_pause = 0.55
					_build_crawl_path()
				_update_segment_positions()
			shoot_timer -= delta
			if shoot_timer <= 0.0:
				shoot_timer = float(cfg.get("bullet_interval", 0.38))
				_shoot_bullets(player)
			_update_bullets(delta, player)
			for seg in segments:
				seg.queue_redraw()


func _shoot_bullets(player: BattlePlayer) -> void:
	var live := get_active_segments()
	if live.is_empty() or player == null:
		return
	var spd := float(cfg.get("bullet_speed", 130))
	var count := int(cfg.get("bullets_per_shot", 20))
	var dmg := int(cfg.get("bullet_damage", 24))
	for _n in range(count):
		var seg = live[randi() % live.size()]
		var dir: Vector2 = (player.global_position - seg.global_position).normalized()
		bullets.append({
			"pos": seg.global_position,
			"vel": dir * spd,
			"radius": 5.0,
			"damage": dmg,
			"life": 4.0,
		})


func _update_bullets(delta: float, player: BattlePlayer) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		b.pos += b.vel * delta
		b.life -= delta
		if b.life <= 0.0 or not battle.is_in_bounds(b.pos):
			bullets.remove_at(i)
			continue
		if player == null or player.hp <= 0:
			continue
		if b.pos.distance_to(player.global_position) <= float(b.radius) + player.get_effective_radius() * 0.55:
			player.take_damage(int(b.get("damage", 0)))
			bullets.remove_at(i)


func _defeat() -> void:
	if defeated:
		return
	hp = 0
	defeated = true
	phase = Phase.DEAD
	death_fade_timer = death_fade_dur
	bullets.clear()
	var live := get_active_segments()
	if not live.is_empty() and battle and battle.blood_stains:
		var center := Vector2.ZERO
		for seg in live:
			center += seg.global_position
		center /= float(live.size())
		var hit_angle := 0.0
		if battle.player:
			hit_angle = (center - battle.player.global_position).angle()
		battle.blood_stains.spawn(center.x, center.y, 1.5, hit_angle)
		if battle.particles:
			battle.particles.death_effect(center, Color("#3d5a48"))
	if not defeat_rewarded and battle and battle.experience:
		defeat_rewarded = true
		var bonus := int(cfg.get("defeat_exp", 140))
		battle.experience.add_exp(bonus)
		if battle.hud:
			battle.hud.show_message("%s 击破!" % str(cfg.get("name", "千足虫")), 2.0)


func get_warning_text() -> String:
	return str(maxi(1, int(ceil(warning_timer))))


func _draw_warning_overlay() -> void:
	var pulse := 0.45 + sin(warning_pulse) * 0.35
	var border_w := maxf(6.0, 10.0 + pulse * 8.0)
	var alpha := 0.5 + pulse * 0.45
	var col := Color(1.0, 0.16, 0.16, alpha)
	var inset := border_w * 0.5
	draw_rect(
		Rect2(inset, inset, logical_w - border_w, logical_h - border_w),
		col,
		false,
		border_w
	)


func _draw_warning_countdown() -> void:
	var sec := maxi(1, int(ceil(warning_timer)))
	var pulse := 0.88 + sin(warning_pulse * 2.2) * 0.12
	var center := Vector2(logical_w * 0.5, logical_h * 0.46)
	var font := PixelUiHelper.get_ui_font()
	var font_size := 52
	var text := str(sec)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		center - Vector2(text_size.x * 0.5, text_size.y * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(1.0, 0.19, 0.19, pulse)
	)


func _draw() -> void:
	for b in bullets:
		draw_circle(b.pos - global_position, float(b.radius), Color(0.95, 0.35, 0.25, 0.9))
