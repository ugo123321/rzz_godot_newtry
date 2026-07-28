extends Node2D
class_name TerrainBackground

const TILE_SIZE := 40
const PIXEL := 2

# 石地板美术素材（40×40，与 TILE_SIZE 对齐）：_paint_tile 直接 blit，不再过程化绘制。
const STONE_FLOOR_TEX := preload("res://assets/ui/terrains/stone_floor.png")

# 水簇生成参数（第 2 关起 stage_index >= 1 才启用）
const WATER_TILES_PER_CLUSTER_BASE := 85    # 单簇基础约 55 格（之前 35 偏稀疏）
const WATER_CLUSTER_MIN_LEN := 6             # 河流最短 6 格
const WATER_PROB_CLUSTERS := [0.25, 0.45, 0.20, 0.08, 0.02]  # 0/1/2/3/4 簇
const WATER_PROB_RIVER := 0.6                # 河流 vs 水池
const WATER_PROB_BIG_RIVER := 0.15           # 河流长度 ×1.6
const WATER_PROB_BIG_POND := 0.12            # 水池放大到 8×8
const WATER_SAFE_PAD := 18.0                 # 安全区外缘缓冲（额外避让玩家出生点）

const TYPE_GRASS := "grass"
const TYPE_WATER := "water"
const TYPE_EMPTY := "empty"
const TYPE_DIRT := "dirt"
const TYPE_STONE := "stone"
const TYPE_DEMON_GROUND := "demon_ground"
const TYPE_ANGEL_GROUND := "angel_ground"
const TYPE_FORGE_GROUND := "forge_ground"
const TYPE_PARADE_GROUND := "parade_ground"
# 章节地图演进：草地→土路→乡村→石板路→城镇→城堡→王宫（每 4 关一段）
const TYPE_VILLAGE := "village"
const TYPE_TOWN := "town"
const TYPE_CASTLE := "castle"
const TYPE_PALACE := "palace"
const TYPE_PALACE_CORRIDOR := "palace_corridor"

# 局内特殊地块（与水地块同 40px 尺寸；由 set_tile 写入 grid 后过程化烘焙）
const TYPE_PIT := "pit"                  # 深坑：只阻挡移动 + 画线（玩家/怪不能走过/斩过，但子弹飞过、视线穿过）
const TYPE_STONE_FLOOR := "stone_floor"  # 石地板：可通行，但怪物/树/草不在其上生成
const TYPE_BLOCKING_STONE := "blocking_stone"  # 阻挡石块：阻挡移动 + 子弹 + 画线

# 阻挡移动/画线的地块类型集合（water 不在内 —— water 走 path_input 的额外 ki 消耗逻辑）
# 注意：深坑在这里 → 玩家/怪不能走过/斩过深坑；但深坑不在 BULLET_BLOCKING_TILE_TYPES → 子弹可飞过、视线可穿过
const BLOCKING_TILE_TYPES := [TYPE_PIT, TYPE_BLOCKING_STONE]
# 只阻挡子弹（不含深坑：深坑是地面上的洞，子弹从上方飞过；阻挡石是实体石块才挡子弹）
const BULLET_BLOCKING_TILE_TYPES := [TYPE_BLOCKING_STONE]
# 怪物/树/草生成时需避让的地块类型集合（含水 + 阻挡 + 石地板）
const SPAWN_AVOID_TILE_TYPES := [TYPE_WATER, TYPE_PIT, TYPE_BLOCKING_STONE, TYPE_STONE_FLOOR]

# 段索引 → 地面 tile 类型：每 4 关一段（打造/主题/boss 关会 override）
# 段 7 是 boss 前一关（idx=28）的专用火把长廊过渡地面
const SEGMENT_TERRAIN_MAP := {
	0: TYPE_GRASS,             # 关 1-4：草地荒野
	1: TYPE_DIRT,              # 关 5-8：土路
	2: TYPE_VILLAGE,           # 关 9-12：乡村
	3: TYPE_STONE,             # 关 13-16：石板路
	4: TYPE_TOWN,              # 关 17-20：城镇
	5: TYPE_CASTLE,            # 关 21-24：城堡
	6: TYPE_PALACE,            # 关 25-28 + 关 30：王宫
	7: TYPE_PALACE_CORRIDOR,   # 关 29：火把长廊（boss 前奏）
}

# 主题印记参数：在地形烘焙的最末段把 9×9 的 grid（每 cell 8px = 72×72 像素）画在视口中心
const SIGIL_PIXEL := 8
const SIGIL_GRID_SIZE := 9

# Demon 印记：粗略的恶魔头/牛角骷髅图案
# 0=空，1=最深阴影，2=深红，3=主红，4=亮红/橙，5=高光金/眼睛
const DEMON_SIGIL_GRID := [
	[0, 1, 0, 0, 0, 0, 0, 1, 0],
	[1, 2, 1, 0, 0, 0, 1, 2, 1],
	[1, 2, 2, 1, 0, 1, 2, 2, 1],
	[0, 1, 2, 2, 2, 2, 2, 1, 0],
	[0, 0, 1, 5, 2, 5, 1, 0, 0],
	[0, 0, 1, 2, 3, 2, 1, 0, 0],
	[0, 0, 1, 2, 4, 2, 1, 0, 0],
	[0, 0, 0, 1, 4, 1, 0, 0, 0],
	[0, 0, 0, 0, 1, 0, 0, 0, 0],
]
const DEMON_SIGIL_PALETTE := {
	1: Color("#1a0608"),
	2: Color("#3a0a10"),
	3: Color("#6a1418"),
	4: Color("#a02830"),
	5: Color("#ffd860"),
}

# Angel 印记：六翼天使 + 圣环 + 中心十字光
# 0=空，1=深蓝阴影，2=淡蓝中间，3=主蓝/银白，4=明亮白，5=暖金光辉
const ANGEL_SIGIL_GRID := [
	[0, 0, 0, 5, 5, 5, 0, 0, 0],
	[0, 0, 5, 4, 5, 4, 5, 0, 0],
	[0, 0, 0, 5, 4, 5, 0, 0, 0],
	[1, 2, 3, 4, 5, 4, 3, 2, 1],
	[2, 3, 4, 5, 5, 5, 4, 3, 2],
	[1, 2, 3, 4, 5, 4, 3, 2, 1],
	[0, 0, 0, 5, 4, 5, 0, 0, 0],
	[0, 0, 5, 4, 5, 4, 5, 0, 0],
	[0, 0, 0, 5, 5, 5, 0, 0, 0],
]
const ANGEL_SIGIL_PALETTE := {
	1: Color("#3a4860"),
	2: Color("#7c98b6"),
	3: Color("#a8c0d8"),
	4: Color("#ffffff"),
	5: Color("#f0e8c8"),
}

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
		"base": Color("#82b5d4"),
		"shade": Color("#6fa3c4"),
		"highlight": Color("#a3cde6"),
		"speckle_chance": 0.05,
		"deco_chance": 0.025,
		"deco_kind": "ripple",
		"deco_palette": [Color("#c5e0ef"), Color("#ffffff")],
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
		# 土路：黄褐色车辙 + 深浅斑驳（复用现有 pebble deco 表现为路面碎石/踩痕）
		"base": Color("#8b6a3f"),
		"shade": Color("#6f5432"),
		"highlight": Color("#a48358"),
		"speckle_chance": 0.045,
		"deco_chance": 0.035,
		"deco_kind": "pebble",
		"deco_palette": [Color("#5c4326"), Color("#b39067"), Color("#4a3520")],
	},
	"stone": {
		# 石板路：冷灰石板 + seam 缝土黄色（进入城郭外围的过渡）
		"base": Color("#7a7d82"),
		"shade": Color("#64676c"),
		"highlight": Color("#949aa0"),
		"speckle_chance": 0.04,
		"deco_chance": 0.06,
		"deco_kind": "seam",
		"deco_palette": [Color("#8a7a52"), Color("#a89066"), Color("#5c503a")],
	},
	"demon_ground": {
		"base": Color("#150406"),
		"shade": Color("#090203"),
		"highlight": Color("#22080a"),
		"speckle_chance": 0.06,
		"deco_chance": 0.04,
		"deco_kind": "ember",
		"deco_palette": [Color("#4a0a10"), Color("#2a0608"), Color("#7a1820")],
	},
	"angel_ground": {
		"base": Color("#c8d8e8"),
		"shade": Color("#b0c4d8"),
		"highlight": Color("#e0eaf2"),
		"speckle_chance": 0.05,
		"deco_chance": 0.035,
		"deco_kind": "flake",
		"deco_palette": [Color("#f0e8c8"), Color("#ffffff"), Color("#a8c0d8")],
	},
	"forge_ground": {
		# 打造关：深紫神秘地面，rune 像素印记。
		"base": Color("#2a1a55"),
		"shade": Color("#1a0e33"),
		"highlight": Color("#3d2570"),
		"speckle_chance": 0.05,
		"deco_chance": 0.04,
		"deco_kind": "rune",
		"deco_palette": [Color("#8a5cff"), Color("#c8a8ff"), Color("#5536a8")],
	},
	"parade_ground": {
		# Boss 关「冲锋骑士」练兵操场：踩实的棕黄土地 + 干草 / 脚印 / 暗色裂痕。
		"base": Color("#9a7244"),
		"shade": Color("#7a5a30"),
		"highlight": Color("#b08a58"),
		"speckle_chance": 0.06,
		"deco_chance": 0.05,
		"deco_kind": "pebble",
		"deco_palette": [Color("#4a3220"), Color("#5e4028"), Color("#7a5430"), Color("#d8b878")],
	},
	"village": {
		# 乡村：浅褐夯土 + 谷穗/稻草 deco
		"base": Color("#a68858"),
		"shade": Color("#886f45"),
		"highlight": Color("#c0a276"),
		"speckle_chance": 0.055,
		"deco_chance": 0.05,
		"deco_kind": "grain",
		"deco_palette": [Color("#d8b96a"), Color("#b89550"), Color("#7c5a2c")],
	},
	"town": {
		# 城镇：深灰砖 + brick 砖纹（偶发暖橘灯高光 = 商铺灯光）
		"base": Color("#5b5f66"),
		"shade": Color("#4a4e54"),
		"highlight": Color("#7a7f88"),
		"speckle_chance": 0.045,
		"deco_chance": 0.055,
		"deco_kind": "brick",
		"deco_palette": [Color("#4a4e54"), Color("#6a6e75"), Color("#d8a860")],
	},
	"castle": {
		# 城堡：冷灰大理石 + 蓝紫纹章 crest deco
		"base": Color("#8890a0"),
		"shade": Color("#6f7688"),
		"highlight": Color("#a0a8b8"),
		"speckle_chance": 0.04,
		"deco_chance": 0.03,
		"deco_kind": "crest",
		"deco_palette": [Color("#5a6a90"), Color("#7080a8"), Color("#a0a8c8")],
	},
	"palace": {
		# 王宫：金红大理石 + 金箔菱格 gilt deco（终章视觉华丽感）
		"base": Color("#b8967c"),
		"shade": Color("#9a7860"),
		"highlight": Color("#d4b898"),
		"speckle_chance": 0.035,
		"deco_chance": 0.04,
		"deco_kind": "gilt",
		"deco_palette": [Color("#d4a848"), Color("#b88830"), Color("#f0d488")],
	},
	"palace_corridor": {
		# 王宫火把长廊（第 29 关 boss 前奏）：深红地毯 + 火把余烬（ember deco 复用）
		"base": Color("#4c2c30"),
		"shade": Color("#3a2028"),
		"highlight": Color("#683840"),
		"speckle_chance": 0.05,
		"deco_chance": 0.045,
		"deco_kind": "ember",
		"deco_palette": [Color("#c85030"), Color("#f08040"), Color("#501818")],
	},
	"pit": {
		# 深坑：3 档深色，无装饰 —— 视觉上是地面上的黑洞
		"base": Color("#0c0a12"),
		"shade": Color("#060409"),
		"highlight": Color("#14101c"),
		"speckle_chance": 0.05,
		"deco_chance": 0.0,
		"deco_kind": "crack",
		"deco_palette": [Color("#1a1424"), Color("#000000"), Color("#221830")],
	},
	"stone_floor": {
		# 石地板：可通行，灰冷 4 档 + 微裂纹（怪物/树/草不在其上生成）
		"base": Color("#8a8d92"),
		"shade": Color("#72757a"),
		"highlight": Color("#a4a8ae"),
		"speckle_chance": 0.035,
		"deco_chance": 0.05,
		"deco_kind": "crack",
		"deco_palette": [Color("#5c5f64"), Color("#4a4d52"), Color("#6c6f74")],
	},
	"blocking_stone": {
		# 阻挡石块：灰棕 4 档 + 深轮廓块状 —— 阻挡移动/子弹/画线
		"base": Color("#6a6058"),
		"shade": Color("#4a423a"),
		"highlight": Color("#8a7e72"),
		"speckle_chance": 0.06,
		"deco_chance": 0.08,
		"deco_kind": "chunk",
		"deco_palette": [Color("#3a342c"), Color("#9a8e82"), Color("#524840")],
	},
}

var _texture: ImageTexture
var _world_w := 720
var _world_h := 1280
var _cols := 0
var _rows := 0
var _grid: Array = []
var _current_theme := ""
var _stone_floor_img: Image = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stone_floor_img = STONE_FLOOR_TEX.get_image()


func setup_for_stage(stage_index: int, safe_zone: Dictionary = {}) -> void:
	_world_w = int(GameConfig.get_tuning("logical_width", 720))
	_world_h = int(GameConfig.get_tuning("logical_height", 1280))
	_cols = int(ceil(float(_world_w) / float(TILE_SIZE)))
	_rows = int(ceil(float(_world_h) / float(TILE_SIZE)))
	_current_theme = _resolve_stage_theme(stage_index)
	_build_grid(stage_index, safe_zone)
	_rebake_texture()
	queue_redraw()


func _resolve_stage_theme(stage_index: int) -> String:
	# 由 BattleController.get_stage_theme 负责"哪关是主题关 + 哪种主题"的运行时决策。
	# terrain 不缓存随机结果，直接每次重问 battle，确保和 monster.gd / battle.gd 视角完全一致。
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.has_method("get_stage_theme"):
		return String(battle.get_stage_theme(stage_index))
	return ""


func set_tile(col: int, row: int, tile_type: String) -> void:
	if row < 0 or row >= _rows or col < 0 or col >= _cols:
		return
	if not TILE_DATA.has(tile_type):
		push_warning("TerrainBackground: unknown tile type '%s'" % tile_type)
		return
	_grid[row][col] = tile_type
	_rebake_texture()
	queue_redraw()


# 整片 grid 重置为某类型（如 grass）后只烘焙一次；用于编辑器"恢复初始"。
func clear_all_tiles(tile_type: String) -> void:
	if not TILE_DATA.has(tile_type):
		tile_type = TYPE_GRASS
	for r in range(_rows):
		for c in range(_cols):
			_grid[r][c] = tile_type
	_rebake_texture()
	queue_redraw()

# 批量改若干格后只烘焙一次。编辑器布局载入大量水/石地板时，逐格 set_tile 每格都会
# _rebake_texture() 整张图（720×1280 全格 _paint_tile + ImageTexture 重建）→ N 格 = N 次全图
# 重绘，进测试 / 恢复现场卡顿。这里先写 grid，末尾一次 bake。
func set_tiles_batch(changes: Array) -> void:
	var dirty := false
	for ch in changes:
		if not (ch is Dictionary):
			continue
		var col: int = int(ch.get("col", 0))
		var row: int = int(ch.get("row", 0))
		var tile_type: String = String(ch.get("type", ""))
		if row < 0 or row >= _rows or col < 0 or col >= _cols:
			continue
		if not TILE_DATA.has(tile_type):
			push_warning("TerrainBackground: unknown tile type '%s'" % tile_type)
			continue
		_grid[row][col] = tile_type
		dirty = true
	if dirty:
		_rebake_texture()
		queue_redraw()


func get_tile(col: int, row: int) -> String:
	if row < 0 or row >= _rows or col < 0 or col >= _cols:
		return ""
	return String(_grid[row][col])


func get_rows() -> int:
	return _rows


func get_cols() -> int:
	return _cols


func get_tile_at_world(world_x: float, world_y: float) -> String:
	var col := int(floor(world_x / float(TILE_SIZE)))
	var row := int(floor(world_y / float(TILE_SIZE)))
	return get_tile(col, row)


# 局内特殊地块：是否阻挡移动 / 画线（pit + blocking_stone）。
# water 不算阻挡（走 path_input 的额外 ki 消耗逻辑）。
# 注意：子弹/视线走 is_blocking_for_bullet（不含 pit）。
func is_blocking_tile(tile_type: String) -> bool:
	return BLOCKING_TILE_TYPES.has(tile_type)


# 坐标版本：越界或空串返回 false（不阻挡）。
func is_blocking_for_line(col: int, row: int) -> bool:
	return is_blocking_tile(get_tile(col, row))


func is_blocking_for_movement(col: int, row: int) -> bool:
	return is_blocking_tile(get_tile(col, row))


# 子弹/视线专用阻挡：只含实体石块，不含深坑（深坑是地面上的洞，子弹从上方飞过）。
# is_bullet_blocked_at 用这个，而非 is_blocking_for_movement。
func is_blocking_for_bullet(col: int, row: int) -> bool:
	return BULLET_BLOCKING_TILE_TYPES.has(get_tile(col, row))


# 怪物 / 树 / 草生成时的避让判定：water / pit / blocking_stone / stone_floor 都避开。
func is_spawn_avoid_tile(tile_type: String) -> bool:
	return SPAWN_AVOID_TILE_TYPES.has(tile_type)


func is_spawn_avoid_at(col: int, row: int) -> bool:
	return is_spawn_avoid_tile(get_tile(col, row))


func iter_water_cells() -> Array:
	var out: Array = []
	for r in range(_rows):
		for c in range(_cols):
			if String(_grid[r][c]) == TYPE_WATER:
				out.append(Vector2i(c, r))
	return out


func make_water_only_texture() -> ImageTexture:
	# 返回一张和地形同尺寸的图：水格保留原烘焙像素（颜色 + 涟漪 + 高光），非水格透明。
	# WaterOverlay 直接 draw_texture 它，等于在画线暗罩之上把"原本的水"再拍一遍 → 解决"条纹感"和"压盖"问题。
	if _texture == null:
		return null
	var src := _texture.get_image()
	if src == null:
		return null
	var img := Image.create(_world_w, _world_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for r in range(_rows):
		for c in range(_cols):
			if String(_grid[r][c]) != TYPE_WATER:
				continue
			var ox: int = c * TILE_SIZE
			var oy: int = r * TILE_SIZE
			var w: int = mini(TILE_SIZE, _world_w - ox)
			var h: int = mini(TILE_SIZE, _world_h - oy)
			if w <= 0 or h <= 0:
				continue
			img.blit_rect(src, Rect2i(ox, oy, w, h), Vector2i(ox, oy))
	return ImageTexture.create_from_image(img)


func has_grass_tiles() -> bool:
	for r in range(_rows):
		for c in range(_cols):
			if _grid[r][c] == TYPE_GRASS:
				return true
	return false


# Override hook: stages can return any tile type key for a given cell. Default = grass everywhere.
func _pick_tile_type_for(stage_index: int, _col: int, _row: int) -> String:
	# 打造关（room_type == attr_forge）→ 全部 forge_ground 紫色 tile
	var stage_dict: Dictionary = GameConfig.get_stage(stage_index)
	if str(stage_dict.get("room_type", "")) == "attr_forge":
		return TYPE_FORGE_GROUND
	# Boss 关 → 王宫大厅金红大理石（第 30 关剧情：闯王宫击杀 boss）
	if str(stage_dict.get("boss_id", "")) != "":
		return TYPE_PALACE
	match _current_theme:
		"demon":
			return TYPE_DEMON_GROUND
		"angel":
			return TYPE_ANGEL_GROUND
	# 无特殊 override → 按段位映射默认地面（草地→土路→乡村→石板→城镇→城堡→王宫）
	return _get_segment_terrain(stage_index)


func _get_segment_terrain(stage_index: int) -> String:
	# 第 29 关（idx=28）：boss 前奏，火把长廊
	if stage_index == 28:
		return TYPE_PALACE_CORRIDOR
	var segment := clampi(stage_index / 4, 0, 6)  # 每 4 关一段，第 25 关以后（含）都归段 6
	return String(SEGMENT_TERRAIN_MAP.get(segment, TYPE_GRASS))


func _build_grid(stage_index: int, safe_zone: Dictionary) -> void:
	_grid.resize(_rows)
	for r in range(_rows):
		var row: Array = []
		row.resize(_cols)
		for c in range(_cols):
			row[c] = _pick_tile_type_for(stage_index, c, r)
		_grid[r] = row
	# 随机水簇生成已停用：水改为关卡编辑器布局放置（_apply_level_layout 走 set_tile）。
	# 保留 _generate_water_clusters 函数体以备需要，但 _build_grid 不再调用。


func _generate_water_clusters(_stage_index: int, safe_zone: Dictionary) -> void:
	var cluster_count := _roll_water_cluster_count()
	for n in range(cluster_count):
		if randf() < WATER_PROB_RIVER:
			_place_water_river(safe_zone)
		else:
			_place_water_pond(safe_zone)


func _roll_water_cluster_count() -> int:
	var roll := randf()
	var acc := 0.0
	for i in range(WATER_PROB_CLUSTERS.size()):
		acc += float(WATER_PROB_CLUSTERS[i])
		if roll < acc:
			return i
	return WATER_PROB_CLUSTERS.size() - 1


func _place_water_river(safe_zone: Dictionary) -> void:
	# 河流：条状，仅横/竖两种方向（不再有对角线，避免梯形锯齿）。
	# 方向：0=水平、1=竖直
	var dir_idx: int = randi() % 2
	var dx := 0
	var dy := 0
	match dir_idx:
		0: dx = 1; dy = 0
		1: dx = 0; dy = 1
	# 宽度：横/竖 2~3 格
	var width: int = 2 + (1 if randf() < 0.45 else 0)
	var length := WATER_TILES_PER_CLUSTER_BASE / width
	if randf() < WATER_PROB_BIG_RIVER:
		length = int(round(length * 1.6))
	length = maxi(WATER_CLUSTER_MIN_LEN, length)
	# 选起点：随机 60 次，找一个不在 safe_zone + pad 内的合法格
	var start := _pick_safe_cell(safe_zone, 60)
	if start.x < 0:
		return
	var col := start.x
	var row := start.y
	for step in range(length):
		# 主线 + 宽度沿"垂直方向"扩张
		for off in range(width):
			var ocol := col + (-dy * off)
			var orow := row + (dx * off)
			if _cell_in_bounds(ocol, orow) and not _cell_in_safe(ocol, orow, safe_zone):
				_grid[orow][ocol] = TYPE_WATER
		col += dx
		row += dy
		if not _cell_in_bounds(col, row):
			break
		if _cell_in_safe(col, row, safe_zone):
			break


func _place_water_pond(safe_zone: Dictionary) -> void:
	# 水池：方块，基础 6×6 ≈ 36 格，允许 ±2 扰动；低概率放大到 8×8
	var base_w := 6 + randi_range(-2, 2)
	var base_h := 6 + randi_range(-2, 2)
	if randf() < WATER_PROB_BIG_POND:
		base_w = 8 + randi_range(-1, 1)
		base_h = 8 + randi_range(-1, 1)
	base_w = maxi(2, base_w)
	base_h = maxi(2, base_h)
	var center := _pick_safe_cell(safe_zone, 60)
	if center.x < 0:
		return
	var c0 := center.x - int(floor(base_w * 0.5))
	var r0 := center.y - int(floor(base_h * 0.5))
	for r in range(r0, r0 + base_h):
		for c in range(c0, c0 + base_w):
			if _cell_in_bounds(c, r) and not _cell_in_safe(c, r, safe_zone):
				_grid[r][c] = TYPE_WATER


func _pick_safe_cell(safe_zone: Dictionary, attempts: int) -> Vector2i:
	for n in range(attempts):
		var c := randi_range(1, _cols - 2)
		var r := randi_range(1, _rows - 2)
		if not _cell_in_safe(c, r, safe_zone):
			return Vector2i(c, r)
	return Vector2i(-1, -1)


func _cell_in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < _cols and row >= 0 and row < _rows


func _cell_in_safe(col: int, row: int, safe_zone: Dictionary) -> bool:
	if safe_zone.is_empty():
		return false
	var cx := (col + 0.5) * float(TILE_SIZE)
	var cy := (row + 0.5) * float(TILE_SIZE)
	var dx := cx - float(safe_zone.get("x", 0.0))
	var dy := cy - float(safe_zone.get("y", 0.0))
	var rr := float(safe_zone.get("r", 0.0)) + WATER_SAFE_PAD
	return dx * dx + dy * dy <= rr * rr


func _rebake_texture() -> void:
	var img := Image.create(_world_w, _world_h, false, Image.FORMAT_RGBA8)
	for r in range(_rows):
		for c in range(_cols):
			_paint_tile(img, c, r, String(_grid[r][c]))
	if not _current_theme.is_empty():
		_paint_theme_sigil(img, _current_theme)
	_texture = ImageTexture.create_from_image(img)


func _paint_theme_sigil(img: Image, theme: String) -> void:
	var grid: Array = []
	var palette: Dictionary = {}
	match theme:
		"demon":
			grid = DEMON_SIGIL_GRID
			palette = DEMON_SIGIL_PALETTE
		"angel":
			grid = ANGEL_SIGIL_GRID
			palette = ANGEL_SIGIL_PALETTE
		_:
			return
	var sigil_w := SIGIL_GRID_SIZE * SIGIL_PIXEL
	var sigil_h := SIGIL_GRID_SIZE * SIGIL_PIXEL
	var ox := int(round((_world_w - sigil_w) * 0.5))
	var oy := int(round((_world_h - sigil_h) * 0.5))
	for gy in range(SIGIL_GRID_SIZE):
		var row: Array = grid[gy]
		for gx in range(SIGIL_GRID_SIZE):
			var key: int = int(row[gx])
			if key == 0 or not palette.has(key):
				continue
			var color: Color = palette[key]
			var px := ox + gx * SIGIL_PIXEL
			var py := oy + gy * SIGIL_PIXEL
			img.fill_rect(Rect2i(px, py, SIGIL_PIXEL, SIGIL_PIXEL), color)


func _paint_tile(img: Image, col: int, row: int, tile_type: String) -> void:
	var data: Dictionary = TILE_DATA.get(tile_type, TILE_DATA[TYPE_GRASS])
	var ox := col * TILE_SIZE
	var oy := row * TILE_SIZE
	var w := mini(TILE_SIZE, _world_w - ox)
	var h := mini(TILE_SIZE, _world_h - oy)
	if w <= 0 or h <= 0:
		return
	# 石地板走美术素材：先铺底色（防素材边缘透明露黑），再 blit stone_floor.png
	if tile_type == TYPE_STONE_FLOOR and _stone_floor_img != null:
		img.fill_rect(Rect2i(ox, oy, w, h), Color(data.base))
		img.blit_rect(_stone_floor_img, Rect2i(0, 0, w, h), Vector2i(ox, oy))
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
	# 水格在与陆地相邻的"外角"做一个阶梯倒角，让河岸看起来圆滑而非纯方块
	if tile_type == TYPE_WATER:
		_chamfer_water_corner(img, col, row, ox, oy, w, h)


func _chamfer_water_corner(img: Image, col: int, row: int, ox: int, oy: int, w: int, h: int) -> void:
	# 4 邻判定：上、下、左、右 哪些是非水（含越界）
	var n_up := _cell_is_non_water(col, row - 1)
	var n_down := _cell_is_non_water(col, row + 1)
	var n_left := _cell_is_non_water(col - 1, row)
	var n_right := _cell_is_non_water(col + 1, row)
	# 仅在"两个相邻邻居都非水"的角上倒角（即外凸角，朝向陆地）
	var shore: Color = TILE_DATA[TYPE_GRASS]["base"]
	var chamfer := 6  # 6 像素（≈ 3 个 PIXEL 块），相对 40px 瓦片视觉适中
	if n_up and n_right:
		_paint_corner_stairs(img, ox + w - chamfer, oy, chamfer, shore, true, false)
	if n_up and n_left:
		_paint_corner_stairs(img, ox, oy, chamfer, shore, false, false)
	if n_down and n_right:
		_paint_corner_stairs(img, ox + w - chamfer, oy + h - chamfer, chamfer, shore, true, true)
	if n_down and n_left:
		_paint_corner_stairs(img, ox, oy + h - chamfer, chamfer, shore, false, true)


func _cell_is_non_water(col: int, row: int) -> bool:
	# 越界算非水（让外边缘也能倒角）
	if not _cell_in_bounds(col, row):
		return true
	return String(_grid[row][col]) != TYPE_WATER


func _paint_corner_stairs(img: Image, x: int, y: int, size: int, color: Color, right_side: bool, bottom_side: bool) -> void:
	# 在 [x..x+size, y..y+size] 区域内画一个三角形阶梯，把角"咬掉"成 shore 色
	# right_side / bottom_side 控制阶梯朝向哪个外角收紧
	for i in range(size):
		var run := size - i  # 本行的像素数（越靠内/角点越短）
		var px_x := (x + (size - run)) if right_side else x
		var px_y := (y + size - 1 - i) if bottom_side else (y + i)
		img.fill_rect(Rect2i(px_x, px_y, run, 1), color)


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
		"ember":
			# 暗红基底里的微小灰烬/血珠：1 个亮点 + 周围 2 个暗点
			var ecol: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), ecol)
			img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL, PIXEL), palette[(rng.randi() % palette.size())])
			if palette.size() >= 3:
				img.fill_rect(Rect2i(x - PIXEL, y + PIXEL, PIXEL, PIXEL), palette[2])
		"flake":
			# 圣光关淡蓝砖里的金色/白色雪花光斑：十字 3 点
			var fcol: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), fcol)
			img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL, PIXEL), fcol)
			img.fill_rect(Rect2i(x - PIXEL, y + PIXEL, PIXEL, PIXEL), fcol)
		"rune":
			# 打造关紫色地面里的 rune 印记：3 点小十字 + 1 颗亮核（参考 flake 但配色不同）
			var rcol: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), rcol)
			img.fill_rect(Rect2i(x + PIXEL, y, PIXEL, PIXEL), rcol)
			img.fill_rect(Rect2i(x, y + PIXEL, PIXEL, PIXEL), rcol)
			if palette.size() >= 2:
				img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL, PIXEL), palette[1])
		"grain":
			# 乡村谷穗/稻草：3×1 竖秆 + 顶端一颗麦粒
			var stalk_col: Color = palette[palette.size() - 1]  # 最后一色 = 秆色（深褐）
			var head_col: Color = palette[rng.randi() % maxi(1, palette.size() - 1)]  # 前面几色 = 穗色
			img.fill_rect(Rect2i(x, y + PIXEL, PIXEL, PIXEL), stalk_col)
			img.fill_rect(Rect2i(x, y + PIXEL * 2, PIXEL, PIXEL), stalk_col)
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), head_col)
		"seam":
			# 石板缝隙：随机横/竖 2 段短线，缝土色
			var seam_col: Color = palette[rng.randi() % palette.size()]
			if rng.randf() < 0.5:
				img.fill_rect(Rect2i(x, y, PIXEL * 2, PIXEL), seam_col)  # 横缝
			else:
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL * 2), seam_col)  # 竖缝
		"brick":
			# 城镇砖纹：2×1 或 1×2 错缝砖块，1/10 概率单点暖橘灯高光
			var brick_col: Color = palette[rng.randi() % maxi(1, palette.size() - 1)]  # 前几色 = 砖色
			if rng.randf() < 0.5:
				img.fill_rect(Rect2i(x, y, PIXEL * 2, PIXEL), brick_col)
				img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL * 2, PIXEL), brick_col)  # 错缝
			else:
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL * 2), brick_col)
				img.fill_rect(Rect2i(x + PIXEL, y + PIXEL, PIXEL, PIXEL * 2), brick_col)
			if palette.size() >= 3 and rng.randf() < 0.1:
				# 暖橘灯高光（palette 末尾 = 灯色 #d8a860）
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), palette[palette.size() - 1])
		"crest":
			# 城堡纹章：3 点垂直菱形（中心 + 上下）
			var crest_col: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), crest_col)
			img.fill_rect(Rect2i(x, y + PIXEL, PIXEL, PIXEL), crest_col)
			img.fill_rect(Rect2i(x, y - PIXEL, PIXEL, PIXEL), crest_col)
		"gilt":
			# 王宫金箔菱格：3×3 十字 + 中心高亮 1 点
			var gilt_col: Color = palette[rng.randi() % maxi(1, palette.size() - 1)]  # 前几色 = 金色
			img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), gilt_col)
			img.fill_rect(Rect2i(x + PIXEL, y, PIXEL, PIXEL), gilt_col)
			img.fill_rect(Rect2i(x - PIXEL, y, PIXEL, PIXEL), gilt_col)
			img.fill_rect(Rect2i(x, y + PIXEL, PIXEL, PIXEL), gilt_col)
			img.fill_rect(Rect2i(x, y - PIXEL, PIXEL, PIXEL), gilt_col)
			if palette.size() >= 3:
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), palette[palette.size() - 1])  # 中心高亮
		"crack":
			# 深坑 / 石地板裂纹：从中心向随机方向延伸的 2-3 段暗线（模拟裂缝）
			var crack_col: Color = palette[rng.randi() % palette.size()]
			var len_px: int = rng.randi_range(2, 3)
			if rng.randf() < 0.5:
				for i in range(len_px):
					img.fill_rect(Rect2i(x + i * PIXEL, y, PIXEL, PIXEL), crack_col)
			else:
				for i in range(len_px):
					img.fill_rect(Rect2i(x, y + i * PIXEL, PIXEL, PIXEL), crack_col)
			if palette.size() >= 2:
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), palette[1])  # 裂缝深处更暗
		"chunk":
			# 阻挡石块的块状纹理：2×2 深色块 + 1 点高光（凸出岩石质感）
			var chunk_col: Color = palette[rng.randi() % palette.size()]
			img.fill_rect(Rect2i(x, y, PIXEL * 2, PIXEL * 2), chunk_col)
			if palette.size() >= 2:
				img.fill_rect(Rect2i(x, y, PIXEL, PIXEL), palette[1])  # 高光
		_:
			pass


func _draw() -> void:
	if _texture:
		draw_texture(_texture, Vector2.ZERO)
