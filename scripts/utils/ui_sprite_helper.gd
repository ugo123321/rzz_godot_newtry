class_name UiSpriteHelper
extends RefCounted

## Franuka RPG UI 图集（1x）：`res://assets/ui/UI assets (1x).png`（1024×1024）
## v2: 优先使用 assets/ui/panels/bar_frame_9s.png + bar_fill_9s.png（高清 9-slice），
##     未交付时 fallback 到旧 atlas region。

const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

const UI_ATLAS_PATH := "res://assets/ui/UI assets (1x).png"

# 单段横条外框（勿用 0,50,144,13 —— 那是三连段整条素材）
const BAR_FRAME_REGION := Rect2(1, 69, 46, 19)
const BAR_FRAME_MARGINS := Vector4(14, 5, 14, 5)

# 单段实心填充（横向九宫格拉伸）
const BAR_FILL_KI_REGION := Rect2(433, 50, 46, 13)
const BAR_FILL_EXP_REGION := Rect2(598, 856, 21, 16)
const BAR_FILL_MARGINS := Vector4(4, 2, 4, 2)

const BAR_VISUAL_HEIGHT := 18.0

# 气力条颜色：未满恢复中保持中灰（叠白色 9-slice fill），满为明亮天蓝
const KI_FILL_NORMAL := Color(0.6, 0.6, 0.6, 1.0)
const KI_FILL_FULL := Color(0.38, 1.32, 1.75, 1.0)
const KI_GLOW_SKY := Color(0.45, 0.92, 1.0)
const KI_GLOW_FILL := Color(0.55, 1.2, 1.65, 1.0)

# 暂停按钮（MINI ICONS 行 y≈736 的 ||，勿用 287,785 横条或 48,176 大块）
const PAUSE_ICON_REGION := Rect2(210, 740, 12, 12)
const PAUSE_BUTTON_REGION := Rect2(204, 736, 18, 18)

# 高清暂停 icon 路径（32×32，docs/ui_asset_spec.md v1.1）
const PAUSE_ICON_HD_PATH := "res://assets/ui/icons/system/icon_pause.png"

# 经验条主题色（atlas EXP region 是绿色；外部 9-slice 用白色，需要在这里染色）
const EXP_FILL_TINT := Color(0.50, 0.94, 0.55, 1.0)

static var _atlas: Texture2D
static var _cache: Dictionary = {}


static func _load_atlas() -> Texture2D:
	if _atlas == null:
		_atlas = load(UI_ATLAS_PATH) as Texture2D
	return _atlas


static func get_region_texture(region: Rect2) -> Texture2D:
	var key := "%d_%d_%d_%d" % [region.position.x, region.position.y, region.size.x, region.size.y]
	if _cache.has(key):
		return _cache[key]
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _load_atlas()
	atlas_tex.region = region
	atlas_tex.filter_clip = true
	_cache[key] = atlas_tex
	return atlas_tex


static func apply_pixel_filter(node: CanvasItem) -> void:
	if node:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func _draw_nine_patch_horizontal(
	canvas: CanvasItem,
	tex: Texture2D,
	rect: Rect2,
	margins: Vector4,
	modulate: Color = Color.WHITE
) -> void:
	if tex == null:
		return
	apply_pixel_filter(canvas)
	var src_size := tex.get_size()
	if src_size.x <= 0.0 or src_size.y <= 0.0:
		return
	var ml := margins.x
	var mr := margins.z
	var center_src_w := maxf(1.0, src_size.x - ml - mr)
	var dest_h := rect.size.y
	var x := rect.position.x
	var y := rect.position.y
	var total_w := rect.size.x

	var left_w := minf(ml, total_w)
	if left_w > 0.5:
		canvas.draw_texture_rect_region(
			tex, Rect2(x, y, left_w, dest_h), Rect2(0, 0, left_w, src_size.y), modulate
		)
		x += left_w

	var right_w := minf(mr, maxf(0.0, total_w - left_w))
	var mid_w := maxf(0.0, total_w - left_w - right_w)
	if mid_w > 0.5:
		canvas.draw_texture_rect_region(
			tex,
			Rect2(x, y, mid_w, dest_h),
			Rect2(ml, 0, center_src_w, src_size.y),
			modulate
		)
		x += mid_w

	if right_w > 0.5:
		canvas.draw_texture_rect_region(
			tex,
			Rect2(x, y, right_w, dest_h),
			Rect2(src_size.x - mr, 0, mr, src_size.y),
			modulate
		)


static func _ki_fill_modulate(ratio: float, is_ready: bool) -> Color:
	if is_ready:
		return KI_FILL_FULL
	# 接近满时略偏蓝，满时一下子切到天蓝
	var t := clampf(inverse_lerp(0.72, 1.0, ratio), 0.0, 1.0)
	return KI_FILL_NORMAL.lerp(KI_FILL_FULL, t * 0.35)


static func _draw_ki_ready_glow(canvas: CanvasItem, rect: Rect2, ratio: float) -> void:
	var pulse := 0.56 + sin(Time.get_ticks_msec() * 0.009) * 0.28
	var glow_base := KI_GLOW_SKY.lerp(KI_GLOW_FILL, 0.35)
	var ready_boost := 0.8 + 0.2 * clampf(ratio, 0.0, 1.0)
	var cy := rect.position.y + rect.size.y * 0.5
	var base_r := rect.size.y * 0.5
	var seg_left := rect.position.x + base_r
	var seg_right := rect.position.x + rect.size.x - base_r
	for i in range(3):
		var expand := 8.0 - float(i) * 2.5
		var mix := 1.0 - float(i) * 0.26
		var glow_col := glow_base
		glow_col.a = pulse * 0.34 * mix * ready_boost
		var r := base_r + expand
		var x0 := int(floor(rect.position.x - expand))
		var x1 := int(ceili(rect.position.x + rect.size.x + expand))
		for xi in range(x0, x1 + 1):
			var x := float(xi) + 0.5
			var nearest_x := clampf(x, seg_left, seg_right)
			var dx := absf(x - nearest_x)
			if dx >= r:
				continue
			var half_h := sqrt(r * r - dx * dx)
			var y0 := cy - half_h
			var y1 := cy + half_h
			canvas.draw_rect(Rect2(float(xi), y0, 1.0, y1 - y0), glow_col)


static func _fit_bar_rect(x: float, y: float, width: float, height: float) -> Rect2:
	var ui_scale := GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()
	var bar_h := minf(BAR_VISUAL_HEIGHT * ui_scale, height)
	var bar_y := y + (height - bar_h) * 0.5
	return Rect2(x, bar_y, width, bar_h)


static func draw_horizontal_bar(
	canvas: CanvasItem,
	rect: Rect2,
	ratio: float,
	fill_region: Rect2,
	fill_margins: Vector4 = BAR_FILL_MARGINS,
	fill_modulate: Color = Color.WHITE
) -> void:
	# v2: 优先用外部 9-slice 贴图（高清现代风），否则回退到 atlas region
	var ext_frame := UiStyle.get_bar_frame_texture()
	var ext_fill := UiStyle.get_bar_fill_texture()
	if ext_frame != null and ext_fill != null:
		_draw_bar_external_9slice(canvas, rect, ratio, ext_frame, ext_fill, fill_modulate, fill_region)
		return

	var frame_tex := get_region_texture(BAR_FRAME_REGION)
	if frame_tex:
		_draw_nine_patch_horizontal(canvas, frame_tex, rect, BAR_FRAME_MARGINS)

	var pad := 5.0
	var inner := Rect2(
		rect.position.x + pad,
		rect.position.y + pad,
		maxf(0.0, rect.size.x - pad * 2.0),
		maxf(0.0, rect.size.y - pad * 2.0)
	)
	var fill_tex := get_region_texture(fill_region)
	if inner.size.x > 0.5 and inner.size.y > 0.5 and fill_tex:
		var fill_w := inner.size.x * clampf(ratio, 0.0, 1.0)
		if fill_w > 0.5:
			var fill_rect := Rect2(inner.position, Vector2(fill_w, inner.size.y))
			_draw_nine_patch_horizontal(canvas, fill_tex, fill_rect, fill_margins, fill_modulate)


# 外部 9-slice 路径：用 panels/bar_frame_9s + panels/bar_fill_9s
# fill_region 仅用于判断是否是 EXP 条（绿色默认染色），其他用 fill_modulate
static func _draw_bar_external_9slice(
	canvas: CanvasItem,
	rect: Rect2,
	ratio: float,
	frame_tex: Texture2D,
	fill_tex: Texture2D,
	fill_modulate: Color,
	fill_region: Rect2
) -> void:
	if canvas == null or frame_tex == null or fill_tex == null:
		return
	# 9-slice 边框
	_draw_9slice_rect(canvas, frame_tex, rect, UiStyle.BAR_MARGIN, Color.WHITE)
	# 填充：按 ratio 计算可绘制宽度；4px 内边距与原 5px 接近，避免覆盖边框
	var pad := 4.0
	var inner := Rect2(
		rect.position.x + pad,
		rect.position.y + pad,
		maxf(0.0, rect.size.x - pad * 2.0),
		maxf(0.0, rect.size.y - pad * 2.0)
	)
	if inner.size.x <= 0.5 or inner.size.y <= 0.5:
		return
	var fill_w := inner.size.x * clampf(ratio, 0.0, 1.0)
	if fill_w <= 0.5:
		return
	# 经验条用默认绿；KI bar 传 fill_modulate（淡蓝/白）
	var tint := fill_modulate
	if tint == Color.WHITE and fill_region == BAR_FILL_EXP_REGION:
		tint = EXP_FILL_TINT
	_draw_9slice_rect(canvas, fill_tex, Rect2(inner.position, Vector2(fill_w, inner.size.y)), UiStyle.BAR_MARGIN, tint)


# 通用 9-slice 矩形绘制（4 角不拉伸，4 边单向拉伸，中心双向拉伸）
static func _draw_9slice_rect(canvas: CanvasItem, tex: Texture2D, rect: Rect2, margin: float, modulate: Color) -> void:
	if tex == null or canvas == null:
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var src := tex.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var m := clampf(margin, 0.0, minf(src.x * 0.49, src.y * 0.49))
	var dest_x := rect.position.x
	var dest_y := rect.position.y
	var dest_w := rect.size.x
	var dest_h := rect.size.y
	var center_src_w := maxf(1.0, src.x - m * 2.0)
	var center_src_h := maxf(1.0, src.y - m * 2.0)
	var center_dest_w := maxf(0.0, dest_w - m * 2.0)
	var center_dest_h := maxf(0.0, dest_h - m * 2.0)

	# 4 角
	canvas.draw_texture_rect_region(tex, Rect2(dest_x, dest_y, m, m), Rect2(0, 0, m, m), modulate)
	canvas.draw_texture_rect_region(tex, Rect2(dest_x + dest_w - m, dest_y, m, m), Rect2(src.x - m, 0, m, m), modulate)
	canvas.draw_texture_rect_region(tex, Rect2(dest_x, dest_y + dest_h - m, m, m), Rect2(0, src.y - m, m, m), modulate)
	canvas.draw_texture_rect_region(tex, Rect2(dest_x + dest_w - m, dest_y + dest_h - m, m, m), Rect2(src.x - m, src.y - m, m, m), modulate)
	# 4 边
	if center_dest_w > 0.5:
		canvas.draw_texture_rect_region(tex, Rect2(dest_x + m, dest_y, center_dest_w, m), Rect2(m, 0, center_src_w, m), modulate)
		canvas.draw_texture_rect_region(tex, Rect2(dest_x + m, dest_y + dest_h - m, center_dest_w, m), Rect2(m, src.y - m, center_src_w, m), modulate)
	if center_dest_h > 0.5:
		canvas.draw_texture_rect_region(tex, Rect2(dest_x, dest_y + m, m, center_dest_h), Rect2(0, m, m, center_src_h), modulate)
		canvas.draw_texture_rect_region(tex, Rect2(dest_x + dest_w - m, dest_y + m, m, center_dest_h), Rect2(src.x - m, m, m, center_src_h), modulate)
	# 中心
	if center_dest_w > 0.5 and center_dest_h > 0.5:
		canvas.draw_texture_rect_region(tex, Rect2(dest_x + m, dest_y + m, center_dest_w, center_dest_h), Rect2(m, m, center_src_w, center_src_h), modulate)


static func draw_exp_bar(
	canvas: CanvasItem,
	viewport_size: Vector2,
	level: int,
	exp_value: int,
	exp_to_next: int
) -> void:
	var ui_scale := GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()
	var pad := 10.0 * ui_scale
	var w := viewport_size.x - pad * 2.0
	var rect := _fit_bar_rect(pad, viewport_size.y - BAR_VISUAL_HEIGHT * ui_scale - pad, w, BAR_VISUAL_HEIGHT * ui_scale)
	var ratio := clampf(float(exp_value) / maxf(1.0, float(exp_to_next)), 0.0, 1.0)
	draw_horizontal_bar(canvas, rect, ratio, BAR_FILL_EXP_REGION)

	var font_size := PixelUiHelper.snap_pixel_font_size(int(round(11.0 * ui_scale)))
	var cy := rect.position.y + rect.size.y * 0.5
	PixelUiHelper.draw_pixel_text(
		canvas, "Lv%d" % level, Vector2(pad + 8.0 * ui_scale, cy), font_size,
		Color("#ffe8a8"), HORIZONTAL_ALIGNMENT_LEFT
	)
	PixelUiHelper.draw_pixel_text(
		canvas, "%d / %d" % [exp_value, exp_to_next], Vector2(pad + w - 8.0 * ui_scale, cy),
		font_size, Color("#e8f0d8"), HORIZONTAL_ALIGNMENT_RIGHT
	)


static func draw_ki_bar(
	canvas: CanvasItem,
	x: float,
	y: float,
	width: float,
	height: float,
	ratio: float,
	is_ready: bool
) -> void:
	var rect := _fit_bar_rect(x, y, width, height)
	var fill_tint := _ki_fill_modulate(ratio, is_ready)
	if is_ready:
		_draw_ki_ready_glow(canvas, rect, ratio)
	draw_horizontal_bar(canvas, rect, ratio, BAR_FILL_KI_REGION, BAR_FILL_MARGINS, fill_tint)


static func make_pause_button_icon() -> Texture2D:
	return get_region_texture(PAUSE_ICON_REGION)


static func make_pause_button_texture() -> Texture2D:
	var key := "pause_button_pixel_v2"
	if _cache.has(key):
		return _cache[key]
	var ui_scale := GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()
	var size_px := maxi(18, int(round(18.0 * ui_scale)))
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border_dark := Color("#1f2430")
	var border_mid := Color("#4a566c")
	var panel_fill := Color("#2d3647")
	var panel_hi := Color("#6f7d97")
	var bar_col := Color("#d6e2ff")
	var shadow_col := Color("#0f1420")
	var inner_max := size_px - 2
	for y in range(1, inner_max + 1):
		for x in range(1, inner_max + 1):
			image.set_pixel(x, y, panel_fill)
	for x in range(1, inner_max + 1):
		image.set_pixel(x, 1, border_dark)
		image.set_pixel(x, inner_max, border_dark)
	for y in range(1, inner_max + 1):
		image.set_pixel(1, y, border_dark)
		image.set_pixel(inner_max, y, border_dark)
	for x in range(2, inner_max):
		image.set_pixel(x, 2, panel_hi)
	for y in range(2, inner_max):
		image.set_pixel(2, y, panel_hi)
	for x in range(2, inner_max):
		image.set_pixel(x, inner_max - 1, border_mid)
	for y in range(2, inner_max):
		image.set_pixel(inner_max - 1, y, border_mid)
	var bar_x1 := int(round(size_px * 0.33))
	var bar_x2 := bar_x1 + 1
	var bar_x3 := int(round(size_px * 0.62))
	var bar_x4 := bar_x3 + 1
	var shadow_x1 := bar_x2 + 1
	var shadow_x2 := bar_x4 + 1
	var bar_top := int(round(size_px * 0.22))
	var bar_bottom := int(round(size_px * 0.78))
	for y in range(bar_top, bar_bottom):
		image.set_pixel(bar_x1, y, bar_col)
		image.set_pixel(bar_x2, y, bar_col)
		image.set_pixel(bar_x3, y, bar_col)
		image.set_pixel(bar_x4, y, bar_col)
		if shadow_x1 < size_px:
			image.set_pixel(shadow_x1, y, shadow_col)
		if shadow_x2 < size_px:
			image.set_pixel(shadow_x2, y, shadow_col)
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


static func style_pause_button(btn: TextureButton) -> void:
	# v2: 优先用高清 icon_pause.png（32×32），未交付时回退到 atlas 程序绘制
	var hd_tex := load(PAUSE_ICON_HD_PATH) as Texture2D if ResourceLoader.exists(PAUSE_ICON_HD_PATH) else null
	if hd_tex != null:
		btn.texture_normal = hd_tex
		btn.texture_pressed = hd_tex
		btn.texture_hover = hd_tex
		btn.texture_disabled = hd_tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		return
	var tex := make_pause_button_texture()
	btn.texture_normal = tex
	btn.texture_pressed = tex
	btn.texture_hover = tex
	btn.texture_disabled = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	apply_pixel_filter(btn)
