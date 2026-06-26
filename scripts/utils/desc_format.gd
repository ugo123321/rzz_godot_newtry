extends RefCounted
class_name DescFormat

# 把玩家面向描述里**带正负号**的 `[+-]数字%` 替换成绿/红像素箭头。
# 档位（按绝对值）：|n|<=10 → 1 个；10<|n|<=25 → 2 个；>25 → 3 个
# `+` → 绿 ▲（#5fd96c）；`-` → 红 ▼（#ef5b5b）
# 没有正负号的百分比（"50%" "30%"）原样保留 — 那是阈值 / 概率类数字。
#
# 用法：`DescFormat.apply_to_rich_text(rt, text, base_font_size, center)`
# 内部直接调 RichTextLabel.add_text / add_image API（不走 BBCode），
# 像素箭头用 Image.set_pixel 手绘 + 算法描边，缓存为 ImageTexture，
# RichTextLabel.texture_filter = NEAREST 保持像素 sharp 放大。

const COLOR_UP := Color("#22ee44")     # 鲜艳荧光绿
const COLOR_UP_OUTLINE := Color.BLACK
const COLOR_DOWN := Color("#ff2a2a")    # 鲜艳警示红
const COLOR_DOWN_OUTLINE := Color.BLACK
const ARROW_GAP := 2   # 多个箭头并排时之间的像素间距（留一点让黑描边间隔分明）
const ARROW_PAD := 1   # 每个箭头四周给算法描边留的空隙（保证左右两端的描边也能画上）
const ARROW_DISPLAY_SCALE := 1.0  # 显示高度 = base_font_size × 此倍率（≈ 跟文字同高）

# 9×9 实心箭头（X = 主色，. = 透明）。描边由算法在主色外侧自动加 1 像素黑边。
# 比上一版三角 11→9、柄宽 5→3、高度 11→9，整体更瘦更短，不会比文字高。
const UP_PATTERN: Array = [
	"....X....",
	"...XXX...",
	"..XXXXX..",
	".XXXXXXX.",
	"XXXXXXXXX",
	"...XXX...",
	"...XXX...",
	"...XXX...",
	"...XXX...",
]

const DOWN_PATTERN: Array = [
	"...XXX...",
	"...XXX...",
	"...XXX...",
	"...XXX...",
	"XXXXXXXXX",
	".XXXXXXX.",
	"..XXXXX..",
	"...XXX...",
	"....X....",
]

static var _re: RegEx
static var _arrow_cache: Dictionary = {}  # key: "up_3" / "down_1" -> ImageTexture


static func _ensure_regex() -> void:
	if _re != null:
		return
	_re = RegEx.new()
	# 必须带 + 或 - 号才匹配（裸百分比如 "50%" / "30%" 不动）
	_re.compile("([+-])(\\d+(?:\\.\\d+)?)%")


# 把 raw_text 应用到 RichTextLabel：clear → push_paragraph → 逐 token push add_text / add_image
# rt 调用前应已存在；不强依赖 bbcode_enabled（API 路径不走 BBCode 解析）
static func apply_to_rich_text(rt: RichTextLabel, raw_text: String, base_font_size: int, center: bool = true) -> void:
	if rt == null:
		return
	rt.clear()
	rt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if center:
		rt.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_ensure_regex()
	var cursor := 0
	var arrow_h := int(round(float(base_font_size) * ARROW_DISPLAY_SCALE))
	for m in _re.search_all(raw_text):
		if m.get_start() > cursor:
			rt.add_text(raw_text.substr(cursor, m.get_start() - cursor))
		var sign := m.get_string(1)
		var num := float(m.get_string(2))
		var count := _count_for(num)
		if count == 0:
			rt.add_text(raw_text.substr(m.get_start(), m.get_end() - m.get_start()))
		else:
			var tex := _get_arrow_texture(sign == "-", count)
			var aspect := float(tex.get_width()) / float(tex.get_height())
			var arrow_w := int(round(float(arrow_h) * aspect))
			rt.add_image(tex, arrow_w, arrow_h, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		cursor = m.get_end()
	if cursor < raw_text.length():
		rt.add_text(raw_text.substr(cursor))
	if center:
		rt.pop()


static func _count_for(num: float) -> int:
	if num <= 0.0:
		return 0
	if num > 25.0:
		return 3
	if num > 10.0:
		return 2
	return 1


static func _get_arrow_texture(is_down: bool, count: int) -> ImageTexture:
	var key := "%s_%d" % ["down" if is_down else "up", count]
	if _arrow_cache.has(key):
		return _arrow_cache[key]
	var tex := _build_arrow_texture(is_down, count)
	_arrow_cache[key] = tex
	return tex


static func _build_arrow_texture(is_down: bool, count: int) -> ImageTexture:
	var pattern: Array = DOWN_PATTERN if is_down else UP_PATTERN
	var main_color: Color = COLOR_DOWN if is_down else COLOR_UP
	var outline_color: Color = COLOR_DOWN_OUTLINE if is_down else COLOR_UP_OUTLINE
	var pattern_w: int = pattern[0].length()
	var pattern_h: int = pattern.size()
	# 每个箭头四周各留 ARROW_PAD 像素，让算法描边在边缘也能画一圈（修复并排箭头描边不一致问题）
	var per_arrow_w := pattern_w + ARROW_PAD * 2
	var per_arrow_h := pattern_h + ARROW_PAD * 2
	var total_w := per_arrow_w * count + ARROW_GAP * maxi(0, count - 1)
	var img := Image.create(total_w, per_arrow_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Pass 1: 填主色（pattern 内坐标 + pad 偏移）
	var main_pixels: Array = []
	for k in count:
		var ox := k * (per_arrow_w + ARROW_GAP)
		for row in pattern_h:
			var row_str: String = pattern[row]
			for col in pattern_w:
				if row_str.substr(col, 1) == "X":
					var px := ox + ARROW_PAD + col
					var py := ARROW_PAD + row
					img.set_pixel(px, py, main_color)
					main_pixels.append(Vector2i(px, py))

	# Pass 2: 描边（透明且四邻有主色 → 填 outline）
	var dirs := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for px in main_pixels:
		for d in dirs:
			var nx: int = px.x + d.x
			var ny: int = px.y + d.y
			if nx < 0 or nx >= total_w or ny < 0 or ny >= per_arrow_h:
				continue
			if img.get_pixel(nx, ny).a < 0.01:
				img.set_pixel(nx, ny, outline_color)

	return ImageTexture.create_from_image(img)
