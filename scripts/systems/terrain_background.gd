extends Node2D
class_name TerrainBackground

const TILE_SIZE := 40
const PIXEL := 2

const TYPE_GRASS := "grass"
const TYPE_WATER := "water"
const TYPE_EMPTY := "empty"
const TYPE_DIRT := "dirt"
const TYPE_STONE := "stone"

const TILE_DATA := {
	"grass": {
		"base": Color("#4a8048"),
		"shade": Color("#427640"),
		"highlight": Color("#558e52"),
		"speckle_chance": 0.025,
		"deco_chance": 0.04,
		"deco_kind": "flower",
		"deco_palette": [Color("#f5e060"), Color("#f2a0c8"), Color("#ffffff"), Color("#558e52")],
	},
	"water": {
		"base": Color("#3a6fb8"),
		"shade": Color("#33649e"),
		"highlight": Color("#4f82c4"),
		"speckle_chance": 0.05,
		"deco_chance": 0.025,
		"deco_kind": "ripple",
		"deco_palette": [Color("#a8d0e8"), Color("#ffffff")],
	},
	"empty": {
		"base": Color("#1c1c20"),
		"shade": Color("#16161a"),
		"highlight": Color("#222228"),
		"speckle_chance": 0.02,
		"deco_chance": 0.0,
		"deco_kind": "",
		"deco_palette": [],
	},
	"dirt": {
		"base": Color("#7a5a3a"),
		"shade": Color("#6a4d32"),
		"highlight": Color("#88684a"),
		"speckle_chance": 0.04,
		"deco_chance": 0.03,
		"deco_kind": "pebble",
		"deco_palette": [Color("#3a2618"), Color("#5a3a22")],
	},
	"stone": {
		"base": Color("#7a7a82"),
		"shade": Color("#6e6e76"),
		"highlight": Color("#88888e"),
		"speckle_chance": 0.05,
		"deco_chance": 0.02,
		"deco_kind": "pebble",
		"deco_palette": [Color("#4a4a52"), Color("#aaaab2")],
	},
}

var _texture: ImageTexture
var _world_w := 720
var _world_h := 1280
var _cols := 0
var _rows := 0
var _grid: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup_for_stage(stage_index: int, safe_zone: Dictionary = {}) -> void:
	_world_w = int(GameConfig.get_tuning("logical_width", 720))
	_world_h = int(GameConfig.get_tuning("logical_height", 1280))
	_cols = int(ceil(float(_world_w) / float(TILE_SIZE)))
	_rows = int(ceil(float(_world_h) / float(TILE_SIZE)))
	_build_grid(stage_index, safe_zone)
	_rebake_texture()
	queue_redraw()


func set_tile(col: int, row: int, tile_type: String) -> void:
	if row < 0 or row >= _rows or col < 0 or col >= _cols:
		return
	if not TILE_DATA.has(tile_type):
		push_warning("TerrainBackground: unknown tile type '%s'" % tile_type)
		return
	_grid[row][col] = tile_type
	_rebake_texture()
	queue_redraw()


func get_tile(col: int, row: int) -> String:
	if row < 0 or row >= _rows or col < 0 or col >= _cols:
		return ""
	return String(_grid[row][col])


func has_grass_tiles() -> bool:
	for r in range(_rows):
		for c in range(_cols):
			if _grid[r][c] == TYPE_GRASS:
				return true
	return false


# Override hook: stages can return any tile type key for a given cell. Default = grass everywhere.
func _pick_tile_type_for(_stage_index: int, _col: int, _row: int) -> String:
	return TYPE_GRASS


func _build_grid(stage_index: int, _safe_zone: Dictionary) -> void:
	_grid.resize(_rows)
	for r in range(_rows):
		var row: Array = []
		row.resize(_cols)
		for c in range(_cols):
			row[c] = _pick_tile_type_for(stage_index, c, r)
		_grid[r] = row


func _rebake_texture() -> void:
	var img := Image.create(_world_w, _world_h, false, Image.FORMAT_RGBA8)
	for r in range(_rows):
		for c in range(_cols):
			_paint_tile(img, c, r, String(_grid[r][c]))
	_texture = ImageTexture.create_from_image(img)


func _paint_tile(img: Image, col: int, row: int, tile_type: String) -> void:
	var data: Dictionary = TILE_DATA.get(tile_type, TILE_DATA[TYPE_GRASS])
	var ox := col * TILE_SIZE
	var oy := row * TILE_SIZE
	var w := mini(TILE_SIZE, _world_w - ox)
	var h := mini(TILE_SIZE, _world_h - oy)
	if w <= 0 or h <= 0:
		return
	img.fill_rect(Rect2i(ox, oy, w, h), Color(data.base))
	var seed_v: int = (col * 73856093) ^ (row * 19349663) ^ hash(tile_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var blocks_x := int(float(w) / float(PIXEL))
	var blocks_y := int(float(h) / float(PIXEL))
	var speckle_chance := float(data.speckle_chance)
	for by in range(blocks_y):
		for bx in range(blocks_x):
			if rng.randf() < speckle_chance:
				var sp_color: Color = data.shade if rng.randf() < 0.6 else data.highlight
				img.fill_rect(Rect2i(ox + bx * PIXEL, oy + by * PIXEL, PIXEL, PIXEL), sp_color)
	if rng.randf() < float(data.deco_chance) and (data.deco_palette as Array).size() > 0:
		var max_bx := maxi(2, blocks_x - 4)
		var max_by := maxi(2, blocks_y - 4)
		var dx := rng.randi_range(1, max_bx)
		var dy := rng.randi_range(1, max_by)
		_paint_decoration(img, ox + dx * PIXEL, oy + dy * PIXEL, data, rng)


func _paint_decoration(img: Image, x: int, y: int, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind := String(data.deco_kind)
	var palette: Array = data.deco_palette
	if palette.is_empty():
		return
	match kind:
		"flower":
			var petal_pool_size := maxi(1, palette.size() - 1)
			var petal_col: Color = palette[rng.randi() % petal_pool_size]
			var center_col: Color = palette[palette.size() - 1]
			img.fill_rect(Rect2i(x + PIXEL, y, PIXEL, PIXEL), petal_col)
			img.fill_rect(Rect2i(x, y + PIXEL, PIXEL, PIXEL), petal_col)
			img.fill_rect(Rect2i(x + PIXEL * 2, y + PIXEL, PIXEL, PIXEL), petal_col)
			img.fill_rect(Rect2i(x + PIXEL, y + PIXEL * 2, PIXEL, PIXEL), petal_col)
			img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL, PIXEL), center_col)
		"pebble":
			var pcol: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL * 2, PIXEL * 2), pcol)
		"ripple":
			var rcol: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL * 3, PIXEL), rcol)
		_:
			pass


func _draw() -> void:
	if _texture:
		draw_texture(_texture, Vector2.ZERO)
