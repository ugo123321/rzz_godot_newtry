extends Node2D
class_name BattlePlayer

signal auto_bullet_released

enum State { IDLE, BULLET_TIME, ATTACKING }

const AUTO_BULLET_RELEASE_RATIO := 0.42
const PATH_LINE_WIDTH := 6.0
const PATH_LINE_COLOR := Color(1.0, 0.85, 0.2, 0.9)
const PATH_LINE_COLOR_ATTACK := Color(1.0, 0.85, 0.2, 0.35)
const PATH_HIT_PAD_RATIO := 0.68
const DRAW_START_FX_SCALE := 1.3
const TRIGGER_RING_VISUAL_SCALE := 0.6
const HP_BAR_Y_OFFSET := 8

var home_position: Vector2
var state := State.IDLE

var base_attack := 95.0
var attack_power_scale := 1.0
var crit_rate := 0.08
var crit_damage := 1.6
var size_scale := 1.0

var max_hp := 100
var hp := 100
var invincible_timer := 0.0
var damage_flash_timer := 0.0

var base_ki := 234.0
var ki_max := 234.0
var ki := 234.0
var ki_regen_speed := 135.0
var basic_attack_speed := 2.0
var next_turn_ki_bonus := 0.0

var combo_count := 0.0
var combo_hit_count := 0
var combo_display_peak := 0
var combo_display_weight := 0.0
var combo_display_timer := 0.0
var combo_display_fading := false
var combo_damage_bonus := 0.01

var attack_path: Array[Vector2] = []
var path_index := 0
var path_progress := 0.0
var _path_hit_inside: Dictionary = {}
var _last_attack_pos := Vector2.ZERO
var _attack_hits_primmed := false
var hit_projectiles_this_attack: Dictionary = {}

var upgrade_stacks: Dictionary = {}
var turn_buff_attack_mult := 1.0
var turn_buff_combo_mult := 1.0
var ice_ready := false
var draw_session_snapshot = null
var collected_orb_buffs: Array = []
var ki_at_draw_start := 0.0

var bullet_count := 1
var water_tornado_charge := 0
var whirl_charge := 0
var holy_shield_timer := 0.0
var holy_shield_charges := 0
var charge_strike_time := 0.0
var attack_speed_mult := 1.0
var ki_regen_mult := 1.0
var slash_damage_mult := 1.0
var bonus_attack_mult := 1.0
var bonus_attack_speed_mult := 1.0
var bonus_crit_rate := 0.0
var bonus_crit_damage := 0.0
var bonus_damage_reduction := 0.0
var move_speed_penalty_mult := 1.0
var luck_roll_blue_offset := 0.0
var luck_roll_purple_offset := 0.0
var luck_roll_orange_offset := 0.0
var run_acquired_once: Dictionary = {}
var chapter_acquired_once: Dictionary = {}
var force_legendary_upgrade_count := 0
var _trigger_ring_fade_t := 0.0
var death_anim: Dictionary = {}
var _auto_bullet_cycle_active := false
var _auto_bullet_released := false
var _draw_start_fx_frames: SpriteFrames
var _draw_start_fx_t := -1.0
var _draw_start_fx_duration := 0.0
var _draw_start_fx_sprite: Sprite2D
var _charge_flame_frames: SpriteFrames
var _charge_flame_anim_t := 0.0
var desperate_counter_timer := 0.0
var desperate_counter_bonus := 0.0
var steadfast_stand_timer := 0.0
var steadfast_active := false
var stillness_stack_timer := 0.0
var stillness_move_grace_timer := 0.0
var stillness_stacks := 0
const STILLNESS_MAX_STACKS := 15
const STILLNESS_CRIT_PER_STACK := 0.03
var _last_position := Vector2.ZERO
var _joystick_locomotion_active := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var trigger_area: Area2D = $TriggerArea
@onready var path_line: Line2D = $PathLine


func _ready() -> void:
	_load_base_stats()
	_draw_start_fx_frames = EffectHelper.build_effect_frames("air_slash")
	if _draw_start_fx_frames != null:
		_draw_start_fx_duration = EffectHelper.one_shot_anim_duration(_draw_start_fx_frames)
	_charge_flame_frames = EffectHelper.build_effect_frames("flame_loop")
	home_position = global_position
	_last_position = global_position
	_setup_sprite()
	_update_trigger_radius()
	path_line.width = GameConfig.scale_world(PATH_LINE_WIDTH)
	path_line.default_color = PATH_LINE_COLOR
	path_line.top_level = true


func _load_base_stats() -> void:
	base_attack = float(GameConfig.get_player_value("base_attack", 95))
	max_hp = int(GameConfig.get_player_value("base_hp", 100))
	hp = max_hp
	base_ki = float(GameConfig.get_player_value("base_ki", 234))
	ki_max = base_ki
	ki = ki_max
	crit_rate = float(GameConfig.get_player_value("base_crit_rate", 0.08))
	crit_damage = float(GameConfig.get_player_value("base_crit_damage", 1.6))
	combo_damage_bonus = float(GameConfig.get_player_value("combo_damage_bonus", 0.01))
	basic_attack_speed = maxf(0.01, float(GameConfig.get_player_value("basic_attack_speed", 2.0)))
	ki_regen_speed = maxf(0.0, float(GameConfig.get_player_value("ki_regen_speed", 135.0)))
	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += int(equip.get("max_hp", 0))
		crit_rate += float(equip.get("crit_rate", 0.0))
		hp = max_hp
	size_scale = 1.0
	bullet_count = 1


func _apply_sprite_scale() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return
	SpriteHelper.apply_pixel_art(anim_sprite)
	var scale_val := float(GameConfig.get_player_value("sprite_scale", 1.0))
	var final_scale := SpriteHelper.pixel_scale(scale_val, size_scale)
	anim_sprite.scale = Vector2.ONE * final_scale


func _get_sprite() -> AnimatedSprite2D:
	if sprite != null:
		return sprite
	return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func get_sprite_node() -> AnimatedSprite2D:
	return _get_sprite()


func _setup_sprite() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		push_warning("BattlePlayer: AnimatedSprite2D not ready")
		return
	var folder := str(GameConfig.get_player_value("character_folder", "Swordsman"))
	var prefix := str(GameConfig.get_player_value("sprite_prefix", "Swordsman"))
	anim_sprite.sprite_frames = SpriteHelper.build_character_frames(folder, prefix)
	SpriteHelper.apply_pixel_art(anim_sprite)
	SpriteHelper.sync_attack01_speed(
		anim_sprite.sprite_frames,
		get_auto_bullet_cycle_interval()
	)
	if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	if not anim_sprite.animation_finished.is_connected(_on_animation_finished):
		anim_sprite.animation_finished.connect(_on_animation_finished)
	if not anim_sprite.frame_changed.is_connected(_on_sprite_frame_changed):
		anim_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_apply_sprite_scale()


func apply_config() -> void:
	_load_base_stats()
	_setup_sprite()
	_update_trigger_radius()
	queue_redraw()


func _update_trigger_radius() -> void:
	var ref_w := float(GameConfig.get_tuning("logical_width", 720))
	var min_r := GameConfig.scale_world(float(GameConfig.get_player_value("trigger_radius_min", 30)))
	var ratio := float(GameConfig.get_player_value("trigger_radius_ratio", 0.06))
	var radius := maxf(min_r, ratio * ref_w) * size_scale
	if trigger_area.get_child_count() > 0:
		var shape := trigger_area.get_child(0) as CollisionShape2D
		if shape and shape.shape is CircleShape2D:
			(shape.shape as CircleShape2D).radius = radius


func get_effective_radius() -> float:
	return GameConfig.scale_world(float(GameConfig.get_player_value("hitbox_radius", 12))) * size_scale


func get_path_hit_pad() -> float:
	return get_effective_radius() * PATH_HIT_PAD_RATIO


func get_trigger_radius() -> float:
	var ref_w := float(GameConfig.get_tuning("logical_width", 720))
	var min_r := GameConfig.scale_world(float(GameConfig.get_player_value("trigger_radius_min", 30)))
	var ratio := float(GameConfig.get_player_value("trigger_radius_ratio", 0.06))
	return maxf(min_r, ratio * ref_w) * size_scale


func _get_trigger_ring_fade_duration() -> float:
	return maxf(0.001, float(GameConfig.get_player_value("trigger_ring_fade_in", 0.35)))


func _get_trigger_ring_alpha() -> float:
	var t := clampf(_trigger_ring_fade_t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _update_trigger_ring_fade(delta: float) -> void:
	var should_show := state == State.IDLE and is_ki_full()
	if should_show:
		if _trigger_ring_fade_t >= 1.0:
			return
		_trigger_ring_fade_t = minf(1.0, _trigger_ring_fade_t + delta / _get_trigger_ring_fade_duration())
		queue_redraw()
	elif _trigger_ring_fade_t > 0.0:
		_trigger_ring_fade_t = 0.0
		queue_redraw()


func is_ki_full() -> bool:
	return ki >= ki_max - 0.01


func is_in_attack_mode() -> bool:
	return state == State.ATTACKING


func is_attack_invincible() -> bool:
	return state == State.ATTACKING


func get_auto_bullet_cycle_interval() -> float:
	var interval := 1.0 / maxf(0.01, basic_attack_speed * attack_speed_mult * bonus_attack_speed_mult * move_speed_penalty_mult)
	var charge_lv := get_upgrade_level("charge_strike")
	if charge_lv > 0 and charge_strike_time > 0.05:
		var charge_bonus := clampf(charge_strike_time / 3.0, 0.0, 1.0)
		interval /= 1.0 + charge_bonus * (0.35 + 0.08 * float(charge_lv))
	return interval


func sync_auto_bullet_anim_speed() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	SpriteHelper.sync_attack01_speed(anim_sprite.sprite_frames, get_auto_bullet_cycle_interval())


func begin_auto_bullet_cycle() -> bool:
	if state != State.IDLE:
		return false
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return false
	if not anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK01):
		return false
	sync_auto_bullet_anim_speed()
	_auto_bullet_cycle_active = true
	_auto_bullet_released = false
	_play_anim(SpriteHelper.ANIM_ATTACK01, true)
	if _get_auto_bullet_release_frame() <= 0:
		_auto_bullet_released = true
		auto_bullet_released.emit()
	return true


func _get_auto_bullet_release_frame() -> int:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return 0
	if not anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK01):
		return 0
	var count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_ATTACK01)
	return clampi(int(floor(float(count) * AUTO_BULLET_RELEASE_RATIO)), 0, maxi(0, count - 1))


func _on_sprite_frame_changed() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite != null and is_fail_death_pose() and not bool(death_anim.get("frozen", false)):
		_update_fail_death_last_frame_speed(anim_sprite)
	if not _auto_bullet_cycle_active or _auto_bullet_released:
		return
	if anim_sprite == null or anim_sprite.animation != SpriteHelper.ANIM_ATTACK01:
		return
	if anim_sprite.frame >= _get_auto_bullet_release_frame():
		_auto_bullet_released = true
		auto_bullet_released.emit()


func begin_stage() -> void:
	state = State.IDLE
	damage_flash_timer = 0.0
	_reset_sprite_pose()
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	combo_count = 0.0
	combo_hit_count = 0
	combo_display_peak = 0
	combo_display_weight = 0.0
	combo_display_fading = false
	water_tornado_charge = 0
	whirl_charge = 0
	_auto_bullet_cycle_active = false
	_auto_bullet_released = false
	turn_buff_attack_mult = 1.0
	turn_buff_combo_mult = 1.0
	ice_ready = false
	draw_session_snapshot = null
	collected_orb_buffs.clear()
	ki_max = round(base_ki * (1.0 + next_turn_ki_bonus))
	ki = ki_max
	next_turn_ki_bonus = 0.0
	_trigger_ring_fade_t = 0.0
	queue_redraw()
	_update_path_line()


func start_bullet_time() -> void:
	state = State.BULLET_TIME
	clear_drawing_combo_preview()
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	hit_projectiles_this_attack.clear()
	_play_draw_start_fx()
	add_path_point(home_position)


func _play_draw_start_fx() -> void:
	if _draw_start_fx_frames == null or _draw_start_fx_duration <= 0.0:
		return
	var fx_sprite := _ensure_draw_start_fx_sprite()
	_draw_start_fx_t = 0.0
	fx_sprite.visible = true
	_update_draw_start_fx_sprite()


func _ensure_draw_start_fx_sprite() -> Sprite2D:
	if _draw_start_fx_sprite == null:
		_draw_start_fx_sprite = Sprite2D.new()
		_draw_start_fx_sprite.centered = true
		_draw_start_fx_sprite.z_index = 2
		SpriteHelper.apply_pixel_art(_draw_start_fx_sprite)
		add_child(_draw_start_fx_sprite)
	return _draw_start_fx_sprite


func _update_draw_start_fx(delta: float) -> void:
	if _draw_start_fx_t < 0.0:
		return
	_draw_start_fx_t += delta
	if _draw_start_fx_t >= _draw_start_fx_duration:
		_draw_start_fx_t = -1.0
		if _draw_start_fx_sprite:
			_draw_start_fx_sprite.visible = false
		return
	_update_draw_start_fx_sprite()


func _update_draw_start_fx_sprite() -> void:
	if _draw_start_fx_t < 0.0 or _draw_start_fx_frames == null:
		return
	var fx_sprite := _ensure_draw_start_fx_sprite()
	var tex := EffectHelper.animation_frame_texture_once(_draw_start_fx_frames, _draw_start_fx_t)
	if tex == null:
		fx_sprite.visible = false
		return
	var life_t := clampf(_draw_start_fx_t / maxf(0.001, _draw_start_fx_duration), 0.0, 1.0)
	fx_sprite.texture = tex
	fx_sprite.scale = Vector2.ONE * DRAW_START_FX_SCALE
	fx_sprite.modulate = Color(1.0, 0.98, 0.82, 1.0 - life_t * 0.25)
	fx_sprite.visible = true


func add_path_point(point: Vector2) -> void:
	if attack_path.is_empty() or attack_path.back().distance_to(point) >= 2.0:
		attack_path.append(point)
		_update_path_line()


func consume_ki_by_distance(distance: float) -> bool:
	var cost := distance * float(GameConfig.get_player_value("ki_per_pixel", 0.18))
	if ki < cost:
		return false
	ki -= cost
	return true


func invalidate_path() -> void:
	state = State.IDLE
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	clear_drawing_combo_preview()
	_update_path_line()


func start_attack() -> void:
	if attack_path.size() < 2:
		invalidate_path()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.buff_orbs:
		battle.buff_orbs.commit_draw_session()
	state = State.ATTACKING
	_reset_charge_strike()
	combo_count = 0.0
	combo_hit_count = 0
	if battle and battle.combat:
		battle.combat.begin_round_attack()
	if battle and battle.abilities:
		battle.abilities.on_resolve_started()
		battle.abilities.try_abyss_explosion(self, attack_path)
	path_index = 0
	path_progress = 0.0
	_path_hit_inside.clear()
	_attack_hits_primmed = false
	_last_attack_pos = attack_path[0]
	hit_projectiles_this_attack.clear()
	_apply_path_line_color()
	_play_anim(SpriteHelper.ANIM_ATTACK)


func update_attack(delta: float, combat: CombatDirector, monsters: Array) -> bool:
	if state != State.ATTACKING or attack_path.size() < 2:
		return false
	if not _attack_hits_primmed:
		_prime_path_start_hits(combat, monsters)
		_attack_hits_primmed = true
	var speed := float(GameConfig.get_player_value("attack_speed", 2300))
	path_progress += speed * delta
	while path_index < attack_path.size() - 1:
		var from := attack_path[path_index]
		var to := attack_path[path_index + 1]
		var seg_len := from.distance_to(to)
		if seg_len < 0.001:
			path_index += 1
			continue
		if path_progress >= seg_len:
			_record_path_crossings(_last_attack_pos, to, combat, monsters, path_index)
			_last_attack_pos = to
			path_progress -= seg_len
			path_index += 1
			continue
		var t := path_progress / seg_len
		var pos := from.lerp(to, t)
		global_position = pos
		_record_path_crossings(_last_attack_pos, pos, combat, monsters, path_index)
		_last_attack_pos = pos
		return false
	_finish_attack(combat)
	return true


func _prime_path_start_hits(combat: CombatDirector, monsters: Array) -> void:
	var hit_pad := get_path_hit_pad()
	var start := attack_path[0]
	for monster in monsters:
		if not is_instance_valid(monster) or not monster.is_combat_targetable():
			continue
		var hit_r: float = monster.get_hitbox_radius() + hit_pad
		var id: int = monster.get_instance_id()
		if start.distance_to(monster.global_position) <= hit_r:
			_path_hit_inside[id] = true
			combat.queue_hit(monster, 0, monster.global_position)
		else:
			_path_hit_inside[id] = false


func _record_path_crossings(
	prev: Vector2,
	curr: Vector2,
	combat: CombatDirector,
	monsters: Array,
	segment_index: int,
) -> void:
	if prev.distance_squared_to(curr) < 0.0001:
		return
	var hit_pad := get_path_hit_pad()
	for monster in monsters:
		if not is_instance_valid(monster) or not monster.is_combat_targetable():
			continue
		var hit_r: float = monster.get_hitbox_radius() + hit_pad
		var center: Vector2 = monster.global_position
		var id: int = monster.get_instance_id()
		var inside: bool = bool(_path_hit_inside.get(id, prev.distance_to(center) <= hit_r))
		for ev in MathUtils.segment_circle_crossings(prev, curr, center, hit_r):
			if bool(ev.get("enter", false)):
				if not inside:
					combat.queue_hit(monster, segment_index, center)
				inside = true
			else:
				inside = false
		_path_hit_inside[id] = inside
	var battle := get_tree().get_first_node_in_group("battle") as BattleController
	if battle:
		battle.block_projectiles_on_path_segment(prev, curr, segment_index, self)


func _finish_attack(combat: CombatDirector) -> void:
	home_position = global_position
	state = State.IDLE
	_reset_sprite_pose()
	_play_anim(SpriteHelper.ANIM_IDLE)
	combat.consume_round_attack()
	combat.begin_resolve(self)
	attack_path.clear()
	_update_path_line()


func end_combo_turn() -> void:
	if combo_display_peak >= 2:
		combo_display_fading = true
		combo_display_timer = 0.4
	else:
		clear_drawing_combo_preview()
	combo_count = 0.0
	combo_hit_count = 0


func get_combo_bonus_percent(_combo: int = -1) -> int:
	var weighted := combo_display_weight if combo_display_weight > 0.0 else combo_count
	if weighted <= 1.0:
		return 0
	return int(round((weighted - 1.0) * combo_damage_bonus * 100.0))


func _combo_hit_increment() -> float:
	var multi_combo_lv := get_upgrade_level("multi_combo")
	return turn_buff_combo_mult * (1.0 + 0.2 * float(multi_combo_lv))


func clear_drawing_combo_preview() -> void:
	combo_display_peak = 0
	combo_display_weight = 0.0
	combo_display_fading = false
	combo_display_timer = 0.0
	combo_count = 0.0
	combo_hit_count = 0


func is_combo_display_visible() -> bool:
	if combo_display_peak < 2:
		return false
	if combo_display_fading:
		return combo_display_timer > 0.0
	return true


func update_combo_preview(total_hits: int) -> void:
	if state != State.BULLET_TIME:
		return
	if total_hits < 2:
		if combo_display_peak >= 2:
			clear_drawing_combo_preview()
		return
	if total_hits == combo_display_peak:
		return
	var weighted := float(total_hits) * _combo_hit_increment()
	combo_display_peak = total_hits
	combo_display_weight = weighted
	combo_display_fading = false
	combo_display_timer = 1.0


func update_combo_display(delta: float) -> void:
	if combo_display_fading and combo_display_timer > 0.0:
		combo_display_timer = maxf(0.0, combo_display_timer - delta)


func get_ability_damage(mult: float) -> int:
	return int(max(1, round(base_attack * attack_power_scale * bonus_attack_mult * mult)))


func get_auto_bullet_damage() -> int:
	var mult := float(GameConfig.get_player_value("auto_bullet_damage_mult", 0.2))
	var dmg := float(get_ability_damage(1)) * turn_buff_attack_mult * mult
	if get_upgrade_level("spirit_bomb") > 0:
		var def := GameConfig.get_upgrade("spirit_bomb")
		dmg *= float(def.get("apply_value", 1.3))
	return int(max(1, round(dmg)))


func has_spirit_bomb() -> bool:
	return get_upgrade_level("spirit_bomb") > 0


func has_pierce_bullet() -> bool:
	return get_upgrade_level("pierce") > 0


func has_mirror_bullet() -> bool:
	return get_upgrade_level("mirror_bullet") > 0


func get_bounce_bullet_count() -> int:
	return get_upgrade_level("bounce_bullet")


func get_laser_blast_chance() -> float:
	var lv := get_upgrade_level("laser_blast")
	if lv <= 0:
		return 0.0
	var def := GameConfig.get_upgrade("laser_blast")
	return minf(0.45, float(def.get("apply_value", 0.06)) * float(lv))


func register_combo_hit() -> float:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or not battle.combat.is_resolving():
		return combo_count
	combo_hit_count += 1
	var inc := _combo_hit_increment()
	combo_count += inc
	EventBus.combo_changed.emit(combo_hit_count)
	return combo_count


func get_effective_crit_rate() -> float:
	return minf(0.95, crit_rate + bonus_crit_rate)


func roll_crit_damage(raw: float) -> Dictionary:
	var is_crit := randf() < get_effective_crit_rate()
	var final := raw
	if is_crit:
		final *= crit_damage + bonus_crit_damage
	return {"amount": int(max(1, round(final))), "is_crit": is_crit}


func get_attack_damage(combo: float) -> Dictionary:
	var bonus := 1.0 + combo_damage_bonus * float(combo)
	var raw := base_attack * attack_power_scale * turn_buff_attack_mult * bonus * slash_damage_mult * bonus_attack_mult
	var charge_lv := get_upgrade_level("charge_strike")
	if charge_lv > 0 and charge_strike_time > 0.05:
		var charge_bonus := clampf(charge_strike_time / 3.0, 0.0, 1.0)
		raw *= 1.0 + charge_bonus * (0.45 + 0.12 * float(charge_lv))
	return roll_crit_damage(raw)


func take_damage(amount: int) -> int:
	if invincible_timer > 0.0 or is_attack_invincible():
		return 0
	if holy_shield_charges > 0:
		holy_shield_charges -= 1
		holy_shield_timer = _get_holy_shield_interval()
		queue_redraw()
		var battle := get_tree().get_first_node_in_group("battle")
		if battle and battle.hud:
			battle.hud.show_message("圣盾抵挡", 0.9)
		return 0
	var final_damage := int(max(1, round(float(amount) * maxf(0.2, 1.0 - bonus_damage_reduction))))
	hp = maxi(0, hp - final_damage)
	invincible_timer = float(GameConfig.get_player_value("invincible_time", 0.45))
	damage_flash_timer = 0.42
	queue_redraw()
	if state == State.IDLE:
		_auto_bullet_cycle_active = false
		_auto_bullet_released = false
		_play_anim(SpriteHelper.ANIM_HURT)
	_on_player_damaged_trigger()
	EventBus.player_damaged.emit(final_damage, hp)
	AudioManager.play_player_hurt()
	var battle := get_tree().get_first_node_in_group("battle")
	if battle:
		battle.shake_camera(4.0, 0.12)
	return final_damage


func heal_percent(ratio: float) -> void:
	var amount := int(round(max_hp * ratio))
	hp = mini(max_hp, hp + amount)
	queue_redraw()
	EventBus.player_healed.emit(amount, hp)


func apply_upgrade(upgrade: Dictionary) -> void:
	var id := str(upgrade.get("id", ""))
	var def := GameConfig.get_upgrade(id)
	if def.is_empty():
		def = upgrade
	if int(def.get("once_per_run", 0)) != 0:
		run_acquired_once[id] = true
	if int(def.get("once_per_chapter", 0)) != 0:
		chapter_acquired_once[id] = true
	upgrade_stacks[id] = int(upgrade_stacks.get(id, 0)) + 1
	_rebuild_upgrades()
	if id == "super_mushroom":
		hp = max_hp
		queue_redraw()
	elif id == "holy_shield":
		grant_holy_shield_immediate()


func is_upgrade_pool_blocked(id: String) -> bool:
	var def := GameConfig.get_upgrade(id)
	if def.is_empty():
		return false
	if int(def.get("once_per_run", 0)) != 0 and bool(run_acquired_once.get(id, false)):
		return true
	if int(def.get("once_per_chapter", 0)) != 0 and bool(chapter_acquired_once.get(id, false)):
		return true
	return false


func get_luck_roll_offsets() -> Dictionary:
	return {
		"blue": luck_roll_blue_offset,
		"purple": luck_roll_purple_offset,
		"orange": luck_roll_orange_offset,
	}


func on_chapter_started(_chapter_id: int) -> void:
	chapter_acquired_once.clear()


func _reset_charge_strike() -> void:
	charge_strike_time = 0.0
	_charge_flame_anim_t = 0.0
	_queue_charge_flame_redraw()


func _accumulate_charge_strike(delta: float, time_scale: float) -> void:
	if get_upgrade_level("charge_strike") <= 0:
		return
	if state != State.IDLE:
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.combat == null:
		return
	if battle.state == GameState.LEVEL_UP:
		return
	var was_charging := charge_strike_time > 0.0
	if global_position.distance_to(home_position) > 14.0:
		charge_strike_time = maxf(0.0, charge_strike_time - delta * time_scale * 0.5)
	else:
		charge_strike_time = minf(6.0, charge_strike_time + delta * time_scale)
	if was_charging != (charge_strike_time > 0.0):
		_queue_charge_flame_redraw()


func _ensure_charge_flame_frames() -> SpriteFrames:
	if _charge_flame_frames == null or _charge_flame_frames.get_frame_count(EffectHelper.ANIM_PREVIEW) <= 0:
		_charge_flame_frames = EffectHelper.build_effect_frames("flame_loop")
	return _charge_flame_frames


func _queue_charge_flame_redraw() -> void:
	queue_redraw()


func _tick_charge_flame_anim(delta: float) -> void:
	if get_upgrade_level("charge_strike") <= 0:
		return
	if state != State.IDLE or charge_strike_time <= 0.0:
		return
	_charge_flame_anim_t += delta
	queue_redraw()


func _draw_charge_flame() -> void:
	if get_upgrade_level("charge_strike") <= 0:
		return
	var frames := _ensure_charge_flame_frames()
	if frames == null or frames.get_frame_count(EffectHelper.ANIM_PREVIEW) <= 0:
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle != null and battle.state == GameState.LEVEL_UP:
		return
	if state != State.IDLE or charge_strike_time <= 0.0:
		return
	var charge_t := clampf(charge_strike_time / 3.0, 0.0, 1.0)
	var tex := EffectHelper.animation_frame_texture(frames, _charge_flame_anim_t)
	if tex == null:
		return
	var size := tex.get_size()
	var size_scale_t := lerpf(1.15, 1.5, charge_t)
	var draw_scale := (get_effective_radius() * 3.75 * size_scale_t) / maxf(size.x, size.y)
	var low := Color(1.0, 0.98, 0.62, 0.78)
	var high := Color(1.0, 0.38, 0.08, 0.95)
	var color_t := pow(charge_t, 0.55)
	var modulate := low.lerp(high, color_t)
	var feet_local := Vector2(0.0, get_effective_radius() * 0.35)
	SpriteHelper.draw_effect_texture_bottom_center(
		self,
		tex,
		feet_local,
		Vector2.ONE * draw_scale,
		modulate
	)


func get_upgrade_level(id: String) -> int:
	return int(upgrade_stacks.get(id, 0))


func rebuild_upgrades_from_stacks(stacks: Dictionary, silent := false) -> void:
	var hp_ratio := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	upgrade_stacks.clear()
	for u in GameConfig.upgrades:
		var id := str(u.get("id", ""))
		var lv := clampi(int(stacks.get(id, 0)), 0, int(u.get("max_level", 9)))
		if lv > 0:
			upgrade_stacks[id] = lv
	_rebuild_upgrades()
	hp = maxi(1, int(round(float(max_hp) * hp_ratio)))
	ki = minf(ki, ki_max)
	if not silent:
		var battle := get_tree().get_first_node_in_group("battle")
		if battle and battle.hud:
			battle.hud.show_message("调试: 强化已更新", 1.2)


func _rebuild_upgrades() -> void:
	base_attack = float(GameConfig.get_player_value("base_attack", 95))
	base_ki = float(GameConfig.get_player_value("base_ki", 234))
	max_hp = int(GameConfig.get_player_value("base_hp", 100))
	crit_rate = float(GameConfig.get_player_value("base_crit_rate", 0.08))
	basic_attack_speed = maxf(0.01, float(GameConfig.get_player_value("basic_attack_speed", 2.0)))
	ki_regen_speed = maxf(0.0, float(GameConfig.get_player_value("ki_regen_speed", 135.0)))
	size_scale = 1.0
	bullet_count = 1
	attack_speed_mult = 1.0
	ki_regen_mult = 1.0
	slash_damage_mult = 1.0
	bonus_attack_mult = 1.0
	bonus_attack_speed_mult = 1.0
	bonus_crit_rate = 0.0
	bonus_crit_damage = 0.0
	bonus_damage_reduction = 0.0
	move_speed_penalty_mult = 1.0
	luck_roll_blue_offset = 0.0
	luck_roll_purple_offset = 0.0
	luck_roll_orange_offset = 0.0
	for id in upgrade_stacks.keys():
		var level := int(upgrade_stacks[id])
		var def := GameConfig.get_upgrade(id)
		if def.is_empty():
			continue
		var apply_type := str(def.get("apply_type", ""))
		match apply_type:
			"ki_mult":
				base_ki = round(base_ki * pow(float(def.get("apply_value", 1.2)), level))
			"bullet_count":
				bullet_count += level
			"crit_rate":
				crit_rate += float(def.get("apply_value", 0.05)) * level
			"godspeed":
				attack_speed_mult *= pow(float(def.get("apply_value", 1.3)), level)
				ki_regen_mult *= pow(0.85, float(level))
			"luck_roll":
				luck_roll_blue_offset -= 0.04 * float(level)
				luck_roll_purple_offset += 0.03 * float(level)
				luck_roll_orange_offset += 0.01 * float(level)
			"super_mushroom":
				if level > 0:
					max_hp = int(round(float(max_hp) * 1.2))
					size_scale *= 1.5
					slash_damage_mult *= 1.3
			"combo_mult":
				pass
			"barrage_king":
				if level > 0:
					bullet_count += 3
					move_speed_penalty_mult *= 0.8
	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += int(equip.get("max_hp", 0))
		crit_rate += float(equip.get("crit_rate", 0.0))
	ki_max = base_ki
	ki_regen_speed *= ki_regen_mult
	hp = mini(hp, max_hp)
	_update_trigger_radius()
	_apply_sprite_scale()
	sync_auto_bullet_anim_speed()
	_queue_charge_flame_redraw()


func grant_force_legendary_upgrade() -> void:
	force_legendary_upgrade_count += 1


func consume_force_legendary_upgrade() -> bool:
	if force_legendary_upgrade_count <= 0:
		return false
	force_legendary_upgrade_count -= 1
	return true


func _play_anim(anim_name: String, force: bool = false) -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if anim_name == SpriteHelper.ANIM_HURT:
		force = true
	if not force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	if force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		anim_sprite.stop()
		anim_sprite.frame = 0
	anim_sprite.play(anim_name)
	_apply_combat_modulate()


func _on_animation_finished() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if anim_sprite.animation == SpriteHelper.ANIM_DEATH:
		if is_fail_death_pose() and not bool(death_anim.get("frozen", false)):
			death_anim["anim_finished"] = true
		return
	if anim_sprite.animation in [SpriteHelper.ANIM_ATTACK, SpriteHelper.ANIM_ATTACK01, SpriteHelper.ANIM_HURT]:
		if state == State.ATTACKING and anim_sprite.animation == SpriteHelper.ANIM_ATTACK:
			return
		if anim_sprite.animation == SpriteHelper.ANIM_ATTACK01:
			_auto_bullet_cycle_active = false
			_auto_bullet_released = false
		if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)


func _apply_combat_modulate() -> void:
	if damage_flash_timer > 0.0 and int(floor(damage_flash_timer * 22.0)) % 2 == 0:
		modulate = Color(1.0, 0.45, 0.45)
	elif invincible_timer > 0.0 and damage_flash_timer <= 0.0 and int(floor(invincible_timer * 18.0)) % 2 == 0:
		modulate = Color(1.0, 1.0, 1.0, 0.55)
	else:
		modulate = Color.WHITE


func trigger_combo_abilities(_combo: int, _target_pos: Vector2) -> void:
	pass


func update_joystick_locomotion(dir: Vector2, delta: float, battle: Node) -> void:
	if state != State.IDLE:
		_stop_joystick_locomotion_visual()
		return
	if dir.length_squared() < 0.01:
		_stop_joystick_locomotion_visual()
		return
	var speed := float(GameConfig.get_player_value("move_speed", 120.0)) * move_speed_penalty_mult
	var next_pos := global_position + dir.normalized() * speed * delta
	if battle != null and battle.has_method("is_in_bounds") and battle.is_in_bounds(next_pos):
		global_position = next_pos
		home_position = global_position
	var anim_sprite := _get_sprite()
	if anim_sprite:
		if dir.x < -0.01:
			anim_sprite.flip_h = true
		elif dir.x > 0.01:
			anim_sprite.flip_h = false
	_joystick_locomotion_active = true
	if not SpriteHelper.is_playing_priority_anim(anim_sprite):
		_play_anim(SpriteHelper.ANIM_WALK)


func _stop_joystick_locomotion_visual() -> void:
	if not _joystick_locomotion_active:
		return
	_joystick_locomotion_active = false
	if state != State.IDLE:
		return
	var anim_sprite := _get_sprite()
	if anim_sprite and not SpriteHelper.is_playing_priority_anim(anim_sprite):
		_play_anim(SpriteHelper.ANIM_IDLE)


func update_idle(delta: float, time_scale: float) -> void:
	if state != State.IDLE:
		return
	if invincible_timer > 0.0:
		invincible_timer -= delta
	if damage_flash_timer > 0.0:
		damage_flash_timer -= delta
	_apply_combat_modulate()
	_accumulate_charge_strike(delta, time_scale)
	if _can_regen_ki():
		ki = minf(ki_max, ki + ki_regen_speed * delta * time_scale)
	_update_holy_shield(delta)


func _can_regen_ki() -> bool:
	if state != State.IDLE or ki >= ki_max - 0.01:
		return false
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.combat == null:
		return false
	if battle.combat.is_resolving():
		return false
	if not battle.combat.round_attack_resolved:
		return false
	if battle.state == GameState.LEVEL_UP:
		return false
	return true


func reset_for_new_run() -> void:
	upgrade_stacks.clear()
	run_acquired_once.clear()
	chapter_acquired_once.clear()
	force_legendary_upgrade_count = 0
	desperate_counter_timer = 0.0
	desperate_counter_bonus = 0.0
	steadfast_stand_timer = 0.0
	steadfast_active = false
	stillness_stack_timer = 0.0
	stillness_move_grace_timer = 0.0
	stillness_stacks = 0
	charge_strike_time = 0.0
	clear_fail_death_visuals()
	_load_base_stats()
	hp = max_hp
	ki = ki_max
	home_position = global_position
	begin_stage()
	_rebuild_upgrades()


func _get_holy_shield_max_charges() -> int:
	if get_upgrade_level("holy_shield") <= 0:
		return 0
	return 5


func _get_holy_shield_interval() -> float:
	var lv := get_upgrade_level("holy_shield")
	if lv <= 0:
		return 0.0
	return maxf(1.0, 15.0 - float(holy_shield_charges))


func grant_holy_shield_immediate() -> void:
	if get_upgrade_level("holy_shield") <= 0:
		return
	var max_charges := _get_holy_shield_max_charges()
	if holy_shield_charges < max_charges:
		holy_shield_charges += 1
	holy_shield_timer = _get_holy_shield_interval()
	queue_redraw()


func _update_holy_shield(delta: float) -> void:
	if get_upgrade_level("holy_shield") <= 0:
		return
	var max_charges := _get_holy_shield_max_charges()
	if holy_shield_charges >= max_charges:
		return
	holy_shield_timer -= delta
	if holy_shield_timer <= 0.0:
		holy_shield_charges += 1
		holy_shield_timer = _get_holy_shield_interval()
		queue_redraw()


func on_enemy_killed(_kill_pos: Vector2) -> void:
	pass


func get_bonus_damage_reduction() -> float:
	return clampf(bonus_damage_reduction, 0.0, 0.8)


func get_desperate_counter_ratio() -> float:
	if desperate_counter_timer <= 0.0:
		return 0.0
	return desperate_counter_bonus


func get_steadfast_ratio() -> float:
	return get_bonus_damage_reduction() if steadfast_active else 0.0


func get_stillness_stacks() -> int:
	return stillness_stacks


func is_near_stationary() -> bool:
	return global_position.distance_to(_last_position) <= 2.0


func get_total_summons_count() -> int:
	var total := 0
	for id in ["wild_wolf", "wild_bull", "divine_god"]:
		var lv := get_upgrade_level(id)
		if lv <= 0:
			continue
		var def := GameConfig.get_upgrade(id)
		var per_level := maxi(1, int(def.get("apply_value", 1)))
		total += lv * per_level * (2 if get_upgrade_level("nurturing_heart") > 0 else 1)
	return total


func on_summon_hit() -> void:
	if get_upgrade_level("bloodthirst") <= 0:
		return
	var chance := 0.08
	if randf() <= chance:
		heal_percent(0.01)


func _on_player_damaged_trigger() -> void:
	var lv := get_upgrade_level("desperate_counter")
	if lv <= 0:
		return
	desperate_counter_bonus = 0.2 + 0.05 * float(maxi(0, lv - 1))
	desperate_counter_timer = 4.0


func _update_new_upgrade_states(delta: float) -> void:
	bonus_attack_mult = 1.0
	bonus_attack_speed_mult = 1.0
	bonus_crit_rate = 0.0
	bonus_crit_damage = 0.0
	bonus_damage_reduction = 0.0
	_update_desperate_counter(delta)
	_update_steadfast_guard(delta)
	_update_stillness_heart(delta)
	_update_wild_call()
	_update_adversity_heart()
	_last_position = global_position


func _update_desperate_counter(delta: float) -> void:
	if desperate_counter_timer > 0.0:
		desperate_counter_timer = maxf(0.0, desperate_counter_timer - delta)
	if desperate_counter_timer > 0.0:
		bonus_crit_rate = desperate_counter_bonus
		bonus_attack_speed_mult *= 1.0 + desperate_counter_bonus
	else:
		bonus_crit_rate = 0.0


func _update_steadfast_guard(delta: float) -> void:
	var lv := get_upgrade_level("steadfast_guard")
	var prev_active := steadfast_active
	if lv <= 0:
		steadfast_stand_timer = 0.0
		steadfast_active = false
		if prev_active != steadfast_active:
			queue_redraw()
		return
	if is_near_stationary() and state == State.IDLE:
		steadfast_stand_timer += delta
		if steadfast_stand_timer >= 1.5:
			steadfast_active = true
	else:
		steadfast_stand_timer = 0.0
		steadfast_active = false
	if steadfast_active:
		bonus_damage_reduction = minf(0.6, 0.3 + 0.05 * float(maxi(0, lv - 1)))
	else:
		bonus_damage_reduction = 0.0
	if prev_active != steadfast_active:
		queue_redraw()


func _update_stillness_heart(delta: float) -> void:
	if get_upgrade_level("stillness_heart") <= 0:
		stillness_stacks = 0
		stillness_stack_timer = 0.0
		stillness_move_grace_timer = 0.0
		bonus_crit_damage = 0.0
		return
	if is_near_stationary() and state == State.IDLE:
		stillness_move_grace_timer = 3.0
		stillness_stack_timer += delta
		while stillness_stack_timer >= 0.5:
			stillness_stack_timer -= 0.5
			stillness_stacks = mini(stillness_stacks + 1, STILLNESS_MAX_STACKS)
	else:
		stillness_stack_timer = 0.0
		stillness_move_grace_timer = maxf(0.0, stillness_move_grace_timer - delta)
		if stillness_move_grace_timer <= 0.0:
			stillness_stacks = 0
	bonus_crit_rate += STILLNESS_CRIT_PER_STACK * float(stillness_stacks)
	bonus_crit_damage = STILLNESS_CRIT_PER_STACK * float(stillness_stacks)


func _update_wild_call() -> void:
	var lv := get_upgrade_level("wild_call")
	if lv <= 0:
		return
	var per := 0.06 + 0.02 * float(maxi(0, lv - 1))
	var pet_cnt := get_total_summons_count()
	bonus_attack_speed_mult *= 1.0 + per * float(pet_cnt)


func _update_adversity_heart() -> void:
	var lv := get_upgrade_level("adversity_heart")
	if lv <= 0:
		return
	if hp < int(round(float(max_hp) * 0.5)):
		bonus_attack_mult = 1.0 + (0.15 + 0.05 * float(maxi(0, lv - 1)))


func _apply_path_line_color() -> void:
	path_line.default_color = PATH_LINE_COLOR_ATTACK if state == State.ATTACKING else PATH_LINE_COLOR


func _update_path_line() -> void:
	path_line.clear_points()
	for p in attack_path:
		path_line.add_point(p)
	_apply_path_line_color()


func begin_fail_death(info: Dictionary) -> void:
	death_anim = info.duplicate()
	death_anim["active"] = true
	_trigger_ring_fade_t = 0.0
	path_line.visible = false
	modulate = Color.WHITE
	z_index = 2
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		queue_redraw()
		return
	anim_sprite.rotation = 0.0
	anim_sprite.position = Vector2.ZERO
	var speed_scale := maxf(0.05, float(info.get("speed_scale", 0.35)))
	var frame_count := 0
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		frame_count = anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if frame_count <= 1:
		anim_sprite.speed_scale = 1.0
	else:
		anim_sprite.speed_scale = speed_scale
	death_anim["slow_speed_scale"] = speed_scale
	death_anim["last_frame_normal"] = frame_count <= 1
	death_anim["anim_finished"] = false
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		anim_sprite.play(SpriteHelper.ANIM_DEATH)
	elif anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	queue_redraw()


func freeze_fail_death_pose() -> void:
	if death_anim.is_empty():
		return
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		death_anim["frozen"] = true
		return
	anim_sprite.stop()
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		var frame_count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
		if frame_count > 0:
			anim_sprite.frame = frame_count - 1
	death_anim["frozen"] = true
	queue_redraw()


func _reset_sprite_pose() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.rotation = 0.0
		anim_sprite.position = Vector2.ZERO
	modulate = Color.WHITE


func clear_fail_death_visuals() -> void:
	death_anim.clear()
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.speed_scale = 1.0
		anim_sprite.rotation = 0.0
		anim_sprite.position = Vector2.ZERO
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)
	z_index = 0
	modulate = Color.WHITE
	queue_redraw()


func is_fail_death_pose() -> bool:
	return not death_anim.is_empty() and bool(death_anim.get("active", false))


func is_fail_death_anim_finished() -> bool:
	return bool(death_anim.get("anim_finished", false))


func _update_fail_death_last_frame_speed(anim_sprite: AnimatedSprite2D) -> void:
	if anim_sprite.sprite_frames == null or anim_sprite.animation != SpriteHelper.ANIM_DEATH:
		return
	if bool(death_anim.get("last_frame_normal", false)):
		return
	var frame_count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if frame_count <= 1:
		return
	if anim_sprite.frame >= frame_count - 2:
		death_anim["last_frame_normal"] = true
		anim_sprite.speed_scale = 1.0


func _process(delta: float) -> void:
	_update_draw_start_fx(delta)
	_tick_charge_flame_anim(delta)
	if is_fail_death_pose():
		path_line.visible = false
		queue_redraw()
		return
	if state == State.IDLE:
		_apply_combat_modulate()
	_update_new_upgrade_states(delta)
	path_line.visible = attack_path.size() >= 2
	_update_trigger_ring_fade(delta)


func _should_show_hp_bar() -> bool:
	return hp < max_hp


func get_head_top_global_position() -> Vector2:
	return SpriteHelper.get_character_head_top_global(
		_get_sprite(),
		global_position + Vector2(0.0, -get_effective_radius() * 1.5)
	)


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
			"border_color": "#122028",
			"panel_fill": "#101a20",
			"empty_a": "#18303a",
			"empty_b": "#10262f",
			"fill_color": "#36b88a",
			"shine_color": "#9cffd4",
			"segment_count": 8,
			"segment_gap": 1
		}
	)


func _draw_holy_shield() -> void:
	if holy_shield_charges <= 0:
		return
	var radius := get_effective_radius() + 10.0
	draw_circle(Vector2.ZERO, radius, Color(0.353, 0.667, 1.0, 0.18))
	_draw_closed_ring(Vector2.ZERO, radius, 64, Color(0.471, 0.784, 1.0, 0.85), 2.5)


func _draw_desperate_counter_fx() -> void:
	if desperate_counter_timer <= 0.0:
		return
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	var r := get_effective_radius() + 16.0 + pulse * 3.0
	_draw_closed_ring(Vector2.ZERO, r, 48, Color(1.0, 0.55, 0.28, 0.85), 2.0)
	draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 0.35, 0.25, 0.12))


func _draw_steadfast_guard_fx() -> void:
	if not steadfast_active:
		return
	var r := get_effective_radius() + 22.0
	_draw_closed_ring(Vector2.ZERO, r, 56, Color(0.4, 0.95, 0.78, 0.9), 2.6)
	draw_circle(Vector2.ZERO, r * 0.58, Color(0.26, 0.65, 0.55, 0.12))


func _draw_stillness_heart_fx() -> void:
	if get_upgrade_level("stillness_heart") <= 0 or stillness_stacks <= 0:
		return
	var r := get_effective_radius() + 8.0 + float(stillness_stacks) * 1.8
	var a := 0.28 + minf(0.45, 0.03 * float(stillness_stacks))
	_draw_closed_ring(Vector2.ZERO, r, 64, Color(0.72, 0.9, 1.0, a), 1.8)


func _draw_closed_ring(center: Vector2, radius: float, point_count: int, color: Color, width: float) -> void:
	# draw_arc at exactly [0, TAU] can show a visible seam at 0 angle on some scales.
	# Expand a tiny angle on both sides so both caps overlap and hide the gap.
	var overlap := TAU / maxf(96.0, float(point_count) * 2.0)
	draw_arc(center, radius, -overlap, TAU + overlap, point_count + 2, color, width)


func _draw() -> void:
	if is_fail_death_pose():
		return
	_draw_charge_flame()
	if _should_show_hp_bar():
		_draw_hp_bar()
	_draw_holy_shield()
	_draw_desperate_counter_fx()
	_draw_steadfast_guard_fx()
	_draw_stillness_heart_fx()
	var ring_alpha := _get_trigger_ring_alpha()
	if ring_alpha <= 0.0:
		return
	var radius := get_trigger_radius() * lerpf(0.88, 1.0, ring_alpha)
	var visual_radius := radius * TRIGGER_RING_VISUAL_SCALE
	_draw_closed_ring(
		Vector2.ZERO,
		visual_radius,
		64,
		Color(1.0, 1.0, 1.0, 0.35 * ring_alpha),
		GameConfig.scale_world(2.0)
	)
	_draw_closed_ring(
		Vector2.ZERO,
		visual_radius,
		64,
		Color(1.0, 0.9, 0.3, 0.12 * ring_alpha),
		visual_radius * 1.3
	)
