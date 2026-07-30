extends Node2D
class_name GroundEffectManager

const EffectHelperScript = preload("res://scripts/utils/effect_helper.gd")

var battle
var effects: Array = []
var _fire_frames: SpriteFrames


func setup(battle_node) -> void:
	battle = battle_node
	_fire_frames = EffectHelperScript.build_fire_pillar_frames()


func reset() -> void:
	effects.clear()
	queue_redraw()


func spawn_fire_pillar(pos: Vector2, damage: int) -> void:
	effects.append({
		"type": "fire_pillar",
		"pos": pos,
		"radius": GameConfig.scale_world(float(GameConfig.get_tuning("fire_pillar_radius", 60))),
		"damage": damage,
		"phase": "warning",
		"timer": float(GameConfig.get_tuning("fire_pillar_warning_time", 1.1)),
		"flash_t": 0.0,
		"hit": false,
	})
	queue_redraw()


# 跳跃怪 JUMPER 落地砸击：脚下红色预警（复用 _draw_warning，同火法师观感）→ 撞击伤害 + 灰尘。
# warning_time 由调用方决定（JUMPER 用 2s），半径/伤害也由调用方传入。
func spawn_smash(pos: Vector2, damage: int, radius: float, warning_time: float) -> void:
	effects.append({
		"type": "smash",
		"pos": pos,
		"radius": GameConfig.scale_world(radius),
		"damage": damage,
		"phase": "warning",
		"timer": maxf(0.1, warning_time),
		"flash_t": 0.0,
		"hit": false,
	})
	queue_redraw()


# TELEPORTER 瞬移怪：在将出现点画紫色脉动预警圈（warning 期结束直接 dead，无 active/伤害）。
# 独立 ground_effect 节点绘制，不受 monster 的 modulate.a=0 隐形影响。
func spawn_teleport_marker(pos: Vector2, radius: float, duration: float) -> void:
	effects.append({
		"type": "teleport_marker",
		"pos": pos,
		"radius": GameConfig.scale_world(radius),
		"phase": "warning",
		"timer": maxf(0.1, duration),
		"flash_t": 0.0,
	})
	queue_redraw()


func update_effects(delta: float, player: BattlePlayer) -> void:
	if effects.is_empty():
		return
	var any := false
	for e in effects:
		e.flash_t = float(e.flash_t) + delta
		e.timer = float(e.timer) - delta
		match str(e.phase):
			"warning":
				if float(e.timer) <= 0.0:
					if str(e.type) == "teleport_marker":
						e.phase = "dead"
					else:
						e.phase = "active"
						if str(e.type) == "smash":
							e.timer = float(GameConfig.get_tuning("smash_active_time", 0.35))
						else:
							e.timer = float(GameConfig.get_tuning("fire_pillar_active_time", 0.5))
						_damage_player(e, player)
			"active":
				if float(e.timer) <= 0.0:
					e.phase = "fade"
					if str(e.type) == "smash":
						e.timer = float(GameConfig.get_tuning("smash_fade_time", 0.25))
					else:
						e.timer = float(GameConfig.get_tuning("fire_pillar_fade_time", 0.3))
			"fade":
				if float(e.timer) <= 0.0:
					e.phase = "dead"
		if str(e.phase) != "dead":
			any = true
	effects = effects.filter(func(item): return str(item.phase) != "dead")
	if any:
		queue_redraw()


func _damage_player(e: Dictionary, player: BattlePlayer) -> void:
	if bool(e.hit) or player == null or player.hp <= 0:
		return
	if player.state == BattlePlayer.State.BULLET_TIME or player.is_attack_invincible():
		return
	var r: float = float(e.radius)
	if player.global_position.distance_to(e.pos) > r + player.get_effective_radius() + 2.0:
		return
	e.hit = true
	var dmg := player.take_damage(int(e.damage))
	if dmg <= 0 or battle == null:
		return
	if battle.combat:
		var num_color := Color("#ff7040") if str(e.type) != "smash" else Color("#ffd060")
		battle.combat.spawn_damage_number(
			player.global_position + Vector2(0, -player.get_effective_radius() - 8),
			dmg,
			false,
			false,
			num_color
		)
	if battle.particles:
		battle.particles.hit_spark(player.global_position, false)
		if str(e.type) == "smash":
			# 砸击：灰褐色灰尘溅射 + 更强屏震
			for i in range(16):
				var col := Color("#8a7a60") if i % 2 == 0 else Color("#b09878")
				battle.particles.emit_particle(
					float(e.pos.x) + randf_range(-r * 0.4, r * 0.4),
					float(e.pos.y) + randf_range(-r * 0.4, r * 0.4),
					randf_range(-60.0, 60.0),
					randf_range(-130.0, -30.0),
					randf_range(0.25, 0.5),
					randf_range(3.0, 6.0),
					col,
					90.0,
					true,
					false
				)
			battle.shake_camera(7.0, 0.2)
		else:
			for i in range(14):
				var col := Color("#ff6020") if i % 2 == 0 else Color("#ffcc50")
				battle.particles.emit_particle(
					float(e.pos.x) + randf_range(-r * 0.45, r * 0.45),
					float(e.pos.y) + randf_range(-r * 0.45, r * 0.45),
					randf_range(-40.0, 40.0),
					randf_range(-80.0, -20.0),
					randf_range(0.25, 0.5),
					randf_range(3.0, 6.0),
					col,
					80.0,
					true,
					false
				)
			battle.shake_camera(4.5, 0.12)


func _draw() -> void:
	var offset := -global_position
	for e in effects:
		var pos: Vector2 = e.pos + offset
		var r: float = float(e.radius)
		match str(e.phase):
			"warning":
				if str(e.type) == "teleport_marker":
					_draw_teleport_marker(pos, r, float(e.flash_t))
				else:
					_draw_warning(pos, r, float(e.flash_t))
			"active":
				if str(e.type) == "smash":
					_draw_smash(pos, r, float(e.flash_t), 1.0)
				else:
					_draw_fire_pillar(pos, r, float(e.flash_t), 1.0)
			"fade":
				if str(e.type) == "smash":
					var smash_fade := maxf(0.001, float(GameConfig.get_tuning("smash_fade_time", 0.25)))
					_draw_smash(pos, r, float(e.flash_t), clampf(float(e.timer) / smash_fade, 0.0, 1.0))
				else:
					var fade_dur := maxf(0.001, float(GameConfig.get_tuning("fire_pillar_fade_time", 0.3)))
					_draw_fire_pillar(pos, r, float(e.flash_t), clampf(float(e.timer) / fade_dur, 0.0, 1.0))


func _draw_warning(pos: Vector2, r: float, flash_t: float) -> void:
	var pulse := sin(flash_t * 14.0) * 0.5 + 0.5
	var flash := int(floor(flash_t * 10.0)) % 2 == 0
	var fill_a := 0.1 + pulse * 0.16
	var stroke_a := 0.9 if flash else 0.42
	draw_circle(pos, r, Color(1.0, 0.14, 0.11, fill_a))
	draw_arc(pos, r, 0.0, TAU, 48, Color(1.0, 0.18 if flash else 0.37, 0.14, stroke_a), 3.0 if flash else 2.0)
	draw_arc(pos, r * 0.7, 0.0, TAU, 36, Color(1.0, 0.43, 0.27, 0.38 + pulse * 0.28), 1.0)


# TELEPORTER 紫色脉动预警圈：fill + 外环 + 内环（同 _draw_warning 结构，换色）。
func _draw_teleport_marker(pos: Vector2, r: float, flash_t: float) -> void:
	var pulse := sin(flash_t * 14.0) * 0.5 + 0.5
	var flash := int(floor(flash_t * 10.0)) % 2 == 0
	var fill_a := 0.10 + pulse * 0.16
	var stroke_a := 0.85 if flash else 0.42
	draw_circle(pos, r, Color(0.60, 0.35, 0.82, fill_a))
	draw_arc(pos, r, 0.0, TAU, 48, Color(0.78, 0.55, 0.95, stroke_a), 3.0 if flash else 2.0)
	draw_arc(pos, r * 0.7, 0.0, TAU, 36, Color(0.85, 0.65, 1.0, 0.38 + pulse * 0.28), 1.0)


func _draw_fire_pillar(pos: Vector2, r: float, flash_t: float, alpha_mul: float) -> void:
	draw_circle(pos, r, Color(0.19, 0.07, 0.03, 0.6 * alpha_mul))
	if _fire_frames != null and _fire_frames.get_frame_count(EffectHelperScript.ANIM_PREVIEW) > 0:
		var tex := EffectHelperScript.animation_frame_texture(_fire_frames, flash_t)
		if tex != null:
			var size := tex.get_size()
			var scale := (r * 2.2) / maxf(size.x, size.y)
			var draw_size := size * scale
			SpriteHelper.draw_effect_texture_rect(
				self,
				tex,
				Rect2(pos - draw_size * 0.5 + Vector2(0, -r * 0.35), draw_size),
				Color(1, 1, 1, alpha_mul)
			)
	else:
		var col_h := r * 1.55
		for i in range(8):
			var ang := float(i) / 8.0 * TAU + flash_t * 4.2
			var spread := r * (0.28 + float(i % 3) * 0.14)
			var fx := pos.x + cos(ang) * spread
			var fy := pos.y + sin(ang) * spread * 0.4 - col_h * 0.35
			var fh := col_h * (0.55 + float(i % 4) * 0.12)
			var fw := 3.0 + float(i % 3) * 2.0
			var colors := [Color("#ff5018"), Color("#ffb038"), Color("#ff2810"), Color("#ff9048")]
			draw_rect(Rect2(fx - fw * 0.5, fy - fh, fw, fh), Color(colors[i % 4], alpha_mul))
	draw_arc(pos, r, 0.0, TAU, 48, Color(1.0, 0.75, 0.27, 0.65 * alpha_mul), 2.0)


# 跳跃怪落地砸击视觉：暗色撞击坑 + 灰尘溅射环（位置由 flash_t 确定性驱动，稳定不抖）。
func _draw_smash(pos: Vector2, r: float, flash_t: float, alpha_mul: float) -> void:
	draw_circle(pos, r, Color(0.18, 0.14, 0.12, 0.55 * alpha_mul))
	draw_arc(pos, r, 0.0, TAU, 36, Color(0.5, 0.4, 0.32, 0.7 * alpha_mul), 2.5)
	# 灰尘溅射点
	for i in range(10):
		var ang := float(i) / 10.0 * TAU + flash_t * 3.0
		var dr := r * (0.5 + 0.4 * sin(float(i) * 1.7 + flash_t * 5.0))
		var dp := pos + Vector2(cos(ang), sin(ang)) * dr
		var cr := 2.5 + 1.5 * sin(float(i) + flash_t * 8.0)
		draw_circle(dp, cr, Color(0.6, 0.5, 0.42, 0.6 * alpha_mul))
