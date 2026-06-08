extends Node

var enabled := false
var volume := 0.7


func set_enabled(value: bool) -> void:
	enabled = value


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)


func play_slash() -> void:
	if not enabled:
		return


func play_hit(_is_crit: bool = false) -> void:
	if not enabled:
		return


func play_monster_death() -> void:
	if not enabled:
		return


func play_level_up() -> void:
	if not enabled:
		return


func play_player_hurt() -> void:
	if not enabled:
		return


func play_orb_pickup() -> void:
	if not enabled:
		return
