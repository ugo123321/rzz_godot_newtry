extends Control
class_name TalentPixelIcon

# 天赋卡 icon 的程序化像素绘制。
# 32×32 grid + 5 色阶 palette（out/dark/base/light/hi），参考 pixel_card_icon.gd 的手法。
# 7 张卡各自的图案硬编码在 _draw()：strength/hp/ki/ki_regen/crit_rate/crit_damage/move_speed。
#
# 用法：
#   var icon := TalentPixelIcon.new()
#   icon.talent_id = "strength"
#   icon.quality = 0
#   icon.icon_size = 96.0
#   container.add_child(icon)

@export var talent_id: String = ""
@export var quality: int = 0            # 0/1/2/3 (白/蓝/紫/橙) → palette 选色
@export var icon_size: float = 96.0
@export var locked: bool = false

const GRID := 32

# 每张卡一个 palette；locked 时另用灰色。
const CARD_PALETTES: Dictionary = {
	"strength":    {"hi": Color("#ffe0d0"), "light": Color("#ff8060"), "base": Color("#e04028"), "dark": Color("#7a1810"), "out": Color("#2a0808")},
	"hp":          {"hi": Color("#ffe0e8"), "light": Color("#ff90a8"), "base": Color("#e04068"), "dark": Color("#8a1838"), "out": Color("#2a0810")},
	"ki":          {"hi": Color("#e0ffec"), "light": Color("#60e090"), "base": Color("#20a848"), "dark": Color("#0a5820"), "out": Color("#082810")},
	"ki_regen":    {"hi": Color("#fff8d0"), "light": Color("#ffe060"), "base": Color("#f4b820"), "dark": Color("#8c6010"), "out": Color("#3c2808")},
	"crit_rate":   {"hi": Color("#fff8d0"), "light": Color("#ffd048"), "base": Color("#f08020"), "dark": Color("#a04010"), "out": Color("#380808")},
	"crit_damage": {"hi": Color("#ffe4c0"), "light": Color("#ffa848"), "base": Color("#e05820"), "dark": Color("#7a2810"), "out": Color("#280810")},
	"move_speed":  {"hi": Color("#e0f0ff"), "light": Color("#80c0ff"), "base": Color("#2870d8"), "dark": Color("#0a2870"), "out": Color("#080820")},
	# 新增白卡 2
	"range":       {"hi": Color("#e0ffe0"), "light": Color("#80d880"), "base": Color("#40a840"), "dark": Color("#186018"), "out": Color("#082808")},
	"atk_speed":   {"hi": Color("#fff8b8"), "light": Color("#ffe040"), "base": Color("#c89018"), "dark": Color("#6a4a08"), "out": Color("#2a1808")},
	# 新增紫卡 5
	"lethal_strike":     {"hi": Color("#ffd0d0"), "light": Color("#ff6060"), "base": Color("#c0102c"), "dark": Color("#600810"), "out": Color("#200404")},
	"lightning_dash":    {"hi": Color("#fff8d0"), "light": Color("#ffe040"), "base": Color("#5090ff"), "dark": Color("#1848a0"), "out": Color("#081438")},
	"meditation":        {"hi": Color("#f0e0ff"), "light": Color("#c090ff"), "base": Color("#8040c8"), "dark": Color("#3a1868"), "out": Color("#180820")},
	"super_enhance":     {"hi": Color("#ffe8c0"), "light": Color("#ffb840"), "base": Color("#e04020"), "dark": Color("#7a1810"), "out": Color("#280408")},
	"long_range_strike": {"hi": Color("#d8ffd0"), "light": Color("#80c060"), "base": Color("#408820"), "dark": Color("#1a4010"), "out": Color("#082004")},
	# 新增橙卡 6（unlock）—— 统一金橙色系为底 + 个别调色
	"unlock_first_reward":   {"hi": Color("#fff0c8"), "light": Color("#ffc848"), "base": Color("#e08820"), "dark": Color("#7a4810"), "out": Color("#281808")},
	"unlock_angel_stage":    {"hi": Color("#fffde0"), "light": Color("#ffe888"), "base": Color("#f0c848"), "dark": Color("#8c6820"), "out": Color("#382808")},
	"unlock_demon_stage":    {"hi": Color("#ffd0c8"), "light": Color("#ff6040"), "base": Color("#a02020"), "dark": Color("#480808"), "out": Color("#180404")},
	"unlock_forge_stage":    {"hi": Color("#fff0d0"), "light": Color("#c89060"), "base": Color("#805018"), "dark": Color("#402808"), "out": Color("#181008")},
	"unlock_mystery_portal": {"hi": Color("#f0d0ff"), "light": Color("#c060ff"), "base": Color("#8020c0"), "dark": Color("#3a0868"), "out": Color("#180420")},
	"unlock_elite_enemy":    {"hi": Color("#fff0c0"), "light": Color("#ffd020"), "base": Color("#e09818"), "dark": Color("#7a5008"), "out": Color("#281804")},
}

const LOCKED_PALETTE := {
	"hi": Color("#a0a8b0"), "light": Color("#7a828c"), "base": Color("#4a525c"), "dark": Color("#2a2f38"), "out": Color("#12141a"),
}


func set_talent(id: String, q: int) -> void:
	talent_id = id
	quality = q
	queue_redraw()


func set_locked(v: bool) -> void:
	locked = v
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var g: float = icon_size / float(GRID)
	var pal: Dictionary = LOCKED_PALETTE if locked else CARD_PALETTES.get(talent_id, LOCKED_PALETTE)
	# 圆形背景光晕（浅色）
	_draw_halo(g, pal)
	if locked:
		_draw_question(g, pal)
		return
	match talent_id:
		"strength":    _draw_fist(g, pal)
		"hp":          _draw_heart(g, pal)
		"ki":          _draw_ki_orb(g, pal)
		"ki_regen":    _draw_hourglass(g, pal)
		"crit_rate":   _draw_target(g, pal)
		"crit_damage": _draw_burst_sword(g, pal)
		"move_speed":  _draw_boot(g, pal)
		"range":       _draw_range(g, pal)
		"atk_speed":   _draw_atk_speed(g, pal)
		"lethal_strike":       _draw_lethal_strike(g, pal)
		"lightning_dash":      _draw_lightning_dash(g, pal)
		"meditation":          _draw_meditation(g, pal)
		"super_enhance":       _draw_super_enhance(g, pal)
		"long_range_strike":   _draw_long_range_strike(g, pal)
		"unlock_first_reward":   _draw_first_reward(g, pal)
		"unlock_angel_stage":    _draw_angel(g, pal)
		"unlock_demon_stage":    _draw_demon(g, pal)
		"unlock_forge_stage":    _draw_forge(g, pal)
		"unlock_mystery_portal": _draw_mystery(g, pal)
		"unlock_elite_enemy":    _draw_crown(g, pal)
		_:             _draw_question(g, pal)


func _block(x: int, y: int, g: float, color: Color) -> void:
	if x < 0 or x >= GRID or y < 0 or y >= GRID:
		return
	draw_rect(Rect2(float(x) * g, float(y) * g, g + 0.5, g + 0.5), color)


func _pat(pattern: Array, ox: int, oy: int, g: float, pal: Dictionary) -> void:
	# pattern: 每行字符串；O=out D=dark B=base L=light H=hi 空格=跳过
	for y in range(pattern.size()):
		var row: String = pattern[y]
		for x in range(row.length()):
			var ch := row[x]
			var col: Color
			match ch:
				"O": col = pal["out"]
				"D": col = pal["dark"]
				"B": col = pal["base"]
				"L": col = pal["light"]
				"H": col = pal["hi"]
				_: continue
			_block(ox + x, oy + y, g, col)


func _draw_halo(g: float, pal: Dictionary) -> void:
	var halo := Color(pal["light"].r, pal["light"].g, pal["light"].b, 0.28)
	var cx := 16
	var cy := 16
	var r := 13
	for y in range(GRID):
		for x in range(GRID):
			var dx := x - cx
			var dy := y - cy
			var d2 := dx * dx + dy * dy
			if d2 <= r * r and d2 >= (r - 2) * (r - 2):
				_block(x, y, g, halo)


func _draw_question(g: float, pal: Dictionary) -> void:
	var pattern := [
		"   OOOOO   ",
		"  OBBLLBBO ",
		" OBB   BBO ",
		"  OO   BBO ",
		"      OBBO ",
		"     OBBO  ",
		"    OBBO   ",
		"    OBO    ",
		"    OBO    ",
		"           ",
		"    OBO    ",
		"    OBO    ",
	]
	_pat(pattern, 10, 10, g, pal)


# 力量：拳头
func _draw_fist(g: float, pal: Dictionary) -> void:
	var pattern := [
		"   OOOOOO   ",
		"  ODDBBBBDO ",
		" ODBLLBBBBDO",
		" OBBLHLBBBDO",
		"OBBLLLLBBBBO",
		"OBBLLLLBBBBO",
		"ODBBBBBBBBDO",
		" OOBOBOBOBO ",
		"  OOBOBOBO  ",
		"   OOOOOO   ",
	]
	_pat(pattern, 10, 11, g, pal)


# 生命：心
func _draw_heart(g: float, pal: Dictionary) -> void:
	var pattern := [
		"  OOO  OOO  ",
		" OBBLOOBBLO ",
		"OBLLHOOLLBO ",
		"OBBLLBBLLBBO",
		"OBBBBBBBBBBO",
		" OBBBBBBBBO ",
		"  OBBBBBBO  ",
		"   OBBBBO   ",
		"    OBBO    ",
		"     OO     ",
	]
	_pat(pattern, 10, 11, g, pal)


# 气力：能量球
func _draw_ki_orb(g: float, pal: Dictionary) -> void:
	var pattern := [
		"    OOOO    ",
		"  OOBBBBOO  ",
		" OBBLLLLBBO ",
		"OBLLLHHLLBBO",
		"OBLLHHHHLLBO",
		"OBLLHHHHLLBO",
		"OBBLLLLLLBBO",
		" OBBBBBBBBO ",
		"  OOBBBBOO  ",
		"    OOOO    ",
	]
	_pat(pattern, 10, 11, g, pal)


# 回气：沙漏
func _draw_hourglass(g: float, pal: Dictionary) -> void:
	var pattern := [
		"OOOOOOOOOO",
		"OBBBBBBBBO",
		" OBLLLLBO ",
		"  OBLLBO  ",
		"   OBBO   ",
		"   OBBO   ",
		"  OBLLBO  ",
		" OBLHHLBO ",
		"OBBLHHLBBO",
		"OBBBBBBBBO",
		"OOOOOOOOOO",
	]
	_pat(pattern, 11, 11, g, pal)


# 暴击率：靶心
func _draw_target(g: float, pal: Dictionary) -> void:
	# 十字瞄准 + 中心
	var cx := 16
	var cy := 16
	var pal_out: Color = pal["out"]
	var pal_dark: Color = pal["dark"]
	var pal_base: Color = pal["base"]
	var pal_light: Color = pal["light"]
	var pal_hi: Color = pal["hi"]
	# 外圈
	for a in range(0, 360, 15):
		var rad := deg_to_rad(float(a))
		var x := cx + int(round(cos(rad) * 8.0))
		var y := cy + int(round(sin(rad) * 8.0))
		_block(x, y, g, pal_out)
	for a in range(0, 360, 12):
		var rad2 := deg_to_rad(float(a))
		var x2 := cx + int(round(cos(rad2) * 6.5))
		var y2 := cy + int(round(sin(rad2) * 6.5))
		_block(x2, y2, g, pal_base)
	# 中心十字
	for i in range(-4, 5):
		_block(cx + i, cy, g, pal_dark)
		_block(cx, cy + i, g, pal_dark)
	# 中央填充
	var center_pat := [
		" HH ",
		"HLLH",
		"HLLH",
		" HH ",
	]
	_pat(center_pat, cx - 2, cy - 2, g, pal)
	# 四角箭头
	_block(cx - 8, cy, g, pal_light)
	_block(cx + 8, cy, g, pal_light)
	_block(cx, cy - 8, g, pal_light)
	_block(cx, cy + 8, g, pal_light)


# 暴伤：剑 + 冲击波
func _draw_burst_sword(g: float, pal: Dictionary) -> void:
	# 斜剑
	var pattern := [
		"        HL",
		"       HLB",
		"      HLBO",
		"     HLBO ",
		"    HLBO  ",
		"   HLBO   ",
		"  HLBO    ",
		" HLBO     ",
		"OLBO      ",
		"OBO       ",
		"OO        ",
	]
	_pat(pattern, 12, 10, g, pal)
	# 剑柄十字
	_block(11, 21, g, pal["dark"])
	_block(12, 21, g, pal["dark"])
	_block(13, 21, g, pal["dark"])
	# 冲击波（右下爆点）
	var bx := 22
	var by := 12
	for dx in [-2, -1, 0, 1, 2]:
		for dy in [-2, -1, 0, 1, 2]:
			var d := absi(dx) + absi(dy)
			if d == 2:
				_block(bx + dx, by + dy, g, pal["hi"])
			elif d == 3:
				_block(bx + dx, by + dy, g, pal["light"])


# 移速：靴 + 速度线
func _draw_boot(g: float, pal: Dictionary) -> void:
	var pattern := [
		"    OOOO   ",
		"    OBBBO  ",
		"    OBLBO  ",
		"    OBLBO  ",
		"    OBLBO  ",
		"    OBBBO  ",
		"    OBBBOOO",
		"OOOOBBLLLBO",
		"OBBBLLHHHLO",
		"OBLLLHHLLBO",
		"OOOOOOOOOOO",
	]
	_pat(pattern, 8, 10, g, pal)
	# 速度线（左侧 3 条）
	_block(5, 12, g, pal["light"])
	_block(4, 12, g, pal["light"])
	_block(3, 12, g, pal["light"])
	_block(6, 15, g, pal["light"])
	_block(5, 15, g, pal["light"])
	_block(4, 15, g, pal["light"])
	_block(5, 18, g, pal["light"])
	_block(4, 18, g, pal["light"])
	_block(3, 18, g, pal["light"])


# 射程：弓箭
func _draw_range(g: float, pal: Dictionary) -> void:
	# 弓 + 箭 组合（斜对角线）
	var pattern := [
		"        HL",
		"       HLB",
		"      HLBO",
		"     HLBO ",
		"    HLBO  ",
		"   HLBO   ",
		"  HLBO    ",
		" HLBO     ",
		"OLBO      ",
		"OBO       ",
		"OO        ",
	]
	_pat(pattern, 12, 10, g, pal)
	# 弓弧（左下）
	var bow := [
		"  OO ",
		" OBBO",
		"OBBLO",
		"OBLO ",
		"OBLO ",
		"OBBLO",
		" OBBO",
		"  OO ",
	]
	_pat(bow, 6, 12, g, pal)


# 攻速：竖向闪电 + 速度线
func _draw_atk_speed(g: float, pal: Dictionary) -> void:
	var pattern := [
		"     HLL   ",
		"    HLLBO  ",
		"   HLLBO   ",
		"  HLBBO    ",
		"HLBBOOOO   ",
		" LBBBBO    ",
		"  OBBBLO   ",
		"    OLLO   ",
		"    OLO    ",
		"    OLO    ",
		"     OO    ",
	]
	_pat(pattern, 10, 10, g, pal)
	# 左右速度线（3 对）
	for i in [11, 15, 19]:
		_block(4, i, g, pal["light"])
		_block(5, i, g, pal["light"])
		_block(6, i, g, pal["light"])


# 致命一击：十字准心 + 血滴
func _draw_lethal_strike(g: float, pal: Dictionary) -> void:
	var cx := 16
	var cy := 15
	# 圆圈瞄准（8 段）
	for a in range(0, 360, 22):
		var rad := deg_to_rad(float(a))
		var x := cx + int(round(cos(rad) * 7.0))
		var y := cy + int(round(sin(rad) * 7.0))
		_block(x, y, g, pal["out"])
		_block(x, y - 1 if a > 180 else y + 1, g, pal["dark"])
	# 十字瞄准
	for i in range(-6, 7):
		if absi(i) > 2:
			_block(cx + i, cy, g, pal["base"])
			_block(cx, cy + i, g, pal["base"])
	# 中心红点
	_pat(["HH", "HH"], cx - 1, cy - 1, g, pal)
	# 血滴（右下角）
	var drop := [
		"OO ",
		"OBO",
		"OBLO",
		"OBLO",
		" OO ",
	]
	_pat(drop, 22, 22, g, pal)


# 电光石火：闪电靴
func _draw_lightning_dash(g: float, pal: Dictionary) -> void:
	# 靴子（下）
	var boot := [
		"    OOOO   ",
		"    OBBBO  ",
		"    OBLBO  ",
		"    OBLBO  ",
		"    OBBBOOO",
		"OOOOBBLLLBO",
		"OBBBLLHHHLO",
		"OOOOOOOOOOO",
	]
	_pat(boot, 8, 15, g, pal)
	# 闪电 zig-zag（上部）
	var lightning := [
		"   HL ",
		"  HLB ",
		" HLB  ",
		"HLBB  ",
		" LBBHL",
		"  BBLL",
		"   BLL",
		"    LL",
	]
	_pat(lightning, 14, 5, g, pal)


# 冥想：打坐（简化：气流圆环 + 中心人形）
func _draw_meditation(g: float, pal: Dictionary) -> void:
	# 中心人形（打坐轮廓）
	var monk := [
		"   OOOO   ",
		"  OBBBBO  ",
		"  OBLLBO  ",
		"   OBBO   ",
		"  OBBBBO  ",
		" OBBLLBBO ",
		"OBBLHHLBBO",
		"OBBBBBBBBO",
		" OOOOOOOO ",
	]
	_pat(monk, 11, 12, g, pal)
	# 气流圆环（左右点缀）
	for y in [11, 15, 19]:
		_block(5, y, g, pal["light"])
		_block(4, y - 1, g, pal["light"])
		_block(4, y + 1, g, pal["light"])
		_block(26, y, g, pal["light"])
		_block(27, y - 1, g, pal["light"])
		_block(27, y + 1, g, pal["light"])


# 超级强化：拳头 + 心（两层叠加）
func _draw_super_enhance(g: float, pal: Dictionary) -> void:
	# 拳（左半）
	var fist := [
		"  OOOO  ",
		" ODBBBDO",
		"ODBLLBBDO",
		"ODBLHLBBO",
		"OBBLLBBBO",
		"ODBBBBBDO",
		" OOOOOOO",
	]
	_pat(fist, 5, 13, g, pal)
	# 心（右半，重叠）
	var heart := [
		"OO OO",
		"OLOLO",
		"OLLLO",
		"OLLLO",
		" OLO ",
		"  O  ",
	]
	_pat(heart, 19, 12, g, pal)


# 远程打击：弓 + 箭头（合体）
func _draw_long_range_strike(g: float, pal: Dictionary) -> void:
	# 弓 (左)
	var bow := [
		"  OO ",
		" OBBO",
		"OBBLO",
		"OBLLO",
		"OBLO ",
		"OBLO ",
		"OBLLO",
		"OBBLO",
		" OBBO",
		"  OO ",
	]
	_pat(bow, 5, 11, g, pal)
	# 箭（水平飞行）
	var arrow := [
		"         HL",
		"        HLB",
		"OOOOOOOOOLBO",
		"OBBBBBBBBLBO",
		"OOOOOOOOOLBO",
		"        HLB",
		"         HL",
	]
	_pat(arrow, 11, 14, g, pal)


# 先发制人：礼盒
func _draw_first_reward(g: float, pal: Dictionary) -> void:
	# 盒盖
	var lid := [
		"OOOOOOOOOO",
		"OBBBBBBBBO",
		"OBLLLLLLLO",
		"OBBBBBBBBO",
		"OOOOOOOOOO",
	]
	_pat(lid, 11, 10, g, pal)
	# 盒身
	var body := [
		"OBBBBBBBBO",
		"OBLLLLLLLO",
		"OBLLLLLLLO",
		"OBLLLLLLLO",
		"OBLLLLLLLO",
		"OOOOOOOOOO",
	]
	_pat(body, 11, 15, g, pal)
	# 蝴蝶结（中间竖带）
	for y in range(10, 21):
		_block(15, y, g, pal["dark"])
		_block(16, y, g, pal["dark"])
	# 蝴蝶结 loops
	_pat(["OHO", "HLH", "OHO"], 12, 8, g, pal)
	_pat(["OHO", "HLH", "OHO"], 18, 8, g, pal)


# 天使关：天使翅膀（左右对称）
func _draw_angel(g: float, pal: Dictionary) -> void:
	# 左翅膀
	var lwing := [
		"    O    ",
		"   OBO   ",
		"  OBLBO  ",
		" OBLLLBO ",
		"OBLLHHLBO",
		" OBLHLBO ",
		"  OBLBO  ",
		"   OBO   ",
		"    O    ",
	]
	_pat(lwing, 6, 12, g, pal)
	# 右翅膀（镜像 = 相同 pattern，往右挪）
	_pat(lwing, 18, 12, g, pal)
	# 中央光晕（圆点）
	_pat([" HH ", "HHHH", "HHHH", " HH "], 14, 8, g, pal)


# 恶魔关：恶魔角（骷髅顶两只角）
func _draw_demon(g: float, pal: Dictionary) -> void:
	# 左右角
	_pat(["OB ", "OBO", "OLO", " OO"], 8, 8, g, pal)
	_pat([" BO", "OBO", "OLO", "OO "], 22, 8, g, pal)
	# 骷髅头
	var skull := [
		"  OOOOOO  ",
		" OBBBBBBBO",
		"OBLLLLLLBBO",
		"OBLOOLLOOLBO",
		"OBLOBLLBOOLBO",
		"OBLLLLLLLLBO",
		" OBLLOOLLBO ",
		"  OBBBBBBO  ",
		"   OOOOOO   ",
	]
	_pat(skull, 11, 12, g, pal)


# 属性打造关：铁砧 + 锤
func _draw_forge(g: float, pal: Dictionary) -> void:
	# 铁砧（下）
	var anvil := [
		"OOOOOOOOOOOO",
		"OBBBBBBBBBBBO",
		"OBLLLLLLLLLLO",
		"OOOOBBBBBBOOO",
		"   OBBBBBO   ",
		"   OBBBBBO   ",
		"  OOBBBBBOO  ",
		"OOOOOOOOOOOOO",
	]
	_pat(anvil, 9, 16, g, pal)
	# 锤头（右上斜）
	var hammer := [
		"OOOOO ",
		"OBBLO ",
		"OBLLO ",
		"OBBLO ",
		"OOOBO ",
		"  OBO ",
		"   OBO",
		"    OB",
	]
	_pat(hammer, 16, 6, g, pal)


# 神秘大奖：旋涡 + "?"
func _draw_mystery(g: float, pal: Dictionary) -> void:
	# 旋涡（同心圆 spiral）
	var cx := 16
	var cy := 16
	# 外圈
	for a in range(0, 360, 20):
		var rad := deg_to_rad(float(a))
		_block(cx + int(round(cos(rad) * 9.0)), cy + int(round(sin(rad) * 9.0)), g, pal["out"])
	for a in range(0, 360, 18):
		var rad2 := deg_to_rad(float(a))
		_block(cx + int(round(cos(rad2) * 7.0)), cy + int(round(sin(rad2) * 7.0)), g, pal["base"])
	for a in range(0, 360, 20):
		var rad3 := deg_to_rad(float(a) + 30.0)
		_block(cx + int(round(cos(rad3) * 5.0)), cy + int(round(sin(rad3) * 5.0)), g, pal["light"])
	# 中心 "?"
	var q := [
		" OOO ",
		"OBBBO",
		"OB OB",
		"  OB ",
		"  OB ",
		"     ",
		"  OB ",
	]
	_pat(q, cx - 2, cy - 3, g, pal)


# 精英化：皇冠
func _draw_crown(g: float, pal: Dictionary) -> void:
	# 3 尖皇冠
	var pattern := [
		"O   O   O",
		"OBO OBO OBO",
		"OBHOBHOBHO",
		"OBBBBBBBBBO",
		"OBLLLLLLLBO",
		"OBLHHHHHLBO",
		"OBLLLLLLLBO",
		"OOOOOOOOOOO",
	]
	_pat(pattern, 10, 12, g, pal)
	# 中央宝石
	_pat(["HH", "HH"], 15, 17, g, pal)
