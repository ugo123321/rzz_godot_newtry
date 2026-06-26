extends Node
class_name AuraOrbitManager

# "环绕玩家旋转的纯视觉小物件"管理器（光之守护 / 吸血鬼 / 九命猫等）。
# - 不做命中扫描（剑系统由 SwordOrbitManager 负责）
# - 数据驱动：AURA_DRAW_DATA 字典，每条目自带 grid + palette + 闪烁 + 外发光 + 旋转参数
# - 每帧按 count_source 动态对齐 entries 数量（例：九命猫剩余次数减少时自动减少猫头）
# - 由 BattleController 调 setup() / reset() / update(delta, player) / draw_fx(canvas, below_monsters)

const AURA_PIXEL: float = 3.0  # 单位像素块边长

# count_source 解释：
# - int: 直接固定数量
# - String: 每帧 player.get(field)，bool→0/1，int→自身
const AURA_DRAW_DATA: Dictionary = {
	# ---------------- 光之守护：金色小圆盾 ----------------
	"holy_ward": {
		"body_grid": [
			[0, 0, 3, 3, 1, 3, 3, 0, 0],
			[0, 3, 2, 1, 9, 1, 2, 3, 0],
			[3, 2, 1, 9, 9, 9, 1, 2, 3],
			[3, 1, 9, 9, 0, 9, 9, 1, 3],
			[1, 9, 9, 0, 0, 0, 9, 9, 1],
			[3, 1, 9, 9, 0, 9, 9, 1, 3],
			[3, 2, 1, 9, 9, 9, 1, 2, 3],
			[0, 3, 2, 1, 9, 1, 2, 3, 0],
			[0, 0, 3, 3, 1, 3, 3, 0, 0],
		],
		"palette": {
			9: [Color("#fff8d8"), Color("#ffffff")],
			1: [Color("#ffd848"), Color("#ffe890")],
			2: [Color("#a87810"), null],
			3: [Color("#5a4810"), Color("#3a3008")],
		},
		"flicker_ms": 120,
		"glow_color": Color(1.0, 0.85, 0.35),
		"glow_inner_color": Color(0.7, 0.55, 0.15),
		"glow_r1": 16.0,
		"glow_r2": 10.0,
		"orbit_radius": 42.0,
		"orbit_speed": 3.0,
		"self_rot_speed": 1.5,
		"count_source": "angel_light_ward_active",
		"scale": 1.0,
	},
	# ---------------- 吸血鬼：紫黑小蝙蝠（2 帧翼展） ----------------
	"vampire_bat": {
		# 翅膀张开
		"body_grid": [
			[0, 3, 0, 0, 3, 0, 0, 3, 0],
			[3, 1, 3, 1, 9, 1, 3, 1, 3],
			[1, 2, 1, 9, 9, 9, 1, 2, 1],
			[0, 1, 2, 1, 9, 1, 2, 1, 0],
			[0, 0, 0, 3, 1, 3, 0, 0, 0],
		],
		# 翅膀收拢
		"body_grid_alt": [
			[0, 0, 0, 0, 3, 0, 0, 0, 0],
			[0, 3, 3, 1, 9, 1, 3, 3, 0],
			[3, 1, 2, 9, 9, 9, 2, 1, 3],
			[0, 3, 1, 2, 9, 2, 1, 3, 0],
			[0, 0, 0, 3, 1, 3, 0, 0, 0],
		],
		"palette": {
			9: [Color("#ff70b0"), Color("#ff90c8")],
			1: [Color("#a83078"), Color("#c04088")],
			2: [Color("#5a1840"), null],
			3: [Color("#200818"), Color("#100408")],
		},
		"flicker_ms": 100,
		"wing_flap_ms": 110,  # 两帧翅膀切换周期
		"glow_color": Color(0.65, 0.18, 0.45),
		"glow_inner_color": Color(0.35, 0.08, 0.25),
		"glow_r1": 14.0,
		"glow_r2": 8.0,
		"orbit_radius": 50.0,
		"orbit_speed": -2.5,  # 反向旋转
		"self_rot_speed": 0.0,  # 蝙蝠不自转
		"count_source": "demon_vampire_count",
		"scale": 0.9,
	},
	# ---------------- 九命猫：黄白小猫头剪影 ----------------
	"cat_head": {
		"body_grid": [
			[1, 0, 0, 0, 0, 0, 1],
			[1, 1, 2, 2, 2, 1, 1],
			[2, 2, 9, 2, 9, 2, 2],
			[2, 1, 2, 2, 2, 1, 2],
			[3, 2, 1, 9, 1, 2, 3],
			[0, 3, 2, 2, 2, 3, 0],
			[0, 0, 3, 3, 3, 0, 0],
		],
		"palette": {
			9: [Color("#ffffff"), Color("#fff4c0")],  # 眼睛/高光
			1: [Color("#ffd848"), Color("#ffe890")],  # 浅黄毛
			2: [Color("#a87810"), Color("#8a6010")],  # 中黄毛
			3: [Color("#3a2808"), null],              # 深色阴影
		},
		"flicker_ms": 140,
		"glow_color": Color(1.0, 0.8, 0.3),
		"glow_inner_color": Color(0.6, 0.45, 0.15),
		"glow_r1": 12.0,
		"glow_r2": 7.0,
		"orbit_radius": 34.0,
		"orbit_speed": 2.0,
		"self_rot_speed": 0.0,  # 猫头不自转
		"count_source": "multi_revive_extra",
		"scale": 0.85,
	},
}

var battle
# 每个 entry: {kind, angle, _anim_t, slot_in_kind, total_in_kind}
var entries: Array = []


func setup(battle_node) -> void:
	battle = battle_node


func reset() -> void:
	entries.clear()


# 给 battle._needs_fx_redraw 用 — 只要还有光环就持续 queue_redraw，否则远离敌人时光环会停转。
func has_active_fx() -> bool:
	return not entries.is_empty()


func update(delta: float, player) -> void:
	if player == null or battle == null:
		return
	if battle.state != GameState.PLAYING:
		return
	if player.hp <= 0:
		return
	if delta <= 0.0 or player.state == player.State.BULLET_TIME:
		return
	_align_entries(player)
	_advance_angles(delta)


func _align_entries(player) -> void:
	# 按 count_source 动态对齐每个 kind 的 entries 数量
	for kind in AURA_DRAW_DATA.keys():
		var data: Dictionary = AURA_DRAW_DATA[kind]
		var desired: int = _resolve_count(data.get("count_source", 0), player)
		var existing: int = 0
		for e in entries:
			if str(e.kind) == kind:
				existing += 1
		while existing < desired:
			entries.append({
				"kind": kind,
				# 按 index 均分角度（不同 kind 之间错开 0.4 rad 避免重叠）
				"angle": randf() * TAU,
				"_anim_t": 0.0,
			})
			existing += 1
		while existing > desired:
			for i in range(entries.size() - 1, -1, -1):
				if str(entries[i].kind) == kind:
					entries.remove_at(i)
					existing -= 1
					break
	# 重新计算每个 kind 的 total 和 slot（用于均分角度）
	var counters: Dictionary = {}
	for i in range(entries.size()):
		var k: String = str(entries[i].kind)
		var slot: int = int(counters.get(k, 0))
		entries[i]["slot_in_kind"] = slot
		counters[k] = slot + 1
	for i in range(entries.size()):
		var k2: String = str(entries[i].kind)
		entries[i]["total_in_kind"] = int(counters.get(k2, 1))


static func _resolve_count(src, player) -> int:
	if src is int:
		return int(src)
	if src is String:
		var v = player.get(src)
		if v is bool:
			return 1 if v else 0
		if v == null:
			return 0
		return int(v)
	return 0


func _advance_angles(delta: float) -> void:
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var data: Dictionary = AURA_DRAW_DATA.get(str(e.kind), {})
		var spin: float = float(data.get("orbit_speed", 2.0))
		e.angle = fposmod(float(e.angle) + spin * delta, TAU)
		e._anim_t = float(e._anim_t) + delta
		entries[i] = e


func draw_fx(canvas: Node2D, below_monsters: bool) -> void:
	if below_monsters:
		return
	if battle == null or battle.player == null:
		return
	var center: Vector2 = battle.player.global_position
	var t_ms: int = Time.get_ticks_msec()
	for e in entries:
		var kind: String = str(e.kind)
		var data: Dictionary = AURA_DRAW_DATA.get(kind, {})
		if data.is_empty():
			continue
		var orbit_r: float = float(data.get("orbit_radius", 40.0))
		var slot: int = int(e.get("slot_in_kind", 0))
		var total: int = int(e.get("total_in_kind", 1))
		# 每 kind 内按 slot 均分角度（基础角 + 等分偏移）
		var ang: float = float(e.angle) + float(slot) * TAU / float(maxi(1, total))
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * orbit_r
		var self_rot: float = float(t_ms) * 0.001 * float(data.get("self_rot_speed", 0.0))
		_draw_pixel_aura_body(canvas, pos, self_rot, kind, data)


func _draw_pixel_aura_body(canvas: Node2D, world_pos: Vector2, self_rot: float, kind: String, data: Dictionary) -> void:
	var t_ms: int = Time.get_ticks_msec()
	var flicker_ms: int = int(data.get("flicker_ms", 100))
	var flicker: bool = int(t_ms / flicker_ms) % 2 == 0
	var scale_val: float = float(data.get("scale", 1.0))
	var local: Vector2 = world_pos - canvas.global_position
	# 外发光圆晕（双层呼吸）
	var glow_pulse: float = 0.20 + 0.06 * sin(float(t_ms) * 0.005)
	var glow_outer: Color = data.get("glow_color", Color(1, 1, 1))
	glow_outer.a = glow_pulse
	canvas.draw_circle(local, float(data.get("glow_r1", 14.0)) * scale_val, glow_outer)
	var glow_inner: Color = data.get("glow_inner_color", Color(1, 1, 1))
	glow_inner.a = 0.12
	canvas.draw_circle(local, float(data.get("glow_r2", 9.0)) * scale_val, glow_inner)
	# 选用 grid：有 body_grid_alt 时按 wing_flap_ms 切换
	var grid: Array = data.get("body_grid", [])
	if data.has("body_grid_alt"):
		var flap_ms: int = int(data.get("wing_flap_ms", 110))
		if int(t_ms / flap_ms) % 2 == 1:
			grid = data["body_grid_alt"]
	# 旋转坐标系并画 grid
	canvas.draw_set_transform(local, self_rot, Vector2.ONE * scale_val)
	_draw_aura_grid(canvas, grid, data.get("palette", {}), flicker, AURA_PIXEL)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 复制自 summon_ability_manager._draw_summon_grid（避免跨 manager 耦合）
func _draw_aura_grid(canvas: CanvasItem, grid: Array, palette: Dictionary, flicker: bool, px: float) -> void:
	var rows: int = grid.size()
	if rows == 0:
		return
	var cols: int = (grid[0] as Array).size()
	var half_w: float = float(cols) * 0.5
	var half_h: float = float(rows) * 0.5
	for ry in range(rows):
		var row_arr: Array = grid[ry]
		for cx in range(cols):
			var layer: int = int(row_arr[cx])
			if layer == 0:
				continue
			var x: float = (float(cx) - half_w) * px
			var y: float = (float(ry) - half_h) * px
			# flicker 仅作用在 layer==3（外圈/阴影）
			var f: bool = flicker if layer == 3 else false
			canvas.draw_rect(Rect2(x, y, px, px), _aura_color(palette, layer, f))


func _aura_color(palette: Dictionary, layer: int, flicker: bool) -> Color:
	var pair = palette.get(layer, null)
	if pair == null:
		pair = palette.get(4, [Color.BLACK, null])
	if flicker and pair.size() >= 2 and pair[1] != null:
		return pair[1]
	return pair[0]
