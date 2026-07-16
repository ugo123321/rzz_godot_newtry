extends Control
class_name ScrollingBackground

# 主界面背景同款无缝横向卷轴：两个相同贴片左右拼接，每帧整体右移，
# 移出一屏宽度时跳到另一贴片后方。自包含 _process + resized，挂到任意面板当背景即可。
# 用法：场景里加一个 Control 挂本脚本，@export 贴图 + 速度，full_rect 占满。

@export var texture: Texture2D = null
@export var scroll_speed: float = 22.0

var _tiles: Array[TextureRect] = []
var _tile_width := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture == null:
		return
	for i in 2:
		var tile := TextureRect.new()
		tile.name = "ScrollTile" + ("A" if i == 0 else "B")
		tile.texture = texture
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tile)
		_tiles.append(tile)
	if not resized.is_connected(_refresh_layout):
		resized.connect(_refresh_layout)
	_refresh_layout()


func _process(delta: float) -> void:
	if _tiles.size() < 2 or scroll_speed <= 0.0:
		return
	if _tile_width <= 0.0:
		_refresh_layout()
		return
	var dx := scroll_speed * delta
	for tile in _tiles:
		tile.position.x += dx
	for i in 2:
		var tile := _tiles[i]
		if tile.position.x >= _tile_width:
			var other := _tiles[1 - i]
			tile.position.x = other.position.x - _tile_width


func _refresh_layout() -> void:
	if _tiles.size() < 2:
		return
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	_tile_width = s.x
	for tile in _tiles:
		tile.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		tile.size = s
	_tiles[0].position = Vector2.ZERO
	_tiles[1].position = Vector2(_tile_width, 0.0)
