extends Node
class_name SummonAbilityManager

const PLAY_TOP := 88.0
const FX_SCALE := 1.75
const THUNDER_CFG := {
	"interval": 1.0,
	"radius": 52.0,
	"dmg_mult": 0.38,
	"warn_time": 0.22,
	"bolt_time": 0.09,
	"explode_time": 0.32,
	"sky_y": 0.0,
}
const WOLF_CFG := {
	"speed": 118.0,
	"aggro": INF,
	"atk_range": 36.0,
	"atk_cd": 0.75,
	"dmg_mult": 0.8,
}
const BULL_CFG := {
	"aggro": INF,
	"charge_speed": 420.0,
	"charge_time": 1.4,
	"charge_dmg_mult": 1,
	"idle_cd": 1.1,
	"dmg_mult": 0.8,
}
const GOD_CFG := {
	"follow_speed": 52.0,
	"atk_interval": 0.28,
	"sword_speed": 540.0,
	"dmg_mult": 1.2,
	"orbit_dist": 14.0,
}

var battle
var companions_container: Node2D
var thunder_bolts: Array = []
var thunder_timer := 0.0
var companions: Array = []
var god_swords: Array = []


func setup(battle_node) -> void:
	battle = battle_node
	companions_container = Node2D.new()
	companions_container.name = "Companions"
	companions_container.z_index = 2
	battle.get_node("Entities").add_child(companions_container)


func reset(keep_companions := false) -> void:
	if not keep_companions:
		companions.clear()
		_clear_companion_sprites()
		thunder_timer = 0.0
	thunder_bolts.clear()
	god_swords.clear()


func has_active_fx() -> bool:
	return not thunder_bolts.is_empty() or not god_swords.is_empty()


func update(delta: float, player: BattlePlayer, monsters: Array) -> void:
	if player == null or battle == null:
		return
	if battle.state != GameState.PLAYING:
		return
	if player.hp <= 0:
		return
	# 子弹时间 / 慢动作期间暂停天雷与召唤逻辑（与怪物 AI、火柱一致）
	if delta <= 0.0 or player.state == BattlePlayer.State.BULLET_TIME:
		return
	if player.get_upgrade_level("heavenly_thunder") > 0:
		_update_thunder(delta, player, monsters)
	if player.get_upgrade_level("wild_wolf") > 0 \
			or player.get_upgrade_level("wild_bull") > 0 \
			or player.get_upgrade_level("divine_god") > 0:
		_update_companions(delta, player, monsters)
	_sync_companion_visuals()


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	_draw_thunder(canvas, below_monsters)
	for s in god_swords:
		if not _fx_on_layer(s, below_monsters):
			continue
		_draw_god_sword(canvas, s)


func _with_upgrade_fx_layer(data: Dictionary, upgrade_id: String) -> Dictionary:
	data["upgrade_id"] = upgrade_id
	data["below_monsters"] = GameConfig.upgrade_fx_below_monsters(upgrade_id)
	return data


func _fx_on_layer(item: Dictionary, below_monsters: bool) -> bool:
	return bool(item.get("below_monsters", false)) == below_monsters


func _play_bottom() -> float:
	return float(GameConfig.get_tuning("logical_height", 1280))


func _play_width() -> float:
	return float(GameConfig.get_tuning("logical_width", 720))


func _get_pet_count_multiplier(player: BattlePlayer) -> int:
	var heart := player.get_upgrade_level("nurturing_heart")
	if heart <= 0:
		return 1
	return int(pow(2.0, heart))


func _get_desired_pet_count(player: BattlePlayer, upgrade_id: String) -> int:
	var lv := player.get_upgrade_level(upgrade_id)
	if lv <= 0:
		return 0
	var def := GameConfig.get_upgrade(upgrade_id)
	if def.is_empty() or int(def.get("is_pet", 0)) == 0:
		return lv
	var per_level := maxi(1, int(def.get("apply_value", 1)))
	return lv * per_level * _get_pet_count_multiplier(player)


func _upgrade_id_for_type(type: String) -> String:
	match type:
		"wolf":
			return "wild_wolf"
		"bull":
			return "wild_bull"
		_:
			return "divine_god"


func _player_repositioning(player: BattlePlayer) -> bool:
	return player.state == BattlePlayer.State.BULLET_TIME or player.state == BattlePlayer.State.ATTACKING


func _summon_deal_damage(m, damage: int, color: Color, from_pos: Vector2) -> void:
	if m == null or not is_instance_valid(m) or m.get("alive") == false:
		return
	if m.has_method("take_damage"):
		var result: Dictionary = m.take_damage(damage, from_pos)
		if battle and battle.combat and int(result.get("damage", 0)) > 0:
			battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false)
			if battle.player and battle.player.has_method("on_summon_hit"):
				battle.player.on_summon_hit()
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(m)


func _summon_aoe_damage(center: Vector2, radius: float, damage: int, color: Color) -> void:
	if battle == null or battle.spawner == null:
		return
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var hit_r := 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if center.distance_to(m.global_position) > radius + hit_r:
			continue
		_summon_deal_damage(m, damage, color, center)


func _anchor_near_player(player: BattlePlayer, index: int, total: int, dist_mul: float) -> Vector2:
	var base := float(index) / float(maxi(1, total)) * TAU
	var orbit := Time.get_ticks_msec() * 0.001 + base
	var r := player.get_effective_radius() + GameConfig.scale_world(36.0) + dist_mul
	return Vector2(
		player.home_position.x + cos(orbit) * r,
		player.home_position.y + sin(orbit) * r * 0.85
	)


func _spawn_pet_world_pos(player: BattlePlayer, index: int, total: int, scatter_in_field: bool) -> Vector2:
	var w := _play_width()
	var bottom := _play_bottom()
	if scatter_in_field:
		return Vector2(
			MathUtils.rand_range(40.0, w - 40.0),
			MathUtils.rand_range(PLAY_TOP + GameConfig.scale_world(30.0), bottom - GameConfig.scale_world(30.0))
		)
	var spread := float(index) / float(maxi(1, total)) * TAU + MathUtils.rand_range(-0.35, 0.35)
	var r := MathUtils.rand_range(55.0, 95.0 + float(index) * 14.0)
	return Vector2(
		clampf(player.home_position.x + cos(spread) * r, 30.0, w - 30.0),
		clampf(player.home_position.y + sin(spread) * r * 0.85, PLAY_TOP + GameConfig.scale_world(24.0), bottom - GameConfig.scale_world(24.0))
	)


func _companion_damage(player: BattlePlayer, cfg: Dictionary, lv: int) -> int:
	var mult := float(cfg.get("dmg_mult", 1.0)) * (1.0 + float(maxi(0, lv - 1)) * 0.08)
	return player.get_ability_damage(mult)


func _spawn_companion(type: String, index: int, total: int, player: BattlePlayer) -> Dictionary:
	var is_pet := type == "wolf" or type == "bull"
	var scatter := is_pet and _player_repositioning(player)
	var pos := _spawn_pet_world_pos(player, index, total, scatter) if is_pet else _anchor_near_player(player, index, total, float(GOD_CFG.orbit_dist))
	var cfg_key := "wild_wolf" if type == "wolf" else ("wild_bull" if type == "bull" else "divine_god")
	var cfg := WOLF_CFG if type == "wolf" else (BULL_CFG if type == "bull" else GOD_CFG)
	var lv := player.get_upgrade_level(cfg_key)
	return {
		"type": type,
		"is_pet": is_pet,
		"pos": pos,
		"slot": index,
		"state": "idle",
		"atk_timer": MathUtils.rand_range(0.0, 0.4),
		"charge_timer": 0.0,
		"charge_target": Vector2.ZERO,
		"charge_hit": {},
		"walk_phase": MathUtils.rand_range(0.0, TAU),
		"facing": 1.0,
		"attack_timer": 0.0,
		"lv": lv,
		"damage": _companion_damage(player, cfg, lv),
		"sprite": null,
	}


func _ensure_companions(player: BattlePlayer) -> void:
	var specs := [
		{"id": "wild_wolf", "type": "wolf"},
		{"id": "wild_bull", "type": "bull"},
		{"id": "divine_god", "type": "god"},
	]
	for spec in specs:
		var need := _get_desired_pet_count(player, spec.id)
		var list: Array = []
		for c in companions:
			if str(c.type) == spec.type:
				list.append(c)
		while list.size() < need:
			var c := _spawn_companion(spec.type, list.size(), need, player)
			companions.append(c)
			list.append(c)
		while list.size() > need:
			var rem := -1
			for i in range(companions.size()):
				if str(companions[i].type) == spec.type:
					rem = i
					break
			if rem >= 0:
				var removed = companions[rem]
				if removed.sprite and is_instance_valid(removed.sprite):
					removed.sprite.queue_free()
				companions.remove_at(rem)
			list = []
			for c in companions:
				if str(c.type) == spec.type:
					list.append(c)


func _spawn_thunder_strikes(player: BattlePlayer, monsters: Array) -> void:
	var lv := player.get_upgrade_level("heavenly_thunder")
	if lv <= 0:
		return
	var cfg := THUNDER_CFG
	var count := lv
	var w := _play_width()
	var bottom := _play_bottom()
	for i in range(count):
		var target := Vector2.ZERO
		if not monsters.is_empty():
			var m = monsters[randi() % monsters.size()]
			if is_instance_valid(m):
				target = m.global_position + Vector2(
					MathUtils.rand_range(-20.0, 20.0),
					MathUtils.rand_range(-16.0, 16.0)
				)
		if target == Vector2.ZERO:
			target = player.home_position + Vector2(
				MathUtils.rand_range(-80.0, 80.0),
				MathUtils.rand_range(-60.0, 60.0)
			)
		target.x = clampf(target.x, 30.0, w - 30.0)
		target.y = clampf(target.y, PLAY_TOP + GameConfig.scale_world(20.0), bottom - GameConfig.scale_world(20.0))
		var dmg_mult := float(cfg.dmg_mult) * (1.0 + float(maxi(0, lv - 1)) * 0.06)
		thunder_bolts.append(_with_upgrade_fx_layer({
			"pos": target,
			"phase": "warn",
			"timer": float(cfg.warn_time),
			"radius": GameConfig.scale_world(float(cfg.radius) + float(lv) * 4.0) * FX_SCALE,
			"damage": player.get_ability_damage(dmg_mult),
			"sky_y": float(cfg.sky_y),
			"bolt_points": null,
			"explode_max": float(cfg.explode_time),
		}, "heavenly_thunder"))


func _generate_thunder_bolt_path(gx: float, gy: float, sky_y: float) -> Array:
	var points: Array = [Vector2(gx, sky_y)]
	var steps := 14
	for i in range(1, steps):
		var t := float(i) / float(steps)
		points.append(Vector2(
			gx + MathUtils.rand_range(-22.0, 22.0) * (1.0 - t * 0.45),
			lerpf(sky_y, gy, t) + MathUtils.rand_range(-10.0, 10.0)
		))
	points.append(Vector2(gx, gy))
	return points


func _update_thunder(delta: float, player: BattlePlayer, monsters: Array) -> void:
	var lv := player.get_upgrade_level("heavenly_thunder")
	if lv <= 0:
		thunder_bolts.clear()
		return
	var cfg := THUNDER_CFG
	thunder_timer -= delta
	if thunder_timer <= 0.0:
		_spawn_thunder_strikes(player, monsters)
		thunder_timer = float(cfg.interval)
	for i in range(thunder_bolts.size() - 1, -1, -1):
		var t = thunder_bolts[i]
		t.timer -= delta
		match str(t.phase):
			"warn":
				if float(t.timer) <= 0.0:
					t.phase = "bolt"
					t.timer = float(cfg.bolt_time)
					t.bolt_points = _generate_thunder_bolt_path(t.pos.x, t.pos.y, float(t.sky_y))
			"bolt":
				if float(t.timer) <= 0.0:
					t.phase = "explode"
					t.timer = float(t.explode_max)
					_summon_aoe_damage(t.pos, float(t.radius), int(t.get("damage", 0)), Color("#ffe878"))
					if battle:
						battle.shake_camera(1.8 + float(lv) * 0.15, 0.07)
						if battle.particles:
							for j in range(18):
								var a := randf() * TAU
								var sp := randf_range(100.0, 280.0)
								battle.particles.emit_particle(
									t.pos.x, t.pos.y,
									cos(a) * sp, sin(a) * sp,
									randf_range(0.2, 0.45), randf_range(6.0, 12.0) * FX_SCALE * GameConfig.get_world_scale(),
									Color("#ffe878"), 90.0, true, true
								)
			"explode":
				if float(t.timer) <= 0.0:
					t.phase = "done"
		if str(t.phase) == "done":
			thunder_bolts.remove_at(i)


func _update_wolf(c: Dictionary, delta: float, player: BattlePlayer, monsters: Array) -> void:
	if str(c.get("state", "idle")) == "attacking":
		c["attack_timer"] = float(c.get("attack_timer", 0.0)) - delta
		if float(c.attack_timer) <= 0.0:
			c.state = "idle"
		return
	c.walk_phase = float(c.walk_phase) + delta * 9.0
	var target = null
	var best := float(WOLF_CFG.aggro)
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var d: float = Vector2(c.pos).distance_to(m.global_position)
		if d < best:
			best = d
			target = m
	if target == null:
		return
	var cpos: Vector2 = c.pos
	c.facing = 1.0 if target.global_position.x >= cpos.x else -1.0
	var dist: float = cpos.distance_to(target.global_position)
	if dist > float(WOLF_CFG.atk_range):
		var dir: Vector2 = (target.global_position - cpos).normalized()
		cpos += dir * float(WOLF_CFG.speed) * delta
		c.pos = cpos
	else:
		c.atk_timer = float(c.atk_timer) - delta
		if float(c.atk_timer) <= 0.0:
			c.atk_timer = float(WOLF_CFG.atk_cd)
			c.state = "attacking"
			c.attack_timer = _companion_attack_anim_duration(c)
			_summon_deal_damage(target, int(c.get("damage", 0)), Color("#c8d8b0"), c.pos)


func _circles_collide(ax: float, ay: float, ar: float, bx: float, by: float, br: float) -> bool:
	return Vector2(ax, ay).distance_to(Vector2(bx, by)) <= ar + br


func _update_bull(c: Dictionary, delta: float, player: BattlePlayer, monsters: Array) -> void:
	if str(c.state) == "charging":
		c.charge_timer = float(c.charge_timer) - delta
		var tx := float(c.charge_target.x)
		var ty := float(c.charge_target.y)
		var cpos: Vector2 = c.pos
		var dx: float = tx - cpos.x
		var dy: float = ty - cpos.y
		var len := maxf(0.001, sqrt(dx * dx + dy * dy))
		c.facing = 1.0 if dx >= 0.0 else -1.0
		var step := float(BULL_CFG.charge_speed) * delta
		c.pos += Vector2(dx / len, dy / len) * step
		for m in monsters:
			if not is_instance_valid(m) or m.get("alive") == false:
				continue
			var key := str(m.get_instance_id())
			if c.charge_hit.has(key):
				continue
			var hit_r := 13.0
			if m.has_method("get_hitbox_radius"):
				hit_r = m.get_hitbox_radius()
			if not _circles_collide(c.pos.x, c.pos.y, 32.0, m.global_position.x, m.global_position.y, hit_r):
				continue
			c.charge_hit[key] = true
			_summon_deal_damage(m, int(c.get("damage", 0)), Color("#e8b878"), c.pos)
		if c.pos.distance_to(Vector2(tx, ty)) < 18.0 or float(c.charge_timer) <= 0.0:
			c.state = "idle"
			c.atk_timer = float(BULL_CFG.idle_cd)
		return
	c.atk_timer = float(c.atk_timer) - delta
	if float(c.atk_timer) > 0.0:
		return
	var target = null
	var best := float(BULL_CFG.aggro)
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var d: float = Vector2(c.pos).distance_to(m.global_position)
		if d < best:
			best = d
			target = m
	if target == null:
		return
	var cpos: Vector2 = c.pos
	c.facing = 1.0 if target.global_position.x >= cpos.x else -1.0
	c.state = "charging"
	c.charge_target = target.global_position
	c.charge_timer = float(BULL_CFG.charge_time)
	c.charge_hit = {}
	var lv := int(c.lv)
	c.damage = player.get_ability_damage(float(BULL_CFG.charge_dmg_mult) * (1.0 + float(maxi(0, lv - 1)) * 0.08))


func _fire_god_sword(c: Dictionary, monsters: Array) -> void:
	if monsters.is_empty():
		return
	var sorted: Array = []
	for m in monsters:
		if is_instance_valid(m) and m.get("alive") != false:
			sorted.append(m)
	if sorted.is_empty():
		return
	sorted.sort_custom(func(a, b): return c.pos.distance_to(a.global_position) < c.pos.distance_to(b.global_position))
	var target = sorted[0]
	var ang: float = Vector2(c.pos).angle_to_point(target.global_position)
	god_swords.append(_with_upgrade_fx_layer({
		"pos": c.pos + Vector2(0.0, -18.0),
		"vel": Vector2(cos(ang), sin(ang)) * float(GOD_CFG.sword_speed),
		"rot": ang,
		"target_id": target.get_instance_id(),
		"tx": target.global_position.x,
		"ty": target.global_position.y,
		"damage": int(c.get("damage", 0)),
		"life": 2.5,
		"hit_target": false,
	}, "divine_god"))


func _update_god(c: Dictionary, delta: float, player: BattlePlayer, monsters: Array) -> void:
	var god_count := _get_desired_pet_count(player, "divine_god")
	var anchor := _anchor_near_player(player, int(c.slot), god_count, float(GOD_CFG.orbit_dist))
	c.pos = c.pos.lerp(anchor, delta * 2.2)
	c.atk_timer = float(c.atk_timer) - delta
	if float(c.atk_timer) <= 0.0:
		c.atk_timer = float(GOD_CFG.atk_interval)
		_fire_god_sword(c, monsters)


func _update_god_swords(delta: float, monsters: Array) -> void:
	for i in range(god_swords.size() - 1, -1, -1):
		var s = god_swords[i]
		s.life = float(s.life) - delta
		s.pos += s.vel * delta
		if not bool(s.hit_target):
			for m in monsters:
				if not is_instance_valid(m) or m.get("alive") == false:
					continue
				if m.get_instance_id() != int(s.target_id):
					continue
				var hit_r := 13.0
				if m.has_method("get_hitbox_radius"):
					hit_r = m.get_hitbox_radius()
				if not _circles_collide(s.pos.x, s.pos.y, 16.0, m.global_position.x, m.global_position.y, hit_r):
					continue
				s.hit_target = true
				_summon_deal_damage(m, int(s.get("damage", 0)), Color("#fff8c8"), s.pos)
				break
		if not bool(s.hit_target) and s.pos.distance_to(Vector2(float(s.tx), float(s.ty))) < 24.0:
			s.life = 0.0
		if float(s.life) <= 0.0 or bool(s.hit_target):
			god_swords.remove_at(i)


func _update_companions(delta: float, player: BattlePlayer, monsters: Array) -> void:
	_ensure_companions(player)
	var w := _play_width()
	var bottom := _play_bottom()
	var freeze_wolf_bull := _player_repositioning(player)
	for c in companions:
		var upgrade_id := _upgrade_id_for_type(str(c.type))
		c.lv = player.get_upgrade_level(upgrade_id)
		if int(c.lv) <= 0:
			continue
		var cfg := WOLF_CFG if str(c.type) == "wolf" else (BULL_CFG if str(c.type) == "bull" else GOD_CFG)
		c.damage = _companion_damage(player, cfg, int(c.lv))
		c.pos.x = clampf(c.pos.x, 20.0, w - 20.0)
		c.pos.y = clampf(c.pos.y, PLAY_TOP + GameConfig.scale_world(16.0), bottom - GameConfig.scale_world(16.0))
		if freeze_wolf_bull and str(c.type) in ["wolf", "bull"]:
			continue
		match str(c.type):
			"wolf":
				_update_wolf(c, delta, player, monsters)
			"bull":
				_update_bull(c, delta, player, monsters)
			"god":
				_update_god(c, delta, player, monsters)
	var i := companions.size() - 1
	while i >= 0:
		var c = companions[i]
		var key := _upgrade_id_for_type(str(c.type))
		if player.get_upgrade_level(key) <= 0:
			if c.sprite and is_instance_valid(c.sprite):
				c.sprite.queue_free()
			companions.remove_at(i)
		i -= 1
	if not god_swords.is_empty():
		_update_god_swords(delta, monsters)


func _companion_attack_anim_duration(c: Dictionary) -> float:
	var sprite: AnimatedSprite2D = c.get("sprite")
	if sprite == null or sprite.sprite_frames == null:
		return 0.45
	var frames: SpriteFrames = sprite.sprite_frames
	var anim := SpriteHelper.ANIM_ATTACK01 if frames.has_animation(SpriteHelper.ANIM_ATTACK01) else SpriteHelper.ANIM_ATTACK
	if not frames.has_animation(anim):
		return 0.45
	var count := frames.get_frame_count(anim)
	if count <= 0:
		return 0.45
	var speed := frames.get_animation_speed(anim)
	if speed <= 0.0:
		speed = 12.0
	return float(count) / speed


func _create_companion_sprite(type: String) -> AnimatedSprite2D:
	var upgrade_id := _upgrade_id_for_type(type)
	var def := GameConfig.get_upgrade(upgrade_id)
	var folder := str(def.get("effect_name", "Werewolf"))
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = SpriteHelper.build_character_frames(folder, folder)
	SpriteHelper.apply_pixel_art(anim)
	var scale_val := float(GameConfig.get_tuning("monster_sprite_scale", 1.0))
	var size_mul := 1.1 if type in ["wolf", "bull"] else 0.85
	anim.scale = Vector2.ONE * SpriteHelper.pixel_scale(scale_val * size_mul)
	if anim.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim.play(SpriteHelper.ANIM_IDLE)
	companions_container.add_child(anim)
	return anim


func _sync_companion_visuals() -> void:
	for c in companions:
		if c.sprite == null or not is_instance_valid(c.sprite):
			c.sprite = _create_companion_sprite(str(c.type))
		var sprite: AnimatedSprite2D = c.sprite
		sprite.global_position = c.pos
		sprite.flip_h = float(c.facing) < 0.0
		if str(c.type) == "wolf":
			var frames: SpriteFrames = sprite.sprite_frames
			if str(c.get("state", "idle")) == "attacking":
				var attack_anim := SpriteHelper.ANIM_ATTACK01 if frames.has_animation(SpriteHelper.ANIM_ATTACK01) else SpriteHelper.ANIM_ATTACK
				if frames.has_animation(attack_anim) and sprite.animation != attack_anim:
					sprite.play(attack_anim)
			elif not SpriteHelper.is_playing_priority_anim(sprite):
				var moving := false
				if battle and battle.spawner:
					var chase_target = null
					var chase_best := float(WOLF_CFG.aggro)
					for m in battle.spawner.get_active_monsters():
						if not is_instance_valid(m) or m.get("alive") == false:
							continue
						var d: float = c.pos.distance_to(m.global_position)
						if d < chase_best:
							chase_best = d
							chase_target = m
					if chase_target != null:
						moving = chase_best > float(WOLF_CFG.atk_range)
				var want := SpriteHelper.ANIM_WALK if moving and frames.has_animation(SpriteHelper.ANIM_WALK) else SpriteHelper.ANIM_IDLE
				if sprite.animation != want:
					sprite.play(want)
		elif str(c.type) == "bull":
			var frames: SpriteFrames = sprite.sprite_frames
			if str(c.state) == "charging":
				var charge_time := float(BULL_CFG.charge_time)
				var elapsed := charge_time - float(c.charge_timer)
				if elapsed < _companion_attack_anim_duration(c):
					var attack_anim := SpriteHelper.ANIM_ATTACK01 if frames.has_animation(SpriteHelper.ANIM_ATTACK01) else SpriteHelper.ANIM_ATTACK
					if frames.has_animation(attack_anim):
						if sprite.animation != attack_anim or not sprite.is_playing():
							sprite.play(attack_anim)
				elif frames.has_animation(SpriteHelper.ANIM_WALK) and sprite.animation != SpriteHelper.ANIM_WALK:
					sprite.play(SpriteHelper.ANIM_WALK)
			elif not SpriteHelper.is_playing_priority_anim(sprite):
				if frames.has_animation(SpriteHelper.ANIM_IDLE) and sprite.animation != SpriteHelper.ANIM_IDLE:
					sprite.play(SpriteHelper.ANIM_IDLE)


func _clear_companion_sprites() -> void:
	if companions_container == null:
		return
	for child in companions_container.get_children():
		child.queue_free()


func _draw_thunder_bolt_path(canvas: Node2D, points: Array, alpha: float, width: float) -> void:
	if points.size() < 2:
		return
	var offset := -canvas.global_position
	for pass_idx in range(2):
		var col := Color("#e8fcff", alpha) if pass_idx == 0 else Color("#ffffff", alpha)
		var line_w := width if pass_idx == 0 else maxf(1.0, width * 0.45)
		for i in range(points.size() - 1):
			canvas.draw_line(points[i] + offset, points[i + 1] + offset, col, line_w)


func _draw_thunder_explosion(canvas: Node2D, t: Dictionary) -> void:
	var cx: float = t.pos.x
	var cy: float = t.pos.y
	var max_t := float(t.explode_max)
	var prog := clampf(1.0 - float(t.timer) / max_t, 0.0, 1.0)
	var r := float(t.radius) * (0.25 + prog * 0.85)
	var alpha := 1.0 - prog * 0.85
	var offset := -canvas.global_position
	var local: Vector2 = Vector2(cx, cy) + offset
	canvas.draw_circle(local, r * 0.55, Color(1.0, 1.0, 0.94, 0.95 * alpha))
	canvas.draw_circle(local, r, Color(1.0, 0.7, 0.2, 0.5 * alpha))
	canvas.draw_arc(local, r * prog, 0.0, TAU, 40, Color(1.0, 0.94, 0.7, alpha * 0.85), 6.0)
	canvas.draw_arc(local, r * prog * 0.7, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, alpha * 0.5), 3.0)


func _draw_thunder(canvas: Node2D, below_monsters: bool) -> void:
	var cfg := THUNDER_CFG
	var bolt_dur := float(cfg.bolt_time)
	var offset := -canvas.global_position
	for t in thunder_bolts:
		if not _fx_on_layer(t, below_monsters):
			continue
		var cx: float = t.pos.x
		var cy: float = t.pos.y
		match str(t.phase):
			"warn":
				var pulse := 0.4 + sin(Time.get_ticks_msec() * 0.025) * 0.2
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				canvas.draw_arc(
					Vector2(cx, cy) + offset,
					float(t.radius) * 0.72,
					0.0, TAU, 40,
					Color(1.0, 0.91, 0.47, pulse), 4.0
				)
				canvas.draw_circle(
					Vector2(cx, cy) + offset,
					float(t.radius) * 0.58,
					Color(1.0, 0.9, 0.47, 0.2 * pulse)
				)
			"bolt":
				if t.bolt_points:
					var bolt_prog := clampf(1.0 - float(t.timer) / bolt_dur, 0.0, 1.0)
					var vis_count := maxi(2, int(floor(float(t.bolt_points.size()) * bolt_prog)))
					var vis_pts: Array = t.bolt_points.slice(0, vis_count)
					_draw_thunder_bolt_path(canvas, vis_pts, 0.95, GameConfig.scale_world(9.0) * FX_SCALE)
					if bolt_prog >= 0.95:
						canvas.draw_circle(Vector2(cx, cy) + offset, GameConfig.scale_world(28.0) * FX_SCALE, Color(1.0, 1.0, 1.0, 0.9))
			"explode":
				if t.bolt_points:
					_draw_thunder_bolt_path(canvas, t.bolt_points, 0.35, GameConfig.scale_world(5.0) * FX_SCALE)
				_draw_thunder_explosion(canvas, t)


func _draw_god_sword(canvas: Node2D, s: Dictionary) -> void:
	var pos: Vector2 = s.pos
	var rot: float = float(s.rot) + PI * 0.5
	var offset := -canvas.global_position
	var fx_s := FX_SCALE
	canvas.draw_set_transform(pos + offset, rot, Vector2.ONE)
	canvas.draw_rect(Rect2(-3.0 * fx_s, -14.0 * fx_s, 6.0 * fx_s, 28.0 * fx_s), Color("#fffce8"))
	canvas.draw_rect(Rect2(-5.0 * fx_s, 10.0 * fx_s, 10.0 * fx_s, 6.0 * fx_s), Color("#ffd860"))
	canvas.draw_rect(Rect2(-2.0 * fx_s, -18.0 * fx_s, 4.0 * fx_s, 6.0 * fx_s), Color("#c8a040"))
	canvas.draw_circle(Vector2.ZERO, 10.0 * fx_s, Color(1.0, 0.95, 0.6, 0.35))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
