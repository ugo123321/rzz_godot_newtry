extends FieldElement
class_name ArrowBlock

# 单向 / 十字飞箭块：每 1s 朝正对方向（单向）或十字四向（十字）射出飞箭，阻挡移动/画线/子弹。
# 箭只伤害玩家，对敌人无效。朝向由编辑器设定（up/down/left/right）。

const FIRE_INTERVAL := 1.0
const ArrowProjectileScript := preload("res://scripts/entities/arrow_projectile.gd")

const DIRS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}

var _t := 0.0
var _fire_timer := 0.0


func setup_block(col: int, row: int, p_kind: String, p_facing: String) -> void:
	setup(col, row, p_kind, p_facing)  # kind = "arrow_single" / "arrow_cross"
	_configure_blocking(true, true, true)


func _process(delta: float) -> void:
	if consumed:
		return
	_t += delta
	_fire_timer += delta
	queue_redraw()  # 驱动闪烁动画（每帧重绘）
	if _battle == null:
		_battle = get_tree().get_first_node_in_group("battle")
	if _battle == null or _battle.player == null:
		return
	if _battle.state != GameState.PLAYING:
		return
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_fire_arrows()


func _fire_arrows() -> void:
	if _battle == null:
		return
	var dirs: Array = []
	if kind == "arrow_cross":
		dirs = [DIRS.up, DIRS.down, DIRS.left, DIRS.right]
	else:
		dirs = [DIRS.get(facing, Vector2.RIGHT)]
	for d in dirs:
		var proj := ArrowProjectileScript.new()
		_battle.field_elements.get_parent().add_child(proj)  # 加到 $Entities 下
		proj.setup(global_position + d * 22.0, Vector2(d), _battle)


func _draw() -> void:
	# 像素箭匣 + 朝向箭头 + 外发光圆晕 + 周期闪烁（CLAUDE.md §9）
	var s: float = 18.0
	var pulse: float = 0.8 + 0.2 * (0.5 + 0.5 * sin(_t * 6.0))
	var c_body := Color("#6a6058") * pulse
	var c_shade := Color("#3a342c") * pulse
	var c_high := Color("#9a8e82") * pulse
	var c_rim := Color("#1a1208") * pulse
	var c_arrow := Color("#ffd060") * pulse
	# 外发光（暖色，提示"会射箭"）
	var glow_a: float = 0.18 + 0.12 * (0.5 + 0.5 * sin(_t * 6.0))
	draw_circle(Vector2.ZERO, s * 1.45, Color(0.95, 0.7, 0.3, glow_a))
	# 块体
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c_body, true)
	draw_rect(Rect2(-s * 0.6, -s * 0.6, s * 0.5, s * 0.5), c_shade, true)
	draw_rect(Rect2(s * 0.1, s * 0.1, s * 0.5, s * 0.5), c_shade, true)
	draw_rect(Rect2(-s, -s, s * 2.0, 4.0), c_high, true)
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c_rim, false, 2.5)
	# 朝向箭头
	_draw_facing_arrow(s * 0.5, c_arrow, c_rim)


func _draw_facing_arrow(r: float, c: Color, c_rim: Color) -> void:
	var d: Vector2 = DIRS.get(facing, Vector2.RIGHT)
	var ang: float = d.angle()
	# 旋转后的三角箭头
	var pts := PackedVector2Array([
		Vector2(cos(ang) * r, sin(ang) * r),
		Vector2(cos(ang + 2.5) * r * 0.7, sin(ang + 2.5) * r * 0.7),
		Vector2(cos(ang - 2.5) * r * 0.7, sin(ang - 2.5) * r * 0.7),
	])
	draw_colored_polygon(pts, c)
	# 描边（近似：再画一次 outline 偏移色）
	draw_polyline(pts + PackedVector2Array([pts[0]]), c_rim, 1.5, true)
