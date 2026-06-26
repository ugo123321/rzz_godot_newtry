extends RigidBody2D
class_name EnhancementBlock

# 属性打造关「强化块」：物理沿用 wood_block 配方（settle 阈值不变），
# 仅尺寸更大、重力略轻、视觉换成 lottery_portal 紫色系 + 80ms 二态闪烁高光。
# 每块生成时绑定 1 个 forge buff（buff_idx）— 结算时由 battle 一次性 commit 到 player。

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const SETTLE_VEL := 25.0
const SETTLE_TIME := 0.35

var size_px := 96.0
var is_settled := false
var _low_v_t := 0.0
var _flicker_seed := 0.0

# 碰撞特效：director 在 spawn 时通过 set_particles_ref 注入 _battle.particles。
# 节流避免稳态堆叠时持续微抖刷屏（80ms + impact<60 双门槛）。
var _particles_ref: Object = null
var _last_burst_ms: int = -1000

# Buff 绑定：在 setup() 中由 director 传入；_draw() 中显示在方块正面。
var buff_idx := -1
var buff_name_cn := ""
var buff_delta := 0.0


func setup(size: float, b_idx: int = -1, b_short_name: String = "", b_delta: float = 0.0) -> void:
	size_px = size
	buff_idx = b_idx
	buff_name_cn = b_short_name
	buff_delta = b_delta
	_flicker_seed = randf() * TAU
	gravity_scale = 1.3
	mass = 1.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.95
	physics_material_override.bounce = 0.05
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	body_entered.connect(_on_body_entered)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size_px, size_px)
	var coll := CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)


func set_particles_ref(p: Object) -> void:
	_particles_ref = p


func _on_body_entered(_body: Node) -> void:
	if _particles_ref == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_burst_ms < 80:
		return
	var impact: float = linear_velocity.length()
	if impact < 60.0:
		return
	_last_burst_ms = now
	var pos := global_position
	var k: float = clampf((impact - 60.0) / 540.0, 0.0, 1.0)
	var dust_size: float = lerp(8.0, 16.0, k)
	var debris_size: float = lerp(6.0, 12.0, k)
	var dust_color := Color("#c8a8ff")
	var debris_color := Color("#5536a8")
	for i in range(8):
		var a := randf() * TAU
		var sp: float = randf_range(40.0, 110.0) * lerp(0.7, 1.0, k)
		_particles_ref.emit_particle(
			pos.x, pos.y - size_px * 0.25,
			cos(a) * sp, sin(a) * sp - 30.0,
			randf_range(0.28, 0.45), dust_size,
			dust_color, 80.0, true, true
		)
	for i in range(6):
		var a2 := randf() * TAU
		var sp2: float = randf_range(100.0, 220.0) * lerp(0.7, 1.0, k)
		_particles_ref.emit_particle(
			pos.x, pos.y - size_px * 0.15,
			cos(a2) * sp2, sin(a2) * sp2,
			randf_range(0.14, 0.26), debris_size,
			debris_color, 200.0, true, false
		)


func _physics_process(delta: float) -> void:
	if is_settled:
		return
	if linear_velocity.length() < SETTLE_VEL and absf(angular_velocity) < 1.0:
		_low_v_t += delta
		if _low_v_t >= SETTLE_TIME:
			is_settled = true
	else:
		_low_v_t = 0.0


func _process(_delta: float) -> void:
	# 80ms 闪烁需要持续 redraw
	queue_redraw()


func _draw() -> void:
	var half := size_px * 0.5
	var outline := Color("#1a0e33")
	var mid := Color("#2a1a55")
	var base := Color("#5536a8")
	var light := Color("#8a5cff")
	var hl := Color("#c8a8ff")
	var cyan := Color("#a8e8ff")
	# outer
	draw_rect(Rect2(-half, -half, size_px, size_px), outline)
	draw_rect(Rect2(-half + 2.0, -half + 2.0, size_px - 4.0, size_px - 4.0), mid)
	draw_rect(Rect2(-half + 4.0, -half + 4.0, size_px - 8.0, size_px - 8.0), base)
	draw_rect(Rect2(-half + 7.0, -half + 7.0, size_px - 14.0, size_px - 14.0), light)
	# 顶部高光带 80ms 二态闪烁
	var flicker_on := int(Time.get_ticks_msec() / 80) % 2 == 0
	var hl_color := hl if flicker_on else Color(hl.r, hl.g, hl.b, 0.55)
	draw_rect(Rect2(-half + 6.0, -half + 6.0, size_px - 12.0, 3.0), hl_color)
	draw_rect(Rect2(-half + 6.0, -half + 6.0, 3.0, size_px - 12.0), hl_color)
	# 左上 cyan accent
	draw_rect(Rect2(-half + 6.0, -half + 6.0, 5.0, 5.0), cyan)
	# 中心 buff 文字（跟随方块旋转）— 2 行：短名 + ±X%
	# v3：深色文字，字号加大，避免被亮紫底色淹没。
	if buff_idx >= 0 and not buff_name_cn.is_empty():
		var text_color := Color("#1a0e33") if buff_delta >= 0.0 else Color("#0a2a3a")
		PixelUi.draw_pixel_text(
			self,
			buff_name_cn,
			Vector2(0.0, -size_px * 0.16),
			24,
			text_color,
			HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER,
			true
		)
		var sign_str := "+" if buff_delta >= 0.0 else ""
		var pct := int(round(buff_delta * 100.0))
		PixelUi.draw_pixel_text(
			self,
			"%s%d%%" % [sign_str, pct],
			Vector2(0.0, size_px * 0.18),
			30,
			text_color,
			HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER,
			true
		)
