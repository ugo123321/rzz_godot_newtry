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

# 升级卡 PNG icon（skill_XX.png，源自 xlsx E 列 icon 字段）+ 边框
const UPGRADE_ICON_DIR := "res://assets/ui/icons/upgrades/"
const REWARD_FRAME_PATH := "res://assets/ui/decorations/deco_frame_32.png"
# deco_frame_32.png 是 64×64 画布，但可见边框图案只占中间 40×40（外圈 12px 透明留白）。
# 拉到跟 icon 同尺寸时可见部分会缩小 → 反向放大 1/0.625 让边框可见外沿对齐 icon。
const REWARD_FRAME_OPAQUE_RATIO := 0.625

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


# ─── UI 图片抗锯齿（LINEAR filter） ───
# 项目全局 default_texture_filter=NEAREST（保战斗像素锐利），但高清 UI 图缩放会锯齿。
# 递归给指定分支下所有 TextureRect / TextureButton / NinePatchRect / Sprite2D 单独设 LINEAR。
# exclude_paths 里的相对路径（可以是子路径关键字，match 用 String.contains）会被跳过 —
# 例：装备预览的角色像素 sprite 传入 "PreviewSprite" 就不会被误改。
static func apply_linear_filter_tree(root: Node, exclude_keywords: Array = []) -> void:
	if root == null:
		return
	_apply_linear_recursive(root, exclude_keywords)


static func _apply_linear_recursive(node: Node, exclude_keywords: Array) -> void:
	var skip := false
	for kw in exclude_keywords:
		if str(kw).is_empty():
			continue
		if str(node.name).contains(str(kw)):
			skip = true
			break
	if not skip and (node is TextureRect or node is TextureButton or node is NinePatchRect or node is Sprite2D or node is AnimatedSprite2D):
		# AnimatedSprite2D 装备预览角色是像素，跳过；只当不在 exclude 里且不是像素动画时才 LINEAR
		if not (node is AnimatedSprite2D):
			(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		if skip:
			# 父节点被 exclude 时，子节点也整体跳过（比如 PreviewViewport 里所有像素东西）
			continue
		_apply_linear_recursive(child, exclude_keywords)


# ─── 升级卡 PNG icon + FRAME 边框 ───
# 数据来源：rewards_v6.json 的 "icon" 字段（由 export_rewards_v6_compact_json.py 从 xlsx E 列导出）。
# 值形如 "skill_45"（不带扩展名）→ 加载 res://assets/ui/icons/upgrades/skill_45.png
# 空值 / emoji（如 "💪"）/ 加载失败 → 返回 null，让调用方 fallback 到 PixelCardIcon 程序绘制。
static func try_load_upgrade_icon(upgrade: Dictionary) -> Texture2D:
	var icon_key := str(upgrade.get("icon", "")).strip_edges()
	if icon_key.is_empty() or not icon_key.begins_with("skill_"):
		return null
	var path := UPGRADE_ICON_DIR + icon_key + ".png"
	if not ResourceLoader.exists(path):
		return null
	return _load_tex(path)


# 组装 "PNG icon + FRAME 边框" 的可复用 Control。
# 结构：CenterContainer > Control(size × size) > [icon_rect, frame_rect]（两层等大 stack）
# 返回 null → 调用方走 PixelCardIcon fallback。
static func build_reward_icon_with_frame(upgrade: Dictionary, size: float) -> Control:
	var tex := try_load_upgrade_icon(upgrade)
	if tex == null:
		return null
	var box := CenterContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(size, size)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stack)

	var icon_rect := TextureRect.new()
	icon_rect.texture = tex
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon_rect)
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame_tex := _load_tex(REWARD_FRAME_PATH)
	if frame_tex != null:
		var frame_rect := TextureRect.new()
		frame_rect.texture = frame_tex
		frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(frame_rect)
		# 边框可见部分只占 PNG 的 62.5%，反向放大让可见边界对齐 icon rect
		var frame_draw := size / REWARD_FRAME_OPAQUE_RATIO
		var bleed := (frame_draw - size) * 0.5
		frame_rect.position = Vector2(-bleed, -bleed)
		frame_rect.size = Vector2(frame_draw, frame_draw)
	return box
