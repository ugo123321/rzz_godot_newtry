class_name UiSpriteHelper
extends RefCounted

## Franuka RPG UI 图集（1x）：`res://assets/ui/UI assets (1x).png`（1024×1024）
## 气力条 / 经验条已改用整条贴图素材（assets/ui/battle/energy_*.png），关闭像素化（LINEAR）。

const UI_ATLAS_PATH := "res://assets/ui/UI assets (1x).png"

# HUD 条实际绘制高度（px，乘 ui_scale）
const BAR_VISUAL_HEIGHT := 18.0

# 气力 / 经验条素材（整条贴图：empty=空槽背景，blue=气力填充，green=经验填充）
const ENERGY_EMPTY_PATH := "res://assets/ui/battle/energy_empty.png"
const ENERGY_BLUE_PATH := "res://assets/ui/battle/energy_blue.png"
const ENERGY_GREEN_PATH := "res://assets/ui/battle/energy_green.png"

# 暂停按钮（MINI ICONS 行 y≈736 的 ||，勿用 287,785 横条或 48,176 大块）
const PAUSE_ICON_REGION := Rect2(210, 740, 12, 12)
const PAUSE_BUTTON_REGION := Rect2(204, 736, 18, 18)

# 高清暂停 icon 路径（32×32，docs/ui_asset_spec.md v1.1）
const PAUSE_ICON_HD_PATH := "res://assets/ui/icons/system/icon_pause.png"

static var _atlas: Texture2D
static var _cache: Dictionary = {}
static var _energy_empty_tex: Texture2D
static var _energy_blue_tex: Texture2D
static var _energy_green_tex: Texture2D


static func _load_energy_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _get_energy_empty() -> Texture2D:
	if _energy_empty_tex == null:
		_energy_empty_tex = _load_energy_tex(ENERGY_EMPTY_PATH)
	return _energy_empty_tex


static func _get_energy_blue() -> Texture2D:
	if _energy_blue_tex == null:
		_energy_blue_tex = _load_energy_tex(ENERGY_BLUE_PATH)
	return _energy_blue_tex


static func _get_energy_green() -> Texture2D:
	if _energy_green_tex == null:
		_energy_green_tex = _load_energy_tex(ENERGY_GREEN_PATH)
	return _energy_green_tex


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


# 气力条 / 经验条：整条贴图绘制（energy_empty 作空槽背景，energy_blue/green 作填充）。
# 关掉像素化（LINEAR），填充按 ratio 从左侧裁剪绘制，居中嵌进 empty 框内。
static func _draw_energy_bar(
	canvas: CanvasItem,
	rect: Rect2,
	ratio: float,
	fill_tex: Texture2D,
	modulate: Color = Color.WHITE
) -> void:
	if canvas == null:
		return
	var empty_tex := _get_energy_empty()
	if empty_tex == null or fill_tex == null:
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 空槽背景：整图拉伸到目标 rect
	canvas.draw_texture_rect(empty_tex, rect, false, Color.WHITE)

	# 填充：按 empty 尺寸算缩放，把 fill 居中嵌进 empty 内部（源图边距即 inset）
	var empty_size := empty_tex.get_size()
	var fill_size := fill_tex.get_size()
	if empty_size.x <= 0.0 or empty_size.y <= 0.0 or fill_size.x <= 0.0 or fill_size.y <= 0.0:
		return
	var sx := rect.size.x / empty_size.x
	var sy := rect.size.y / empty_size.y
	var inset_x := (empty_size.x - fill_size.x) * 0.5
	var inset_y := (empty_size.y - fill_size.y) * 0.5
	var fill_dest_w := fill_size.x * sx
	var fill_dest_h := fill_size.y * sy
	var fx := rect.position.x + inset_x * sx
	var fy := rect.position.y + inset_y * sy
	var r := clampf(ratio, 0.0, 1.0)
	var draw_w := fill_dest_w * r
	if draw_w <= 0.5:
		return
	# 用 region 裁剪源图左侧 r 比例，拉伸到目标宽度
	canvas.draw_texture_rect_region(
		fill_tex,
		Rect2(fx, fy, draw_w, fill_dest_h),
		Rect2(0.0, 0.0, fill_size.x * r, fill_size.y),
		modulate
	)


static func _fit_bar_rect(x: float, y: float, width: float, height: float) -> Rect2:
	var ui_scale := GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()
	var bar_h := minf(BAR_VISUAL_HEIGHT * ui_scale, height)
	var bar_y := y + (height - bar_h) * 0.5
	return Rect2(x, bar_y, width, bar_h)



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
	_draw_energy_bar(canvas, rect, ratio, _get_energy_green())

	# 文字在条上层绘制
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
	# 满气力时叠加轻微脉冲亮蓝，作为「就绪」提示（仍使用同一张贴图）
	var mod := Color.WHITE
	if is_ready:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
		mod = Color.WHITE.lerp(Color(0.70, 0.92, 1.0), pulse * 0.45)
	_draw_energy_bar(canvas, rect, ratio, _get_energy_blue(), mod)


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
