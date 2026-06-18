extends Node2D
class_name TerrainBackground


func setup_for_stage(_stage_index: int, _safe_zone: Dictionary = {}) -> void:
	_clear_children()


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func has_grass_tiles() -> bool:
	return false
