extends Node2D
class_name ArrowProjectile

# 飞箭块射出的箭：单向 / 十字。只命中玩家（对敌人无效，不入 monster group，怪物忽略）。
# 撞阻挡石/深坑 → 火花消失。出屏 → 消失。

const SPEED := 220.0
const HIT_RADIUS := 18.0  # 放大后随块变大（原 12）
const DAMAGE := 8
const PIXEL := 3.5  # 放大 1.4×（原 2.5）
const FLICKER_MS := 80

var _dir := Vector2.RIGHT
var _battle: Node = null
var _alive := true
var _t := 0.0


func setup(pos: Vector2, dir: Vector2, battle: Node) -> void:
	global_position = pos
	_dir = dir.normalized()
	_battle = battle
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rotation = _dir.angle()


func _process(delta: float) -> void:
	if not _alive:
		return
	# 画线时停（bullet time, time_scale < 1.0）：冻结 —— 不移动、不检测命中，与怪物一致
	if _battle and "time_scale" in _battle and _battle.time_scale < 1.0:
		return
	_t += delta
	global_position += _dir * SPEED * delta
	# 命中玩家
	if _battle and _battle.player and is_instance_valid(_battle.player):
		if global_position.distance_to(_battle.player.global_position) <= HIT_RADIUS + 6.0:
			_battle.player.take_damage(DAMAGE)
			_alive = false
			_burst()
			queue_free()
			return
	# 撞阻挡石/深坑/未解锁锁定块/箭块
	if _battle and _battle.has_method("is_bullet_blocked_at") and _battle.is_bullet_blocked_at(global_position):
		_alive = false
		_burst()
		queue_free()
		return
	# 出屏
	if _battle and _battle.has_method("is_in_bounds") and not _battle.is_in_bounds(global_position):
		queue_free()


func _burst() -> void:
	if _battle and _battle.particles:
		_battle.particles.hit_spark(global_position, false)


func _draw() -> void:
	# 像素箭：杆 + 箭头 + 尾羽，多色分层 + 周期闪烁（CLAUDE.md §9）
	var flicker := 0.85 + 0.15 * (0.5 + 0.5 * sin((_t * 1000.0 / FLICKER_MS) * TAU * 0.5))
	var c_shaft := Color("#caa850") * flicker
	var c_head := Color("#f0e090") * flicker
	var c_fletch := Color("#a8403a") * flicker
	var c_rim := Color("#2a1808") * flicker
	# 杆（朝 +x 方向，rotation 已对齐 _dir）
	draw_rect(Rect2(-6.0 * PIXEL, -0.6 * PIXEL, 12.0 * PIXEL, 1.2 * PIXEL), c_shaft, true)
	# 箭头（三角块）
	var pts := PackedVector2Array([
		Vector2(6.0 * PIXEL, 0.0),
		Vector2(3.0 * PIXEL, -2.2 * PIXEL),
		Vector2(3.0 * PIXEL, 2.2 * PIXEL),
	])
	draw_colored_polygon(pts, c_head)
	# 尾羽
	draw_rect(Rect2(-7.0 * PIXEL, -2.0 * PIXEL, 2.0 * PIXEL, 1.5 * PIXEL), c_fletch, true)
	draw_rect(Rect2(-7.0 * PIXEL, 0.5 * PIXEL, 2.0 * PIXEL, 1.5 * PIXEL), c_fletch, true)
	# 描边（杆）
	draw_rect(Rect2(-6.0 * PIXEL, -0.6 * PIXEL, 12.0 * PIXEL, 1.2 * PIXEL), c_rim, false, 1.0)
