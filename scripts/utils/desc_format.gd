extends RefCounted
class_name DescFormat

# 把玩家面向描述里**带正负号**的 `[+-]数字%` 替换成绿/红箭头图标。
# 档位（按绝对值）：|n|<=10 → 1 个；10<|n|<=25 → 2 个；>25 → 3 个
# `+` → 绿 arrow_green.png；`-` → 红 arrow_red.png
# 没有正负号的百分比（"50%" "30%"）原样保留 — 那是阈值 / 概率类数字。
#
# 用法：`DescFormat.apply_to_rich_text(rt, text, base_font_size, center)`
# 内部直接调 RichTextLabel.add_text / add_image API（不走 BBCode），
# 多个箭头并排时合成到同一张 ImageTexture，texture_filter = NEAREST 保持像素 sharp。

const ARROW_GREEN_PATH := "res://assets/ui/icons/system/arrow_green.png"
const ARROW_RED_PATH := "res://assets/ui/icons/system/arrow_red.png"
const ARROW_GAP := 2          # 多个箭头并排时的像素间距
const ARROW_DISPLAY_SCALE := 1.0  # 显示高度 = base_font_size × 此倍率（≈ 跟文字同高）

static var _re: RegEx
static var _arrow_cache: Dictionary = {}   # key: "up_3" / "down_1" -> ImageTexture
static var _base_image_up: Image
static var _base_image_down: Image


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
	_ensure_base_images()
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


static func _ensure_base_images() -> void:
	if _base_image_up != null and _base_image_down != null:
		return
	var green_tex := load(ARROW_GREEN_PATH) as Texture2D
	var red_tex := load(ARROW_RED_PATH) as Texture2D
	_base_image_up = green_tex.get_image()
	_base_image_down = red_tex.get_image()
	# blit_rect 要求 src/dest 同格式，统一到 RGBA8
	for img in [_base_image_up, _base_image_down]:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)


static func _get_arrow_texture(is_down: bool, count: int) -> ImageTexture:
	var key := "%s_%d" % ["down" if is_down else "up", count]
	if _arrow_cache.has(key):
		return _arrow_cache[key]
	var base: Image = _base_image_down if is_down else _base_image_up
	var bw := base.get_width()
	var bh := base.get_height()
	var total_w := bw * count + ARROW_GAP * maxi(0, count - 1)
	var img := Image.create(total_w, bh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for k in count:
		var ox := k * (bw + ARROW_GAP)
		img.blit_rect(base, Rect2i(0, 0, bw, bh), Vector2i(ox, 0))
	var tex := ImageTexture.create_from_image(img)
	_arrow_cache[key] = tex
	return tex
