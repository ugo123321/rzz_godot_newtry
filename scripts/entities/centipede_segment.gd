extends Node2D
class_name CentipedeSegment

var boss_ref
var segment_index := 0
var alive := true
var vulnerable_mark := false
var path_target_hit_count := 0


func get_hitbox_radius() -> float:
	if boss_ref:
		return boss_ref.segment_radius
	return 13.0


func is_combat_targetable() -> bool:
	return alive and boss_ref != null and boss_ref.phase == CentipedeBoss.Phase.ACTIVE and not boss_ref.defeated


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	if boss_ref:
		return boss_ref.apply_damage(raw_damage, self, from_pos)
	return {"damage": 0, "is_crit": false}


func apply_burn_dot(_duration: float, _dps: int) -> void:
	pass


func die() -> void:
	pass


func update_ai(_delta: float, _player: BattlePlayer, _battle: Node) -> void:
	pass


func _draw() -> void:
	if not alive or boss_ref == null:
		return
	var alpha: float = boss_ref.get_body_draw_alpha()
	if alpha <= 0.0:
		return
	var r := get_hitbox_radius()
	var w := r * 2.1
	var h := r * 1.55
	var frozen: bool = boss_ref.is_segment_frozen(self)
	var body := Color("#5a88b8") if frozen else Color("#4a6858")
	var edge := Color("#2a3830") if not frozen else Color("#88c8f0")
	if path_target_hit_count > 0:
		var ring := CombatDirector.path_preview_ring_color(path_target_hit_count)
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 24, Color(ring.r, ring.g, ring.b, ring.a * alpha), 3.0)
	draw_set_transform(Vector2.ZERO, boss_ref.get_segment_angle(segment_index), Vector2.ONE)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(edge, alpha))
	draw_rect(Rect2(-w * 0.5 + 2, -h * 0.5 + 2, w - 4, h - 5), Color(body, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
