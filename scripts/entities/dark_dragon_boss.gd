extends Node2D
class_name DarkDragonBoss

# ===================== 暗黑龙 BOSS =====================
# 定点站桩:每 fire_interval 朝玩家发一发火球(auto_bullet 视觉)。
# 技能(每 skill_interval=5s):跳跃 —— 参考 JUMPER 状态机
#   windup(下沉蓄力) → 起跳出屏+脚下 spawn_smash 预警 → 落到玩家原位
#   → 喷大量不规则火球霰弹(随机角度/速度) → recover → 回站桩。
# 受击:闪红(无 hurt 动画)。死亡:渐隐(无 death 动画)。
# 龙精灵只取每张图第 3 排(朝右),朝左靠 flip_h(见 _apply_sprite)。

enum Phase { WARNING, ACTIVE, DEAD }
enum MoveState { BREATH, JUMP_WINDUP, JUMP_AIR, JUMP_LAND, JUMP_RECOVER }

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
var hitbox_radius := 18.0
var body_scale_mult := 1.4
var alive := true
var dying := false

var move_state := MoveState.BREATH
var skill_cooldown := 5.0
var fire_timer := 0.0
var jump_timer := 0.0
var jump_target := Vector2.ZERO
var recover_timer := 0.0
var contact_timer := 0.0
var facing := 1.0
var _speed_fx_t := 0.0
var _hurt_flash_t := 0.0
# 画线攻击(路径预览)命中计数 —— 由 CombatDirector 写入,>0 时身上画圆圈标记,同小怪
var path_target_hit_count := 0

const JUMP_WINDUP := 0.8
const JUMP_AIR := 1.6
const JUMP_RECOVER := 0.5
const HURT_FLASH_DUR := 0.18

const APPEAR_DURATION := 0.65
var appear_timer := 0.0
var appear_active := false
var _appear_shockwave_r := 0.0
var _appear_shockwave_alpha := 0.0

var death_fade_timer := 0.0
var death_fade_dur := 0.45

# v2 元素抗性/易伤(从 bosses.json 加载,默认 0 = 中立)
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
# 三张图帧尺寸不一(idle 144 / fly 192×144 / attack 432),按每动画首帧高度做补偿
# 缩放,把显示高度统一到 DRAGON_BASE_FRAME_H(=attack 帧高)。
var _anim_comp := {}

var logical_w := 720.0
var logical_h := 1280.0
var play_top := 88.0
var play_bottom := 580.0

var sprite: AnimatedSprite2D
var _marker_overlay: Node2D  # 画线攻击标记圆圈,画在精灵之上

# 龙帧基准高度(attack 帧高);朝右那行=第 3 排(0-indexed=2),朝左靠 flip_h
const DRAGON_BASE_FRAME_H := 432.0
const DRAGON_ROW := 2


func _init() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)
	# 标记圆圈 overlay:作为排在精灵之后的子节点,画在顶层
	# (父 _draw 永远在子节点之后,直接画在 _draw 会被龙身盖住)
	_marker_overlay = BossMarkerOverlay.new()
	_marker_overlay.name = "MarkerOverlay"
	add_child(_marker_overlay)


func is_boss_active() -> bool:
	return phase == Phase.ACTIVE


func get_hp_ratio() -> float:
	return clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)


func get_display_name() -> String:
	return str(cfg.get("name", "暗黑龙"))


func setup(battle_node, p_stage_index: int) -> void:
	battle = battle_node
	stage_index = p_stage_index
	cfg = GameConfig.bosses.get("dark_dragon", {})
	logical_w = float(GameConfig.get_tuning("logical_width", 720))
	logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	play_top = 88.0
	play_bottom = logical_h - 120.0
	hitbox_radius = float(cfg.get("hitbox_radius", 18))
	body_scale_mult = float(cfg.get("body_scale_mult", 1.4))
	hitbox_radius *= body_scale_mult
	warning_timer = float(cfg.get("warning_time", 3))
	warning_total = warning_timer
	skill_cooldown = float(cfg.get("skill_interval", 5.0))
	fire_timer = float(cfg.get("fire_interval", 1.3))
	phase = Phase.WARNING
	defeated = false
	defeat_rewarded = false
	move_state = MoveState.BREATH
	appear_active = true
	appear_timer = APPEAR_DURATION
	_appear_shockwave_r = 0.0
	_appear_shockwave_alpha = 1.0
	var scale := GameConfig.stage_stat_scale(stage_index)
	max_hp = int(round(float(cfg.get("hp", 2600)) * scale.hp))
	hp = max_hp
	defense = maxi(1, int(round(float(cfg.get("def", 8)) * scale.def)))
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
	# 起步小 + 透明,让 update_boss 的 appear tween 拉到位
	sprite.scale = Vector2.ONE * _base_sprite_scale * float(_anim_comp.get(SpriteHelper.ANIM_IDLE, 1.0)) * 0.4
	sprite.modulate.a = 0.0
	_spawn_appear_particles()


# Boss 出现:地面砖石粉尘 + 金色火星 + 屏抖
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
			Color("#8a6244"), 80.0, true, true
		)
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
	# 龙素材:三张 4 行 spritesheet(idle 576² / fly 768×576 / attack 2592×1728),
	# 1/4 行=正面/背面(不用),2/3 行=朝左/朝右。只取第 3 行(朝右),朝左靠 flip_h。
	var specs := {
		SpriteHelper.ANIM_IDLE: {
			"path": "res://assets/Characters/Characters2/AncientBlackDragon/AncientBlackDragon_idle.png",
			"frame_w": 144, "frame_h": 144, "row": DRAGON_ROW, "cols": 4, "fps": 6.0, "loop": true,
		},
		SpriteHelper.ANIM_WALK: {
			"path": "res://assets/Characters/Characters2/AncientBlackDragon/AncientBlackDragon_fly.png",
			"frame_w": 192, "frame_h": 144, "row": DRAGON_ROW, "cols": 4, "fps": 10.0, "loop": true,
		},
		SpriteHelper.ANIM_ATTACK: {
			"path": "res://assets/Characters/Characters2/AncientBlackDragon/AncientBlackDragon_attack_NOhitbox.png",
			"frame_w": 432, "frame_h": 432, "row": DRAGON_ROW, "cols": 6, "fps": 12.0, "loop": false,
		},
	}
	sprite.sprite_frames = EffectHelper.build_row_character_frames("char_dark_dragon", specs)
	SpriteHelper.apply_pixel_art(sprite)
	# 实测:三张图里龙"身体"高度都 ≈141px(idle/fly 帧被身体填满,attack 帧是 432
	# 画布但龙身只占 ~1/3,其余留白)。所以不能按"帧画布高度"归一——那会让 attack 的
	# 龙身缩成 1/3。正确做法:三张图用同一个每像素缩放(以 idle 帧 144 为基准),龙身
	# 自然等大;attack 画布会大些但留白透明无妨。_anim_comp 留空(全 1.0)。
	_anim_comp.clear()
	var target_h := float(cfg.get("display_height", 200))
	_base_sprite_scale = SpriteHelper.pixel_scale(target_h / 144.0, 1.0)


func _apply_dragon_scale(anim_name: String = "") -> void:
	if anim_name.is_empty():
		anim_name = sprite.animation
	var comp := float(_anim_comp.get(anim_name, 1.0))
	sprite.scale = Vector2.ONE * _base_sprite_scale * comp


# 龙定点站桩 —— 选屏幕中上方固定位置,若玩家太近则往对侧偏
func _pick_spawn_position() -> Vector2:
	var safe: Vector2 = battle.player.global_position if battle and battle.player else Vector2(logical_w * 0.5, logical_h * 0.45)
	var base := Vector2(logical_w * 0.5, play_top + 120.0)
	if base.distance_to(safe) < 180.0:
		base.x = logical_w * 0.25 if safe.x > logical_w * 0.5 else logical_w * 0.75
	return base


func get_hitbox_radius() -> float:
	return hitbox_radius


func is_combat_targetable() -> bool:
	# 空中(起跳出屏)不可被攻击,同 JUMPER
	return alive and phase == Phase.ACTIVE and not defeated and move_state != MoveState.JUMP_AIR


func get_active_segments() -> Array:
	if phase != Phase.ACTIVE or defeated or move_state == MoveState.JUMP_AIR:
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
	if defeated or phase != Phase.ACTIVE or move_state == MoveState.JUMP_AIR:
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
	facing = 1.0 if _from_pos.x >= global_position.x else -1.0
	sprite.flip_h = facing < 0
	# 受击闪红(无 hurt 动画)
	if hp > 0:
		_hurt_flash_t = HURT_FLASH_DUR
	if hp <= 0:
		_defeat()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false))}


func die() -> void:
	_defeat()


func activate() -> void:
	phase = Phase.ACTIVE
	move_state = MoveState.BREATH
	skill_cooldown = float(cfg.get("skill_interval", 5.0))
	fire_timer = float(cfg.get("fire_interval", 1.3))


func update_boss(delta: float, player: BattlePlayer) -> void:
	_speed_fx_t += delta
	# Boss 出现 tween:scale 0.4→1 + alpha 0→1 + 黄色冲击波(含龙帧补偿)
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
			_apply_dragon_scale(sprite.animation)
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


# 统一 modulate:appear 期间由 appear 逻辑管;否则 闪红 / 起跳隐身 / 死亡渐隐
func _apply_modulate() -> void:
	if appear_active:
		return
	var a := 1.0
	if phase == Phase.DEAD:
		a = clampf(death_fade_timer / death_fade_dur, 0.0, 1.0)
	elif move_state == MoveState.JUMP_AIR:
		a = 0.0
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
	match move_state:
		MoveState.BREATH:
			_update_breath(delta, player)
		MoveState.JUMP_WINDUP:
			_update_jump_windup(delta, player)
		MoveState.JUMP_AIR:
			_update_jump_air(delta, player)
		MoveState.JUMP_LAND:
			_update_jump_land(delta, player)
		MoveState.JUMP_RECOVER:
			_update_jump_recover(delta, player)
	if move_state != MoveState.JUMP_AIR:
		_update_facing(player)
	_try_contact_damage(player)


# 站桩:播 idle(attack 播放中不打断);skill_cooldown 到 → 跳跃;fire_timer 到 → 发火球
func _update_breath(delta: float, player: BattlePlayer) -> void:
	if not (sprite.animation == SpriteHelper.ANIM_ATTACK and sprite.is_playing()):
		_play_anim(SpriteHelper.ANIM_IDLE)
	skill_cooldown -= delta
	if skill_cooldown <= 0.0:
		_begin_jump(player)
		return
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = float(cfg.get("fire_interval", 1.3))
		_fire_single(player)


func _begin_jump(player: BattlePlayer) -> void:
	move_state = MoveState.JUMP_WINDUP
	jump_timer = JUMP_WINDUP
	jump_target = player.global_position


func _update_jump_windup(delta: float, _player: BattlePlayer) -> void:
	jump_timer -= delta
	# 下沉蓄力(照 JUMPER windup)+ 帧补偿
	var p := 1.0 - clampf(jump_timer / JUMP_WINDUP, 0.0, 1.0)
	var comp := float(_anim_comp.get(sprite.animation, 1.0))
	sprite.scale = Vector2.ONE * _base_sprite_scale * comp * lerpf(1.0, 0.82, p)
	if jump_timer <= 0.0:
		# 起跳:锁定玩家当前位置,脚下预警,自身飞出屏幕顶部并隐身
		jump_target = _player.global_position
		move_state = MoveState.JUMP_AIR
		jump_timer = JUMP_AIR
		if battle and battle.ground_effects:
			battle.ground_effects.spawn_smash(
				jump_target,
				int(round(float(cfg.get("smash_damage", 22)))),
				float(cfg.get("smash_radius", 80.0)),
				JUMP_AIR
			)
		global_position = Vector2(jump_target.x, -300.0)
		_apply_dragon_scale(sprite.animation)


func _update_jump_air(delta: float, player: BattlePlayer) -> void:
	jump_timer -= delta
	if jump_timer <= 0.0:
		# 落到玩家原位,显形,屏震,喷霰弹
		global_position = jump_target
		move_state = MoveState.JUMP_LAND
		jump_timer = 0.35
		_play_anim(SpriteHelper.ANIM_ATTACK, true)
		if battle and battle.has_method("shake_camera"):
			battle.shake_camera(8.0, 0.28)
		if battle and battle.particles:
			for i in range(16):
				var ang := float(i) / 16.0 * TAU
				battle.particles.emit_particle(
					global_position.x, global_position.y,
					cos(ang) * 110.0, sin(ang) * 50.0,
					0.4, 5.0, Color("#b04030"), 90.0, true, false
				)
		_fire_shotgun(player)


func _update_jump_land(delta: float, _player: BattlePlayer) -> void:
	jump_timer -= delta
	if jump_timer <= 0.0:
		move_state = MoveState.JUMP_RECOVER
		recover_timer = JUMP_RECOVER


func _update_jump_recover(delta: float, _player: BattlePlayer) -> void:
	recover_timer -= delta
	if recover_timer <= 0.0:
		move_state = MoveState.BREATH
		skill_cooldown = float(cfg.get("skill_interval", 5.0))
		fire_timer = float(cfg.get("fire_interval", 1.3))


# 站桩单发火球
func _fire_single(player: BattlePlayer) -> void:
	if battle == null:
		return
	_play_anim(SpriteHelper.ANIM_ATTACK, true)
	battle.spawn_arrow(
		global_position,
		player.global_position,
		int(cfg.get("fire_damage", 14)),
		float(cfg.get("fire_speed", 130)),
		"auto_bullet",
		Color("#ff8a3a")
	)


# 落地喷大量不规则火球霰弹:朝玩家方向 ± 随机角度,速度随机
func _fire_shotgun(player: BattlePlayer) -> void:
	if battle == null:
		return
	var from := global_position
	var base_dir := player.global_position - from
	if base_dir.length_squared() < 1.0:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()
	var base_angle := base_dir.angle()
	var count := int(cfg.get("breath_count", 16))
	var spread_rad := deg_to_rad(float(cfg.get("breath_spread_deg", 80)))
	var dmg := int(cfg.get("breath_damage", 12))
	var smin := float(cfg.get("breath_speed_min", 90))
	var smax := float(cfg.get("breath_speed_max", 170))
	for _i in range(count):
		var ang := base_angle + randf_range(-spread_rad, spread_rad)
		var dir := Vector2(cos(ang), sin(ang))
		var speed := randf_range(smin, smax)
		var to := from + dir * 600.0
		battle.spawn_arrow(from, to, dmg, speed, "auto_bullet", Color("#ff8a3a"))


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
			dealt, false, false, Color("#e05840")
		)


func _play_anim(anim_name: String, force: bool = false) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		if anim_name != SpriteHelper.ANIM_IDLE:
			_play_anim(SpriteHelper.ANIM_IDLE, force)
		return
	if not force and sprite.animation == anim_name and sprite.is_playing():
		_apply_dragon_scale(anim_name)
		return
	if force and sprite.animation == anim_name:
		sprite.stop()
		sprite.frame = 0
	sprite.play(anim_name)
	_apply_dragon_scale(anim_name)


func _defeat() -> void:
	if defeated:
		return
	hp = 0
	defeated = true
	alive = false
	dying = true
	phase = Phase.DEAD
	death_fade_timer = death_fade_dur
	# 死亡无动画,只渐隐;停 sprite
	sprite.stop()
	if battle and battle.blood_stains:
		var hit_angle := 0.0
		if battle.player:
			hit_angle = (global_position - battle.player.global_position).angle()
		battle.blood_stains.spawn(global_position.x, global_position.y, 1.6, hit_angle)
	if battle and battle.particles:
		battle.particles.death_effect(global_position, Color("#7a3030"))
	if not defeat_rewarded and battle and battle.experience:
		defeat_rewarded = true
		battle.experience.add_exp(int(cfg.get("defeat_exp", 160)))
	if battle and battle.hud:
		battle.hud.show_message("%s 击破!" % get_display_name(), 2.0)


func get_warning_text() -> String:
	return str(maxi(1, int(ceil(warning_timer))))


# ===================== 绘制 =====================
# 照搬 LancerBoss 的 warning overlay / appear shockwave(已验证可用),加跳跃蓄力红环。

func _draw() -> void:
	if phase == Phase.WARNING:
		_draw_warning_overlay()
	if phase == Phase.ACTIVE and move_state == MoveState.JUMP_WINDUP:
		_draw_jump_windup()
	# 画线攻击标记圆圈由 _marker_overlay 子节点画在精灵之上(见 BossMarkerOverlay)
	if appear_active or _appear_shockwave_alpha > 0.01:
		_draw_appear_shockwave()


func _draw_jump_windup() -> void:
	var progress := 1.0 - clampf(jump_timer / maxf(0.001, JUMP_WINDUP), 0.0, 1.0)
	var pulse := 0.55 + sin(_speed_fx_t * 12.0) * 0.25
	draw_arc(Vector2.ZERO, hitbox_radius + 12.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 28, Color(1.0, 0.20, 0.18, pulse), 3.0)
	draw_circle(Vector2.ZERO, hitbox_radius + 12.0, Color(1.0, 0.10, 0.08, 0.10 + 0.10 * pulse))


func _draw_warning_overlay() -> void:
	var origin: Vector2 = -global_position
	var t: float = warning_pulse
	var urgency: float = clampf(1.0 - warning_timer / maxf(0.001, warning_total), 0.0, 1.0)
	var fast_pulse: float = 0.5 + 0.5 * sin(t * (6.0 + urgency * 8.0))
	var vignette_a: float = 0.18 + 0.10 * urgency + 0.06 * fast_pulse
	var vignette_thick: float = 32.0 + 12.0 * urgency
	draw_rect(Rect2(origin, Vector2(logical_w, vignette_thick)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin + Vector2(0, logical_h - vignette_thick), Vector2(logical_w, vignette_thick)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin, Vector2(vignette_thick, logical_h)), Color(0.05, 0.0, 0.02, vignette_a))
	draw_rect(Rect2(origin + Vector2(logical_w - vignette_thick, 0), Vector2(vignette_thick, logical_h)), Color(0.05, 0.0, 0.02, vignette_a))
	_draw_warning_chevron_band(origin + Vector2(0, vignette_thick - 4.0), logical_w, t, 1.0, urgency)
	_draw_warning_chevron_band(origin + Vector2(0, logical_h - vignette_thick - 14.0), logical_w, t, -1.0, urgency)
	var pulse_r: float = 42.0 + sin(t * 7.0) * 6.0
	draw_arc(Vector2.ZERO, pulse_r, 0.0, TAU, 48, Color(1.0, 0.18, 0.18, 0.85), 4.0)
	draw_arc(Vector2.ZERO, pulse_r + 14.0, 0.0, TAU, 48, Color(1.0, 0.78, 0.20, 0.6), 2.5)
	draw_arc(Vector2.ZERO, pulse_r + 24.0 + sin(t * 4.0) * 4.0, 0.0, TAU, 48, Color(1.0, 0.95, 0.7, 0.32 + 0.18 * fast_pulse), 1.5)
	draw_circle(Vector2.ZERO, pulse_r * 0.85, Color(1.0, 0.18, 0.10, 0.08 + 0.10 * fast_pulse))
	var inset: float = lerpf(2.0, 18.0, urgency)
	var inner_origin: Vector2 = origin + Vector2(inset, inset)
	var inner_size: Vector2 = Vector2(logical_w - inset * 2.0, logical_h - inset * 2.0)
	var border_w_inner: float = 4.0 + 3.0 * fast_pulse
	draw_rect(Rect2(inner_origin, inner_size), Color(1.0, 0.18, 0.18, 0.72), false, border_w_inner)
	draw_rect(Rect2(inner_origin + Vector2(border_w_inner, border_w_inner) * 0.5, inner_size - Vector2(border_w_inner, border_w_inner)), Color(1.0, 0.82, 0.25, 0.55), false, 1.5)


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
		var shrink: float = 5.0
		var pts2 := PackedVector2Array([
			Vector2(tip_x - shrink * dir, y + arrow_h * 0.5),
			Vector2(base_x + shrink * dir, top_y + 3.0),
			Vector2(base_x + shrink * dir, bot_y - 3.0),
		])
		draw_polygon(pts2, inner_colors)


func _draw_appear_shockwave() -> void:
	if not appear_active and _appear_shockwave_alpha <= 0.01:
		return
	var ring_w: float = 6.0 * _appear_shockwave_alpha
	var col_outer := Color(1.0, 0.85, 0.30, 0.6 * _appear_shockwave_alpha)
	var col_inner := Color(1.0, 1.0, 0.7, 0.85 * _appear_shockwave_alpha)
	draw_arc(Vector2.ZERO, _appear_shockwave_r, 0.0, TAU, 48, col_outer, ring_w)
	draw_arc(Vector2.ZERO, _appear_shockwave_r * 0.7, 0.0, TAU, 48, col_inner, ring_w * 0.6)
	draw_circle(Vector2.ZERO, maxf(0.0, 28.0 - _appear_shockwave_r * 0.1), Color(1.0, 0.95, 0.65, 0.45 * _appear_shockwave_alpha))
