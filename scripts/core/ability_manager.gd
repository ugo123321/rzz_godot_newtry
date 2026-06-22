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
# Phase 6 sr=25 trail_elem_field：场域格列表
var v6_trail_fields: Array = []
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
	v6_trail_fields.clear()
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
	_update_v6_trail_fields(delta, player, monsters)


func on_combo_hit(combo: float, hit_pos: Vector2, seg_ang: float, player: BattlePlayer) -> void:
	if player == null or battle == null or not battle.combat.is_resolving():
		return
	var combo_floor := int(floor(combo))
	# Phase 6 sr=20 combo_milestone_spell：5 张 v6 combo_* 卡按 trigger_value 触发
	SpecialRuleDispatcher.on_combo_milestone(player, self, combo_floor, hit_pos, seg_ang)


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
	var count := maxi(1, player.bullet_count)
	for i in range(count):
		var ang := base_ang
		if count > 1:
			ang = base_ang + (float(i) - (count - 1) * 0.5) * AUTO_BULLET_FAN_SPREAD
		_spawn_bullet_from_angle(player, ang, dmg, false, 1.0)
	# Phase 3 sr=17 bullet_side：dispatcher 返回斜射额外角度
	var extra_angles: Array = SpecialRuleDispatcher.collect_extra_bullet_angles(player, base_ang)
	for ang2 in extra_angles:
		_spawn_bullet_from_angle(player, float(ang2), dmg, false, 1.0)


func _on_auto_bullet_released() -> void:
	if battle == null or battle.player == null or battle.spawner == null:
		return
	_spawn_auto_bullet_volley(battle.player, battle.spawner.get_active_monsters())


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


func _auto_outbound_mirror_pending(s: Dictionary, player: BattlePlayer) -> bool:
	if player == null or _projectile_kind(s) != "auto":
		return false
	if bool(s.get("returning", false)) or bool(s.get("mirror_used", false)):
		return false
	return float(player.bullet_mirror_mult) > 0.0


func _start_mirror_return(s: Dictionary, player: BattlePlayer) -> void:
	s["returning"] = true
	s["mirror_used"] = true
	s["hit"] = {}
	_redirect_auto_to_player(s, player)


func _try_start_outbound_mirror_return(s: Dictionary, player: BattlePlayer) -> bool:
	if not _auto_outbound_mirror_pending(s, player):
		return false
	# 仅镜像：出屏后折返
	if not _is_out_of_playfield(Vector2(s.get("pos", Vector2.ZERO))):
		return false
	_start_mirror_return(s, player)
	return true


func _auto_projectile_should_remove(s: Dictionary, player: BattlePlayer, out_of_bounds: bool) -> bool:
	if bool(s.get("returning", false)):
		if player == null:
			return true
		return Vector2(s.pos).distance_to(player.global_position) <= player.get_effective_radius() + 10.0
	if out_of_bounds:
		if _try_start_outbound_mirror_return(s, player):
			return false
		return true
	if _auto_outbound_mirror_pending(s, player):
		return false
	# 普攻主子弹：飞行距离达到 auto_bullet_range 后消失；split/bounce 仍按 life
	if not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)):
		var origin: Vector2 = Vector2(s.get("origin", s.get("pos", Vector2.ZERO)))
		var traveled: float = Vector2(s.get("pos", Vector2.ZERO)).distance_to(origin)
		var range_px: float = float(s.get("range_px", GameConfig.get_player_value("auto_bullet_range", 378)))
		return traveled >= range_px
	return float(s.life) <= 0.0


func try_abyss_explosion(player: BattlePlayer, path: Array) -> void:
	if path.size() < 5:
		return
	var loops := MathUtils.path_extract_all_closed_loops(path)
	if loops.is_empty():
		return
	var anim_life := EffectHelperScript.one_shot_anim_duration(_explosion_frames)
	if anim_life <= 0.0:
		anim_life = 0.55
	# Phase 6 sr=27 trail_loop_explode：v6 卡按 weapon_mult 爆炸
	var v6_explosions: Array = SpecialRuleDispatcher.on_loop_explode(player, self, loops)
	for ex in v6_explosions:
		var damage: int = player.get_ability_damage(float(ex.weapon_mult))
		var explosion2 := _with_upgrade_fx_layer({
			"kind": "abyss_explosion",
			"pos": ex.center,
			"radius": float(ex.radius),
			"life": anim_life,
			"max_life": anim_life,
			"anim_t": 0.0,
			"dmg_mul": 1.0,
			"damage": damage,
			"hit": {},
		}, "trail_loop_explode")
		explosion2["damage_applied"] = false
		abyss_explosions.append(explosion2)
		_skill_burst(ex.center, 8.0, 0.18, Color("#ff8030"), 20)


func _update_auto_bullets(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player.state != BattlePlayer.State.IDLE:
		return
	if player.bullet_count <= 0:
		return
	if monsters.is_empty():
		return
	var nearest = _find_nearest_monster(player.global_position, monsters)
	if nearest == null:
		return
	var range_px := float(GameConfig.get_player_value("auto_bullet_range", 378))
	if player.global_position.distance_to(nearest.global_position) > range_px:
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
	var range_px := float(GameConfig.get_player_value("auto_bullet_range", 378))
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"pos": spawn_pos,
		"origin": spawn_pos,
		"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)),
		"life": max_life,
		"max_life": max_life,
		"range_px": range_px,
		"damage": damage,
		"hit": {},
		"rot": ang,
		"anim_t": 0.0,
		"visual_scale": visual_scale,
		"is_spirit": is_spirit,
		"returning": false,
		"mirror_used": false,
	}, "spirit_bomb" if is_spirit else "multi_bullet"))
	_finalize_spawned_projectile(shurikens.back(), player)


# Phase 3 sr=14 bullet_split：从命中点向随机角度 spawn 短寿命小子弹（is_split=true 避免递归）
func spawn_split_bullet(player: BattlePlayer, origin: Vector2, ang: float, damage: int) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var max_life := float(GameConfig.get_player_value("auto_bullet_life", 0.9)) * 0.5
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"pos": origin,
		"origin": origin,
		"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)) * 0.85,
		"life": max_life,
		"max_life": max_life,
		"damage": damage,
		"hit": {},
		"rot": ang,
		"anim_t": 0.0,
		"visual_scale": 0.7,
		"is_spirit": false,
		"returning": false,
		"mirror_used": false,
		"is_split": true,
	}, "multi_bullet"))
	_finalize_spawned_projectile(shurikens.back(), player)


# Phase 3 sr=15 bullet_bounce：从命中怪向最近未链怪 spawn 子弹，递减 bounces_remaining
func spawn_bounce_bullet(player: BattlePlayer, from_monster, bounces_remaining: int, damage: int, falloff: float) -> void:
	if bounces_remaining <= 0 or battle == null or battle.spawner == null:
		return
	# 找最近未命中过的怪
	var best = null
	var best_d := 9e9
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or m == from_monster:
			continue
		if not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var d: float = from_monster.global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return
	var dir: Vector2 = (best.global_position - from_monster.global_position).normalized()
	var max_life := 0.7
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"pos": from_monster.global_position,
		"origin": from_monster.global_position,
		"vel": dir * 520.0,
		"life": max_life,
		"max_life": max_life,
		"damage": damage,
		"hit": {},
		"rot": dir.angle(),
		"anim_t": 0.0,
		"visual_scale": 0.7,
		"is_spirit": false,
		"returning": false,
		"mirror_used": false,
		"is_bounce": true,
		"bounce_remaining": bounces_remaining - 1,
		"bounce_falloff": falloff,
	}, "multi_bullet"))
	_finalize_spawned_projectile(shurikens.back(), player)


# Phase 5 sr=22 combo_shuriken：slash 末段 spawn 辅助子弹（line: 朝最近敌人；其它 shape 走随机方向）
func spawn_combo_shuriken(player: BattlePlayer, shape: String) -> void:
	if battle == null or battle.spawner == null:
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	if monsters.is_empty():
		return
	var ang: float = _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
	if shape == "random" or shape == "":
		ang = randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var spawn_pos := player.global_position + dir * (player.get_effective_radius() + GameConfig.scale_world(AUTO_BULLET_SPAWN_OFFSET))
	var dmg: int = player.get_auto_bullet_damage()
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"pos": spawn_pos,
		"origin": spawn_pos,
		"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)) * 0.9,
		"life": 0.8,
		"max_life": 0.8,
		"damage": dmg,
		"hit": {},
		"rot": ang,
		"anim_t": 0.0,
		"visual_scale": 0.9,
		"is_spirit": false,
		"returning": false,
		"mirror_used": false,
		"is_split": true,
	}, "shuriken"))
	_finalize_spawned_projectile(shurikens.back(), player)


# ============= Phase 6 v6 combo spawn helpers (sr=20) =============

# combo_black_hole：单点黑洞 — 强 pull + AOE
func spawn_v6_black_hole(player: BattlePlayer, pos: Vector2, level: int, weapon_mult: float) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	black_holes.append(_with_upgrade_fx_layer({
		"kind": "black_hole",
		"pos": pos,
		"radius": GameConfig.scale_world(64.0 + float(level) * 24.0) * FX_SCALE,
		"life": 2.0,
		"max_life": 2.0,
		"anim_t": 0.0,
		"pull": 260.0 + float(level) * 70.0,
		"dmg_timer": 0.0,
		"hit": {},
		"damage": dmg,
		"dmg_mul": 1.0,
	}, "black_hole"))
	_skill_burst(pos, 8.0, 0.2, Color("#9040d8"), 22)


# combo_fireball：line — N 颗火球横向喷出
func spawn_v6_fireballs(player: BattlePlayer, pos: Vector2, seg_ang: float, level: int, weapon_mult: float) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	var cnt: int = 3 + maxi(0, level - 1)
	for i in range(cnt):
		var a: float = seg_ang + MathUtils.rand_range(-0.9, 0.9)
		shurikens.append(_with_upgrade_fx_layer({
			"kind": "fireball",
			"pos": pos,
			"vel": Vector2(cos(a), sin(a)) * 280.0,
			"life": 0.95,
			"damage": dmg,
			"hit": {},
			"rot": a,
			"spin": 0.0,
			"dmg_mul": 1.0,
			"visual_scale": 1.5,
		}, "great_fireball"))
	_skill_burst(pos, 6.5, 0.16, Color("#ff7020"), 18)


# combo_water_tornado：line — N 个龙卷螺旋
func spawn_v6_water_tornado(player: BattlePlayer, pos: Vector2, seg_ang: float, level: int, weapon_mult: float) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	var cnt: int = 1 + maxi(0, level - 1)
	for i in range(cnt):
		var spread: float = 0.0 if cnt <= 1 else (float(i) - (cnt - 1) * 0.5) * 0.22
		var monsters: Array = battle.spawner.get_active_monsters() if battle and battle.spawner else []
		var ang: float = _nearest_monster_angle(pos, seg_ang, monsters) + spread
		water_tornados.append(_with_upgrade_fx_layer({
			"kind": "water_tornado",
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * 360.0,
			"life": 1.85,
			"max_life": 1.85,
			"anim_t": 0.0,
			"hit": {},
			"damage": dmg,
			"dmg_mul": 1.0,
		}, "water_tornado"))
	_skill_burst(pos, 5.5, 0.14, Color("#58d8ff"), 14)


# combo_blade_storm：circle — 转刀阵
func spawn_v6_blade_storm(player: BattlePlayer, pos: Vector2, level: int, weapon_mult: float, radius: float, extra_per_lv: int) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	# 单转刀阵 sized by radius；extra_per_lv 增加 blade 数（实际表现为同一 whirl 数）
	var blade_count: int = 1 + extra_per_lv * maxi(0, level - 1)
	for i in range(blade_count):
		var offset_ang: float = TAU * float(i) / float(maxi(1, blade_count))
		var spawn_pos: Vector2 = pos + Vector2(cos(offset_ang), sin(offset_ang)) * 20.0
		whirls.append(_with_upgrade_fx_layer({
			"kind": "whirl",
			"pos": spawn_pos,
			"radius": GameConfig.scale_world(radius) * FX_SCALE * 0.6,
			"max_radius": GameConfig.scale_world(radius) * FX_SCALE,
			"life": 1.0,
			"max_life": 1.0,
			"anim_t": 0.0,
			"hit": {},
			"damage": dmg,
			"dmg_mul": 1.0,
		}, "blade_whirl"))
	_skill_burst(pos, 6.0, 0.15, Color("#ffe060"), 16)


# combo_thunder：circle — 雷链 + AOE
func spawn_v6_thunder(player: BattlePlayer, pos: Vector2, level: int, weapon_mult: float, radius: float) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	# 直接 AOE，所有 radius 内怪都吃伤；走 info 路径（thunder element 可激活 chain）
	if battle == null or battle.spawner == null:
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if pos.distance_to(m.global_position) > radius + m.get_hitbox_radius():
			continue
		var info := player.make_ability_damage("combo_v6_thunder", weapon_mult, "combo", "thunder", false, false)
		info.raw_amount = dmg
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, pos)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color("#f8d020"))
			if battle.particles:
				battle.particles.lightning_effect(pos, m.global_position)
			if int(result.get("damage", 0)) > 0:
				ElementEffectManager.try_apply(m, info, player)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	_skill_burst(pos, 7.5, 0.17, Color("#a8e8ff"), 18)


# ============= Phase 6 v6 bullet proc helpers (sr=13 / sr=18) =============

# sr=13 bullet_fire_support：在命中位置 spawn 小爆炸
func spawn_v6_bullet_aoe(player: BattlePlayer, pos: Vector2, atk_mult: float, radius_px: float) -> void:
	if battle == null or battle.spawner == null:
		return
	var dmg: int = player.get_ability_damage(atk_mult)
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if pos.distance_to(m.global_position) > radius_px + m.get_hitbox_radius():
			continue
		var info := player.make_ability_damage("bullet_fire_support", atk_mult, "bullet", "fire", false, false)
		info.raw_amount = dmg
		info.applies_fire = true
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, pos)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color("#ff8040"))
			if int(result.get("damage", 0)) > 0:
				ElementEffectManager.try_apply(m, info, player)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	_skill_burst(pos, 4.0, 0.1, Color("#ff8040"), 10)


# sr=18 bullet_beam：spawn 一条 laser 短射线
func spawn_v6_bullet_beam(player: BattlePlayer, pos: Vector2, ang: float, atk_mult: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var exit_dist := _ray_playfield_exit_distance(pos, dir)
	var beam_length := exit_dist + GameConfig.scale_world(48.0) * FX_SCALE
	lasers.append(_with_upgrade_fx_layer({
		"kind": "laser",
		"tail": pos,
		"origin": pos,
		"dir": dir,
		"exit_dist": exit_dist,
		"beam_length": beam_length,
		"vel": dir * 1200.0,
		"damage": player.get_ability_damage(atk_mult),
		"hit": {},
		"rot": ang,
	}, "bullet_beam"))


# Phase 7 sr=37 orb_fire/ice/poison/thunder：拾取触发的元素 AOE
func spawn_v6_orb_elem_aoe(player: BattlePlayer, pos: Vector2, element: String, atk_mult: float, radius_px: float) -> void:
	if battle == null or battle.spawner == null:
		return
	var dmg: int = player.get_ability_damage(atk_mult)
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if pos.distance_to(m.global_position) > radius_px + m.get_hitbox_radius():
			continue
		var info := player.make_ability_damage("orb_elem_" + element, atk_mult, "trail", element, false, false)
		info.raw_amount = dmg
		match element:
			"fire":    info.applies_fire = true
			"ice":     info.applies_ice = true
			"thunder": info.applies_thunder = true
			"poison":  info.applies_poison = true
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, pos)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, _orb_elem_color(element))
			if int(result.get("damage", 0)) > 0:
				ElementEffectManager.try_apply(m, info, player)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	_skill_burst(pos, 5.0, 0.12, _orb_elem_color(element), 14)


func _orb_elem_color(element: String) -> Color:
	match element:
		"fire":    return Color(1.0, 0.55, 0.25, 1.0)
		"ice":     return Color(0.6, 0.85, 1.0, 1.0)
		"thunder": return Color(1.0, 0.95, 0.35, 1.0)
		"poison":  return Color(0.55, 0.95, 0.45, 1.0)
		_:         return Color(0.95, 0.95, 0.85, 1.0)


# ============= Phase 6 sr=26 trail_slash_wave：末段 spawn 推开 AOE =============
func spawn_v6_slash_wave(player: BattlePlayer, end_pos: Vector2, radius: float, weapon_mult: float) -> void:
	if battle == null or battle.spawner == null:
		return
	var dmg: int = player.get_ability_damage(weapon_mult)
	var push_force: float = 220.0
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var d: float = end_pos.distance_to(m.global_position)
		if d > radius + m.get_hitbox_radius():
			continue
		# 推开
		var to_m: Vector2 = m.global_position - end_pos
		if to_m.length_squared() > 1.0:
			m.global_position += to_m.normalized() * push_force * 0.08
		var info := player.make_ability_damage("trail_slash_wave", weapon_mult, "slash", "", false, false)
		info.raw_amount = dmg
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, end_pos)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color("#ffffff"))
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	_skill_burst(end_pos, 7.0, 0.18, Color("#e8e8ff"), 18)
	if battle:
		battle.shake_camera(2.2, 0.08)


# ============= Phase 6 sr=25 trail_elem_field：元素场域 =============

func spawn_v6_trail_field(player: BattlePlayer, points: Array, element: String, atk_mult: float, tick_interval: float, slow_pct: float, stun_sec: float, ramp_pct: float, duration: float, bullet_attach: bool, card_id: String) -> void:
	for p in points:
		v6_trail_fields.append({
			"pos": p,
			"radius": 32.0,
			"element": element,
			"atk_mult": atk_mult,
			"tick_interval": tick_interval,
			"slow_pct": slow_pct,
			"stun_sec": stun_sec,
			"ramp_pct": ramp_pct,
			"bullet_attach": bullet_attach,
			"life": duration,
			"max_life": duration,
			"tick_timer": 0.0,
			"ramp_stacks": {},
			"card_id": card_id,
		})


func _update_v6_trail_fields(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if v6_trail_fields.is_empty():
		return
	for i in range(v6_trail_fields.size() - 1, -1, -1):
		var f: Dictionary = v6_trail_fields[i]
		f.life = float(f.life) - delta
		if float(f.life) <= 0.0:
			v6_trail_fields.remove_at(i)
			continue
		f.tick_timer = float(f.tick_timer) - delta
		if float(f.tick_timer) <= 0.0:
			f.tick_timer = float(f.tick_interval)
			_trail_field_tick(f, player, monsters)
		v6_trail_fields[i] = f


func _trail_field_tick(f: Dictionary, player: BattlePlayer, monsters: Array) -> void:
	var element: String = str(f.element)
	var atk_mult: float = float(f.atk_mult)
	var radius: float = float(f.radius)
	var slow_pct: float = float(f.slow_pct)
	var stun_sec: float = float(f.stun_sec)
	var ramp_pct: float = float(f.ramp_pct)
	var ramp_stacks: Dictionary = f.ramp_stacks
	var pos: Vector2 = f.pos
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		if pos.distance_to(m.global_position) > radius + m.get_hitbox_radius():
			continue
		var key := str(m.get_instance_id())
		# ramp 计 tick 数
		var stacks: int = int(ramp_stacks.get(key, 0)) + 1
		ramp_stacks[key] = stacks
		var ramp_total: float = ramp_pct * float(stacks - 1)
		var effective_mult: float = atk_mult * (1.0 + ramp_total)
		var dmg: int = player.get_ability_damage(effective_mult)
		var info := player.make_ability_damage("trail_field_" + element, effective_mult, "trail", element, false, true)
		info.raw_amount = dmg
		# 元素自带状态由 element_effect_manager 接管；这里只在 sv 有 override 时额外注入
		var apply_fire := element == "fire"
		var apply_ice := element == "ice"
		var apply_thunder := element == "thunder"
		var apply_poison := element == "poison"
		info.applies_fire = apply_fire
		info.applies_ice = apply_ice
		info.applies_thunder = apply_thunder
		info.applies_poison = apply_poison
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, pos)
		if not result.is_empty() and int(result.get("damage", 0)) > 0:
			ElementEffectManager.try_apply(m, info, player)
			# 额外 slow override（trail_frost 0.4 取代 ice 默认 0.3）
			if slow_pct > 0.0 and m.has_method("apply_freeze_slow"):
				m.apply_freeze_slow(player.base_attack, 0.0, slow_pct)
			# stun（trail_thunder_field 0.3s）
			if stun_sec > 0.0 and m.has_method("apply_paralyze"):
				m.apply_paralyze(stun_sec)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	f.ramp_stacks = ramp_stacks


func draw_v6_trail_fields(canvas: Node2D, below_monsters: bool) -> void:
	if v6_trail_fields.is_empty():
		return
	# 场域绘制在怪物之下
	if not below_monsters:
		return
	var offset := -canvas.global_position
	for f in v6_trail_fields:
		var life_t: float = clampf(float(f.life) / maxf(0.001, float(f.max_life)), 0.0, 1.0)
		var alpha: float = 0.45 * life_t
		var col: Color = _trail_field_color(str(f.element), alpha)
		var pos: Vector2 = Vector2(f.pos) + offset
		canvas.draw_circle(pos, float(f.radius), col)
		# 元素特征轮廓
		canvas.draw_arc(pos, float(f.radius), 0.0, TAU, 32, Color(col.r, col.g, col.b, alpha * 1.4), 1.6)


func _trail_field_color(element: String, alpha: float) -> Color:
	match element:
		"fire":    return Color(1.0, 0.45, 0.15, alpha)
		"ice":     return Color(0.5, 0.85, 1.0, alpha)
		"thunder": return Color(1.0, 0.95, 0.35, alpha)
		"poison":  return Color(0.45, 0.95, 0.4, alpha)
		_:         return Color(0.9, 0.9, 0.9, alpha)


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
	# Phase 5 sr=16 bullet_mirror：命中后回弹（mult>0 启用；split/bounce 不参与）
	if not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)) and float(player.bullet_mirror_mult) > 0.0 and not bool(s.get("mirror_used", false)):
		s["damage"] = int(max(1, round(float(s.get("damage", 1)) * float(player.bullet_mirror_mult))))
		_start_mirror_return(s, player)
		return false
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
	# Phase 3 sr=11 bullet_distance_scale：按飞行距离加成（只对 auto/laser/spirit 类）
	if kind == "auto" or kind == "laser":
		dmg = SpecialRuleDispatcher.transform_bullet_damage(player, s, dmg)
	# crit roll 移到 resolver；emitter 端不再预乘暴击倍率
	# 构造 DamageInfo：按 projectile kind 映射到 v6 dmg_layer/element
	var info := _build_projectile_damage_info(kind, dmg, false, player)
	var result: Dictionary = {}
	if m.has_method("take_damage_info"):
		result = m.take_damage_info(info, pos)
	elif m.has_method("take_damage"):
		result = m.take_damage(dmg, pos)
	if not result.is_empty():
		var hit_is_crit := bool(result.get("is_crit", false))
		if battle and battle.combat:
			battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), hit_is_crit)
		# Sheet4 元素状态注入（仅当伤害实际生效）
		if int(result.get("damage", 0)) > 0:
			ElementEffectManager.try_apply(m, info, player)
		# Phase 3 sr=14/15 bullet_split / bounce
		if kind == "auto" and int(result.get("damage", 0)) > 0:
			SpecialRuleDispatcher.on_bullet_hit(player, self, s, m, info, int(result.get("damage", 0)))
		# Phase 6 sr=13 / sr=18 bullet proc spell / beam
		if kind == "auto" and int(result.get("damage", 0)) > 0:
			SpecialRuleDispatcher.on_bullet_proc(player, self, m.global_position, float(s.get("rot", 0.0)))
		if kind == "auto":
			var fx_scale := float(s.get("visual_scale", 1.0))
			_spawn_auto_hit_fx(m, fx_scale)
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(m)
	return true


# 按 projectile kind 映射到 v6 dmg_layer/element。覆盖 ability_manager 已知的 8 种 kind。
# 未识别的 kind 默认归到 physical (无元素)，保证迁移过程不漏。
func _build_projectile_damage_info(kind: String, dmg: int, is_crit: bool, player: BattlePlayer) -> DamageInfo:
	var category := "physical"
	var element := ""
	var source := "projectile_" + kind
	match kind:
		"auto":
			category = "bullet"
			source = "bullet_auto"
		"laser":
			category = "bullet"
			source = "bullet_laser"
		"abyss_explosion":
			category = "combo"
			source = "combo_abyss"
		"whirl":
			category = "combo"
			source = "combo_whirl"
		"black_hole":
			category = "combo"
			source = "combo_blackhole"
		"water_tornado":
			category = "combo"
			element = "ice"
			source = "combo_tornado"
		"fireball":
			category = "combo"
			element = "fire"
			source = "combo_fireball"
		"skill":
			category = "combo"
			source = "combo_skill"
	var info := player.make_damage(source, 1.0, category, element, true, false)
	info.raw_amount = dmg
	info.is_crit_resolved = is_crit
	return info


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
				# Phase 5 sr=12 bullet_homing：每帧调整 velocity 朝最近怪
				elif player != null and player.bullet_homing_enabled and not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)):
					var new_vel: Vector2 = SpecialRuleDispatcher.apply_bullet_homing(player, s, monsters, delta)
					if new_vel.length_squared() > 4.0:
						s["vel"] = new_vel
						s["rot"] = new_vel.angle()
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
	var life_t: float
	if not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)) and not bool(s.get("returning", false)):
		# 普攻主子弹：按飞行距离剩余比例计算视觉淡出
		var origin: Vector2 = Vector2(s.get("origin", s.get("pos", Vector2.ZERO)))
		var traveled: float = Vector2(s.get("pos", Vector2.ZERO)).distance_to(origin)
		var range_px: float = float(s.get("range_px", GameConfig.get_player_value("auto_bullet_range", 378)))
		life_t = clampf(1.0 - traveled / maxf(0.001, range_px), 0.0, 1.0)
	else:
		var max_life := float(s.get("max_life", GameConfig.get_player_value("auto_bullet_life", 0.9)))
		life_t = clampf(float(s.life) / maxf(0.001, max_life), 0.0, 1.0)
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
	# Phase 6 sr=25 trail_elem_field：地面场域（仅 below_monsters）
	draw_v6_trail_fields(canvas, below_monsters)
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
