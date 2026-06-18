extends Node
class_name SwordOrbitManager

# Phase 7 sr=40 sword_unit：6 张剑单位卡。
# 每把剑绕玩家旋转，按 hit_interval 节奏与敌人碰撞造成伤害 + 应用元素状态。
# 6 张卡的元素 / atk_mult / hit_interval 从 SWORD_SPEC 读取（对应 rewards_v6.json）。
#
# 受 sr=38/41/42/43 buff 影响：count_mult / length_pct / speed_pct / dmg_pct
# 受 sr=39 sword_rage：击中按 proc 概率 spawn 一次 AOE
#
# 由 BattleController 调 setup() / reset() / update(delta, player, monsters) / draw_fx(canvas)

const SWORD_SPEC: Dictionary = {
	"sword_guard":   {"count_field": "sword_guard_count",   "atk_mult": 0.8, "hit_interval": 0.5, "element": ""},
	"sword_blood":   {"count_field": "sword_blood_count",   "atk_mult": 1.0, "hit_interval": 0.6, "element": ""},
	"sword_flame":   {"count_field": "sword_flame_count",   "atk_mult": 0.4, "hit_interval": 0.5, "element": "fire"},
	"sword_thunder": {"count_field": "sword_thunder_count", "atk_mult": 0.4, "hit_interval": 0.5, "element": "thunder"},
	"sword_poison":  {"count_field": "sword_poison_count",  "atk_mult": 0.3, "hit_interval": 0.5, "element": "poison"},
	"sword_frost":   {"count_field": "sword_frost_count",   "atk_mult": 0.3, "hit_interval": 0.5, "element": "ice"},
}

const BASE_RADIUS := 72.8    # 剑距离玩家中心的基础半径（默认 +30%，原 56）
const BASE_SPIN := 2.6       # 基础角速度 (rad/s)
const SWORD_HIT_RADIUS := 18.0

var battle
var swords: Array = []   # {kind, atk_mult, hit_interval, element, angle, hit_timer, hit_cooldown:{id:t}}


func setup(battle_node) -> void:
	battle = battle_node


func reset() -> void:
	swords.clear()


func _ensure_swords(player) -> void:
	if player == null:
		return
	var count_mult: float = float(player.sword_count_mult)
	# 每种 sword 期望数量 = count_field × count_mult
	for kind in SWORD_SPEC.keys():
		var spec: Dictionary = SWORD_SPEC[kind]
		var desired: int = int(round(float(player.get(spec.count_field)) * count_mult))
		var existing: int = 0
		for s in swords:
			if str(s.kind) == kind:
				existing += 1
		while existing < desired:
			swords.append({
				"kind": kind,
				"atk_mult": float(spec.atk_mult),
				"hit_interval": float(spec.hit_interval),
				"element": str(spec.element),
				"angle": randf() * TAU,
				"hit_cooldown": {},
				"_anim_t": 0.0,
			})
			existing += 1
		while existing > desired:
			for i in range(swords.size() - 1, -1, -1):
				if str(swords[i].kind) == kind:
					swords.remove_at(i)
					existing -= 1
					break


func update(delta: float, player, monsters: Array) -> void:
	if player == null or battle == null:
		return
	if battle.state != GameState.PLAYING:
		return
	if player.hp <= 0:
		return
	if delta <= 0.0 or player.state == player.State.BULLET_TIME:
		return
	_ensure_swords(player)
	if swords.is_empty():
		return
	var spin: float = BASE_SPIN * (1.0 + float(player.sword_speed_pct))
	var radius: float = BASE_RADIUS * (1.0 + float(player.sword_length_pct))
	var center: Vector2 = player.global_position
	# 同 kind 的剑均分角度（视觉好看）。简化：所有剑共享一个统一旋转，按 index 分布。
	var n: int = swords.size()
	for i in range(n):
		var s: Dictionary = swords[i]
		s.angle = fposmod(float(s.angle) + spin * delta, TAU)
		s._anim_t = float(s._anim_t) + delta
		var pos: Vector2 = center + Vector2(cos(float(s.angle)), sin(float(s.angle))) * radius
		# 命中扫描
		_check_sword_hit(s, pos, player, monsters, delta)
		swords[i] = s


func _check_sword_hit(s: Dictionary, pos: Vector2, player, monsters: Array, delta: float) -> void:
	var cd: Dictionary = s.hit_cooldown
	# CD 衰减
	for k in cd.keys():
		cd[k] = float(cd[k]) - delta
	# 清理过期
	for k in cd.keys():
		if float(cd[k]) <= 0.0:
			cd.erase(k)
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var key: String = str(m.get_instance_id())
		if cd.has(key):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if pos.distance_to(m.global_position) > hit_r + SWORD_HIT_RADIUS:
			continue
		cd[key] = float(s.hit_interval)
		_deal_sword_damage(s, pos, m, player)
	s.hit_cooldown = cd


func _deal_sword_damage(s: Dictionary, pos: Vector2, m, player) -> void:
	var atk_mult: float = float(s.atk_mult) * (1.0 + float(player.sword_dmg_pct))
	var element: String = str(s.element)
	var source: String = "sword_" + str(s.kind)
	var info: DamageInfo = player.make_ability_damage(source, atk_mult, "sword", element, false, false)
	info.raw_amount = player.get_ability_damage(atk_mult)
	# 元素状态
	if element != "":
		match element:
			"fire":    info.applies_fire = true
			"ice":     info.applies_ice = true
			"thunder": info.applies_thunder = true
			"poison":  info.applies_poison = true
	var result: Dictionary = {}
	if m.has_method("take_damage_info"):
		result = m.take_damage_info(info, pos)
	if not result.is_empty():
		if battle and battle.combat:
			battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, _sword_color(s))
		if int(result.get("damage", 0)) > 0:
			ElementEffectManager.try_apply(m, info, player)
			# Phase 7 sr=39 sword_rage：剑击中按 proc 触发 AOE
			SpecialRuleDispatcher.on_sword_hit(player, battle.abilities if battle else null, m.global_position, pos)
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(m)


func _sword_color(s: Dictionary) -> Color:
	match str(s.element):
		"fire":    return Color(1.0, 0.6, 0.2)
		"ice":     return Color(0.6, 0.9, 1.0)
		"thunder": return Color(1.0, 0.95, 0.4)
		"poison":  return Color(0.5, 1.0, 0.5)
		_:         return Color(0.9, 0.9, 0.95)


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	if below_monsters:
		return
	var offset: Vector2 = -canvas.global_position
	if battle == null or battle.player == null:
		return
	var spin: float = BASE_SPIN * (1.0 + float(battle.player.sword_speed_pct))
	var radius: float = BASE_RADIUS * (1.0 + float(battle.player.sword_length_pct))
	var center: Vector2 = battle.player.global_position + offset
	for s in swords:
		var ang: float = float(s.angle)
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		# 剑方向：切线（垂直径向）
		var blade_dir: float = ang + PI * 0.5
		var color: Color = _sword_color(s)
		# 画剑：6×22 像素长条
		canvas.draw_set_transform(pos, blade_dir, Vector2.ONE * 1.3)
		canvas.draw_rect(Rect2(-2.5, -12.0, 5.0, 24.0), color)
		canvas.draw_rect(Rect2(-1.0, -14.0, 2.0, 4.0), Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, 1.0))  # tip
		canvas.draw_rect(Rect2(-3.5, 10.0, 7.0, 3.0), Color(0.45, 0.3, 0.18))  # hilt
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 元素 glow
		if str(s.element) != "":
			canvas.draw_circle(pos, 10.0, Color(color.r, color.g, color.b, 0.25))
