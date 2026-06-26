extends Node2D
class_name LancerBoss

const SpecterArcherScript = preload("res://scripts/entities/specter_archer.gd")

enum Phase { WARNING, ACTIVE, DEAD }
enum SkillState { CHASE, WINDUP, SUPER_SPEED }

const SkillId := {"SPECTER_SUMMON": "specter_summon", "SUPER_SPEED": "super_speed"}

var battle
var stage_index := 0
var cfg: Dictionary = {}
var phase := Phase.WARNING
var warning_timer := 3.0
var warning_pulse := 0.0
var warning_total := 3.0           # 用于警告阶段进度计算（chevron 扫描 / 内缩边框）
var defeated := false
var defeat_rewarded := false
var hp := 0
var max_hp := 0
var defense := 0
var hitbox_radius := 14.0
var body_scale_mult := 1.0         # bosses.json body_scale_mult；体型放大与碰撞同步
var move_speed := 48.0
var death_fade_timer := 0.0
var death_fade_dur := 0.35

# Boss 出现特效：WARNING 前 0.6s 走 scale 0→1 + alpha 0→1 + 黄色冲击波 + 屏抖。
# 走完后接现有 warning 倒计时。
const APPEAR_DURATION := 0.65
var appear_timer := 0.0
var appear_active := false
var _appear_shockwave_r := 0.0     # 黄色冲击波当前半径
var _appear_shockwave_alpha := 0.0

var skill_state := SkillState.CHASE
var skill_cooldown := 5.0
var windup_timer := 0.0
var pending_skill := ""
var super_speed_timer := 0.0
var contact_timer := 0.0
var facing := 1.0
var vulnerable_mark := false
var path_target_hit_count := 0
var alive := true
# `dying` 与 BattleMonster 对齐 —— 召唤物 / 元素 DoT / 剑环绕等系统统一靠 `bool(m.get("dying"))`
# 过滤死亡中目标。没有这个字段会让 Godot 4 在 `bool(null)` 处抛 "Nonexistent 'bool' constructor"。
var dying := false

# v2 元素抗性/易伤(从 bosses.json 加载)
var elem_resist_fire := 0.0
var elem_resist_ice := 0.0
var elem_resist_thunder := 0.0
var elem_resist_poison := 0.0
var vuln_physical := 0.0
var vuln_fire := 0.0
var vuln_ice := 0.0
var vuln_thunder := 0.0
var vuln_poison := 0.0

var _warning_alpha := 0.0
var _speed_fx_t := 0.0
var _specter_archers: Array = []
var _base_sprite_scale := 1.0      # _apply_sprite 算出来的最终 scale，appear tween 用作目标值

var logical_w := 720.0
var logical_h := 1280.0
var play_top := 88.0
var play_bottom := 580.0

var sprite: AnimatedSprite2D


func _init() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)


func is_boss_active() -> bool:
	return phase == Phase.ACTIVE


func get_hp_ratio() -> float:
	return clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)


func get_display_name() -> String:
	return str(cfg.get("name", "Boss"))


func setup(battle_node, p_stage_index: int) -> void:
	battle = battle_node
	stage_index = p_stage_index
	cfg = GameConfig.bosses.get("lancer_knight", {})
	logical_w = float(GameConfig.get_tuning("logical_width", 720))
	logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	play_top = 88.0
	play_bottom = logical_h - 120.0
	hitbox_radius = float(cfg.get("hitbox_radius", 14))
	body_scale_mult = float(cfg.get("body_scale_mult", 1.0))
	# body_scale_mult 同步放大 hitbox（与精英化 size_mult 思路一致）
	hitbox_radius *= body_scale_mult
	move_speed = float(cfg.get("move_speed", 48))
	warning_timer = float(cfg.get("warning_time", 3))
	warning_total = warning_timer
	skill_cooldown = float(cfg.get("skill_interval", 5.0))
	phase = Phase.WARNING
	defeated = false
	defeat_rewarded = false
	skill_state = SkillState.CHASE
	# Boss 出现特效：scale 0 + alpha 0 起步，appear_timer 推进到 APPEAR_DURATION 时归位
	appear_active = true
	appear_timer = APPEAR_DURATION
	_appear_shockwave_r = 0.0
	_appear_shockwave_alpha = 1.0
	var scale := GameConfig.stage_stat_scale(stage_index)
	max_hp = int(round(float(cfg.get("hp", 3200)) * scale.hp))
	hp = max_hp
	defense = maxi(1, int(round(float(cfg.get("def", 8)) * scale.def)))
	# v2 元素抗性/易伤(默认 0 = 中立)
	elem_resist_fire = float(cfg.get("elem_resist_fire", 0.0))
	elem_resist_ice = float(cfg.get("elem_resist_ice", 0.0))
	elem_resist_thunder = float(cfg.get("elem_resist_thunder", 0.0))
	elem_resist_poison = float(cfg.get("elem_resist_poison", 0.0))
	vuln_physical = float(cfg.get("vuln_physical", 0.0))
	vuln_fire = float(cfg.get("vuln_fire", 0.0))
	vuln_ice = float(cfg.get("vuln_ice", 0.0))
	vuln_thunder = float(cfg.get("vuln_thunder", 0.0))
	vuln_poison = float(cfg.get("vuln_poison", 0.0))
	_apply_sprite()
	global_position = _pick_spawn_position()
	sprite.play(SpriteHelper.ANIM_IDLE)
	# 起步小 + 透明，让 update_boss 的 tween 拉到位（避免第一帧露出全尺寸）
	sprite.scale = Vector2.ONE * _base_sprite_scale * 0.4
	sprite.modulate.a = 0.0
	_spawn_appear_particles()


# Boss 出现：地面砖石粉尘 + 金色火星向外 + 屏抖
func _spawn_appear_particles() -> void:
	if battle == null:
		return
	battle.shake_camera(7.5, 0.35)
	if battle.particles == null:
		return
	# 24 个棕色尘土向外
	for i in range(24):
		var a := randf() * TAU
		var sp := randf_range(160.0, 320.0)
		battle.particles.emit_particle(
			global_position.x, global_position.y,
			cos(a) * sp, sin(a) * sp,
			randf_range(0.35, 0.6),
			randf_range(6.0, 11.0),
			Color("#8a6244"), 80.0, true, true
		)
	# 14 个金色火星更快、更亮、向上抛
	for i in range(14):
		var a2 := -PI * 0.5 + randf_range(-PI * 0.5, PI * 0.5)
		var sp2 := randf_range(240.0, 420.0)
		battle.particles.emit_particle(
			global_position.x, global_position.y,
			cos(a2) * sp2, sin(a2) * sp2,
			randf_range(0.3, 0.55),
			randf_range(4.0, 7.0),
			Color("#ffd040"), 320.0, true, false
		)


func _apply_sprite() -> void:
	var folder := str(cfg.get("character_folder", "Lancer"))
	var prefix := str(cfg.get("sprite_prefix", "Lancer"))
	sprite.sprite_frames = SpriteHelper.build_character_frames(folder, prefix)
	SpriteHelper.apply_pixel_art(sprite)
	var scale_val := float(GameConfig.get_tuning("monster_sprite_scale", 1.0))
	# pixel_scale 接受 size_mult 参数自动按 0.5 步进对齐避免糊边
	_base_sprite_scale = SpriteHelper.pixel_scale(scale_val, body_scale_mult)
	sprite.scale = Vector2.ONE * _base_sprite_scale


func _pick_spawn_position() -> Vector2:
	var safe: Vector2 = battle.player.global_position if battle and battle.player else Vector2(logical_w * 0.5, logical_h * 0.45)
	for _i in range(80):
		var pos := Vector2(
			MathUtils.rand_range(40.0, logical_w - 40.0),
			MathUtils.rand_range(play_top + 20.0, play_bottom - 20.0)
		)
		if pos.distance_to(safe) >= 150.0:
			return pos
	return Vector2(logical_w * 0.72, play_top + 80.0)


func get_hitbox_radius() -> float:
	return hitbox_radius


func is_combat_targetable() -> bool:
	return alive and phase == Phase.ACTIVE and not defeated


func get_active_segments() -> Array:
	if phase != Phase.ACTIVE or defeated:
		return []
	return [self]


func is_defeated() -> bool:
	return defeated


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	return apply_damage(raw_damage, from_pos)


# 新路径：透传到 apply_damage_info
func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	return apply_damage_info(info, from_pos)


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func apply_damage(raw_damage: int, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(DamageInfo.legacy(raw_damage), _from_pos)


# 新路径：接收 DamageInfo (供 v2 emitter 用)
func apply_damage_info(info: DamageInfo, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(info, _from_pos)


func _resolve_apply_damage(info: DamageInfo, _from_pos: Vector2) -> Dictionary:
	if defeated or phase != Phase.ACTIVE:
		return {"damage": 0, "is_crit": false}
	var target_stats := {
		"defense": defense,
		"vulnerable_mark": vulnerable_mark,
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
	if bool(res.get("vuln_consumed", false)):
		vulnerable_mark = false
	var actual := int(res.get("damage", 0))
	hp = maxi(0, hp - actual)
	facing = 1.0 if _from_pos.x >= global_position.x else -1.0
	sprite.flip_h = facing < 0
	if hp > 0:
		_play_anim(SpriteHelper.ANIM_HURT, true)
	if hp <= 0:
		_defeat()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false))}


func die() -> void:
	_defeat()


func activate() -> void:
	phase = Phase.ACTIVE
	skill_state = SkillState.CHASE
	skill_cooldown = float(cfg.get("skill_interval", 5.0))
	modulate = Color.WHITE


func update_boss(delta: float, player: BattlePlayer) -> void:
	# Boss 出现 tween：scale 0.6→1.0 (back-out)；alpha 0→1；冲击波扩散
	# 跨任何 phase 都跑（实际 WARNING 阶段刚 setup 完触发，0.65s 后退场）
	if appear_active:
		appear_timer = maxf(0.0, appear_timer - delta)
		_appear_shockwave_r += delta * 480.0
		_appear_shockwave_alpha = clampf(appear_timer / APPEAR_DURATION, 0.0, 1.0)
		var p: float = 1.0 - (appear_timer / APPEAR_DURATION)
		# back-out 缓动：1 - (1-p)^2 × (1 - 1.4*(1-p))
		var k: float = 1.0 - p
		var ease_p: float = 1.0 - k * k * (1.0 - 1.4 * k)
		var scale_now: float = _base_sprite_scale * lerpf(0.4, 1.0, clampf(ease_p, 0.0, 1.0))
		sprite.scale = Vector2.ONE * scale_now
		sprite.modulate.a = clampf(p * 1.6, 0.0, 1.0)
		if appear_timer <= 0.0:
			appear_active = false
			sprite.scale = Vector2.ONE * _base_sprite_scale
			sprite.modulate.a = 1.0
			modulate = Color.WHITE
		queue_redraw()
	match phase:
		Phase.WARNING:
			warning_timer -= delta
			warning_pulse += delta * 5.0
			if warning_timer <= 0.0:
				activate()
			queue_redraw()
		Phase.DEAD:
			death_fade_timer -= delta
			modulate.a = clampf(death_fade_timer / death_fade_dur, 0.0, 1.0)
			queue_redraw()
		Phase.ACTIVE:
			_update_active(delta, player)
			queue_redraw()


func _update_active(delta: float, player: BattlePlayer) -> void:
	if player == null:
		return
	contact_timer = maxf(0.0, contact_timer - delta)
	_speed_fx_t += delta
	_update_specter_archers(delta, player)
	match skill_state:
		SkillState.CHASE:
			_update_chase(delta, player)
		SkillState.WINDUP:
			_update_windup(delta, player)
		SkillState.SUPER_SPEED:
			_update_super_speed(delta, player)
	_update_facing(player)
	_try_contact_damage(player)


func _update_specter_archers(delta: float, player: BattlePlayer) -> void:
	var i := _specter_archers.size() - 1
	while i >= 0:
		var spec = _specter_archers[i]
		if not is_instance_valid(spec) or spec.get("alive") == false:
			_specter_archers.remove_at(i)
		else:
			spec.update_specter(delta, player)
		i -= 1


func _current_move_speed() -> float:
	var speed := move_speed
	if skill_state == SkillState.SUPER_SPEED:
		speed *= float(cfg.get("super_speed_mult", 2.0))
	return speed


func _update_chase(delta: float, player: BattlePlayer) -> void:
	skill_cooldown -= delta
	if skill_cooldown <= 0.0:
		_begin_skill(player)
		return
	var to_player := player.global_position - global_position
	if to_player.length_squared() <= 16.0:
		_play_anim(SpriteHelper.ANIM_IDLE)
		return
	global_position += to_player.normalized() * _current_move_speed() * delta
	global_position = _clamp_to_play_area(global_position)
	_play_anim(SpriteHelper.ANIM_WALK)


func _begin_skill(_player: BattlePlayer) -> void:
	skill_state = SkillState.WINDUP
	windup_timer = float(cfg.get("skill_windup", 1.5))
	pending_skill = SkillId.SPECTER_SUMMON if randf() < 0.5 else SkillId.SUPER_SPEED
	_play_anim(SpriteHelper.ANIM_IDLE)


func _update_windup(delta: float, player: BattlePlayer) -> void:
	windup_timer -= delta
	_warning_alpha = 0.45 + sin(_speed_fx_t * 8.0) * 0.25
	if windup_timer > 0.0:
		return
	if pending_skill == SkillId.SPECTER_SUMMON:
		_summon_specter_archers(player)
		_finish_skill()
	elif pending_skill == SkillId.SUPER_SPEED:
		skill_state = SkillState.SUPER_SPEED
		super_speed_timer = float(cfg.get("super_speed_duration", 5.0))
		skill_cooldown = float(cfg.get("skill_interval", 5.0))
		if battle:
			battle.shake_camera(4.0, 0.18)


func _summon_specter_archers(player: BattlePlayer) -> void:
	if battle == null:
		return
	_clear_specter_archers()
	var count := maxi(1, int(cfg.get("specter_count", 2)))
	var tint := Color(str(cfg.get("specter_tint_hex", "#9a5acc")))
	var alpha := float(cfg.get("specter_alpha", 0.52))
	var attack_mult := float(cfg.get("specter_attack_mult", 1.0))
	var container: Node2D = battle.monster_container
	if container == null:
		return
	for _i in range(count):
		var spec: SpecterArcher = SpecterArcherScript.new()
		container.add_child(spec)
		spec.setup(battle, stage_index, _pick_specter_spawn_position(player), tint, alpha, attack_mult)
		_specter_archers.append(spec)
	if battle:
		battle.shake_camera(3.0, 0.15)
		if battle.particles:
			for spec in _specter_archers:
				if is_instance_valid(spec):
					battle.particles.emit_particle(
						spec.global_position.x,
						spec.global_position.y,
						0,
						-12,
						0.4,
						6.0,
						Color("#b878e8"),
						0,
						false,
						false
					)


func _pick_specter_spawn_position(player: BattlePlayer) -> Vector2:
	var safe := player.global_position if player else Vector2(logical_w * 0.5, logical_h * 0.5)
	for _i in range(60):
		var pos := Vector2(
			MathUtils.rand_range(36.0, logical_w - 36.0),
			MathUtils.rand_range(play_top + 16.0, play_bottom - 16.0)
		)
		if pos.distance_to(safe) >= 72.0 and pos.distance_to(global_position) >= 48.0:
			return pos
	return Vector2(
		MathUtils.rand_range(36.0, logical_w - 36.0),
		MathUtils.rand_range(play_top + 16.0, play_bottom - 16.0)
	)


func _clear_specter_archers() -> void:
	for spec in _specter_archers:
		if is_instance_valid(spec):
			spec.dismiss()
	_specter_archers.clear()


func _update_super_speed(delta: float, player: BattlePlayer) -> void:
	super_speed_timer -= delta
	var to_player := player.global_position - global_position
	if to_player.length_squared() > 16.0:
		global_position += to_player.normalized() * _current_move_speed() * delta
		global_position = _clamp_to_play_area(global_position)
		_play_anim(SpriteHelper.ANIM_WALK)
	else:
		_play_anim(SpriteHelper.ANIM_IDLE)
	if super_speed_timer <= 0.0:
		skill_state = SkillState.CHASE
		modulate = Color.WHITE


func _finish_skill() -> void:
	skill_state = SkillState.CHASE
	skill_cooldown = float(cfg.get("skill_interval", 5.0))
	pending_skill = ""
	modulate = Color.WHITE


func _clamp_to_play_area(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 24.0, logical_w - 24.0),
		clampf(pos.y, play_top, play_bottom)
	)


func _update_facing(player: BattlePlayer) -> void:
	if player == null:
		return
	var to_player := player.global_position - global_position
	if absf(to_player.x) > 2.0:
		facing = 1.0 if to_player.x >= 0 else -1.0
		sprite.flip_h = facing < 0


func _try_contact_damage(player: BattlePlayer) -> void:
	if contact_timer > 0.0 or player == null or player.hp <= 0:
		return
	if battle and battle.combat and not battle.combat.should_monsters_attack(player):
		return
	var touch_r := hitbox_radius + player.get_effective_radius() * 0.55
	if global_position.distance_to(player.global_position) > touch_r:
		return
	contact_timer = float(cfg.get("contact_interval", 0.8))
	var dealt := player.take_damage(int(cfg.get("contact_damage", 18)))
	if dealt > 0 and battle and battle.combat:
		battle.combat.spawn_damage_number(
			player.global_position + Vector2(0.0, -player.get_effective_radius() - 8.0),
			dealt,
			false,
			false,
			Color("#e05840")
		)


func _play_anim(anim_name: String, force: bool = false) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		if anim_name != SpriteHelper.ANIM_IDLE:
			_play_anim(SpriteHelper.ANIM_IDLE, force)
		return
	if not force and sprite.animation == anim_name and sprite.is_playing():
		return
	if force and sprite.animation == anim_name:
		sprite.stop()
		sprite.frame = 0
	sprite.play(anim_name)


func _defeat() -> void:
	if defeated:
		return
	_clear_specter_archers()
	hp = 0
	defeated = true
	alive = false
	dying = true
	phase = Phase.DEAD
	death_fade_timer = death_fade_dur
	_play_anim(SpriteHelper.ANIM_DEATH, true)
	if battle and battle.blood_stains:
		var hit_angle := 0.0
		if battle.player:
			hit_angle = (global_position - battle.player.global_position).angle()
		battle.blood_stains.spawn(global_position.x, global_position.y, 1.4, hit_angle)
	if battle and battle.particles:
		battle.particles.death_effect(global_position, Color("#7a3030"))
	if not defeat_rewarded and battle and battle.experience:
		defeat_rewarded = true
		battle.experience.add_exp(int(cfg.get("defeat_exp", 140)))
	if battle and battle.hud:
		battle.hud.show_message("%s 击破!" % get_display_name(), 2.0)


func get_warning_text() -> String:
	return str(maxi(1, int(ceil(warning_timer))))


func _draw_warning_overlay() -> void:
	# 警告视觉重做（替代纯红色矩形描边）：
	# 1. 屏幕外圈深色 vignette 渐淡 — 玩家视野收紧
	# 2. 上下两条扫动 chevron（黄/红箭头条纹）— 强烈"小心冲锋"暗示
	# 3. boss 周围多层警告环（红 + 金）— 标记目标
	# 4. 倒计时进度按 stage 边框内缩 — 时间感
	# origin: world (0,0) 相对自己 = -global_position
	var origin: Vector2 = -global_position
	var t: float = warning_pulse
	# 警告强度：剩余越少越急
	var urgency: float = clampf(1.0 - warning_timer / maxf(0.001, warning_total), 0.0, 1.0)
	var fast_pulse: float = 0.5 + 0.5 * sin(t * (6.0 + urgency * 8.0))
	# 1) Vignette: 屏幕外圈黑色衰减（从边缘到中心淡出）
	var vignette_a: float = 0.18 + 0.10 * urgency + 0.06 * fast_pulse
	var vignette_thick: float = 32.0 + 12.0 * urgency
	draw_rect(Rect2(origin, Vector2(logical_w, vignette_thick)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin + Vector2(0, logical_h - vignette_thick), Vector2(logical_w, vignette_thick)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin, Vector2(vignette_thick, logical_h)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin + Vector2(logical_w - vignette_thick, 0), Vector2(vignette_thick, logical_h)), Color(0.05, 0.0, 0.02, vignette_a))
	# 2) 上下 chevron 扫动条 —— 8 个三角形像素箭头，沿 X 方向滚动，方向相对（上往右、下往左）
	_draw_warning_chevron_band(origin + Vector2(0, vignette_thick - 4.0), logical_w, t, 1.0, urgency)
	_draw_warning_chevron_band(origin + Vector2(0, logical_h - vignette_thick - 14.0), logical_w, t, -1.0, urgency)
	# 3) boss 周围多层环：内圈红，中圈金，外圈淡白 — 标记目标
	var pulse_r: float = 38.0 + sin(t * 7.0) * 6.0
	draw_arc(Vector2.ZERO, pulse_r, 0.0, TAU, 48, Color(1.0, 0.18, 0.18, 0.85), 4.0)
	draw_arc(Vector2.ZERO, pulse_r + 14.0, 0.0, TAU, 48, Color(1.0, 0.78, 0.20, 0.6), 2.5)
	draw_arc(Vector2.ZERO, pulse_r + 24.0 + sin(t * 4.0) * 4.0, 0.0, TAU, 48, Color(1.0, 0.95, 0.7, 0.32 + 0.18 * fast_pulse), 1.5)
	# 红色脉冲填充（淡）
	draw_circle(Vector2.ZERO, pulse_r * 0.85, Color(1.0, 0.18, 0.10, 0.08 + 0.10 * fast_pulse))
	# 4) 边框（红+金双层）按倒计时进度收紧 —— 玩家看见 frame 在向中心压
	var inset: float = lerpf(2.0, 18.0, urgency)
	var inner_origin: Vector2 = origin + Vector2(inset, inset)
	var inner_size: Vector2 = Vector2(logical_w - inset * 2.0, logical_h - inset * 2.0)
	var border_w_inner: float = 4.0 + 3.0 * fast_pulse
	draw_rect(Rect2(inner_origin, inner_size), Color(1.0, 0.18, 0.18, 0.72), false, border_w_inner)
	draw_rect(Rect2(inner_origin + Vector2(border_w_inner, border_w_inner) * 0.5, inner_size - Vector2(border_w_inner, border_w_inner)), Color(1.0, 0.82, 0.25, 0.55), false, 1.5)


# 8 个朝向 dir 的扫动三角箭头，间距 90px，整体随 t 滚动，速度按 urgency 加快。
# dir=+1 朝右；dir=-1 朝左。每个箭头 14px 高 × 18px 宽，黄/红渐变。
func _draw_warning_chevron_band(top_left: Vector2, band_w: float, t: float, dir: float, urgency: float) -> void:
	var roll: float = fposmod(t * (90.0 + 60.0 * urgency) * dir, 90.0)
	var arrow_h: float = 14.0
	var arrow_w: float = 22.0
	var y: float = top_left.y
	var x_start: float = top_left.x - 90.0
	var n: int = int(ceil((band_w + 180.0) / 90.0))
	var col_outer := Color(1.0, 0.20, 0.18, 0.85)
	var col_inner := Color(1.0, 0.85, 0.28, 0.95)
	var outer_colors := PackedColorArray([col_outer, col_outer, col_outer])
	var inner_colors := PackedColorArray([col_inner, col_inner, col_inner])
	for i in range(n):
		var cx: float = x_start + roll + float(i) * 90.0
		var tip_x: float = cx + arrow_w * 0.5 * dir
		var base_x: float = cx - arrow_w * 0.5 * dir
		var top_y: float = y
		var bot_y: float = y + arrow_h
		var pts := PackedVector2Array([
			Vector2(tip_x, y + arrow_h * 0.5),
			Vector2(base_x, top_y),
			Vector2(base_x, bot_y),
		])
		draw_polygon(pts, outer_colors)
		# 内层小箭头（金心）
		var shrink: float = 5.0
		var pts2 := PackedVector2Array([
			Vector2(tip_x - shrink * dir, y + arrow_h * 0.5),
			Vector2(base_x + shrink * dir, top_y + 3.0),
			Vector2(base_x + shrink * dir, bot_y - 3.0),
		])
		draw_polygon(pts2, inner_colors)


# Boss 出现：黄色扩散冲击波（绘制在 _draw 末尾，不受 warning vignette 影响）
func _draw_appear_shockwave() -> void:
	if not appear_active and _appear_shockwave_alpha <= 0.01:
		return
	var ring_w: float = 6.0 * _appear_shockwave_alpha
	var col_outer := Color(1.0, 0.85, 0.30, 0.6 * _appear_shockwave_alpha)
	var col_inner := Color(1.0, 1.0, 0.7, 0.85 * _appear_shockwave_alpha)
	draw_arc(Vector2.ZERO, _appear_shockwave_r, 0.0, TAU, 48, col_outer, ring_w)
	draw_arc(Vector2.ZERO, _appear_shockwave_r * 0.7, 0.0, TAU, 48, col_inner, ring_w * 0.6)
	# 内圈实心闪光
	draw_circle(Vector2.ZERO, maxf(0.0, 28.0 - _appear_shockwave_r * 0.1), Color(1.0, 0.95, 0.65, 0.45 * _appear_shockwave_alpha))


func _draw_skill_windup(ring_color: Color, marker_color: Color) -> void:
	var total := float(cfg.get("skill_windup", 1.5))
	var progress := 1.0 - clampf(windup_timer / maxf(0.001, total), 0.0, 1.0)
	var pulse := 0.55 + sin(_speed_fx_t * 12.0) * 0.25
	draw_arc(Vector2.ZERO, hitbox_radius + 10.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 28, Color(ring_color.r, ring_color.g, ring_color.b, pulse), 3.0)
	draw_rect(Rect2(-4.0, -hitbox_radius - 14.0, 8.0, 8.0), Color(marker_color.r, marker_color.g, marker_color.b, pulse))


func _draw_super_speed_windup() -> void:
	_draw_skill_windup(Color(1.0, 0.78, 0.22), Color(1.0, 0.86, 0.34))


func _draw_specter_summon_windup() -> void:
	_draw_skill_windup(Color(0.62, 0.38, 0.95), Color(0.78, 0.55, 1.0))
	var pulse := 0.35 + sin(_speed_fx_t * 9.0) * 0.2
	for i in range(maxi(1, int(cfg.get("specter_count", 1)))):
		var ang := _speed_fx_t * 2.4 + float(i) * PI
		var offset := Vector2(cos(ang), sin(ang)) * (hitbox_radius + 22.0)
		draw_arc(offset, 7.0, 0.0, TAU, 16, Color(0.72, 0.45, 0.98, pulse), 2.0)


func _draw_super_speed_fx() -> void:
	var pulse := 0.65 + sin(_speed_fx_t * 14.0) * 0.35
	modulate = Color(1.0 + pulse * 0.25, 0.92 + pulse * 0.08, 0.55 + pulse * 0.1)
	var back := Vector2(-facing, 0.0)
	for i in range(5):
		var dist := 10.0 + float(i) * 7.0
		var alpha := 0.55 - float(i) * 0.09
		var size := 3.0 - float(i) * 0.35
		var offset := back * dist + Vector2(0.0, sin(_speed_fx_t * 16.0 + float(i)) * 2.0)
		draw_rect(
			Rect2(offset.x - size, offset.y - size, size * 2.0, size * 2.0),
			Color(1.0, 0.82, 0.28, alpha)
		)
	draw_rect(Rect2(-14.0, -18.0, 28.0, 36.0), Color(1.0, 0.72, 0.18, 0.12 + pulse * 0.08), false, 2.0)


func _draw() -> void:
	if phase == Phase.WARNING:
		_draw_warning_overlay()
	if phase == Phase.ACTIVE and skill_state == SkillState.WINDUP and pending_skill == SkillId.SPECTER_SUMMON:
		_draw_specter_summon_windup()
	elif phase == Phase.ACTIVE and skill_state == SkillState.WINDUP and pending_skill == SkillId.SUPER_SPEED:
		_draw_super_speed_windup()
	if phase == Phase.ACTIVE and skill_state == SkillState.SUPER_SPEED:
		_draw_super_speed_fx()
	if path_target_hit_count > 0:
		var ring := CombatDirector.path_preview_ring_color(path_target_hit_count)
		draw_arc(Vector2.ZERO, hitbox_radius + 5.0, 0.0, TAU, 24, ring, 3.0)
	# Boss 出现冲击波（warning 阶段前 0.65s，扩散黄色 ring）
	if appear_active or _appear_shockwave_alpha > 0.01:
		_draw_appear_shockwave()
