class_name UiStyleHelper
extends RefCounted

## 9-slice 贴图样式统一入口（docs/ui_asset_spec.md v1.1）
## 用法：
##   panel.add_theme_stylebox_override("panel", UiStyleHelper.make_dialog_stylebox(Color("#eb2d18")))
##   UiStyleHelper.apply_primary_button(btn, Color("#efb840"))

const DIALOG_PATH := "res://assets/ui/panels/panel_dialog_9s.png"
const TOOLTIP_STD_PATH := "res://assets/ui/panels/panel_tooltip_std_9s.png"
const BTN_PRIMARY_PATH := "res://assets/ui/buttons/btn_primary_9s.png"
const BAR_FRAME_PATH := "res://assets/ui/panels/bar_frame_9s.png"
const BAR_FILL_PATH := "res://assets/ui/panels/bar_fill_9s.png"

# 切片数值见 docs/ui_asset_spec.md § 4
const DIALOG_MARGIN := 24
const TOOLTIP_STD_MARGIN := 12
const BTN_PRIMARY_MARGIN := 16
const BAR_MARGIN := 8

# 按钮状态调制（normal=1.0；hover 提亮；pressed 压暗；disabled 灰化半透）
const HOVER_BOOST := 1.18
const PRESSED_DIM := 0.72
const DISABLED_DIM := 0.5
const DISABLED_ALPHA := 0.6

static var _tex_cache: Dictionary = {}


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not ResourceLoader.exists(path):
		_tex_cache[path] = null
		return null
	var tex := load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


static func _build_stylebox(path: String, margin: int, tint: Color) -> StyleBoxTexture:
	var tex := _load_tex(path)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.modulate_color = tint
	return sb


# ─── Dialog 面板（升级 / 主题关 / 转盘 / 暂停菜单通用） ───
static func make_dialog_stylebox(tint: Color = Color.WHITE, content_pad: int = 20) -> StyleBoxTexture:
	var sb := _build_stylebox(DIALOG_PATH, DIALOG_MARGIN, tint)
	if sb == null:
		return null
	sb.set_content_margin_all(float(content_pad))
	return sb


# ─── Tooltip 标准档 ───
static func make_tooltip_stylebox(tint: Color = Color.WHITE, content_pad: int = 10) -> StyleBoxTexture:
	var sb := _build_stylebox(TOOLTIP_STD_PATH, TOOLTIP_STD_MARGIN, tint)
	if sb == null:
		return null
	sb.set_content_margin_all(float(content_pad))
	return sb


# ─── 主按钮 styleboxes（normal / hover / pressed / disabled） ───
static func _btn_stylebox(tint: Color, brightness: float, alpha: float, content_pad: int) -> StyleBoxTexture:
	var col := Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, tint.a * alpha)
	var sb := _build_stylebox(BTN_PRIMARY_PATH, BTN_PRIMARY_MARGIN, col)
	if sb == null:
		return null
	sb.set_content_margin_all(float(content_pad))
	return sb


# 给 Button 一次性挂上四态样式 + 高清线性过滤
static func apply_primary_button(btn: Button, tint: Color = Color.WHITE, content_pad: int = 10) -> void:
	if btn == null:
		return
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sb_normal := _btn_stylebox(tint, 1.0, 1.0, content_pad)
	if sb_normal == null:
		# 贴图缺失时退回 StyleBoxFlat 兜底
		var fb := StyleBoxFlat.new()
		fb.bg_color = tint
		fb.set_corner_radius_all(6)
		fb.set_content_margin_all(float(content_pad))
		btn.add_theme_stylebox_override("normal", fb)
		return
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", _btn_stylebox(tint, HOVER_BOOST, 1.0, content_pad))
	btn.add_theme_stylebox_override("pressed", _btn_stylebox(tint, PRESSED_DIM, 1.0, content_pad))
	btn.add_theme_stylebox_override("disabled", _btn_stylebox(tint, DISABLED_DIM, DISABLED_ALPHA, content_pad))
	btn.add_theme_stylebox_override("focus", _btn_stylebox(tint, 1.0, 0.0, content_pad))


# ─── HUD 血条 / 经验条（独立绘制函数，因为 HUD 是 _draw 模式） ───
static func get_bar_frame_texture() -> Texture2D:
	return _load_tex(BAR_FRAME_PATH)


static func get_bar_fill_texture() -> Texture2D:
	return _load_tex(BAR_FILL_PATH)
