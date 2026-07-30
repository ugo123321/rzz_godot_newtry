extends CanvasLayer

## Boss 出场原画特写：屏幕变暗 → 长条原画从左滑入屏幕正中
## （原画下方白字 boss 名，如 boss-冲锋骑士）→ 滑出到右 → 屏幕恢复。
## 由 battle.start_boss_intro(boss_id) 触发；monster_spawner 把 boss 生成延迟到特写播完，
## 这样「特写先播、屏幕恢复后 boss 才下落震屏 + 血条展开」。
## 目前覆盖两个 boss：lancer_knight(冲锋骑士)、dark_dragon(远古黑龙)。centipede 无特写。

const BOSS_POPUP_ART := {
	"lancer_knight": "res://assets/ui/icons/boss_popup/DeathKnight_popup.png",
	"dark_dragon": "res://assets/ui/icons/boss_popup/AncientBlackDragon_popup.png",
	"bounce_slime": "res://assets/ui/icons/boss_popup/Slime_popup.png",
}

const DARKEN_ALPHA := 0.72            # 屏幕变暗目标 alpha（黑罩）
const ART_WIDTH_RATIO := 0.80         # 原画按屏宽 80% 缩放，保持原比例

# 时序（顺序执行）：变暗→滑入→停→滑出→恢复，总 1.6s
const T_DARKEN_IN := 0.20
const T_SLIDE_IN := 0.30
const T_HOLD := 0.55
const T_SLIDE_OUT := 0.30
const T_BRIGHTEN := 0.25
const DURATION := T_DARKEN_IN + T_SLIDE_IN + T_HOLD + T_SLIDE_OUT + T_BRIGHTEN  # = 1.6s

var _dim: ColorRect
var _art: TextureRect
var _name: Label

var _tween: Tween
var _art_target_x: float = 0.0   # 原画居中时的 x
var _art_off_left_x: float = 0.0
var _art_off_right_x: float = 0.0


func _ready() -> void:
	layer = 100  # 盖在所有东西（含 HUD）之上
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_art = TextureRect.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.visible = false
	add_child(_art)

	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_color", Color.WHITE)
	_name.add_theme_font_size_override("font_size", 30)
	_name.modulate.a = 0.0
	# 用项目 UI 字体（含 CJK），与 intro_label 同款处理
	PixelUiHelper.apply_ui_font(_name)
	add_child(_name)

	visible = false


## 查 boss 是否有特写（供 spawner 决定是否延迟生成）。
static func has_popup(boss_id: String) -> bool:
	return BOSS_POPUP_ART.has(boss_id)


## 播放特写。无映射/加载失败 → 返回 false（调用方按原 wave_delay 走）。
func play(boss_id: String) -> bool:
	var art_path: String = BOSS_POPUP_ART.get(boss_id, "")
	if art_path.is_empty():
		return false
	var tex := load(art_path) as Texture2D
	if tex == null:
		push_warning("BossIntroPopup: 加载失败 %s" % art_path)
		return false
	var name_cn: String = str(GameConfig.bosses.get(boss_id, {}).get("name", boss_id))
	_art.texture = tex
	_name.text = "boss-%s" % name_cn
	_layout(_viewport_size())
	_art.position.x = _art_off_left_x
	_art.visible = true
	_dim.color.a = 0.0
	_name.modulate.a = 0.0
	visible = true

	if _tween:
		_tween.kill()
	_tween = create_tween()
	# 变暗 + 名字淡入（并行）
	_tween.tween_property(_dim, "color:a", DARKEN_ALPHA, T_DARKEN_IN)
	_tween.parallel().tween_property(_name, "modulate:a", 1.0, T_DARKEN_IN)
	# 原画从左滑入正中
	_tween.tween_property(_art, "position:x", _art_target_x, T_SLIDE_IN).set_ease(Tween.EASE_OUT)
	# 停
	_tween.tween_interval(T_HOLD)
	# 滑出到右侧外
	_tween.tween_property(_art, "position:x", _art_off_right_x, T_SLIDE_OUT).set_ease(Tween.EASE_IN)
	# 屏幕恢复 + 名字淡出（并行）
	_tween.tween_property(_dim, "color:a", 0.0, T_BRIGHTEN)
	_tween.parallel().tween_property(_name, "modulate:a", 0.0, T_BRIGHTEN)
	# 收尾
	_tween.tween_callback(_on_finished)
	return true


func _on_finished() -> void:
	visible = false
	_art.visible = false
	_dim.color.a = 0.0
	_name.modulate.a = 0.0


## 按当前视口尺寸布局：原画按屏宽 80% 缩放保持比例，原画+名字作为整体垂直居中。
func _layout(vp: Vector2) -> void:
	_dim.position = Vector2.ZERO
	_dim.size = vp

	var tex := _art.texture
	if tex == null:
		return
	var aspect: float = float(tex.get_height()) / float(tex.get_width())
	var target_w: float = vp.x * ART_WIDTH_RATIO
	var target_h: float = target_w * aspect
	_art.size = Vector2(target_w, target_h)

	var name_h: float = 48.0
	var composite_h: float = target_h + 10.0 + name_h
	var top_y: float = (vp.y - composite_h) * 0.5

	_art_target_x = (vp.x - target_w) * 0.5
	_art_off_left_x = -target_w
	_art_off_right_x = vp.x
	_art.position = Vector2(_art_off_left_x, top_y)

	_name.position = Vector2(0.0, top_y + target_h + 10.0)
	_name.size = Vector2(vp.x, name_h)


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp:
		return vp.get_visible_rect().size
	return Vector2(1280, 720)
