extends Node
class_name CombatDirector

const EffectHelperScript = preload("res://scripts/utils/effect_helper.gd")

signal resolve_finished

const SLASH_HIT_FX_SCALE := 1.55
const SLASH_HIT_FX_DRAW_SCALE := 2.15

var resolving := false
var round_attack_resolved := true
var pending_hits: Array = []
var resolve_timer := 0.0
var damage_numbers: Array = []
var afterimages: Array = []
var slash_hit_fx: Array = []
var _death_stagger_index := 0
var _slash_hit_frames: SpriteFrames


func _ready() -> void:
	_slash_hit_frames = EffectHelperScript.build_effect_frames("hit_a")


func reset_for_stage() -> void:
	clear_presentation()
	round_attack_resolved = true


func clear_presentation() -> void:
	resolving = false
	pending_hits.clear()
	resolve_timer = 0.0
	damage_numbers.clear()
	afterimages.clear()
	slash_hit_fx.clear()
	_death_stagger_index = 0


func begin_round_attack() -> void:
	round_attack_resolved = false
	pending_hits.clear()
	resolving = false
	resolve_timer = 0.0
	afterimages.clear()
	slash_hit_fx.clear()
	_death_stagger_index = 0


func consume_round_attack() -> bool:
	if round_attack_resolved:
		return false
	round_attack_resolved = true
	return true


func is_resolving() -> bool:
	return resolving


func should_monsters_attack(player: BattlePlayer) -> bool:
	if player == null:
		return true
	if player.state == BattlePlayer.State.BULLET_TIME:
		return false
	if player.state == BattlePlayer.State.ATTACKING:
		return false
	if resolving:
		return false
	return true


func has_combat_presentation() -> bool:
	return resolving or not afterimages.is_empty() or not damage_numbers.is_empty() or has_active_hit_fx()


func has_active_hit_fx() -> bool:
	return not slash_hit_fx.is_empty()


func schedule_death_fade() -> float:
	var delay := float(_death_stagger_index) * float(GameConfig.get_tuning("combat_death_stagger", 0.012))
	_death_stagger_index += 1
	return delay


func spawn_afterimage(pos: Vector2, angle: float) -> void:
	var life := float(GameConfig.get_tuning("combat_afterimage_life", 0.1))
	afterimages.append({
		"pos": pos,
		"angle": angle,
		"life": life,
		"max_life": life,
	})


func update_afterimages(delta: float) -> void:
	if afterimages.is_empty() or delta <= 0.0:
		return
	var i := afterimages.size() - 1
	while i >= 0:
		var img: Dictionary = afterimages[i]
		var life := float(img.get("life", 0.0)) - delta
		if life <= 0.0:
			afterimages.remove_at(i)
		else:
			img["life"] = life
			afterimages[i] = img
		i -= 1


func get_path_preview_hit_counts(path: Array, player: BattlePlayer, targets: Array) -> Dictionary:
	var result := {}
	if path.size() < 2 or player == null:
		return result
	var hit_pad := player.get_path_hit_pad()
	for m in targets:
		if _is_non_targetable(m):
			continue
		var hit_r := 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		var count := MathUtils.count_path_circle_hits(path, m.global_position, hit_r + hit_pad)
		if count > 0:
			var id: int = m.get_instance_id()
			result[id] = count
	return result


func get_path_preview_total_hits(path: Array, player: BattlePlayer, targets: Array) -> int:
	var preview := get_path_preview_hit_counts(path, player, targets)
	var total := 0
	for id in preview:
		total += int(preview[id])
	return total


static func path_preview_ring_color(hit_count: int) -> Color:
	match clampi(hit_count, 0, 4):
		1:
			return Color(1.0, 0.92, 0.2, 0.9)
		2:
			return Color(1.0, 0.58, 0.1, 0.92)
		3:
			return Color(1.0, 0.32, 0.18, 0.94)
		_:
			return Color(0.95, 0.18, 0.55, 0.95)


func update_path_preview_highlights(path: Array, player: BattlePlayer, targets: Array) -> void:
	var preview := get_path_preview_hit_counts(path, player, targets) if path.size() >= 2 and player != null else {}
	var total_hits := 0
	for id in preview:
		total_hits += int(preview[id])
	var marked_increase := false
	for m in targets:
		if not is_instance_valid(m):
			continue
		if m.get("path_target_hit_count") == null:
			continue
		var count := int(preview.get(m.get_instance_id(), 0))
		if m.path_target_hit_count != count:
			if count > int(m.path_target_hit_count):
				marked_increase = true
			m.path_target_hit_count = count
			m.queue_redraw()
	if marked_increase:
		var battle := get_tree().get_first_node_in_group("battle")
		if battle:
			var combo := clampf(float(maxi(total_hits, 2)), 2.0, 36.0)
			battle.shake_camera(1.15 + (combo - 2.0) * 0.065, 0.055 + (combo - 2.0) * 0.002)


func clear_path_preview_highlights(targets: Array) -> void:
	for m in targets:
		if not is_instance_valid(m) or m.get("path_target_hit_count") == null:
			continue
		if m.path_target_hit_count != 0:
			m.path_target_hit_count = 0
			m.queue_redraw()


func queue_hit(monster: Node, segment_index: int, hit_pos: Vector2) -> void:
	if monster == null or not is_instance_valid(monster):
		return
	pending_hits.append({
		"monster": monster,
		"segment_index": segment_index,
		"pos": hit_pos,
	})


func begin_resolve(player: BattlePlayer) -> void:
	if pending_hits.is_empty():
		_finish_resolve(player)
		return
	resolving = true
	resolve_timer = float(GameConfig.get_tuning("combat_first_hit_delay", 0.04))


func update_resolve(delta: float, player: BattlePlayer) -> void:
	if not resolving:
		return
	resolve_timer -= delta
	if resolve_timer > 0.0:
		return
	if pending_hits.is_empty():
		_finish_resolve(player)
		return
	var hit = pending_hits.pop_front()
	_apply_hit(player, hit)
	resolve_timer = float(GameConfig.get_tuning("combat_hit_interval", 0.012))


func _apply_hit(player: BattlePlayer, hit: Dictionary) -> void:
	var monster = hit.monster
	if monster == null or not is_instance_valid(monster):
		return
	if _is_non_targetable(monster):
		return
	var seg_ang := 0.0
	if player.attack_path.size() >= 2:
		var seg_idx := mini(int(hit.segment_index), player.attack_path.size() - 2)
		var from := player.attack_path[seg_idx]
		var to := player.attack_path[seg_idx + 1]
		seg_ang = (to - from).angle()

	var dash_ang: float = (hit.pos - player.global_position).angle()
	spawn_afterimage(hit.pos, dash_ang)

	var dmg_info: Dictionary = player.get_attack_damage(player.combo_count)
	var result: Dictionary = monster.take_damage(int(dmg_info.amount), player.global_position)
	if bool(result.get("blocked_by_shield", false)):
		spawn_damage_number(hit.pos, 0, false, false, Color("#9fb8d8"))
		return
	var dealt_damage := int(result.get("damage", 0))
	if dealt_damage > 0 and not bool(result.get("started_dying", false)):
		var extra_base := player.get_ability_damage(1.0)
		var extra_damage := LobbyState.roll_weapon_extra_damage(extra_base)
		if extra_damage > 0 and not _is_non_targetable(monster):
			var extra_result: Dictionary = monster.take_damage(extra_damage, player.global_position)
			var actual_extra := int(extra_result.get("damage", 0))
			if actual_extra > 0:
				spawn_damage_number(hit.pos + Vector2(0.0, -10.0), actual_extra, false, false, Color("#ffd27a"))
			if bool(extra_result.get("started_dying", false)):
				result["started_dying"] = true
			result["damage"] = dealt_damage + actual_extra
	var combo_count: float = player.register_combo_hit()
	spawn_damage_number(hit.pos, int(result.get("damage", 0)), bool(dmg_info.is_crit))
	var battle := get_tree().get_first_node_in_group("battle")
	if battle:
		if int(result.get("damage", 0)) > 0:
			var fx_scale := 1.15 if bool(dmg_info.is_crit) else 1.0
			spawn_slash_hit_fx(hit.pos, seg_ang, fx_scale)
		if bool(dmg_info.is_crit):
			battle.shake_camera(6.0 + mini(float(combo_count) * 0.15, 4.0), 0.14)
		else:
			battle.shake_camera(3.0, 0.08)
		AudioManager.play_hit(bool(dmg_info.is_crit))
	player.trigger_combo_abilities(int(combo_count), monster.global_position)

	if battle and battle.abilities:
		battle.abilities.on_combo_hit(combo_count, hit.pos, seg_ang, player)

	if bool(result.get("started_dying", false)):
		var tint := Color.WHITE
		var fx_scale := 1.0
		if monster is BattleMonster:
			var bm := monster as BattleMonster
			tint = bm.color
			fx_scale = clampf(bm.get_hitbox_radius() / 13.0, 0.85, 1.8)
		if battle and battle.particles:
			battle.particles.death_effect(monster.global_position, tint, fx_scale)
		if battle:
			battle.shake_camera(4.5 + fx_scale * 1.5, 0.1)
		EventBus.monster_killed.emit(monster)


func spawn_damage_number(pos: Vector2, damage: int, is_crit: bool, is_heal: bool = false, tint: Variant = null) -> void:
	damage_numbers.append({
		"pos": pos,
		"damage": damage,
		"is_crit": is_crit,
		"is_heal": is_heal,
		"color": tint,
		"life": 0.85,
		"max_life": 0.85,
		"vy": -68.0,
	})


func update_damage_numbers(delta: float) -> void:
	if damage_numbers.is_empty() or delta <= 0.0:
		return
	var i := damage_numbers.size() - 1
	while i >= 0:
		var dn: Dictionary = damage_numbers[i]
		var life := float(dn.get("life", 0.0)) - delta
		if life <= 0.0:
			damage_numbers.remove_at(i)
		else:
			dn["life"] = life
			dn["pos"] = dn.pos + Vector2(0.0, float(dn.get("vy", 0.0)) * delta)
			damage_numbers[i] = dn
		i -= 1


func spawn_slash_hit_fx(pos: Vector2, angle: float, scale_mul: float = 1.0) -> void:
	if _slash_hit_frames == null or _slash_hit_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) <= 0:
		return
	slash_hit_fx.append({
		"pos": pos,
		"angle": angle,
		"anim_t": 0.0,
		"duration": EffectHelperScript.one_shot_anim_duration(_slash_hit_frames),
		"scale": SLASH_HIT_FX_SCALE * scale_mul,
	})


func update_slash_hit_fx(delta: float) -> void:
	if slash_hit_fx.is_empty() or delta <= 0.0:
		return
	for i in range(slash_hit_fx.size() - 1, -1, -1):
		var fx: Dictionary = slash_hit_fx[i]
		fx["anim_t"] = float(fx.anim_t) + delta
		if float(fx.anim_t) >= float(fx.duration):
			slash_hit_fx.remove_at(i)
		else:
			slash_hit_fx[i] = fx


func draw_slash_hit_fx(canvas: Node2D) -> void:
	if _slash_hit_frames == null:
		return
	for fx in slash_hit_fx:
		var tex := EffectHelperScript.animation_frame_texture_once(_slash_hit_frames, float(fx.anim_t))
		if tex == null:
			continue
		var life_t := clampf(float(fx.anim_t) / maxf(0.001, float(fx.duration)), 0.0, 1.0)
		var alpha := 1.0 - life_t * 0.25
		var draw_scale := SLASH_HIT_FX_DRAW_SCALE * float(fx.scale)
		var local_center: Vector2 = Vector2(fx.pos) - canvas.global_position
		SpriteHelper.draw_effect_texture(
			canvas,
			tex,
			local_center,
			float(fx.get("angle", 0.0)),
			Vector2.ONE * draw_scale,
			Color(1.0, 1.0, 1.0, alpha)
		)


func _finish_resolve(player: BattlePlayer) -> void:
	resolving = false
	pending_hits.clear()
	if player:
		player.end_combo_turn()
	resolve_finished.emit()


func try_ice_burst(player: BattlePlayer, center: Vector2) -> void:
	if player == null or not player.ice_ready:
		return
	player.ice_ready = false
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.spawner == null:
		return
	var monsters: Array = battle.spawner.get_active_monsters()
	var dmg := player.get_ability_damage(0.30)
	var radius := 90.0
	for m in monsters:
		if not is_instance_valid(m) or m.get("alive") == false:
			continue
		var hit_r := 13.0
		if m.has_method("get_hitbox_radius"):
			hit_r = m.get_hitbox_radius()
		if center.distance_to(m.global_position) > radius + hit_r:
			continue
		if m is BattleMonster:
			m.freeze(1.8)
			m.vulnerable_mark = true
		if m.has_method("take_damage"):
			var result: Dictionary = m.take_damage(dmg, center)
			spawn_damage_number(m.global_position, int(result.get("damage", 0)), false)
			if bool(result.get("started_dying", false)):
				EventBus.monster_killed.emit(m)
	if battle.hud:
		battle.hud.show_message("冰冻触发!", 1.2)


func _is_non_targetable(monster: Node) -> bool:
	if not is_instance_valid(monster):
		return true
	if monster.has_method("is_combat_targetable"):
		return not monster.is_combat_targetable()
	if monster.get("alive") == false:
		return true
	if monster.get("dying") == true:
		return true
	return false
