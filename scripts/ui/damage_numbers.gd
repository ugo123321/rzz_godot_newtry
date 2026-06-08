extends Node2D
class_name DamageNumbersOverlay

const FONT_SIZE := 19
const CRIT_FONT_SIZE := 28

var combat: CombatDirector


func setup(combat_director: CombatDirector) -> void:
	combat = combat_director


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if combat == null:
		return
	var battle := get_tree().get_first_node_in_group("battle") as BattleController
	if battle != null and battle.state in [GameState.FAIL_DEATH, GameState.STAGE_FAIL]:
		return
	var font := PixelUiHelper.get_ui_font()
	for dn in combat.damage_numbers:
		var t := clampf(float(dn.life) / float(dn.max_life), 0.0, 1.0)
		var pos: Vector2 = dn.pos - global_position
		var is_crit: bool = bool(dn.is_crit)
		var is_heal: bool = bool(dn.get("is_heal", false))
		var tint = dn.get("color")
		var color := Color.WHITE
		if tint is Color:
			color = tint as Color
			color.a = t
		elif is_heal:
			color = Color("#68d878", t)
		elif is_crit:
			color = Color("#ff4040", t)
		else:
			color = Color(1.0, 1.0, 1.0, t)
		var font_size := _scaled_font(CRIT_FONT_SIZE if is_crit else FONT_SIZE)
		var text := str(dn.get("damage", 0))
		if is_heal:
			text = "+%s" % text
		var draw_pos := _get_centered_draw_pos(font, pos, text, font_size)
		_draw_outlined_string(font, draw_pos, text, font_size, color)


func _scaled_font(v: float) -> int:
	return maxi(8, int(round(GameConfig.scale_ui(v))))


func _get_centered_draw_pos(font: Font, center: Vector2, text: String, font_size: int) -> Vector2:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(
		roundi(center.x - text_size.x * 0.5),
		roundi(center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	)


func _draw_outlined_string(font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var outline := Color(0, 0, 0, color.a)
	for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
