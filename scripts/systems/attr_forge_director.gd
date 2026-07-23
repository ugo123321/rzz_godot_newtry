extends Node2D
class_name AttrForgeDirector

# 属性打造关导演（v2）：摆动绳子 + 掉落 + 沉降骨架。
# v2 改动：
#   - block 生成时随机绑 1 个 forge buff（idx + 短名 + delta） → player 字段不变
#   - 结算时（10 块都落完 + 沉降稳定）把所有「存活且坐落在地基附近」的 block 的 buff 一次性传回 battle
#   - 移除上方紫色 halo；保留 sparkle 旋转点（精简到 4 个）
#   - 堆叠计数 HUD 移到屏幕右侧，避免和画线轨迹重叠

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const EnhancementBlockScript = preload("res://scripts/entities/enhancement_block.gd")

enum Phase { IDLE, PLAYING, FINISHING, DONE }

# 8 个 forge buff（与 player.apply_forge_buff 的 idx 对齐）
# short_name 是方块上显示的短名（96px 方块容不下完整中文）
const FORGE_BUFF_TABLE: Array = [
	{"idx": 0, "name_cn": "基础生命",   "short_name": "生命", "delta":  0.5},
	{"idx": 1, "name_cn": "基础攻击力", "short_name": "攻击", "delta":  0.03},
	{"idx": 2, "name_cn": "气力上限",   "short_name": "气力", "delta":  0.03},
	{"idx": 3, "name_cn": "暴击率",     "short_name": "暴击", "delta":  0.03},
	{"idx": 4, "name_cn": "移速",       "short_name": "移速", "delta":  0.03},
	{"idx": 5, "name_cn": "攻速",       "short_name": "攻速", "delta":  0.03},
	{"idx": 6, "name_cn": "气力恢复",   "short_name": "恢复", "delta":  0.03},
	{"idx": 7, "name_cn": "画线消耗",   "short_name": "画线", "delta": -0.03},
]

var phase: int = Phase.IDLE
var blocks_left := 0
# blocks_dropped 每项：{block, buff_idx, name_cn, short_name, delta, settled_once, alive}
var blocks_dropped: Array = []
# v3：当前悬挂中（还没扔下去）那块的预选 buff — 用于在 _draw_preview_block 上显示属性
var _pending_buff: Dictionary = {}
var ground_y := 0.0
var px_per_meter := 36.0
var block_size_px := 96.0
var swing_speed := 1.5
var swing_amplitude := 120.0
var swing_center_x := 360.0
var swing_t := 0.0
var rope_drop_y := 120.0
var rope_y := 80.0
var ground_static: StaticBody2D
var _battle: Node = null
var _logical_w := 720.0
var _logical_h := 1280.0
var _phase_timer := 0.0
# 实时计算（每帧重算）— 「目前还稳在地基上」的块数
var _live_stacked := 0
# 碰撞粒子专用绘制层（z_index 高于方块，避免被方块本体遮挡）
var _particle_canvas: Node2D = null
# 反馈提示：跟踪上一帧"在地基上的 block instance id"集合，
# 新增 id → 触发"属性增加"，消失 id → 触发"属性减少"。
var _prev_stacked_ids: Dictionary = {}
# 最新一条反馈大字：{text, color, timer, duration}；新一条覆盖旧一条。
var _feedback_msg: Dictionary = {}
const FEEDBACK_DURATION := 1.2
const FEEDBACK_RISE_PX := 80.0
const FEEDBACK_FONT_SIZE := 56
const FEEDBACK_COLOR_GAIN := Color("#5eff90")
const FEEDBACK_COLOR_LOSS := Color("#ff5e5e")


func reset() -> void:
	phase = Phase.IDLE
	blocks_left = 0
	for entry in blocks_dropped:
		var b = entry.get("block", null)
		if is_instance_valid(b):
			b.queue_free()
	blocks_dropped.clear()
	_pending_buff = {}
	_phase_timer = 0.0
	_live_stacked = 0
	if is_instance_valid(ground_static):
		ground_static.queue_free()
	ground_static = null
	if is_instance_valid(_particle_canvas):
		_particle_canvas.queue_free()
	_particle_canvas = null
	_prev_stacked_ids = {}
	_feedback_msg = {}
	# v3：把相机平滑拉回 _initial_camera_y，让玩家从打造门长出时画面对齐。
	# 直接同步设值（reset 是单帧动作，没有 await 余地）
	if _battle and _battle.camera:
		_battle.camera.global_position = Vector2(_battle._initial_camera_x, _battle._initial_camera_y)


func begin(battle: Node) -> void:
	reset()
	_battle = battle
	px_per_meter = float(GameConfig.get_tuning("house_px_per_meter", 36))
	# v3：方块更大（3.4m × 36px/m ≈ 122px），地基也跟随；摆幅 / 速度保持 v2 节奏。
	block_size_px = float(GameConfig.get_tuning("forge_block_size_m", 3.4)) * px_per_meter
	swing_speed = float(GameConfig.get_tuning("forge_swing_speed", 1.5))
	swing_amplitude = float(GameConfig.get_tuning("forge_swing_amplitude_px", 120))
	# v3：绳子末端再往下放（120 → 280），更靠近地基，降低难度。
	rope_drop_y = float(GameConfig.get_tuning("forge_rope_drop_y", 280))
	_logical_w = float(GameConfig.get_tuning("logical_width", 720))
	_logical_h = float(GameConfig.get_tuning("logical_height", 1280))
	swing_center_x = _logical_w * 0.5
	ground_y = _logical_h - 80.0
	blocks_left = int(GameConfig.get_tuning("forge_block_count", 10))
	_setup_static_geometry()
	_setup_particle_canvas()
	_recompute_rope_y()
	# 预选第 1 块的 buff（preview 上要显示）
	_roll_next_pending_buff()
	phase = Phase.PLAYING
	_phase_timer = 0.0
	swing_t = 0.0
	visible = true
	queue_redraw()


# v3：地基宽度从 block_size+8 提升到 block_size+24，匹配更大的方块尺寸。
func _setup_static_geometry() -> void:
	ground_static = StaticBody2D.new()
	ground_static.name = "ForgeGround"
	add_child(ground_static)
	var g_shape := RectangleShape2D.new()
	g_shape.size = Vector2(block_size_px + 24.0, 60.0)
	var g_coll := CollisionShape2D.new()
	g_coll.shape = g_shape
	ground_static.global_position = Vector2(swing_center_x, ground_y + 30.0)
	ground_static.add_child(g_coll)


# 粒子专用绘制层：z_index=5（方块默认 0），强制画在方块本体之上。
# z_relative=false 让它不继承父节点 z_index=30，避免和外部 hit_fx_overlay 抢层。
func _setup_particle_canvas() -> void:
	if is_instance_valid(_particle_canvas):
		_particle_canvas.queue_free()
	_particle_canvas = Node2D.new()
	_particle_canvas.name = "ForgeParticleCanvas"
	_particle_canvas.z_index = 5
	_particle_canvas.z_as_relative = true
	add_child(_particle_canvas)
	_particle_canvas.draw.connect(_draw_particles_layer)


func _draw_particles_layer() -> void:
	if _battle and _battle.particles:
		_battle.particles.draw_particles(_particle_canvas)


# v3：随机选下一块预绑 buff，供 _draw_preview_block 显示
func _roll_next_pending_buff() -> void:
	if blocks_left <= 0:
		_pending_buff = {}
		return
	_pending_buff = FORGE_BUFF_TABLE[randi() % FORGE_BUFF_TABLE.size()]


func _recompute_rope_y() -> void:
	# 绳子尾端比原盖房子更低（更接近地基） — rope_drop_y 比 build_house 大约低 40px。
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	rope_y = cam_y - _logical_h * 0.42 + rope_drop_y


func update(delta: float) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE:
		return
	swing_t += delta
	_sweep_off_screen()
	# 每帧重新计算「还稳在地基上」的块数（用于右侧 HUD 实时显示）
	_live_stacked = _count_surviving_blocks_on_ground().size()
	# 反馈差异检测：新增 id → "属性增加"，消失 id → "属性减少"
	_detect_stack_changes()
	# 反馈大字 timer
	if not _feedback_msg.is_empty():
		var t: float = float(_feedback_msg.get("timer", 0.0)) - delta
		if t <= 0.0:
			_feedback_msg = {}
		else:
			_feedback_msg["timer"] = t
		queue_redraw()
	# v4：相机随塔顶平滑跟随（塔长起来时往上挪、塔塌时往下挪），保证绳子永远高于塔顶
	_update_camera()
	if phase == Phase.PLAYING:
		if blocks_left <= 0 and _all_blocks_settled():
			phase = Phase.FINISHING
			_phase_timer = 0.0
		queue_redraw()
		if is_instance_valid(_particle_canvas):
			_particle_canvas.queue_redraw()
		_recompute_rope_y()
	elif phase == Phase.FINISHING:
		_phase_timer += delta
		queue_redraw()
		if is_instance_valid(_particle_canvas):
			_particle_canvas.queue_redraw()
		_recompute_rope_y()
		if _phase_timer >= 1.0:
			phase = Phase.DONE
			var surviving: Array = _count_surviving_blocks_on_ground()
			if _battle and _battle.has_method("on_attr_forge_phase_done"):
				_battle.on_attr_forge_phase_done(surviving)


func _sweep_off_screen() -> void:
	# 跌出屏幕的方块释放掉。entry 字段 alive 标记是否还存活 — 这里直接从数组移除。
	var i := blocks_dropped.size() - 1
	while i >= 0:
		var entry = blocks_dropped[i]
		var b = entry.get("block", null)
		if not is_instance_valid(b):
			blocks_dropped.remove_at(i)
			i -= 1
			continue
		var off_bottom: bool = b.global_position.y > ground_y + 600.0
		var off_side: bool = absf(b.global_position.x - swing_center_x) > _logical_w * 0.8
		if off_bottom or off_side:
			b.queue_free()
			blocks_dropped.remove_at(i)
		i -= 1


# 返回当前还「稳坐地基附近」的 block 对应的 buff 列表（结算时调）。
# 条件：is_settled AND 在地基纵向以上 AND 横向落在地基覆盖范围内（_logical_w * 0.55 阈值，比 sweep 的 0.8 更严，避免边滚边算）
func _count_surviving_blocks_on_ground() -> Array:
	var out: Array = []
	for entry in blocks_dropped:
		var b = entry.get("block", null)
		if not is_instance_valid(b):
			continue
		if not b.is_settled:
			continue
		if b.global_position.y >= ground_y:
			continue
		if absf(b.global_position.x - swing_center_x) > _logical_w * 0.55:
			continue
		out.append({
			"buff_idx": int(entry.get("buff_idx", -1)),
			"name_cn": str(entry.get("name_cn", "")),
			"short_name": str(entry.get("short_name", "")),
			"delta": float(entry.get("delta", 0.0)),
		})
	return out


func _all_blocks_settled() -> bool:
	# blocks_dropped 里只剩「还在场上」的方块（掉出屏幕的已被 _sweep_off_screen 移除）。
	# 用 block.is_settled 判定：physics_process 跑完 SETTLE_TIME=0.35s 才置 true，
	# 涵盖角速度，且排除刚 spawn 时 linear_velocity=ZERO 的误判。
	for entry in blocks_dropped:
		var b = entry.get("block", null)
		if not is_instance_valid(b):
			continue
		if not b.is_settled:
			return false
	return true


# 返回当前还「稳坐地基附近」的 block id 集合（用于检测堆叠状态变化反馈）。
# 与 _count_surviving_blocks_on_ground 用同样的判定规则，但只返回 instance id 集合，便于差异比对。
func _live_stacked_block_ids() -> Dictionary:
	var out: Dictionary = {}
	for entry in blocks_dropped:
		var b = entry.get("block", null)
		if not is_instance_valid(b):
			continue
		if not b.is_settled:
			continue
		if b.global_position.y >= ground_y:
			continue
		if absf(b.global_position.x - swing_center_x) > _logical_w * 0.55:
			continue
		out[b.get_instance_id()] = true
	return out


# 每帧比对 _prev_stacked_ids vs current_ids：
#   新增 id（之前没堆稳，现在堆稳了）→ "属性增加" 绿色大字
#   消失 id（之前堆稳，现在掉了出去或翻了下来）→ "属性减少" 红色大字
func _detect_stack_changes() -> void:
	var current_ids: Dictionary = _live_stacked_block_ids()
	var gained := 0
	var lost := 0
	for id in current_ids:
		if not _prev_stacked_ids.has(id):
			gained += 1
	for id in _prev_stacked_ids:
		if not current_ids.has(id):
			lost += 1
	# 同一帧若 gained 和 lost 都有（罕见，比如新方块挤掉旧方块），优先显示损失（玩家更关心扣分）
	if lost > 0:
		_spawn_feedback_msg("属性减少", FEEDBACK_COLOR_LOSS)
	elif gained > 0:
		_spawn_feedback_msg("属性增加", FEEDBACK_COLOR_GAIN)
	_prev_stacked_ids = current_ids


func _spawn_feedback_msg(text: String, color: Color) -> void:
	_feedback_msg = {
		"text": text,
		"color": color,
		"timer": FEEDBACK_DURATION,
		"duration": FEEDBACK_DURATION,
	}
	queue_redraw()


# v4：当前塔顶 world-y（最高沉稳块的顶边）。无沉稳块时返回 ground_y（地基自身）。
# 过滤条件与 _count_surviving_blocks_on_ground 一致，保证镜头跟随和结算计数同步。
func _compute_tower_top_y() -> float:
	var top_y := ground_y
	for entry in blocks_dropped:
		var b = entry.get("block", null)
		if not is_instance_valid(b):
			continue
		if not b.is_settled:
			continue
		if b.global_position.y >= ground_y:
			continue
		if absf(b.global_position.x - swing_center_x) > _logical_w * 0.55:
			continue
		var block_top: float = b.global_position.y - block_size_px * 0.5
		if block_top < top_y:
			top_y = block_top
	return top_y


# v5：相机随塔顶平滑跟随，从第 1 块就开始挪。
# 公式：target_cam_y = tower_top_y + (initial_cam_y - ground_y)
#   即「塔顶 -> 相机中心」的相对距离永远 = 初始「地基 -> 相机中心」距离。
# 0 块时 tower_top == ground_y → target == initial_cam_y（不动）
# 1 块时 tower_top 上移 block_size → target 上移 block_size（相机随之上移一块）
# 塔塌时 tower_top 下移 → target 下移 → lerp 平滑拉回
# 不再钳上限（让相机自然随塔顶任意上移）；下限同样不钳（塔塌只能回到 initial）
func _update_camera() -> void:
	if _battle == null or _battle.camera == null:
		return
	var initial_cam_y: float = _logical_h * 0.5  # 默认相机中心 y（= _initial_camera_y）
	var tower_top: float = _compute_tower_top_y()
	# 相机额外下偏：让屏底容下完整一块（block_size_px*0.55≈67px + 原 80px = 147px > 122px 整块 + 25px 边距）。
	var camera_y_offset: float = block_size_px * 0.55
	var target_cam_y: float = tower_top + (initial_cam_y - ground_y) + camera_y_offset
	var current_cam_y: float = _battle.camera.global_position.y
	var lerp_factor: float = 0.10
	_battle.camera.global_position.y = lerpf(current_cam_y, target_cam_y, lerp_factor)


func handle_drop_click() -> void:
	if phase != Phase.PLAYING:
		return
	if blocks_left <= 0:
		return
	# v3：使用预选的 _pending_buff（preview 上展示过那个）；若空（理论上不应发生）则现选
	var buff: Dictionary = _pending_buff if not _pending_buff.is_empty() else FORGE_BUFF_TABLE[randi() % FORGE_BUFF_TABLE.size()]
	blocks_left -= 1
	var b_idx: int = int(buff.get("idx", -1))
	var b_name_cn: String = str(buff.get("name_cn", ""))
	var b_short: String = str(buff.get("short_name", ""))
	var b_delta: float = float(buff.get("delta", 0.0))
	var hang_x := _rope_tip_x()
	var hang_y := rope_y + 40.0
	var block = EnhancementBlockScript.new()
	add_child(block)
	block.setup(block_size_px, b_idx, b_short, b_delta)
	if _battle and _battle.particles:
		block.set_particles_ref(_battle.particles)
	block.global_position = Vector2(hang_x, hang_y)
	block.linear_velocity = Vector2.ZERO
	blocks_dropped.append({
		"block": block,
		"buff_idx": b_idx,
		"name_cn": b_name_cn,
		"short_name": b_short,
		"delta": b_delta,
		"alive": true,
	})
	swing_t += 0.05
	# 为下一块预选 buff（如果还有剩余）
	_roll_next_pending_buff()
	queue_redraw()


func _rope_tip_x() -> float:
	return swing_center_x + sin(swing_t * swing_speed) * swing_amplitude


# === 绘制 ===

func _draw() -> void:
	if phase == Phase.IDLE:
		return
	# v3 修正：小游戏场景仍然画自己的深紫渐变背景（不是 forge_ground tile）。
	# forge_ground 紫色 tile 只用于"看见打造门"的过渡场景；玩家跳进门后切到小游戏
	# 场景，要看到摆动绳子 / 强化块 / 这个全屏渐变背景 —— 即原来的视觉。
	_draw_background()
	_draw_ambient_sparkles()
	_draw_ground()
	_draw_swing_rope()
	_draw_stack_counter_hud()
	_draw_feedback_msg()


func _draw_background() -> void:
	# 深紫渐变（顶 -> 底）— 用 3 段平行四边形堆出渐变感
	var top_color := Color("#1a0e33")
	var mid_color := Color("#2a1a55")
	var bot_color := Color("#0a0518")
	var top_band := _logical_h * 0.4
	var bot_band := _logical_h * 0.7
	draw_rect(Rect2(-_logical_w, ground_y - 4000.0, _logical_w * 3.0, top_band + 4000.0), top_color)
	draw_rect(Rect2(-_logical_w, ground_y - 4000.0 + top_band, _logical_w * 3.0, bot_band - top_band), mid_color)
	draw_rect(Rect2(-_logical_w, ground_y - 4000.0 + bot_band, _logical_w * 3.0, 4500.0 - bot_band), bot_color)
	# v2: 移除上方呼吸 halo（紫色圆圈），跟玩家画的线视觉打架


func _draw_ambient_sparkles() -> void:
	# 4 个旋转 sparkle 像素点（紫/青交替）— v2 从 6 个减到 4 个避免拥挤
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	var center := Vector2(swing_center_x, cam_y - _logical_h * 0.42 - 40.0)
	var sparkle_t := swing_t * 2.5
	for i in range(4):
		var ang := sparkle_t + TAU * float(i) / 4.0
		var r: float = 180.0 + 14.0 * sin(swing_t * 3.0 + float(i))
		var p := center + Vector2(cos(ang), sin(ang)) * r
		var on_flicker := (int(Time.get_ticks_msec() / 80) + i) % 2 == 0
		if not on_flicker:
			continue
		var col := Color("#c8a8ff") if i % 2 == 0 else Color("#a8e8ff")
		draw_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), col)


func _draw_ground() -> void:
	# 底色（深紫地表条）
	draw_rect(Rect2(-_logical_w, ground_y, _logical_w * 3.0, 200.0), Color("#100620"))
	draw_rect(Rect2(-_logical_w, ground_y, _logical_w * 3.0, 5.0), Color("#5536a8"))
	# 地基本体（高亮 1 块宽地基）
	var fx := swing_center_x - (block_size_px + 8.0) * 0.5
	var fy := ground_y - 4.0
	draw_rect(Rect2(fx - 2.0, fy - 2.0, block_size_px + 12.0, 16.0), Color("#1a0e33"))
	draw_rect(Rect2(fx, fy, block_size_px + 8.0, 12.0), Color("#5536a8"))
	draw_rect(Rect2(fx + 2.0, fy + 2.0, block_size_px + 4.0, 8.0), Color("#8a5cff"))
	# 地基上画十字 rune 印记
	var r := 4.0
	var cx := swing_center_x
	var cy := fy + 6.0
	var sigil := Color("#c8a8ff")
	draw_rect(Rect2(cx - r * 0.5, cy - r * 0.5, r, r), sigil)
	draw_rect(Rect2(cx - r * 1.5 - 1.0, cy - r * 0.5, r, r), sigil)
	draw_rect(Rect2(cx + r * 0.5 + 1.0, cy - r * 0.5, r, r), sigil)


func _draw_swing_rope() -> void:
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	var rope_anchor := Vector2(swing_center_x, cam_y - _logical_h * 0.42)
	var tip_x: float = _rope_tip_x()
	var rope_tip := Vector2(tip_x, rope_anchor.y + rope_drop_y)
	var dark := Color("#2a1a55")
	var bright := Color("#8a5cff")
	var steps := 14
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := rope_anchor.lerp(rope_tip, t)
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), dark)
		if i % 2 == 0:
			draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), bright)
	# 悬挂强化块预览
	if blocks_left > 0 and phase == Phase.PLAYING:
		_draw_preview_block(rope_tip + Vector2(0.0, block_size_px * 0.5))


func _draw_preview_block(center: Vector2) -> void:
	var half := block_size_px * 0.5
	var outline := Color("#1a0e33")
	var mid := Color("#2a1a55")
	var base := Color("#5536a8")
	var light := Color("#8a5cff")
	var hl := Color("#c8a8ff")
	draw_rect(Rect2(center.x - half, center.y - half, block_size_px, block_size_px), outline)
	draw_rect(Rect2(center.x - half + 2.0, center.y - half + 2.0, block_size_px - 4.0, block_size_px - 4.0), mid)
	draw_rect(Rect2(center.x - half + 4.0, center.y - half + 4.0, block_size_px - 8.0, block_size_px - 8.0), base)
	draw_rect(Rect2(center.x - half + 7.0, center.y - half + 7.0, block_size_px - 14.0, block_size_px - 14.0), light)
	var flicker_on := int(Time.get_ticks_msec() / 80) % 2 == 0
	var hl_color := hl if flicker_on else Color(hl.r, hl.g, hl.b, 0.55)
	draw_rect(Rect2(center.x - half + 6.0, center.y - half + 6.0, block_size_px - 12.0, 3.0), hl_color)
	# v3：在悬挂预览块上画出预选 buff（短名 + ±X%），让玩家在掉之前就看到下一块给什么
	if not _pending_buff.is_empty():
		var short_name := str(_pending_buff.get("short_name", ""))
		var delta: float = float(_pending_buff.get("delta", 0.0))
		var text_color := Color("#1a0e33") if delta >= 0.0 else Color("#0a2a3a")
		PixelUi.draw_pixel_text(
			self,
			short_name,
			Vector2(center.x, center.y - block_size_px * 0.16),
			24,
			text_color,
			HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER,
			true
		)
		var sign_str := "+" if delta >= 0.0 else ""
		var pct := int(round(delta * 100.0))
		PixelUi.draw_pixel_text(
			self,
			"%s%d%%" % [sign_str, pct],
			Vector2(center.x, center.y + block_size_px * 0.18),
			30,
			text_color,
			HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER,
			true
		)


# v3: 单层文字（去掉 v2 的 glow 叠层，避免视觉上像 "两个数字重叠"）
func _draw_stack_counter_hud() -> void:
	if _battle == null or _battle.camera == null:
		return
	var cam_pos: Vector2 = _battle.camera.global_position
	var hud_x := cam_pos.x + _logical_w * 0.5 - 28.0
	var hud_y := cam_pos.y - _logical_h * 0.25
	var rarity_color := _rarity_color_for_count(_live_stacked)
	var t := clampf(float(_live_stacked) / 10.0, 0.0, 1.0)
	var main_size := int(round(lerp(24.0, 60.0, t)))
	PixelUi.draw_pixel_text(
		self,
		"堆叠 ×%d" % _live_stacked,
		Vector2(hud_x, hud_y),
		main_size,
		rarity_color,
		HORIZONTAL_ALIGNMENT_RIGHT,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)
	PixelUi.draw_pixel_text(
		self,
		"剩余 %d 块" % blocks_left,
		Vector2(hud_x, hud_y + 52.0),
		18,
		Color("#c8a8ff"),
		HORIZONTAL_ALIGNMENT_RIGHT,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)


func _rarity_color_for_count(count: int) -> Color:
	if count <= 3:
		return Color("#ffffff")
	elif count <= 6:
		return Color("#5aa8e8")
	elif count <= 9:
		return Color("#8a5cff")
	else:
		return Color("#ff9820")


# 反馈大字：屏幕中心稍微上方，1.2s 内上浮 80px + 后半段淡出。
# 用相机坐标定位 — attr_forge 期间相机随塔顶动态上移，需跟随。
func _draw_feedback_msg() -> void:
	if _feedback_msg.is_empty():
		return
	var timer: float = float(_feedback_msg.get("timer", 0.0))
	var duration: float = float(_feedback_msg.get("duration", FEEDBACK_DURATION))
	if duration <= 0.0:
		return
	var elapsed: float = duration - timer
	var t: float = clampf(elapsed / duration, 0.0, 1.0)  # 0→1 across whole duration
	# 上浮：从中心 → 中心上方 FEEDBACK_RISE_PX
	var rise: float = -FEEDBACK_RISE_PX * t
	# alpha 包络：前 0.15s 淡入 → 中段 hold → 后 0.4s 淡出
	var alpha := 1.0
	var fade_in_t := 0.15 / duration
	var fade_out_t := 0.4 / duration
	if t < fade_in_t:
		alpha = t / fade_in_t
	elif t > 1.0 - fade_out_t:
		alpha = (1.0 - t) / fade_out_t
	# 屏幕中心稍微上方（用相机坐标）
	var cam_y: float = _logical_h * 0.5
	if _battle and _battle.camera:
		cam_y = _battle.camera.global_position.y
	var pos := Vector2(swing_center_x, cam_y - _logical_h * 0.18 + rise)
	var color: Color = _feedback_msg.get("color", Color.WHITE)
	color.a *= alpha
	var text: String = str(_feedback_msg.get("text", ""))
	# 深色描边（垂直/水平 +-3px 4 个偏移），让大字在紫色背景上仍然清晰
	var outline := Color(0.06, 0.04, 0.16, alpha)
	for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
		PixelUi.draw_pixel_text(
			self,
			text,
			pos + off,
			FEEDBACK_FONT_SIZE,
			outline,
			HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER,
			true
		)
	PixelUi.draw_pixel_text(
		self,
		text,
		pos,
		FEEDBACK_FONT_SIZE,
		color,
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)
