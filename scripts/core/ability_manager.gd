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
var v6_demon_scythes: Array = []  # sr=46 死神镰刀实例（弯月像素体 + 渐进展开 + 拖尾光带）
var abyss_explosions: Array = []
var hit_fx: Array = []
var water_tornados: Array = []
var black_holes: Array = []
var whirls: Array = []
# sr=26 trail_slash_wave 斩击余波：地面扩散冲击环（ease_out_cubic 扩散 + 渐隐）
var v6_slash_waves: Array = []   # {pos, radius, life, max_life, color}
# sr=13 视觉实体：火力支援像素爆炸 / 圣光柱（与 _skill_burst 微粒子分开管理）
var bomb_explosions: Array = []   # {pos, radius_px, life, max_life}
var holy_pillars: Array = []      # {pos, life, max_life, fall_t}
# sr=13 手榴弹弹道（抛物线投掷 → 落地引爆 bomb_explosion）。与直接的 bomb_explosions 区分：
# bomb_explosions 是命中/落地后的视觉烟花；grenade_arcs 是飞行中的弹道。
var grenade_arcs: Array = []      # {start, end, t, total_t, peak, atk_mult, radius_px, style, rot_spin}
# Phase 6 sr=25 trail_elem_field：场域格列表
var v6_trail_fields: Array = []
var auto_bullet_cooldown := 0.0
var black_hole_spawned_this_resolve := false
var combo_fireball_milestone := 0
var _auto_bullet_release_connected := false
# sr=55 炸弹人：延时炸弹（fuse 倒计时到 0 → 十字爆炸）
var pending_bombs: Array = []     # {pos, fuse, max_fuse, atk_mult, arm_px, applied}
# sr=55 视觉：十字爆炸淡出实体（爆炸时才 spawn，独立于 bomb_explosions）
var cross_explosions: Array = []  # {pos, arm_px, life, max_life}
# sr=54 近身战：一次性挥砍视觉实体
var melee_swipes: Array = []      # {pos, dir, range_px, life, max_life}


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
	var draw_r := 110.0 * FX_SCALE * GameConfig.get_world_scale()
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
	v6_demon_scythes.clear()
	abyss_explosions.clear()
	hit_fx.clear()
	water_tornados.clear()
	black_holes.clear()
	whirls.clear()
	bomb_explosions.clear()
	holy_pillars.clear()
	grenade_arcs.clear()
	v6_trail_fields.clear()
	v6_slash_waves.clear()
	pending_bombs.clear()
	cross_explosions.clear()
	melee_swipes.clear()
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
	return not shurikens.is_empty() or not lasers.is_empty() or not v6_demon_scythes.is_empty() or not abyss_explosions.is_empty() or not hit_fx.is_empty() or not water_tornados.is_empty() or not black_holes.is_empty() or not whirls.is_empty() or not bomb_explosions.is_empty() or not holy_pillars.is_empty() or not grenade_arcs.is_empty() or not pending_bombs.is_empty() or not cross_explosions.is_empty() or not melee_swipes.is_empty() or not v6_slash_waves.is_empty()


func update(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player == null:
		return
	# 子弹时间期间暂停普攻子弹/激光等自动攻击逻辑（与怪物 AI、天雷一致）
	if delta <= 0.0 or player.state == BattlePlayer.State.BULLET_TIME:
		return
	_update_auto_bullets(delta, player, monsters)
	_update_shurikens(delta, player, monsters)
	_update_lasers(delta, player, monsters)
	_update_v6_demon_scythes(delta, player, monsters)
	_update_abyss_explosions(delta, player, monsters)
	_update_hit_fx(delta)
	_update_water_tornados(delta, player, monsters)
	_update_black_holes(delta, player, monsters)
	_update_whirls(delta, player, monsters)
	_update_bomb_explosions(delta)
	_update_pending_bombs(delta, player, monsters)
	_update_cross_explosions(delta)
	_update_melee_swipes(delta)
	_update_slash_waves(delta)
	_update_holy_pillars(delta)
	_update_grenade_arcs(delta, player)
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


# 玩家→怪物的普攻弹道是否被"阻挡石/深坑/未解锁锁定块/箭块"挡住。
# 沿线按 10px 步长采样，任一采样点命中 is_bullet_blocked_at 即视为挡住
# （与子弹飞行中的撞墙消失判定同一来源 → "打不到就不发" 与 "飞行撞墙消失" 一致）。
# 树不算阻挡（placed_tree：树只挡移动，不挡子弹/画线）。
# 起点跳过玩家半径、终点跳过怪物命中半径，避免贴身/贴怪误判。
func _has_bullet_line_of_sight(from: Vector2, to: Vector2, from_radius: float, to_radius: float) -> bool:
	if battle == null or not battle.has_method("is_bullet_blocked_at"):
		return true
	var diff: Vector2 = to - from
	var dist: float = diff.length()
	if dist <= from_radius + to_radius:
		return true
	var dir: Vector2 = diff / dist
	var seg_len: float = dist - from_radius - to_radius
	const STEP: float = 10.0
	var t: float = 0.0
	while t <= seg_len:
		if battle.is_bullet_blocked_at(from + dir * (from_radius + t)):
			return false
		t += STEP
	# 终点（怪物边缘）补采一次，防步长跳过最后一格
	return not battle.is_bullet_blocked_at(from + dir * (from_radius + seg_len))


# 最近且视线无阻挡的怪物；没有则返回 null（用于"打不到就不开火"门控）。
# 距离比当前最近更远的怪直接跳过，不做（较贵的）视线采样。
func _find_nearest_monster_with_los(from_pos: Vector2, monsters: Array, from_radius: float):
	var nearest = null
	var nearest_dist := INF
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var d := from_pos.distance_to(m.global_position)
		if d >= nearest_dist:
			continue
		var hit_r: float = 16.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if not _has_bullet_line_of_sight(from_pos, m.global_position, from_radius, hit_r):
			continue
		nearest_dist = d
		nearest = m
	return nearest


# 返回 from_pos 视线无阻挡的怪物列表（保留原顺序），供"只朝打得到的怪发射"使用。
func _filter_monsters_with_los(from_pos: Vector2, monsters: Array, from_radius: float) -> Array:
	var out: Array = []
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var hit_r: float = 16.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if _has_bullet_line_of_sight(from_pos, m.global_position, from_radius, hit_r):
			out.append(m)
	return out


func fire_auto_bullets(player: BattlePlayer, monsters: Array) -> void:
	_spawn_auto_bullet_volley(player, monsters)


func _spawn_auto_bullet_volley(player: BattlePlayer, monsters: Array) -> void:
	if player == null or monsters.is_empty():
		return
	# sr=53 laser_cannon_basic：普攻改激光。子弹数量 = 激光条数，扇射同 bullet 逻辑
	if bool(player.laser_cannon_active):
		var laser_base_ang := _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
		var laser_count := maxi(1, player.bullet_count)
		var mult := float(player.laser_cannon_atk_mult)
		var pierce := bool(player.laser_cannon_pierce)
		var color_key := String(player.laser_cannon_color_key)
		for i in range(laser_count):
			var lang := laser_base_ang
			if laser_count > 1:
				lang = laser_base_ang + (float(i) - (laser_count - 1) * 0.5) * AUTO_BULLET_FAN_SPREAD
			spawn_v6_player_laser(player, monsters, mult, pierce, color_key, lang)
		# sr=17 bullet_side：斜射额外角度也走激光
		var laser_side_angles: Array = SpecialRuleDispatcher.collect_extra_bullet_angles(player, laser_base_ang)
		for ang2 in laser_side_angles:
			spawn_v6_player_laser(player, monsters, mult, pierce, color_key, float(ang2))
		return
	# sr=54 melee_basic：普攻改近战挥砍（子弹数锁 1，射程=melee_range_px，攻击 +atk_bonus%）
	if bool(player.melee_basic_active):
		_fire_melee_swipe(player, monsters)
		return
	# 普通子弹：只朝视线无阻挡的怪发射 — 没有打得到的目标就不发子弹
	var from_pos := player.global_position
	var los_monsters := _filter_monsters_with_los(from_pos, monsters, player.get_effective_radius())
	if los_monsters.is_empty():
		return
	var base_ang := _nearest_monster_angle(from_pos, -PI * 0.5, los_monsters)
	var dmg := player.get_auto_bullet_damage()
	var count := maxi(1, player.bullet_count)
	# sr=11 bullet_spirit_bomb：装备此卡时把所有普攻子弹切换到元气弹视觉（蓝白能量球）
	# 不依赖 player 字段，直接看 upgrade_stacks（sr=11 没有持久化的 player buff 字段）
	var is_spirit: bool = int(player.upgrade_stacks.get("bullet_spirit_bomb", 0)) > 0
	for i in range(count):
		var ang := base_ang
		if count > 1:
			ang = base_ang + (float(i) - (count - 1) * 0.5) * AUTO_BULLET_FAN_SPREAD
		_spawn_bullet_from_angle(player, ang, dmg, is_spirit, 1.0)
	# Phase 3 sr=17 bullet_side：dispatcher 返回斜射额外角度
	var extra_angles: Array = SpecialRuleDispatcher.collect_extra_bullet_angles(player, base_ang)
	for ang2 in extra_angles:
		_spawn_bullet_from_angle(player, float(ang2), dmg, is_spirit, 1.0)


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
	# 普攻主子弹：飞行距离达到 auto_bullet_range 或 life 到时消失
	# 注意：必须 life 兜底 — homing 子弹会绕怪拐弯，pos→origin 直线距离可能永远 < range_px
	# 没 life 兜底的话拐弯子弹会卡在屏幕上无限绕圈，再没怪打就再也不死。
	if not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)):
		var origin: Vector2 = Vector2(s.get("origin", s.get("pos", Vector2.ZERO)))
		var traveled: float = Vector2(s.get("pos", Vector2.ZERO)).distance_to(origin)
		var range_px: float = float(s.get("range_px", GameConfig.get_player_value("auto_bullet_range", 378)))
		return traveled >= range_px or float(s.life) <= 0.0
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
		_skill_burst(ex.center, 3.0, 0.08, Color("#ff8030"), 20)


func _update_auto_bullets(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player.state != BattlePlayer.State.IDLE:
		return
	if player.bullet_count <= 0:
		return
	if monsters.is_empty():
		return
	var from_pos := player.global_position
	# 普通子弹要求"打得到才开火"：最近怪若被阻挡石/深坑挡住视线 → 不开火（避免隔着墙空射）。
	# 激光炮(sr=53)贯通墙、近战(sr=54)短程挥砍 → 不做视线门控。
	var require_los := not bool(player.laser_cannon_active) and not bool(player.melee_basic_active)
	var nearest = null
	if require_los:
		nearest = _find_nearest_monster_with_los(from_pos, monsters, player.get_effective_radius())
	else:
		nearest = _find_nearest_monster(from_pos, monsters)
	if nearest == null:
		return
	var range_px := player.get_effective_auto_bullet_range()
	if from_pos.distance_to(nearest.global_position) > range_px:
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
	var range_px := player.get_effective_auto_bullet_range()
	# sr=49 血飞刀：射程 ×range_mult；穿透由 _apply_projectile_hit 末段判定（行为永远生效，不受视觉互斥影响）
	var blood_blade: bool = bool(player.blood_blade_pierce)
	if blood_blade:
		range_px *= float(player.blood_blade_range_mult)
		max_life *= float(player.blood_blade_range_mult)
	# 视觉互斥：玩家可能同时装备元气弹 + 血飞刀。按 player.get_active_bullet_visual_kind() 决出胜者（后获得者覆盖之前）
	# 调用方传进的 is_spirit 只表示"元气弹卡当前是否装备"；真正画哪张交给 visual_kind 字段决定
	var visual_kind: String = player.get_active_bullet_visual_kind() if player.has_method("get_active_bullet_visual_kind") else ("spirit" if is_spirit else ("blood_blade" if blood_blade else ""))
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		# is_basic_attack：标记「这是玩家普攻的一次命中实例」，与 kind（底层渲染/伤害分类）正交。
		# 1471/1496/1498 等普攻 proc 管线按此 flag 门控，而非 kind=="auto"——
		# 这样激光炮/血飞刀/近身战及未来任何「替换普攻形态」的卡只要打上此 flag，
		# 自动吃 sr=11 距离加成 / sr=13/18 命中 proc / 受击特效，无需在门控处 or 新 kind。
		"is_basic_attack": true,
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
		"is_blood_blade": blood_blade,
		"visual_kind": visual_kind,
	}, "spirit_bomb" if visual_kind == "spirit" else ("blood_blade" if visual_kind == "blood_blade" else "multi_bullet")))
	_finalize_spawned_projectile(shurikens.back(), player)


# Phase 3 sr=14 bullet_split：从命中怪向随机角度 spawn 短寿命小子弹（is_split=true 避免递归）
# 关键：预置源怪 id 进 hit 字典 → 子子弹跳过源怪。否则子子弹出生在源怪身上，
# _update_shurikens 先碰撞后移动，下一帧立即命中源怪被秒删，根本飞不出去（「命中了没分裂」根因）。
func spawn_split_bullet(player: BattlePlayer, origin_monster, ang: float, damage: int) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var origin_pos: Vector2 = Vector2.ZERO
	var hit_seed: Dictionary = {}
	if origin_monster != null and is_instance_valid(origin_monster):
		origin_pos = origin_monster.global_position
		hit_seed[str(origin_monster.get_instance_id())] = true   # 跳过源怪，避免出生即命中被秒删
		# 从源怪边缘外推出生，避免贴在怪身上
		var hit_r := 16.0
		if origin_monster.has_method("get_hitbox_radius"):
			hit_r = origin_monster.get_hitbox_radius()
		origin_pos = origin_pos + dir * (hit_r + 4.0)
	var max_life := float(GameConfig.get_player_value("auto_bullet_life", 0.9)) * 0.5
	# 继承玩家当前普攻视觉（元气弹 / 血飞刀 / 普通），分裂子弹外观与源子弹一致
	var visual_kind: String = player.get_active_bullet_visual_kind() if player.has_method("get_active_bullet_visual_kind") else ""
	var is_spirit: bool = visual_kind == "spirit"
	var is_blood_blade: bool = visual_kind == "blood_blade"
	var upgrade_id: String = "spirit_bomb" if visual_kind == "spirit" else ("blood_blade" if visual_kind == "blood_blade" else "multi_bullet")
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"is_basic_attack": true,   # 分裂子弹仍是普攻实例 → 保留 sr=13/18 proc（与历史行为一致）
		"pos": origin_pos,
		"origin": origin_pos,
		"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)) * 0.85,
		"life": max_life,
		"max_life": max_life,
		"damage": damage,
		"hit": hit_seed,   # 预置源怪 id → 跳过源怪，子子弹才能飞出去
		"rot": ang,
		"anim_t": 0.0,
		"visual_scale": 0.7,
		"is_spirit": is_spirit,
		"is_blood_blade": is_blood_blade,
		"visual_kind": visual_kind,
		"returning": false,
		"mirror_used": false,
		"is_split": true,
	}, upgrade_id))
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
	# 预置源怪 id → 弹射子弹跳过源怪。否则出生在源怪身上，_update_shurikens 先碰撞后移动，
	# 下一帧立即命中源怪 → is_bounce 分支递归 spawn → 在源怪身上反复弹射直到 remaining=0，根本飞不到 best。
	var hit_seed: Dictionary = {}
	if is_instance_valid(from_monster):
		hit_seed[str(from_monster.get_instance_id())] = true
	var origin_pos: Vector2 = from_monster.global_position + dir * 20.0   # 边缘外推，避免贴源怪
	var max_life := 1.4                        # 拉长弹射寿命（原 0.7）
	# 继承玩家当前普攻视觉（元气弹 / 血飞刀 / 普通），弹射子弹外观与源子弹一致
	var visual_kind: String = player.get_active_bullet_visual_kind() if player.has_method("get_active_bullet_visual_kind") else ""
	var is_spirit: bool = visual_kind == "spirit"
	var is_blood_blade: bool = visual_kind == "blood_blade"
	var upgrade_id: String = "spirit_bomb" if visual_kind == "spirit" else ("blood_blade" if visual_kind == "blood_blade" else "multi_bullet")
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "auto",
		"is_basic_attack": true,   # 弹射子弹仍是普攻实例 → 保留 sr=13/18 proc（与历史行为一致）
		"pos": origin_pos,
		"origin": origin_pos,
		"vel": dir * 700.0,                    # 拉长弹射速度（原 520）→ 最大飞行距离 ~980px（覆盖大半屏）
		"life": max_life,
		"max_life": max_life,
		"damage": damage,
		"hit": hit_seed,   # 预置源怪 id → 跳过源怪，弹射子弹才能飞向 best
		"rot": dir.angle(),
		"anim_t": 0.0,
		"visual_scale": 0.7,
		"is_spirit": is_spirit,
		"is_blood_blade": is_blood_blade,
		"visual_kind": visual_kind,
		"returning": false,
		"mirror_used": false,
		"is_bounce": true,
		"bounce_remaining": bounces_remaining - 1,
		"bounce_falloff": falloff,
	}, upgrade_id))
	_finalize_spawned_projectile(shurikens.back(), player)


# Phase 5 sr=22 combo_shuriken：slash 末段 spawn 辅助子弹（line: 朝最近敌人；其它 shape 走随机方向）
# 数量 = 2/级（desc「+2 枚手里剑/级」）；伤害 = auto_bullet × weapon_mult（desc「0.6×ATK」）；
# 方向优先用 slash 末端方向 end_ang 扇射（desc「向斩击末端方向」），无 end_ang 则朝最近怪。
func spawn_combo_shuriken(player: BattlePlayer, shape: String, level: int = 1, weapon_mult: float = 0.6, end_ang: float = INF) -> void:
	if battle == null or battle.spawner == null:
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	if monsters.is_empty():
		return
	# 基准方向：优先 slash 末端方向；random/空 shape 或无 end_ang 走最近怪 / 随机
	var base_ang: float = end_ang
	if base_ang == INF or shape == "random" or shape == "":
		base_ang = _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
		if shape == "random" or shape == "":
			base_ang = randf() * TAU
	var count: int = maxi(1, 2 * maxi(1, level))
	var dmg: int = maxi(1, int(round(player.get_auto_bullet_damage() * weapon_mult)))
	const SHURIKEN_FAN_SPREAD := 0.18   # 扇射间隔（弧度）
	for i in range(count):
		var fang: float = base_ang + (float(i) - (count - 1) * 0.5) * SHURIKEN_FAN_SPREAD
		var dir := Vector2(cos(fang), sin(fang))
		var spawn_pos := player.global_position + dir * (player.get_effective_radius() + GameConfig.scale_world(AUTO_BULLET_SPAWN_OFFSET))
		shurikens.append(_with_upgrade_fx_layer({
			"kind": "auto",
			"is_basic_attack": true,   # combo 衍生子弹：保留历史 sr=13/18/11 触发（kind=auto 一直在吃）
			"visual_kind": "shuriken",   # 走 _draw_pixel_shuriken 手里剑像素 art，不再画成普通白剑气
			"pos": spawn_pos,
			"origin": spawn_pos,
			"vel": dir * float(GameConfig.get_player_value("auto_bullet_speed", 420)) * 0.9,
			"life": 0.8,
			"max_life": 0.8,
			"damage": dmg,
			"hit": {},
			"rot": fang,
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
	# 玩家反馈：黑洞屏震过重 → 调成最轻微（粒子保留，仅 shake_mag/dur 降到最低档）
	_skill_burst(pos, 1.0, 0.05, Color("#9040d8"), 22)


# combo_fireball：line — 1 颗大火球贯穿飞出屏
func spawn_v6_fireballs(player: BattlePlayer, pos: Vector2, seg_ang: float, level: int, weapon_mult: float) -> void:
	var dmg: int = player.get_ability_damage(weapon_mult)
	# 从玩家外缘沿 seg_ang 方向喷出，避免生在被击怪身上被 _try_projectile_collision 秒杀
	var dir := Vector2(cos(seg_ang), sin(seg_ang))
	var muzzle_offset: float = player.get_effective_radius() + GameConfig.scale_world(10.0)
	var spawn_pos: Vector2 = player.global_position + dir * muzzle_offset
	shurikens.append(_with_upgrade_fx_layer({
		"kind": "fireball",
		"pos": spawn_pos,
		"vel": dir * 700.0,          # 高速前冲，飞出屏由 out_of_bounds 自然移除
		"life": 3.0,                 # 兜底寿命，避免异常情况下永久存在
		"damage": dmg,
		"hit": {},                   # _apply_projectile_hit 按 monster id 去重，贯穿天然只打一次
		"rot": seg_ang,
		"spin": 0.0,
		"dmg_mul": 1.0,
		"visual_scale": 1.9,         # 大火球（配合 _draw_pixel_fireball scale 参数）
		"pierce": true,              # 贯穿：_try_projectile_collision 命中后不消失
	}, "great_fireball"))
	_skill_burst(spawn_pos, 3.0, 0.08, Color("#ff7020"), 18)


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
			"radius": 100.0 * FX_SCALE * GameConfig.get_world_scale(),
		}, "water_tornado"))
	_skill_burst(pos, 3.0, 0.08, Color("#58d8ff"), 14)


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
	_skill_burst(pos, 3.0, 0.08, Color("#ffe060"), 16)


# sr=39 sword_rage 旋风弹道：从剑当前位置朝命中怪方向直线飞行，途中持续 AOE 命中。
# 与 spawn_v6_blade_storm 的差别 — 那个 vel=0 原地转刀阵；这个 vel ≠ 0 是飞行旋风。
func spawn_v6_sword_whirlwind(player: BattlePlayer, spawn_pos: Vector2, dir: Vector2, atk_mult: float, radius_px: float) -> void:
	var dmg: int = player.get_ability_damage(atk_mult)
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var travel_life: float = 1.2
	whirls.append(_with_upgrade_fx_layer({
		"kind": "whirl",
		"pos": spawn_pos,
		"vel": d * 260.0,
		"radius": GameConfig.scale_world(radius_px) * FX_SCALE * 0.55,
		"max_radius": GameConfig.scale_world(radius_px) * FX_SCALE * 0.95,
		"life": travel_life,
		"max_life": travel_life,
		"anim_t": 0.0,
		"hit": {},
		"damage": dmg,
		"dmg_mul": 1.0,
	}, "sword_rage"))
	_skill_burst(spawn_pos, 3.0, 0.08, Color("#e0d0a0"), 10)


# sr=13 bullet_fire_support 手榴弹弹道：从玩家投出抛物线落到命中点，落地引爆 bomb_explosion。
# style="holy" 不走弧线（圣光柱本来就是天降）；只有 "bomb" 走 grenade_arc 流程。
func spawn_v6_grenade_arc(player: BattlePlayer, start_pos: Vector2, end_pos: Vector2, atk_mult: float, radius_px: float, style: String = "bomb") -> void:
	if style != "bomb":
		spawn_v6_bullet_aoe(player, end_pos, atk_mult, radius_px, style)
		return
	var dist: float = start_pos.distance_to(end_pos)
	var total_t: float = clampf(0.30 + dist * 0.0008, 0.32, 0.65)
	var peak: float = clampf(dist * 0.32, 48.0, 140.0)
	grenade_arcs.append({
		"start": start_pos,
		"end": end_pos,
		"t": 0.0,
		"total_t": total_t,
		"peak": peak,
		"atk_mult": atk_mult,
		"radius_px": radius_px,
		"style": style,
		"rot_spin": randf_range(-10.0, 10.0),
	})


func _update_grenade_arcs(delta: float, player: BattlePlayer) -> void:
	if player == null:
		return
	var i := grenade_arcs.size() - 1
	while i >= 0:
		var g: Dictionary = grenade_arcs[i]
		g["t"] = float(g.t) + delta
		if float(g.t) >= float(g.total_t):
			# 着地 → 复用现有 bomb_explosion 视觉 + AOE 伤害；手榴弹屏震调成最轻微
			spawn_v6_bullet_aoe(player, Vector2(g.end), float(g.atk_mult), float(g.radius_px), str(g.style), true)
			grenade_arcs.remove_at(i)
		else:
			grenade_arcs[i] = g
		i -= 1


func _grenade_arc_position(g: Dictionary) -> Vector2:
	var t_norm: float = clampf(float(g.t) / float(g.total_t), 0.0, 1.0)
	var linear_pos: Vector2 = Vector2(g.start).lerp(Vector2(g.end), t_norm)
	var y_off: float = -float(g.peak) * sin(PI * t_norm)
	return linear_pos + Vector2(0.0, y_off)


# 手榴弹像素图：dark gray 圆体 + 顶部黑色短引信 + 闪烁火星。约 3x3 块 × 2.5px = 7.5px 球径。
func _draw_pixel_grenade(canvas: Node2D, local_pos: Vector2, rot: float, _g: Dictionary) -> void:
	var px := 2.5
	canvas.draw_set_transform(local_pos, rot, Vector2.ONE)
	var body_grid := [
		[0, 1, 1, 0],
		[1, 2, 2, 1],
		[1, 2, 3, 1],
		[0, 1, 1, 0],
	]
	var palette := {
		1: Color("#2a2828"),
		2: Color("#48433f"),
		3: Color("#7a6f60"),
	}
	for ry in range(body_grid.size()):
		var row: Array = body_grid[ry]
		for cx in range(row.size()):
			var layer: int = int(row[cx])
			if layer == 0:
				continue
			var col: Color = palette.get(layer, Color.BLACK)
			var x: float = (float(cx) - 1.5) * px
			var y: float = (float(ry) - 1.5) * px
			canvas.draw_rect(Rect2(x, y, px, px), col)
	# 引信柄
	canvas.draw_rect(Rect2(-px * 0.5, -2.5 * px, px, px), Color("#1a1410"))
	# 火星（每 60ms 闪烁，黄→橙）
	var spark_flicker: bool = int(Time.get_ticks_msec() / 60) % 2 == 0
	var spark_col: Color = Color("#fff080") if spark_flicker else Color("#ff8830")
	canvas.draw_rect(Rect2(-px * 0.5, -3.5 * px, px, px), spark_col)
	# 闪烁外光晕
	var glow_alpha: float = 0.22 if spark_flicker else 0.32
	canvas.draw_circle(Vector2(0.0, -3.0 * px), px * 1.4, Color(1.0, 0.7, 0.25, glow_alpha))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_grenade_arcs(canvas: Node2D, below_monsters: bool) -> void:
	if below_monsters:
		return
	var offset: Vector2 = -canvas.global_position
	for g in grenade_arcs:
		var t_norm: float = clampf(float(g.t) / float(g.total_t), 0.0, 1.0)
		# 地面阴影：沿 start → end 直线，随飞行靠近 end 缩小 / 变暗
		var ground_pos: Vector2 = Vector2(g.start).lerp(Vector2(g.end), t_norm)
		var shadow_local: Vector2 = ground_pos + offset
		var shadow_r: float = 4.5 * (1.0 - 0.35 * sin(PI * t_norm))  # 飞到高点时阴影最小
		canvas.draw_circle(shadow_local, shadow_r, Color(0.0, 0.0, 0.0, 0.28))
		# 弹体
		var pos: Vector2 = _grenade_arc_position(g) + offset
		var rot: float = float(g.t) * float(g.rot_spin)
		_draw_pixel_grenade(canvas, pos, rot, g)


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
	_skill_burst(pos, 3.0, 0.08, Color("#a8e8ff"), 18)


# ============= Phase 6 v6 bullet proc helpers (sr=13 / sr=18) =============

# sr=13 bullet_fire_support / angel_holy_bullet：在命中位置 spawn 小爆炸（火力支援）或天降光柱（圣光子弹）
# style="bomb" → 橙色像素爆炸圆环；style="holy" → 蓝白雷电像素光柱
# light_shake=true 时把屏震调成最轻微（仅手榴弹落地走此分支，避免震屏过重）。
func spawn_v6_bullet_aoe(player: BattlePlayer, pos: Vector2, atk_mult: float, radius_px: float, style: String = "bomb", light_shake: bool = false) -> void:
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
	# 视觉实体 + 屏幕抖（按 style 分发）
	if style == "holy":
		holy_pillars.append(_with_upgrade_fx_layer({
			"pos": pos,
			"life": 0.5,
			"max_life": 0.5,
			"fall_t": 0.0,
			"fall_dur": 0.18,
			"radius_px": radius_px,
		}, "angel_holy_bullet"))
		# 屏震对齐激光炮（sr=53），避免天降光柱震感过重
		battle.shake_camera(4.0 * FX_SCALE, 0.08)
	else:
		bomb_explosions.append(_with_upgrade_fx_layer({
			"pos": pos,
			"life": 0.4,
			"max_life": 0.4,
			"radius_px": radius_px,
		}, "bullet_fire_support"))
		# 手榴弹落地（light_shake=true）：屏震降到最轻微档；其余 bomb 来源封顶到激光炮档
		if light_shake:
			battle.shake_camera(1.0 * FX_SCALE, 0.05)
		else:
			battle.shake_camera(4.0 * FX_SCALE, 0.08)
	# _skill_burst 的 shake：light_shake 时归零（只保留粒子），避免叠回大震
	# 震幅封顶到激光炮 burst（3.0 / 0.08）
	var burst_shake := 0.0 if light_shake else 3.0
	_skill_burst(pos, burst_shake, 0.08, Color("#ff8040") if style != "holy" else Color("#a8c8ff"), 10)


# 视觉实体生命周期：bomb_explosions / holy_pillars 仅做计时淡出，不再造成伤害（伤害已在 spawn 时结算）
func _update_bomb_explosions(delta: float) -> void:
	var i := bomb_explosions.size() - 1
	while i >= 0:
		var e: Dictionary = bomb_explosions[i]
		e["life"] = float(e.life) - delta
		if float(e.life) <= 0.0:
			bomb_explosions.remove_at(i)
		else:
			bomb_explosions[i] = e
		i -= 1


func _update_holy_pillars(delta: float) -> void:
	var i := holy_pillars.size() - 1
	while i >= 0:
		var p: Dictionary = holy_pillars[i]
		p["life"] = float(p.life) - delta
		p["fall_t"] = clampf(float(p.fall_t) + delta / float(p.get("fall_dur", 0.18)), 0.0, 1.0)
		if float(p.life) <= 0.0:
			holy_pillars.remove_at(i)
		else:
			holy_pillars[i] = p
		i -= 1


# sr=18 bullet_beam：spawn 一条 laser 短射线
func spawn_v6_bullet_beam(player: BattlePlayer, pos: Vector2, ang: float, atk_mult: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	# 从玩家外缘发射（不用 dispatcher 传入的 hit_pos，那是子弹命中怪物点，离玩家太远）
	# 能量光束是 60px 短冲刺段，发射点贴玩家身体（半径 0.4 处），不要像满屏激光炮那样外推到边缘+14
	var muzzle_offset: float = player.get_effective_radius() * 0.4
	var muzzle: Vector2 = player.global_position + dir * muzzle_offset
	var exit_dist := _ray_playfield_exit_distance(muzzle, dir)
	var beam_length := GameConfig.scale_world(60.0) * FX_SCALE   # 短线段，非满屏光柱
	lasers.append(_with_upgrade_fx_layer({
		"kind": "laser",
		"tail": muzzle,
		"origin": muzzle,
		"dir": dir,
		"exit_dist": exit_dist,             # 段体飞行边界（tail 到达 exit_dist 后消失）
		"beam_length": beam_length,
		"vel": dir * 1200.0,                # 高速向前飞出，沿途贯穿敌人
		"damage": player.get_ability_damage(atk_mult),
		"hit": {},                          # _apply_projectile_hit 内部按 monster id 去重，天然贯穿
		"rot": ang,
		"is_energy_beam": true,             # 走绿色画法（_draw_pixel_energy_beam）
	}, "bullet_beam"))


# sr=46 死神镰刀：实体镰刀飞行物 — 慢速向前飞 + 自身高速自转 + 沿途贯通命中
# 与激光的关键区别：镰刀有实体（一个旋转的弯月像素体在某个位置），不是从 origin 拉到 head 的光条
const SCYTHE_SPEED := 280.0          # 实体飞行速度（px/s）— 再次降速，强调投掷感、便于看清弯月旋转
const SCYTHE_SPIN_SPEED := TAU * 4.0  # 自转角速度（rad/s）— 每秒 4 圈，切割感
const SCYTHE_HIT_RADIUS := 36.0       # 镰刀本体的命中半径
const SCYTHE_PIXEL := 4.0             # 弯月像素块尺寸
const SCYTHE_RADIUS_BLOCKS := 6       # 弯月外接半径（块数）

func spawn_v6_demon_scythe(player: BattlePlayer, pos: Vector2, ang: float, atk_mult: float, pierce: bool) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	# 飞出屏幕外稍远一点后自然消失（不再 fade，越界即死）
	v6_demon_scythes.append(_with_upgrade_fx_layer({
		"pos": pos,
		"dir": dir,
		"vel": dir * SCYTHE_SPEED * FX_SCALE,
		"ang": ang,
		"spin": 0.0,
		"damage": player.get_ability_damage(atk_mult),
		"hit": {},
		"pierce": pierce,
		"life": 6.0,  # 最长 6 秒兜底（极慢分辨率下也能死）
	}, "demon_scythe"))


func _update_v6_demon_scythes(delta: float, player: BattlePlayer, monsters: Array) -> void:
	var i := v6_demon_scythes.size() - 1
	while i >= 0:
		var s: Dictionary = v6_demon_scythes[i]
		var new_pos: Vector2 = Vector2(s.pos) + Vector2(s.vel) * delta
		s["pos"] = new_pos
		s["spin"] = float(s.get("spin", 0.0)) + SCYTHE_SPIN_SPEED * delta
		s["life"] = float(s.life) - delta
		# 镰刀撞阻挡石/深坑/未解锁锁定块 → 火花消失（贯通模式下也终止）
		var _blocked_by_terrain: bool = battle and battle.has_method("is_bullet_blocked_at") and battle.is_bullet_blocked_at(new_pos)
		# 命中扫描：圆形碰撞（镰刀本体）
		_scythe_hit_pos(s, player, monsters, new_pos)
		# 出屏 / 寿命结束 / 被地形阻挡 → 移除
		if _blocked_by_terrain or _is_out_of_playfield(new_pos) or float(s.life) <= 0.0:
			if _blocked_by_terrain and battle and battle.particles:
				battle.particles.hit_spark(new_pos, false)
			v6_demon_scythes.remove_at(i)
		else:
			v6_demon_scythes[i] = s
		i -= 1


# 镰刀当前位置做圆形命中扫描；贯通模式下命中后只记 hit dict 不停飞
func _scythe_hit_pos(s: Dictionary, player: BattlePlayer, monsters: Array, scythe_pos: Vector2) -> void:
	var thickness: float = SCYTHE_HIT_RADIUS * FX_SCALE
	var hit: Dictionary = s.get("hit", {})
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var key := str(m.get_instance_id())
		if hit.has(key):
			continue
		var hit_r := 16.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if scythe_pos.distance_to(m.global_position) > hit_r + thickness:
			continue
		hit[key] = true
		var fake_proj: Dictionary = {
			"kind": "laser",  # 借 laser 通道：bullet 层的伤害分类
			"pos": m.global_position,
			"origin": Vector2(s.pos),
			"damage": int(s.damage),
			"hit": {},
			"rot": float(s.ang),
		}
		_apply_projectile_hit(fake_proj, m, player)
		if not bool(s.pierce):
			s["hit"] = hit
			s["life"] = 0.0  # 非贯通：第一击即消失
			return
	s["hit"] = hit


# 镰刀实体绘制：弯月像素体 + 自身周围 1 圈外发光（不再画 origin→head 的拖尾光带）
func _draw_v6_demon_scythe(canvas: Node2D, s: Dictionary) -> void:
	var world_pos: Vector2 = Vector2(s.pos) - canvas.global_position
	var rot: float = float(s.get("spin", 0.0))
	var flicker: bool = int(Time.get_ticks_msec() / 60) % 2 == 0
	# 外发光圆晕（豪火球术配方：双层 + 闪烁）
	var glow_r1: float = SCYTHE_HIT_RADIUS * FX_SCALE * 1.4
	var glow_r2: float = SCYTHE_HIT_RADIUS * FX_SCALE * 0.9
	var glow_outer := Color(0.6, 0.05, 0.18, 0.22 if flicker else 0.28)
	var glow_inner := Color(0.95, 0.18, 0.20, 0.35 if flicker else 0.45)
	canvas.draw_circle(world_pos, glow_r1, glow_outer)
	canvas.draw_circle(world_pos, glow_r2, glow_inner)
	# 弯月本体（按当前自转角度旋转）
	_draw_pixel_scythe_blade(canvas, world_pos, rot, flicker, 1.0)


# 弯月像素体：13x13 网格画一个 C 形月牙 + 核心高光
func _draw_pixel_scythe_blade(canvas: Node2D, world_pos: Vector2, rot: float, flicker: bool, alpha: float) -> void:
	var px := SCYTHE_PIXEL * FX_SCALE
	var rb := float(SCYTHE_RADIUS_BLOCKS)
	canvas.draw_set_transform(world_pos, rot, Vector2.ONE)
	# 外圈月牙（深紫 → 血红渐变）
	for by in range(-int(rb), int(rb) + 1):
		for bx in range(-int(rb), int(rb) + 1):
			var d_out := sqrt(float(bx * bx + by * by))
			if d_out > rb + 0.2 or d_out < rb - 1.6:
				continue
			# 月牙缺口：保留 bx>0 半圆，遮掉左侧 1.5 块的内圈以形成 C 形
			var inner_d := sqrt(float((bx + 2) * (bx + 2) + by * by))
			if inner_d < rb - 0.8:
				continue
			var ratio := d_out / rb
			canvas.draw_rect(
				Rect2(bx * px - px * 0.5, by * px - px * 0.5, px, px),
				_scythe_block_color(ratio, flicker and ratio > 0.6, alpha)
			)
	# 核心高光（白点）
	canvas.draw_rect(Rect2(rb * px * 0.5 - px * 0.5, -px * 0.5, px, px), Color(1.0, 1.0, 1.0, 0.95 * alpha))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _scythe_block_color(dist_ratio: float, flicker: bool, alpha: float) -> Color:
	var c: Color
	if dist_ratio > 0.92:
		c = Color("#280418") if not flicker else Color("#1a0210")
	elif dist_ratio > 0.78:
		c = Color("#7a0a25") if not flicker else Color("#6a0820")
	elif dist_ratio > 0.55:
		c = Color("#d81830") if not flicker else Color("#c81528")
	elif dist_ratio > 0.32:
		c = Color("#ff5848") if not flicker else Color("#ff4838")
	else:
		c = Color("#ffd8b0") if not flicker else Color("#ffe8c0")
	c.a *= alpha
	return c
# sr=47 硫磺火：单条持续激光 — 寿命 duration 秒、原点跟随玩家、每 tick_interval 秒对沿途怪 tick 一次伤害
# 与 bullet_beam 不同：不飞行（origin 跟随玩家），到寿后整体移除（不是按 traveled 距离）
func spawn_v6_sulfur_laser(player: BattlePlayer, atk_mult: float, duration: float, tick_interval: float) -> void:
	if battle == null or battle.spawner == null:
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	var ang: float = _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
	var dir := Vector2(cos(ang), sin(ang))
	var pos: Vector2 = player.global_position
	var exit_dist := _ray_playfield_exit_distance(pos, dir)
	var beam_length := exit_dist + GameConfig.scale_world(48.0) * FX_SCALE
	lasers.append(_with_upgrade_fx_layer({
		"kind": "laser",
		"tail": pos,
		"origin": pos,
		"dir": dir,
		"exit_dist": exit_dist,
		"beam_length": beam_length,
		"vel": Vector2.ZERO,
		"damage": player.get_ability_damage(atk_mult),
		"atk_mult": atk_mult,                 # 用于每 tick 重算 damage（应对 base_attack 变化）
		"hit": {},
		"rot": ang,
		"is_sulfur_laser": true,
		"follow_player": true,                # _update_lasers 走持续跟随分支
		"life": maxf(0.05, duration),         # 剩余存活秒数
		"tick_interval": maxf(0.02, tick_interval),
		"tick_timer": 0.0,                    # 立即触发首次 tick
	}, "demon_sulfur_laser"))


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
	_skill_burst(pos, 3.0, 0.08, _orb_elem_color(element), 14)


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
	# 地面扩散冲击环（ease_out_cubic 扩散 + 渐隐）— 让「范围冲击/推开」真正看得见
	v6_slash_waves.append({
		"pos": end_pos,
		"radius": radius,
		"life": 0.45,
		"max_life": 0.45,
		"color": Color("#e8e8ff"),
	})
	# 中心粒子爆光（加强：更多粒子 + 更长寿命，配合环扩散）
	_skill_burst(end_pos, 3.0, 0.12, Color("#f4f4ff"), 26)
	if battle:
		battle.shake_camera(2.2, 0.10)


# sr=26 斩击余波地面环：扩散 + 渐隐
func _update_slash_waves(delta: float) -> void:
	if v6_slash_waves.is_empty():
		return
	var i := v6_slash_waves.size() - 1
	while i >= 0:
		var w: Dictionary = v6_slash_waves[i]
		w["life"] = float(w.get("life", 0.0)) - delta
		if float(w.get("life", 0.0)) <= 0.0:
			v6_slash_waves.remove_at(i)
		else:
			v6_slash_waves[i] = w
		i -= 1


func _draw_slash_waves(canvas: Node2D) -> void:
	var offset := -canvas.global_position
	for w in v6_slash_waves:
		var max_life: float = float(w.get("max_life", 0.45))
		var life: float = float(w.get("life", 0.0))
		var p: float = clampf(1.0 - life / max_life, 0.0, 1.0)
		var ease_p: float = 1.0 - pow(1.0 - p, 3.0)   # ease_out_cubic
		var base_r: float = float(w.get("radius", 200.0))
		var radius: float = base_r * ease_p
		var fade: float = 1.0 - p
		var col: Color = w.get("color", Color("#e8e8ff"))
		var center: Vector2 = Vector2(w.pos) + offset
		# 外环描边（亮）+ 内环 + 淡填充，随扩散渐隐
		var outer := Color(col.r, col.g, col.b, 0.9 * fade)
		var fill := Color(col.r, col.g, col.b, 0.18 * fade)
		var inner := Color(min(col.r + 0.2, 1.0), min(col.g + 0.2, 1.0), min(col.b + 0.2, 1.0), 0.5 * fade)
		if radius > 2.0:
			canvas.draw_circle(center, radius, fill)
			canvas.draw_arc(center, radius, 0.0, TAU, 48, outer, 4.0)
			var inner_r: float = radius * 0.62
			if inner_r > 2.0:
				canvas.draw_arc(center, inner_r, 0.0, TAU, 32, inner, 2.0)


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
		# 冰场 tick **不**触发冻结衍生（applies_ice=false）：
		# 冻结衍生 = 立即 0.30×ATK 冰伤 + slow(0.30+bonus)，场域每 0.5s tick × 两路（try_apply + 下方 1438）
		# 重新触发 → 每 tick 多 0.60×ATK 立即伤 + slow 算成 0.30+0.4=0.70（desc 是 40%）。
		# 场域减速改走下方 apply_slow_override（只 slow 不扣血，slow 直接 = slow_pct）。info.element 仍是 "ice"。
		var apply_ice := false
		# 雷场 tick **不**触发雷链（applies_thunder=false）：
		# 雷链是瞬时多目标爆发衍生（0.6×ATK × 链数），场域每 0.5s tick × 场内每只怪都重新整链释放，
		# 把 desc 承诺的「0.5×ATK/0.5s」放大 ~4 倍 → 伤害爆炸。麻痹已由下方 stun_sec 直接 apply_paralyze 给出，
		# 不需要雷链尾麻痹。info.element 仍是 "thunder"（雷属性伤害类型 / 抗性计算不变）。
		var apply_thunder := false
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
			# 走 apply_slow_override：只刷新减速、不扣血、slow 直接 = slow_pct（40%）。
			# 旧代码调 apply_freeze_slow 会每 tick 叠 0.30×ATK 立即伤 + 把 slow 算成 0.30+0.4=0.70（desc 是 40%）。
			if slow_pct > 0.0 and m.has_method("apply_slow_override"):
				m.apply_slow_override(slow_pct, 1.5)
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
				if bool(s.get("pierce", false)):
					continue  # 贯穿：命中不消失，继续检查其他怪
				return true
	return false


func _should_remove_auto_projectile(s: Dictionary, player: BattlePlayer, monsters: Array) -> bool:
	if bool(s.get("returning", false)):
		var dist := Vector2(s.pos).distance_to(player.global_position)
		return dist <= player.get_effective_radius() + 10.0
	# sr=49 血飞刀：穿透 — 命中后保留（仍受 life / out_of_bounds / range 限制）
	if bool(s.get("is_blood_blade", false)):
		return false
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
	# sr=47 sulfur laser：标记火属性 + applies_fire（Sheet4 element_effects 自动触发燃烧）
	if bool(s.get("is_sulfur_laser", false)):
		info.element = "fire"
		info.applies_fire = true
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
		# Phase 3 sr=14/15 bullet_split / bounce — 命中就触发（即使护盾挡掉 damage=0 也算命中）
		# 按 Option A：split/bounce 是「飞行投射物生命周期」加成，仅 auto 子弹吃；激光炮/近身战不吃
		if kind == "auto":
			SpecialRuleDispatcher.on_bullet_hit(player, self, s, m, info, int(result.get("damage", 0)))
		# Phase 6 sr=13 / sr=18 bullet proc spell / beam — 所有「普攻形态」命中都触发
		# （is_basic_attack flag：普通子弹/元气弹/血飞刀/激光炮/未来新形态；近身战在 _fire_melee_swipe 内单独调）
		if bool(s.get("is_basic_attack", false)) and int(result.get("damage", 0)) > 0:
			SpecialRuleDispatcher.on_bullet_proc(player, self, m.global_position, float(s.get("rot", 0.0)))
		if bool(s.get("is_basic_attack", false)):
			# 受击特效统一用画线攻击的 hit_a 动画爆光（与 combat_director.spawn_slash_hit_fx 一致）
			# 所有普攻形态（含激光炮）命中都走这里；近身战有自己的挥砍矩形视觉不经过此分支
			var fx_scale := float(s.get("visual_scale", 1.0))
			if battle and battle.combat:
				battle.combat.spawn_slash_hit_fx(pos, float(s.get("rot", 0.0)), fx_scale)
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
			# 子弹撞阻挡石/深坑/未解锁锁定块 → 火花消失（remove=true，后续 if not remove 检查自动跳过）
			if battle and battle.has_method("is_bullet_blocked_at") and battle.is_bullet_blocked_at(Vector2(s.pos)):
				if battle.particles:
					battle.particles.hit_spark(Vector2(s.pos), false)
				remove = true
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
		var remove: bool = battle == null
		if not remove and bool(s.get("follow_player", false)) and is_instance_valid(player):
			# sr=47 硫磺火 / 持续跟随激光：origin/tail 实时贴在玩家身上；按寿命移除；周期 tick 伤害
			# 方向在 spawn 时锁定，期间不再重新锁敌（参考以撒硫磺火：射出后方向不变）。
			# 玩家移动激光跟随平移，但 dir/rot 保持不变。
			s["life"] = float(s.get("life", 0.0)) - delta
			if float(s["life"]) <= 0.0:
				remove = true
			else:
				var ppos: Vector2 = player.global_position
				var dir: Vector2 = Vector2(s.get("dir", Vector2.RIGHT))
				if dir.length_squared() < 0.0001:
					dir = Vector2.RIGHT
				var exit_dist := _ray_playfield_exit_distance(ppos, dir)
				var beam_length := exit_dist + GameConfig.scale_world(48.0) * FX_SCALE
				s["tail"] = ppos
				s["origin"] = ppos
				s["exit_dist"] = exit_dist
				s["beam_length"] = beam_length
				s["pos"] = _laser_head(s)
				s["tick_timer"] = float(s.get("tick_timer", 0.0)) - delta
				if float(s["tick_timer"]) <= 0.0:
					s["tick_timer"] = float(s.get("tick_interval", 0.1))
					s["hit"] = {}  # 每 tick 重置 hit 表 → 同一怪每 tick 可再受击一次
					var mult: float = float(s.get("atk_mult", 0.5))
					s["damage"] = player.get_ability_damage(mult)
					_apply_laser_hits(s, player, monsters)
		else:
			# 飞行激光：tail 向前推进，到达 exit + beam_length 后移除
			s["tail"] = Vector2(s.get("tail", s.get("pos", Vector2.ZERO))) + Vector2(s.vel) * delta
			s["pos"] = _laser_head(s)
			# sr=53 玩家激光炮：vel=0，靠 life 计时消失（快速渐隐）
			if bool(s.get("is_player_laser", false)):
				s["life"] = float(s.get("life", 0.0)) - delta
				# 命中 tick：每 tick_interval 一次伤害（tick_interval > life → 只触发一次）
				# 每次 tick 都用最新 get_auto_bullet_damage() 刷新，与普攻子弹伤害同步
				s["tick_timer"] = float(s.get("tick_timer", 0.0)) - delta
				if float(s["tick_timer"]) <= 0.0:
					s["tick_timer"] = float(s.get("tick_interval", 1.0))
					s["hit"] = {}
					s["damage"] = player.get_auto_bullet_damage()
					_apply_laser_hits(s, player, monsters)
				remove = battle == null or float(s["life"]) <= 0.0
			else:
				var origin: Vector2 = s.get("origin", s.get("tail", Vector2.ZERO))
				var traveled := (Vector2(s.get("tail", Vector2.ZERO)) - origin).dot(Vector2(s.get("dir", Vector2.RIGHT)))
				remove = battle == null or traveled >= float(s.get("exit_dist", 0.0)) + float(s.get("beam_length", 0.0))
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
		# 旋风弹道：vel ≠ 0 时每帧推进 pos（sword_rage 旋风用；combo_blade_storm 默认 vel=0 保持原地）
		var vel: Vector2 = Vector2(w.get("vel", Vector2.ZERO))
		if vel.length_squared() > 0.001:
			w.pos = Vector2(w.pos) + vel * delta
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
		whirls[i] = w


func _draw_animated_projectile(
	canvas: Node2D,
	world_pos: Vector2,
	rot: float,
	frames: SpriteFrames,
	scale_mul: float,
	anim_t: float,
	alpha: float = 1.0,
	tint: Color = Color(1.0, 1.0, 1.0, 1.0)
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
		Color(tint.r, tint.g, tint.b, alpha)
	)


# 根据 player.current_applies["bullet"] 算混合染色：单元素返回该色；多元素取平均（亮度兜底 0.55）；无元素返回白。
func _bullet_element_tint() -> Color:
	if battle == null or battle.player == null:
		return Color(1.0, 1.0, 1.0, 1.0)
	var applies: Dictionary = battle.player.current_applies.get("bullet", {})
	if applies.is_empty():
		return Color(1.0, 1.0, 1.0, 1.0)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	if bool(applies.get("fire", false)):
		r += 1.0; g += 0.45; b += 0.18; n += 1
	if bool(applies.get("ice", false)):
		r += 0.55; g += 0.85; b += 1.0; n += 1
	if bool(applies.get("thunder", false)):
		r += 1.0; g += 0.92; b += 0.35; n += 1
	if bool(applies.get("poison", false)):
		r += 0.55; g += 1.0; b += 0.45; n += 1
	if n == 0:
		return Color(1.0, 1.0, 1.0, 1.0)
	var inv := 1.0 / float(n)
	var col := Color(r * inv, g * inv, b * inv, 1.0)
	# 亮度兜底：多元素平均后亮度若 < 0.55 则整体抬升（避免变灰暗）
	var luma := 0.299 * col.r + 0.587 * col.g + 0.114 * col.b
	if luma < 0.55:
		var lift := 0.55 / maxf(luma, 0.01)
		col = Color(minf(1.0, col.r * lift), minf(1.0, col.g * lift), minf(1.0, col.b * lift), 1.0)
	return col


func _draw_auto_bullet(canvas: Node2D, s: Dictionary) -> void:
	# 按 visual_kind 分发（由 player.get_active_bullet_visual_kind() 在 spawn 时决出，
	# 同时装备元气弹 + 血飞刀时按"后获得者覆盖"规则胜出）。回落到老 is_spirit / is_blood_blade
	# 兼容尚未带 visual_kind 的存量子弹。
	var visual_kind: String = str(s.get("visual_kind", ""))
	if visual_kind.is_empty():
		if bool(s.get("is_spirit", false)):
			visual_kind = "spirit"
		elif bool(s.get("is_blood_blade", false)):
			visual_kind = "blood_blade"
	match visual_kind:
		"spirit":
			_draw_pixel_spirit_bomb(canvas, s)
			return
		"blood_blade":
			_draw_pixel_blood_blade(canvas, s)
			return
		"shuriken":
			# combo 衍生手里剑：走专属像素 art（不再画成普通白剑气，否则玩家认不出）
			_draw_pixel_shuriken(canvas, Vector2(s.pos) - canvas.global_position, float(s.rot), SHURIKEN_PIXEL)
			return
	# 默认普攻：像素白色月牙剑气（保留元素染色 + 返回态蓝色）
	_draw_pixel_auto_bullet(canvas, s)


const AUTO_BULLET_PIXEL: float = 3.0
# V 形剑气：双臂笔触从尖端 (tip,0) 张向尾部 (back,±H)，沿臂 taper 收尖 → 1px 尖点。
# 尖端朝 +x（飞行方向），沿 rot 旋转贴齐弹道。无元素时走白蓝调色板（核心白 → 外缘淡蓝）。
const AUTO_BULLET_V_TIP_X: float = 5       # 尖端 x（朝 +x）
const AUTO_BULLET_V_BACK_X: float = -1.0      # 张口尾部 x
const AUTO_BULLET_V_HALF_HEIGHT: float = 4  # 尾部半高
const AUTO_BULLET_V_HALF_THICK: float = 1.5    # 双臂笔触半厚（尾部全厚，尖端 taper 收尖）

# "白色剑气"专用调色板：外缘淡蓝描边 → 核心白，无元素时用这套保持"剑气"质感
static var SWORD_AURA_WHITE_PALETTE: PackedColorArray = PackedColorArray([
	Color("#4a7ab4"),  # 外缘描边（淡蓝）
	Color("#8ab0dc"),  # 浅蓝晕
	Color("#c4dcf4"),  # 淡蓝白
	Color("#e8f2fc"),  # 近白
	Color("#ffffff"),  # 核心白
])

# 剑气调色板派生：无元素（近白基色）→ 固定白蓝调色板；有元素染色 → 5 档全部保留元素 tint，
# 核心也不再纯白（只轻微 lerp 30% 向白），确保整个剑气都被染上元素颜色而不是"白核 + 彩色边"
func _derive_sword_aura_palette(base: Color) -> PackedColorArray:
	if base.r > 0.98 and base.g > 0.98 and base.b > 0.98:
		return SWORD_AURA_WHITE_PALETTE
	var out: PackedColorArray = PackedColorArray()
	out.push_back(base.darkened(0.40))              # 外缘：更深的元素色
	out.push_back(base.darkened(0.10))              # 描边：接近纯元素色
	out.push_back(base)                              # 中：纯元素色（原本这里已经开始 lerp 白，太淡）
	out.push_back(base.lerp(Color.WHITE, 0.30))     # 近核：只掺 30% 白，仍带明显元素 tint
	out.push_back(base.lerp(Color.WHITE, 0.55))     # 核心：55% 白 + 45% 元素色，视觉上仍是彩色而非纯白
	return out

# 点到线段距离 + 参数 s（s=0 在起点 A0，s=1 在终点 A0+e）；返回 Vector2(dist, s)
func _seg_dist_s(px: float, py: float, ax: float, ay: float, ex: float, ey: float) -> Vector2:
	var wx: float = px - ax
	var wy: float = py - ay
	var len2: float = ex * ex + ey * ey
	var t: float = 0.0
	if len2 > 0.0001:
		t = clampf((wx * ex + wy * ey) / len2, 0.0, 1.0)
	var cx: float = ax + ex * t
	var cy: float = ay + ey * t
	var ddx: float = px - cx
	var ddy: float = py - cy
	return Vector2(sqrt(ddx * ddx + ddy * ddy), t)

# 默认普攻子弹：白色 V 形剑气（双臂笔触 + 沿臂 taper 收尖：tip=10、back=-3、H=8、px=3、80ms 闪烁）
# 基色仍走 _bullet_element_tint()（无元素返回白），保留元素染色的调色板派生规则。
# returning=true（sr=16 mirror 回弹）强制蓝调色板。
func _draw_pixel_auto_bullet(canvas: Node2D, s: Dictionary) -> void:
	var pos: Vector2 = Vector2(s.get("pos", Vector2.ZERO))
	var rot: float = float(s.get("rot", 0.0))
	var life_t: float = _auto_bullet_life_t(s)
	var t_ms: int = Time.get_ticks_msec()
	var flicker: bool = int(t_ms / 80) % 2 == 0
	var base_color: Color
	if bool(s.get("returning", false)):
		base_color = Color(0.30, 0.60, 1.0)
	else:
		base_color = _bullet_element_tint()
	var palette: PackedColorArray = _derive_sword_aura_palette(base_color)
	var px: float = AUTO_BULLET_PIXEL
	var local: Vector2 = pos - canvas.global_position
	# V 形栅格：双臂从尖端 (T,0) 张向尾部 (B,±H)；沿臂 taper（s 0→1 尖→尾）半厚 floor→full
	# 元素染色直接落在栅格调色板上（核心白 → 外缘淡蓝），不再叠圆晕
	canvas.draw_set_transform(local, rot, Vector2.ONE)
	var tip_x: float = AUTO_BULLET_V_TIP_X
	var back_x: float = AUTO_BULLET_V_BACK_X
	var half_h: float = AUTO_BULLET_V_HALF_HEIGHT
	var half_thick: float = AUTO_BULLET_V_HALF_THICK
	var ex: float = back_x - tip_x            # 两臂公共 x 分量（自尖端起）
	var x_min: int = int(floor(back_x)) - 1
	var x_max: int = int(ceil(tip_x)) + 1
	var y_max: int = int(ceil(half_h)) + 1
	for by in range(-y_max, y_max + 1):
		var fy: float = float(by)
		if absf(fy) > half_h + 1.0:
			continue
		for bx in range(x_min, x_max + 1):
			var fx: float = float(bx)
			# 两臂：A=尖→(B,-H)（上臂），B=尖→(B,+H)（下臂）；取较近者
			var da: Vector2 = _seg_dist_s(fx, fy, tip_x, 0.0, ex, -half_h)
			var db: Vector2 = _seg_dist_s(fx, fy, tip_x, 0.0, ex, half_h)
			var dist: float
			var arm_s: float
			if da.x <= db.x:
				dist = da.x
				arm_s = da.y
			else:
				dist = db.x
				arm_s = db.y
			# 沿臂 taper：尖端 arm_s=0 半厚=35% floor（保留 1px 尖点），尾部 arm_s=1 全厚
			var local_half_thick: float = half_thick * (0.35 + 0.65 * arm_s)
			if dist > local_half_thick + 0.35:
				continue
			# t_pos：0=笔触中心（白核 / 尖端）→ 1=外缘（淡蓝描边）；混入 arm_s 让尾部偏深，强化尖→尾渐变
			var denom: float = maxf(0.35, local_half_thick)
			var t_pos: float = clampf(dist / denom * 0.7 + arm_s * 0.3, 0.0, 1.0)
			var idx: int
			if t_pos < 0.20:
				idx = 4  # 核心白（笔触中线 / 尖端）
			elif t_pos < 0.40:
				idx = 3  # 近白
			elif t_pos < 0.60:
				idx = 2  # 中
			elif t_pos < 0.80:
				idx = 1  # 深
			else:
				idx = 0  # 外缘描边
			var col: Color = palette[idx]
			# 全体块参与闪烁（核心 lerp 向 palette[3] 产生"剑气抖动"，边缘 lerp 向更深加对比）
			if flicker:
				var adj_idx: int = clamp(idx - 1, 0, palette.size() - 1)
				col = col.lerp(palette[adj_idx], 0.35)
			col.a *= 0.75 + life_t * 0.25
			canvas.draw_rect(Rect2(fx * px - px * 0.5, fy * px - px * 0.5, px, px), col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 元气弹：蓝白能量球（比普攻大一圈，rb=5、px=3、呼吸式外发光）
static var SPIRIT_BOMB_PALETTE: PackedColorArray = PackedColorArray([
	Color("#0c2050"),  # 外圈最深
	Color("#1844a0"),  # 深蓝
	Color("#3878d8"),  # 中蓝
	Color("#88c4ff"),  # 浅蓝
	Color("#ffffff"),  # 核心白
])
const SPIRIT_BOMB_PIXEL: float = 3.0
const SPIRIT_BOMB_RADIUS_BLOCKS: int = 5

func _draw_pixel_spirit_bomb(canvas: Node2D, s: Dictionary) -> void:
	var pos: Vector2 = Vector2(s.get("pos", Vector2.ZERO))
	var rot: float = float(s.get("rot", 0.0))
	var life_t: float = _auto_bullet_life_t(s)
	var t_ms: int = Time.get_ticks_msec()
	var flicker: bool = int(t_ms / 80) % 2 == 0
	var local: Vector2 = pos - canvas.global_position
	# sr=11 视觉跟随飞行距离放大：t=0 时 1.0×，飞到最大射程时 1.4×（与伤害加成 +50% 呼应）
	var origin: Vector2 = Vector2(s.get("origin", pos))
	var travel: float = pos.distance_to(origin)
	var max_range: float = maxf(50.0, float(s.get("range_px", 378.0)))
	var travel_t: float = clampf(travel / max_range, 0.0, 1.0)
	var size_scale: float = 1.0 + 0.4 * travel_t
	var px: float = SPIRIT_BOMB_PIXEL * size_scale
	var rb: float = float(SPIRIT_BOMB_RADIUS_BLOCKS)
	# 呼吸式外发光
	var breath: float = 0.95 + 0.1 * sin(float(t_ms) * 0.006)
	var glow_r1: float = px * (rb + 2.0) * breath
	var glow_r2: float = px * (rb + 0.8) * breath
	canvas.draw_circle(local, glow_r1, Color(0.30, 0.55, 1.0, 0.24 * life_t))
	canvas.draw_circle(local, glow_r2, Color(0.55, 0.80, 1.0, 0.36 * life_t))
	canvas.draw_set_transform(local, rot, Vector2.ONE)
	for by in range(-int(rb), int(rb) + 1):
		for bx in range(-int(rb), int(rb) + 1):
			var d: float = sqrt(float(bx * bx + by * by))
			if d > rb + 0.35:
				continue
			var ratio: float = d / rb
			var col: Color = _pixel_orb_block_color(ratio, flicker and ratio > 0.45, SPIRIT_BOMB_PALETTE)
			col.a *= 0.75 + life_t * 0.25
			canvas.draw_rect(Rect2(bx * px - px * 0.5, by * px - px * 0.5, px, px), col)
	# 核心十字高光（4 个像素）
	var core: Color = Color("#ffffff") if not flicker else Color("#e8f0ff")
	canvas.draw_rect(Rect2(-px * 0.5, -px * 0.5, px, px), core)
	canvas.draw_rect(Rect2(-px * 1.5, -px * 0.5, px, px), core)
	canvas.draw_rect(Rect2(px * 0.5, -px * 0.5, px, px), core)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 血飞刀：红刃像素小匕首（剑尖朝飞行方向 = local +x，自转）
# 结构：pommel（青铜圆头） + grip（皮革手柄） + cross-guard（黄铜横档） + 红色 tapered blade + 白色刀尖高光
# 调色板：4 档红色血刃 + 3 档黄铜横档 + 2 档棕皮手柄；60ms 闪烁让锋刃像在反光
const BLOOD_BLADE_PIXEL: float = 3.0

func _draw_pixel_blood_blade(canvas: Node2D, s: Dictionary) -> void:
	var pos: Vector2 = Vector2(s.get("pos", Vector2.ZERO))
	# 直线投掷：刀尖恒朝飞行方向（s.rot），不自转 — 像投枪而不是像飞旋小刀
	var t_ms: int = Time.get_ticks_msec()
	var rot: float = float(s.get("rot", 0.0))
	var life_t: float = _auto_bullet_life_t(s)
	var flicker: bool = int(t_ms / 60) % 2 == 0
	var local: Vector2 = pos - canvas.global_position
	var px: float = BLOOD_BLADE_PIXEL
	# 双层红色外发光（保留原版氛围）
	canvas.draw_circle(local, px * 8.0, Color(0.85, 0.10, 0.15, 0.22 * life_t))
	canvas.draw_circle(local, px * 5.5, Color(1.0, 0.30, 0.30, 0.32 * life_t))
	canvas.draw_set_transform(local, rot, Vector2.ONE)
	# 寿命 alpha：bullet 临近寿终时整把刀淡出，保持与默认 auto bullet 一致的退场感
	var a: float = 0.75 + life_t * 0.25
	# 调色板（已乘 life alpha；色调按 4 档红 + 3 档铜 + 2 档棕，配 60ms 闪烁让锋刃像在反光）
	var blade_outline := Color(0.35, 0.04, 0.07, a) if not flicker else Color(0.26, 0.02, 0.06, a)
	var blade_body := Color(0.78, 0.10, 0.14, a) if not flicker else Color(0.69, 0.06, 0.13, a)
	var blade_highlight := Color(1.0, 0.31, 0.31, a) if not flicker else Color(1.0, 0.44, 0.38, a)
	var blade_tip := Color(1.0, 0.94, 0.88, a) if not flicker else Color(1.0, 0.88, 0.75, a)
	var guard_outline := Color(0.35, 0.22, 0.06, a)
	var guard_main := Color(0.78, 0.63, 0.25, a) if not flicker else Color(0.66, 0.53, 0.16, a)
	var guard_highlight := Color(1.0, 0.88, 0.50, a)
	var grip_outline := Color(0.16, 0.09, 0.03, a)
	var grip_main := Color(0.48, 0.25, 0.13, a)
	var pommel_main := Color(0.63, 0.50, 0.31, a)
	var pommel_outline := Color(0.23, 0.14, 0.09, a)
	# ============ Pommel（青铜小球，x=-6 到 -5） ============
	_blade_pixel(canvas, -6,  0, px, pommel_outline)
	_blade_pixel(canvas, -5, -1, px, pommel_outline)
	_blade_pixel(canvas, -5,  0, px, pommel_main)
	_blade_pixel(canvas, -5,  1, px, pommel_outline)
	_blade_pixel(canvas, -4,  0, px, pommel_outline)
	# ============ Grip（皮革手柄，x=-4 到 -2，3 长 × 3 宽） ============
	for bx in range(-4, -1):
		for by in range(-1, 2):
			var on_edge: bool = (bx == -4) or (by == -1) or (by == 1)
			_blade_pixel(canvas, bx, by, px, grip_outline if on_edge else grip_main)
	# ============ Cross-guard（黄铜横档，x=-1 到 0，垂直 7 高 × 2 宽） ============
	for by in range(-3, 4):
		_blade_pixel(canvas, -1, by, px, guard_outline)
		# x=0 内列：中心 3 格高光，其它黄铜本色
		if absi(by) <= 1:
			_blade_pixel(canvas,  0, by, px, guard_highlight)
		else:
			_blade_pixel(canvas,  0, by, px, guard_main)
	# ============ Blade（红色 tapered，x=+1 到 +7，越往尖越窄） ============
	# 宽度分布（half-width）：x=1..4 → 1（3 宽含中线），x=5..6 → 1（仍 3 宽），x=7 → 0（只剩中线一格）
	# 中线（y=0）用 blade_body 或末段 blade_highlight；y=±1 用 blade_outline 描边
	for bx in range(1, 7):
		# 3 宽段
		_blade_pixel(canvas, bx, -1, px, blade_outline)
		_blade_pixel(canvas, bx,  1, px, blade_outline)
		# 中线：x=1..4 主红，x=5..6 渐亮（接近尖端）
		var center_col: Color = blade_body if bx <= 4 else blade_highlight
		_blade_pixel(canvas, bx,  0, px, center_col)
	# 收尖（x=+7：1 宽，红色描边）
	_blade_pixel(canvas, 7, 0, px, blade_outline)
	# 刀尖白色反光高光（x=+8）
	_blade_pixel(canvas, 8, 0, px, blade_tip)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 小工具：在 local 坐标 (bx, by) 画一个 px×px 块（在 _draw_pixel_blood_blade 调用前先把
# canvas.modulate 设成 life_t 对应的 alpha，比给每个颜色加 alpha 干净；但 modulate 会污染整张画布，
# 这里更稳：让调用方自己在 col.a 上乘 life_alpha；此 helper 不再做 alpha 修饰）
func _blade_pixel(canvas: Node2D, bx: int, by: int, px: float, col: Color) -> void:
	canvas.draw_rect(Rect2(float(bx) * px - px * 0.5, float(by) * px - px * 0.5, px, px), col)


# 4 档调色板派生：根据基色（元素 tint）生成 [外圈深, 中暗, 中亮, 浅, 核心白]
func _derive_orb_palette(base: Color) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	out.push_back(base.darkened(0.75))  # 外圈最深
	out.push_back(base.darkened(0.45))  # 深
	out.push_back(base)                  # 中
	out.push_back(base.lerp(Color.WHITE, 0.55))  # 浅
	out.push_back(base.lerp(Color.WHITE, 0.85))  # 核心
	return out


# 5 档调色板按 dist_ratio 取色（被 #1 / #5 共用，替代旧 _fireball_block_color）
func _pixel_orb_block_color(dist_ratio: float, flicker: bool, palette: PackedColorArray) -> Color:
	var idx: int
	if dist_ratio > 0.92:
		idx = 0
	elif dist_ratio > 0.72:
		idx = 1
	elif dist_ratio > 0.50:
		idx = 2
	elif dist_ratio > 0.28:
		idx = 3
	else:
		idx = 4
	var col: Color = palette[idx]
	if flicker:
		# 闪烁：相邻档颜色之间 lerp 0.4 制造跳动
		var adj_idx: int = clamp(idx - 1, 0, palette.size() - 1)
		col = col.lerp(palette[adj_idx], 0.4)
	return col


# 普攻子弹 life_t（剩余比例，1=新鲜，0=快消失）— 从旧 _draw_auto_bullet 抽出
func _auto_bullet_life_t(s: Dictionary) -> float:
	if not bool(s.get("is_split", false)) and not bool(s.get("is_bounce", false)) and not bool(s.get("returning", false)):
		var origin: Vector2 = Vector2(s.get("origin", s.get("pos", Vector2.ZERO)))
		var traveled: float = Vector2(s.get("pos", Vector2.ZERO)).distance_to(origin)
		var range_px: float = float(s.get("range_px", GameConfig.get_player_value("auto_bullet_range", 378)))
		return clampf(1.0 - traveled / maxf(0.001, range_px), 0.0, 1.0)
	var max_life: float = float(s.get("max_life", GameConfig.get_player_value("auto_bullet_life", 0.9)))
	return clampf(float(s.life) / maxf(0.001, max_life), 0.0, 1.0)


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


func _draw_pixel_fireball(canvas: CanvasItem, world_pos: Vector2, rot: float, life_t: float, scale: float = 1.0) -> void:
	var px := float(FIREBALL_PIXEL)
	var rb := float(FIREBALL_RADIUS_BLOCKS)
	var flicker := int(Time.get_ticks_msec() / 50) % 2 == 0
	var local: Vector2 = world_pos - canvas.global_position
	canvas.draw_set_transform(local, rot, Vector2.ONE * scale)
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


# 火力支援像素爆炸：3 圈像素同心环按 life_t 扩张+淡出，50ms 闪烁
# 调色板：外橙黑 #3a1808 → 中橙 #ff8040 → 核黄 #ffe080
func _draw_pixel_bomb_explosion(canvas: Node2D, e: Dictionary) -> void:
	var pos: Vector2 = Vector2(e.get("pos", Vector2.ZERO))
	var max_life: float = float(e.get("max_life", 0.4))
	var life: float = float(e.get("life", 0.0))
	var t_norm: float = clampf(1.0 - life / maxf(0.001, max_life), 0.0, 1.0)
	var alpha: float = clampf(1.0 - t_norm * 0.8, 0.0, 1.0)
	var local: Vector2 = pos - canvas.global_position
	var t_ms: int = Time.get_ticks_msec()
	var flicker: bool = int(t_ms / 50) % 2 == 0
	var max_r: float = float(e.get("radius_px", 80.0))
	var px: float = 4.0
	var rb_max: float = max_r / px
	for ring_idx in range(3):
		var ring_t: float = float(ring_idx) / 2.0
		var ring_r: float = rb_max * lerpf(0.35, 1.0, t_norm) * (1.0 - ring_t * 0.25)
		var ring_color: Color
		match ring_idx:
			0: ring_color = Color("#ffe080") if not flicker else Color("#fff4a0")
			1: ring_color = Color("#ff8040") if not flicker else Color("#ff6020")
			_: ring_color = Color("#3a1808") if not flicker else Color("#2a1208")
		ring_color.a *= alpha
		for by in range(-int(ring_r) - 1, int(ring_r) + 2):
			for bx in range(-int(ring_r) - 1, int(ring_r) + 2):
				var d: float = sqrt(float(bx * bx + by * by))
				if d > ring_r + 0.4 or d < ring_r - 0.8:
					continue
				canvas.draw_rect(Rect2(local.x + bx * px - px * 0.5,
					local.y + by * px - px * 0.5, px, px), ring_color)
	var glow_r1: float = max_r * lerpf(0.55, 1.35, t_norm)
	var glow_r2: float = max_r * lerpf(0.30, 0.90, t_norm)
	canvas.draw_circle(local, glow_r1, Color(1.0, 0.55, 0.15, 0.22 * alpha))
	canvas.draw_circle(local, glow_r2, Color(1.0, 0.85, 0.35, 0.32 * alpha))


# 圣光柱：从屏幕上方降下的蓝白雷电像素柱（width=4 块 × height=20 块）+ 落地扩散圆
func _draw_pixel_holy_pillar(canvas: Node2D, p: Dictionary) -> void:
	var ground_pos: Vector2 = Vector2(p.get("pos", Vector2.ZERO))
	var max_life: float = float(p.get("max_life", 0.5))
	var life: float = float(p.get("life", 0.0))
	var t_norm: float = clampf(1.0 - life / maxf(0.001, max_life), 0.0, 1.0)
	var fall_t: float = float(p.get("fall_t", 0.0))
	var alpha: float = clampf(1.0 - maxf(0.0, t_norm - 0.5) * 2.0, 0.0, 1.0)
	var t_ms: int = Time.get_ticks_msec()
	var flicker: bool = int(t_ms / 60) % 2 == 0
	var px: float = 4.0
	var pillar_cols: int = 4
	var pillar_rows: int = 20
	var pillar_height_px: float = float(pillar_rows) * px
	var sky_offset: float = pillar_height_px * 4.0
	var top_y: float = ground_pos.y - pillar_height_px - sky_offset * (1.0 - fall_t)
	var top_local: Vector2 = Vector2(ground_pos.x, top_y) - canvas.global_position
	var half_w: float = float(pillar_cols) * 0.5
	for ry in range(pillar_rows):
		for cx in range(pillar_cols):
			var x: float = top_local.x + (float(cx) - half_w) * px
			var y: float = top_local.y + float(ry) * px
			var col_idx: int = mini(cx, pillar_cols - 1 - cx)
			var col: Color
			match col_idx:
				0: col = Color("#1830a0") if not flicker else Color("#1024a0")
				_: col = Color("#88c4ff") if not flicker else Color("#a8d0ff")
			var jitter_seed: int = (ry * 13 + cx * 7 + int(t_ms / 60)) % 11
			if jitter_seed < 3:
				col = Color("#ffffff")
			col.a *= alpha
			canvas.draw_rect(Rect2(x, y, px, px), col)
	var ground_local: Vector2 = Vector2(ground_pos.x, ground_pos.y) - canvas.global_position
	if fall_t >= 0.95:
		var splash_r: float = float(p.get("radius_px", 80.0)) * minf(1.0, (t_norm - 0.36) * 3.0)
		if splash_r > 0.0:
			canvas.draw_circle(ground_local, splash_r * 1.2, Color(0.30, 0.55, 1.0, 0.30 * alpha))
			canvas.draw_circle(ground_local, splash_r * 0.7, Color(0.65, 0.85, 1.0, 0.45 * alpha))
	canvas.draw_circle(ground_local, px * 6.0, Color(0.40, 0.60, 1.0, 0.28 * alpha))


func _draw_laser(canvas: Node2D, s: Dictionary) -> void:
	var tail: Vector2 = Vector2(s.get("tail", s.get("pos", Vector2.ZERO))) - canvas.global_position
	var head := _laser_head(s) - canvas.global_position
	var origin: Vector2 = Vector2(s.get("origin", s.tail)) - canvas.global_position
	var dir := Vector2(s.get("dir", Vector2.RIGHT)).normalized()
	var tip := head + dir * GameConfig.scale_world(12.0) * FX_SCALE
	# 硫磺火走暗红配色（参考以撒 Brimstone）；其他 laser（bullet_beam 等）走原品红 / 白
	if bool(s.get("is_sulfur_laser", false)):
		var t_ms: int = Time.get_ticks_msec()
		var flicker: bool = int(t_ms / 60) % 2 == 0
		var halo := Color(0.55, 0.02, 0.04, 0.45 if flicker else 0.38)
		var mid := Color(0.78, 0.08, 0.06, 0.92)
		var core := Color(1.0, 0.42, 0.20, 0.95 if flicker else 0.85)
		canvas.draw_line(tail, tip, halo, GameConfig.scale_world(24.0) * FX_SCALE)
		canvas.draw_line(tail, tip, mid, GameConfig.scale_world(10.0) * FX_SCALE)
		canvas.draw_line(tail, tip, core, GameConfig.scale_world(3.5) * FX_SCALE)
		# 沿途 7 个像素方块（暗红 → 亮红交替），制造"硫磺火"颗粒感
		for i in range(7):
			var t := float(i) / 6.0
			var p := tail.lerp(tip, t)
			var dot_col: Color = Color(1.0, 0.62, 0.30, 0.85) if (i + int(t_ms / 80)) % 2 == 0 else Color(0.85, 0.18, 0.08, 0.85)
			canvas.draw_rect(Rect2(p.x - 3.0, p.y - 3.0, 6.0, 6.0), dot_col)
		# 起点深红光晕（吟唱口）
		canvas.draw_circle(origin, GameConfig.scale_world(8.0) * FX_SCALE, Color(0.55, 0.05, 0.05, 0.60))
		canvas.draw_circle(origin, GameConfig.scale_world(5.0) * FX_SCALE, Color(1.0, 0.40, 0.15, 0.85))
		# 末端亮橙红高光
		canvas.draw_circle(head, GameConfig.scale_world(6.0) * FX_SCALE, Color(1.0, 0.55, 0.20, 0.95))
		return
	# sr=53 玩家蓄力激光炮：白 + 淡蓝调色板
	if bool(s.get("is_player_laser", false)):
		_draw_pixel_player_laser(canvas, s)
		return
	# sr=18 能量光束：绿色 + 逐步射出 + 细线宽
	if bool(s.get("is_energy_beam", false)):
		_draw_pixel_energy_beam(canvas, s)
		return
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
	# sr=26 trail_slash_wave 斩击余波：地面扩散冲击环（仅 below_monsters）
	if below_monsters:
		_draw_slash_waves(canvas)
	for s in shurikens:
		if not _fx_on_layer(s, below_monsters):
			continue
		var kind := _projectile_kind(s)
		if kind == "auto":
			_draw_auto_bullet(canvas, s)
			continue
		if kind == "fireball":
			var life_t := clampf(float(s.life) / 0.95, 0.0, 1.0)
			var vs := float(s.get("visual_scale", 1.0))
			_draw_pixel_fireball(canvas, Vector2(s.pos), float(s.rot), life_t, vs)
			continue
		_draw_pixel_shuriken(canvas, Vector2(s.pos) - canvas.global_position, float(s.rot), SHURIKEN_PIXEL)
	for laser in lasers:
		if not _fx_on_layer(laser, below_monsters):
			continue
		_draw_laser(canvas, laser)
	for sc in v6_demon_scythes:
		if not _fx_on_layer(sc, below_monsters):
			continue
		_draw_v6_demon_scythe(canvas, sc)
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
	for e in bomb_explosions:
		if not _fx_on_layer(e, below_monsters):
			continue
		_draw_pixel_bomb_explosion(canvas, e)
	for p in holy_pillars:
		if not _fx_on_layer(p, below_monsters):
			continue
		_draw_pixel_holy_pillar(canvas, p)
	_draw_grenade_arcs(canvas, below_monsters)
	# sr=55 炸弹人：pending 炸弹（引信中）+ 十字爆炸淡出
	for b in pending_bombs:
		if not _fx_on_layer(b, below_monsters):
			continue
		_draw_pixel_pending_bomb(canvas, b)
	for c in cross_explosions:
		if not _fx_on_layer(c, below_monsters):
			continue
		_draw_pixel_cross_explosion(canvas, c)
	# sr=54 近身战：挥砍矩形
	for ms in melee_swipes:
		if not _fx_on_layer(ms, below_monsters):
			continue
		_draw_melee_swipe_fx(canvas, ms)


# ==================================================================
# sr=53 laser_cannon_basic — 普攻改白色激光炮
# ==================================================================
# 每次 auto_bullet cycle（动画从头到 release frame）= 一发激光。
# 攻速通过卡表 attr 2 直接扣 30%，玩家 basic_attack_speed 自然变慢 → 激光更疏。
# 激光发射位置从玩家外缘（radius + padding）沿朝向前推，避免覆盖玩家 sprite。
func spawn_v6_player_laser(player: BattlePlayer, monsters: Array, atk_mult: float, pierce: bool, color_key: String, ang: float) -> void:
	if battle == null:
		return
	var dir := Vector2(cos(ang), sin(ang))
	# 发射位置外推到玩家外缘：radius + padding，避免激光贴在身上
	var muzzle_offset: float = player.get_effective_radius() + GameConfig.scale_world(14.0)
	var pos: Vector2 = player.global_position + dir * muzzle_offset
	var exit_dist := _ray_playfield_exit_distance(pos, dir)
	var beam_length := exit_dist + GameConfig.scale_world(48.0) * FX_SCALE
	# 若装备元素子弹 (applies_* on bullet)，激光颜色跟随元素；否则白色
	var effective_color: String = color_key
	var applies_map: Dictionary = player.current_applies.get("bullet", {}) if "current_applies" in player else {}
	if bool(applies_map.get("fire", false)):
		effective_color = "fire"
	elif bool(applies_map.get("ice", false)):
		effective_color = "ice"
	elif bool(applies_map.get("thunder", false)):
		effective_color = "thunder"
	elif bool(applies_map.get("poison", false)):
		effective_color = "poison"
	lasers.append(_with_upgrade_fx_layer({
		"kind": "laser",
		"tail": pos,
		"origin": pos,
		"dir": dir,
		"exit_dist": exit_dist,
		"beam_length": beam_length,
		"vel": Vector2.ZERO,
		"damage": player.get_auto_bullet_damage(),   # 与普攻子弹同伤害基线
		"atk_mult": atk_mult,
		"hit": {},
		"rot": ang,
		"is_sulfur_laser": false,   # 与硫磺火分开渲染分支
		"is_player_laser": true,
		"is_basic_attack": true,   # 激光炮是普攻形态 → 吃 sr=11/13/18 + 受击特效（修复「激光炮导致能量光束失效」）
		"laser_color_key": effective_color,
		"pierce": pierce,
		"follow_player": false,
		"life": 0.18,                # 短寿命 — 快速渐隐（原 0.35 太拖沓）
		"max_life": 0.18,
		"tick_interval": 1.0,        # 整发激光只触发一次伤害（tick_interval > life）
		"tick_timer": 0.0,
	}, "bullet_laser_cannon"))
	# 屏幕轻抖 + 前端粒子
	if battle:
		battle.shake_camera(4.0 * FX_SCALE, 0.08)
	_skill_burst(pos + dir * GameConfig.scale_world(6.0), 3.0, 0.08, _laser_color_core(effective_color), 8)


# ==================================================================
# sr=54 melee_basic — 普攻改近战挥砍
# ==================================================================
# 每次 volley 只做一次挥砍 AOE：以玩家为中心，沿最近敌人方向 melee_range_px 范围内所有怪吃伤害
# 伤害 = get_auto_bullet_damage × (1 + melee_basic_atk_bonus)
func _fire_melee_swipe(player: BattlePlayer, monsters: Array) -> void:
	if player == null or monsters.is_empty():
		return
	var base_ang := _nearest_monster_angle(player.global_position, -PI * 0.5, monsters)
	var dir: Vector2 = Vector2(cos(base_ang), sin(base_ang))
	var range_px: float = float(player.melee_range_px) * GameConfig.get_world_scale()
	var bonus: float = 1.0 + float(player.melee_basic_atk_bonus)
	var dmg_raw: int = player.get_auto_bullet_damage()
	var dmg: int = maxi(1, int(round(float(dmg_raw) * bonus)))
	# 命中判定：敌人在 melee 前方半锥（距离 <= range 且 与 dir 夹角 < 60°）
	var hit_r_pad := 12.0
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var to_m: Vector2 = m.global_position - player.global_position
		var d: float = to_m.length()
		var hitbox: float = m.get_hitbox_radius() if m.has_method("get_hitbox_radius") else 16.0
		if d > range_px + hitbox + hit_r_pad:
			continue
		if d > 0.001 and to_m.normalized().dot(dir) < 0.15:
			continue  # 后方不算
		var info := player.make_ability_damage("melee_swipe", bonus, "bullet", "", false, false)
		info.raw_amount = dmg
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, player.global_position)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color(0.95, 0.95, 0.95, 1.0))
			# 近身战视为普攻命中实例 → 触发 sr=13/18 on_bullet_proc（火力支援/能量光束）。
			# 注意：不调 on_bullet_hit（split/bounce 是飞行专属，按 Option A 跳过），
			#       也不走 transform_bullet_damage（sr=11 按飞行距离缩放，近战无飞行距离且攻击距离锁死）。
			if int(result.get("damage", 0)) > 0:
				SpecialRuleDispatcher.on_bullet_proc(player, self, m.global_position, base_ang)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	# 视觉：在玩家前方一次性短寿命挥砍矩形
	melee_swipes.append(_with_upgrade_fx_layer({
		"pos": player.global_position,
		"dir": dir,
		"range_px": range_px,
		"life": 0.15,
		"max_life": 0.15,
	}, "bullet_melee"))
	if battle:
		battle.shake_camera(3.0 * FX_SCALE, 0.06)


# ==================================================================
# sr=55 bomb_on_slash_end — 十字炸弹
# ==================================================================
# on_slash_end 时 spawn 一个 pending bomb（闪烁引信 fuse 秒）；引信=0 时执行十字 AOE
func spawn_v6_cross_bomb(player: BattlePlayer, pos: Vector2, atk_mult: float, fuse_sec: float, cross_arm_px: float) -> void:
	if battle == null:
		return
	pending_bombs.append(_with_upgrade_fx_layer({
		"pos": pos,
		"fuse": maxf(0.1, fuse_sec),
		"max_fuse": maxf(0.1, fuse_sec),
		"atk_mult": atk_mult,
		"arm_px": cross_arm_px,
		"caster": player,
	}, "trail_bomber"))


func _update_pending_bombs(delta: float, player: BattlePlayer, monsters: Array) -> void:
	var i := pending_bombs.size() - 1
	while i >= 0:
		var b: Dictionary = pending_bombs[i]
		b.fuse = maxf(0.0, float(b.fuse) - delta)
		if b.fuse <= 0.0:
			# 引信到，执行十字爆炸
			_apply_cross_bomb_hits(b, player, monsters)
			cross_explosions.append(_with_upgrade_fx_layer({
				"pos": Vector2(b.pos),
				"arm_px": float(b.arm_px),
				"life": 0.32,
				"max_life": 0.32,
			}, "trail_bomber"))
			if battle:
				battle.shake_camera(4.0 * FX_SCALE, 0.08)
			pending_bombs.remove_at(i)
		else:
			pending_bombs[i] = b
		i -= 1


func _apply_cross_bomb_hits(b: Dictionary, player: BattlePlayer, monsters: Array) -> void:
	var pos: Vector2 = Vector2(b.pos)
	var half_w: float = 20.0  # 十字宽度（半）
	var atk_mult: float = float(b.atk_mult)
	var dmg: int = player.get_ability_damage(atk_mult)
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var to_m: Vector2 = m.global_position - pos
		var hitbox: float = m.get_hitbox_radius() if m.has_method("get_hitbox_radius") else 16.0
		# 十字无限长：只判断到轴的垂直距离，忽略沿轴距离
		var horiz: bool = absf(to_m.y) <= half_w + hitbox
		var vert: bool = absf(to_m.x) <= half_w + hitbox
		if not (horiz or vert):
			continue
		var info := player.make_ability_damage("cross_bomb", atk_mult, "trail", "", false, false)
		info.raw_amount = dmg
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, pos)
		if not result.is_empty():
			if battle.combat:
				battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color(1.0, 0.72, 0.15, 1.0))
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)


func _update_cross_explosions(delta: float) -> void:
	var i := cross_explosions.size() - 1
	while i >= 0:
		var c: Dictionary = cross_explosions[i]
		c.life = maxf(0.0, float(c.life) - delta)
		if c.life <= 0.0:
			cross_explosions.remove_at(i)
		else:
			cross_explosions[i] = c
		i -= 1


func _update_melee_swipes(delta: float) -> void:
	var i := melee_swipes.size() - 1
	while i >= 0:
		var s: Dictionary = melee_swipes[i]
		s.life = maxf(0.0, float(s.life) - delta)
		if s.life <= 0.0:
			melee_swipes.remove_at(i)
		else:
			melee_swipes[i] = s
		i -= 1


# ==================================================================
# 像素绘制：pending bomb / cross explosion / melee swipe / player laser
# ==================================================================
# FC 炸弹人配色：#111 外壳 / #f8f8f8 高光 / #ffb000 引信
func _draw_pixel_pending_bomb(canvas: Node2D, b: Dictionary) -> void:
	var pos: Vector2 = Vector2(b.get("pos", Vector2.ZERO))
	var fuse: float = float(b.get("fuse", 0.0))
	var max_fuse: float = float(b.get("max_fuse", 2.0))
	var local: Vector2 = pos - canvas.global_position
	var t_ms: int = Time.get_ticks_msec()
	# 越接近爆炸闪烁越快
	var period_ms: int = 100 if fuse > max_fuse * 0.5 else (50 if fuse > 0.4 else 30)
	var flicker: bool = int(t_ms / period_ms) % 2 == 0
	# 外发光
	canvas.draw_circle(local, 26.0, Color(1.0, 0.7, 0.15, 0.18))
	# 圆形炸弹本体
	canvas.draw_circle(local, 18.0, Color("#111111"))
	canvas.draw_circle(local, 16.0, Color("#2a2828"))
	canvas.draw_circle(local + Vector2(-5.0, -5.0), 5.0, Color("#f8f8f8"))  # 高光
	# 引信（从顶部一小段线）
	var fuse_tip_col: Color = Color("#ffe860") if flicker else Color("#ffb000")
	canvas.draw_line(local + Vector2(0.0, -18.0), local + Vector2(0.0, -28.0), Color("#663300"), 3.0)
	canvas.draw_circle(local + Vector2(0.0, -28.0), 4.0, fuse_tip_col)


# 十字爆炸：4 条从中心扩展的橙黄矩形 + 中心闪白
const CROSS_EXP_PAL := [
	Color("#ffffff"),  # 中心
	Color("#ffd744"),
	Color("#ff8000"),
	Color("#d02010"),
]

func _draw_pixel_cross_explosion(canvas: Node2D, c: Dictionary) -> void:
	var pos: Vector2 = Vector2(c.get("pos", Vector2.ZERO))
	var life: float = float(c.get("life", 0.0))
	var max_life: float = float(c.get("max_life", 0.32))
	var t_norm: float = clampf(1.0 - life / maxf(0.001, max_life), 0.0, 1.0)  # 0 → 1 扩展
	var alpha: float = clampf(1.0 - t_norm * 0.8, 0.0, 1.0)
	var local: Vector2 = pos - canvas.global_position
	# 无限十字：臂长直接撑到屏外，快速全屏铺开
	var arm_full: float = 3000.0
	var half_len: float = arm_full * clampf(t_norm * 2.0, 0.1, 1.0)
	var half_w: float = 20.0 + 10.0 * t_norm
	# 阴影层（暗红）
	var col_dark: Color = CROSS_EXP_PAL[3]
	col_dark.a = alpha
	canvas.draw_rect(Rect2(local.x - half_len - 4.0, local.y - half_w - 3.0, (half_len + 4.0) * 2.0, (half_w + 3.0) * 2.0), col_dark)
	canvas.draw_rect(Rect2(local.x - half_w - 3.0, local.y - half_len - 4.0, (half_w + 3.0) * 2.0, (half_len + 4.0) * 2.0), col_dark)
	# 主色层（橙）
	var col_orange: Color = CROSS_EXP_PAL[2]
	col_orange.a = alpha
	canvas.draw_rect(Rect2(local.x - half_len, local.y - half_w, half_len * 2.0, half_w * 2.0), col_orange)
	canvas.draw_rect(Rect2(local.x - half_w, local.y - half_len, half_w * 2.0, half_len * 2.0), col_orange)
	# 高光层（黄）
	var col_yellow: Color = CROSS_EXP_PAL[1]
	col_yellow.a = alpha * 0.85
	var hw2: float = maxf(3.0, half_w - 6.0)
	canvas.draw_rect(Rect2(local.x - half_len, local.y - hw2, half_len * 2.0, hw2 * 2.0), col_yellow)
	canvas.draw_rect(Rect2(local.x - hw2, local.y - half_len, hw2 * 2.0, half_len * 2.0), col_yellow)
	# 中心闪白
	var flash_r: float = 22.0 * (1.0 - t_norm) + 6.0
	canvas.draw_circle(local, flash_r, Color(1.0, 1.0, 1.0, alpha))


# 近战挥砍矩形（sr=54 视觉）— 银灰 20×8 矩形沿 dir + 前端 3px 高光
func _draw_melee_swipe_fx(canvas: Node2D, item: Dictionary) -> void:
	var pos: Vector2 = Vector2(item.get("pos", Vector2.ZERO))
	var dir: Vector2 = Vector2(item.get("dir", Vector2.RIGHT))
	var range_px: float = float(item.get("range_px", 60.0))
	var life: float = float(item.get("life", 0.0))
	var max_life: float = float(item.get("max_life", 0.15))
	var t_norm: float = clampf(1.0 - life / maxf(0.001, max_life), 0.0, 1.0)
	var alpha: float = clampf(1.0 - t_norm, 0.0, 1.0)
	var local: Vector2 = pos - canvas.global_position
	# 沿 dir 绘制 20×8 矩形（旋转）
	var ang: float = dir.angle()
	canvas.draw_set_transform(local, ang, Vector2.ONE)
	var swipe_len: float = range_px * (0.35 + 0.65 * t_norm)
	var swipe_w: float = 8.0
	canvas.draw_rect(Rect2(0.0, -swipe_w * 0.5, swipe_len, swipe_w), Color(0.44, 0.44, 0.48, alpha))       # 描边
	canvas.draw_rect(Rect2(2.0, -swipe_w * 0.5 + 1.0, swipe_len - 4.0, swipe_w - 2.0), Color(0.75, 0.75, 0.78, alpha))  # 主色
	canvas.draw_rect(Rect2(swipe_len - 6.0, -1.5, 5.0, 3.0), Color(0.98, 0.98, 0.98, alpha))                 # 前端高光
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 玩家白色激光绘制（覆盖 sulfur_laser 分支，让 _draw_laser 走 is_player_laser 通道）
# 用法：在 _draw_laser 的分支里检测 s.get("is_player_laser") 时调用此函数
func _draw_pixel_player_laser(canvas: Node2D, s: Dictionary) -> void:
	var tail: Vector2 = Vector2(s.get("tail", s.get("pos", Vector2.ZERO)))
	var dir: Vector2 = Vector2(s.get("dir", Vector2.RIGHT))
	var beam_length: float = float(s.get("beam_length", 400.0))
	var life: float = float(s.get("life", 0.0))
	var max_life: float = float(s.get("max_life", 0.18))
	if max_life <= 0.0:
		max_life = 0.18
	# 陡渐隐：pow(life_ratio, 0.5) 让前 40% 时间线更饱满、后 60% 快速衰减
	var life_ratio: float = clampf(life / max_life, 0.0, 1.0)
	var alpha: float = pow(life_ratio, 0.5)
	var local: Vector2 = tail - canvas.global_position
	var head: Vector2 = local + dir * beam_length
	var color_key: String = String(s.get("laser_color_key", "white"))
	var pal := _laser_palette(color_key)
	var s_world := GameConfig.get_world_scale()
	# 4 档线宽：外晕 22px / 主色 12px / 高光 7px / 核心 3px
	canvas.draw_line(local, head, Color(pal[0].r, pal[0].g, pal[0].b, 0.42 * alpha), 22.0 * s_world)  # 外晕
	canvas.draw_line(local, head, Color(pal[1].r, pal[1].g, pal[1].b, 0.90 * alpha), 12.0 * s_world)  # 主色
	canvas.draw_line(local, head, Color(pal[2].r, pal[2].g, pal[2].b, alpha), 7.0 * s_world)          # 高光
	canvas.draw_line(local, head, Color(pal[3].r, pal[3].g, pal[3].b, alpha), 3.0 * s_world)          # 核心
	# 头端闪光
	canvas.draw_circle(head, 10.0 * s_world * alpha, Color(pal[3].r, pal[3].g, pal[3].b, alpha))
	canvas.draw_circle(head, 16.0 * s_world * alpha, Color(pal[1].r, pal[1].g, pal[1].b, alpha * 0.5))


# sr=18 能量光束：绿色 + 从起点向头端逐步射出 + 细线宽
const ENERGY_BEAM_PAL := [
	Color(0.10, 0.50, 0.15),  # 外晕
	Color(0.25, 0.90, 0.30),  # 主色
	Color(0.60, 1.0, 0.55),   # 高光
	Color(0.90, 1.0, 0.85),   # 核心
]

func _draw_pixel_energy_beam(canvas: Node2D, s: Dictionary) -> void:
	# 有限长度飞行光束：tail 由 _update_lasers 每帧前推，head = tail + dir * beam_length（固定 60）
	# 不渐隐、不做延伸动画 — 段体本身在飞，视觉自然由平移带来"射出"感
	var tail: Vector2 = Vector2(s.get("tail", s.get("pos", Vector2.ZERO)))
	var dir: Vector2 = Vector2(s.get("dir", Vector2.RIGHT))
	var beam_length: float = float(s.get("beam_length", 60.0))
	var local: Vector2 = tail - canvas.global_position
	var head: Vector2 = local + dir * beam_length
	var s_world := GameConfig.get_world_scale()
	# 中等线宽：外晕 12 / 主色 7 / 高光 4 / 核心 2
	canvas.draw_line(local, head, Color(ENERGY_BEAM_PAL[0].r, ENERGY_BEAM_PAL[0].g, ENERGY_BEAM_PAL[0].b, 0.42), 12.0 * s_world)
	canvas.draw_line(local, head, Color(ENERGY_BEAM_PAL[1].r, ENERGY_BEAM_PAL[1].g, ENERGY_BEAM_PAL[1].b, 0.90), 7.0 * s_world)
	canvas.draw_line(local, head, ENERGY_BEAM_PAL[2], 4.0 * s_world)
	canvas.draw_line(local, head, ENERGY_BEAM_PAL[3], 2.0 * s_world)
	# 头端亮点（飞行方向前端）
	canvas.draw_circle(head, 7.0 * s_world, ENERGY_BEAM_PAL[3])
	canvas.draw_circle(head, 11.0 * s_world, Color(ENERGY_BEAM_PAL[1].r, ENERGY_BEAM_PAL[1].g, ENERGY_BEAM_PAL[1].b, 0.5))


# 激光炮 4 档调色板（外晕 / 主色 / 高光 / 核心）— 按颜色 key 返回
func _laser_palette(color_key: String) -> Array:
	match color_key:
		"fire":
			return [Color(1.0, 0.35, 0.10), Color(1.0, 0.55, 0.20), Color(1.0, 0.80, 0.40), Color(1.0, 0.95, 0.75)]
		"ice":
			return [Color(0.35, 0.65, 1.0),  Color(0.55, 0.80, 1.0), Color(0.80, 0.94, 1.0), Color(0.95, 0.99, 1.0)]
		"thunder":
			return [Color(0.90, 0.55, 1.0),  Color(1.0, 0.85, 0.30), Color(1.0, 0.95, 0.65), Color(1.0, 1.0, 0.90)]
		"poison":
			return [Color(0.35, 0.85, 0.30), Color(0.55, 1.0, 0.45), Color(0.80, 1.0, 0.65), Color(0.95, 1.0, 0.85)]
		_:  # "white"
			return [Color(0.24, 0.55, 1.0),  Color(0.50, 0.75, 1.0), Color(0.85, 0.95, 1.0), Color(1.0, 1.0, 1.0)]


func _laser_color_core(color_key: String) -> Color:
	return _laser_palette(color_key)[3]
