extends Node
class_name SummonAbilityManager

const PLAY_TOP := 88.0
const FX_SCALE := 1.75

var battle
# Phase 4 v6 召唤实体。每个 entry: {
#   "kind": "king/god/gorilla/thunder/bear/snake/fire",
#   "pos": Vector2, "atk_timer": float, "atk_interval": float,
#   "atk_mult": float, "range_px": float, "element": String,
#   "mechanic": String, "p1": float, "p2": float, "taunt_cd_timer": float,
# }
var v6_companions: Array = []
# 共享的 v6 召唤投射物（aoe / single 弹道）
var v6_projectiles: Array = []
# AOE 命中视觉环：{pos, radius, life, max_life, color}
var v6_aoe_rings: Array = []
# Isaac 式延迟尾随：记录玩家最近若干帧位置，每只召唤物按 index 取不同回溯偏移
const TRAIL_STEP_PX := 60.0             # 玩家每移动 60px 入账一个 trail 点，召唤物之间的物理间距
const TRAIL_HISTORY_MAX := 32           # 按点数：够 ~12 只召唤 × 1 槽 + 余量
var _player_trail: Array = []          # Vector2，距离采样：仅当玩家移动 >= TRAIL_STEP_PX 时 push
var _trail_partial_dist := 0.0         # 玩家自上次 push 后又移动的距离（0~TRAIL_STEP_PX），用于 anchor 连续插值
# Sheet5 sr=45 规格（同 rewards_v6.json 中的 special_values）：写死避免每次重新查
const V6_SUMMON_SPEC: Dictionary = {
	"summon_king":     {"kind": "king",     "atk_mult": 1.2, "interval": 2.5, "range": 600.0, "element": "",        "mechanic": "ranged_aoe",    "p1": 200.0, "p2": 0.0,  "count_field": "summon_king_count"},
	"summon_god":      {"kind": "god",      "atk_mult": 1.8, "interval": 1.5, "range": 500.0, "element": "",        "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_god_count"},
	"summon_gorilla":  {"kind": "gorilla",  "atk_mult": 1.0, "interval": 1.0, "range": 400.0, "element": "",        "mechanic": "ranged_taunt",  "p1": 10.0,  "p2": 3.0,  "count_field": "summon_gorilla_count"},
	"summon_thunder":  {"kind": "thunder",  "atk_mult": 1.2, "interval": 3.0, "range": 0.0,   "element": "thunder", "mechanic": "random_aoe",    "p1": 0.0,   "p2": 0.0,  "count_field": "summon_thunder_count"},
	"summon_bear":     {"kind": "bear",     "atk_mult": 1.0, "interval": 1.0, "range": 500.0, "element": "ice",     "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_bear_count"},
	"summon_snake":    {"kind": "snake",    "atk_mult": 1.0, "interval": 1.0, "range": 500.0, "element": "poison",  "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_snake_count"},
	"summon_fire":     {"kind": "fire",     "atk_mult": 1.2, "interval": 1.5, "range": 500.0, "element": "fire",    "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_fire_count"},
	# 主题关：恶魔 / 天使宝宝
	"demon_baby":      {"kind": "demon_baby","atk_mult": 1.5, "interval": 1.2, "range": 600.0, "element": "fire",    "mechanic": "ranged_laser",  "p1": 0.0,   "p2": 0.0,  "count_field": "summon_demon_baby_count"},
	"angel_baby":      {"kind": "angel_baby","atk_mult": 1.5, "interval": 1.0, "range": 550.0, "element": "thunder", "mechanic": "ranged_single", "p1": 0.0,   "p2": 0.0,  "count_field": "summon_angel_baby_count"},
}


func setup(battle_node) -> void:
	battle = battle_node


func reset(keep_companions := false) -> void:
	if not keep_companions:
		v6_companions.clear()
	v6_projectiles.clear()
	v6_aoe_rings.clear()
	_player_trail.clear()
	_trail_partial_dist = 0.0


# 关卡 REBASE 后调：把所有保留下来的召唤物瞬移到玩家身边，清空旧轨迹。
# 没这一步的话，召唤物的 c.pos 还是上一关 REBASE 前的世界坐标，新关开局会从奇怪位置
# 平滑 lerp 到新 anchor — 视觉上就是用户看到的"先出现在奇怪地方再瞬移回身边"。
func snap_to_player(player: BattlePlayer) -> void:
	if player == null:
		return
	_player_trail.clear()
	_trail_partial_dist = 0.0
	var snap_pos: Vector2 = player.global_position + Vector2(0, -40)
	for i in range(v6_companions.size()):
		var c: Dictionary = v6_companions[i]
		c.pos = snap_pos
		c.vel = Vector2.ZERO
		v6_companions[i] = c


func has_active_fx() -> bool:
	return not v6_projectiles.is_empty() or not v6_aoe_rings.is_empty()


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
	# 记录玩家轨迹（用于 v6 召唤物的距离尾随）：玩家每移动 TRAIL_STEP_PX 才入账一个点
	# _trail_partial_dist 跟踪自上次 push 后又走了多少，用于 anchor 连续插值（去抖）
	if _player_trail.is_empty():
		_player_trail.append(player.global_position)
		_trail_partial_dist = 0.0
	else:
		var last_pt: Vector2 = _player_trail[_player_trail.size() - 1]
		_trail_partial_dist = last_pt.distance_to(player.global_position)
		if _trail_partial_dist >= TRAIL_STEP_PX:
			_player_trail.append(player.global_position)
			_trail_partial_dist = 0.0
			if _player_trail.size() > TRAIL_HISTORY_MAX:
				_player_trail.remove_at(0)
	# Phase 4 v6 召唤系统：按 player.summon_*_count 自驱
	_update_v6_summons(delta, player, monsters)


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	# v6 召唤实体与投射物
	if not below_monsters:
		_draw_v6_companions(canvas)
		_draw_v6_projectiles(canvas)
		_draw_v6_aoe_rings(canvas)


# AOE 命中视觉环：ease_out_cubic 扩散 + 渐隐
func _draw_v6_aoe_rings(canvas: Node2D) -> void:
	var offset := -canvas.global_position
	for r in v6_aoe_rings:
		var max_life: float = float(r.get("max_life", 0.45))
		var life: float = float(r.get("life", 0.0))
		var p: float = clampf(1.0 - life / max_life, 0.0, 1.0)
		var ease_p: float = 1.0 - pow(1.0 - p, 3.0)
		var base_r: float = float(r.get("radius", 100.0))
		var radius: float = base_r * ease_p
		var fade: float = 1.0 - p
		var col: Color = r.get("color", Color(1.0, 0.85, 0.35))
		var outer := Color(col.r, col.g, col.b, 0.85 * fade)
		var fill := Color(col.r, col.g, col.b, 0.22 * fade)
		var inner := Color(min(col.r + 0.2, 1.0), min(col.g + 0.2, 1.0), min(col.b + 0.2, 1.0), 0.55 * fade)
		var center: Vector2 = Vector2(r.pos) + offset
		canvas.draw_circle(center, radius, fill)
		canvas.draw_arc(center, radius, 0.0, TAU, 48, outer, 4.0)
		var inner_r: float = radius * 0.6
		if inner_r > 2.0:
			canvas.draw_arc(center, inner_r, 0.0, TAU, 32, inner, 2.0)


func _play_bottom() -> float:
	return float(GameConfig.get_tuning("logical_height", 1280))


func _play_width() -> float:
	return float(GameConfig.get_tuning("logical_width", 720))


func _summon_deal_damage(m, damage: int, _color: Color, from_pos: Vector2, source: String = "summon_hit", element: String = "") -> void:
	if m == null or not is_instance_valid(m) or _target_dead(m):
		return
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
	if info != null and int(result.get("damage", 0)) > 0:
		ElementEffectManager.try_apply(m, info, battle.player)
	if bool(result.get("started_dying", false)):
		EventBus.monster_killed.emit(m)


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
		# 平滑跟随：指数衰减 lerp（frame-rate independent），紧贴连续 anchor
		# anchor 已连续插值（不再 60px 一跳），lerp 主要消除瞬时数值抖动
		var follow_speed := 22.0
		var lerp_t: float = 1.0 - exp(-follow_speed * delta)
		c.pos = Vector2(c.pos).lerp(anchor, lerp_t)
		# 攻击计时
		c.atk_timer = float(c.atk_timer) - delta * atk_speed_factor
		if float(c.atk_timer) <= 0.0:
			c.atk_timer = float(c.atk_interval)
			_v6_summon_attack(c, player, monsters, size_factor)
		v6_companions[i] = c
	# 投射物推进
	_update_v6_projectiles(delta, player)
	_update_v6_aoe_rings(delta)


func _update_v6_aoe_rings(delta: float) -> void:
	for i in range(v6_aoe_rings.size() - 1, -1, -1):
		var r: Dictionary = v6_aoe_rings[i]
		r.life = float(r.life) - delta
		if float(r.life) <= 0.0:
			v6_aoe_rings.remove_at(i)
		else:
			v6_aoe_rings[i] = r


# v6 召唤跟随位置：距离链—第 index 个跟在玩家身后 (index+1) × TRAIL_STEP_PX 距离处。
# 沿玩家路径连续回溯（用 _trail_partial_dist 在两个 trail 点之间插值），避免 anchor 离散跳变。
func _v6_anchor_for(player: BattlePlayer, index: int, _total: int) -> Vector2:
	if _player_trail.is_empty():
		return player.global_position
	var want_dist: float = float(index + 1) * TRAIL_STEP_PX
	# 第 0 段：player → trail.back()，长度 = _trail_partial_dist
	var prev_pt: Vector2 = player.global_position
	var seg_len: float = _trail_partial_dist
	var cur_idx: int = _player_trail.size() - 1
	# 把 want_dist 沿路径一段一段回溯掉
	while cur_idx >= 0:
		if want_dist <= seg_len:
			# 在 prev_pt → _player_trail[cur_idx] 这段上，回溯 want_dist 后的位置
			if seg_len <= 0.0:
				return _player_trail[cur_idx]
			var next_pt: Vector2 = _player_trail[cur_idx]
			return prev_pt.lerp(next_pt, want_dist / seg_len)
		want_dist -= seg_len
		prev_pt = _player_trail[cur_idx]
		cur_idx -= 1
		if cur_idx >= 0:
			seg_len = prev_pt.distance_to(_player_trail[cur_idx])
	# trail 还不够长（玩家刚出生 / 没怎么动）：从最早点沿玩家朝向反向延伸补距离
	var earliest: Vector2 = _player_trail[0]
	var dir_back: Vector2 = (earliest - player.global_position).normalized()
	if dir_back == Vector2.ZERO:
		dir_back = Vector2.DOWN
	return earliest + dir_back * want_dist


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
			# 在战场上随机砸雷：从天而降的弹道（垂直下落），落地后 AOE
			var w: float = _play_width()
			var h: float = _play_bottom()
			var fall_pos := Vector2(
				MathUtils.rand_range(40.0, w - 40.0),
				MathUtils.rand_range(PLAY_TOP + 24.0, h - 24.0)
			)
			_v6_spawn_sky_strike(c, fall_pos, damage, source, element, 80.0)
		"ranged_laser":
			# 主题关 demon_baby：朝最近怪发射穿透激光（火属性）
			var laser_target = _v6_nearest_in_range(c, monsters)
			if laser_target != null:
				_v6_spawn_laser(c, laser_target.global_position, damage, source, element)


func _v6_nearest_in_range(c: Dictionary, monsters: Array):
	var best = null
	var best_d := float(c.get("range_px", 500.0))
	var best_d2 := best_d * best_d
	var origin: Vector2 = c.pos
	for m in monsters:
		if not is_instance_valid(m) or _target_dead(m) or _target_dying(m):
			continue
		var d2: float = origin.distance_squared_to(m.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = m
	return best


# 安全访问 alive/dying：Godot 4 的 Node.get(prop) 只接受 1 个参数，缺字段时返回 null。
# 用 `in` 检查属性是否存在，避免 `bool(null)` 抛 "Nonexistent 'bool' constructor"。
# Boss 类（LancerBoss / CentipedeBoss）现在已经补了 alive/dying 字段，但保留这层防御兜底。
static func _target_dead(m) -> bool:
	if "alive" in m:
		return not bool(m.alive)
	return false


static func _target_dying(m) -> bool:
	if "dying" in m:
		return bool(m.dying)
	return false


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


# 天雷专用：从屏幕顶部上方垂直落下，到达 fall_pos 时触发 AOE（不查怪碰撞）
func _v6_spawn_sky_strike(c: Dictionary, fall_pos: Vector2, damage: int, source: String, element: String, aoe_radius: float) -> void:
	var fall_speed: float = 3000.0
	var spawn_pos := Vector2(fall_pos.x, PLAY_TOP - 80.0)
	var distance: float = maxf(0.0, fall_pos.y - spawn_pos.y)
	var life: float = (distance / fall_speed) if fall_speed > 0.0 else 0.3
	v6_projectiles.append({
		"pos": spawn_pos,
		"vel": Vector2(0.0, fall_speed),
		"target_pos": fall_pos,
		"life": life,
		"max_life": life,
		"damage": damage,
		"source": source,
		"element": element,
		"kind": "sky_strike",
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
		# 主题关：恶魔宝宝激光 — 一次性穿透命中，存活短时间用于视觉
		if str(p.kind) == "laser":
			if not bool(p.get("applied", false)):
				_v6_apply_laser_pierce(p, player)
				p["applied"] = true
			if float(p.life) <= 0.0:
				v6_projectiles.remove_at(i)
				continue
			v6_projectiles[i] = p
			continue
		# 天雷弹道：到达落点 OR life 到时即爆，不与怪做碰撞
		if str(p.kind) == "sky_strike":
			var arrived: bool = float(p.life) <= 0.0 \
				or Vector2(p.pos).y >= float(Vector2(p.target_pos).y)
			if arrived:
				_v6_apply_aoe_hit(Vector2(p.target_pos), float(p.aoe_radius), int(p.damage), player, str(p.source), str(p.element))
				v6_projectiles.remove_at(i)
				continue
			v6_projectiles[i] = p
			continue
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
		if not is_instance_valid(m) or _target_dead(m) or _target_dying(m):
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
		if not is_instance_valid(m) or _target_dead(m) or _target_dying(m):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if center.distance_to(m.global_position) <= radius + hit_r:
			_summon_deal_damage(m, damage, _v6_element_color(element), center, source, element)
	_spawn_aoe_ring(center, radius, element)
	_maybe_summon_burst(source, center)


# AOE 命中视觉：扩散冲击环（外圈描边 + 半透明填充 + 内核高光），ease_out_cubic
func _spawn_aoe_ring(center: Vector2, radius: float, element: String) -> void:
	var col := _v6_element_color(element)
	# 非元素的精灵王（element=""）走金黄
	if element == "":
		col = Color(1.0, 0.85, 0.35, 1.0)
	v6_aoe_rings.append({
		"pos": center,
		"radius": radius,
		"life": 0.45,
		"max_life": 0.45,
		"color": col,
	})


# 主题关：恶魔宝宝激光 — 沿线穿透命中所有怪
func _v6_spawn_laser(c: Dictionary, target_pos: Vector2, damage: int, source: String, element: String) -> void:
	var dir: Vector2 = (target_pos - Vector2(c.pos)).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	v6_projectiles.append({
		"pos": Vector2(c.pos),
		"origin": Vector2(c.pos),
		"vel": Vector2.ZERO,  # 静态可视
		"dir": dir,
		"target_pos": target_pos,
		"life": 0.18,
		"damage": damage,
		"source": source,
		"element": element,
		"kind": "laser",
		"color": _v6_element_color(element),
		"summon_kind": str(c.get("kind", "")),
		"applied": false,
	})


func _v6_apply_laser_pierce(p: Dictionary, player: BattlePlayer) -> void:
	if battle == null or battle.spawner == null:
		return
	var origin: Vector2 = Vector2(p.get("origin", p.pos))
	var dir: Vector2 = Vector2(p.get("dir", Vector2.RIGHT))
	# 在屏幕边界内取最远点
	var w: float = _play_width()
	var h: float = _play_bottom()
	var max_dist: float = 2000.0
	var end_pt: Vector2 = origin + dir * max_dist
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or _target_dead(m) or _target_dying(m):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if _point_segment_distance(m.global_position, origin, end_pt) > hit_r + 8.0:
			continue
		_summon_deal_damage(m, int(p.damage), _v6_element_color(str(p.element)), m.global_position, str(p.source), str(p.element))
	_maybe_summon_burst(str(p.source), origin)


static func _point_segment_distance(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return pt.distance_to(a)
	var t := clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


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
		if str(p.get("kind", "")) == "sky_strike":
			_draw_sky_strike(canvas, p)
			continue
		if str(p.get("kind", "")) == "laser":
			_draw_v6_summon_laser(canvas, p)
			continue
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


# demon_baby 激光绘制：从 origin 沿 dir 到屏幕边缘的多层光束 + 命中外发光
func _draw_v6_summon_laser(canvas: Node2D, p: Dictionary) -> void:
	var offset := -canvas.global_position
	var origin: Vector2 = Vector2(p.get("origin", p.pos)) + offset
	var dir: Vector2 = Vector2(p.get("dir", Vector2.RIGHT))
	var end_pt: Vector2 = origin + dir * 2000.0
	var col: Color = p.get("color", Color(1.0, 0.4, 0.25))
	var life_left: float = float(p.get("life", 0.2))
	var alpha: float = clampf(life_left / 0.18, 0.0, 1.0)
	canvas.draw_line(origin, end_pt, Color(col, 0.25 * alpha), 14.0)
	canvas.draw_line(origin, end_pt, Color(col, 0.55 * alpha), 7.0)
	canvas.draw_line(origin, end_pt, Color(1.0, 1.0, 1.0, 0.85 * alpha), 2.5)


# 天雷弹道绘制：从屏幕顶上方一道锯齿闪电下落到当前位置 + 落点预兆圆 + 头部像素体
func _draw_sky_strike(canvas: Node2D, p: Dictionary) -> void:
	var head: Vector2 = Vector2(p.pos)
	var target: Vector2 = Vector2(p.target_pos)
	var tail_y: float = PLAY_TOP - 80.0
	var tail: Vector2 = Vector2(head.x, tail_y)
	var offset := -canvas.global_position
	# 1) 锯齿闪电尾迹（tail -> head）
	var length: float = maxf(1.0, head.y - tail_y)
	var segments: int = clampi(int(length / 14.0), 4, 32)
	var jitter_seed: int = int(Time.get_ticks_msec() / 30) ^ int(target.x)
	var pts: Array = []
	for s in range(segments + 1):
		var t: float = float(s) / float(segments)
		var py: float = tail.y + length * t
		var jitter: float = 0.0
		if s != 0 and s != segments:
			# 用 sin 让锯齿稳定但每 30ms 跳一次
			jitter = sin(float(jitter_seed + s * 17)) * 7.0
		pts.append(Vector2(head.x + jitter, py) + offset)
	# 外发光（粗淡黄）
	var glow_col := Color(1.0, 0.95, 0.35, 0.32)
	for i in range(pts.size() - 1):
		canvas.draw_line(pts[i], pts[i + 1], glow_col, 9.0)
	# 中层（黄）
	var mid_col := Color(1.0, 0.92, 0.28, 0.78)
	for i in range(pts.size() - 1):
		canvas.draw_line(pts[i], pts[i + 1], mid_col, 4.5)
	# 核心（白）
	var core_col := Color(1.0, 1.0, 1.0, 0.95)
	for i in range(pts.size() - 1):
		canvas.draw_line(pts[i], pts[i + 1], core_col, 2.0)
	# 2) 落点预兆圆（提示玩家这里要砸）
	var warn_local: Vector2 = target + offset
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.02)
	canvas.draw_circle(warn_local, 80.0, Color(1.0, 0.9, 0.2, 0.10 + 0.10 * pulse))
	canvas.draw_arc(warn_local, 80.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.35, 0.55 + 0.3 * pulse), 2.0)
	# 3) 头部像素体（沿用 thunder 的 rock_grid）
	if SUMMON_DRAW_DATA.has("thunder"):
		var life_left: float = float(p.get("life", 0.3))
		var max_life: float = float(p.get("max_life", 0.3))
		var age: float = maxf(0.0, max_life - life_left)
		_draw_pixel_summon_projectile(canvas, head, age, "thunder")


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
	# 主题关：恶魔宝宝（血红 + 黑底 + 红光） 与 天使宝宝（圣黄 + 白底 + 金光）
	"demon_baby": {
		"body_grid": [
			[0, 0, 3, 3, 3, 3, 3, 0, 0],
			[0, 3, 2, 9, 2, 9, 2, 3, 0],
			[3, 2, 1, 9, 1, 9, 1, 2, 3],
			[3, 2, 1, 1, 1, 1, 1, 2, 3],
			[3, 2, 2, 1, 1, 1, 2, 2, 3],
			[0, 3, 2, 2, 2, 2, 2, 3, 0],
			[0, 3, 1, 2, 2, 2, 1, 3, 0],
			[0, 0, 3, 1, 1, 1, 3, 0, 0],
		],
		"rock_grid": [
			[0, 1, 1, 1, 0],
			[1, 9, 1, 9, 1],
			[1, 1, 9, 1, 1],
			[1, 9, 1, 9, 1],
			[0, 1, 1, 1, 0],
		],
		"palette": {
			9: [Color("#ffe0d0"), Color("#fff8e0")],
			1: [Color("#d83020"), Color("#c81810")],
			2: [Color("#801010"), null],
			3: [Color("#380808"), Color("#200404")],
			4: [Color("#100202"), null],
		},
		"body_flicker_ms": 70,
		"rock_flicker_ms": 55,
		"glow_color": Color(0.95, 0.2, 0.1),
		"glow_inner_color": Color(0.6, 0.05, 0.05),
		"glow_r1": 24.0, "glow_r2": 16.0,
		"rock_rot_speed": 6.0, "rock_shadow_r": 7.0,
		"hit_dust_color": Color("#d83020"), "hit_debris_color": Color("#200404"),
		"hit_dust_count": 18, "hit_debris_count": 10,
		"hit_shake": 5.0, "hit_dur": 0.12,
	},
	"angel_baby": {
		"body_grid": [
			[0, 0, 1, 1, 9, 1, 1, 0, 0],
			[0, 1, 9, 9, 9, 9, 9, 1, 0],
			[1, 9, 1, 9, 9, 9, 1, 9, 1],
			[1, 9, 9, 1, 1, 1, 9, 9, 1],
			[1, 9, 9, 9, 9, 9, 9, 9, 1],
			[0, 1, 9, 9, 9, 9, 9, 1, 0],
			[0, 1, 1, 1, 1, 1, 1, 1, 0],
			[0, 0, 1, 0, 1, 0, 1, 0, 0],
		],
		"rock_grid": [
			[0, 9, 1, 9, 0],
			[9, 1, 9, 1, 9],
			[1, 9, 1, 9, 1],
			[9, 1, 9, 1, 9],
			[0, 9, 1, 9, 0],
		],
		"palette": {
			9: [Color("#ffffff"), Color("#fff8c0")],
			1: [Color("#fff488"), Color("#ffe860")],
			2: [Color("#e8c040"), null],
			3: [Color("#a07820"), Color("#806010")],
			4: [Color("#4a3408"), null],
		},
		"body_flicker_ms": 90,
		"rock_flicker_ms": 65,
		"glow_color": Color(1.0, 0.95, 0.55),
		"glow_inner_color": Color(1.0, 0.85, 0.3),
		"glow_r1": 26.0, "glow_r2": 18.0,
		"rock_rot_speed": 4.0, "rock_shadow_r": 7.0,
		"hit_dust_color": Color("#fff488"), "hit_debris_color": Color("#4a3408"),
		"hit_dust_count": 20, "hit_debris_count": 10,
		"hit_shake": 4.0, "hit_dur": 0.11,
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
	# 召唤物普攻命中只用粒子反馈，不触发屏幕震动（玩家反馈：召唤物攻击频繁，震屏太烦）
