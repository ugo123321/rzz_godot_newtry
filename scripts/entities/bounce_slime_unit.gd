extends Node2D
class_name BounceSlimeUnit

# 弹射史莱姆 BOSS 的一个分体:像打砖块子弹一样在场景内反弹飞行,
# 撞玩家造成接触伤害。5 个分体共享一条 boss 血条(血量之和 —— 见 BounceSlimeBoss)。
#
# 精灵图集(Slime):idle/move 192²(4×4/48) + attack 720×576(5×4/144)。
# 取第 3 排(朝右,0-indexed=2),朝左靠 flip_h —— 同龙/骑士。
# 三张图史莱姆身体等高(48px),用同一每像素缩放(以 idle 48 为基准);
# attack 画布(144)大但身体只占一部分,留白透明无妨 —— _anim_comp 留空(全 1.0)。

const HURT_FLASH_DUR := 0.18
const SLIME_BASE_FRAME_H := 48.0
const SLIME_ROW := 2

var boss_ref
var unit_index := 0
var alive := true
var dying := false
var hp := 0
var max_hp := 0
var velocity := Vector2.ZERO
var _dir := Vector2.RIGHT
var facing := 1.0
var contact_timer := 0.0
var _hurt_flash_t := 0.0
var death_fade_timer := 0.0
var death_fade_dur := 0.35
var path_target_hit_count := 0
var hitbox_radius := 24.0

# 从 boss cfg 拷出来的字段(避免每帧跨对象读)
var contact_damage := 12
var contact_interval := 0.8
var bounce_speed := 280.0
var logical_w := 720.0
var logical_h := 1280.0
var play_top := 88.0
var play_bottom := 580.0

var _base_sprite_scale := 1.0
var _anim_comp := {}
var _speed_fx_t := 0.0

var sprite: AnimatedSprite2D
var _marker_overlay: Node2D


func _init() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)
	# 画线攻击标记圆圈:排在精灵之后的子节点,画在顶层(同龙/骑士 BossMarkerOverlay)
	_marker_overlay = BossMarkerOverlay.new()
	_marker_overlay.name = "MarkerOverlay"
	add_child(_marker_overlay)


func setup(boss, index: int, p_max_hp: int, p_dir: Vector2) -> void:
	boss_ref = boss
	unit_index = index
	if boss == null:
		return
	hitbox_radius = boss.hitbox_radius
	contact_damage = int(boss.cfg.get("contact_damage", 12))
	contact_interval = float(boss.cfg.get("contact_interval", 0.8))
	bounce_speed = float(boss.cfg.get("bounce_speed", 280))
	logical_w = boss.logical_w
	logical_h = boss.logical_h
	play_top = boss.play_top
	play_bottom = boss.play_bottom
	max_hp = p_max_hp
	hp = max_hp
	_dir = p_dir
	velocity = Vector2.ZERO  # WARNING 阶段不动,activate 时给速度
	_apply_sprite()
	sprite.play(SpriteHelper.ANIM_IDLE)
	sprite.flip_h = facing < 0
	# 起步小+透明,boss 的 appear tween 拉到位(避免第一帧露出全尺寸)
	sprite.scale = Vector2.ONE * _base_sprite_scale * 0.4
	sprite.modulate.a = 0.0
	# 初始位置:boss 中心 + 朝向方向的小偏移(出场聚集成一小簇,activate 后弹射飞出)
	global_position = boss.global_position + p_dir * 26.0
	if _marker_overlay:
		_marker_overlay.queue_redraw()


# activate 后给速度,正式弹射飞出
func burst_out() -> void:
	velocity = _dir * bounce_speed
	_play_anim(SpriteHelper.ANIM_WALK)


func get_hitbox_radius() -> float:
	return hitbox_radius


func is_combat_targetable() -> bool:
	return alive and boss_ref != null and boss_ref.phase == BounceSlimeBoss.Phase.ACTIVE and not boss_ref.defeated


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	if boss_ref:
		return boss_ref.apply_damage(raw_damage, self, from_pos)
	return {"damage": 0, "is_crit": false}


func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if boss_ref:
		return boss_ref.apply_damage_info(info, self, from_pos)
	return {"damage": 0, "is_crit": false}


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func die() -> void:
	pass


func update_ai(_delta: float, _player: BattlePlayer, _battle: Node) -> void:
	pass


func flash_hurt() -> void:
	_hurt_flash_t = HURT_FLASH_DUR


func update_unit(delta: float, player: BattlePlayer) -> void:
	_speed_fx_t += delta
	if not alive:
		# 死亡渐隐(原地冻结,不再反弹)
		death_fade_timer = maxf(0.0, death_fade_timer - delta)
		sprite.modulate.a = clampf(death_fade_timer / maxf(0.001, death_fade_dur), 0.0, 1.0)
		if _marker_overlay:
			_marker_overlay.queue_redraw()
		return
	if boss_ref == null or not boss_ref.is_boss_active():
		return
	# 移动 + 边缘反弹(打砖块子弹逻辑)
	global_position += velocity * delta
	_try_bounce()
	# 接触伤害
	contact_timer = maxf(0.0, contact_timer - delta)
	if _hurt_flash_t > 0.0:
		_hurt_flash_t = maxf(0.0, _hurt_flash_t - delta)
	_try_contact_damage(player)
	# 朝向
	if absf(velocity.x) > 2.0:
		facing = 1.0 if velocity.x >= 0 else -1.0
		sprite.flip_h = facing < 0
	# 动画:移动中播 walk,attack 播放中不打断
	if not (sprite.animation == SpriteHelper.ANIM_ATTACK and sprite.is_playing()):
		_play_anim(SpriteHelper.ANIM_WALK)
	_apply_slime_scale(sprite.animation)
	_apply_modulate()
	if _marker_overlay:
		_marker_overlay.queue_redraw()


# 场景边缘物理反弹:碰边把对应轴速度取绝对值反向,位置钳回场内
func _try_bounce() -> void:
	var r := hitbox_radius
	var pos := global_position
	var bounced := false
	if pos.x <= r:
		global_position.x = r
		velocity.x = absf(velocity.x)
		bounced = true
	elif pos.x >= logical_w - r:
		global_position.x = logical_w - r
		velocity.x = -absf(velocity.x)
		bounced = true
	if pos.y <= play_top + r:
		global_position.y = play_top + r
		velocity.y = absf(velocity.y)
		bounced = true
	elif pos.y >= play_bottom - r:
		global_position.y = play_bottom - r
		velocity.y = -absf(velocity.y)
		bounced = true
	if bounced and boss_ref and boss_ref.battle and boss_ref.battle.particles:
		boss_ref.battle.particles.hit_spark(global_position, false)


func _try_contact_damage(player: BattlePlayer) -> void:
	if contact_timer > 0.0 or player == null or player.hp <= 0:
		return
	if boss_ref and boss_ref.battle and boss_ref.battle.combat and not boss_ref.battle.combat.should_monsters_attack(player):
		return
	var touch_r := hitbox_radius + player.get_effective_radius() * 0.55
	if global_position.distance_to(player.global_position) > touch_r:
		return
	contact_timer = contact_interval
	player.take_damage(contact_damage)
	# 播攻击动画(咬一口)——同时验证 attack 图集缩放与其他图集一致
	_play_anim(SpriteHelper.ANIM_ATTACK, true)


func _apply_sprite() -> void:
	# 史莱姆素材:三张 4 行 spritesheet(idle 192² 4×4/48 / move 192² 4×4/48 / attack 720×576 5×4/144)。
	# 只取第 3 行(朝右,0-indexed=2),朝左靠 flip_h —— 同龙/骑士。
	var specs := {
		SpriteHelper.ANIM_IDLE: {
			"path": "res://assets/Characters/Characters2/Slime/Slime_idle.png",
			"frame_w": 48, "frame_h": 48, "row": SLIME_ROW, "cols": 4, "fps": 6.0, "loop": true,
		},
		SpriteHelper.ANIM_WALK: {
			"path": "res://assets/Characters/Characters2/Slime/Slime_move.png",
			"frame_w": 48, "frame_h": 48, "row": SLIME_ROW, "cols": 4, "fps": 10.0, "loop": true,
		},
		SpriteHelper.ANIM_ATTACK: {
			"path": "res://assets/Characters/Characters2/Slime/Slime_attack_NOhitbox.png",
			"frame_w": 144, "frame_h": 144, "row": SLIME_ROW, "cols": 5, "fps": 12.0, "loop": false,
		},
	}
	sprite.sprite_frames = EffectHelper.build_row_character_frames("char_bounce_slime", specs)
	SpriteHelper.apply_pixel_art(sprite)
	# 同龙/骑士:_anim_comp 留空(三张图身体等高 48),只按 idle 帧高 48 做每像素缩放。
	# attack 画布 144 但史莱姆身体只占一部分,留白透明无妨,身体自然等大。
	_anim_comp.clear()
	var target_h := float(boss_ref.cfg.get("display_height", 100))
	_base_sprite_scale = SpriteHelper.pixel_scale(target_h / SLIME_BASE_FRAME_H, 1.0)
	sprite.scale = Vector2.ONE * _base_sprite_scale


func _apply_slime_scale(anim_name: String = "") -> void:
	if anim_name.is_empty():
		anim_name = sprite.animation
	var comp := float(_anim_comp.get(anim_name, 1.0))
	sprite.scale = Vector2.ONE * _base_sprite_scale * comp


func _apply_modulate() -> void:
	var a := 1.0
	if not alive:
		a = clampf(death_fade_timer / maxf(0.001, death_fade_dur), 0.0, 1.0)
	if _hurt_flash_t > 0.0 and a > 0.0:
		var kk := _hurt_flash_t / HURT_FLASH_DUR
		modulate = Color(1.0, 1.0 - 0.6 * kk, 1.0 - 0.6 * kk, a)
	else:
		modulate = Color(1.0, 1.0, 1.0, a)


func _play_anim(anim_name: String, force: bool = false) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		if anim_name != SpriteHelper.ANIM_IDLE:
			_play_anim(SpriteHelper.ANIM_IDLE, force)
		return
	if not force and sprite.animation == anim_name and sprite.is_playing():
		_apply_slime_scale(anim_name)
		return
	if force and sprite.animation == anim_name:
		sprite.stop()
		sprite.frame = 0
	sprite.play(anim_name)
	_apply_slime_scale(anim_name)


func _draw() -> void:
	# 分体绘制由 sprite 子节点负责;_draw 留空(标记圆圈由 _marker_overlay 画)
	pass
