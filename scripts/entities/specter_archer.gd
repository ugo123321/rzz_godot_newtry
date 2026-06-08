extends Node2D
class_name SpecterArcher

var battle
var alive := true
var attack := 12
var attack_interval := 1.35
var attack_timer := 0.0
var arrow_speed := 85.0
var hitbox_radius := 12.0
var facing := 1.0
var arrow_tint := Color("#9a5acc")

var sprite: AnimatedSprite2D


func _init() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)


func setup(
	battle_node,
	stage_index: int,
	spawn_pos: Vector2,
	tint: Color,
	alpha: float,
	attack_mult: float = 1.0
) -> void:
	battle = battle_node
	var stats := GameConfig.scaled_monster_stats("ARCHER", stage_index)
	attack = maxi(1, int(round(float(stats.get("attack", 12)) * attack_mult)))
	attack_interval = float(stats.get("attack_interval", 1.35))
	arrow_speed = float(stats.get("arrow_speed", 85.0))
	hitbox_radius = float(stats.get("size", 12))
	global_position = spawn_pos
	attack_timer = attack_interval * MathUtils.rand_range(0.35, 0.85)
	arrow_tint = tint
	_apply_sprite(str(stats.get("character_folder", "Archer")), str(stats.get("sprite_prefix", "Archer")))
	modulate = Color(tint.r, tint.g, tint.b, alpha)


func _apply_sprite(folder: String, prefix: String) -> void:
	sprite.sprite_frames = SpriteHelper.build_character_frames(folder, prefix)
	SpriteHelper.apply_pixel_art(sprite)
	var scale_val := float(GameConfig.get_tuning("monster_sprite_scale", 1.0))
	sprite.scale = Vector2.ONE * SpriteHelper.pixel_scale(scale_val)
	sprite.modulate = Color.WHITE
	if sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		sprite.play(SpriteHelper.ANIM_IDLE)


func is_combat_targetable() -> bool:
	return false


func get_hitbox_radius() -> float:
	return hitbox_radius


func take_damage(_raw_damage: int, _from_pos: Vector2) -> Dictionary:
	return {"damage": 0, "is_crit": false}


func apply_damage(_raw_damage: int, _from_pos: Vector2) -> Dictionary:
	return take_damage(0, _from_pos)


func dismiss() -> void:
	alive = false
	queue_free()


func update_specter(delta: float, player: BattlePlayer) -> void:
	if not alive or player == null or player.hp <= 0:
		return
	var to_player := player.global_position - global_position
	facing = 1.0 if to_player.x >= 0 else -1.0
	sprite.flip_h = facing < 0
	if battle and battle.combat and not battle.combat.should_monsters_attack(player):
		return
	attack_timer -= delta
	if attack_timer > 0.0:
		return
	attack_timer = attack_interval
	_fire_arrow(player)


func _fire_arrow(player: BattlePlayer) -> void:
	if battle == null:
		return
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK):
		sprite.play(SpriteHelper.ANIM_ATTACK)
	battle.spawn_arrow(global_position, player.global_position, attack, arrow_speed, "", arrow_tint)
