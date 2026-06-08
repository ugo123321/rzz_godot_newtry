extends Node2D
class_name BattleMonster

const HP_BAR_Y_OFFSET := 9.0
const MELEE_REACH_PAD := 6.0
const MELEE_STOP_PAD := 2.0

var kind_id := "NORMAL"
var display_name := ""
var alive := true
var hp := 1
var max_hp := 1
var defense := 0
var attack := 10
var attack_interval := 1.0
var attack_timer := 0.0
var move_speed := 19.0
var hitbox_radius := 13.0
var can_move := true
var ranged := false
var attack_range := 0.0
var arrow_speed := 85.0
var ki_drain_on_hit := 0
var attack_pattern := ""
var projectile_effect := ""
var spread_count := 5
var spread_angle_deg := 50.0
var bounce_count := 1
var sprite_tint := Color.WHITE
var has_shield := false
var facing := 1.0
var color := Color.WHITE
var split_tier := 0
var max_split_tier := 0
var split_count := 0
var spawned_children := false
var stage_index_cached := 0
var frozen_timer := 0.0
var vulnerable_mark := false
var path_target_hit_count := 0
var dying := false
var death_delay := 0.0
var death_timer := 0.0
var death_fade_dur := 0.28
var death_flash := 0.0
var _death_base_scale := Vector2.ONE
var hurt_reaction_timer := 0.0
var burn_timer := 0.0
var burn_tick_timer := 0.0
var burn_dps := 0

var _sprite_folder := "Skeleton"
var _sprite_prefix := "Skeleton"
var spawn_lock_timer := 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(monster_kind: String, stage_index: int, spawn_pos: Vector2) -> void:
	kind_id = monster_kind
	stage_index_cached = stage_index
	var stats := GameConfig.scaled_monster_stats(monster_kind, stage_index)
	display_name = str(stats.get("name_cn", monster_kind))
	max_hp = int(stats.get("hp", 1))
	hp = max_hp
	defense = int(stats.get("def", 0))
	attack = int(stats.get("attack", 1))
	attack_interval = float(stats.get("attack_interval", 1.0))
	hitbox_radius = GameConfig.scale_world(float(stats.get("size", 13)))
	move_speed = float(stats.get("speed", 19))
	can_move = int(stats.get("can_move", 1)) != 0
	ranged = int(stats.get("ranged", 0)) != 0
	attack_range = float(stats.get("attack_range", 0))
	arrow_speed = float(stats.get("arrow_speed", 85.0))
	ki_drain_on_hit = int(stats.get("ki_drain_on_hit", 0))
	attack_pattern = str(stats.get("attack_pattern", ""))
	projectile_effect = str(stats.get("projectile_effect", ""))
	spread_count = int(stats.get("spread_count", 5))
	spread_angle_deg = float(stats.get("spread_angle_deg", 50.0))
	bounce_count = int(stats.get("bounce_count", 1))
	var tint_hex := str(stats.get("sprite_tint_hex", ""))
	if not tint_hex.is_empty():
		sprite_tint = Color(tint_hex)
	else:
		sprite_tint = Color.WHITE
	has_shield = kind_id == "SHIELD"
	max_split_tier = int(stats.get("max_split_tier", 0))
	split_count = int(stats.get("split_count", 0))
	color = Color(str(stats.get("color_hex", "#ffffff")))
	global_position = spawn_pos
	_sprite_folder = str(stats.get("character_folder", "Skeleton"))
	_sprite_prefix = str(stats.get("sprite_prefix", "Skeleton"))
	_apply_sprite()


func begin_spawn(duration: float = -1.0, target_scale: Vector2 = Vector2.ONE) -> void:
	if duration < 0.0:
		duration = float(GameConfig.get_tuning("monster_spawn_anim", 0.6))
	spawn_lock_timer = duration
	attack_timer = attack_interval
	modulate.a = 0.0
	scale = target_scale * 0.35
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, duration)
	tween.tween_property(self, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_spawn_anim_finished, CONNECT_ONE_SHOT)


func _on_spawn_anim_finished() -> void:
	spawn_lock_timer = 0.0
	attack_timer = attack_interval


func _apply_sprite() -> void:
	var anim_sprite := sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite == null:
		push_warning("BattleMonster: AnimatedSprite2D not ready")
		return
	anim_sprite.sprite_frames = SpriteHelper.build_character_frames(_sprite_folder, _sprite_prefix)
	SpriteHelper.apply_pixel_art(anim_sprite)
	var scale_val := float(GameConfig.get_tuning("monster_sprite_scale", 1.0))
	anim_sprite.scale = Vector2.ONE * SpriteHelper.pixel_scale(scale_val)
	if sprite_tint != Color.WHITE:
		anim_sprite.modulate = sprite_tint
	if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	if not anim_sprite.animation_finished.is_connected(_on_animation_finished):
		anim_sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	if dying or not alive:
		return
	var anim_sprite := sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if anim_sprite.animation in [SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_ATTACK]:
		if anim_sprite.animation == SpriteHelper.ANIM_HURT:
			hurt_reaction_timer = 0.0
		if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)


func get_hitbox_radius() -> float:
	return hitbox_radius


func get_feet_global_position() -> Vector2:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return global_position + Vector2(0.0, hitbox_radius)
	# 使用未缩放帧坐标；to_global 会再应用 sprite scale，避免重复乘缩放导致锚点下沉。
	var feet_local_y := SpriteHelper.FRAME_H * 0.5 * 0.88
	return anim_sprite.to_global(Vector2(0.0, feet_local_y))


func get_head_top_global_position() -> Vector2:
	return SpriteHelper.get_character_head_top_global(
		_get_sprite(),
		global_position + Vector2(0.0, -hitbox_radius * 1.5)
	)


func _melee_attack_range(player: BattlePlayer) -> float:
	if player == null:
		return GameConfig.scale_world(30.0)
	return player.get_effective_radius() + hitbox_radius + GameConfig.scale_world(MELEE_REACH_PAD)


func _melee_stop_distance(player: BattlePlayer) -> float:
	if player == null:
		return GameConfig.scale_world(26.0)
	return player.get_effective_radius() + hitbox_radius + GameConfig.scale_world(MELEE_STOP_PAD)


func is_combat_targetable() -> bool:
	return alive and not dying and spawn_lock_timer <= 0.0


func is_spawn_locked() -> bool:
	return spawn_lock_timer > 0.0


func update_death(delta: float) -> void:
	if not dying:
		return
	death_flash = maxf(0.0, death_flash - delta * 6.0)
	if death_delay > 0.0:
		death_delay -= delta
		_apply_death_modulate(1.0)
		return
	death_timer -= delta
	var alpha := clampf(death_timer / maxf(0.001, death_fade_dur), 0.0, 1.0)
	_apply_death_modulate(alpha)
	var shrink := lerpf(1.0, 0.72, 1.0 - alpha)
	scale = _death_base_scale * shrink
	if death_timer <= 0.0:
		_finish_death()


func _apply_death_modulate(alpha: float) -> void:
	var flash := 1.0 + death_flash * 0.25
	modulate = Color(flash, flash, flash, alpha)


func is_frozen() -> bool:
	return frozen_timer > 0.0


func freeze(duration: float) -> void:
	frozen_timer = maxf(frozen_timer, duration)


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	if not alive or dying:
		return {"damage": 0, "is_crit": false}
	if has_shield:
		has_shield = false
		return {"damage": 0, "is_crit": false, "blocked_by_shield": true}
	var mult := 2.0 if vulnerable_mark else 1.0
	vulnerable_mark = false
	var actual := maxi(1, int(round((float(raw_damage) - defense) * mult)))
	hp -= actual
	var started_dying := false
	if hp <= 0:
		hp = 0
		var battle := get_tree().get_first_node_in_group("battle")
		var delay := 0.0
		if battle and battle.combat:
			delay = battle.combat.schedule_death_fade()
		started_dying = begin_dying(delay)
	else:
		facing = 1.0 if from_pos.x >= global_position.x else -1.0
		var anim_sprite := _get_sprite()
		if anim_sprite:
			anim_sprite.flip_h = facing < 0
		_play_hurt_anim()
	queue_redraw()
	return {"damage": actual, "is_crit": false, "started_dying": started_dying}


func apply_burn_dot(duration: float, dps: int) -> void:
	if not alive or dying:
		return
	burn_timer = maxf(burn_timer, duration)
	burn_tick_timer = 0.0
	burn_dps = maxi(burn_dps, dps)


func can_split() -> bool:
	return kind_id == "SPLITTER" and split_tier < max_split_tier and not spawned_children


func begin_dying(stagger_delay: float) -> bool:
	if dying or not alive:
		return false
	dying = true
	death_fade_dur = float(GameConfig.get_tuning("monster_death_fade", 0.28))
	var death_anim_dur := _death_anim_duration()
	death_delay = maxf(0.0, stagger_delay) + death_anim_dur
	death_timer = death_fade_dur
	death_flash = 0.35
	_death_base_scale = scale
	modulate = Color.WHITE
	var pop_tween := create_tween()
	pop_tween.tween_property(self, "scale", _death_base_scale * 1.08, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "scale", _death_base_scale, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	queue_redraw()
	_play_anim(SpriteHelper.ANIM_DEATH, true)
	if can_split() and not spawned_children:
		var battle := get_tree().get_first_node_in_group("battle")
		if battle and battle.spawner:
			battle.spawner.spawn_split_children(self)
		spawned_children = true
	return true


func die() -> void:
	begin_dying(0.0)


func _finish_death() -> void:
	alive = false
	dying = false
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.spawner:
		battle.spawner.unregister_monster(self)
	queue_free()


func update_ai(delta: float, player: BattlePlayer, battle: Node) -> void:
	if not alive or dying or player == null:
		return
	_update_burn_dot(delta)
	if spawn_lock_timer > 0.0:
		spawn_lock_timer = maxf(0.0, spawn_lock_timer - delta)
		return
	if frozen_timer > 0.0:
		frozen_timer -= delta
		return
	if hurt_reaction_timer > 0.0:
		hurt_reaction_timer = maxf(0.0, hurt_reaction_timer - delta)
	var to_player := player.global_position - global_position
	facing = 1.0 if to_player.x >= 0 else -1.0
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.flip_h = facing < 0
	var preserve_anim := hurt_reaction_timer > 0.0 or SpriteHelper.is_playing_priority_anim(anim_sprite)
	if can_move:
		var dist := to_player.length()
		var stop_dist := _melee_stop_distance(player)
		if ranged:
			stop_dist = attack_range * 0.85 if attack_range > 0.0 else GameConfig.scale_world(140.0)
		if dist > stop_dist:
			global_position += to_player.normalized() * move_speed * delta
			if not preserve_anim:
				_play_anim(SpriteHelper.ANIM_WALK)
		elif not preserve_anim:
			_play_anim(SpriteHelper.ANIM_IDLE)
	var can_attack := true
	if battle and battle.combat:
		can_attack = battle.combat.should_monsters_attack(player)
	if can_attack and hurt_reaction_timer <= 0.0:
		attack_timer -= delta
		if attack_timer > 0.0:
			return
		if ranged and attack_range > 0.0 and to_player.length() > attack_range:
			return
		if not ranged and to_player.length() > _melee_attack_range(player):
			return
		attack_timer = attack_interval
		_perform_attack(player, battle)


func _perform_attack(player: BattlePlayer, battle: Node) -> void:
	if kind_id == "FIRE_MAGE":
		if battle and battle.ground_effects:
			battle.ground_effects.spawn_fire_pillar(player.global_position, attack)
		if battle and battle.particles:
			var hand := global_position + Vector2(cos(facing), sin(facing)) * (hitbox_radius + 4.0)
			battle.particles.emit_particle(hand.x, hand.y, 0, 0, 0.35, 5.0, Color("#c03030"), 0, false, false)
			battle.particles.emit_particle(hand.x, hand.y - 4.0, 0, -20, 0.35, 4.0, Color("#ff5040"), 0, false, false)
		return
	if ranged:
		_play_anim(SpriteHelper.ANIM_ATTACK)
		match attack_pattern:
			"spread":
				battle.spawn_enemy_spread(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					spread_count,
					spread_angle_deg,
					projectile_effect,
					sprite_tint
				)
			"cross":
				battle.spawn_enemy_cross(
					global_position,
					attack,
					arrow_speed,
					projectile_effect,
					sprite_tint
				)
			"bounce":
				battle.spawn_enemy_bounce(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					bounce_count,
					projectile_effect,
					sprite_tint
				)
			_:
				battle.spawn_arrow(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					projectile_effect,
					sprite_tint
				)
	else:
		_play_anim(SpriteHelper.ANIM_ATTACK)
		player.take_damage(attack)
		if ki_drain_on_hit > 0:
			player.ki = maxf(0.0, player.ki - float(ki_drain_on_hit))


func _get_sprite() -> AnimatedSprite2D:
	return sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _anim_duration(anim_name: String, fallback: float) -> float:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return fallback
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return fallback
	var frame_count := anim_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return fallback
	var speed := anim_sprite.sprite_frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return fallback
	var total := 0.0
	for i in range(frame_count):
		total += anim_sprite.sprite_frames.get_frame_duration(anim_name, i)
	return maxf(0.12, total / speed)


func _hurt_anim_duration() -> float:
	return _anim_duration(SpriteHelper.ANIM_HURT, 0.35)


func _death_anim_duration() -> float:
	return _anim_duration(SpriteHelper.ANIM_DEATH, 0.5)


func _play_hurt_anim() -> void:
	hurt_reaction_timer = maxf(hurt_reaction_timer, _hurt_anim_duration())
	_play_anim(SpriteHelper.ANIM_HURT, true)


func _play_anim(anim_name: String, force: bool = false) -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null or not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if anim_sprite.sprite_frames.get_frame_count(anim_name) <= 0:
		return
	if dying and anim_name != SpriteHelper.ANIM_DEATH:
		return
	if hurt_reaction_timer > 0.0 and anim_name in [SpriteHelper.ANIM_WALK, SpriteHelper.ANIM_IDLE, SpriteHelper.ANIM_ATTACK]:
		return
	if anim_sprite.is_playing() and anim_sprite.animation in [SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_DEATH, SpriteHelper.ANIM_ATTACK]:
		if anim_name in [SpriteHelper.ANIM_WALK, SpriteHelper.ANIM_IDLE]:
			return
	if anim_name == SpriteHelper.ANIM_HURT:
		force = true
	if not force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	if force and anim_sprite.animation == anim_name:
		anim_sprite.stop()
		anim_sprite.frame = 0
	if anim_name == SpriteHelper.ANIM_DEATH:
		force = true
	anim_sprite.play(anim_name)


func _should_show_hp_bar() -> bool:
	return alive and not dying and hp < max_hp


func _draw_hp_bar() -> void:
	var head_pos := to_local(get_head_top_global_position())
	PixelUiHelper.draw_compact_hp_bar(
		self,
		head_pos + Vector2(0.0, GameConfig.scale_world(HP_BAR_Y_OFFSET)),
		hp,
		max_hp,
		GameConfig.scale_world(28.0),
		GameConfig.scale_world(5.0),
		{
			"border_color": "#2a1317",
			"panel_fill": "#201016",
			"empty_a": "#34161c",
			"empty_b": "#281218",
			"fill_color": "#cc4040",
			"shine_color": "#ff9494",
			"segment_count": 8,
			"segment_gap": 1
		}
	)


func _draw() -> void:
	if _should_show_hp_bar():
		_draw_hp_bar()
	if burn_timer > 0.0:
		var t := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.018)
		draw_arc(Vector2.ZERO, hitbox_radius + GameConfig.scale_world(7.0), 0.0, TAU, 30, Color(1.0, 0.35, 0.2, 0.55 + 0.25 * t), GameConfig.scale_world(2.0))
	if not alive or dying or path_target_hit_count <= 0:
		return
	var ring := CombatDirector.path_preview_ring_color(path_target_hit_count)
	var fill := ring
	fill.a = 0.12 + mini(path_target_hit_count, 4) * 0.04
	var r := hitbox_radius + GameConfig.scale_world(5.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ring, GameConfig.scale_world(3.0))
	draw_circle(Vector2.ZERO, r * 0.55, fill)


func _update_burn_dot(delta: float) -> void:
	if burn_timer <= 0.0:
		burn_timer = 0.0
		burn_tick_timer = 0.0
		burn_dps = 0
		_restore_sprite_tint()
		return
	_apply_burn_tint()
	burn_timer = maxf(0.0, burn_timer - delta)
	burn_tick_timer += delta
	var battle := get_tree().get_first_node_in_group("battle")
	while burn_tick_timer >= 0.5 and burn_timer > 0.0 and burn_dps > 0 and alive and not dying:
		burn_tick_timer -= 0.5
		var tick_damage := int(max(1, round(float(burn_dps) * 0.5)))
		var result := take_damage(tick_damage, global_position + Vector2(0.0, -8.0))
		if battle and battle.combat and int(result.get("damage", 0)) > 0:
			battle.combat.spawn_damage_number(global_position + Vector2(0.0, -8.0), int(result.get("damage", 0)), false, false, Color("#ff6a3a"))
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(self)


func _apply_burn_tint() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return
	if sprite_tint != Color.WHITE:
		anim_sprite.modulate = sprite_tint.lerp(Color(1.0, 0.45, 0.38, 1.0), 0.42)
	else:
		anim_sprite.modulate = Color(1.0, 0.42, 0.36, 1.0)


func _restore_sprite_tint() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return
	anim_sprite.modulate = sprite_tint if sprite_tint != Color.WHITE else Color.WHITE
