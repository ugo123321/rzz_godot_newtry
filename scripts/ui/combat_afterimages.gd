extends Node2D
class_name CombatAfterimagesOverlay

var combat: CombatDirector
var player: BattlePlayer
var _had_afterimages := false


func setup(combat_director: CombatDirector, battle_player: BattlePlayer) -> void:
	combat = combat_director
	player = battle_player
	z_index = 45


func _process(_delta: float) -> void:
	if combat == null:
		return
	var active := not combat.afterimages.is_empty()
	# 残影列表变空后仍需重绘一次，否则上一帧会永久留在画面上
	if active or _had_afterimages:
		queue_redraw()
	_had_afterimages = active


func _draw() -> void:
	if combat == null or player == null or combat.afterimages.is_empty():
		return
	var anim_sprite := player.get_sprite_node()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	var anim_name := SpriteHelper.ANIM_ATTACK
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		anim_name = SpriteHelper.ANIM_IDLE
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	var tex: Texture2D = anim_sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if tex == null:
		return
	var draw_scale := anim_sprite.scale * 0.92
	var half := tex.get_size() * 0.5
	for img in combat.afterimages:
		var t := clampf(float(img.life) / float(img.max_life), 0.0, 1.0)
		var alpha := t * 0.55
		var pos: Vector2 = img.pos - global_position
		draw_set_transform(pos, float(img.angle) * 0.15, draw_scale)
		draw_texture(tex, -half, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
