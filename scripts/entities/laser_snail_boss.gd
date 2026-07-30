extends Node2D
class_name LaserSnailBoss

# ===================== 激光蜗牛 BOSS =====================
# 缓慢朝玩家移动;每 skill_interval(默认 3s)释放一次技能:
#   释放时停止移动,按先后顺序逐道发射 LASER_COUNT(默认 10)道粗激光,
#   每道激光 = 红色路径预警 LASER_WINDUP → 射出粗激光束 LASER_FIRE(沿途伤害一次)→ 下一道,
#   方向随机(均匀覆盖 + 抖动,避免聚堆)。10 道射完 → 回移动阶段,重新计 3s 冷却。
# 激光效果参考 LASER 激光怪(_draw_laser 同款三层绘制 + 垂距命中判定),
# 但半宽 36(激光怪 14 的 ~2.6×),粗得多。
#
# 单体 BOSS(同暗黑龙):精灵图集取第 3 排(朝右),朝左靠 flip_h;
# attack 图集画布(144)比 idle/walk(48)大,但蜗牛身体等高,
# 用同一每像素缩放(以 idle 48 为基准),_anim_comp 留空 —— 同龙/骑士/史莱姆。

enum Phase { WARNING, ACTIVE, DEAD }
enum CastState { MOVE, CAST }

const SNAIL_BASE_FRAME_H := 48.0
const SNAIL_ROW := 2
const APPEAR_DURATION := 0.65
const HURT_FLASH_DUR := 0.18

# 技能:每 skill_interval 秒释放,一次性同时放出 LASER_COUNT 道粗激光,
# 但各道预警按 LASER_STAGGER 错峰亮起(同时放、有先后顺序),各自 windup→fire。
const LASER_COUNT := 10
const LASER_WINDUP := 1.0         # 每道激光预警时长(预警后 1s 再射出)
const LASER_FIRE := 0.30          # 每道激光射束时长(命中一次)
const LASER_STAGGER := 0.15       # 相邻激光预警错开间隔(同时放,但按先后顺序亮起)
const LASER_LENGTH := 1400.0     # 激光长度(逻辑像素,同激光怪)
const LASER_HALF_WIDTH := 36.0    # 激光半宽(激光怪 14 → 这里粗得多)

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
var hitbox_radius := 40.0
var body_scale_mult := 1.0
var move_speed := 38.0
var alive := true
var dying := false

var _cast_state := CastState.MOVE
var skill_timer := 3.0
# 本轮激光列表(同时施法、错峰亮起):每项 {dir, delay, phase(0等/1预警/2射束/3结束), timer, hit}
var _lasers: Array = []

var contact_timer := 0.0
var facing := 1.0
var _hurt_flash_t := 0.0
var _speed_fx_t := 0.0
var path_target_hit_count := 0

var appear_timer := 0.0
var appear_active := false
var _appear_shockwave_r := 0.0
var _appear_shockwave_alpha := 0.0

var death_fade_timer := 0.0
var death_fade_dur := 0.45

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

var _base_sprite_scale := 1.0
var _anim_comp := {}

var logical_w := 720.0
var logical_h := 1280.0
var play_top := 88.0
var play_bottom := 580.0

var sprite: AnimatedSprite2D
var _marker_overlay: Node2D


func _init() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)
	# 画线攻击标记圆圈:排在精灵之后的子节点,画在顶层(同龙/骑士)
	_marker_overlay = BossMarkerOverlay.new()
	_marker_overlay.name = "MarkerOverlay"
	add_child(_marker_overlay)


func is_boss_active() -> bool:
	return phase == Phase.ACTIVE


func get_hp_ratio() -> float:
	return clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)


func get_display_name() -> String:
	return str(cfg.get("name", "激光蜗牛"))


func get_hitbox_radius() -> float:
	return hitbox_radius


func setup(battle_node, p_stage_index: int) -> void:
	battle = battle_node
	stage_index = p_stage_index
	cfg = GameConfig.bosses.get("laser_snail", {})
	logical_w = float(GameConfig.get_tuning("logical_width", 720))
	logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	play_top = 88.0
	play_bottom = logical_h - 120.0
	hitbox_radius = float(cfg.get("hitbox_radius", 40))
	body_scale_mult = float(cfg.get("body_scale_mult", 1.0))
	hitbox_radius *= body_scale_mult
	move_speed = float(cfg.get("move_speed", 38))
	warning_timer = float(cfg.get("warning_time", 3.0))
	warning_total = warning_timer
	phase = Phase.WARNING
	defeated = false
	defeat_rewarded = false
	_cast_state = CastState.MOVE
	skill_timer = float(cfg.get("skill_interval", 3.0))
	appear_active = true
	appear_timer = APPEAR_DURATION
	_appear_shockwave_r = 0.0
	_appear_shockwave_alpha = 1.0
	var stat_scale = GameConfig.stage_stat_scale(stage_index)
	max_hp = int(round(float(cfg.get("hp", 3000)) * stat_scale.hp))
	hp = max_hp
	defense = maxi(1, int(round(float(cfg.get("def", 8)) * stat_scale.def)))
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
	# 起步小+透明,让 update_boss 的 appear tween 拉到位
	sprite.scale = Vector2.ONE * _base_sprite_scale * 0.4
	sprite.modulate.a = 0.0
	_spawn_appear_particles()


# Boss 出现:地面粉尘 + 青绿能量火星 + 屏抖(蜗牛主色青绿)
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
			Color("#3a5a4a"), 80.0, true, true
		)
	for i in range(14):
		var a2 := -PI * 0.5 + randf_range(-PI * 0.5, PI * 0.5)
		var sp2 := randf_range(240.0, 420.0)
		battle.particles.emit_particle(
			global_position.x, global_position.y,
			cos(a2) * sp2, sin(a2) * sp2,
			randf_range(0.3, 0.55),
			randf_range(4.0, 7.0),
			Color("#5ae8c0"), 320.0, true, false
		)


func _apply_sprite() -> void:
	# 蜗牛素材:三张 4 行 spritesheet(idle 192² 4×4/48 / walk 192² 4×4/48 / attack 720×576 5×4/144)。
	# 只取第 3 行(朝右,0-indexed=2),朝左靠 flip_h —— 同龙/骑士/史莱姆。
	var specs := {
		SpriteHelper.ANIM_IDLE: {
			"path": "res://assets/Characters/Characters2/ElderSnail/ElderSnail_idle.png",
			"frame_w": 48, "frame_h": 48, "row": SNAIL_ROW, "cols": 4, "fps": 6.0, "loop": true,
		},
		SpriteHelper.ANIM_WALK: {
			"path": "res://assets/Characters/Characters2/ElderSnail/ElderSnail_walk.png",
			"frame_w": 48, "frame_h": 48, "row": SNAIL_ROW, "cols": 4, "fps": 10.0, "loop": true,
		},
		SpriteHelper.ANIM_ATTACK: {
			"path": "res://assets/Characters/Characters2/ElderSnail/ElderSnail_attack_NOhitbox.png",
			"frame_w": 144, "frame_h": 144, "row": SNAIL_ROW, "cols": 5, "fps": 12.0, "loop": false,
		},
	}
	sprite.sprite_frames = EffectHelper.build_row_character_frames("char_laser_snail", specs)
	SpriteHelper.apply_pixel_art(sprite)
	# 同龙/骑士:_anim_comp 留空(三张图身体等高 48),只按 idle 帧高 48 做每像素缩放。
	# attack 画布 144 但蜗牛身体只占一部分,留白透明无妨,身体自然等大。
	_anim_comp.clear()
	var target_h := float(cfg.get("display_height", 200))
	_base_sprite_scale = SpriteHelper.pixel_scale(target_h / SNAIL_BASE_FRAME_H, 1.0)


func _apply_snail_scale(anim_name: String = "") -> void:
	if anim_name.is_empty():
		anim_name = sprite.animation
	var comp := float(_anim_comp.get(anim_name, 1.0))
	sprite.scale = Vector2.ONE * _base_sprite_scale * comp


func _pick_spawn_position() -> Vector2:
	var safe: Vector2 = battle.player.global_position if battle and battle.player else Vector2(logical_w * 0.5, logical_h * 0.45)
	var base := Vector2(logical_w * 0.5, play_top + 140.0)
	if base.distance_to(safe) < 220.0:
		base.x = logical_w * 0.28 if safe.x > logical_w * 0.5 else logical_w * 0.72
	return base


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


func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	return apply_damage_info(info, from_pos)


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func apply_damage(raw_damage: int, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(DamageInfo.legacy(raw_damage), _from_pos)


func apply_damage_info(info: DamageInfo, _from_pos: Vector2) -> Dictionary:
	return _resolve_apply_damage(info, _from_pos)


func _resolve_apply_damage(info: DamageInfo, _from_pos: Vector2) -> Dictionary:
	if defeated or phase != Phase.ACTIVE:
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
	hp = maxi(0, hp - actual)
	if _from_pos.x >= global_position.x:
		facing = 1.0
	else:
		facing = -1.0
	sprite.flip_h = facing < 0
	if hp > 0:
		_hurt_flash_t = HURT_FLASH_DUR
	if hp <= 0:
		_defeat()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false))}


func die() -> void:
	_defeat()


func activate() -> void:
	phase = Phase.ACTIVE
	_cast_state = CastState.MOVE
	skill_timer = float(cfg.get("skill_interval", 3.0))


func update_boss(delta: float, player: BattlePlayer) -> void:
	_speed_fx_t += delta
	# Boss 出现 tween:scale 0.4→1 + alpha 0→1 + 黄色冲击波
	if appear_active:
		appear_timer = maxf(0.0, appear_timer - delta)
		_appear_shockwave_r += delta * 480.0
		_appear_shockwave_alpha = clampf(appear_timer / APPEAR_DURATION, 0.0, 1.0)
		var p: float = 1.0 - (appear_timer / APPEAR_DURATION)
		var k: float = 1.0 - p
		var ease_p: float = 1.0 - k * k * (1.0 - 1.4 * k)
		var comp := float(_anim_comp.get(sprite.animation, 1.0))
		var scale_now: float = _base_sprite_scale * comp * lerpf(0.4, 1.0, clampf(ease_p, 0.0, 1.0))
		sprite.scale = Vector2.ONE * scale_now
		sprite.modulate.a = clampf(p * 1.6, 0.0, 1.0)
		if appear_timer <= 0.0:
			appear_active = false
			_apply_snail_scale(sprite.animation)
			sprite.modulate.a = 1.0
	match phase:
		Phase.WARNING:
			warning_timer -= delta
			warning_pulse += delta * 5.0
			if warning_timer <= 0.0:
				activate()
		Phase.DEAD:
			death_fade_timer -= delta
		Phase.ACTIVE:
			_update_active(delta, player)
	_apply_modulate()
	queue_redraw()
	if _marker_overlay:
		_marker_overlay.queue_redraw()


func _apply_modulate() -> void:
	if appear_active:
		return
	var a := 1.0
	if phase == Phase.DEAD:
		a = clampf(death_fade_timer / death_fade_dur, 0.0, 1.0)
	if _hurt_flash_t > 0.0 and a > 0.0:
		var kk := _hurt_flash_t / HURT_FLASH_DUR
		modulate = Color(1.0, 1.0 - 0.6 * kk, 1.0 - 0.6 * kk, a)
	else:
		modulate = Color(1.0, 1.0, 1.0, a)


func _update_active(delta: float, player: BattlePlayer) -> void:
	if player == null:
		return
	contact_timer = maxf(0.0, contact_timer - delta)
	if _hurt_flash_t > 0.0:
		_hurt_flash_t = maxf(0.0, _hurt_flash_t - delta)
	match _cast_state:
		CastState.MOVE:
			_update_move(delta, player)
		CastState.CAST:
			_update_cast(delta, player)
	_update_facing(player)
	_try_contact_damage(player)


# 移动阶段:缓慢朝玩家移动(保持一定交战距离,不至于贴脸),倒计时到 → 进入施法
func _update_move(delta: float, player: BattlePlayer) -> void:
	if not (sprite.animation == SpriteHelper.ANIM_ATTACK and sprite.is_playing()):
		_play_anim(SpriteHelper.ANIM_WALK)
	var to_p: Vector2 = player.global_position - global_position
	var dist: float = to_p.length()
	var standoff := float(cfg.get("standoff_range", 220.0))
	if dist > standoff and dist > 1.0:
		var dir: Vector2 = to_p / dist
		global_position += dir * move_speed * delta
	_clamp_to_play_area()
	skill_timer -= delta
	if skill_timer <= 0.0:
		_begin_cast(player)


# 进入施法:一次性生成 LASER_COUNT 道激光,方向朝玩家大概范围的随机扇形(±spread),
# 预警按 LASER_STAGGER 错峰亮起(同时放、有先后顺序),各自 windup→fire。
func _begin_cast(player: BattlePlayer) -> void:
	_cast_state = CastState.CAST
	_lasers.clear()
	var base_ang: float = (player.global_position - global_position).angle() if player != null else 0.0
	var spread := deg_to_rad(float(cfg.get("laser_spread_deg", 70.0)))
	for i in range(LASER_COUNT):
		var ang := base_ang + randf_range(-spread, spread)
		_lasers.append({
			"dir": Vector2(cos(ang), sin(ang)),
			"delay": float(i) * LASER_STAGGER,
			"phase": 0,
			"timer": 0.0,
			"hit": false,
		})
	_play_anim(SpriteHelper.ANIM_ATTACK, true)


# 施法阶段:停止移动,10 道激光同时推进、错峰亮起;全部射完 → 回移动阶段重新计冷却
func _update_cast(delta: float, player: BattlePlayer) -> void:
	var all_done := true
	for L in _lasers:
		match int(L.phase):
			0:  # 等待错峰开始
				L.delay = float(L.delay) - delta
				if float(L.delay) <= 0.0:
					L.phase = 1
					L.timer = LASER_WINDUP
				all_done = false
			1:  # windup 红色路径预警
				L.timer = float(L.timer) - delta
				if float(L.timer) <= 0.0:
					L.phase = 2
					L.timer = LASER_FIRE
					L.hit = false
					if battle and battle.has_method("shake_camera"):
						battle.shake_camera(1.8, 0.06)
				else:
					all_done = false
			2:  # fire 粗激光束(沿途伤害一次)
				L.timer = float(L.timer) - delta
				_apply_laser_damage(L, player)
				if float(L.timer) <= 0.0:
					L.phase = 3
				else:
					all_done = false
			3:
				pass
	queue_redraw()
	if all_done:
		_cast_state = CastState.MOVE
		skill_timer = float(cfg.get("skill_interval", 3.0))
		_lasers.clear()
		_play_anim(SpriteHelper.ANIM_WALK)


# 玩家到激光射线(自 boss 沿 L.dir)的垂直距离判定,命中则造伤一次(同激光怪,但更粗)
func _apply_laser_damage(L: Dictionary, player: BattlePlayer) -> void:
	if bool(L.hit) or player == null or player.hp <= 0:
		return
	if player.state == BattlePlayer.State.BULLET_TIME or player.is_attack_invincible():
		return
	var ldir: Vector2 = L.dir
	var to_p: Vector2 = player.global_position - global_position
	var proj: float = to_p.dot(ldir)
	if proj < 0.0 or proj > LASER_LENGTH:
		return
	var perp: Vector2 = to_p - ldir * proj
	if perp.length() > LASER_HALF_WIDTH + player.get_effective_radius():
		return
	L.hit = true
	var dmg: int = int(cfg.get("laser_damage", 18))
	var dealt := player.take_damage(dmg)
	if dealt > 0 and battle and battle.combat:
		battle.combat.spawn_damage_number(
			player.global_position + Vector2(0.0, -player.get_effective_radius() - 8.0),
			dealt, false, false, Color("#ff4040")
		)
	if battle and battle.particles:
		battle.particles.hit_spark(player.global_position, false)


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
	contact_timer = float(cfg.get("contact_interval", 1.0))
	var dealt := player.take_damage(int(cfg.get("contact_damage", 16)))
	if dealt > 0 and battle and battle.combat:
		battle.combat.spawn_damage_number(
			player.global_position + Vector2(0.0, -player.get_effective_radius() - 8.0),
			dealt, false, false, Color("#5ae8a0")
		)


func _clamp_to_play_area() -> void:
	var r := hitbox_radius
	global_position.x = clampf(global_position.x, r, logical_w - r)
	global_position.y = clampf(global_position.y, play_top + r, play_bottom - r)


func _play_anim(anim_name: String, force: bool = false) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		if anim_name != SpriteHelper.ANIM_IDLE:
			_play_anim(SpriteHelper.ANIM_IDLE, force)
		return
	if not force and sprite.animation == anim_name and sprite.is_playing():
		_apply_snail_scale(anim_name)
		return
	if force and sprite.animation == anim_name:
		sprite.stop()
		sprite.frame = 0
	sprite.play(anim_name)
	_apply_snail_scale(anim_name)


func _defeat() -> void:
	if defeated:
		return
	hp = 0
	defeated = true
	alive = false
	dying = true
	phase = Phase.DEAD
	death_fade_timer = death_fade_dur
	sprite.stop()
	if battle and battle.blood_stains:
		var hit_angle := 0.0
		if battle.player:
			hit_angle = (global_position - battle.player.global_position).angle()
		battle.blood_stains.spawn(global_position.x, global_position.y, 1.6, hit_angle)
	if battle and battle.particles:
		battle.particles.death_effect(global_position, Color("#3a5a4a"))
	if not defeat_rewarded and battle and battle.experience:
		defeat_rewarded = true
		battle.experience.add_exp(int(cfg.get("defeat_exp", 180)))
	if battle and battle.hud:
		battle.hud.show_message("%s 击破!" % get_display_name(), 2.0)


func get_warning_text() -> String:
	return str(maxi(1, int(ceil(warning_timer))))


# ===================== 绘制 =====================

func _draw() -> void:
	# 激光(预警带 / 射束)与 appear 冲击波画在 boss 本体 _draw 里;父 _draw 画在子节点
	# AnimatedSprite2D 之下(同激光怪)——激光从 boss 中心射出,长 1400 远超身体,
	# 只有穿过身体的一小段被精灵盖住,其余可见,视觉与激光怪一致。
	if phase == Phase.ACTIVE and _cast_state == CastState.CAST:
		for L in _lasers:
			match int(L.phase):
				1:
					_draw_laser_warning(L.dir)
				2:
					_draw_laser_fire(L.dir)
	if appear_active or _appear_shockwave_alpha > 0.01:
		_draw_appear_shockwave()


# 激光预警:深红半透明带(显示激光将出现的位置与粗细),脉动闪烁
func _draw_laser_warning(p_dir: Vector2) -> void:
	var end := p_dir * LASER_LENGTH
	var pulse := 0.5 + 0.5 * sin(_speed_fx_t * 10.0)
	# 危险带主体(半宽 = LASER_HALF_WIDTH,提示玩家激光有多粗)——深血红色,比射束更暗
	draw_line(Vector2.ZERO, end, Color(0.55, 0.05, 0.05, 0.45 + pulse * 0.25), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH * 2.0)))
	# 中心细暗线
	draw_line(Vector2.ZERO, end, Color(0.78, 0.18, 0.15, 0.65 + pulse * 0.25), maxf(1.0, GameConfig.scale_world(2.5)))


# 激光射束:外发光 + 主体 + 核心(三层,同激光怪,但半宽 36 → 粗得多)
func _draw_laser_fire(p_dir: Vector2) -> void:
	var end := p_dir * LASER_LENGTH
	var flicker := 0.85 + 0.15 * sin(_speed_fx_t * 22.0)
	# 外发光
	draw_line(Vector2.ZERO, end, Color(1.0, 0.25, 0.2, 0.35 * flicker), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH * 2.2)))
	# 主体
	draw_line(Vector2.ZERO, end, Color(1.0, 0.35, 0.25, 0.9), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH)))
	# 核心
	draw_line(Vector2.ZERO, end, Color(1.0, 0.95, 0.85, flicker), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH * 0.4)))


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
