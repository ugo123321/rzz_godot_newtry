extends Node2D
class_name EnemyArrow

enum Pattern { SINGLE, CROSS, BOUNCE }

const DEFAULT_ARROW_TEXTURES: Array[String] = [
	"res://assets/Characters/Characters(100x100)/Archer/Arrow(projectile)/Arrow01(32x32).png",
	"res://assets/Characters/Characters(100x100)/Archer/Arrow(projectile)/Arrow02(32x32).png",
	"res://assets/Characters/Characters(100x100)/Archer/Arrow(projectile)/Arrow03(32x32).png",
]
const HIT_RADIUS := 6.0
const DRAW_SCALE := 1.75
const VERTICAL_FX_SCALE_Y := 1
const SPAWN_OFFSET := 10.0

var velocity := Vector2.ZERO
var damage := 10
var pattern := Pattern.SINGLE
var bounces_left := 0
var _battle: BattleController
var _player: BattlePlayer
var _alive := true
var _effect_key := ""
var _tint := Color.WHITE
var _static_sprite: Sprite2D
var _animated_sprite: AnimatedSprite2D


static func spawn(
	battle: BattleController,
	from_pos: Vector2,
	to_pos: Vector2,
	dmg: int,
	speed: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	var dir := _aim_dir(from_pos, to_pos)
	_create(
		battle,
		from_pos,
		dir,
		dmg,
		speed,
		Pattern.SINGLE,
		0,
		effect_key,
		tint
	)


static func spawn_spread(
	battle: BattleController,
	from_pos: Vector2,
	to_pos: Vector2,
	dmg: int,
	speed: float,
	count: int,
	spread_deg: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	var base_dir := _aim_dir(from_pos, to_pos)
	var shots := maxi(1, count)
	if shots == 1:
		_create(battle, from_pos, base_dir, dmg, speed, Pattern.SINGLE, 0, effect_key, tint)
		return
	var half := spread_deg * 0.5
	var step := spread_deg / float(shots - 1)
	for i in range(shots):
		var offset := deg_to_rad(-half + step * float(i))
		_create(
			battle,
			from_pos,
			base_dir.rotated(offset),
			dmg,
			speed,
			Pattern.SINGLE,
			0,
			effect_key,
			tint
		)


static func spawn_cross(
	battle: BattleController,
	from_pos: Vector2,
	dmg: int,
	speed: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_create(battle, from_pos, dir, dmg, speed, Pattern.CROSS, 0, effect_key, tint)


static func spawn_bounce(
	battle: BattleController,
	from_pos: Vector2,
	to_pos: Vector2,
	dmg: int,
	speed: float,
	bounces: int,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	var dir := _aim_dir(from_pos, to_pos)
	_create(
		battle,
		from_pos,
		dir,
		dmg,
		speed,
		Pattern.BOUNCE,
		maxi(0, bounces),
		effect_key,
		tint
	)


static func _aim_dir(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	var dir := to_pos - from_pos
	if dir.length_squared() < 1.0:
		return Vector2.RIGHT
	return dir.normalized()


static func _create(
	battle: BattleController,
	from_pos: Vector2,
	dir: Vector2,
	dmg: int,
	speed: float,
	arrow_pattern: Pattern,
	bounces: int,
	effect_key: String,
	tint: Color
) -> void:
	if battle == null or battle.player == null:
		return
	var arrow := EnemyArrow.new()
	arrow._battle = battle
	arrow._player = battle.player
	arrow.damage = maxi(1, dmg)
	arrow.pattern = arrow_pattern
	arrow.bounces_left = bounces
	arrow._effect_key = effect_key
	arrow._tint = tint
	arrow.velocity = dir * maxf(40.0, speed)
	arrow.global_position = from_pos + dir * GameConfig.scale_world(SPAWN_OFFSET)
	if arrow._uses_vertical_fx() and not effect_key.is_empty():
		arrow.rotation = 0.0
	else:
		arrow.rotation = dir.angle()
	battle.projectiles.add_child(arrow)


func is_alive() -> bool:
	return _alive


func update_arrow(delta: float) -> void:
	if not _alive:
		return
	if delta <= 0.0:
		return
	if _battle == null or _player == null or not is_instance_valid(_player):
		queue_free()
		return
	if _battle.state != GameState.PLAYING:
		queue_free()
		return
	global_position += velocity * delta
	if _try_hit_player():
		return
	if _try_bounce():
		return
	if not _battle.is_in_bounds(global_position):
		queue_free()


func destroy_blocked(from: Vector2, to: Vector2) -> void:
	if not _alive:
		return
	_alive = false
	if _battle and _battle.particles:
		_battle.particles.hit_spark(global_position, false)
		_battle.particles.slash_trail(global_position, (to - from).angle())
	queue_free()


func _uses_vertical_fx() -> bool:
	return pattern == Pattern.CROSS or _effect_key == "enemy_cross_magic"


func _vertical_fx_scale() -> Vector2:
	var base := SpriteHelper.pixel_scale(DRAW_SCALE * GameConfig.get_world_scale())
	var scale := Vector2(base, base * VERTICAL_FX_SCALE_Y)
	if velocity.y > 0.0:
		scale.y = -absf(scale.y)
	return scale


func _ready() -> void:
	if not _effect_key.is_empty():
		var frames := EffectHelper.build_effect_frames(_effect_key)
		if frames != null and frames.get_frame_count(EffectHelper.ANIM_PREVIEW) > 0:
			_animated_sprite = AnimatedSprite2D.new()
			_animated_sprite.sprite_frames = frames
			_animated_sprite.animation = EffectHelper.ANIM_PREVIEW
			_animated_sprite.play(EffectHelper.ANIM_PREVIEW)
			_animated_sprite.centered = true
			_animated_sprite.modulate = _tint
			_animated_sprite.scale = _vertical_fx_scale() if _uses_vertical_fx() else Vector2.ONE * SpriteHelper.pixel_scale(DRAW_SCALE * GameConfig.get_world_scale())
			SpriteHelper.apply_pixel_art(_animated_sprite)
			add_child(_animated_sprite)
			return
	_static_sprite = Sprite2D.new()
	var tex_path: String = DEFAULT_ARROW_TEXTURES[randi() % DEFAULT_ARROW_TEXTURES.size()]
	if ResourceLoader.exists(tex_path):
		_static_sprite.texture = load(tex_path)
	else:
		_static_sprite.texture = load(DEFAULT_ARROW_TEXTURES[1])
	_static_sprite.centered = true
	_static_sprite.modulate = _tint
	_static_sprite.scale = _vertical_fx_scale() if _uses_vertical_fx() else Vector2.ONE * SpriteHelper.pixel_scale(DRAW_SCALE * GameConfig.get_world_scale())
	SpriteHelper.apply_pixel_art(_static_sprite)
	add_child(_static_sprite)


func _try_bounce() -> bool:
	if pattern != Pattern.BOUNCE or bounces_left <= 0:
		return false
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var pos := global_position
	var bounced := false
	if pos.x <= 0.0:
		velocity.x = absf(velocity.x)
		global_position.x = 1.0
		bounced = true
	elif pos.x >= w:
		velocity.x = -absf(velocity.x)
		global_position.x = w - 1.0
		bounced = true
	if pos.y <= 0.0:
		velocity.y = absf(velocity.y)
		global_position.y = 1.0
		bounced = true
	elif pos.y >= h:
		velocity.y = -absf(velocity.y)
		global_position.y = h - 1.0
		bounced = true
	if not bounced:
		return false
	bounces_left -= 1
	rotation = velocity.angle()
	if _battle and _battle.particles:
		_battle.particles.hit_spark(global_position, false)
	return false


func _try_hit_player() -> bool:
	if _player.hp <= 0:
		return false
	if _player.state == BattlePlayer.State.BULLET_TIME:
		return false
	if _player.is_attack_invincible():
		return false
	var player_r := _player.get_effective_radius() + 2.0
	if global_position.distance_to(_player.global_position) > GameConfig.scale_world(HIT_RADIUS) + player_r:
		return false
	_alive = false
	var dealt := _player.take_damage(damage)
	if dealt > 0:
		if _battle.combat:
			_battle.combat.spawn_damage_number(
				_player.global_position + Vector2(0.0, -_player.get_effective_radius() - 8.0),
				dealt,
				false,
				false,
				Color("#e05840")
			)
		if _battle.particles:
			_battle.particles.hit_spark(_player.global_position, false)
	queue_free()
	return true
