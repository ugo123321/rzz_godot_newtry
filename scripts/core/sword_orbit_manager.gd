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
	"sword_guard":   {"count_field": "sword_guard_count",   "atk_mult": 0.8, "hit_interval": 0.5, "element": "",        "length_mult": 3.0},
	"sword_blood":   {"count_field": "sword_blood_count",   "atk_mult": 1.0, "hit_interval": 0.6, "element": "",        "length_mult": 3.0},
	"sword_flame":   {"count_field": "sword_flame_count",   "atk_mult": 0.4, "hit_interval": 0.5, "element": "fire",    "length_mult": 3.0},
	"sword_thunder": {"count_field": "sword_thunder_count", "atk_mult": 0.4, "hit_interval": 0.5, "element": "thunder", "length_mult": 3.0},
	"sword_poison":  {"count_field": "sword_poison_count",  "atk_mult": 0.3, "hit_interval": 0.5, "element": "poison",  "length_mult": 3.0},
	"sword_frost":   {"count_field": "sword_frost_count",   "atk_mult": 0.3, "hit_interval": 0.5, "element": "ice",     "length_mult": 3.0},
	# 主题关：命运之矛（环绕长枪，无元素，高 ATK 倍率 + 高频）；长度 6× 突出长枪形态
	"angel_fate_spear": {"count_field": "sword_spear_count", "atk_mult": 1.5, "hit_interval": 0.4, "element": "",      "length_mult": 6.0},
}

const BASE_RADIUS := 72.8    # 剑距离玩家中心的基础半径（默认 +30%，原 56）
const BASE_SPIN := 2.6       # 基础角速度 (rad/s)
const SWORD_HIT_RADIUS := 18.0
# 剑身内端到 pos（剑中心点）的世界距离 — 固定值，不随 length_mult 改变。
# 对应原版 local y=+12 × scale 1.3 = 15.6 — 这个端点贴近玩家身体外缘，必须保持不动，
# 否则剑越长越往玩家身体里钻。length_mult 只影响"外端（剑尖那侧）的延伸长度"。
const BLADE_INNER_WORLD := 15.6

var battle
var swords: Array = []   # {kind, atk_mult, hit_interval, element, angle, hit_timer, hit_cooldown:{id:t}}
# 全局相位：所有剑共享一个旋转角 _orbit_t，每帧 += spin × delta。
# 单把剑的角度 = _orbit_t + i × TAU / count → 严格均匀分布（关卡 reset 后重新 spawn 也照样均匀）
var _orbit_t: float = 0.0


func setup(battle_node) -> void:
	battle = battle_node


func reset() -> void:
	swords.clear()
	_orbit_t = 0.0


# 给 battle._needs_fx_redraw 用 — 只要场上有剑就持续 queue_redraw，否则远离敌人时剑会"冻在原位"。
func has_active_fx() -> bool:
	return not swords.is_empty()


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
				"length_mult": float(spec.get("length_mult", 3.0)),
				# angle 由 update() 每帧从 _orbit_t + i × step 重写（保证均匀），这里只占位
				"angle": 0.0,
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
	# 全局相位推进 → 每把剑的角度 = _orbit_t + i × step，自然均匀
	_orbit_t = fposmod(_orbit_t + spin * delta, TAU)
	var n: int = swords.size()
	var step: float = TAU / float(maxi(1, n))
	for i in range(n):
		var s: Dictionary = swords[i]
		s._anim_t = float(s._anim_t) + delta
		var ang: float = fposmod(_orbit_t + step * float(i), TAU)
		s.angle = ang
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		# 命中扫描（按整条剑身段做线段碰撞，长度随 length_mult 拉长）
		_check_sword_hit(s, pos, ang, player, monsters, delta)
		swords[i] = s


func _check_sword_hit(s: Dictionary, pos: Vector2, ang: float, player, monsters: Array, delta: float) -> void:
	var cd: Dictionary = s.hit_cooldown
	# CD 衰减
	for k in cd.keys():
		cd[k] = float(cd[k]) - delta
	# 清理过期
	for k in cd.keys():
		if float(cd[k]) <= 0.0:
			cd.erase(k)
	# 剑身段：内端固定（pos - radial × 15.6，贴近玩家身体外缘 — 与原版位置一致），
	# 外端按 length_mult 向外延伸 → 整段总长 = 原版 × length_mult。
	# 公式推导：原 blade body local y ∈ [-12, +12]（24 长），lengthmult=N 时改为 y ∈ [12-24N, +12]，
	# 内端永远在 +12 不动；外端从 -12（原）→ 12-24N（拉长）。换到世界 ×1.3：
	#   inner = pos - radial × 15.6
	#   outer = pos + radial × 15.6 × (2N - 1)
	# sr=41 sword_length_pct 仍作用在 length_mult 上（卡牌叠加）
	var length_mult: float = float(s.get("length_mult", 3.0)) * (1.0 + float(player.sword_length_pct))
	var outer_extent: float = BLADE_INNER_WORLD * maxf(1.0, 2.0 * length_mult - 1.0)
	var radial: Vector2 = Vector2(cos(ang), sin(ang))
	var blade_start: Vector2 = pos - radial * BLADE_INNER_WORLD
	var blade_end: Vector2 = pos + radial * outer_extent
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var key: String = str(m.get_instance_id())
		if cd.has(key):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if MathUtils.point_segment_distance(m.global_position, blade_start, blade_end) > hit_r + SWORD_HIT_RADIUS:
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
	var sword_length_pct_buff: float = 1.0 + float(battle.player.sword_length_pct)
	var center: Vector2 = battle.player.global_position + offset
	for s in swords:
		var ang: float = float(s.angle)
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		# 剑方向：local +y 朝玩家方向（内端），local -y 朝外（剑尖）
		var blade_dir: float = ang + PI * 0.5
		var color: Color = _sword_color(s)
		# 内端固定 local y=+12（贴近玩家），外端 y=12 - 24×length_mult（按 length_mult 向外伸长）
		# scale 1.3 不变 — 不再走 Y 缩放（缩放会把 hilt 一起拉到玩家身体里）
		var length_mult: float = float(s.get("length_mult", 3.0)) * sword_length_pct_buff
		var inner_y: float = 12.0
		var outer_y: float = 12.0 - 24.0 * length_mult
		var blade_h: float = inner_y - outer_y  # = 24 × length_mult
		canvas.draw_set_transform(pos, blade_dir, Vector2.ONE * 1.3)
		canvas.draw_rect(Rect2(-2.5, outer_y, 5.0, blade_h), color)  # 剑身体（外端→内端）
		# tip：紧贴外端，跨外端 2px 突出
		canvas.draw_rect(Rect2(-1.0, outer_y - 2.0, 2.0, 4.0), Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, 1.0))
		# hilt：永远在内端附近（y=10~13），位置完全不变 — 这就是用户要的"起点保持原样"
		canvas.draw_rect(Rect2(-3.5, 10.0, 7.0, 3.0), Color(0.45, 0.3, 0.18))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 元素 glow：沿剑身中点 + 外端各铺一圈，长剑更均匀
		if str(s.element) != "":
			var radial: Vector2 = Vector2(cos(ang), sin(ang))
			var outer_extent: float = BLADE_INNER_WORLD * maxf(1.0, 2.0 * length_mult - 1.0)
			var mid_offset: float = (outer_extent - BLADE_INNER_WORLD) * 0.5  # 剑身中点距 pos 多远（沿径向外）
			var glow_color := Color(color.r, color.g, color.b, 0.22)
			canvas.draw_circle(pos + radial * mid_offset, 10.0, glow_color)
			if length_mult > 1.5:
				canvas.draw_circle(pos + radial * outer_extent * 0.85, 8.0, glow_color)
