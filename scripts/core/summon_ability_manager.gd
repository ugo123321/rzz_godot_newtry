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

# Phase 4 v6 召唤实体（独立于 v5 companions 数组）
# 每个 entry: {
#   "kind": "king/god/gorilla/thunder/bear/snake/fire",
#   "pos": Vector2, "atk_timer": float, "atk_interval": float,
#   "atk_mult": float, "range_px": float, "element": String,
#   "mechanic": String, "p1": float, "p2": float,
#   "follow_anchor_index": int,
#   "projectiles": Array  # for ranged_aoe / random_aoe in-flight bolts
# }
var v6_companions: Array = []
# 共享的 v6 召唤投射物（god_sword 类、aoe 弹道）
var v6_projectiles: Array = []
# Isaac 式延迟尾随：记录玩家最近若干帧位置，每只召唤物按 index 取不同回溯偏移
const TRAIL_HISTORY_MAX := 240         # 2s buffer @ 120fps；够 ~12 只召唤 × 20 frame delay
const TRAIL_FRAME_DELAY_PER_SLOT := 8  # 每只召唤物比前一只多回溯 8 帧（~133ms @60fps）
var _player_trail: Array = []          # Vector2 ring buffer，新 push 在尾部
# Sheet5 sr=45 规格（同 rewards_v6.json 中的 special_values）：写死避免每次重新查
const V6_SUMMON_SPEC: Dictionary = {
	"summon_king":     {"kind": "king",     "atk_mult": 2.5, "interval": 2.0, "range": 600.0, "element": "",        "mechanic": "ranged_aoe",    "p1": 200.0, "p2": 0.0,  "count_field": "summon_king_count"},
	"summon_god":      {"kind": "god",      "atk_mult": 1.8, "interval": 1.5, "range": 500.0, "element": "",        "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_god_count"},
	"summon_gorilla":  {"kind": "gorilla",  "atk_mult": 1.0, "interval": 1.0, "range": 400.0, "element": "",        "mechanic": "ranged_taunt",  "p1": 10.0,  "p2": 3.0,  "count_field": "summon_gorilla_count"},
	"summon_thunder":  {"kind": "thunder",  "atk_mult": 1.2, "interval": 3.0, "range": 0.0,   "element": "thunder", "mechanic": "random_aoe",    "p1": 0.0,   "p2": 0.0,  "count_field": "summon_thunder_count"},
	"summon_bear":     {"kind": "bear",     "atk_mult": 1.0, "interval": 1.0, "range": 500.0, "element": "ice",     "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_bear_count"},
	"summon_snake":    {"kind": "snake",    "atk_mult": 1.0, "interval": 1.0, "range": 500.0, "element": "poison",  "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_snake_count"},
	"summon_fire":     {"kind": "fire",     "atk_mult": 1.2, "interval": 1.5, "range": 500.0, "element": "fire",    "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_fire_count"},
}


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
		v6_companions.clear()
	thunder_bolts.clear()
	god_swords.clear()
	v6_projectiles.clear()
	_player_trail.clear()


func has_active_fx() -> bool:
	return not thunder_bolts.is_empty() or not god_swords.is_empty() or not v6_projectiles.is_empty()


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
	# 记录玩家轨迹（用于 v6 召唤物的延迟尾随）
	_player_trail.append(player.global_position)
	if _player_trail.size() > TRAIL_HISTORY_MAX:
		_player_trail.remove_at(0)
	if player.get_upgrade_level("heavenly_thunder") > 0:
		_update_thunder(delta, player, monsters)
	if player.get_upgrade_level("wild_wolf") > 0 \
			or player.get_upgrade_level("wild_bull") > 0 \
			or player.get_upgrade_level("divine_god") > 0:
		_update_companions(delta, player, monsters)
	# Phase 4 v6 召唤系统：按 player.summon_*_count 自驱
	_update_v6_summons(delta, player, monsters)
	_sync_companion_visuals()


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	_draw_thunder(canvas, below_monsters)
	for s in god_swords:
		if not _fx_on_layer(s, below_monsters):
			continue
		_draw_god_sword(canvas, s)
	# v6 召唤实体与投射物
	if not below_monsters:
		_draw_v6_companions(canvas)
		_draw_v6_projectiles(canvas)


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


func _summon_deal_damage(m, damage: int, color: Color, from_pos: Vector2, source: String = "summon_hit", element: String = "") -> void:
	if m == null or not is_instance_valid(m) or m.get("alive") == false:
		return
	# 构造 DamageInfo (category=summon)。当 battle.player 不可用时回退到 legacy int 路径
	var info: DamageInfo = null
	if battle and battle.player and battle.player.has_method("make_damage"):
		info = battle.player.make_damage(source, 1.0, "summon", element, false, false)
		info.raw_amount = damage
	var result: Dictionary = {}
	if info != null and m.has_method("take_damage_info"):
		result = m.take_damage_info(info, from_pos)
	elif m.has_method("take_damage"):
		result = m.take_damage(damage, from_pos)
	if result.is_empty():
		return
	if battle and battle.combat and int(result.get("damage", 0)) > 0:
		battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false)
		if battle.player and battle.player.has_method("on_summon_hit"):
			battle.player.on_summon_hit()
	# Sheet4 元素状态注入
	if info != null and int(result.get("damage", 0)) > 0:
		ElementEffectManager.try_apply(m, info, battle.player)
	if bool(result.get("started_dying", false)):
		EventBus.monster_killed.emit(m)


func _summon_aoe_damage(center: Vector2, radius: float, damage: int, color: Color, source: String = "summon_aoe", element: String = "") -> void:
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
		_summon_deal_damage(m, damage, color, center, source, element)


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
					_summon_aoe_damage(t.pos, float(t.radius), int(t.get("damage", 0)), Color("#ffe878"), "summon_thunder", "thunder")
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
			_summon_deal_damage(target, int(c.get("damage", 0)), Color("#c8d8b0"), c.pos, "summon_wolf", "")


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
			_summon_deal_damage(m, int(c.get("damage", 0)), Color("#e8b878"), c.pos, "summon_bull", "")
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
				_summon_deal_damage(m, int(s.get("damage", 0)), Color("#fff8c8"), s.pos, "summon_god", "")
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


# =========================================================================
# Phase 4 v6 召唤系统
# =========================================================================

# 同步 v6 召唤数量：按 player.summon_*_count 字段，少则 spawn，多则砍。
func _sync_v6_summon_count(player: BattlePlayer) -> void:
	for upgrade_id in V6_SUMMON_SPEC.keys():
		var spec: Dictionary = V6_SUMMON_SPEC[upgrade_id]
		var desired: int = int(player.get(spec.count_field))
		# 数当前同 kind 的数量
		var existing: int = 0
		for c in v6_companions:
			if str(c.get("kind", "")) == spec.kind:
				existing += 1
		while existing < desired:
			_spawn_v6_summon(spec, player)
			existing += 1
		while existing > desired:
			for i in range(v6_companions.size() - 1, -1, -1):
				if str(v6_companions[i].get("kind", "")) == spec.kind:
					v6_companions.remove_at(i)
					existing -= 1
					break


func _spawn_v6_summon(spec: Dictionary, player: BattlePlayer) -> void:
	v6_companions.append({
		"kind": spec.kind,
		"pos": player.global_position + Vector2(0, -40),
		"vel": Vector2.ZERO,
		"atk_timer": MathUtils.rand_range(0.0, float(spec.interval)),
		"atk_interval": float(spec.interval),
		"atk_mult": float(spec.atk_mult),
		"range_px": float(spec.range),
		"element": str(spec.element),
		"mechanic": str(spec.mechanic),
		"p1": float(spec.p1),
		"p2": float(spec.p2),
		"taunt_cd_timer": 0.0,  # ranged_taunt 用
	})


func _update_v6_summons(delta: float, player: BattlePlayer, monsters: Array) -> void:
	_sync_v6_summon_count(player)
	if v6_companions.is_empty() and v6_projectiles.is_empty():
		return
	# sr=44 summon_pact buff：体型 / 攻速
	var size_factor: float = 1.0 + float(player.summon_size_pct)
	var atk_speed_factor: float = 1.0 + float(player.summon_atk_speed_pct)
	# 跟随玩家身后（环形 anchor）
	var total: int = v6_companions.size()
	for i in range(total):
		var c: Dictionary = v6_companions[i]
		var anchor := _v6_anchor_for(player, i, total)
		# 平滑跟随
		var to: Vector2 = anchor - Vector2(c.pos)
		# 锚点本身已经是延迟的历史点，跟随速度放快让召唤物能贴上历史位置（延迟感来自 anchor，不来自速度）
		var step: float = minf(to.length(), 600.0 * delta)
		c.pos = Vector2(c.pos) + (to.normalized() * step if to.length() > 0.5 else Vector2.ZERO)
		# 攻击计时
		c.atk_timer = float(c.atk_timer) - delta * atk_speed_factor
		if float(c.atk_timer) <= 0.0:
			c.atk_timer = float(c.atk_interval)
			_v6_summon_attack(c, player, monsters, size_factor)
		v6_companions[i] = c
	# 投射物推进
	_update_v6_projectiles(delta, player)


# v6 召唤跟随位置：以撒式延迟链—第 index 个跟在玩家身后 (index+1)*delay 帧
func _v6_anchor_for(player: BattlePlayer, index: int, _total: int) -> Vector2:
	if _player_trail.is_empty():
		return player.global_position
	var look_back: int = (index + 1) * TRAIL_FRAME_DELAY_PER_SLOT
	var sample_idx: int = _player_trail.size() - 1 - look_back
	if sample_idx < 0:
		sample_idx = 0
	return _player_trail[sample_idx]


# 攻击主分发
func _v6_summon_attack(c: Dictionary, player: BattlePlayer, monsters: Array, size_factor: float) -> void:
	var mechanic := str(c.get("mechanic", "ranged_single"))
	var atk_mult: float = float(c.get("atk_mult", 1.0))
	var damage: int = player.get_ability_damage(atk_mult)
	var source := "summon_" + str(c.get("kind", "unknown"))
	var element := str(c.get("element", ""))
	match mechanic:
		"ranged_single":
			var target = _v6_nearest_in_range(c, monsters)
			if target != null:
				_v6_spawn_projectile(c, target.global_position, damage, source, element, "single", 0.0)
		"ranged_aoe":
			var target2 = _v6_nearest_in_range(c, monsters)
			if target2 != null:
				_v6_spawn_projectile(c, target2.global_position, damage, source, element, "aoe", float(c.get("p1", 200.0)))
		"ranged_taunt":
			# 嘲讽机制：CD（p1 秒）到期一次，期间 duration（p2 秒）让 N 怪盯着 gorilla 而不是玩家
			c.taunt_cd_timer = float(c.taunt_cd_timer) - float(c.atk_interval)
			if float(c.taunt_cd_timer) <= 0.0:
				c.taunt_cd_timer = float(c.get("p1", 10.0))
				var duration: float = float(c.get("p2", 3.0))
				_v6_apply_taunt(c, monsters, duration)
			# 同时也输出一次单体伤害
			var target3 = _v6_nearest_in_range(c, monsters)
			if target3 != null:
				_v6_spawn_projectile(c, target3.global_position, damage, source, element, "single", 0.0)
		"random_aoe":
			# 在战场上随机砸雷
			var w: float = _play_width()
			var h: float = _play_bottom()
			var fall_pos := Vector2(
				MathUtils.rand_range(40.0, w - 40.0),
				MathUtils.rand_range(PLAY_TOP + 24.0, h - 24.0)
			)
			# 直接落点 AOE，无投射物
			_v6_apply_aoe_hit(fall_pos, 80.0, damage, player, source, element)


func _v6_nearest_in_range(c: Dictionary, monsters: Array):
	var best = null
	var best_d := float(c.get("range_px", 500.0))
	var best_d2 := best_d * best_d
	var origin: Vector2 = c.pos
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var d2: float = origin.distance_squared_to(m.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = m
	return best


func _v6_apply_taunt(c: Dictionary, monsters: Array, duration: float) -> void:
	# 简化的嘲讽：把附近怪的 taunt_target 字段指向 c.pos（monster.gd 若读取则跟向 gorilla）
	# 当 monster.gd 没接此字段时退化为无效果；后续相再补
	for m in monsters:
		if not is_instance_valid(m):
			continue
		if "taunt_target_pos" in m:
			m.taunt_target_pos = c.pos
			m.taunt_timer = duration


func _v6_spawn_projectile(c: Dictionary, target_pos: Vector2, damage: int, source: String, element: String, kind: String, aoe_radius: float) -> void:
	var dir: Vector2 = (target_pos - Vector2(c.pos)).normalized()
	v6_projectiles.append({
		"pos": Vector2(c.pos),
		"vel": dir * 480.0,
		"target_pos": target_pos,
		"life": 1.2,
		"damage": damage,
		"source": source,
		"element": element,
		"kind": kind,       # "single" or "aoe"
		"aoe_radius": aoe_radius,
		"color": _v6_element_color(element),
		"summon_kind": str(c.get("kind", "")),
	})


func _v6_element_color(element: String) -> Color:
	match element:
		"fire":    return Color(1.0, 0.55, 0.25, 1.0)
		"ice":     return Color(0.6, 0.85, 1.0, 1.0)
		"thunder": return Color(1.0, 0.95, 0.35, 1.0)
		"poison":  return Color(0.55, 0.95, 0.45, 1.0)
		_:         return Color(0.95, 0.95, 0.85, 1.0)


func _update_v6_projectiles(delta: float, player: BattlePlayer) -> void:
	for i in range(v6_projectiles.size() - 1, -1, -1):
		var p: Dictionary = v6_projectiles[i]
		p.pos = Vector2(p.pos) + Vector2(p.vel) * delta
		p.life = float(p.life) - delta
		# 碰撞检测：扫描 monsters 看是否命中
		var hit_monster = _v6_projectile_hit_check(p)
		if hit_monster != null:
			if str(p.kind) == "aoe":
				_v6_apply_aoe_hit(Vector2(p.pos), float(p.aoe_radius), int(p.damage), player, str(p.source), str(p.element))
			else:
				_v6_apply_single_hit(hit_monster, int(p.damage), Vector2(p.pos), player, str(p.source), str(p.element))
			v6_projectiles.remove_at(i)
			continue
		if float(p.life) <= 0.0:
			v6_projectiles.remove_at(i)
			continue
		v6_projectiles[i] = p


func _v6_projectile_hit_check(p: Dictionary):
	if battle == null or battle.spawner == null:
		return null
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if Vector2(p.pos).distance_to(m.global_position) <= hit_r + 6.0:
			return m
	return null


func _v6_apply_single_hit(monster, damage: int, from_pos: Vector2, player: BattlePlayer, source: String, element: String) -> void:
	_summon_deal_damage(monster, damage, _v6_element_color(element), from_pos, source, element)
	_maybe_summon_burst(source, from_pos)


func _v6_apply_aoe_hit(center: Vector2, radius: float, damage: int, player: BattlePlayer, source: String, element: String) -> void:
	if battle == null or battle.spawner == null:
		return
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if center.distance_to(m.global_position) <= radius + hit_r:
			_summon_deal_damage(m, damage, _v6_element_color(element), center, source, element)
	_maybe_summon_burst(source, center)


# source 形如 "summon_gorilla"/"summon_god" 等，提取 kind 后调爆点
func _maybe_summon_burst(source: String, pos: Vector2) -> void:
	if not source.begins_with("summon_"):
		return
	var kind := source.substr(7)
	if SUMMON_DRAW_DATA.has(kind):
		_summon_hit_burst(pos, kind)


# =========================================================================
# v6 召唤像素占位绘制
# =========================================================================

func _draw_v6_companions(canvas: Node2D) -> void:
	for c in v6_companions:
		var kind := str(c.get("kind", ""))
		var t := Time.get_ticks_msec() * 0.001
		var bob := sin(t * 4.0) * 1.5
		# 7 张召唤物全部走数据驱动像素绘制（豪火球术配方）
		if SUMMON_DRAW_DATA.has(kind):
			_draw_pixel_summon_body(canvas, Vector2(c.pos), bob, kind)


func _draw_v6_projectiles(canvas: Node2D) -> void:
	for p in v6_projectiles:
		var summon_kind := str(p.get("summon_kind", ""))
		if SUMMON_DRAW_DATA.has(summon_kind):
			var life_left: float = float(p.get("life", 1.2))
			var age: float = 1.2 - life_left
			_draw_pixel_summon_projectile(canvas, Vector2(p.pos), age, summon_kind)
		else:
			# 未注册的 kind：回退原圆点（不应发生，留作兜底）
			var offset := -canvas.global_position
			var pos: Vector2 = Vector2(p.pos) + offset
			var col: Color = p.get("color", Color.WHITE)
			var r: float = 5.0 if str(p.get("kind", "")) == "aoe" else 3.5
			canvas.draw_circle(pos, r + 2.0, Color(col, 0.35))
			canvas.draw_circle(pos, r, col)


# =============================================================
# === 召唤物像素绘制系统（豪火球术配方，数据驱动）===
# 参考 ability_manager.gd:_draw_pixel_fireball：
#   自定义 set_transform + 多色分层 + 周期闪烁 + 外发光圆晕
# 每张召唤物只需在 SUMMON_DRAW_DATA 填一份配置即可，无需写新函数。
# palette key 含义：9=核心高光 / 1=亮 / 2=中 / 3=深(外圈闪烁) / 4=最外阴影
# pair[0]=base color, pair[1]=flicker color（null 表示该层不闪）
# =============================================================
const SUMMON_DRAW_PIXEL := 3

# kind → 完整配置
var SUMMON_DRAW_DATA := {
	"gorilla": {
		"body_grid": [
			[0, 0, 3, 3, 3, 3, 3, 0, 0],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[3, 2, 1, 9, 1, 9, 1, 2, 3],
			[3, 2, 1, 1, 9, 1, 1, 2, 3],
			[0, 3, 2, 9, 9, 9, 2, 3, 0],
			[3, 2, 2, 2, 2, 2, 2, 2, 3],
			[3, 1, 2, 2, 2, 2, 2, 1, 3],
			[3, 1, 2, 9, 2, 9, 2, 1, 3],
			[3, 1, 2, 2, 2, 2, 2, 1, 3],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[0, 3, 1, 1, 0, 1, 1, 3, 0],
		],
		"rock_grid": [
			[0, 3, 3, 3, 0],
			[3, 2, 1, 2, 3],
			[3, 1, 9, 1, 3],
			[3, 2, 1, 2, 3],
			[0, 3, 2, 3, 0],
		],
		"palette": {
			9: [Color("#ffe0c0"), Color("#fff0d0")],
			1: [Color("#b88050"), Color("#a87040")],
			2: [Color("#7a4f30"), null],
			3: [Color("#4a2f1c"), Color("#3a2418")],
			4: [Color("#2a1a10"), null],
		},
		"body_flicker_ms": 80,
		"rock_flicker_ms": 60,
		"glow_color": Color(0.55, 0.35, 0.2),
		"glow_inner_color": Color(0.35, 0.2, 0.1),
		"glow_r1": 22.0, "glow_r2": 16.0,
		"rock_rot_speed": 7.0, "rock_shadow_r": 9.0,
		"hit_dust_color": Color("#8b6a40"), "hit_debris_color": Color("#3a2818"),
		"hit_dust_count": 18, "hit_debris_count": 10,
		"hit_shake": 5.0, "hit_dur": 0.12,
	},
	"king": {
		"body_grid": [
			[0, 0, 1, 0, 1, 0, 1, 0, 0],
			[0, 1, 9, 1, 9, 1, 9, 1, 0],
			[0, 1, 1, 1, 1, 1, 1, 1, 0],
			[3, 2, 9, 2, 9, 2, 9, 2, 3],
			[3, 2, 1, 1, 1, 1, 1, 2, 3],
			[3, 2, 2, 1, 9, 1, 2, 2, 3],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[3, 1, 2, 2, 9, 2, 2, 1, 3],
			[3, 1, 1, 2, 2, 2, 1, 1, 3],
			[3, 1, 2, 2, 2, 2, 2, 1, 3],
			[0, 3, 1, 0, 0, 0, 1, 3, 0],
		],
		"rock_grid": [
			[0, 1, 1, 1, 0],
			[1, 9, 9, 9, 1],
			[1, 9, 1, 9, 1],
			[1, 9, 9, 9, 1],
			[0, 1, 1, 1, 0],
		],
		"palette": {
			9: [Color("#fffceb"), Color("#ffe898")],
			1: [Color("#ffd860"), Color("#f8c850")],
			2: [Color("#c89028"), null],
			3: [Color("#8a5810"), Color("#6a3810")],
			4: [Color("#4a2808"), null],
		},
		"body_flicker_ms": 100,
		"rock_flicker_ms": 70,
		"glow_color": Color(0.95, 0.75, 0.25),
		"glow_inner_color": Color(0.6, 0.4, 0.1),
		"glow_r1": 24.0, "glow_r2": 16.0,
		"rock_rot_speed": 3.0, "rock_shadow_r": 8.0,
		"hit_dust_color": Color("#ffd860"), "hit_debris_color": Color("#c89028"),
		"hit_dust_count": 22, "hit_debris_count": 12,
		"hit_shake": 6.0, "hit_dur": 0.14,
	},
	"god": {
		"body_grid": [
			[0, 0, 1, 1, 9, 1, 1, 0, 0],
			[0, 1, 0, 0, 9, 0, 0, 1, 0],
			[3, 2, 1, 1, 9, 1, 1, 2, 3],
			[3, 2, 9, 2, 1, 2, 9, 2, 3],
			[0, 3, 2, 1, 1, 1, 2, 3, 0],
			[0, 1, 1, 1, 9, 1, 1, 1, 0],
			[3, 1, 2, 2, 9, 2, 2, 1, 3],
			[3, 1, 2, 2, 9, 2, 2, 1, 3],
			[3, 1, 2, 2, 2, 2, 2, 1, 3],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[0, 0, 3, 0, 0, 0, 3, 0, 0],
		],
		"rock_grid": [
			[0, 0, 9, 0, 0],
			[0, 0, 9, 0, 0],
			[1, 1, 9, 1, 1],
			[0, 0, 9, 0, 0],
			[0, 0, 9, 0, 0],
		],
		"palette": {
			9: [Color("#ffffff"), Color("#fff8a0")],
			1: [Color("#e8e8ff"), null],
			2: [Color("#a8b8d8"), null],
			3: [Color("#5868a8"), Color("#4858a8")],
			4: [Color("#283878"), null],
		},
		"body_flicker_ms": 120,
		"rock_flicker_ms": 80,
		"glow_color": Color(0.9, 0.92, 1.0),
		"glow_inner_color": Color(1.0, 0.95, 0.6),
		"glow_r1": 26.0, "glow_r2": 18.0,
		"rock_rot_speed": 1.5, "rock_shadow_r": 6.0,
		"hit_dust_color": Color("#ffffff"), "hit_debris_color": Color("#fff8a0"),
		"hit_dust_count": 16, "hit_debris_count": 8,
		"hit_shake": 4.5, "hit_dur": 0.12,
	},
	"thunder": {
		"body_grid": [
			[0, 0, 0, 1, 1, 1, 0, 0, 0],
			[0, 0, 1, 9, 9, 9, 1, 0, 0],
			[0, 1, 9, 9, 1, 9, 9, 1, 0],
			[0, 1, 9, 1, 1, 1, 9, 1, 0],
			[3, 2, 1, 1, 9, 1, 1, 2, 3],
			[3, 2, 9, 2, 1, 2, 9, 2, 3],
			[0, 3, 2, 1, 1, 1, 2, 3, 0],
			[3, 1, 2, 9, 9, 9, 2, 1, 3],
			[3, 1, 9, 1, 9, 1, 9, 1, 3],
			[0, 3, 1, 2, 2, 2, 1, 3, 0],
			[0, 0, 3, 0, 0, 0, 3, 0, 0],
		],
		"rock_grid": [
			[1, 9, 9, 0, 0],
			[0, 1, 9, 0, 0],
			[0, 0, 9, 0, 0],
			[0, 0, 9, 1, 0],
			[0, 0, 9, 9, 1],
		],
		"palette": {
			9: [Color("#ffffff"), Color("#c0e0ff")],
			1: [Color("#fff038"), Color("#fff8a8")],
			2: [Color("#c8a818"), null],
			3: [Color("#684818"), Color("#483808")],
			4: [Color("#2a1808"), null],
		},
		"body_flicker_ms": 50,
		"rock_flicker_ms": 40,
		"glow_color": Color(1.0, 0.9, 0.2),
		"glow_inner_color": Color(0.7, 0.85, 1.0),
		"glow_r1": 24.0, "glow_r2": 18.0,
		"rock_rot_speed": 0.0, "rock_shadow_r": 5.0,
		"hit_dust_color": Color("#fff038"), "hit_debris_color": Color("#c0e0ff"),
		"hit_dust_count": 20, "hit_debris_count": 12,
		"hit_shake": 6.5, "hit_dur": 0.15,
	},
	"bear": {
		"body_grid": [
			[0, 1, 0, 0, 0, 0, 0, 1, 0],
			[1, 9, 1, 0, 0, 0, 1, 9, 1],
			[1, 1, 1, 2, 2, 2, 1, 1, 1],
			[0, 1, 2, 1, 1, 1, 2, 1, 0],
			[3, 1, 9, 1, 1, 1, 9, 1, 3],
			[3, 1, 1, 2, 9, 2, 1, 1, 3],
			[0, 3, 1, 9, 2, 9, 1, 3, 0],
			[3, 1, 1, 1, 1, 1, 1, 1, 3],
			[3, 1, 2, 2, 1, 2, 2, 1, 3],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[0, 0, 3, 0, 0, 0, 3, 0, 0],
		],
		"rock_grid": [
			[0, 0, 9, 0, 0],
			[0, 1, 9, 1, 0],
			[1, 9, 9, 9, 1],
			[0, 1, 9, 1, 0],
			[0, 0, 9, 0, 0],
		],
		"palette": {
			9: [Color("#ffffff"), null],
			1: [Color("#f0f8ff"), Color("#ffffff")],
			2: [Color("#a0b8d0"), null],
			3: [Color("#506880"), Color("#405878")],
			4: [Color("#283848"), null],
		},
		"body_flicker_ms": 150,
		"rock_flicker_ms": 100,
		"glow_color": Color(0.85, 0.92, 1.0),
		"glow_inner_color": Color(0.6, 0.75, 0.95),
		"glow_r1": 22.0, "glow_r2": 16.0,
		"rock_rot_speed": 4.0, "rock_shadow_r": 5.0,
		"hit_dust_color": Color("#e0f0ff"), "hit_debris_color": Color("#ffffff"),
		"hit_dust_count": 20, "hit_debris_count": 10,
		"hit_shake": 4.5, "hit_dur": 0.12,
	},
	"snake": {
		"body_grid": [
			[0, 0, 0, 0, 1, 1, 1, 1, 0],
			[0, 0, 0, 1, 1, 9, 1, 1, 0],
			[0, 0, 0, 1, 9, 1, 1, 1, 0],
			[0, 0, 0, 1, 1, 9, 9, 0, 0],
			[0, 0, 1, 2, 2, 2, 1, 0, 0],
			[0, 1, 2, 2, 1, 0, 0, 0, 0],
			[0, 2, 1, 0, 0, 0, 0, 0, 0],
			[1, 2, 0, 0, 0, 0, 0, 0, 0],
			[1, 1, 2, 0, 0, 0, 1, 1, 0],
			[0, 0, 1, 2, 1, 2, 1, 0, 0],
			[0, 0, 0, 1, 1, 1, 0, 0, 0],
		],
		"rock_grid": [
			[0, 0, 1, 0, 0],
			[0, 1, 9, 1, 0],
			[1, 9, 9, 9, 1],
			[1, 9, 9, 9, 1],
			[0, 1, 1, 1, 0],
		],
		"palette": {
			9: [Color("#ff4030"), Color("#ff6050")],
			1: [Color("#80d040"), Color("#a0e858")],
			2: [Color("#508028"), null],
			3: [Color("#284018"), Color("#183008")],
			4: [Color("#102008"), null],
		},
		"body_flicker_ms": 90,
		"rock_flicker_ms": 65,
		"glow_color": Color(0.4, 0.8, 0.2),
		"glow_inner_color": Color(0.5, 0.95, 0.3),
		"glow_r1": 20.0, "glow_r2": 14.0,
		"rock_rot_speed": 2.0, "rock_shadow_r": 6.0,
		"hit_dust_color": Color("#80d040"), "hit_debris_color": Color("#284018"),
		"hit_dust_count": 18, "hit_debris_count": 8,
		"hit_shake": 4.0, "hit_dur": 0.11,
	},
	"fire": {
		"body_grid": [
			[0, 0, 0, 1, 9, 1, 0, 0, 0],
			[0, 0, 1, 9, 9, 9, 1, 0, 0],
			[0, 1, 9, 9, 9, 9, 9, 1, 0],
			[0, 1, 9, 9, 1, 9, 9, 1, 0],
			[1, 1, 9, 1, 1, 1, 9, 1, 1],
			[1, 9, 1, 9, 9, 9, 1, 9, 1],
			[1, 1, 9, 9, 1, 9, 9, 1, 1],
			[0, 1, 9, 9, 9, 9, 9, 1, 0],
			[0, 1, 1, 9, 9, 9, 1, 1, 0],
			[0, 0, 1, 1, 9, 1, 1, 0, 0],
			[0, 0, 0, 3, 3, 3, 0, 0, 0],
		],
		"rock_grid": [
			[0, 1, 9, 1, 0],
			[1, 9, 9, 9, 1],
			[9, 9, 1, 9, 9],
			[1, 9, 9, 9, 1],
			[0, 1, 9, 1, 0],
		],
		"palette": {
			9: [Color("#fff8a0"), Color("#ffffff")],
			1: [Color("#ffa838"), Color("#ffc868")],
			2: [Color("#d85020"), null],
			3: [Color("#681810"), Color("#481008")],
			4: [Color("#2a0808"), null],
		},
		"body_flicker_ms": 60,
		"rock_flicker_ms": 50,
		"glow_color": Color(1.0, 0.5, 0.15),
		"glow_inner_color": Color(1.0, 0.85, 0.3),
		"glow_r1": 26.0, "glow_r2": 18.0,
		"rock_rot_speed": 6.0, "rock_shadow_r": 7.0,
		"hit_dust_color": Color("#ff8030"), "hit_debris_color": Color("#2a0808"),
		"hit_dust_count": 22, "hit_debris_count": 12,
		"hit_shake": 5.5, "hit_dur": 0.13,
	},
}


func _summon_color(palette: Dictionary, layer: int, flicker: bool) -> Color:
	var pair = palette.get(layer, null)
	if pair == null:
		pair = palette.get(4, [Color.BLACK, null])
	if flicker and pair.size() >= 2 and pair[1] != null:
		return pair[1]
	return pair[0]


func _draw_summon_grid(canvas: CanvasItem, grid: Array, palette: Dictionary, flicker: bool, px: float) -> void:
	var rows := grid.size()
	if rows == 0:
		return
	var cols := (grid[0] as Array).size()
	var half_w := float(cols) * 0.5
	var half_h := float(rows) * 0.5
	for ry in range(rows):
		var row_arr: Array = grid[ry]
		for cx in range(cols):
			var layer: int = int(row_arr[cx])
			if layer == 0:
				continue
			var x: float = (float(cx) - half_w) * px
			var y: float = (float(ry) - half_h) * px
			# flicker 仅作用在 layer==3 外圈
			var f := flicker if layer == 3 else false
			canvas.draw_rect(Rect2(x, y, px, px), _summon_color(palette, layer, f))


func _draw_pixel_summon_body(canvas: CanvasItem, world_pos: Vector2, bob: float, kind: String) -> void:
	var data: Dictionary = SUMMON_DRAW_DATA.get(kind, {})
	if data.is_empty():
		return
	var px := float(SUMMON_DRAW_PIXEL)
	var flicker_ms := int(data.get("body_flicker_ms", 80))
	var flicker := int(Time.get_ticks_msec() / flicker_ms) % 2 == 0
	var local: Vector2 = world_pos - canvas.global_position + Vector2(0, bob)
	canvas.draw_set_transform(local, 0.0, Vector2.ONE * 1.2)
	# 外发光圆晕（双层呼吸）
	var glow_pulse: float = 0.18 + 0.06 * sin(Time.get_ticks_msec() * 0.004)
	var glow_outer: Color = data.get("glow_color", Color(1, 1, 1))
	glow_outer.a = glow_pulse
	canvas.draw_circle(Vector2.ZERO, float(data.get("glow_r1", 22.0)), glow_outer)
	var glow_inner: Color = data.get("glow_inner_color", Color(1, 1, 1))
	glow_inner.a = 0.12
	canvas.draw_circle(Vector2.ZERO, float(data.get("glow_r2", 16.0)), glow_inner)
	_draw_summon_grid(canvas, data.get("body_grid", []), data.get("palette", {}), flicker, px)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pixel_summon_projectile(canvas: CanvasItem, world_pos: Vector2, age: float, kind: String) -> void:
	var data: Dictionary = SUMMON_DRAW_DATA.get(kind, {})
	if data.is_empty():
		return
	var px := float(SUMMON_DRAW_PIXEL)
	var flicker_ms := int(data.get("rock_flicker_ms", 60))
	var flicker := int(Time.get_ticks_msec() / flicker_ms) % 2 == 0
	var local: Vector2 = world_pos - canvas.global_position
	var rot: float = age * float(data.get("rock_rot_speed", 0.0))
	canvas.draw_set_transform(local, rot, Vector2.ONE * 1.2)
	var shadow_r: float = data.get("rock_shadow_r", 0.0)
	if shadow_r > 0.0:
		canvas.draw_circle(Vector2.ZERO, shadow_r, Color(0, 0, 0, 0.28))
	_draw_summon_grid(canvas, data.get("rock_grid", []), data.get("palette", {}), flicker, px)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _summon_hit_burst(pos: Vector2, kind: String) -> void:
	var data: Dictionary = SUMMON_DRAW_DATA.get(kind, {})
	if data.is_empty() or battle == null:
		return
	if battle.particles:
		var ws: float = GameConfig.get_world_scale()
		var dust_color: Color = data.get("hit_dust_color", Color.WHITE)
		var debris_color: Color = data.get("hit_debris_color", Color.BLACK)
		var dust_count: int = int(data.get("hit_dust_count", 18))
		var debris_count: int = int(data.get("hit_debris_count", 10))
		for j in range(dust_count):
			var a := randf() * TAU
			var sp := randf_range(60.0, 180.0)
			battle.particles.emit_particle(
				pos.x, pos.y,
				cos(a) * sp, sin(a) * sp,
				randf_range(0.25, 0.5), randf_range(5.0, 10.0) * FX_SCALE * ws,
				dust_color, 40.0, true, true
			)
		for k in range(debris_count):
			var a2 := randf() * TAU
			var sp2 := randf_range(180.0, 320.0)
			battle.particles.emit_particle(
				pos.x, pos.y,
				cos(a2) * sp2, sin(a2) * sp2,
				randf_range(0.2, 0.4), randf_range(3.0, 6.0) * FX_SCALE * ws,
				debris_color, 220.0, true, false
			)
	if battle.has_method("shake_camera"):
		battle.shake_camera(float(data.get("hit_shake", 5.0)), float(data.get("hit_dur", 0.12)))
