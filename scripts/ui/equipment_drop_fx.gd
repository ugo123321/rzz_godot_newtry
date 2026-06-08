extends Node2D
class_name EquipmentDropFxOverlay

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const BOB_DURATION := 1.0
const FADE_DURATION := 0.45
const TOTAL_LIFE := BOB_DURATION + FADE_DURATION
const BOB_AMPLITUDE := 7.0
const ICON_SIZE := 28.0
const PANEL_PADDING := 3.0

var _drops: Array[Dictionary] = []
var _icon_cache: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 8


func clear() -> void:
	_drops.clear()
	queue_redraw()


func spawn(item: Dictionary, world_pos: Vector2) -> void:
	if item.is_empty():
		return
	var icon := _get_equipment_icon(item)
	if icon == null:
		return
	_drops.append({
		"pos": world_pos + Vector2(0.0, -10.0),
		"icon": icon,
		"quality": int(item.get("quality", LobbyState.QUALITY_COMMON)),
		"age": 0.0,
	})


func _process(delta: float) -> void:
	if _drops.is_empty():
		return
	_update_drops(delta)
	queue_redraw()


func _update_drops(delta: float) -> void:
	for i in range(_drops.size() - 1, -1, -1):
		var drop := _drops[i]
		var age := float(drop.get("age", 0.0)) + delta
		if age >= TOTAL_LIFE:
			_drops.remove_at(i)
		else:
			drop["age"] = age
			_drops[i] = drop


func _draw() -> void:
	for drop in _drops:
		var age := float(drop.get("age", 0.0))
		var pos: Vector2 = drop.get("pos", Vector2.ZERO)

		var bob_offset := 0.0
		if age < BOB_DURATION:
			var t := age / BOB_DURATION
			bob_offset = sin(t * TAU * 2.0) * BOB_AMPLITUDE

		var alpha := 1.0
		if age > BOB_DURATION:
			alpha = 1.0 - clampf((age - BOB_DURATION) / FADE_DURATION, 0.0, 1.0)

		var draw_pos := pos + Vector2(0.0, bob_offset)
		var panel_size := ICON_SIZE + PANEL_PADDING * 2.0
		var half := panel_size * 0.5
		var rect := Rect2(draw_pos.x - half, draw_pos.y - half, panel_size, panel_size)

		var fill := Color(0.08, 0.08, 0.12, 0.78 * alpha)
		var quality := int(drop.get("quality", LobbyState.QUALITY_COMMON))
		var border := LobbyState.get_quality_color(quality)
		border.a = alpha
		PixelUi.draw_pixel_panel(self, rect, fill, border, 2)

		var icon := drop.get("icon") as Texture2D
		if icon != null:
			var icon_rect := Rect2(
				draw_pos.x - ICON_SIZE * 0.5,
				draw_pos.y - ICON_SIZE * 0.5,
				ICON_SIZE,
				ICON_SIZE
			)
			draw_texture_rect(icon, icon_rect, false, Color(1.0, 1.0, 1.0, alpha))


func _get_equipment_icon(item: Dictionary) -> Texture2D:
	var path := LobbyState.get_item_icon_path(item)
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_icon_cache[path] = tex
	return tex
