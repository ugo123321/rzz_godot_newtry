extends FieldElement
class_name PitBlock

# 深坑（实体版）：阻挡移动 + 画线 + 子弹。作为实体放在地板（水/石/草）之上，
# 这样"水地板上放深坑"能同时保留地板与深坑两层视觉。
# 对敌人无效（敌人不在其上刷出；敌人本身不受地块影响）。

func setup_block(col: int, row: int) -> void:
	setup(col, row, "pit", "up")
	_configure_blocking(true, true, true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# 深坑：外圈微亮坑缘 + 中部深色 + 中心最深 + 几道裂纹（CLAUDE.md §9 多色分层）
	var s: float = 18.0
	var c_rim := Color("#2a2030")
	var c_base := Color("#0c0a12")
	var c_shade := Color("#060409")
	var c_crack := Color("#1a1424")
	# 外发光（深紫，提示"危险"）
	draw_circle(Vector2.ZERO, s * 1.35, Color(0.15, 0.05, 0.2, 0.25))
	# 坑缘
	draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c_rim, true)
	# 中部
	draw_rect(Rect2(-s + 3.0, -s + 3.0, s * 2.0 - 6.0, s * 2.0 - 6.0), c_base, true)
	# 中心最深
	draw_rect(Rect2(-s + 7.0, -s + 7.0, s * 2.0 - 14.0, s * 2.0 - 14.0), c_shade, true)
	# 裂纹（几道短暗线）
	draw_rect(Rect2(-s + 6.0, -2.0, 8.0, 2.0), c_crack, true)
	draw_rect(Rect2(2.0, 2.0, 8.0, 2.0), c_crack, true)
	draw_rect(Rect2(-2.0, -s + 8.0, 2.0, 6.0), c_crack, true)
