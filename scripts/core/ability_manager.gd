extends Node
class_name AbilityManager

const EffectHelperScript = preload("res://scripts/utils/effect_helper.gd")
const FX_SCALE := 1.75
const PROJ_DRAW_SCALE := 0.72
const AUTO_BULLET_DRAW_SCALE := 0.95
const AUTO_BULLET_SPAWN_OFFSET := 8.0
const AUTO_BULLET_FAN_SPREAD := 0.16
const AUTO_HIT_VISUAL_PAD := 10.0
const AUTO_HIT_FX_SCALE := 1.3
const HIT_FX_DRAW_SCALE := 0.78
const ABYSS_EXPLOSION_DAMAGE_FRAME := 5
const SHURIKEN_PIXEL := 4
const SHURIKEN_PIXELS: Array = [
	[null, "#7a8aa8", null, "#7a8aa8", null],
	["#7a8aa8", "#e8f4ff", "#b8cce8", "#e8f4ff", "#7a8aa8"],
	[null, "#b8cce8", "#586878", "#b8cce8", null],
	["#7a8aa8", "#e8f4ff", "#b8cce8", "#e8f4ff", "#7a8aa8"],
	[null, "#7a8aa8", null, "#7a8aa8", null],
]

const FIREBALL_PIXEL := 4
const FIREBALL_RADIUS_BLOCKS := 8

var battle
var _auto_bullet_frames: SpriteFrames
var _spirit_frames: SpriteFrames
var _fireball_frames: SpriteFrames
var _tornado_frames: SpriteFrames
var _black_hole_frames: SpriteFrames
var _whirl_frames: SpriteFrames
var _explosion_frames: SpriteFrames
var _smoke_hit_frames: SpriteFrames
var shurikens: Array = []
var lasers: Array = []
var abyss_explosions: Array = []
var hit_fx: Array = []
var water_tornados: Array = []
var black_holes: Array = []
var whirls: Array = []
var auto_bullet_cooldown := 0.0
var black_hole_spawned_this_resolve := false
var combo_fireball_milestone := 0
var _auto_bullet_release_connected := false


func setup(battle_node) -> void:
	battle = battle_node
	_load_projectile_frames()
	_connect_auto_bullet_release()


func _connect_auto_bullet_release() -> void:
	if battle == null or battle.player == null or _auto_bullet_release_connected:
		return
	if not battle.player.auto_bullet_released.is_connected(_on_auto_bullet_released):
		battle.player.auto_bullet_released.connect(_on_auto_bullet_released)
	_auto_bullet_release_connected = true


func _load_projectile_frames() -> void:
	_auto_bullet_frames = EffectHelperScript.build_projectile_frames("auto_bullet")
	_spirit_frames = EffectHelperScript.build_projectile_frames("spirit_bomb")
	_fireball_frames = EffectHelperScript.build_projectile_frames("fireball")
	_tornado_frames = EffectHelperScript.build_projectile_frames("tornado")
	_black_hole_frames = EffectHelperScript.build_projectile_frames("black_hole")
	_whirl_frames = EffectHelperScript.build_effect_frames("slash_e")
	_explosion_frames = EffectHelperScript.build_effect_frames("explosion_c")
	_smoke_hit_frames = EffectHelperScript.build_effect_frames("smoke_hit")


func _with_upgrade_fx_layer(data: Dictionary, upgrade_id: String) -> Dictionary:
	data["upgrade_id"] = upgrade_id
	data["below_monsters"] = GameConfig.upgrade_fx_below_monsters(upgrade_id)
	return data


func _fx_on_layer(item: Dictionary, below_monsters: bool) -> bool:
	return bool(item.get("below_monsters", false)) == below_monsters


func _skill_burst(pos: Vector2, shake_mag: float, shake_dur: float, color: Color, count: int = 14) -> void:
	if battle == null:
		return
	battle.shake_camera(shake_mag * FX_SCALE * GameConfig.get_world_scale(), shake_dur)
	if battle.particles == null:
		return
	for i in range(count):
		var a := randf() * TAU
		var speed := randf_range(90.0, 240.0) * FX_SCALE * GameConfig.get_world_scale()
		battle.particles.emit_particle(
			pos.x, pos.y,
			cos(a) * speed, sin(a) * speed,
			randf_range(0.18, 0.42), randf_range(5.0, 11.0) * FX_SCALE * GameConfig.get_world_scale(),
			color, randf_range(60.0, 120.0), true, true
		)


func _draw_water_tornado(canvas: Node2D, t: Dictionary, life_t: float) -> void:
	if _tornado_frames == null or _tornado_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	var tex := EffectHelperScript.animation_frame_texture(_tornado_frames, float(t.get("anim_t", 0.0)))
	if tex == null:
		return
	var alpha := 0.55 + life_t * 0.45
	var size := tex.get_size()
	var draw_r := 60.0 * FX_SCALE * GameConfig.get_world_scale()
	var draw_scale := (draw_r * 2.2) / maxf(size.x, size.y)
	var draw_size := size * draw_scale
	var local_pos: Vector2 = Vector2(t.pos) - canvas.global_position
	SpriteHelper.draw_effect_texture_rect(
		canvas,
		tex,
		Rect2(local_pos - draw_size * 0.5, draw_size),
		Color(1.0, 1.0, 1.0, alpha)
	)


func _draw_black_hole(canvas: Node2D, bh: Dictionary, life_t: float) -> void:
	if _black_hole_frames == null or _black_hole_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	var tex := EffectHelperScript.animation_frame_texture(_black_hole_frames, float(bh.get("anim_t", 0.0)))
	if tex == null:
		return
	var br := float(bh.radius)
	var size := tex.get_size()
	var draw_scale := (br * 2.0) / maxf(size.x, size.y)
	var draw_size := size * draw_scale
	var local_pos: Vector2 = Vector2(bh.pos) - canvas.global_position
	SpriteHelper.draw_effect_texture_rect(
		canvas,
		tex,
		Rect2(local_pos - draw_size * 0.5, draw_size),
		Color(1.0, 1.0, 1.0, 0.85 * life_t)
	)


func _draw_sprite_fx(
	canvas: Node2D,
	world_pos: Vector2,
	rot: float,
	spin: float,
	frames: SpriteFrames,
	scale_mul: float,
	alpha: float = 1.0
) -> void:
	if frames == null or frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	var tex := EffectHelperScript.projectile_frame_texture(frames, spin)
	if tex == null:
		return
	var draw_scale := PROJ_DRAW_SCALE * scale_mul * FX_SCALE * GameConfig.get_world_scale()
	var local_pos: Vector2 = world_pos - canvas.global_position
	SpriteHelper.draw_effect_texture(
		canvas,
		tex,
		local_pos,
		rot,
		Vector2.ONE * draw_scale,
		Color(1.0, 1.0, 1.0, alpha)
	)


func reset() -> void:
	shurikens.clear()
	lasers.clear()
	abyss_explosions.clear()
	hit_fx.clear()
	water_tornados.clear()
	black_holes.clear()
	whirls.clear()
	auto_bullet_cooldown = 0.0
	black_hole_spawned_this_resolve = false
	combo_fireball_milestone = 0


func clear_death_presentation() -> void:
	hit_fx.clear()
	var i := shurikens.size() - 1
	while i >= 0:
		if _projectile_kind(shurikens[i]) == "auto":
			shurikens.remove_at(i)
		i -= 1


func on_resolve_started() -> void:
	black_hole_spawned_this_resolve = false
	combo_fireball_milestone = 0
	if battle and battle.player:
		battle.player.water_tornado_charge = 0
		battle.player.whirl_charge = 0


func has_active_fx() -> bool:
	return not shurikens.is_empty() or not lasers.is_empty() or not abyss_explosions.is_empty() or not hit_fx.is_empty() or not water_tornados.is_empty() or not black_holes.is_empty() or not whirls.is_empty()


func update(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player == null:
		return
	# 子弹时间期间暂停普攻子弹/激光等自动攻击逻辑（与怪物 AI、天雷一致）
	if delta <= 0.0 or player.state == BattlePlayer.State.BULLET_TIME:
		return
	_update_auto_bullets(delta, player, monsters)
	_update_shurikens(delta, player, monsters)
	_update_lasers(delta, player, monsters)
	_update_abyss_explosions(delta, player, monsters)
	_update_hit_fx(delta)
	_update_water_tornados(delta, player, monsters)
	_update_black_holes(delta, player, monsters)
	_update_whirls(delta, player, monsters)


func on_combo_hit(combo: float, hit_pos: Vector2, seg_ang: float, player: BattlePlayer) -> void:
	if player == null or battle == null or not battle.combat.is_resolving():
		return
	var combo_floor := int(floor(combo))

	if player.get_upgrade_level("shuriken") > 0 and combo_floor > 0:
		_spawn_combo_shurikens(hit_pos, seg_ang)

	var fire_milestone := int(floor(combo_floor / 12.0)) * 12
	if player.get_upgrade_level("great_fireball") > 0 and fire_milestone >= 12 and fire_milestone > combo_fireball_milestone:
		combo_fireball_milestone = fire_milestone
		_spawn_combo_fireballs(hit_pos, seg_ang, player)

	if player.get_upgrade_level("lightning_chain") > 0 and combo_floor > 0 and combo_floor % 8 == 0:
		var monsters: Array = battle.spawner.get_active_monsters() if battle and battle.spawner else []
		_spawn_lightning_chain(hit_pos, player, monsters)

	if player.get_upgrade_level("water_tornado") > 0:
		player.water_tornado_charge += 1
		while player.water_tornado_charge >= 5:
			player.water_tornado_charge -= 5
			var cnt := player.get_upgrade_level("water_tornado")
			for i in range(cnt):
				_spawn_water_tornado(hit_pos, seg_ang, player, i, cnt)

	if player.get_upgrade_level("black_hole") > 0 and combo_floor == 8 and not black_hole_spawned_this_resolve:
		_spawn_black_hole(hit_pos, player)
		black_hole_spawned_this_resolve = true

	if player.get_upgrade_level("blade_whirl") > 0:
		player.whirl_charge += 1
		while player.whirl_charge >= 8:
			player.whirl_charge -= 8
			_spawn_whirl(hit_pos, player)


func _find_nearest_monster(from_pos: Vector2, monsters: Array):
	var nearest = null
	var nearest_dist := INF
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var d := from_pos.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = m
	return nearest


func _nearest_monster_angle(from_pos: Vector2, fallback_ang: float, monsters: Array) -> float:
	var nearest = _find_nearest_monster(from_pos, monsters)
	if nearest == null:
		return fallback_ang
	var to_monster: Vector2 = nearest.global_position - from_pos
	if to_monster.length_squared() < 4.0:
		return fallback_ang
	return to_monster.angle()


func fire_auto_bullets(player: BattlePlayer, monsters: Array) -> void:
	_spawn_auto_bullet_volley(player, monsters)


func _spawn_auto_bullet_volley(player: BattlePlayer, monsters: Array) -> void:
	if player == null or monsters.is_empty():
		return
	var base_ang := _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
	var dmg := player.get_auto_bullet_damage()
	var is_spirit := player.has_spirit_bomb()
	var count := maxi(1, player.bullet_count)
	for i in range(count):
		var ang := base_ang
		if count > 1:
			ang = base_ang + (float(i) - (count - 1) * 0.5) * AUTO_BULLET_FAN_SPREAD
		_spawn_bullet_from_angle(player, ang, dmg, is_spirit, 1.0)
	_try_spawn_laser_blast(player, monsters)


func _on_auto_bullet_released() -> void:
	if battle == null or battle.player == null or battle.spawner == null:
		return
	_spawn_auto_bullet_volley(battle.player, battle.spawner.get_active_monsters())


func _try_spawn_laser_blast(player: BattlePlayer, monsters: Array) -> void:
	if player == null or battle == null:
		return
	if randf() >= player.get_laser_blast_chance():
		return
	var spawn_pos := player.global_position
	var ang := _nearest_monster_angle(spawn_pos, -PI * 0.5, monsters)
	var dir := Vector2(cos(ang), sin(ang))
	var exit_dist := _ray_playfield_exit_distance(spawn_pos, dir)
	var beam_length := exit_dist + GameConfig.scale_world(72.0) * FX_SCALE
	lasers.append(_with_upgrade_fx_layer({
		"kind": "laser",
		"tail": spawn_pos,
		"origin": spawn_pos,
		"dir": dir,
		"exit_dist": exit_dist,
		"beam_length": beam_length,
		"vel": dir * 960.0,
		"damage": player.get_auto_bullet_damage(),
		"hit": {},
		"rot": ang,
	}, "laser_blast"))


func _is_out_of_playfield(pos: Vector2) -> bool:
	return battle != null and not battle.is_in_bounds(pos)


func _ray_playfield_exit_distance(origin: Vector2, dir: Vector2) -> float:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var best := INF
	if absf(dir.x) > 0.0001:
		if dir.x > 0.0:
			best = minf(best, (w - origin.x) / dir.x)
		else:
			best = minf(best, (0.0 - origin.x) / dir.x)
	if absf(dir.y) > 0.0001:
		if dir.y > 0.0:
			best = minf(best, (h - origin.y) / dir.y)
		else:
			best = minf(best, (0.0 - origin.y) / dir.y)
	return maxf(0.0, best)


func _laser_head(s: Dictionary) -> Vector2:
	return Vector2(s.get("tail", s.get("pos", Vector2.ZERO))) + Vector2(s.get("dir", Vector2.RIGHT)) * float(s.get("beam_length", 0.0))


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _apply_laser_hits(s: Dictionary, player: BattlePlayer, monsters: Array) -> void:
	var tail: Vector2 = s.get("tail", s.get("pos", Vector2.ZERO))
	var head := _laser_head(s)
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var hit_r := 16.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if _point_segment_distance(m.global_position, tail, head) > hit_r + 10.0:
			continue
		s["pos"] = m.global_position
		_apply_projectile_hit(s, m, player)


func _auto_pierce_max_range(s: Dictionary) -> float:
	return Vector2(s.get("vel", Vector2.ZERO)).length() * float(s.get("max_life", GameConfig.get_player_value("auto_bullet_life", 0.9)))


func _auto_travel_distance(s: Dictionary) -> float:
	var origin: Vector2 = s.get("origin", s.get("pos", Vector2.ZERO))
	return Vector2(s.get("pos", Vector2.ZERO)).distance_to(origin)


func _auto_reached_pierce_max_range(s: Dictionary) -> bool:
	return _auto_travel_distance(s) >= _auto_pierce_max_range(s)


func _auto_outbound_mirror_pending(s: Dictionary, player: BattlePlayer) -> bool:
	if player == null or _projectile_kind(s) != "auto":
		return false
	if bool(s.get("returning", false)) or bool(s.get("mirror_used", false)):
		return false
	return player.has_mirror_bullet()


func _start_mirror_return(s: Dictionary, player: BattlePlayer) -> void:
	s["returning"] = true
	s["mirror_used"] = true
	s["hit"] = {}
	_redirect_auto_to_player(s, player)


func _try_start_outbound_mirror_return(s: Dictionary, player: BattlePlayer) -> bool:
	if not _auto_outbound_mirror_pending(s, player):
		return false
	# 穿透+镜像：飞到穿透最大攻击距离后折返；仅镜像：出屏后折返
	if player.has_pierce_bullet():
		if not _auto_reached_pierce_max_range(s):
			return false
	elif not _is_out_of_playfield(Vector2(s.get("pos", Vector2.ZERO))):
		return false
	_start_mirror_return(s, player)
	return true


func _auto_projectile_should_remove(s: Dictionary, player: BattlePlayer, out_of_bounds: bool) -> bool:
	if bool(s.get("returning", false)):
		if player == null:
			return true
		return Vector2(s.pos).distance_to(player.global_position) <= player.get_effective_radius() + 10.0
	if player != null and _auto_outbound_mirror_pending(s, player) and player.has_pierce_bullet():
		if _auto_reached_pierce_max_range(s):
			return not _try_start_outbound_mirror_return(s, player)
		return false
	if out_of_bounds:
		if _try_start_outbound_mirror_return(s, player):
			return false
		return true
	if _auto_outbound_mirror_pending(s, player):
		return false
	return float(s.life) <= 0.0


func try_abyss_explosion(player: BattlePlayer, path: Array) -> void:
	var lv := player.get_upgrade_level("abyss_explosion")
	if lv <= 0 or path.size() < 5:
		return
	var loops := MathUtils.path_extract_all_closed_loops(path)
	if loops.is_empty():
		return
	var def := GameConfig.get_upgrade("abyss_explosion")
	var dmg_mul := pow(float(def.get("apply_value", 1.2)), float(lv))
	var anim_life := EffectHelperScript.one_shot_anim_duration(_explosion_frames)
	if anim_life <= 0.0:
		anim_life = 0.55
	for loop in loops:
		var center := MathUtils.polygon_centroid(loop)
		var radius := MathUtils.path_loop_radius(loop, center)
		var explosion := _with_upgrade_fx_layer({
			"kind": "abyss_explosion",
			"pos": center,
			"radius": radius,
			"life": anim_life,
			"max_life": anim_life,
			"anim_t": 0.0,
			"dmg_mul": 1 * dmg_mul,
			"hit": {},
		}, "abyss_explosion")
		explosion["damage_applied"] = false
		abyss_explosions.append(explosion)
		_skill_burst(center, 9.0, 0.2, Color("#ff6020"), 24)


func _update_auto_bullets(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player.state != BattlePlayer.State.IDLE:
		return
	if player.bullet_count <= 0:
		return
	if monsters.is_empty():
		return
	_connect_auto_bullet_release()
	auto_bullet_cooldown -= delta
	if auto_bullet_cooldown > 0.0:
		return
	if not player.begin_auto_bullet_cycle():
		return
	auto_bullet_cooldown = player.get_auto_bullet_cycle_interval()


func _spawn_bullet_from_angle(player: BattlePlayer, ang: float, damage: int, is_spirit: bool, visual_scale: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var spawn_pos := player.global_position + dir * (player.get_effective_radius() + GameConfig.scale_world(AUTO_BULLET_SPAWN_OFFSET))
	var max_life := float(GameConfig.get_player_value("auto_bullet_life", 0.9))
	if player.has_pierce_bullet():
		max_life *= float(GameConfig.get_player_value("auto_bullet_pierce_range_mul", 0.85))
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"pos": spawn_pos,
		"origin": spawn_pos,
		"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)),
		"life": max_life,
		"max_life": max_life,
		"damage": damage,
		"hit": {},
		"rot": ang,
		"anim_t": 0.0,
		"visual_scale": visual_scale,
		"is_spirit": is_spirit,
		"bounces_left": player.get_bounce_bullet_count(),
		"returning": false,
		"mirror_used": false,
	}, "spirit_bomb" if is_spirit else "multi_bullet"))
	_finalize_spawned_projectile(shurikens.back(), player)


func _spawn_combo_shurikens(pos: Vector2, seg_ang: float) -> void:
	for i in range(2):
		var spread := seg_ang + MathUtils.rand_range(-0.55, 0.55)
		var spd := MathUtils.rand_range(340.0, 500.0)
		shurikens.append(_with_upgrade_fx_layer({
			"kind": "skill",
			"pos": pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
			"vel": Vector2(cos(spread), sin(spread)) * spd,
			"life": MathUtils.rand_range(0.42, 0.62),
			"damage": 0,
			"hit": {},
			"rot": randf() * TAU,
			"spin": MathUtils.rand_range(10.0, 18.0) * (-1.0 if randf() < 0.5 else 1.0),
			"dmg_mul": 0.10,
		}, "shuriken"))
	_skill_burst(pos, 4.5, 0.1, Color("#b8cce8"), 8)


func _spawn_combo_fireballs(pos: Vector2, seg_ang: float, player: BattlePlayer) -> void:
	var lv := player.get_upgrade_level("great_fireball")
	var cnt := 3 + maxi(0, lv - 1)
	for i in range(cnt):
		var a := seg_ang + MathUtils.rand_range(-0.9, 0.9)
		shurikens.append(_with_upgrade_fx_layer({
			"kind": "fireball",
			"pos": pos,
			"vel": Vector2(cos(a), sin(a)) * 280.0,
			"life": 0.95,
			"damage": 0,
			"hit": {},
			"rot": a,
			"spin": 0.0,
			"dmg_mul": 1.0,
			"visual_scale": 1.5,
		}, "great_fireball"))
	_skill_burst(pos, 6.5, 0.16, Color("#ff7020"), 18)


func _spawn_water_tornado(pos: Vector2, seg_ang: float, player: BattlePlayer, idx: int, total: int) -> void:
	var lv := player.get_upgrade_level("water_tornado")
	var spread := 0.0 if total <= 1 else (float(idx) - (total - 1) * 0.5) * 0.22
	var monsters: Array = battle.spawner.get_active_monsters() if battle and battle.spawner else []
	var ang := _nearest_monster_angle(pos, seg_ang, monsters) + spread
	water_tornados.append(_with_upgrade_fx_layer({
		"kind": "water_tornado",
		"pos": pos,
		"vel": Vector2(cos(ang), sin(ang)) * 360.0,
		"life": 1.85,
		"max_life": 1.85,
		"anim_t": 0.0,
		"hit": {},
		"dmg_mul": 0.55 + 0.1 * float(lv),
	}, "water_tornado"))
	_skill_burst(pos, 5.5, 0.14, Color("#58d8ff"), 14)


func _spawn_black_hole(pos: Vector2, player: BattlePlayer) -> void:
	var lv := player.get_upgrade_level("black_hole")
	black_holes.append(_with_upgrade_fx_layer({
		"kind": "black_hole",
		"pos": pos,
		"radius": GameConfig.scale_world(49.2 + float(lv) * 24.0) * FX_SCALE,
		"life": 1.9,
		"max_life": 1.9,
		"anim_t": 0.0,
		"pull": 220.0 + float(lv) * 65.0,
		"dmg_timer": 0.0,
		"hit": {},
		"dmg_mul": 0.45 + 0.08 * float(lv),
	}, "black_hole"))
	_skill_burst(pos, 8.0, 0.2, Color("#9040d8"), 20)


func _spawn_whirl(pos: Vector2, player: BattlePlayer) -> void:
	var lv := player.get_upgrade_level("blade_whirl")
	var base_r := GameConfig.scale_world((68.0 + float(lv) * 8.0) * 1.12) * FX_SCALE
	whirls.append(_with_upgrade_fx_layer({
		"kind": "whirl",
		"pos": pos,
		"radius": base_r * 0.55,
		"max_radius": base_r,
		"life": 0.9,
		"max_life": 0.9,
		"anim_t": 0.0,
		"hit": {},
		"dmg_mul": 0.35 + float(lv) * 0.12,
	}, "blade_whirl"))
	_skill_burst(pos, 6.0, 0.15, Color("#ffe060"), 16)


func _spawn_lightning_chain(from_pos: Vector2, player: BattlePlayer, monsters: Array) -> void:
	_skill_burst(from_pos, 7.5, 0.17, Color("#a8e8ff"), 12)
	var targets: Array = []
	for m in monsters:
		if is_instance_valid(m) and m.get("alive") != false:
			targets.append(m)
	targets.sort_custom(func(a, b): return from_pos.distance_to(a.global_position) < from_pos.distance_to(b.global_position))
	var chain_count := mini(3 + player.get_upgrade_level("lightning_chain"), targets.size())
	var dmg := int(max(1, round(player.base_attack * player.attack_power_scale * 0.6)))
	var chain_from := from_pos
	for i in range(chain_count):
		var m = targets[i]
		var to_pos: Vector2 = m.global_position
		if battle and battle.particles:
			battle.particles.lightning_effect(chain_from, to_pos)
		if m.has_method("take_damage"):
			var result: Dictionary = m.take_damage(dmg, chain_from)
			if battle and battle.combat:
				battle.combat.spawn_damage_number(to_pos, int(result.get("damage", 0)), false, false, Color("#f8d020"))
			if battle and battle.particles:
				battle.particles.hit_spark(to_pos, false)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
		chain_from = to_pos


func _projectile_kind(s: Dictionary) -> String:
	return str(s.get("kind", ""))


func _projectile_hit_distance(s: Dictionary, m) -> float:
	var hit_r := 16.0
	if m.has_method("get_hitbox_radius"):
		hit_r = m.get_hitbox_radius()
	var kind := _projectile_kind(s)
	if kind in ["abyss_explosion", "whirl", "black_hole", "water_tornado"]:
		return float(s.get("radius", 48.0)) + hit_r
	var pad := 8.0
	if kind == "auto":
		pad = AUTO_HIT_VISUAL_PAD
	return hit_r + pad


func _try_projectile_collision(s: Dictionary, player: BattlePlayer, monsters: Array) -> bool:
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if _apply_projectile_hit(s, m, player):
			if _projectile_kind(s) == "auto":
				return _should_remove_auto_projectile(s, player, monsters)
			if _projectile_kind(s) in ["skill", "fireball"]:
				return true
	return false


func _should_remove_auto_projectile(s: Dictionary, player: BattlePlayer, monsters: Array) -> bool:
	if bool(s.get("returning", false)):
		var dist := Vector2(s.pos).distance_to(player.global_position)
		return dist <= player.get_effective_radius() + 10.0
	var pierce := player.has_pierce_bullet()
	if not pierce:
		var bounces := int(s.get("bounces_left", 0))
		if bounces > 0:
			s["bounces_left"] = bounces - 1
			if _redirect_auto_to_next_enemy(s, monsters):
				return false
	if player.has_mirror_bullet() and not bool(s.get("mirror_used", false)) and not pierce:
		_start_mirror_return(s, player)
		return false
	return not pierce


func _redirect_auto_to_next_enemy(s: Dictionary, monsters: Array) -> bool:
	var from_pos: Vector2 = s.get("pos", Vector2.ZERO)
	var hit: Dictionary = s.get("hit", {})
	var nearest: Node2D = null
	var nearest_dist := INF
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if hit.has(str(m.get_instance_id())):
			continue
		var d := from_pos.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = m
	if nearest == null:
		return false
	var dir: Vector2 = nearest.global_position - from_pos
	if dir.length_squared() < 4.0:
		return false
	var ang: float = dir.angle()
	s["vel"] = Vector2(cos(ang), sin(ang)) * float(GameConfig.get_player_value("auto_bullet_speed", 420))
	s["rot"] = ang
	return true


func _redirect_auto_to_player(s: Dictionary, player: BattlePlayer) -> void:
	var dir: Vector2 = player.global_position - Vector2(s.get("pos", Vector2.ZERO))
	if dir.length_squared() < 4.0:
		return
	var ang: float = dir.angle()
	s["vel"] = Vector2(cos(ang), sin(ang)) * float(GameConfig.get_player_value("auto_bullet_speed", 420))
	s["rot"] = ang


func _finalize_spawned_projectile(s: Dictionary, player: BattlePlayer) -> void:
	if battle == null or battle.spawner == null:
		return
	# 普攻子弹从主角前方飞出后再参与碰撞，避免出生即必中。
	if _projectile_kind(s) == "auto":
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	if _try_projectile_collision(s, player, monsters):
		var idx := shurikens.size() - 1
		if idx >= 0 and shurikens[idx] == s:
			shurikens.remove_at(idx)
	else:
		shurikens[shurikens.size() - 1] = s


func _apply_projectile_hit(s: Dictionary, m, player: BattlePlayer) -> bool:
	var key := str(m.get_instance_id())
	var hit: Dictionary = s.get("hit", {})
	if hit.has(key):
		return false
	var pos: Vector2 = s.get("pos", Vector2.ZERO)
	if pos.distance_to(m.global_position) > _projectile_hit_distance(s, m):
		return false
	hit[key] = true
	s["hit"] = hit
	var dmg := int(s.get("damage", 0))
	if dmg <= 0:
		var mul := float(s.get("dmg_mul", 0.35))
		dmg = int(max(1, round(player.base_attack * player.attack_power_scale * mul)))
	var kind := _projectile_kind(s)
	var is_crit := false
	if kind in ["auto", "laser"]:
		var dmg_info: Dictionary = player.roll_crit_damage(float(dmg))
		dmg = int(dmg_info.get("amount", dmg))
		is_crit = bool(dmg_info.get("is_crit", false))
	if m.has_method("take_damage"):
		var result: Dictionary = m.take_damage(dmg, pos)
		if battle and battle.combat:
			battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), is_crit)
		if kind == "auto":
			var fx_scale := float(s.get("visual_scale", 1.0))
			_spawn_auto_hit_fx(m, fx_scale)
			_apply_auto_bullet_upgrade_effects(s, m, player, int(result.get("damage", 0)))
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(m)
	return true


func _apply_auto_bullet_upgrade_effects(s: Dictionary, m, player: BattlePlayer, dealt_damage: int) -> void:
	if player == null:
		return
	var burn_lv := player.get_upgrade_level("bullet_burn")
	if burn_lv > 0 and m.has_method("apply_burn_dot"):
		var burn_dps := int(max(1, round(player.get_ability_damage(0.14 + 0.06 * float(maxi(0, burn_lv - 1))))))
		m.apply_burn_dot(1.5, burn_dps)
	var close_lv := player.get_upgrade_level("close_range_shot")
	if close_lv > 0 and dealt_damage > 0:
		var travel := Vector2(s.get("pos", Vector2.ZERO)).distance_to(Vector2(s.get("origin", Vector2.ZERO)))
		var max_range := maxf(24.0, _auto_pierce_max_range(s))
		var near_ratio := clampf(1.0 - travel / max_range, 0.0, 1.0)
		var tier_bonus := _close_range_tier_bonus(near_ratio)
		var bonus_mul := (0.35 + 0.12 * float(maxi(0, close_lv - 1))) * tier_bonus
		if bonus_mul > 0.0 and m.has_method("take_damage"):
			var extra_info: Dictionary = player.roll_crit_damage(float(dealt_damage) * bonus_mul)
			var extra := int(extra_info.get("amount", 1))
			var extra_crit := bool(extra_info.get("is_crit", false))
			var result: Dictionary = m.take_damage(extra, Vector2(s.get("pos", Vector2.ZERO)))
			if battle and battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), extra_crit)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)


func _close_range_tier_bonus(near_ratio: float) -> float:
	# 近距离射击做 10 段细分，避免出现“飞一段没变化”的体感。
	var r := clampf(near_ratio, 0.0, 1.0)
	if r >= 0.95:
		return 1.00
	if r >= 0.85:
		return 0.90
	if r >= 0.75:
		return 0.80
	if r >= 0.65:
		return 0.70
	if r >= 0.55:
		return 0.60
	if r >= 0.45:
		return 0.50
	if r >= 0.35:
		return 0.40
	if r >= 0.25:
		return 0.30
	if r >= 0.15:
		return 0.20
	if r >= 0.05:
		return 0.10
	return 0.05


func _update_shurikens(delta: float, player: BattlePlayer, monsters: Array) -> void:
	var i := shurikens.size() - 1
	while i >= 0:
		var s: Dictionary = shurikens[i]
		var remove: bool = battle == null
		if not remove and _try_projectile_collision(s, player, monsters):
			if _projectile_kind(s) == "auto":
				remove = _should_remove_auto_projectile(s, player, monsters)
			else:
				remove = true
		if not remove:
			s["pos"] = s.pos + s.vel * delta
			if _projectile_kind(s) == "auto":
				if not bool(s.get("returning", false)) and not _auto_outbound_mirror_pending(s, player):
					s["life"] = float(s.life) - delta
				s["anim_t"] = float(s.get("anim_t", 0.0)) + delta
				if bool(s.get("returning", false)) and player != null:
					_redirect_auto_to_player(s, player)
			else:
				s["rot"] = float(s.rot) + float(s.get("spin", 0.0)) * delta
				s["life"] = float(s.life) - delta
			var out_of_bounds := _is_out_of_playfield(Vector2(s.get("pos", Vector2.ZERO)))
			if _projectile_kind(s) == "auto":
				remove = _auto_projectile_should_remove(s, player, out_of_bounds)
			else:
				remove = remove or float(s.life) <= 0.0 or out_of_bounds
			if not remove and _try_projectile_collision(s, player, monsters):
				if _projectile_kind(s) == "auto":
					remove = _should_remove_auto_projectile(s, player, monsters)
				else:
					remove = true
		if remove:
			shurikens.remove_at(i)
		else:
			shurikens[i] = s
		i -= 1


func _update_lasers(delta: float, player: BattlePlayer, monsters: Array) -> void:
	var i := lasers.size() - 1
	while i >= 0:
		var s: Dictionary = lasers[i]
		s["tail"] = Vector2(s.get("tail", s.get("pos", Vector2.ZERO))) + Vector2(s.vel) * delta
		s["pos"] = _laser_head(s)
		var origin: Vector2 = s.get("origin", s.get("tail", Vector2.ZERO))
		var traveled := (Vector2(s.get("tail", Vector2.ZERO)) - origin).dot(Vector2(s.get("dir", Vector2.RIGHT)))
		var remove: bool = battle == null or traveled >= float(s.get("exit_dist", 0.0)) + float(s.get("beam_length", 0.0))
		if not remove:
			_apply_laser_hits(s, player, monsters)
		if remove:
			lasers.remove_at(i)
		else:
			lasers[i] = s
		i -= 1


func _abyss_explosion_frame_index(anim_t: float) -> int:
	if _explosion_frames == null or _explosion_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return 0
	var speed := _explosion_frames.get_animation_speed(EffectHelperScript.ANIM_PREVIEW)
	if speed <= 0.0:
		speed = 14.0
	return int(floor(anim_t * speed))


func _apply_abyss_explosion_damage(fx: Dictionary, player: BattlePlayer, monsters: Array) -> void:
	if bool(fx.get("damage_applied", false)):
		return
	fx["damage_applied"] = true
	var center: Vector2 = fx.get("pos", Vector2.ZERO)
	var radius: float = float(fx.get("radius", 48.0))
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if m.global_position.distance_to(center) > radius + m.get_hitbox_radius():
			continue
		_apply_projectile_hit(fx, m, player)


func _update_abyss_explosions(delta: float, player: BattlePlayer, monsters: Array) -> void:
	for i in range(abyss_explosions.size() - 1, -1, -1):
		var fx: Dictionary = abyss_explosions[i]
		fx["life"] = float(fx.life) - delta
		fx["anim_t"] = float(fx.get("anim_t", 0.0)) + delta
		if not bool(fx.get("damage_applied", false)) and _abyss_explosion_frame_index(float(fx.anim_t)) >= ABYSS_EXPLOSION_DAMAGE_FRAME:
			_apply_abyss_explosion_damage(fx, player, monsters)
		if float(fx.life) <= 0.0:
			abyss_explosions.remove_at(i)
		else:
			abyss_explosions[i] = fx


func _spawn_auto_hit_fx(target: Node2D, scale_mul: float = 1.0) -> void:
	if _smoke_hit_frames == null or _smoke_hit_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	if target == null or not is_instance_valid(target):
		return
	hit_fx.append({
		"target": target,
		"pos": _hit_fx_center_pos(target),
		"anim_t": 0.0,
		"duration": EffectHelperScript.one_shot_anim_duration(_smoke_hit_frames),
		"scale": AUTO_HIT_FX_SCALE * scale_mul,
	})


func _hit_fx_center_pos(target: Variant) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	if target is Node2D:
		return target.global_position
	return Vector2.ZERO


func _update_hit_fx(delta: float) -> void:
	for i in range(hit_fx.size() - 1, -1, -1):
		var fx: Dictionary = hit_fx[i]
		fx["anim_t"] = float(fx.anim_t) + delta
		var target = fx.get("target")
		if target != null and is_instance_valid(target):
			fx["pos"] = _hit_fx_center_pos(target)
		if float(fx.anim_t) >= float(fx.duration):
			hit_fx.remove_at(i)
		else:
			hit_fx[i] = fx


func draw_hit_fx(canvas: Node2D) -> void:
	if _smoke_hit_frames == null:
		return
	for fx in hit_fx:
		var tex := EffectHelperScript.animation_frame_texture_once(_smoke_hit_frames, float(fx.anim_t))
		if tex == null:
			continue
		var life_t := clampf(float(fx.anim_t) / maxf(0.001, float(fx.duration)), 0.0, 1.0)
		var alpha := 0.95 - life_t * 0.35
		var draw_scale := HIT_FX_DRAW_SCALE * float(fx.scale)
		var center_global: Vector2 = fx.get("pos", Vector2.ZERO)
		var target = fx.get("target")
		if target != null and is_instance_valid(target):
			center_global = _hit_fx_center_pos(target)
		var local_center: Vector2 = center_global - canvas.global_position
		SpriteHelper.draw_effect_texture(
			canvas,
			tex,
			local_center,
			0.0,
			Vector2.ONE * draw_scale,
			Color(1.0, 0.92, 0.82, alpha)
		)


func _update_water_tornados(delta: float, player: BattlePlayer, monsters: Array) -> void:
	for i in range(water_tornados.size() - 1, -1, -1):
		var t = water_tornados[i]
		t["pos"] = Vector2(t.pos) + Vector2(t.vel) * delta
		t["life"] = float(t.life) - delta
		t["anim_t"] = float(t.get("anim_t", 0.0)) + delta
		if float(t.life) <= 0.0:
			water_tornados.remove_at(i)
			continue
		for m in monsters:
			if not is_instance_valid(m) or m.get("alive") == false:
				continue
			_apply_projectile_hit(t, m, player)


func _update_black_holes(delta: float, player: BattlePlayer, monsters: Array) -> void:
	for i in range(black_holes.size() - 1, -1, -1):
		var bh = black_holes[i]
		bh.life -= delta
		bh.dmg_timer -= delta
		bh["anim_t"] = float(bh.get("anim_t", 0.0)) + delta
		if bh.life <= 0.0:
			black_holes.remove_at(i)
			continue
		for m in monsters:
			if not is_instance_valid(m) or m.get("alive") == false:
				continue
			var to_center: Vector2 = bh.pos - m.global_position
			var dist := to_center.length()
			if dist > float(bh.radius) + 20.0:
				continue
			if dist > 4.0:
				m.global_position += to_center.normalized() * minf(float(bh.pull) * delta, dist * 0.35)
			if bh.dmg_timer <= 0.0:
				_apply_projectile_hit(bh, m, player)
		if bh.dmg_timer <= 0.0:
			bh.dmg_timer = 0.12


func _update_whirls(delta: float, player: BattlePlayer, monsters: Array) -> void:
	for i in range(whirls.size() - 1, -1, -1):
		var w = whirls[i]
		w.life -= delta
		w.anim_t = float(w.get("anim_t", 0.0)) + delta
		var life_t := clampf(float(w.life) / float(w.max_life), 0.0, 1.0)
		w.radius = lerpf(float(w.max_radius) * 0.55, float(w.max_radius), 1.0 - life_t)
		if w.life <= 0.0:
			whirls.remove_at(i)
			continue
		for m in monsters:
			if not is_instance_valid(m) or m.get("alive") == false:
				continue
			if m.global_position.distance_to(w.pos) > float(w.radius) + m.get_hitbox_radius():
				continue
			_apply_projectile_hit(w, m, player)


func _draw_animated_projectile(
	canvas: Node2D,
	world_pos: Vector2,
	rot: float,
	frames: SpriteFrames,
	scale_mul: float,
	anim_t: float,
	alpha: float = 1.0
) -> void:
	if frames == null or frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	var tex := EffectHelperScript.animation_frame_texture(frames, anim_t)
	if tex == null:
		return
	var draw_scale := PROJ_DRAW_SCALE * scale_mul * FX_SCALE * GameConfig.get_world_scale()
	var local_pos: Vector2 = world_pos - canvas.global_position
	SpriteHelper.draw_effect_texture(
		canvas,
		tex,
		local_pos,
		rot,
		Vector2.ONE * draw_scale,
		Color(1.0, 1.0, 1.0, alpha)
	)


func _draw_auto_bullet(canvas: Node2D, s: Dictionary) -> void:
	var frames: SpriteFrames = _auto_bullet_frames
	if bool(s.get("is_spirit", false)):
		frames = _spirit_frames
	var draw_scale := float(s.get("visual_scale", 1.0)) * AUTO_BULLET_DRAW_SCALE
	if bool(s.get("is_spirit", false)):
		draw_scale *= 1.15
	var max_life := float(s.get("max_life", GameConfig.get_player_value("auto_bullet_life", 0.9)))
	var life_t := clampf(float(s.life) / maxf(0.001, max_life), 0.0, 1.0)
	var modulate := Color(1.0, 1.0, 1.0, 0.82 + life_t * 0.18)
	if bool(s.get("returning", false)):
		modulate = Color(0.75, 0.95, 1.0, modulate.a)
	_draw_animated_projectile(
		canvas,
		Vector2(s.pos),
		float(s.rot),
		frames,
		draw_scale,
		float(s.get("anim_t", 0.0)),
		modulate.a
	)
	var glow_r := GameConfig.scale_world(12.0) * FX_SCALE * draw_scale * PROJ_DRAW_SCALE
	var local: Vector2 = Vector2(s.pos) - canvas.global_position
	var glow_col := Color(1.0, 0.42, 0.1, 0.22 * life_t)
	if bool(s.get("returning", false)):
		glow_col = Color(0.55, 0.85, 1.0, 0.24 * life_t)
	canvas.draw_circle(local, glow_r, glow_col)


func _fireball_block_color(dist_ratio: float, flicker: bool) -> Color:
	if dist_ratio > 0.92:
		return Color("#4a1808") if not flicker else Color("#3a1408")
	if dist_ratio > 0.78:
		return Color("#c83818") if not flicker else Color("#b83818")
	if dist_ratio > 0.55:
		return Color("#ff9c38") if not flicker else Color("#ff8830")
	if dist_ratio > 0.32:
		return Color("#ffc868") if not flicker else Color("#ffb858")
	return Color("#ffe8b0") if not flicker else Color("#fff0c0")


func _draw_pixel_fireball(canvas: CanvasItem, world_pos: Vector2, rot: float, life_t: float) -> void:
	var px := float(FIREBALL_PIXEL)
	var rb := float(FIREBALL_RADIUS_BLOCKS)
	var flicker := int(Time.get_ticks_msec() / 50) % 2 == 0
	var local: Vector2 = world_pos - canvas.global_position
	canvas.draw_set_transform(local, rot, Vector2.ONE)
	for by in range(-int(rb), int(rb) + 1):
		for bx in range(-int(rb), int(rb) + 1):
			var d := sqrt(float(bx * bx + by * by))
			if d > rb + 0.35:
				continue
			var ratio := d / rb
			canvas.draw_rect(
				Rect2(bx * px - px * 0.5, by * px - px * 0.5, px, px),
				_fireball_block_color(ratio, flicker and ratio > 0.45)
			)
	var core := Color("#fffaf0") if not flicker else Color("#fff8e8")
	canvas.draw_rect(Rect2(-px, -px, px, px), core)
	canvas.draw_rect(Rect2(px - px, -px, px, px), core)
	canvas.draw_rect(Rect2(-px, px - px, px, px), core)
	canvas.draw_rect(Rect2(px - px, px - px, px, px), core)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_laser(canvas: Node2D, s: Dictionary) -> void:
	var tail: Vector2 = Vector2(s.get("tail", s.get("pos", Vector2.ZERO))) - canvas.global_position
	var head := _laser_head(s) - canvas.global_position
	var origin: Vector2 = Vector2(s.get("origin", s.tail)) - canvas.global_position
	var dir := Vector2(s.get("dir", Vector2.RIGHT)).normalized()
	var tip := head + dir * GameConfig.scale_world(12.0) * FX_SCALE
	canvas.draw_line(tail, tip, Color(1.0, 0.28, 0.82, 0.42), GameConfig.scale_world(22.0) * FX_SCALE)
	canvas.draw_line(tail, tip, Color(1.0, 0.72, 1.0, 0.95), GameConfig.scale_world(9.0) * FX_SCALE)
	canvas.draw_line(tail, tip, Color(1.0, 1.0, 1.0, 0.88), GameConfig.scale_world(3.5) * FX_SCALE)
	for i in range(7):
		var t := float(i) / 6.0
		var p := tail.lerp(tip, t)
		canvas.draw_rect(Rect2(p.x - 3.0, p.y - 3.0, 6.0, 6.0), Color(1.0, 1.0, 1.0, 0.75))
	canvas.draw_circle(origin, GameConfig.scale_world(7.0) * FX_SCALE, Color(1.0, 0.55, 1.0, 0.55))
	canvas.draw_circle(head, GameConfig.scale_world(5.0) * FX_SCALE, Color(1.0, 1.0, 1.0, 0.9))


func _draw_abyss_explosion(canvas: Node2D, fx: Dictionary) -> void:
	if _explosion_frames == null or _explosion_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	var tex := EffectHelperScript.animation_frame_texture_once(_explosion_frames, float(fx.get("anim_t", 0.0)))
	if tex == null:
		return
	var br := float(fx.get("radius", 48.0))
	var size := tex.get_size()
	var draw_scale := (br * 2.0) / maxf(size.x, size.y)
	var draw_size := size * draw_scale
	var local_pos: Vector2 = Vector2(fx.pos) - canvas.global_position
	SpriteHelper.draw_effect_texture_rect(
		canvas,
		tex,
		Rect2(local_pos - draw_size * 0.5, draw_size),
		Color(1.0, 1.0, 1.0, 0.92)
	)


func _draw_pixel_shuriken(canvas: CanvasItem, center: Vector2, rot: float, px: float) -> void:
	var rows := SHURIKEN_PIXELS.size()
	var cols: int = SHURIKEN_PIXELS[0].size()
	var ox: float = -floor((cols * px) * 0.5)
	var oy: float = -floor((rows * px) * 0.5)
	var local := Vector2(floor(center.x), floor(center.y))
	canvas.draw_set_transform(local, rot, Vector2.ONE)
	for r in range(rows):
		for c in range(cols):
			var hex: Variant = SHURIKEN_PIXELS[r][c]
			if hex == null:
				continue
			canvas.draw_rect(Rect2(ox + c * px, oy + r * px, px, px), Color(hex))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	for s in shurikens:
		if not _fx_on_layer(s, below_monsters):
			continue
		var kind := _projectile_kind(s)
		if kind == "auto":
			_draw_auto_bullet(canvas, s)
			continue
		if kind == "fireball":
			var life_t := clampf(float(s.life) / 0.95, 0.0, 1.0)
			_draw_pixel_fireball(canvas, Vector2(s.pos), float(s.rot), life_t)
			continue
		_draw_pixel_shuriken(canvas, Vector2(s.pos) - canvas.global_position, float(s.rot), SHURIKEN_PIXEL)
	for laser in lasers:
		if not _fx_on_layer(laser, below_monsters):
			continue
		_draw_laser(canvas, laser)
	for fx in abyss_explosions:
		if not _fx_on_layer(fx, below_monsters):
			continue
		_draw_abyss_explosion(canvas, fx)
	for t in water_tornados:
		if not _fx_on_layer(t, below_monsters):
			continue
		var life_t := clampf(float(t.life) / float(t.max_life), 0.0, 1.0)
		_draw_water_tornado(canvas, t, life_t)
	for bh in black_holes:
		if not _fx_on_layer(bh, below_monsters):
			continue
		var bh_life_t := clampf(float(bh.life) / float(bh.max_life), 0.0, 1.0)
		_draw_black_hole(canvas, bh, bh_life_t)
	for w in whirls:
		if not _fx_on_layer(w, below_monsters):
			continue
		var whirl_life_t := clampf(float(w.life) / float(w.max_life), 0.0, 1.0)
		var whirl_tex := EffectHelperScript.animation_frame_texture(_whirl_frames, float(w.anim_t))
		if whirl_tex != null:
			var whirl_scale := PROJ_DRAW_SCALE * 1.4 * FX_SCALE
			var whirl_local: Vector2 = Vector2(w.pos) - canvas.global_position
			SpriteHelper.draw_effect_texture(
				canvas,
				whirl_tex,
				whirl_local,
				0.0,
				Vector2.ONE * whirl_scale,
				Color(1.0, 1.0, 1.0, 0.75 + whirl_life_t * 0.25)
			)
