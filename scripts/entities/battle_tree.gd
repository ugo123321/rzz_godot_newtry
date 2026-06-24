extends Node2D
class_name BattleTree

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const BLOCK_RADIUS := 38.0
const HITBOX_RADIUS := 44.0
const FALL_AOE_RADIUS := 90.0
const FALL_AOE_ATTACK_MULT := 2.0

const FALL_DURATION := 0.55
const FALL_AOE_TRIGGER_PROGRESS := 0.78  # 树身接近地面时才触发 AOE
const AOE_RING_DURATION := 0.42
const FADE_AFTER_FALL := 0.65

var max_hp := 1
var hp := 1
var dying := false
var alive := true
var hurt_reaction_timer := 0.0
var stage_index_cached := 0
var path_target_hit_count := 0

var has_shield := false
var vulnerable_mark := false
var vuln_physical := 0.0
var vuln_fire := 0.0
var vuln_ice := 0.0
var vuln_thunder := 0.0
var vuln_poison := 0.0
var elem_resist_fire := 0.0
var elem_resist_ice := 0.0
var elem_resist_thunder := 0.0
var elem_resist_poison := 0.0
var defense := 0.0

var _sway_seed := 0.0

# 倒下动画状态
var fall_dir := 1.0
var fall_progress := 0.0
var aoe_triggered := false
var aoe_ring_progress := 0.0
var fade_after_fall_timer := 0.0


func setup(pos: Vector2, stage_idx: int = 0) -> void:
	global_position = pos
	stage_index_cached = stage_idx
	max_hp = 1
	hp = 1
	_sway_seed = randf() * TAU
	z_index = 1
	scale = Vector2.ONE * 1.6
	queue_redraw()


func _process(delta: float) -> void:
	if hurt_reaction_timer > 0.0:
		hurt_reaction_timer = maxf(0.0, hurt_reaction_timer - delta)
		queue_redraw()
	if dying:
		if fall_progress < 1.0:
			fall_progress = minf(1.0, fall_progress + delta / FALL_DURATION)
			# 倒到接近地面时触发 AOE 伤害 + 冲击波
			if not aoe_triggered and fall_progress >= FALL_AOE_TRIGGER_PROGRESS:
				aoe_triggered = true
				_explode_aoe()
				_emit_impact_dust()
				var battle := get_tree().get_first_node_in_group("battle")
				if battle and battle.has_method("shake_camera"):
					battle.shake_camera(6.5, 0.18)
			queue_redraw()
		else:
			if aoe_ring_progress < 1.0:
				aoe_ring_progress = minf(1.0, aoe_ring_progress + delta / AOE_RING_DURATION)
				queue_redraw()
			else:
				fade_after_fall_timer += delta
				queue_redraw()
				if fade_after_fall_timer >= FADE_AFTER_FALL:
					queue_free()


func is_combat_targetable() -> bool:
	return alive and not dying


func get_hitbox_radius() -> float:
	return HITBOX_RADIUS


func get_block_radius() -> float:
	if not is_combat_targetable():
		return 0.0
	return BLOCK_RADIUS


func take_damage_info(info, from_pos: Vector2) -> Dictionary:
	if not is_combat_targetable():
		return {"damage": 0, "is_crit": false}
	var raw_amount: int = 0
	if info != null and "raw_amount" in info:
		raw_amount = int(info.raw_amount)
	var dmg: int = maxi(1, raw_amount)
	hp = 0
	hurt_reaction_timer = 0.16
	dying = true
	_on_killed(from_pos)
	queue_redraw()
	return {"damage": dmg, "is_crit": false, "started_dying": true}


func _on_killed(from_pos: Vector2) -> void:
	alive = false
	# 倒下方向：远离攻击来源
	var dx := global_position.x - from_pos.x
	if absf(dx) < 1.0:
		fall_dir = -1.0 if randf() < 0.5 else 1.0
	else:
		fall_dir = 1.0 if dx > 0.0 else -1.0
	# 通知 battle（不会立即 free，BattleTree 自己控制生命周期）
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.has_method("on_tree_killed"):
		battle.on_tree_killed(self)
	queue_redraw()


# 树倒下范围伤害：对 FALL_AOE_RADIUS 内的怪造成 base_attack × FALL_AOE_ATTACK_MULT 的物理伤害
func _explode_aoe() -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.spawner == null or battle.player == null:
		return
	var player = battle.player
	var damage: int = int(max(1, player.get_ability_damage(FALL_AOE_ATTACK_MULT)))
	var origin := global_position
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var hit_r: float = 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if origin.distance_to(m.global_position) > FALL_AOE_RADIUS + hit_r:
			continue
		var info: DamageInfo = player.make_damage("tree_fall", FALL_AOE_ATTACK_MULT, "ability", "", false, false)
		info.raw_amount = damage
		var result: Dictionary = {}
		if m.has_method("take_damage_info"):
			result = m.take_damage_info(info, origin)
		elif m.has_method("take_damage"):
			result = m.take_damage(damage, origin)
		if not result.is_empty() and battle.combat and int(result.get("damage", 0)) > 0:
			battle.combat.spawn_damage_number(m.global_position, int(result.get("damage", 0)), false, false, Color("#c08a52"))
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(m)


func _emit_impact_dust() -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.particles == null:
		return
	var origin := global_position
	# 木屑：暖棕色
	for j in range(18):
		var a := randf() * TAU
		var sp := randf_range(80.0, 200.0)
		battle.particles.emit_particle(
			origin.x, origin.y - 24.0,
			cos(a) * sp, sin(a) * sp,
			randf_range(0.3, 0.55), randf_range(4.0, 9.0),
			Color("#8a5a36"), 60.0, true, true
		)
	# 树叶：绿色
	for k in range(10):
		var a2 := randf() * TAU
		var sp2 := randf_range(140.0, 280.0)
		battle.particles.emit_particle(
			origin.x, origin.y - 18.0,
			cos(a2) * sp2, sin(a2) * sp2,
			randf_range(0.25, 0.45), randf_range(3.0, 6.0),
			Color("#4d8a36"), 200.0, true, false
		)
	# 砸地尘土：灰白沿水平方向四散
	for d in range(14):
		var a3: float = randf_range(-0.35, 0.35) + (0.0 if fall_dir > 0.0 else PI)
		var sp3 := randf_range(120.0, 220.0)
		battle.particles.emit_particle(
			origin.x + fall_dir * randf_range(20.0, 50.0), origin.y - randf_range(0.0, 8.0),
			cos(a3) * sp3, sin(a3) * sp3 - 30.0,
			randf_range(0.4, 0.7), randf_range(5.0, 10.0),
			Color("#d8cbb0"), 20.0, true, true
		)


func _draw() -> void:
	if not alive and not dying:
		return
	var sway := sin(Time.get_ticks_msec() / 500.0 + _sway_seed) * 1.2
	var flash := hurt_reaction_timer > 0.0

	if dying:
		var p: float = clampf(fall_progress, 0.0, 1.0)
		# ease_in_quad：先慢后快，模拟树倒下加速
		var angle: float = fall_dir * (PI * 0.5) * (p * p)
		var alpha: float = 1.0
		if p >= 1.0 and fade_after_fall_timer > 0.0:
			alpha = clampf(1.0 - fade_after_fall_timer / FADE_AFTER_FALL, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
		_draw_tree_lush(0.0, flash, alpha)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if aoe_triggered:
			_draw_aoe_ring()
		return

	_draw_tree_lush(sway, flash, 1.0)
	if path_target_hit_count > 0 and is_combat_targetable():
		var ring := CombatDirector.path_preview_ring_color(path_target_hit_count)
		var fill := ring
		fill.a = 0.12 + mini(path_target_hit_count, 4) * 0.04
		var r := HITBOX_RADIUS + 5.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ring, 3.0)
		draw_circle(Vector2.ZERO, r * 0.55, fill)


func _draw_tree_lush(sway: float, flash: bool, alpha: float = 1.0) -> void:
	_draw_trunk_block(flash, 0.0, -8.0, 8, 30, alpha)
	var p_dark := Color("#1f3a1a")
	var p_mid := Color("#2f5a23")
	var p_light := Color("#4d8a36")
	var p_high := Color("#7bbf52")
	if flash:
		p_dark = p_dark.lerp(Color.WHITE, 0.5)
		p_mid = p_mid.lerp(Color.WHITE, 0.5)
		p_light = p_light.lerp(Color.WHITE, 0.5)
		p_high = p_high.lerp(Color.WHITE, 0.5)
	p_dark.a *= alpha
	p_mid.a *= alpha
	p_light.a *= alpha
	p_high.a *= alpha
	var fx := sway
	_draw_pixel_circle(Vector2(fx, -38.0), 26.0, p_dark)
	_draw_pixel_circle(Vector2(fx - 12.0, -32.0), 18.0, p_dark)
	_draw_pixel_circle(Vector2(fx + 12.0, -32.0), 18.0, p_dark)
	_draw_pixel_circle(Vector2(fx, -42.0), 22.0, p_mid)
	_draw_pixel_circle(Vector2(fx - 10.0, -34.0), 14.0, p_mid)
	_draw_pixel_circle(Vector2(fx + 10.0, -34.0), 14.0, p_mid)
	_draw_pixel_circle(Vector2(fx, -46.0), 16.0, p_light)
	_draw_pixel_circle(Vector2(fx - 6.0, -42.0), 8.0, p_high)
	_draw_pixel_circle(Vector2(fx + 6.0, -38.0), 6.0, p_high)


func _draw_trunk_block(flash: bool, cx: float, cy: float, half_w: float, height: float, alpha: float = 1.0) -> void:
	var dark := Color("#3a2618")
	var mid := Color("#5a3a22")
	var light := Color("#8a5a36")
	if flash:
		dark = dark.lerp(Color.WHITE, 0.55)
		mid = mid.lerp(Color.WHITE, 0.55)
		light = light.lerp(Color.WHITE, 0.55)
	dark.a *= alpha
	mid.a *= alpha
	light.a *= alpha
	draw_rect(Rect2(cx - half_w, cy - height, half_w * 2.0, height), dark)
	draw_rect(Rect2(cx - half_w + 2.0, cy - height + 2.0, half_w * 2.0 - 4.0, height - 4.0), mid)
	draw_rect(Rect2(cx - half_w + 4.0, cy - height + 2.0, 2.0, height - 4.0), light)


func _draw_aoe_ring() -> void:
	var p: float = clampf(aoe_ring_progress, 0.0, 1.0)
	if p <= 0.0:
		return
	# ease_out_cubic 让冲击波快速扩散后减速
	var ease_p: float = 1.0 - pow(1.0 - p, 3.0)
	var radius: float = FALL_AOE_RADIUS * ease_p
	var fade: float = 1.0 - p
	var outer_color := Color("#f5a04a", 0.85 * fade)
	var fill_color := Color("#f5a04a", 0.28 * fade)
	var inner_color := Color("#ffd58a", 0.55 * fade)
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outer_color, 4.0)
	var inner_r: float = radius * 0.6
	if inner_r > 2.0:
		draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 32, inner_color, 2.0)


func _draw_pixel_circle(center: Vector2, radius: float, color: Color) -> void:
	var r_i := int(round(radius))
	for dy in range(-r_i, r_i + 1):
		var dx_limit := int(round(sqrt(maxf(0.0, radius * radius - float(dy * dy)))))
		if dx_limit <= 0:
			continue
		draw_rect(
			Rect2(center.x - dx_limit, center.y + dy, dx_limit * 2, 1.0),
			color
		)
