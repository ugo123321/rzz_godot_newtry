extends Node2D
class_name BounceSlimeBoss

# ===================== 弹射史莱姆 BOSS =====================
# 出场即在屏幕中央生成 5 个分体(BounceSlimeUnit),朝 5 个不同方向弹射飞出,
# 像打砖块的子弹一样在场景边缘物理反弹,撞到玩家造成接触伤害。
# 每个分体独立血量;BOSS 血条显示 5 个分体血量之和(hp / max_hp)。
# 受击:分体闪红(无 hurt 动画)。死亡:全部渐隐(无 death 动画)。
#
# 多体血量模型仿 CentipedeBoss 的"分段共享 hp"思路,但这里是"各分体独立 hp +
# boss.hp = 总和":max_hp = SLIME_COUNT * 单体 hp;受击同时扣分体 hp 与 boss hp;
# 分体 hp 归零 → 该分体死亡(渐隐移除);全部死亡 → boss _defeat()。
# 血条 / 画线标记 / 关卡流程 / 出场特写 全部自动接入(只要暴露 hp/max_hp/
# get_hp_ratio/get_display_name + 分体挂 BossMarkerOverlay + path_target_hit_count)。

enum Phase { WARNING, ACTIVE, DEAD }

const SLIME_COUNT := 5
const APPEAR_DURATION := 0.65
const HURT_FLASH_DUR := 0.18

var battle
var stage_index := 0
var cfg: Dictionary = {}
var phase := Phase.WARNING
var warning_timer := 3.0
var warning_pulse := 0.0
var warning_total := 3.0
var defeated := false
var defeat_rewarded := false
var hp := 0
var max_hp := 0
var defense := 0
var hitbox_radius := 24.0
var body_scale_mult := 1.0
var units: Array = []
var death_fade_timer := 0.0
var death_fade_dur := 0.45
var alive := true
var dying := false

# Boss 出现特效:scale 0→1 + alpha 0→1 + 黄色冲击波 + 屏抖(同龙/骑士)
var appear_timer := 0.0
var appear_active := false
var _appear_shockwave_r := 0.0
var _appear_shockwave_alpha := 0.0
var _speed_fx_t := 0.0

# v2 元素抗性/易伤(从 bosses.json 加载,默认 0 = 中性)
var elem_resist_fire := 0.0
var elem_resist_ice := 0.0
var elem_resist_thunder := 0.0
var elem_resist_poison := 0.0
var vuln_physical := 0.0
var vuln_fire := 0.0
var vuln_ice := 0.0
var vuln_thunder := 0.0
var vuln_poison := 0.0

var logical_w := 720.0
var logical_h := 1280.0
var play_top := 88.0
var play_bottom := 580.0


func is_boss_active() -> bool:
	return phase == Phase.ACTIVE


func get_hp_ratio() -> float:
	return clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)


func get_display_name() -> String:
	return str(cfg.get("name", "弹射史莱姆"))


func get_hitbox_radius() -> float:
	return hitbox_radius


func setup(battle_node, p_stage_index: int) -> void:
	battle = battle_node
	stage_index = p_stage_index
	cfg = GameConfig.bosses.get("bounce_slime", {})
	logical_w = float(GameConfig.get_tuning("logical_width", 720))
	logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	play_top = 88.0
	play_bottom = logical_h - 120.0
	hitbox_radius = float(cfg.get("hitbox_radius", 24))
	body_scale_mult = float(cfg.get("body_scale_mult", 1.0))
	hitbox_radius *= body_scale_mult
	warning_timer = float(cfg.get("warning_time", 3.0))
	warning_total = warning_timer
	phase = Phase.WARNING
	defeated = false
	defeat_rewarded = false
	appear_active = true
	appear_timer = APPEAR_DURATION
	_appear_shockwave_r = 0.0
	_appear_shockwave_alpha = 1.0
	var stat_scale = GameConfig.stage_stat_scale(stage_index)
	var hp_each := int(round(float(cfg.get("segment_hp", 420)) * stat_scale.hp))
	defense = maxi(1, int(round(float(cfg.get("def", 6)) * stat_scale.def)))
	max_hp = SLIME_COUNT * hp_each
	hp = max_hp
	elem_resist_fire = float(cfg.get("elem_resist_fire", 0.0))
	elem_resist_ice = float(cfg.get("elem_resist_ice", 0.0))
	elem_resist_thunder = float(cfg.get("elem_resist_thunder", 0.0))
	elem_resist_poison = float(cfg.get("elem_resist_poison", 0.0))
	vuln_physical = float(cfg.get("vuln_physical", 0.0))
	vuln_fire = float(cfg.get("vuln_fire", 0.0))
	vuln_ice = float(cfg.get("vuln_ice", 0.0))
	vuln_thunder = float(cfg.get("vuln_thunder", 0.0))
	vuln_poison = float(cfg.get("vuln_poison", 0.0))
	# BOSS 锚点放屏幕中央,5 个分体从这里弹射飞出;warning overlay / appear shockwave 也以此为锚
	global_position = Vector2(logical_w * 0.5, (play_top + play_bottom) * 0.5)
	_spawn_units(hp_each)
	_spawn_appear_particles()


func _spawn_units(hp_each: int) -> void:
	for child in get_children():
		child.queue_free()
	units.clear()
	# 5 个均匀分布方向(加一个随机偏转,避免每局完全相同)
	var base_rot := randf() * TAU
	for i in range(SLIME_COUNT):
		var ang := base_rot + TAU * float(i) / float(SLIME_COUNT)
		var dir := Vector2(cos(ang), sin(ang))
		var u := BounceSlimeUnit.new()
		add_child(u)
		units.append(u)
		u.setup(self, i, hp_each, dir)


# Boss 出现:地面砖石粉尘 + 绿色黏液火星 + 屏抖(史莱姆主色绿色)
func _spawn_appear_particles() -> void:
	if battle == null:
		return
	battle.shake_camera(7.5, 0.35)
	if battle.particles == null:
		return
	for i in range(24):
		var a := randf() * TAU
		var sp := randf_range(160.0, 320.0)
		battle.particles.emit_particle(
			global_position.x, global_position.y,
			cos(a) * sp, sin(a) * sp,
			randf_range(0.35, 0.6),
			randf_range(6.0, 11.0),
			Color("#4f7a3a"), 80.0, true, true
		)
	for i in range(14):
		var a2 := -PI * 0.5 + randf_range(-PI * 0.5, PI * 0.5)
		var sp2 := randf_range(240.0, 420.0)
		battle.particles.emit_particle(
			global_position.x, global_position.y,
			cos(a2) * sp2, sin(a2) * sp2,
			randf_range(0.3, 0.55),
			randf_range(4.0, 7.0),
			Color("#9be85a"), 320.0, true, false
		)


func is_defeated() -> bool:
	return defeated


func get_active_segments() -> Array:
	if phase != Phase.ACTIVE or defeated:
		return []
	var result: Array = []
	for u in units:
		if is_instance_valid(u) and u.alive:
			result.append(u)
	return result


func activate() -> void:
	phase = Phase.ACTIVE
	# 5 个分体正式弹射飞出
	for u in units:
		if is_instance_valid(u) and u.alive:
			u.burst_out()


func update_boss(delta: float, player: BattlePlayer) -> void:
	_speed_fx_t += delta
	# Boss 出现 tween:各分体 scale 0.4→1 + alpha 0→1 + 黄色冲击波
	if appear_active:
		appear_timer = maxf(0.0, appear_timer - delta)
		_appear_shockwave_r += delta * 480.0
		_appear_shockwave_alpha = clampf(appear_timer / APPEAR_DURATION, 0.0, 1.0)
		var p: float = 1.0 - (appear_timer / APPEAR_DURATION)
		var k: float = 1.0 - p
		var ease_p: float = 1.0 - k * k * (1.0 - 1.4 * k)
		for u in units:
			if not is_instance_valid(u):
				continue
			var scale_now: float = u._base_sprite_scale * lerpf(0.4, 1.0, clampf(ease_p, 0.0, 1.0))
			u.sprite.scale = Vector2.ONE * scale_now
			u.sprite.modulate.a = clampf(p * 1.6, 0.0, 1.0)
		if appear_timer <= 0.0:
			appear_active = false
			for u in units:
				if is_instance_valid(u):
					u._apply_slime_scale(u.sprite.animation)
					u.sprite.modulate.a = 1.0
	match phase:
		Phase.WARNING:
			warning_timer -= delta
			warning_pulse += delta * 5.0
			if warning_timer <= 0.0:
				activate()
			queue_redraw()
		Phase.DEAD:
			death_fade_timer -= delta
			for u in units:
				if is_instance_valid(u):
					u.update_unit(delta, player)
			queue_redraw()
		Phase.ACTIVE:
			for u in units:
				if is_instance_valid(u):
					u.update_unit(delta, player)
			queue_redraw()


func apply_damage(raw_damage: int, hit_unit, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(DamageInfo.legacy(raw_damage), hit_unit, _from_pos)


func apply_damage_info(info: DamageInfo, hit_unit, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(info, hit_unit, _from_pos)


func _resolve_apply_damage(info: DamageInfo, hit_unit, _from_pos: Vector2) -> Dictionary:
	if defeated or phase != Phase.ACTIVE:
		return {"damage": 0, "is_crit": false}
	if hit_unit == null or not is_instance_valid(hit_unit) or not hit_unit.alive:
		return {"damage": 0, "is_crit": false}
	var target_stats := {
		"defense": defense,
		"vulnerable_mark": false,
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
	var actual := int(res.get("damage", 0))
	# boss.hp = 各分体 hp 之和:同步扣,且钳到分体剩余血量(避免过击把总和扣过头)
	var hp_before := int(hit_unit.hp)
	hit_unit.hp = maxi(0, int(hit_unit.hp) - actual)
	var consumed := hp_before - int(hit_unit.hp)
	hp = maxi(0, hp - consumed)
	if hit_unit.hp <= 0:
		_kill_unit(hit_unit)
	else:
		hit_unit.flash_hurt()
	if hp <= 0:
		_defeat()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false))}


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func die() -> void:
	_defeat()


func _kill_unit(u) -> void:
	if u == null or not is_instance_valid(u):
		return
	u.alive = false
	u.dying = true
	u.death_fade_timer = u.death_fade_dur
	u.sprite.stop()
	if battle and battle.particles:
		battle.particles.death_effect(u.global_position, Color("#6aa84f"))
	var any_alive := false
	for o in units:
		if is_instance_valid(o) and o.alive:
			any_alive = true
			break
	if not any_alive:
		_defeat()


func _defeat() -> void:
	if defeated:
		return
	hp = 0
	defeated = true
	alive = false
	dying = true
	phase = Phase.DEAD
	death_fade_timer = death_fade_dur
	for u in units:
		if is_instance_valid(u):
			u.alive = false
			u.dying = true
			u.death_fade_timer = u.death_fade_dur
			u.sprite.stop()
	if battle and battle.blood_stains:
		battle.blood_stains.spawn(global_position.x, global_position.y, 1.6, 0.0)
	if battle and battle.particles:
		for u in units:
			if is_instance_valid(u):
				battle.particles.death_effect(u.global_position, Color("#6aa84f"))
	if not defeat_rewarded and battle and battle.experience:
		defeat_rewarded = true
		battle.experience.add_exp(int(cfg.get("defeat_exp", 160)))
	if battle and battle.hud:
		battle.hud.show_message("%s 击破!" % get_display_name(), 2.0)


func get_warning_text() -> String:
	return str(maxi(1, int(ceil(warning_timer))))


# ===================== 绘制 =====================
# 照搬 LancerBoss/DarkDragonBoss 的 warning overlay / appear shockwave(已验证可用)。

func _draw() -> void:
	if appear_active or _appear_shockwave_alpha > 0.01:
		_draw_appear_shockwave()


# Boss 出现:黄色扩散冲击波
func _draw_appear_shockwave() -> void:
	if not appear_active and _appear_shockwave_alpha <= 0.01:
		return
	var ring_w: float = 6.0 * _appear_shockwave_alpha
	var col_outer := Color(1.0, 0.85, 0.30, 0.6 * _appear_shockwave_alpha)
	var col_inner := Color(1.0, 1.0, 0.7, 0.85 * _appear_shockwave_alpha)
	draw_arc(Vector2.ZERO, _appear_shockwave_r, 0.0, TAU, 48, col_outer, ring_w)
	draw_arc(Vector2.ZERO, _appear_shockwave_r * 0.7, 0.0, TAU, 48, col_inner, ring_w * 0.6)
	draw_circle(Vector2.ZERO, maxf(0.0, 28.0 - _appear_shockwave_r * 0.1), Color(1.0, 0.95, 0.65, 0.45 * _appear_shockwave_alpha))
