extends Control
class_name PixelCardIcon

# 32x32 像素 grid 程序化卡牌图标。
# 每个 sprite 用 4-5 个色阶（outline / dark / base / light / hi）做出立体感，参考
# assets/icons/equipment/icon_equip_*_pixel.svg 的细节密度。
#
# 用法：
#   var icon := PixelCardIcon.new()
#   icon.upgrade = upgrade_dict
#   icon.icon_size = 48.0
#   container.add_child(icon)

@export var upgrade: Dictionary = {}
@export var icon_size: float = 48.0

const GRID := 32

# 元素色阶（hi / base / dark / outline）
const ELEM_PALETTE: Dictionary = {
	"fire":    {"hi": Color("#fff0c0"), "light": Color("#ffb060"), "base": Color("#ff7028"), "dark": Color("#a83812"), "out": Color("#561808")},
	"ice":     {"hi": Color("#eaf6ff"), "light": Color("#9fd8ff"), "base": Color("#5aa8e8"), "dark": Color("#1f5c98"), "out": Color("#0e2a48")},
	"thunder": {"hi": Color("#fffce0"), "light": Color("#ffe060"), "base": Color("#f4b820"), "dark": Color("#8c6010"), "out": Color("#3c2808")},
	"poison":  {"hi": Color("#e4ffd0"), "light": Color("#8de060"), "base": Color("#4caa30"), "dark": Color("#1d5818"), "out": Color("#0a2808")},
}

# prefix → 5 个色阶
const PREFIX_PALETTE: Dictionary = {
	"basic":  {"hi": Color("#fff4d0"), "light": Color("#f8d678"), "base": Color("#d7a838"), "dark": Color("#8a6818"), "out": Color("#3a2808")},
	"sv":     {"hi": Color("#ffe8e8"), "light": Color("#ff8888"), "base": Color("#dc3848"), "dark": Color("#841828"), "out": Color("#3a0810")},
	"bullet": {"hi": Color("#f8fcff"), "light": Color("#d7dcef"), "base": Color("#9098b4"), "dark": Color("#4a516a"), "out": Color("#1a1f30")},
	"sword":  {"hi": Color("#f1f4ff"), "light": Color("#c3c9dd"), "base": Color("#7a819d"), "dark": Color("#3e4358"), "out": Color("#181b28")},
	"trail":  {"hi": Color("#fff4c0"), "light": Color("#ffd060"), "base": Color("#f08820"), "dark": Color("#a04810"), "out": Color("#3a1808")},
	"orb":    {"hi": Color("#ffeaff"), "light": Color("#e898ff"), "base": Color("#a040d0"), "dark": Color("#5a1880"), "out": Color("#280838")},
	"summon": {"hi": Color("#e8f0ff"), "light": Color("#a0b8ff"), "base": Color("#5070d8"), "dark": Color("#1f3088"), "out": Color("#0a1238")},
	"combo":  {"hi": Color("#ffe8f8"), "light": Color("#ff90d0"), "base": Color("#e04098"), "dark": Color("#88184c"), "out": Color("#380818")},
	"elem":   {"hi": Color("#f8fcff"), "light": Color("#d7dcef"), "base": Color("#9098b4"), "dark": Color("#4a516a"), "out": Color("#1a1f30")},
	# 主题关：恶魔（血红+暗黑） / 天使（圣金+白）
	"demon":  {"hi": Color("#ffd0c0"), "light": Color("#ff5848"), "base": Color("#d81830"), "dark": Color("#7a0a25"), "out": Color("#280418")},
	"angel":  {"hi": Color("#ffffff"), "light": Color("#fff488"), "base": Color("#ffd048"), "dark": Color("#a07820"), "out": Color("#2a2008")},
}


func set_upgrade(u: Dictionary) -> void:
	upgrade = u
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if upgrade.is_empty():
		return
	var card_id: String = str(upgrade.get("id", ""))
	var prefix: String = _id_prefix(card_id)
	var element: String = _detect_element(upgrade)
	var g: float = icon_size / float(GRID)
	# 元素卡用元素色（除 basic / sv 这种纯属性卡）
	var pal: Dictionary
	if element != "" and prefix in ["elem", "trail", "sword", "orb", "summon", "combo"]:
		pal = ELEM_PALETTE[element]
	else:
		pal = PREFIX_PALETTE.get(prefix, PREFIX_PALETTE["basic"])
	# 主题关 sv_ 卡（sv_angel_shelter / sv_demon_recover）按主题色覆盖
	if prefix == "sv":
		if card_id.find("angel") >= 0:
			pal = PREFIX_PALETTE["angel"]
		elif card_id.find("demon") >= 0:
			pal = PREFIX_PALETTE["demon"]

	# 背景：暗色圆角卡牌底（与 PNG 实物图标的描边一致）
	_draw_bg(g, pal["out"])

	# 主体 sprite
	match prefix:
		"basic":  _draw_basic(card_id, g, pal)
		"sv":     _draw_heart(g, pal)
		"bullet": _draw_bullet_variant(card_id, g, pal)
		"sword":  _draw_sword(g, pal)
		"trail":  _draw_trail_variant(card_id, g, pal)
		"orb":    _draw_orb(g, pal)
		"summon": _draw_summon(card_id, g, pal)
		"combo":  _draw_combo(card_id, g, pal)
		"elem":   _draw_bullet(g, pal)
		"demon":  _draw_demon(card_id, g, pal)
		"angel":  _draw_angel(card_id, g, pal)
		_:        _draw_question(g, pal)

	# 元素徽章（右下 8×8）
	if element != "":
		_draw_elem_badge(element, g)


func _block(x: int, y: int, g: float, color: Color) -> void:
	if x < 0 or x >= GRID or y < 0 or y >= GRID:
		return
	draw_rect(Rect2(float(x) * g, float(y) * g, g + 0.5, g + 0.5), color)


# 圆角背景：模拟 32×32 卡牌底
func _draw_bg(g: float, outline: Color) -> void:
	var bg := Color(outline.r * 0.25, outline.g * 0.25, outline.b * 0.25, 0.7)
	var bg2 := Color(outline.r * 0.45, outline.g * 0.45, outline.b * 0.45, 0.85)
	# 内填
	for y in range(2, 30):
		for x in range(2, 30):
			# 圆角
			if (x < 4 and y < 4) or (x < 4 and y > 27) or (x > 27 and y < 4) or (x > 27 and y > 27):
				continue
			_block(x, y, g, bg)
	# 顶高光带
	for x in range(4, 28):
		_block(x, 2, g, bg2)
	# 边框
	for x in range(3, 29):
		_block(x, 1, g, outline)
		_block(x, 30, g, outline)
	for y in range(3, 29):
		_block(1, y, g, outline)
		_block(30, y, g, outline)
	# 圆角描边
	for p in [[2,2],[2,28],[28,2],[28,28],[3,2],[2,3],[28,3],[3,28],[27,2],[2,27],[27,28],[28,27]]:
		_block(int(p[0]), int(p[1]), g, outline)


func _id_prefix(card_id: String) -> String:
	for p in ["basic", "sv", "bullet", "sword", "trail", "orb", "summon", "combo", "elem", "demon", "angel"]:
		if card_id.begins_with(p + "_"):
			return p
	return ""


func _detect_element(u: Dictionary) -> String:
	for k in ["fire", "ice", "thunder", "poison"]:
		if int(u.get("applies_" + k, 0) or 0) != 0:
			return k
	var el := str(u.get("element", ""))
	if el in ELEM_PALETTE:
		return el
	return ""


# ============= 主体 sprites（32×32 网格内，内容约 24×24，居中）=============

# 拳头 / 心 / 闪电 / 菱形（属性类多种变体）
func _draw_basic(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("godspeed") >= 0 or card_id.find("swift") >= 0 or card_id.find("move") >= 0:
		_draw_lightning(g, p)
	elif card_id.find("ki") >= 0:
		_draw_diamond(g, p)
	elif card_id.find("shrink") >= 0:
		_draw_arrow_down(g, p)
	elif card_id.find("luck") >= 0 or card_id.find("four_leaf") >= 0:
		_draw_clover(g, p)
	elif card_id.find("unicorn") >= 0:
		_draw_horn(g, p)
	elif card_id.find("warrior") >= 0 or card_id.find("berserker") >= 0 or card_id.find("demon") >= 0 or card_id.find("tri") >= 0 or card_id.find("breath") >= 0 or card_id.find("giant") >= 0:
		_draw_fist(g, p)
	else:
		_draw_fist(g, p)


# 独角兽的角（sr=52 basic_unicorn 用）— 20×22 螺旋角形
func _draw_horn(g: float, p: Dictionary) -> void:
	var pattern := [
		"..........O.........",
		".........OBO........",
		"........OBHBO.......",
		".......OBHHBO.......",
		"......OBHLLBO.......",
		"......OBLBBBO.......",
		".....OBHLLBO........",
		".....OBLBBO.........",
		"....OBHLLBO.........",
		"....OBLBBO..........",
		"...OBHLLBO..........",
		"...OBLBBO...........",
		"..OBHLLBO...........",
		"..OBLBBO............",
		".OBHLLBO............",
		".OBLBBO.............",
		"OBHLLBO.............",
		"OBLBBO..............",
		"OBBBO...............",
		".OBO................",
		"..O.................",
	]
	_draw_pattern(pattern, 6, 5, g, p)


func _draw_fist(g: float, p: Dictionary) -> void:
	# 24×22 像素拳头，居中起点 (5,6)
	var pattern := [
		"....OOOO.......",
		"...OBBBOOOOO...",
		"..OBLBOBBBOO...",
		"..OBLBOBLBLO...",
		"..OBLBOBLBLO...",
		"..OBLBBBBBLO...",
		".OBHLBBBBBLBO..",
		".OBHHLBBBBBBO..",
		".OBHHLLLLLLBO..",
		".OBHHHHHHLLBO..",
		".OBHHHHHHLLBO..",
		".OBHHHHHLLBBO..",
		"..OBHHHLLBBO...",
		"..OBLLLBBBO....",
		"...OOBBBO......",
		"....OOOO.......",
	]
	_draw_pattern(pattern, 7, 7, g, p)


func _draw_diamond(g: float, p: Dictionary) -> void:
	# 菱形 22×22 居中
	var pattern := [
		"..........O..........",
		".........OBO.........",
		"........OBBBO........",
		".......OBHHBBO.......",
		"......OBHHHHBBO......",
		".....OBHHHHHHBBO.....",
		"....OBHHLLLLHHBBO....",
		"...OBHLLLLLLLLHBBO...",
		"..OBHLLLLLLLLLLHBBO..",
		".OBHLLLLLLLLLLLLHBBO.",
		"OBHLLLLLLLLLLLLLLHBBO",
		".OBHLLLLLLLLLLLLHBBO.",
		"..OBHLLLLLLLLLLHBBO..",
		"...OBHLLLLLLLLHBBO...",
		"....OBHLLLLLLHBBO....",
		".....OBHLLLLHBBO.....",
		"......OBHLLHBBO......",
		".......OBHHBBO.......",
		"........OBBBO........",
		".........OBO.........",
		"..........O..........",
	]
	_draw_pattern(pattern, 5, 5, g, p)


func _draw_lightning(g: float, p: Dictionary) -> void:
	# Z 字闪电
	var pattern := [
		".......OOOOOO.",
		"......OBBBBBO.",
		".....OBHLLBO..",
		"....OBHLLBO...",
		"...OBHLLBO....",
		"..OBHLLBOOOOO.",
		".OBHLLBBBBBBBO",
		"OBHLLLLLLLLLBO",
		"OBLLLLLLLLBBBO",
		".OOOOOOBLLBO..",
		".......OBLBO..",
		"......OBLBO...",
		".....OBLBO....",
		"....OBLBO.....",
		"...OBLBO......",
		"..OBLBO.......",
		"..OBBO........",
		"..OOO.........",
	]
	_draw_pattern(pattern, 7, 6, g, p)


func _draw_arrow_down(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OOO......",
		".....OBLBO.....",
		".....OBLBO.....",
		".....OBLBO.....",
		".....OBLBO.....",
		".....OBLBO.....",
		"...OOOBLBOOO...",
		"..OBBBBLBBBBO..",
		"..OBLLLLLLLLBO.",
		"...OBLLLLLLBO..",
		"....OBLLLLBO...",
		".....OBLLBO....",
		"......OBBO.....",
		".......OO......",
	]
	_draw_pattern(pattern, 8, 8, g, p)


func _draw_clover(g: float, p: Dictionary) -> void:
	# 四叶草
	var pattern := [
		"...OOO.....OOO...",
		"..OBHBO...OBHBO..",
		".OBHHHBO.OBHHHBO.",
		".OBHHHBOOOBHHHBO.",
		"..OBHHBLLBBHHBO..",
		"...OBLBLLBBHBO...",
		"....OLLBLLBO.....",
		"....OLLLBLLO.....",
		"...OBHBOLBBO.....",
		"..OBHHHBOLBHBO...",
		".OBHHHBOOOBHHHBO.",
		".OBHHHBO.OBHHHBO.",
		"..OBHBO...OBHBO..",
		"...OOO.....OOO...",
		".........BBO.....",
		".........BBO.....",
	]
	_draw_pattern(pattern, 7, 7, g, p)


func _draw_heart(g: float, p: Dictionary) -> void:
	var pattern := [
		"..OOOO.....OOOO..",
		".OBBBBO...OBBBBO.",
		"OBHHLLBO.OBHHLLBO",
		"OBHHLLBBOBHHLLBBO",
		"OBHHLLLLLBLLLLBBO",
		".OBHLLLLLLLLLBBO.",
		".OBHLLLLLLLLLBBO.",
		"..OBHLLLLLLLBBO..",
		"...OBHLLLLLBBO...",
		"....OBHLLLBBO....",
		".....OBHLBBO.....",
		"......OBBBO......",
		".......OBO.......",
		"........O........",
	]
	_draw_pattern(pattern, 7, 9, g, p)


# 子弹 / 元素弹：仿照 dagger.svg 的渐变色阶
func _draw_bullet_variant(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("spider") >= 0:
		_draw_spider(g, p)
	elif card_id.find("laser") >= 0:
		_draw_beam(g, p)
	elif card_id.find("melee") >= 0:
		_draw_fist(g, p)
	else:
		_draw_bullet(g, p)


func _draw_trail_variant(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("psychic") >= 0:
		_draw_brain(g, p)
	elif card_id.find("bomber") >= 0:
		_draw_bomb(g, p)
	else:
		_draw_trail(g, p)


# 小蜘蛛（16×14）— bullet_spider_man 用
func _draw_spider(g: float, p: Dictionary) -> void:
	var pattern := [
		"O.....O.O.....O.",
		".O.....O.....O..",
		"..O...OBO...O...",
		"...OOOBBBOOO....",
		"..OBBHHHHHBBO...",
		".OBHLLBBBLLHBO..",
		".OBHLLBBBLLHBO..",
		"..OBHLLLLLLHBO..",
		"...OBHLLLLHBO...",
		"....OBHLLHBO....",
		"...OO.OBB.OO....",
		"..O....OO....O..",
		".O..O.....O..O..",
		"O..O.......O..O.",
	]
	_draw_pattern(pattern, 8, 9, g, p)


# 大脑（20×18）— trail_psychic 用
func _draw_brain(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OOOOOO........",
		".....OBBBBBBO.......",
		"....OBLLLLLBBO......",
		"...OBLLHHHLLBO......",
		"..OBLHHLLLHHLBO.....",
		".OBLHLLLLLLLHBO.....",
		".OBLLLBBBBBLLLBO....",
		"OBLLHBLLLLBBLLLBO...",
		"OBLLLLBLLLLBLLLBO...",
		"OBLHLHBLLLLBLLLBO...",
		"OBLLLLBBBBBBLLLBO...",
		".OBLLLLLLLLLLLLBO...",
		".OBLLLBBBBBBLLLBO...",
		"..OBLLLLLLLLLLBO....",
		"...OBLLHHLLLLBO.....",
		"....OBLLLLLLBO......",
		".....OBBBBBBO.......",
		"......OOOOOO........",
	]
	_draw_pattern(pattern, 6, 7, g, p)


# 圆形炸弹 + 引信（16×18）— trail_bomber 用
func _draw_bomb(g: float, p: Dictionary) -> void:
	var pattern := [
		"...........O....",
		"..........OBO...",
		".........OBHBO..",
		"........OBHLBO..",
		"........OBLBO...",
		".......OOOO.....",
		"....OOBBBBOOO...",
		"...OBBBBHHHBBO..",
		"..OBBBHHHLLHHBO.",
		"..OBHHLLLLLLHBO.",
		"..OBHLLLLLLLLBO.",
		"..OBHLLLLLLLLBO.",
		"..OBHHLLLLLLHBO.",
		"...OBBHHHHHHBO..",
		"....OBBBBBBBO...",
		".....OOOOOOO....",
	]
	_draw_pattern(pattern, 8, 8, g, p)


# 激光束（16×22）— bullet_laser_cannon 用
func _draw_beam(g: float, p: Dictionary) -> void:
	var pattern := [
		".....OOOOOO.....",
		"....OBBBBBBO....",
		"....OBHLLHBO....",
		"....OBHLLHBO....",
		"....OBLLLLBO....",
		".....OLLLLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		".....OLHHLO.....",
		"......OHHO......",
		"......OLLO......",
	]
	_draw_pattern(pattern, 8, 5, g, p)


func _draw_bullet(g: float, p: Dictionary) -> void:
	var pattern := [
		"......O......",
		".....OBO.....",
		"....OBHO.....",
		"...OBHHBO....",
		"..OBHHLLBO...",
		".OBHHLLLLBO..",
		".OBHLLLLLBO..",
		".OBHLLLLLBO..",
		".OBHLLLLLBO..",
		".OBHLLLLLBO..",
		".OBHLLLLLBO..",
		".OBBLLLBBBO..",
		"..OBBBBBBO...",
		"...OBBBO.....",
		"....OBBO.....",
		".....OO......",
	]
	_draw_pattern(pattern, 10, 8, g, p)


# 剑：复刻 dagger.svg 的多段色阶
func _draw_sword(g: float, p: Dictionary) -> void:
	var pattern := [
		"......O......",
		".....OBO.....",
		"....OBHBO....",
		"....OBHBO....",
		"...OBHHLBO...",
		"...OBHLLBO...",
		"...OBHLLBO...",
		"..OBHHLLLBO..",
		"..OBHLLLLBO..",
		"..OBHLLLLBO..",
		"..OBHLLLLBO..",
		".OBHLLLLLLBO.",
		"OBHLLLLLLLLBO",
		".OOBBBBBBBOO.",
		"....OBHBO....",
		"....OBHBO....",
		"....OBLBO....",
		"....OBLBO....",
		".....OOO.....",
	]
	_draw_pattern(pattern, 10, 6, g, p)


func _draw_trail(g: float, p: Dictionary) -> void:
	# 斜刀光：左下到右上 + 拖尾
	var pattern := [
		"...........OOO..",
		"..........OBLBO.",
		".........OBHLBO.",
		"........OBHLBO..",
		".......OBHLBO...",
		"......OBHLBO....",
		".....OBHLBO.....",
		"....OBHLBO......",
		"...OBHLBO.......",
		"..OBHLBO........",
		".OBHLBO.........",
		"OBHLBO..........",
		"OBLBO...........",
		"OBBO............",
		".OO.............",
	]
	_draw_pattern(pattern, 9, 9, g, p)


func _draw_orb(g: float, p: Dictionary) -> void:
	# 实心球 22×22 + 高光
	var pattern := [
		".......OOOOOO........",
		".....OOBBBBBBOO......",
		"....OBHHLLLBBBBBO....",
		"...OBHHLLLLLBBBBBO...",
		"..OBHHLLLLLLLBBBBBO..",
		"..OBHLLLLLLLLLBBBBO..",
		".OBHLLLLLLLLLLLBBBBO.",
		".OBLLLLLLLLLLLLBBBBO.",
		".OBLLLLLLLLLLLLBBBBO.",
		"OBLLLLLLLLLLLLLBBBBBO",
		"OBLLLLLLLLLLLLBBBBBBO",
		"OBLLLLLLLLLLLBBBBBBBO",
		".OBLLLLLLLLLBBBBBBBO.",
		".OBLLLLLLLBBBBBBBBBO.",
		".OBBLLLBBBBBBBBBBBBO.",
		"..OBBBBBBBBBBBBBBBO..",
		"..OBBBBBBBBBBBBBBBO..",
		"...OBBBBBBBBBBBBBO...",
		"....OBBBBBBBBBBBO....",
		".....OOBBBBBBBOO.....",
		".......OOOOOO........",
	]
	_draw_pattern(pattern, 5, 5, g, p)


# 召唤：王冠 / 默认小人
func _draw_summon(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("king") >= 0:
		_draw_crown(g, p)
	elif card_id.find("god") >= 0:
		_draw_cross(g, p)
	elif card_id.find("bear") >= 0 or card_id.find("gorilla") >= 0:
		_draw_paw(g, p)
	elif card_id.find("snake") >= 0:
		_draw_zigzag(g, p)
	elif card_id.find("fire") >= 0:
		_draw_flame(g, p)
	elif card_id.find("thunder") >= 0:
		_draw_lightning(g, p)
	elif card_id.find("orbit_shield") >= 0 or card_id.find("shield") >= 0:
		_draw_shield(g, p)
	else:
		_draw_humanoid(g, p)


# 简易盾牌（22×22 居中）— sr=56 环绕盾用
func _draw_shield(g: float, p: Dictionary) -> void:
	var pattern := [
		".....OOOOOOOOOO.....",
		"....OBBBBBBBBBBO....",
		"...OBHHHLLLLLLBBO...",
		"..OBHHLLLLLLLLBBO...",
		"..OBHLLLLLLLLLLBO...",
		"..OBHLLLLLLLLLLBO...",
		"..OBLLLLLLLLLLBBO...",
		"..OBLLLBBBBLLLBBO...",
		"..OBLLBBBBBBLLBBO...",
		"..OBLLLBBBBLLLBBO...",
		"..OBLLLLBBLLLLBBO...",
		"..OBLLLLLLLLLLBBO...",
		"..OBLLLLLLLLLLBBO...",
		"...OBLLLLLLLLBBO....",
		"....OBLLLLLLBBO.....",
		".....OBLLLLBBO......",
		"......OBLLBBO.......",
		".......OBBBBO.......",
		"........OBBO........",
		".........OO.........",
	]
	_draw_pattern(pattern, 6, 6, g, p)


func _draw_crown(g: float, p: Dictionary) -> void:
	var pattern := [
		"O....O....O....O.",
		"OO..OO...OO...OO.",
		"OBO.OBO.OBO..OBO.",
		"OBBOOBBOOBBOOBBO.",
		"OBHBOBHBOBHBOBHBO",
		"OBHHLLLLLLLLLLHBO",
		"OBHHLLLLLLLLLLHBO",
		"OBHHLLLLLLLLLLHBO",
		"OBHLLLLLLLLLLLLBO",
		"OBBBBBBBBBBBBBBBO",
		"OBLLLLLLLLLLLLLBO",
		".OOOOOOOOOOOOOOO.",
	]
	_draw_pattern(pattern, 7, 10, g, p)


func _draw_cross(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OOOOO......",
		".....OBHHLBO.....",
		".....OBHHLBO.....",
		".....OBHLLBO.....",
		"...OOOBHLLBOOO...",
		"..OBBBBHLLBBBBO..",
		".OBHHHHHLLLLLLBO.",
		".OBHLLLLLLLLLLBO.",
		".OBHLLLLLLLLLBBO.",
		"..OBBBBBLLBBBBO..",
		"...OOOOBLLBOOO...",
		".....OBLLBO......",
		".....OBLLBO......",
		".....OBLLBO......",
		".....OBLLBO......",
		".....OBBBBO......",
		"......OOOO.......",
	]
	_draw_pattern(pattern, 7, 7, g, p)


func _draw_paw(g: float, p: Dictionary) -> void:
	var pattern := [
		"..OO....OO....OO...",
		".OBHO..OBHO..OBHO..",
		"OBHHBO.OBHBO.OBHBO.",
		"OBLLBO.OBLBO.OBLBO.",
		".OBBO...OBO...OBO..",
		".......OOOO........",
		"......OBHHBO.......",
		".....OBHHHHBO......",
		"....OBHHLLLLBO.....",
		"....OBLLLLLLBO.....",
		"....OBLLLLLLBO.....",
		".....OBLLLBO.......",
		"......OBBBO........",
		".......OOO.........",
	]
	_draw_pattern(pattern, 6, 8, g, p)


func _draw_zigzag(g: float, p: Dictionary) -> void:
	# 蛇形 S
	var pattern := [
		".....OOOOOOO....",
		"....OBBHHHHBO...",
		"...OBHLLLLLBO...",
		"..OBHLLLOLLBO...",
		"..OBHLLLLLBO....",
		"...OBBBLLBO.....",
		".....OBLBO......",
		"....OBLLBO......",
		"...OBLLBO.......",
		"..OBLLBO........",
		"..OBLBOOO.......",
		"..OBLLLBO.......",
		"...OBLLBO.......",
		"....OBBBO.......",
		".....OOOO.......",
	]
	_draw_pattern(pattern, 8, 8, g, p)


func _draw_flame(g: float, p: Dictionary) -> void:
	var pattern := [
		".......O.......",
		"......OBO......",
		".....OBHBO.....",
		"....OBHHHBO....",
		"...OBHHLHHBO...",
		"...OBHLLLHBO...",
		"..OBHLLLLLHBO..",
		"..OBHLLLLLLBO..",
		".OBHLLLLLLLBBO.",
		".OBHLLLLLLLLBO.",
		"OBHLLLLLLLLLLBO",
		"OBLLLLLLLLLLLBO",
		"OBLLLLBLLLBLLBO",
		"OBLLLOOOOOLLLBO",
		".OBBOOOOOOOBBO.",
		".OOO.......OOO.",
	]
	_draw_pattern(pattern, 9, 8, g, p)


func _draw_humanoid(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OOOO......",
		".....OBHHBO.....",
		"....OBHHLLBO....",
		"....OBHLLLBO....",
		".....OBBBBO.....",
		"......OBBO......",
		"....OOBLLBOO....",
		"...OBLLBBLLBO...",
		"..OBLLLBBLLLBO..",
		"..OBLLLBBLLLBO..",
		"..OBLLOBBOLLBO..",
		"...OBOOBBOOBO...",
		"....OOBLLBOO....",
		"......OBBO......",
		".....OBO.OBO....",
		".....OO...OO....",
	]
	_draw_pattern(pattern, 8, 8, g, p)


# 连击：星 / 多角
func _draw_combo(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("black_hole") >= 0:
		_draw_orb(g, p)  # 复用球（黑洞视觉）
	elif card_id.find("fireball") >= 0:
		_draw_flame(g, p)
	elif card_id.find("water") >= 0 or card_id.find("tornado") >= 0:
		_draw_tornado(g, p)
	elif card_id.find("thunder") >= 0:
		_draw_lightning(g, p)
	elif card_id.find("blade") >= 0 or card_id.find("storm") >= 0:
		_draw_sword(g, p)
	else:
		_draw_star(g, p)


func _draw_star(g: float, p: Dictionary) -> void:
	var pattern := [
		".........O.........",
		"........OBO........",
		".......OBHBO.......",
		".......OBLBO.......",
		"......OBHLLBO......",
		"......OBLLLBO......",
		"OOOOOOBHLLLLBOOOOOO",
		".OBBBBBLLLLLLBBBBO.",
		"..OBHHLLLLLLLLLBO..",
		"...OBHHLLLLLLBBO...",
		"....OBHLLLLLBO.....",
		"....OBLLLLLBO......",
		"...OBHLBOLLLBO.....",
		"..OBHLBO.OBLLBO....",
		".OBHLBO...OBLLBO...",
		"OBHLBO.....OBLLBO..",
		"OBBO.........OBBO..",
		"OO............OO...",
	]
	_draw_pattern(pattern, 6, 7, g, p)


func _draw_tornado(g: float, p: Dictionary) -> void:
	var pattern := [
		".OOOOOOOOOOOOO.",
		"OBBBBBBBBBBBBBO",
		"OBHHHHHHHHHHHBO",
		"OBHLLLLLLLLLHBO",
		".OBHLLLLLLLHBO.",
		"..OBHLLLLLHBO..",
		"...OBHLLLHBO...",
		"....OBHLHBO....",
		".....OBHBO.....",
		".....OBLBO.....",
		"....OBLLLBO....",
		"...OBHLLLLBO...",
		"...OBHLLLLBO...",
		"....OBBBBBO....",
		".....OOOOO.....",
	]
	_draw_pattern(pattern, 9, 8, g, p)


func _draw_question(g: float, p: Dictionary) -> void:
	var pattern := [
		"....OOOOOOOO....",
		"...OBBBBBBBBO...",
		"..OBHHHHLLLLBO..",
		"..OBHHO..OLLBO..",
		"..OBBBO..OBBBO..",
		".........OBBO...",
		"........OBLBO...",
		".......OBLLBO...",
		".......OBLBO....",
		"......OBLBO.....",
		"......OBLBO.....",
		"......OBBO......",
		"......OBO.......",
		"................",
		"......OOO.......",
		"......OBO.......",
		"......OBO.......",
		"......OOO.......",
	]
	_draw_pattern(pattern, 8, 7, g, p)


# ============= 主题关：恶魔（demon_*）/ 天使（angel_*） =============

func _draw_demon(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("scythe") >= 0:
		_draw_scythe(g, p)
	elif card_id.find("sulfur_laser") >= 0:
		_draw_laser_beam(g, p)
	elif card_id.find("baby") >= 0:
		_draw_demon_baby(g, p)
	elif card_id.find("nine_lives") >= 0:
		_draw_cat_head(g, p)
	elif card_id.find("vampire") >= 0:
		_draw_blood_drop(g, p)
	elif card_id.find("blood_blade") >= 0:
		_draw_flying_dagger(g, p)
	else:
		_draw_pentagram(g, p)


func _draw_angel(card_id: String, g: float, p: Dictionary) -> void:
	if card_id.find("holy_bullet") >= 0:
		_draw_light_pillar(g, p)
	elif card_id.find("light_ward") >= 0:
		_draw_shield_cross(g, p)
	elif card_id.find("baby") >= 0:
		_draw_angel_baby(g, p)
	elif card_id.find("fate_spear") >= 0:
		_draw_spear(g, p)
	elif card_id.find("proximity_slow") >= 0:
		_draw_aura_rings(g, p)
	else:
		_draw_halo(g, p)


# ---- 死神镰刀：饱满弧形刀刃 + 长杆 ----
func _draw_scythe(g: float, p: Dictionary) -> void:
	var pattern := [
		"...OOOOOOOOOO....",
		"..OBBBBBBBBBBO...",
		".OBHHHHLLLLBBBO..",
		"OBHLLLLLLLLBBBBO.",
		"OBHLLLLLLLBBBBBO.",
		"OBLLLLLLBBBBBBO..",
		"OBLLLLBBBBBBO....",
		".OBLBBBBBBO......",
		"..OOBBBBOO.......",
		".....OBO.........",
		".....OBO.........",
		".....OBO.........",
		"....OBHBO........",
		"....OBHBO........",
		"....OBHBO........",
		"....OBHBO........",
		"....OBHBO........",
		"....OBLBO........",
		"....OBLBO........",
		".....OOO.........",
	]
	_draw_pattern(pattern, 7, 6, g, p)


# ---- 硫磺火：地狱火球 / 红色太阳 ----
func _draw_laser_beam(g: float, p: Dictionary) -> void:
	var pattern := [
		".......OOOO.......",
		".....OOBBBBOO.....",
		"....OBHHLLLLBBO...",
		"...OBHHLLLLLBBBO..",
		"..OBHLLLLLLLLBBBO.",
		"..OBHLLLLLLLLLBBO.",
		".OBHLLLLOOOLLLBBO.",
		".OBLLLLOHHLOLLBBO.",
		".OBLLLLOHHLOLLBBO.",
		".OBLLLLLOOLLLBBBO.",
		"..OBLLLLLLLLLBBBO.",
		"..OBLLLLLLLLBBBO..",
		"...OBBLLLLLBBBBO..",
		"....OBBBBBBBBBO...",
		".....OOBBBBBOO....",
		".......OOOO.......",
	]
	_draw_pattern(pattern, 7, 8, g, p)


# ---- 恶魔宝宝：双角矮胖小恶魔 ----
func _draw_demon_baby(g: float, p: Dictionary) -> void:
	var pattern := [
		"..OO........OO..",
		".OBHO......OBHO.",
		".OBHO......OBHO.",
		"OBHHOOOOOOOOBHHO",
		"OBHHHHHHHHHHHHBO",
		"OBHLLLLLLLLLLLBO",
		"OBHLLOOLLLLOOLBO",
		"OBHLOHHOLLOHHOLO",
		"OBLLOHHOLLOHHOLO",
		"OBLLLOOLLLLOOLBO",
		"OBLLLLLLLLLLLLBO",
		"OBLLLLOLLLOLLLBO",
		"OBLLLLOOOOOLLLBO",
		".OBBBBBBBBBBBBO.",
		"..OBLLLLLLLLBO..",
		"..OBLLLLLLLLBO..",
		"...OBLLBLLBBO...",
		"...OBBO.OBBO....",
		"...OOO..OOO.....",
	]
	_draw_pattern(pattern, 8, 6, g, p)


# ---- 九命猫：尖耳猫头 + 圆脸 + 大眼 ----
func _draw_cat_head(g: float, p: Dictionary) -> void:
	var pattern := [
		"OOO..........OOO",
		"OBHO........OBHO",
		"OBHHO......OBHHO",
		"OBHHHO....OBHHHO",
		"OBHHHHOOOOBHHHHO",
		"OBHHHHHHHHHHHHBO",
		"OBHLLLLLLLLLLLBO",
		"OBHLLLLLLLLLLLBO",
		".OBLOOLLLLLOOLBO",
		"OBLLOHHOLLOHHOLBO",
		"OBLLLOOLLLLOOLLBO",
		"OBLLLLLLOLLLLLLBO",
		"OBLLLLLOOOLLLLLBO",
		"OBLLLLOLOLLLLLLBO",
		".OBLLLLOLLLLLLBO.",
		".OBBLLLLLLLLLBBO.",
		"..OOBBBBBBBBBBOO.",
		"....OOOOOOOOOO...",
	]
	_draw_pattern(pattern, 7, 7, g, p)


# ---- 嗜血：饱满大血滴 ----
func _draw_blood_drop(g: float, p: Dictionary) -> void:
	var pattern := [
		".......OO.......",
		".......OBO......",
		"......OBHO......",
		"......OBHBO.....",
		".....OBHHHBO....",
		".....OBHHHBO....",
		"....OBHHLLLBO...",
		"....OBHLLLLBO...",
		"...OBHLLLLLLBO..",
		"...OBHLLLLLLBO..",
		"..OBHLLLLLLLLBO.",
		"..OBHLLLLLLLLBO.",
		".OBHLLLLLLLLLLBO",
		".OBHLLLLLLLLLLBO",
		".OBLLLLLLLLLLLBO",
		"..OBBLLLLLLLBBO.",
		"...OBBBBBBBBBO..",
		"....OOOOOOOOO...",
	]
	_draw_pattern(pattern, 8, 7, g, p)


# ---- 血飞刀：斜向弯刃飞刀 ----
func _draw_flying_dagger(g: float, p: Dictionary) -> void:
	var pattern := [
		"OOO.............",
		"OBBO............",
		"OBHBO...........",
		".OBHBO..........",
		".OBHLBO.........",
		"..OBHLBO........",
		"..OBHLLBO.......",
		"...OBHLLBO......",
		"....OBHLLBO.....",
		"....OBHHLLBO....",
		".....OBHHLLBO...",
		"......OBHHLLBO..",
		".......OBHHLLBO.",
		"........OBHHLBO.",
		".........OBHLBO.",
		"..........OBLBO.",
		"...........OBBO.",
		"...........OBO..",
		"...........OO...",
	]
	_draw_pattern(pattern, 8, 7, g, p)


# ---- 默认恶魔图案：五芒星（实心填充）----
func _draw_pentagram(g: float, p: Dictionary) -> void:
	var pattern := [
		".........OO.........",
		"........OBHO........",
		"........OBHO........",
		".......OBHHBO.......",
		".......OBHHBO.......",
		"OOOOOOOOBHLLBOOOOOOO",
		"OBBBBBBBHLLLLBBBBBBO",
		".OBHLLLLLLLLLLLLLBO.",
		"..OBHLLLLLLLLLLLBO..",
		"...OBHLLLLLLLLLBO...",
		"....OBHLLLLLLLBO....",
		".....OBHLLLLLBO.....",
		"....OBHLLLLLLLBO....",
		"....OBHLLBOBLLBO....",
		"...OBHLLBO.OBLLBO...",
		"..OBHLLBO...OBLLBO..",
		".OBHLLBO.....OBLLBO.",
		"OBBBBBO.......OBBBBO",
		"OOOOO...........OOOO",
	]
	_draw_pattern(pattern, 6, 7, g, p)


# ---- 圣光弹：饱满光柱 + 顶部光点 ----
func _draw_light_pillar(g: float, p: Dictionary) -> void:
	var pattern := [
		".......OO.......",
		".......OBO......",
		"......OBHO......",
		"......OBHBO.....",
		"......OBHBO.....",
		".....OBHHBO.....",
		".....OBHHBO.....",
		"....OBHHHBBO....",
		"....OBHHLLBO....",
		"...OBHHLLLBBO...",
		"...OBHLLLLLBO...",
		"..OBHHLLLLLBBO..",
		"..OBHLLLLLLLBO..",
		".OBHHLLLLLLLBBO.",
		".OBHLLLLLLLLLBO.",
		"OBHHLLLLLLLLLBBO",
		"OBHLLLLLLLLLLLBO",
		"OBLLLLLLLLLLLLBO",
		".OBBBBBBBBBBBBO.",
		"..OOOOOOOOOOOO..",
	]
	_draw_pattern(pattern, 8, 6, g, p)


# ---- 圣盾：盾形 + 实心十字浮雕 ----
func _draw_shield_cross(g: float, p: Dictionary) -> void:
	var pattern := [
		"..OOOOOOOOOOOO..",
		".OBBBBBBBBBBBBO.",
		"OBHHHHHHHHHHHHBO",
		"OBHLLLLLLLLLLHBO",
		"OBHLLLOHHOLLLHBO",
		"OBHLLLOHHOLLLHBO",
		"OBHLLLOHHOLLLHBO",
		"OBHLOOOHHOOOLHBO",
		"OBHLOHHHHHHOLHBO",
		"OBHLOOOHHOOOLHBO",
		"OBHLLLOHHOLLLHBO",
		"OBHLLLOHHOLLLHBO",
		"OBHLLLLLLLLLLHBO",
		".OBHLLLLLLLLLBBO",
		".OBHHLLLLLLLBBO.",
		"..OBHHLLLLLBBO..",
		"...OBHHLLLBBO...",
		"....OBHHLBBO....",
		".....OBHBBO.....",
		"......OBBO......",
		".......OO.......",
	]
	_draw_pattern(pattern, 8, 5, g, p)


# ---- 天使宝宝：圆头 + 双翼 + 头顶光环 ----
func _draw_angel_baby(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OOOOOO......",
		".....OBHHHHHBO....",
		".....OBLLLLLBO....",
		"......OOOOOO......",
		"....OOOOOOOOOO....",
		"...OBHHHHHHHHBO...",
		"..OBHLLLLLLLLLBO..",
		"..OBHLOHOLLOHOLBO.",
		"..OBHLOHOLLOHOLBO.",
		"..OBHLLLLLLLLLLBO.",
		"..OBHLLLLOOLLLLBO.",
		"..OBHLLLLLLLLLLBO.",
		"...OBLLLLLLLLLBO..",
		"....OBBBBBBBBBO...",
		"OOO..OBHLLLLBO..OOO",
		"OBHO.OBHLLLLBO.OBHO",
		"OBHHBOBHLLLLBOBHHBO",
		"OBHHHBOBLLLLBOBHHHBO",
		".OBHHBO.OBBO.OBHHBO.",
		"..OBHBO..OO..OBHBO..",
		"...OBO........OBO...",
	]
	_draw_pattern(pattern, 7, 5, g, p)


# ---- 命运之矛：菱形矛尖 + 中段宝石 + 长柄 ----
func _draw_spear(g: float, p: Dictionary) -> void:
	var pattern := [
		"......OO......",
		"......OBO.....",
		".....OBHBO....",
		".....OBHBO....",
		"....OBHHHBO...",
		"....OBHHHBO...",
		"...OBHHHLLBO..",
		"...OBHHLLLBO..",
		"....OBHLLBO...",
		".....OBLBO....",
		".....OBLBO....",
		"....OOBLBOO...",
		"...OBHHBLHHBO.",
		"....OOBLBOO...",
		".....OBLBO....",
		".....OBLBO....",
		".....OBLBO....",
		".....OBLBO....",
		".....OBLBO....",
		".....OBLBO....",
		"....OBHHHBO...",
		".....OOOO.....",
	]
	_draw_pattern(pattern, 9, 5, g, p)


# ---- 减速光环：实心同心圆 + 中心点 ----
func _draw_aura_rings(g: float, p: Dictionary) -> void:
	var pattern := [
		".....OOOOOOOOO.....",
		"...OOBBBBBBBBBOO...",
		"..OBHHHHHHHHHHHBO..",
		".OBHLLLLLLLLLLLHBO.",
		"OBHLLOOOOOOOOOLLHBO",
		"OBLLOBBBBBBBBOLLLBO",
		"OBLOBHHHHHHHHBOLLBO",
		"OBLOBHLLLLLLLHBOLBO",
		"OBLOBHLOOOOOLHBOLBO",
		"OBLOBHLOHHHOLHBOLBO",
		"OBLOBHLOOOOOLHBOLBO",
		"OBLOBHLLLLLLLHBOLBO",
		"OBLOBHHHHHHHHBOLLBO",
		"OBLLOBBBBBBBBOLLLBO",
		"OBHLLOOOOOOOOOLLHBO",
		".OBHLLLLLLLLLLLHBO.",
		"..OBHHHHHHHHHHHBO..",
		"...OOBBBBBBBBBOO...",
		".....OOOOOOOOO.....",
	]
	_draw_pattern(pattern, 6, 6, g, p)


# ---- 默认天使图案：实心光环（饱满圆环）----
func _draw_halo(g: float, p: Dictionary) -> void:
	var pattern := [
		"....OOOOOOOOOO....",
		"..OOBBBBBBBBBBOO..",
		".OBHHHHHHHHHHHHBO.",
		"OBHLLLLLLLLLLLLHBO",
		"OBHLLOOOOOOOOLLHBO",
		"OBHLOBBBBBBBBOLHBO",
		"OBHLOBBBBBBBBOLHBO",
		"OBHLOOOOOOOOOLLHBO",
		"OBHLLLLLLLLLLLLHBO",
		".OBHHHHHHHHHHHHBO.",
		"..OOBBBBBBBBBBOO..",
		"....OOOOOOOOOO....",
	]
	_draw_pattern(pattern, 7, 10, g, p)


# ============= 元素徽章：右下角 8×8 +1 px 描边 =============
func _draw_elem_badge(element: String, g: float) -> void:
	var pal: Dictionary = ELEM_PALETTE.get(element, {})
	if pal.is_empty():
		return
	# 原点 (22, 22) → 8×8
	var ox := 22
	var oy := 22
	# 底色圆角方
	for y in range(1, 7):
		for x in range(1, 7):
			_block(ox + x, oy + y, g, pal["dark"])
	# 边描线
	for x in range(0, 8):
		_block(ox + x, oy, g, pal["out"])
		_block(ox + x, oy + 7, g, pal["out"])
	for y in range(0, 8):
		_block(ox, oy + y, g, pal["out"])
		_block(ox + 7, oy + y, g, pal["out"])
	match element:
		"fire":
			var pat := [
				"..XX..",
				".XXXX.",
				"XXLLXX",
				"XLLLXX",
				".XLLX.",
				"..XX..",
			]
			_draw_elem_pat(pat, ox + 1, oy + 1, g, pal)
		"ice":
			var pat := [
				"..X...",
				"X.X.X.",
				".XXXX.",
				".XXXX.",
				"X.X.X.",
				"..X...",
			]
			_draw_elem_pat(pat, ox + 1, oy + 1, g, pal)
		"thunder":
			var pat := [
				".XXXX.",
				"...XX.",
				"..XXX.",
				".XXX..",
				".XX...",
				".XXXX.",
			]
			_draw_elem_pat(pat, ox + 1, oy + 1, g, pal)
		"poison":
			var pat := [
				"..XX..",
				"..XX..",
				".XLLX.",
				"XLLLLX",
				"XLLLLX",
				".XLLX.",
			]
			_draw_elem_pat(pat, ox + 1, oy + 1, g, pal)


func _draw_elem_pat(pat: Array, ox: int, oy: int, g: float, pal: Dictionary) -> void:
	for y in range(pat.size()):
		var row: String = pat[y]
		for x in range(row.length()):
			var ch := row[x]
			if ch == "X":
				_block(ox + x, oy + y, g, pal["hi"])
			elif ch == "L":
				_block(ox + x, oy + y, g, pal["light"])


# ============= 主体 pattern 绘制器 =============
# O=outline, B=base, L=light, H=hi (亮色), 其它 (.) 透明
func _draw_pattern(pat: Array, ox: int, oy: int, g: float, p: Dictionary) -> void:
	for y in range(pat.size()):
		var row: String = pat[y]
		for x in range(row.length()):
			var ch := row[x]
			match ch:
				"O":
					_block(ox + x, oy + y, g, p["out"])
				"B":
					_block(ox + x, oy + y, g, p["base"])
				"L":
					_block(ox + x, oy + y, g, p["light"])
				"H":
					_block(ox + x, oy + y, g, p["hi"])
				"D":
					_block(ox + x, oy + y, g, p["dark"])
