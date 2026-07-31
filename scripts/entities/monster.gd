extends Node2D
class_name BattleMonster

const HP_BAR_Y_OFFSET := 9.0
const MELEE_REACH_PAD := 6.0
const MELEE_STOP_PAD := 2.0
const NAV_REPATH_SEC := 0.30      # 路径重算间隔
const NAV_WP_REACH_PX := 20.0     # 距 waypoint 小于此值视为抵达（半格）
const NAV_STUCK_SEC := 0.60       # 连续被挡超此时 → 强制 repath

var kind_id := "NORMAL"
var display_name := ""
var alive := true
var hp := 1
var max_hp := 1
var defense := 0
var attack := 10
var attack_interval := 1.0
var attack_timer := 0.0
var move_speed := 19.0
var hitbox_radius := 13.0
var can_move := true
var ranged := false
var attack_range := 0.0
var arrow_speed := 85.0
var ki_drain_on_hit := 0
var attack_pattern := ""
var projectile_effect := ""
var spread_count := 5
var spread_angle_deg := 50.0
var bounce_count := 1
var sprite_tint := Color.WHITE
var has_shield := false
var facing := 1.0
var color := Color.WHITE
var split_tier := 0
var max_split_tier := 0
var split_count := 0
var spawned_children := false
var stage_index_cached := 0
var frozen_timer := 0.0
var vulnerable_mark := false
var path_target_hit_count := 0
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_wp_idx: int = 0
var _nav_repath_timer: float = 0.0
var _nav_stuck_timer: float = 0.0
var _nav_last_player_cell: Vector2i = Vector2i(-1, -1)
# 沿障碍滑步的持久方向（+1=perp_a / -1=perp_b）。撞墙时定一次方向，直行通畅才清 0，
# 避免"每帧选离玩家更近一侧"在对称阻挡（玩家正对墙/树后方）时左右翻转→原地抖动。
var _nav_slide_sign: int = 0

# === v2 易伤/抗性字段 (默认 0，待 debuff/精英差异化时填充；v==1 路径完全忽略) ===
# VULN 层：同层加和。final ×= (1 + vuln_physical + 对应元素的 vuln_*)
var vuln_physical := 0.0
var vuln_fire := 0.0
var vuln_ice := 0.0
var vuln_thunder := 0.0
var vuln_poison := 0.0
# 元素抗性：进 ELEM 层。effective_elem_pct = elem_pct - elem_resist_[type]
var elem_resist_fire := 0.0
var elem_resist_ice := 0.0
var elem_resist_thunder := 0.0
var elem_resist_poison := 0.0
var dying := false
var death_delay := 0.0
var death_timer := 0.0
var death_fade_dur := 0.28
var death_flash := 0.0
var _death_base_scale := Vector2.ONE
var hurt_reaction_timer := 0.0
var burn_timer := 0.0
var burn_tick_timer := 0.0
var burn_dps := 0
# v2 burn DoT 快照玩家挂载时的 elem_fire 加成(elem_all_pct + elem_fire_pct)；
# tick 用这个 snapshot 算 ELEM 层，避免后续玩家面板变化让进行中的 DoT 抖动
var burn_elem_snapshot_pct := 0.0
var burn_tick_interval := 0.5
# v2 元素状态（Sheet4）
var poison_timer := 0.0
var poison_tick_timer := 0.0
var poison_per_tick := 0
var poison_elem_snapshot_pct := 0.0
var poison_tick_interval := 1.0
var paralyze_timer := 0.0
var slow_timer := 0.0
var slow_pct_active := 0.0
var proximity_slow_pct := 0.0  # sr=50 无下限术式：每帧由 dispatcher 写入（按到玩家距离线性插值）
var petrify_timer := 0.0        # sr=51 念力全场石化：>0 时怪物完全定身，anim modulate 变石灰色（视觉优先级最高）

# 冰减速状态着色（slow_timer > 0 时用）—— 水地块不再对怪物减速/染色（局内特殊地块只影响玩家）
const WATER_TINT_COLOR := Color(0.65, 0.85, 1.0, 1.0)
const WATER_TINT_BLEND := 0.45

# 精英化（与 stages.json 的 ELITE kind_id 是两个独立概念，可叠加）
# - 属性加成基于 monsters.json 原值算 extra（不被 stage 二次放大）
# - hp=2.0 表示「基础生命 +100%」(extra = base_hp × 1.0 加到当前 max_hp 上)
# - 隐形精英用 self.modulate.a 渐变（与 anim_sprite.modulate 状态染色互不影响）
# - 自爆精英在 begin_dying 末尾触发 AoE
const ELITE_CONFIG := {
	"bomb":    {"size": 1.80, "hp": 2.0, "def": 1.25, "spd": 1.00, "tint": Color(0.30, 0.28, 0.30), "aoe_r": 48.0, "aoe_dmg_mul": 2.5},
	"tank":    {"size": 1.80, "hp": 2.0, "def": 1.60, "spd": 0.75, "tint": Color(1.35, 1.15, 0.55)},
	"swift":   {"size": 1.50, "hp": 2.0, "def": 1.25, "spd": 1.30, "tint": Color(1.05, 0.70, 1.25)},
	"phantom": {"size": 1.50, "hp": 2.0, "def": 1.25, "spd": 1.00, "tint": Color(0.85, 0.85, 0.85)},
}
const ELITE_ICON_COLOR_HEX := "#ffd84a"
const PHANTOM_MIN_ALPHA := 0.18
const PHANTOM_FADE_DUR := 4.0

var elite_kind := ""
var elite_size_mult := 1.0
var _phantom_fade_time := 0.0
var _phantom_target_alpha := 1.0

var _sprite_folder := "Skeleton"
var _sprite_prefix := "Skeleton"
var spawn_lock_timer := 0.0
# 主题关：demon=暗红+黑气，angel=淡黄+圣光；属性 +15% 速度 +10% 防御
var _theme := ""

# === JUMPER 跳跃怪状态机 ===
# 0=idle(接近) 1=windup(酝酿2s) 2=airborne(跳出屏幕+脚下预警2s) 3=land_recover
var _jumper_state := 0
var _jumper_timer := 0.0
var _jumper_target := Vector2.ZERO
const JUMPER_WINDUP_TIME := 2.0
const JUMPER_AIR_TIME := 2.0          # 等同脚下预警时长
const JUMPER_RECOVER_TIME := 0.5
const JUMPER_SMASH_RADIUS := 70.0
const JUMPER_TRIGGER_RANGE := 200.0
const JUMPER_SMASH_DAMAGE_MUL := 1.6

# === LASER 激光怪状态机 ===
# 0=idle(冷却) 1=windup(红色路径预警2s) 2=fire(激光束) 3=recover
var _laser_state := 0
var _laser_timer := 0.0
var _laser_dir := Vector2.RIGHT
var _laser_hit := false
const LASER_WINDUP_TIME := 2.0
const LASER_FIRE_TIME := 0.45
const LASER_RECOVER_TIME := 1.2
const LASER_LENGTH := 1400.0
const LASER_HALF_WIDTH := 14.0
const LASER_DAMAGE_MUL := 1.4

# === DASHER 冲刺怪状态机 ===
# 0=idle(接近+冷却) 1=windup(蓄力变红,锁定方向) 2=dash(直线冲刺固定距离) 3=recover
var _dasher_state := 0
var _dasher_timer := 0.0          # windup/recover 通用倒计时
var _dasher_dash_dist_acc := 0.0  # 本轮已推进距离
var _dash_dir := Vector2.ZERO
var _has_hit_this_dash := false
var _dasher_cooldown_t := 0.0     # idle 内下次可触发倒计时
# json 扩展字段（setup 读取；缺省给安全默认）
var _dasher_trigger_range := 180.0
var _dasher_windup_sec := 0.6
var _dasher_dash_speed := 320.0
var _dasher_dash_distance := 220.0
var _dasher_recover_sec := 0.5
var _dasher_cooldown_sec := 1.5

# === TELEPORTER 瞬移怪状态机 ===
# 0=APPEAR(现身,播 teleport_in) 1=VISIBLE(发1发子弹+播attack,停2s)
# 2=DISAPPEAR(播 teleport_out) 3=GONE(隐形免疫1.5s,末尾画预警圈,再选位→APPEAR)
var _teleport_state := 0
var _teleport_timer := 0.0
var _teleport_next_pos := Vector2.ZERO
var _teleport_telegraphed := false
const TELEPORT_APPEAR_SEC := 0.18
const TELEPORT_VISIBLE_SEC := 2.0
const TELEPORT_DISAPPEAR_SEC := 0.18
const TELEPORT_GONE_SEC := 1.5
const TELEPORT_EDGE_MARGIN := 60.0
const TELEPORT_MIN_PLAYER_DIST := 160.0
const TELEPORT_TELEGRAPH_SEC := 0.30
const ANIM_TELEPORT_IN := "teleport_in"
const ANIM_TELEPORT_OUT := "teleport_out"

# === MINI_CENTIPEDE 迷你千足虫（直线冲锋撞击型，12 节等大方块，共享血量）===
enum Phase { REPOSITION, CHARGING }
var _code_drawn := false
var _centi_phase := Phase.REPOSITION
var _centi_segments: Array = []          # MiniCentipedeSegment 实例
var _centi_segment_count := 12
var _centi_segment_size := 11.0
var _centi_segment_spacing := 11.0
var _centi_segment_hitbox := 6.0
var _centi_charge_speed := 260.0
var _centi_reposition_delay := 0.5
var _centi_repos_timer := 0.3
var _charge_dir := Vector2.RIGHT
var _charge_entry := Vector2.ZERO
var _charge_target := Vector2.ZERO
var _has_hit_this_pass := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(monster_kind: String, stage_index: int, spawn_pos: Vector2, elite: String = "") -> void:
	kind_id = monster_kind
	stage_index_cached = stage_index
	var stats := GameConfig.scaled_monster_stats(monster_kind, stage_index)
	display_name = str(stats.get("name_cn", monster_kind))
	max_hp = int(stats.get("hp", 1))
	hp = max_hp
	defense = int(stats.get("def", 0))
	# v2 元素抗性 & 易伤（从 monsters.json 配置加载；缺省 0 = 中立）
	elem_resist_fire = float(stats.get("elem_resist_fire", 0.0))
	elem_resist_ice = float(stats.get("elem_resist_ice", 0.0))
	elem_resist_thunder = float(stats.get("elem_resist_thunder", 0.0))
	elem_resist_poison = float(stats.get("elem_resist_poison", 0.0))
	vuln_physical = float(stats.get("vuln_physical", 0.0))
	vuln_fire = float(stats.get("vuln_fire", 0.0))
	vuln_ice = float(stats.get("vuln_ice", 0.0))
	vuln_thunder = float(stats.get("vuln_thunder", 0.0))
	vuln_poison = float(stats.get("vuln_poison", 0.0))
	attack = int(stats.get("attack", 1))
	attack_interval = float(stats.get("attack_interval", 1.0))
	hitbox_radius = GameConfig.scale_world(float(stats.get("size", 13)))
	move_speed = float(stats.get("speed", 19))
	can_move = int(stats.get("can_move", 1)) != 0
	ranged = int(stats.get("ranged", 0)) != 0
	attack_range = float(stats.get("attack_range", 0))
	arrow_speed = float(stats.get("arrow_speed", 85.0))
	ki_drain_on_hit = int(stats.get("ki_drain_on_hit", 0))
	attack_pattern = str(stats.get("attack_pattern", ""))
	projectile_effect = str(stats.get("projectile_effect", ""))
	spread_count = int(stats.get("spread_count", 5))
	spread_angle_deg = float(stats.get("spread_angle_deg", 50.0))
	bounce_count = int(stats.get("bounce_count", 1))
	var tint_hex := str(stats.get("sprite_tint_hex", ""))
	if not tint_hex.is_empty():
		sprite_tint = Color(tint_hex)
	else:
		sprite_tint = Color.WHITE
	has_shield = kind_id == "SHIELD"
	max_split_tier = int(stats.get("max_split_tier", 0))
	split_count = int(stats.get("split_count", 0))
	color = Color(str(stats.get("color_hex", "#ffffff")))
	if kind_id == "MINI_CENTIPEDE":
		_centi_segment_count = int(stats.get("segment_count", 12))
		_centi_segment_size = float(stats.get("segment_size", 11.0))
		_centi_segment_spacing = float(stats.get("segment_spacing", 11.0))
		_centi_segment_hitbox = float(stats.get("segment_hitbox", 6.0))
		_centi_charge_speed = float(stats.get("charge_speed", 260.0))
		_centi_reposition_delay = float(stats.get("reposition_delay", 0.5))
	if kind_id == "DASHER":
		_dasher_trigger_range = float(stats.get("trigger_range", 180.0))
		_dasher_windup_sec = float(stats.get("windup_sec", 0.6))
		_dasher_dash_speed = float(stats.get("dash_speed", 320.0))
		_dasher_dash_distance = float(stats.get("dash_distance", 220.0))
		_dasher_recover_sec = float(stats.get("recover_sec", 0.5))
		_dasher_cooldown_sec = float(stats.get("cooldown_sec", 1.5))
	global_position = spawn_pos
	_sprite_folder = str(stats.get("character_folder", "Skeleton"))
	_sprite_prefix = str(stats.get("sprite_prefix", "Skeleton"))
	_apply_theme(stage_index)
	elite_kind = elite
	_apply_elite_modifier()
	_apply_sprite()


func _apply_theme(stage_idx: int) -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or not battle.has_method("get_stage_theme"):
		_theme = ""
		return
	_theme = String(battle.get_stage_theme(stage_idx))
	if _theme == "demon" or _theme == "angel":
		move_speed *= 1.15
		defense = int(round(float(defense) * 1.10))
		var theme_tint: Color = Color(1.4, 0.55, 0.55) if _theme == "demon" else Color(1.2, 1.15, 0.7)
		sprite_tint *= theme_tint


# 精英修饰：基于 monsters.json 原值算 hp/def/spd 加成（避免 stage 二次放大膨胀）；
# 体型直接乘 size_mult；染色与已有 sprite_tint 相乘叠加；phantom 写隐形目标 alpha
func _apply_elite_modifier() -> void:
	if elite_kind == "" or not ELITE_CONFIG.has(elite_kind):
		return
	var cfg: Dictionary = ELITE_CONFIG[elite_kind]
	elite_size_mult = float(cfg.size)
	var base := GameConfig.get_monster(kind_id)
	var base_hp: int = int(base.get("hp", 1))
	var base_def: int = int(base.get("def", 0))
	var base_speed: float = float(base.get("speed", 19))
	var hp_extra: int = int(round(float(base_hp) * (float(cfg.get("hp", 1.0)) - 1.0)))
	var def_extra: int = int(round(float(base_def) * (float(cfg.def) - 1.0)))
	var spd_extra: float = base_speed * (float(cfg.spd) - 1.0)
	max_hp = maxi(1, max_hp + hp_extra)
	hp = max_hp
	defense = maxi(0, defense + def_extra)
	move_speed = maxf(1.0, move_speed + spd_extra)
	hitbox_radius *= elite_size_mult
	var et: Color = cfg.tint
	sprite_tint = Color(sprite_tint.r * et.r, sprite_tint.g * et.g, sprite_tint.b * et.b, 1.0)
	if elite_kind == "phantom":
		_phantom_target_alpha = PHANTOM_MIN_ALPHA


func begin_spawn(duration: float = -1.0, target_scale: Vector2 = Vector2.ONE) -> void:
	if kind_id == "MINI_CENTIPEDE":
		spawn_lock_timer = 0.0
		attack_timer = attack_interval
		modulate.a = 1.0
		scale = target_scale
		_centi_phase = Phase.REPOSITION
		_centi_repos_timer = 0.3
		return
	if kind_id == "TELEPORTER":
		spawn_lock_timer = 0.0
		attack_timer = attack_interval
		modulate.a = 1.0
		scale = target_scale
		_teleport_state = 0
		_teleport_timer = TELEPORT_APPEAR_SEC
		_play_anim(ANIM_TELEPORT_IN, true)
		return
	if duration < 0.0:
		duration = float(GameConfig.get_tuning("monster_spawn_anim", 0.6))
	spawn_lock_timer = duration
	attack_timer = attack_interval
	modulate.a = 0.0
	scale = target_scale * 0.35
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, duration)
	tween.tween_property(self, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_spawn_anim_finished, CONNECT_ONE_SHOT)


func _on_spawn_anim_finished() -> void:
	spawn_lock_timer = 0.0
	attack_timer = attack_interval


func _apply_sprite() -> void:
	# MINI_CENTIPEDE：纯代码绘制，隐藏精灵帧
	if kind_id == "MINI_CENTIPEDE":
		var centi_sp := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if centi_sp:
			centi_sp.visible = false
		_code_drawn = true
		return
	var anim_sprite := sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite == null:
		push_warning("BattleMonster: AnimatedSprite2D not ready")
		return
	anim_sprite.sprite_frames = SpriteHelper.build_character_frames(_sprite_folder, _sprite_prefix)
	SpriteHelper.apply_pixel_art(anim_sprite)
	var scale_val := float(GameConfig.get_tuning("monster_sprite_scale", 1.0))
	anim_sprite.scale = Vector2.ONE * SpriteHelper.pixel_scale(scale_val) * elite_size_mult
	if sprite_tint != Color.WHITE:
		anim_sprite.modulate = sprite_tint
	if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	if not anim_sprite.animation_finished.is_connected(_on_animation_finished):
		anim_sprite.animation_finished.connect(_on_animation_finished)
	if kind_id == "TELEPORTER":
		_build_teleport_anims(anim_sprite)


# TELEPORTER：从 death 动画前 5 帧派生 teleport_out(正放)/teleport_in(倒放)。
# 在缓存 SpriteFrames 对象上幂等添加，多实例共享安全。
func _build_teleport_anims(anim_sprite: AnimatedSprite2D) -> void:
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	var frames := anim_sprite.sprite_frames
	if not frames.has_animation(SpriteHelper.ANIM_DEATH):
		return
	var n := frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if n < 5:
		return
	if not frames.has_animation(ANIM_TELEPORT_OUT):
		frames.add_animation(ANIM_TELEPORT_OUT)
		for i in range(5):
			frames.add_frame(
				ANIM_TELEPORT_OUT,
				frames.get_frame_texture(SpriteHelper.ANIM_DEATH, i),
				frames.get_frame_duration(SpriteHelper.ANIM_DEATH, i)
			)
		frames.set_animation_speed(ANIM_TELEPORT_OUT, 28.0)
		frames.set_animation_loop(ANIM_TELEPORT_OUT, false)
	if not frames.has_animation(ANIM_TELEPORT_IN):
		frames.add_animation(ANIM_TELEPORT_IN)
		for i in range(4, -1, -1):
			frames.add_frame(
				ANIM_TELEPORT_IN,
				frames.get_frame_texture(SpriteHelper.ANIM_DEATH, i),
				frames.get_frame_duration(SpriteHelper.ANIM_DEATH, i)
			)
		frames.set_animation_speed(ANIM_TELEPORT_IN, 28.0)
		frames.set_animation_loop(ANIM_TELEPORT_IN, false)


func _on_animation_finished() -> void:
	if dying or not alive:
		return
	var anim_sprite := sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if anim_sprite.animation in [SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_ATTACK]:
		if anim_sprite.animation == SpriteHelper.ANIM_HURT:
			hurt_reaction_timer = 0.0
		if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)


func get_hitbox_radius() -> float:
	return hitbox_radius


func get_feet_global_position() -> Vector2:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return global_position + Vector2(0.0, hitbox_radius)
	# 使用未缩放帧坐标；to_global 会再应用 sprite scale，避免重复乘缩放导致锚点下沉。
	var feet_local_y := SpriteHelper.FRAME_H * 0.5 * 0.88
	return anim_sprite.to_global(Vector2(0.0, feet_local_y))


func get_head_top_global_position() -> Vector2:
	# Necromancer（TELEPORTER）头部在 100px 帧里偏上（顶 y≈30，Skeleton 是 y≈42），
	# 默认 0.36 factor 算出的头顶偏低，血条会压到脸上 → 用更大 factor 把血条抬到头上方。
	var factor := 0.60 if kind_id == "TELEPORTER" else SpriteHelper.CHAR_HEAD_Y_FACTOR
	return SpriteHelper.get_character_head_top_global(
		_get_sprite(),
		global_position + Vector2(0.0, -hitbox_radius * 1.5),
		factor
	)


# 被树夹住时的脱困方向：把所有"挡住自己 next-pos"的树的反向推力相加并归一
func _escape_dir_from_trees(battle: Node) -> Vector2:
	if battle == null or not battle.has_method("get_active_trees"):
		return Vector2.ZERO
	var push := Vector2.ZERO
	for t in battle.get_active_trees():
		if not is_instance_valid(t):
			continue
		var to_self: Vector2 = global_position - t.global_position
		var d: float = to_self.length()
		if d <= 0.0001:
			push += Vector2(1.0, 0.0)
			continue
		var r: float = t.get_block_radius() + hitbox_radius
		if d < r + 8.0:
			# 离这棵树越近，推力越强（线性衰减）
			var weight: float = 1.0 - clampf(d / (r + 8.0), 0.0, 1.0)
			push += to_self / d * (0.4 + weight)
	if push == Vector2.ZERO:
		return Vector2.ZERO
	return push.normalized()


# 统一脱困方向（树 + 地形墙 + 放置块元素）。委托 battle.get_monster_escape_dir。
func _escape_dir(battle: Node, mover_radius: float) -> Vector2:
	if battle == null or not battle.has_method("get_monster_escape_dir"):
		return Vector2.ZERO
	return battle.get_monster_escape_dir(global_position, mover_radius)


func _melee_attack_range(player: BattlePlayer) -> float:
	if player == null:
		return GameConfig.scale_world(30.0)
	return player.get_effective_radius() + hitbox_radius + GameConfig.scale_world(MELEE_REACH_PAD)


func _melee_stop_distance(player: BattlePlayer) -> float:
	if player == null:
		return GameConfig.scale_world(26.0)
	return player.get_effective_radius() + hitbox_radius + GameConfig.scale_world(MELEE_STOP_PAD)


func is_combat_targetable() -> bool:
	# JUMPER 起跳后离屏，不可被攻击
	if _jumper_state == 2:
		return false
	# MINI_CENTIPEDE 头部纯驱动（画 12 节 + 状态机）；伤害目标只有 12 个节段，
	# 节段 0 已在头部位置，头部不再独立可击，避免一次命中双重扣血。
	if kind_id == "MINI_CENTIPEDE":
		return false
	# TELEPORTER 隐形期间不可选中
	if kind_id == "TELEPORTER" and _teleport_state == 3:
		return false
	return alive and not dying and spawn_lock_timer <= 0.0


func is_spawn_locked() -> bool:
	return spawn_lock_timer > 0.0


func update_death(delta: float) -> void:
	if not dying:
		return
	death_flash = maxf(0.0, death_flash - delta * 6.0)
	if death_delay > 0.0:
		death_delay -= delta
		_apply_death_modulate(1.0)
		return
	death_timer -= delta
	var alpha := clampf(death_timer / maxf(0.001, death_fade_dur), 0.0, 1.0)
	_apply_death_modulate(alpha)
	var shrink := lerpf(1.0, 0.72, 1.0 - alpha)
	scale = _death_base_scale * shrink
	if death_timer <= 0.0:
		_finish_death()


func _apply_death_modulate(alpha: float) -> void:
	var flash := 1.0 + death_flash * 0.25
	modulate = Color(flash, flash, flash, alpha)


func is_frozen() -> bool:
	# 旧 API：完全冻结视为 paralyze（雷麻痹同语义）
	return paralyze_timer > 0.0


func freeze(duration: float) -> void:
	# v5 freeze（完全不动）映射到 paralyze；v2 冰减速走 apply_freeze_slow
	paralyze_timer = maxf(paralyze_timer, duration)


# sr=51 念力：全场石化 — 完全定身 + 石灰色 tint（视觉优先级压过雷麻痹）。
# 用独立 petrify_timer 记录持续时长；paralyze_timer 同时置位保证真的不动。
func apply_petrify(duration: float) -> void:
	petrify_timer = maxf(petrify_timer, duration)
	paralyze_timer = maxf(paralyze_timer, duration)
	queue_redraw()


func take_damage(raw_damage: int, from_pos: Vector2) -> Dictionary:
	return _resolve_take_damage(DamageInfo.legacy(raw_damage), from_pos)


# 新路径：接收带元素/品类/快照的 DamageInfo，供 v2 emitter 使用
func take_damage_info(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	return _resolve_take_damage(info, from_pos)


func _resolve_take_damage(info: DamageInfo, from_pos: Vector2) -> Dictionary:
	if not alive or dying:
		return {"damage": 0, "is_crit": false}
	# TELEPORTER GONE 隐形期间免疫（防止接触/范围伤害穿透）
	if kind_id == "TELEPORTER" and _teleport_state == 3:
		return {"damage": 0, "is_crit": false}
	if has_shield:
		has_shield = false
		return {"damage": 0, "is_crit": false, "blocked_by_shield": true}
	var target_stats := {
		"defense": defense,
		"vulnerable_mark": vulnerable_mark,
		"vuln_physical": vuln_physical,
		"vuln_fire": vuln_fire,
		"vuln_ice": vuln_ice,
		"vuln_thunder": vuln_thunder,
		"vuln_poison": vuln_poison,
		"elem_resist_fire": elem_resist_fire,
		"elem_resist_ice": elem_resist_ice,
		"elem_resist_thunder": elem_resist_thunder,
		"elem_resist_poison": elem_resist_poison,
		"stage_index": stage_index_cached,
	}
	var res: Dictionary = DamageResolver.compute_damage(target_stats, info)
	if bool(res.get("vuln_consumed", false)):
		vulnerable_mark = false
	var actual := int(res.get("damage", 0))
	hp -= actual
	var started_dying := false
	if hp <= 0:
		hp = 0
		var battle := get_tree().get_first_node_in_group("battle")
		var delay := 0.0
		if battle and battle.combat:
			delay = battle.combat.schedule_death_fade()
		started_dying = begin_dying(delay)
	else:
		facing = 1.0 if from_pos.x >= global_position.x else -1.0
		var anim_sprite := _get_sprite()
		if anim_sprite:
			anim_sprite.flip_h = facing < 0
		_play_hurt_anim()
	queue_redraw()
	return {"damage": actual, "is_crit": bool(res.get("is_crit", false)), "started_dying": started_dying}


func apply_burn_dot(duration: float, dps: int) -> void:
	_apply_burn_internal(duration, dps, 0.0)


# v2 路径：发射端可顺便快照 elem_fire 加成，让 tick 享受元素增伤(v==2 启用时生效)
func apply_burn_dot_with_snapshot(duration: float, dps: int, elem_pct: float) -> void:
	_apply_burn_internal(duration, dps, elem_pct)


# Sheet4 火元素 burn DoT：snapshot_atk × 0.30/sec × ELEM × proc_freq
# proc_freq 越高，tick 间隔越短（频率越高）；duration 固定 2.0s
func apply_burn_dot_v2(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if not alive or dying:
		return
	# tick 间隔随 proc_freq 缩短：base 0.5s / (1 + proc_freq)
	burn_tick_interval = maxf(0.05, 0.5 / maxf(0.01, 1.0 + proc_freq_pct))
	# 每 tick 伤害：snapshot_atk × 0.30(/sec) × tick_interval
	var per_sec := maxf(1.0, snapshot_atk * 0.30)
	var per_tick: int = int(max(1, round(per_sec * burn_tick_interval)))
	burn_timer = maxf(burn_timer, 2.0)
	burn_tick_timer = 0.0
	burn_dps = maxi(burn_dps, per_tick)
	burn_elem_snapshot_pct = maxf(burn_elem_snapshot_pct, elem_pct)


# Sheet4 冰元素 freeze+slow：立即一次冰伤 + 减速持续 1.5s（不彻底冻结，那是 paralyze）
func apply_freeze_slow(snapshot_atk: float, elem_pct: float, slow_bonus: float) -> void:
	if not alive or dying:
		return
	# 立即一次冰伤：snapshot_atk × 0.30 × (1 + elem_pct - resist)
	var elem_layer: float = maxf(0.0, 1.0 + elem_pct - elem_resist_ice)
	var hit_dmg: int = int(max(1, round(snapshot_atk * 0.30 * elem_layer)))
	hp = maxi(0, hp - hit_dmg)
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.combat:
		battle.combat.spawn_damage_number(global_position + Vector2(0.0, -8.0), hit_dmg, false, false, Color("#88ccff"))
	if hp <= 0:
		var delay := 0.0
		if battle and battle.combat:
			delay = battle.combat.schedule_death_fade()
		if begin_dying(delay):
			EventBus.monster_killed.emit(self)
		return
	# 减速 + 计时
	slow_pct_active = maxf(slow_pct_active, 0.30 + slow_bonus)
	slow_timer = maxf(slow_timer, 1.5)
	queue_redraw()


# Sheet4 毒元素 poison DoT：snapshot_atk × 0.30/sec × ELEM × proc_freq；持续 3.0s
func apply_poison_dot(snapshot_atk: float, elem_pct: float, proc_freq_pct: float) -> void:
	if not alive or dying:
		return
	poison_tick_interval = maxf(0.1, 1.0 / maxf(0.01, 1.0 + proc_freq_pct))
	var per_sec := maxf(1.0, snapshot_atk * 0.30)
	var per_tick: int = int(max(1, round(per_sec * poison_tick_interval)))
	poison_timer = maxf(poison_timer, 3.0)
	poison_tick_timer = 0.0
	poison_per_tick = maxi(poison_per_tick, per_tick)
	poison_elem_snapshot_pct = maxf(poison_elem_snapshot_pct, elem_pct)


# Sheet4 雷链尾麻痹：完全停止 N 秒
func apply_paralyze(duration: float) -> void:
	if not alive or dying:
		return
	paralyze_timer = maxf(paralyze_timer, duration)
	queue_redraw()


func _apply_burn_internal(duration: float, dps: int, elem_pct: float) -> void:
	if not alive or dying:
		return
	burn_timer = maxf(burn_timer, duration)
	burn_tick_timer = 0.0
	burn_dps = maxi(burn_dps, dps)
	# 取较高 snapshot：让"重新点燃"时享受更强加成
	burn_elem_snapshot_pct = maxf(burn_elem_snapshot_pct, elem_pct)


func can_split() -> bool:
	return kind_id == "SPLITTER" and split_tier < max_split_tier and not spawned_children


func begin_dying(stagger_delay: float) -> bool:
	if dying or not alive:
		return false
	dying = true
	if kind_id == "MINI_CENTIPEDE":
		for seg in _centi_segments:
			if is_instance_valid(seg):
				seg.dying = true
				seg.alive = false
	death_fade_dur = float(GameConfig.get_tuning("monster_death_fade", 0.28))
	var death_anim_dur := _death_anim_duration()
	death_delay = maxf(0.0, stagger_delay) + death_anim_dur
	death_timer = death_fade_dur
	death_flash = 0.35
	_death_base_scale = scale
	modulate = Color.WHITE
	var pop_tween := create_tween()
	pop_tween.tween_property(self, "scale", _death_base_scale * 1.08, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "scale", _death_base_scale, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	queue_redraw()
	_play_anim(SpriteHelper.ANIM_DEATH, true)
	if can_split() and not spawned_children:
		var battle := get_tree().get_first_node_in_group("battle")
		if battle and battle.spawner:
			battle.spawner.spawn_split_children(self)
		spawned_children = true
	if elite_kind == "bomb":
		_trigger_bomb_aoe()
	return true


func die() -> void:
	begin_dying(0.0)


func _finish_death() -> void:
	alive = false
	dying = false
	var battle := get_tree().get_first_node_in_group("battle")
	if kind_id == "MINI_CENTIPEDE":
		for seg in _centi_segments:
			if is_instance_valid(seg):
				if battle and battle.has_method("get") and battle.get("spawner") != null:
					battle.spawner.unregister_monster(seg)
				seg.queue_free()
		_centi_segments.clear()
	if battle and battle.has_method("get") and battle.get("spawner") != null:
		battle.spawner.unregister_monster(self)
	queue_free()


func update_ai(delta: float, player: BattlePlayer, battle: Node) -> void:
	if not alive or dying or player == null:
		return
	_update_status_effects(delta)
	_apply_status_tint()
	if spawn_lock_timer > 0.0:
		spawn_lock_timer = maxf(0.0, spawn_lock_timer - delta)
		return
	if paralyze_timer > 0.0:
		# 雷麻痹/旧 freeze：完全不动
		return
	# 旧 frozen_timer 兼容路径（v5 残留；如有外部还在写 frozen_timer 也保持原行为）
	if frozen_timer > 0.0:
		frozen_timer -= delta
		return
	if hurt_reaction_timer > 0.0:
		hurt_reaction_timer = maxf(0.0, hurt_reaction_timer - delta)
	if kind_id == "MINI_CENTIPEDE":
		_update_mini_centipede(delta, player, battle)
		return
	var to_player := player.global_position - global_position
	facing = 1.0 if to_player.x >= 0 else -1.0
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.flip_h = facing < 0
	var preserve_anim := hurt_reaction_timer > 0.0 or SpriteHelper.is_playing_priority_anim(anim_sprite)
	# JUMPER/LASER/DASHER 进入非 idle 状态时定身（酝酿/起跳/激光预警/发射/蓄力/冲刺/恢复期间不走通用移动）
	var frozen := _jumper_state != 0 or _laser_state != 0 or _dasher_state != 0
	if can_move and not frozen:
		var dist := to_player.length()
		var stop_dist := _melee_stop_distance(player)
		if ranged:
			stop_dist = attack_range * 0.85 if attack_range > 0.0 else GameConfig.scale_world(140.0)
		if dist > stop_dist:
			# 冰减速 + sr=50 无下限术式：取叠加最大减速
			var eff_slow: float = clampf(slow_pct_active + proximity_slow_pct - slow_pct_active * proximity_slow_pct, 0.0, 0.95)
			var eff_speed: float = move_speed * maxf(0.0, 1.0 - eff_slow)
			var step_len: float = eff_speed * delta
			# A* 网格寻路：朝当前 waypoint 走，地块墙由路径绕开；树仍由下方微碰撞滑步兜底。
			# 注意传 scaled delta（battle._process 传 time-scaled delta，慢动作时 repath 节奏也跟着慢）。
			var steer_target := _nav_steer_target(delta, battle, player)
			var to_target: Vector2 = steer_target - global_position
			var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else to_player.normalized()
			var next_pos := global_position + dir * step_len
			var blocked: bool = _is_pos_blocked(battle, next_pos)
			if blocked:
				_nav_stuck_timer += delta
				if _nav_stuck_timer > NAV_STUCK_SEC:
					_nav_path.clear()
					_nav_repath_timer = 0.0
				# 沿障碍滑步：用持久 slide sign 决定左/右侧，避免"选离玩家更近一侧"在
				# 对称阻挡（玩家正对墙/树后方）时左右翻转 → 原地抖动。sign 在直行通畅时清 0。
				var perp_a := Vector2(-dir.y, dir.x)
				if _nav_slide_sign == 0:
					var alt_a0 := global_position + perp_a * step_len
					var alt_b0 := global_position - perp_a * step_len
					_nav_slide_sign = 1 if alt_a0.distance_to(player.global_position) <= alt_b0.distance_to(player.global_position) else -1
				var slide := perp_a if _nav_slide_sign > 0 else -perp_a
				var slide_pos := global_position + slide * step_len
				if not _is_pos_blocked(battle, slide_pos):
					global_position = slide_pos
				else:
					# 当前侧堵 → 试另一侧，并翻转 sign 持久化
					var rev_pos := global_position - slide * step_len
					if not _is_pos_blocked(battle, rev_pos):
						_nav_slide_sign = -_nav_slide_sign
						global_position = rev_pos
					else:
						# 两侧都堵：被树/地块墙/放置块夹住，沿统一 escape 推力脱困。
						# 用更大步长快速脱困，避免卡在死角龟速蹭（step_len 仅 1~2px）。
						var escape_dir := _escape_dir(battle, hitbox_radius)
						if escape_dir != Vector2.ZERO:
							global_position += escape_dir * maxf(step_len, 4.0)
			else:
				_nav_stuck_timer = 0.0
				_nav_slide_sign = 0
				global_position = next_pos
			if not preserve_anim:
				_play_anim(SpriteHelper.ANIM_WALK)
		elif not preserve_anim:
			_play_anim(SpriteHelper.ANIM_IDLE)
		# JUMPER / LASER 用独立状态机驱动攻击循环，不走通用 attack_timer 路径
	if kind_id == "JUMPER":
		_update_jumper(delta, player, battle)
		return
	if kind_id == "LASER":
		_update_laser(delta, player, battle)
		return
	if kind_id == "DASHER":
		_update_dasher(delta, player, battle)
		return
	if kind_id == "TELEPORTER":
		_update_teleporter(delta, player, battle)
		return
	var can_attack := true
	if battle and battle.combat:
		can_attack = battle.combat.should_monsters_attack(player)
	if can_attack and hurt_reaction_timer <= 0.0:
		attack_timer -= delta
		if attack_timer > 0.0:
			return
		if ranged and attack_range > 0.0 and to_player.length() > attack_range:
			return
		if not ranged and to_player.length() > _melee_attack_range(player):
			return
		attack_timer = attack_interval
		_perform_attack(player, battle)


func _perform_attack(player: BattlePlayer, battle: Node) -> void:
	if kind_id == "FIRE_MAGE":
		if battle and battle.ground_effects:
			battle.ground_effects.spawn_fire_pillar(player.global_position, attack)
		if battle and battle.particles:
			var hand := global_position + Vector2(cos(facing), sin(facing)) * (hitbox_radius + 4.0)
			battle.particles.emit_particle(hand.x, hand.y, 0, 0, 0.35, 5.0, Color("#c03030"), 0, false, false)
			battle.particles.emit_particle(hand.x, hand.y - 4.0, 0, -20, 0.35, 4.0, Color("#ff5040"), 0, false, false)
		return
	if ranged:
		_play_anim(SpriteHelper.ANIM_ATTACK)
		match attack_pattern:
			"spread":
				battle.spawn_enemy_spread(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					spread_count,
					spread_angle_deg,
					projectile_effect,
					sprite_tint
				)
			"cross":
				battle.spawn_enemy_cross(
					global_position,
					attack,
					arrow_speed,
					projectile_effect,
					sprite_tint
				)
			"bounce":
				battle.spawn_enemy_bounce(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					bounce_count,
					projectile_effect,
					sprite_tint
				)
			"snake":
				battle.spawn_enemy_snake(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					projectile_effect,
					sprite_tint
				)
			"radial":
				battle.spawn_enemy_radial(
					global_position,
					attack,
					arrow_speed,
					spread_count,
					projectile_effect,
					sprite_tint
				)
			_:
				battle.spawn_arrow(
					global_position,
					player.global_position,
					attack,
					arrow_speed,
					projectile_effect,
					sprite_tint
				)
	else:
		_play_anim(SpriteHelper.ANIM_ATTACK)
		player.take_damage(attack)
		if ki_drain_on_hit > 0:
			player.ki = maxf(0.0, player.ki - float(ki_drain_on_hit))


# ===================== JUMPER 跳跃怪 =====================
# 进入触发范围 → 酝酿2s（下沉蓄力）→ 起跳飞出屏幕 + 玩家脚下红色预警2s → 砸落。
# 砸击伤害由 ground_effect_manager.spawn_smash 在预警结束时结算（同火法师预警观感）。
func _update_jumper(delta: float, player: BattlePlayer, battle: Node) -> void:
	match _jumper_state:
		0:  # idle：接近到触发范围后开始酝酿（attack_timer 作跳跃冷却）
			if player == null:
				return
			attack_timer -= delta
			if attack_timer > 0.0:
				return
			if global_position.distance_to(player.global_position) <= JUMPER_TRIGGER_RANGE:
				_jumper_state = 1
				_jumper_timer = JUMPER_WINDUP_TIME
				_jumper_target = player.global_position
				_play_anim(SpriteHelper.ANIM_HURT, true)
		1:  # windup 酝酿：下沉蓄力 + 红色脉动 telegraph
			_jumper_timer -= delta
			var p := 1.0 - clampf(_jumper_timer / JUMPER_WINDUP_TIME, 0.0, 1.0)
			scale = Vector2.ONE * lerpf(1.0, 0.8, p)
			queue_redraw()
			if _jumper_timer <= 0.0:
				# 起跳：锁定玩家当前位置为目标，生成脚下预警，自身飞出屏幕顶部
				_jumper_target = player.global_position
				_jumper_state = 2
				_jumper_timer = JUMPER_AIR_TIME
				if battle and battle.ground_effects:
					battle.ground_effects.spawn_smash(
						_jumper_target,
						int(round(attack * JUMPER_SMASH_DAMAGE_MUL)),
						JUMPER_SMASH_RADIUS,
						JUMPER_AIR_TIME
					)
				global_position = Vector2(_jumper_target.x, -300.0)
				modulate.a = 0.0
				scale = Vector2.ONE
		2:  # airborne：等预警结束
			_jumper_timer -= delta
			if _jumper_timer <= 0.0:
				# 下落砸到目标点
				global_position = _jumper_target
				modulate.a = 1.0
				_jumper_state = 3
				_jumper_timer = JUMPER_RECOVER_TIME
				_play_anim(SpriteHelper.ANIM_ATTACK, true)
				if battle and battle.has_method("shake_camera"):
					battle.shake_camera(7.0, 0.22)
				if battle and battle.particles:
					for i in range(12):
						var ang := float(i) / 12.0 * TAU
						battle.particles.emit_particle(
							global_position.x, global_position.y,
							cos(ang) * 90.0, sin(ang) * 40.0,
							0.35, 4.0, Color("#b09878"), 90.0, true, false
						)
		3:  # recover
			_jumper_timer -= delta
			if _jumper_timer <= 0.0:
				_jumper_state = 0
				attack_timer = attack_interval


# ===================== LASER 激光怪 =====================
# 冷却结束 → 锁定方向 + 红色路径预警2s → 射出激光束0.45s（沿途伤害一次）→ 恢复。
func _update_laser(delta: float, player: BattlePlayer, battle: Node) -> void:
	match _laser_state:
		0:  # idle 冷却
			attack_timer -= delta
			if attack_timer > 0.0 or player == null:
				return
			_laser_dir = (player.global_position - global_position).normalized()
			if _laser_dir.length_squared() < 0.0001:
				_laser_dir = Vector2.RIGHT
			_laser_state = 1
			_laser_timer = LASER_WINDUP_TIME
			_laser_hit = false
			_play_anim(SpriteHelper.ANIM_ATTACK, true)
		1:  # windup 红色路径预警
			_laser_timer -= delta
			queue_redraw()
			if _laser_timer <= 0.0:
				_laser_state = 2
				_laser_timer = LASER_FIRE_TIME
				_laser_hit = false
				if battle and battle.has_method("shake_camera"):
					battle.shake_camera(3.0, 0.1)
		2:  # fire 激光束
			_laser_timer -= delta
			_apply_laser_damage(player, battle)
			queue_redraw()
			if _laser_timer <= 0.0:
				_laser_state = 3
				_laser_timer = LASER_RECOVER_TIME
		3:  # recover
			_laser_timer -= delta
			if _laser_timer <= 0.0:
				_laser_state = 0
				attack_timer = attack_interval


# ===================== DASHER 冲刺怪 =====================
# 进入触发范围 → 蓄力 windup_sec（定身+渐变变红,modulate 由 _apply_status_tint 处理）
# → 锁定方向直线冲刺 dash_distance（每轮命中玩家一次,不停不拐弯）→ 恢复 recover_sec → 回 idle 冷却。
func _update_dasher(delta: float, player: BattlePlayer, _battle: Node) -> void:
	match _dasher_state:
		0:  # idle：通用移动已在外层处理；这里只做冷却+触发范围检测
			if _dasher_cooldown_t > 0.0:
				_dasher_cooldown_t = maxf(0.0, _dasher_cooldown_t - delta)
			if player == null or _dasher_cooldown_t > 0.0:
				return
			if global_position.distance_to(player.global_position) <= _dasher_trigger_range:
				_dasher_state = 1
				_dasher_timer = _dasher_windup_sec
				_dasher_dash_dist_acc = 0.0
				_has_hit_this_dash = false
				var d := player.global_position - global_position
				_dash_dir = d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
				_play_anim(SpriteHelper.ANIM_HURT, true)
		1:  # windup 蓄力：定身变红（tint 在 _apply_status_tint）
			_dasher_timer -= delta
			if _dasher_timer <= 0.0:
				_dasher_state = 2
				_play_anim(SpriteHelper.ANIM_ATTACK01, true)
		2:  # dash 直线冲刺固定距离（受 slow/paralyze/petrify 影响,同 _step_charge）
			var slow := clampf(slow_pct_active, 0.0, 0.95)
			var spd := _dasher_dash_speed * (1.0 - slow)
			if paralyze_timer > 0.0 or petrify_timer > 0.0:
				spd = 0.0
			global_position += _dash_dir * spd * delta
			_dasher_dash_dist_acc += spd * delta
			# 撞击：每轮一次接触伤害,不停不拐弯（仿 _step_charge:1004-1008）
			if not _has_hit_this_dash and player != null and player.hp > 0.0:
				var rr := player.get_effective_radius() + GameConfig.scale_world(6.0)
				if global_position.distance_to(player.global_position) <= rr:
					player.take_damage(attack)
					_has_hit_this_dash = true
			if _dasher_dash_dist_acc >= _dasher_dash_distance:
				_dasher_state = 3
				_dasher_timer = _dasher_recover_sec
				_play_anim(SpriteHelper.ANIM_IDLE)
		3:  # recover
			_dasher_timer -= delta
			if _dasher_timer <= 0.0:
				_dasher_state = 0
				_dasher_cooldown_t = _dasher_cooldown_sec


# ===================== TELEPORTER 瞬移怪 =====================
# APPEAR(现身,teleport_in) → VISIBLE(发1发子弹+attack,停2s)
# → DISAPPEAR(teleport_out) → GONE(隐形免疫1.5s,末尾画预警圈,再选位→APPEAR)
func _update_teleporter(delta: float, player: BattlePlayer, battle: Node) -> void:
	if player == null:
		return
	_teleport_timer -= delta
	match _teleport_state:
		0:  # APPEAR
			if _teleport_timer <= 0.0:
				_teleport_state = 1
				_teleport_timer = TELEPORT_VISIBLE_SEC
				# 进入 VISIBLE 立即向玩家发射 1 发暗紫魔法弹
				facing = 1.0 if player.global_position.x >= global_position.x else -1.0
				var anim_sprite := _get_sprite()
				if anim_sprite:
					anim_sprite.flip_h = facing < 0
				_play_anim(SpriteHelper.ANIM_ATTACK, true)
				if battle and battle.has_method("spawn_arrow"):
					battle.spawn_arrow(
						global_position,
						player.global_position,
						attack,
						arrow_speed,
						projectile_effect,
						sprite_tint
					)
		1:  # VISIBLE 停留
			if _teleport_timer <= 0.0:
				_teleport_state = 2
				_teleport_timer = TELEPORT_DISAPPEAR_SEC
				_play_anim(ANIM_TELEPORT_OUT, true)
		2:  # DISAPPEAR
			if _teleport_timer <= 0.0:
				_teleport_state = 3
				_teleport_timer = TELEPORT_GONE_SEC
				modulate.a = 0.0
				_teleport_next_pos = _pick_teleport_pos(battle, player)
				_teleport_telegraphed = false
		3:  # GONE 隐形免疫；末尾在将出现点画紫色预警圈（独立 ground_effect，不受 modulate.a=0 影响）
			if not _teleport_telegraphed and _teleport_timer <= TELEPORT_TELEGRAPH_SEC:
				_teleport_telegraphed = true
				if battle and battle.ground_effects:
					battle.ground_effects.spawn_teleport_marker(_teleport_next_pos, hitbox_radius + 6.0, TELEPORT_TELEGRAPH_SEC)
			if _teleport_timer <= 0.0:
				global_position = _teleport_next_pos
				modulate.a = 1.0
				_teleport_state = 0
				_teleport_timer = TELEPORT_APPEAR_SEC
				_play_anim(ANIM_TELEPORT_IN, true)


# 屏幕边缘随机选位：4 边中随机一边，沿边内缩 EDGE_MARGIN 处取点；
# 拒绝距玩家 < MIN_PLAYER_DIST 的点；失败兜底屏幕中上部。
func _pick_teleport_pos(battle: Node, player: BattlePlayer) -> Vector2:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var m := TELEPORT_EDGE_MARGIN
	var safe := player.global_position if player != null else Vector2(w * 0.5, h * 0.5)
	for _i in range(20):
		var edge := randi() % 4
		var pos := Vector2.ZERO
		match edge:
			0: pos = Vector2(MathUtils.rand_range(m, w - m), m)
			1: pos = Vector2(MathUtils.rand_range(m, w - m), h - m)
			2: pos = Vector2(m, MathUtils.rand_range(m, h - m))
			_: pos = Vector2(w - m, MathUtils.rand_range(m, h - m))
		if MathUtils.dist(pos, safe) < TELEPORT_MIN_PLAYER_DIST:
			continue
		if battle and battle.has_method("is_move_blocked_at") and battle.is_move_blocked_at(pos, hitbox_radius):
			continue
		return pos
	return Vector2(w * 0.5, h * 0.25)


# 玩家到激光射线（自 monster 沿 _laser_dir）的垂直距离判定，命中则造伤一次。
func _apply_laser_damage(player: BattlePlayer, battle: Node) -> void:
	if _laser_hit or player == null or player.hp <= 0:
		return
	if player.state == BattlePlayer.State.BULLET_TIME or player.is_attack_invincible():
		return
	var to_p: Vector2 = player.global_position - global_position
	var proj: float = to_p.dot(_laser_dir)
	if proj < 0.0 or proj > LASER_LENGTH:
		return
	var perp: Vector2 = to_p - _laser_dir * proj
	if perp.length() > LASER_HALF_WIDTH + player.get_effective_radius():
		return
	_laser_hit = true
	var dmg: int = int(round(attack * LASER_DAMAGE_MUL))
	var dealt := player.take_damage(dmg)
	if dealt > 0 and battle and battle.combat:
		battle.combat.spawn_damage_number(
			player.global_position + Vector2(0.0, -player.get_effective_radius() - 8.0),
			dealt, false, false, Color("#ff4040")
		)
	if battle and battle.particles:
		battle.particles.hit_spark(player.global_position, false)


# 激光预警线 + 激光束绘制（local 空间，原点=怪物；_laser_dir 为世界方向，节点未旋转故 local=世界）
func _draw_laser() -> void:
	if not alive or dying:
		return
	var end := _laser_dir * LASER_LENGTH
	if _laser_state == 1:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.018)
		draw_line(Vector2.ZERO, end, Color(1.0, 0.12, 0.12, 0.35 + pulse * 0.4), maxf(1.0, GameConfig.scale_world(2.5)))
		draw_line(Vector2.ZERO, end, Color(1.0, 0.4, 0.3, 0.5 + pulse * 0.3), maxf(1.0, GameConfig.scale_world(1.0)))
	elif _laser_state == 2:
		var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.06)
		# 外发光
		draw_line(Vector2.ZERO, end, Color(1.0, 0.25, 0.2, 0.35 * flicker), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH * 1.8)))
		# 主体
		draw_line(Vector2.ZERO, end, Color(1.0, 0.35, 0.25, 0.9), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH)))
		# 核心
		draw_line(Vector2.ZERO, end, Color(1.0, 0.95, 0.85, flicker), maxf(1.0, GameConfig.scale_world(LASER_HALF_WIDTH * 0.35)))


# ===================== MINI_CENTIPEDE 迷你千足虫 =====================
# 代码绘制：12 节等大紫色方块，沿冲锋方向排成直线；头节加高光点。
func _draw_mini_centipede() -> void:
	if not alive:
		return
	var alpha: float = modulate.a if dying else 1.0
	var body_col := Color("#7a5ab0")
	var edge_col := Color("#2e1f44")
	var ang := _charge_dir.angle()
	var half := _centi_segment_size * 0.5
	for i in range(_centi_segment_count):
		var local := -_charge_dir * (float(i) * _centi_segment_spacing)
		draw_set_transform(local, ang, Vector2.ONE)
		draw_rect(Rect2(-half, -half, _centi_segment_size, _centi_segment_size), Color(edge_col, alpha))
		draw_rect(Rect2(-half + 1.5, -half + 1.5, _centi_segment_size - 3.0, _centi_segment_size - 3.0), Color(body_col, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 头节高光
	draw_circle(Vector2.ZERO, half * 0.4, Color(1.0, 1.0, 1.0, 0.55 * alpha))


# ===================== MINI_CENTIPEDE 冲锋状态机 =====================
func _update_mini_centipede(delta: float, player: BattlePlayer, _battle: Node) -> void:
	match _centi_phase:
		Phase.REPOSITION:
			_centi_repos_timer -= delta
			if _centi_repos_timer <= 0.0:
				_begin_charge_pass(player)
		Phase.CHARGING:
			_step_charge(delta, player)


func _begin_charge_pass(player: BattlePlayer) -> void:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var margin := 80.0
	var side := randi() % 4
	match side:
		0: _charge_entry = Vector2(MathUtils.rand_range(margin, w - margin), -margin)
		1: _charge_entry = Vector2(MathUtils.rand_range(margin, w - margin), h + margin)
		2: _charge_entry = Vector2(-margin, MathUtils.rand_range(margin, h - margin))
		_: _charge_entry = Vector2(w + margin, MathUtils.rand_range(margin, h - margin))
	_charge_target = player.global_position if player != null else Vector2(w * 0.5, h * 0.5)
	var d := _charge_target - _charge_entry
	_charge_dir = d.normalized() if d.length() > 0.001 else Vector2.RIGHT
	global_position = _charge_entry
	_has_hit_this_pass = false
	_centi_phase = Phase.CHARGING
	_position_segments()
	# 冲锋方向变了 → 必须重画：虫身朝向 baked 进 _draw 的局部 transform，
	# 不 queue_redraw 的话绘制会沿用上一轮旧方向，与 hitbox 排位错位。
	queue_redraw()


func _step_charge(delta: float, player: BattlePlayer) -> void:
	var slow := clampf(slow_pct_active, 0.0, 0.95)
	var spd := _centi_charge_speed * (1.0 - slow)
	if paralyze_timer > 0.0 or petrify_timer > 0.0:
		spd = 0.0
	global_position += _charge_dir * spd * delta
	_position_segments()
	# 撞击：每轮一次接触伤害，不停不拐弯
	if not _has_hit_this_pass and player != null and player.hp > 0.0:
		var rr := player.get_effective_radius() + GameConfig.scale_world(6.0)
		if global_position.distance_to(player.global_position) <= rr:
			player.take_damage(attack)
			_has_hit_this_pass = true
	# 飞出对侧屏外 → 进入下一轮
	if _exited_screen():
		_has_hit_this_pass = false
		_centi_phase = Phase.REPOSITION
		_centi_repos_timer = _centi_reposition_delay
	# 每帧重画：保持虫身朝向 / HP 条 / 状态染色与当前位置同步（同 LASER 的 windup/fire 路径）
	queue_redraw()


func _position_segments() -> void:
	for i in range(_centi_segments.size()):
		_centi_segments[i].global_position = global_position - _charge_dir * (float(i) * _centi_segment_spacing)


func _exited_screen() -> bool:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var m := 90.0
	var p := global_position
	if _charge_dir.x > 0.001 and p.x > w + m: return true
	if _charge_dir.x < -0.001 and p.x < -m: return true
	if _charge_dir.y > 0.001 and p.y > h + m: return true
	if _charge_dir.y < -0.001 and p.y < -m: return true
	return false


# MINI_CENTIPEDE：生成 N 个隐形节段命中节点并注册进 spawner.monsters
func _init_centipede_segments(spawner: Node, battle: Node) -> void:
	for seg in _centi_segments:
		if is_instance_valid(seg):
			seg.queue_free()
	_centi_segments.clear()
	var SegClass := load("res://scripts/entities/mini_centipede_segment.gd")
	for i in range(_centi_segment_count):
		var seg = SegClass.new()
		seg.worm = self
		seg.segment_index = i
		seg.alive = true
		seg.dying = false
		if battle and battle.has_method("get") and battle.get("monster_container") != null:
			battle.monster_container.add_child(seg)
		else:
			add_child(seg)
		seg.global_position = global_position
		_centi_segments.append(seg)
		if spawner and "monsters" in spawner:
			spawner.monsters.append(seg)


# 节段命中转发：复用 _resolve_take_damage（已处理 def/vuln/抗性/暴击/死亡触发）。
# 节段不是 BattleMonster，调用方（ability_manager 等）即便对节段 emit monster_killed(seg)
# 也会被 battle._on_monster_killed 忽略（非 BattleMonster 早退）；所以虫死亡时由虫自己
# emit 一次 monster_killed(self)，保证经验/灵魂球/掉落正常。后续节段命中因 dying 早退不重发。
func _apply_segment_hit(info: DamageInfo, _seg, from_pos: Vector2) -> Dictionary:
	var result := _resolve_take_damage(info, from_pos)
	if bool(result.get("started_dying", false)):
		EventBus.monster_killed.emit(self)
	return result


func _get_sprite() -> AnimatedSprite2D:
	return sprite if sprite != null else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _anim_duration(anim_name: String, fallback: float) -> float:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return fallback
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return fallback
	var frame_count := anim_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return fallback
	var speed := anim_sprite.sprite_frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return fallback
	var total := 0.0
	for i in range(frame_count):
		total += anim_sprite.sprite_frames.get_frame_duration(anim_name, i)
	return maxf(0.12, total / speed)


func _hurt_anim_duration() -> float:
	return _anim_duration(SpriteHelper.ANIM_HURT, 0.35)


func _death_anim_duration() -> float:
	return _anim_duration(SpriteHelper.ANIM_DEATH, 0.5)


func _play_hurt_anim() -> void:
	hurt_reaction_timer = maxf(hurt_reaction_timer, _hurt_anim_duration())
	_play_anim(SpriteHelper.ANIM_HURT, true)


func _play_anim(anim_name: String, force: bool = false) -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null or not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if anim_sprite.sprite_frames.get_frame_count(anim_name) <= 0:
		return
	if dying and anim_name != SpriteHelper.ANIM_DEATH:
		return
	if hurt_reaction_timer > 0.0 and anim_name in [SpriteHelper.ANIM_WALK, SpriteHelper.ANIM_IDLE, SpriteHelper.ANIM_ATTACK]:
		return
	if anim_sprite.is_playing() and anim_sprite.animation in [SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_DEATH, SpriteHelper.ANIM_ATTACK]:
		if anim_name in [SpriteHelper.ANIM_WALK, SpriteHelper.ANIM_IDLE]:
			return
	if anim_name == SpriteHelper.ANIM_HURT:
		force = true
	if not force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	if force and anim_sprite.animation == anim_name:
		anim_sprite.stop()
		anim_sprite.frame = 0
	if anim_name == SpriteHelper.ANIM_DEATH:
		force = true
	anim_sprite.play(anim_name)


func _should_show_hp_bar() -> bool:
	return alive and not dying and hp < max_hp


func _draw_theme_aura() -> void:
	# 主题关：demon 暗红黑气脉动，angel 暖白圣光脉动；3 圈低 alpha 同心圆叠出柔光质感
	if _theme == "":
		return
	if not alive or dying:
		return
	var base_r := hitbox_radius
	# 320ms 周期 → 角速度 = TAU / 0.32 ≈ 19.63 rad/s；Time.get_ticks_msec()*1e-3 是秒
	var phase := float(Time.get_ticks_msec()) * 0.001 * (TAU / 0.32)
	var pulse := 0.5 + 0.5 * sin(phase)
	var ring_color: Color = Color("#3a0a14") if _theme == "demon" else Color("#fff4b0")
	var rings := 3
	var center := Vector2(0.0, -base_r * 0.2)
	for i in range(rings):
		var rr := base_r * (1.25 + float(i) * 0.32)
		var alpha := lerpf(0.28, 0.06, float(i) / float(rings - 1)) * (0.75 + 0.25 * pulse)
		var col := ring_color
		col.a = alpha
		draw_circle(center, rr, col)


func _draw_hp_bar() -> void:
	var head_pos := to_local(get_head_top_global_position())
	PixelUiHelper.draw_compact_hp_bar(
		self,
		head_pos + Vector2(0.0, GameConfig.scale_world(HP_BAR_Y_OFFSET)),
		hp,
		max_hp,
		GameConfig.scale_world(28.0),
		GameConfig.scale_world(5.0),
		{
			"border_color": "#2a1317",
			"panel_fill": "#201016",
			"empty_a": "#34161c",
			"empty_b": "#281218",
			"fill_color": "#cc4040",
			"shine_color": "#ff9494",
			"segment_count": 8,
			"segment_gap": 1
		}
	)


func _draw() -> void:
	if _code_drawn:
		_draw_mini_centipede()
	_draw_theme_aura()
	if kind_id == "LASER" and _laser_state != 0:
		_draw_laser()
	if _should_show_hp_bar():
		_draw_hp_bar()
	if elite_kind != "":
		_draw_elite_icon()
	if burn_timer > 0.0:
		var t := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.018)
		draw_arc(Vector2.ZERO, hitbox_radius + GameConfig.scale_world(7.0), 0.0, TAU, 30, Color(1.0, 0.35, 0.2, 0.55 + 0.25 * t), GameConfig.scale_world(2.0))
	if slow_timer > 0.0:
		# 冰减速：脚下半圆 + 围绕青色环
		var ice_pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		draw_arc(Vector2.ZERO, hitbox_radius + GameConfig.scale_world(6.0), 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.45 * ice_pulse), GameConfig.scale_world(2.0))
	if poison_timer > 0.0:
		# 中毒：头顶 3 个绿色气泡上下浮动
		var ms := float(Time.get_ticks_msec())
		var top := -hitbox_radius - GameConfig.scale_world(14.0)
		for i in range(3):
			var phase := ms * 0.004 + float(i) * 0.9
			var ox := (float(i) - 1.0) * GameConfig.scale_world(5.0)
			var oy := top + sin(phase) * GameConfig.scale_world(2.0)
			var rr := GameConfig.scale_world(2.0 + 0.4 * sin(phase * 1.8))
			draw_circle(Vector2(ox, oy), rr, Color(0.55, 0.95, 0.45, 0.85))
	if paralyze_timer > 0.0:
		# 雷麻痹：头顶两道金黄短闪电（X 形）
		var ms2 := float(Time.get_ticks_msec())
		var pulse := 0.5 + 0.5 * sin(ms2 * 0.022)
		var top2 := -hitbox_radius - GameConfig.scale_world(10.0)
		var w := GameConfig.scale_world(6.0)
		var h := GameConfig.scale_world(8.0)
		var col := Color(1.0, 0.95, 0.35, 0.75 + 0.25 * pulse)
		draw_line(Vector2(-w, top2 - h), Vector2(w, top2 + h), col, GameConfig.scale_world(1.5))
		draw_line(Vector2(w, top2 - h), Vector2(-w, top2 + h), col, GameConfig.scale_world(1.5))
	if not alive or dying or path_target_hit_count <= 0:
		return
	var ring := CombatDirector.path_preview_ring_color(path_target_hit_count)
	var fill := ring
	fill.a = 0.12 + mini(path_target_hit_count, 4) * 0.04
	var r := hitbox_radius + GameConfig.scale_world(5.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ring, GameConfig.scale_world(3.0))
	draw_circle(Vector2.ZERO, r * 0.55, fill)


func _update_status_effects(delta: float) -> void:
	# 计时器衰减
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
		if slow_timer <= 0.0:
			slow_pct_active = 0.0
	if paralyze_timer > 0.0:
		paralyze_timer = maxf(0.0, paralyze_timer - delta)
	if petrify_timer > 0.0:
		petrify_timer = maxf(0.0, petrify_timer - delta)
	# burn DoT tick
	_tick_burn(delta)
	# poison DoT tick
	_tick_poison(delta)
	# 视觉刷新（modulate 由 _apply_status_tint 综合处理）
	_apply_status_tint()
	_update_phantom_alpha(delta)
	if burn_timer > 0.0 or slow_timer > 0.0 or poison_timer > 0.0 or paralyze_timer > 0.0 or petrify_timer > 0.0 or _theme != "" or elite_kind != "":
		queue_redraw()


func _tick_burn(delta: float) -> void:
	if burn_timer <= 0.0:
		burn_timer = 0.0
		burn_tick_timer = 0.0
		burn_dps = 0
		burn_elem_snapshot_pct = 0.0
		return
	burn_timer = maxf(0.0, burn_timer - delta)
	burn_tick_timer += delta
	var battle := get_tree().get_first_node_in_group("battle")
	var iv: float = maxf(0.05, burn_tick_interval)
	while burn_tick_timer >= iv and burn_timer > 0.0 and burn_dps > 0 and alive and not dying:
		burn_tick_timer -= iv
		var info := DamageInfo.make("bullet_burn_tick", "bullet", 1.0, "fire", false, true)
		info.raw_amount = burn_dps
		info.snapshot_elem_pct = burn_elem_snapshot_pct
		var result := _resolve_take_damage(info, global_position + Vector2(0.0, -8.0))
		if battle and battle.combat and int(result.get("damage", 0)) > 0:
			battle.combat.spawn_damage_number(global_position + Vector2(0.0, -8.0), int(result.get("damage", 0)), false, false, Color("#ff6a3a"))
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(self)


func _tick_poison(delta: float) -> void:
	if poison_timer <= 0.0:
		poison_timer = 0.0
		poison_tick_timer = 0.0
		poison_per_tick = 0
		poison_elem_snapshot_pct = 0.0
		return
	poison_timer = maxf(0.0, poison_timer - delta)
	poison_tick_timer += delta
	var battle := get_tree().get_first_node_in_group("battle")
	var iv: float = maxf(0.1, poison_tick_interval)
	while poison_tick_timer >= iv and poison_timer > 0.0 and poison_per_tick > 0 and alive and not dying:
		poison_tick_timer -= iv
		var info := DamageInfo.make("bullet_poison_tick", "bullet", 1.0, "poison", false, true)
		info.raw_amount = poison_per_tick
		info.snapshot_elem_pct = poison_elem_snapshot_pct
		var result := _resolve_take_damage(info, global_position + Vector2(0.0, -8.0))
		if battle and battle.combat and int(result.get("damage", 0)) > 0:
			battle.combat.spawn_damage_number(global_position + Vector2(0.0, -8.0), int(result.get("damage", 0)), false, false, Color("#88dd55"))
		if bool(result.get("started_dying", false)):
			EventBus.monster_killed.emit(self)


# 综合 modulate：石化 > 火 > 麻痹（金黄闪烁）> 毒 > 冰 > 水；仅取最高优先级一种染色
func _apply_status_tint() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return
	var base_tint: Color = sprite_tint if sprite_tint != Color.WHITE else Color.WHITE
	# DASHER 蓄力：最高优先级，按进度渐变变红 telegraph（windup 期间每帧重算）
	if _dasher_state == 1:
		var p := 1.0 - clampf(_dasher_timer / maxf(_dasher_windup_sec, 0.001), 0.0, 1.0)
		anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.3, 0.3, 1.0), p)
		return
	# sr=51 念力石化：优先级最高，覆盖所有其它 tint
	if petrify_timer > 0.0:
		anim_sprite.modulate = Color(0.55, 0.55, 0.6, 1.0)
		return
	if burn_timer > 0.0:
		anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.42, 0.36, 1.0), 0.42)
		return
	if paralyze_timer > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.022)
		anim_sprite.modulate = base_tint.lerp(Color(1.0, 0.96, 0.45, 1.0), 0.35 + 0.25 * pulse)
		return
	if poison_timer > 0.0:
		anim_sprite.modulate = base_tint.lerp(Color(0.6, 1.0, 0.55, 1.0), 0.40)
		return
	if slow_timer > 0.0:
		anim_sprite.modulate = base_tint.lerp(WATER_TINT_COLOR, WATER_TINT_BLEND)
		return
	# 都没有则恢复 baseline
	anim_sprite.modulate = base_tint


# 怪物移动位置是否被阻挡：树（is_blocked_by_tree）+ 地块/元素（is_move_blocked_at：深坑/阻挡石/锁定块/箭块）。
func _is_pos_blocked(battle: Node, pos: Vector2) -> bool:
	if battle == null:
		return false
	if battle.has_method("is_blocked_by_tree") and battle.is_blocked_by_tree(pos):
		return true
	# 用 hitbox_radius（默认 13）而非 is_move_blocked_at 的默认 20——
	# 默认 20 把怪当 40px 宽，在 1 格（40px）缺口里 stop=40 零余量，怪会被钉在缺口边缘进不去；
	# 用 hitbox 后 stop=20+13=33，留 7px 余量，怪能穿 1 格缺口。
	if battle.has_method("is_move_blocked_at") and battle.is_move_blocked_at(pos, hitbox_radius):
		return true
	return false



# A* waypoint 转向目标：repath 节奏到 / 玩家格变 / 路径空 → 重算；推到首个未抵达 waypoint；
# 共线 lookahead 平滑（往后看最多 3 个，方向夹角 < ~15° 取更远）。无路径回落直冲玩家。
func _nav_steer_target(delta: float, battle: Node, player: BattlePlayer) -> Vector2:
	if player == null:
		return global_position
	if battle == null or not battle.has_method("get_monster_navigator"):
		return player.global_position
	var nav = battle.get_monster_navigator()
	if nav == null:
		return player.global_position
	_nav_repath_timer -= delta
	var pcell: Vector2i = nav.world_to_cell(player.global_position)
	if _nav_repath_timer <= 0.0 or _nav_path.is_empty() or pcell != _nav_last_player_cell:
		_nav_path = nav.find_path_world(global_position, player.global_position)
		# path[0] 是怪自身所在格的中心；对角绕行时怪常站在格角（离中心 >reach 且在行进反方向），
		# 若从 0 开始会每次 repath 都往回追 path[0] 形成来回震荡。跳过起点格，直接朝 path[1]。
		_nav_wp_idx = 1 if _nav_path.size() > 1 else 0
		_nav_repath_timer = NAV_REPATH_SEC
		_nav_last_player_cell = pcell
	var reach_px: float = GameConfig.scale_world(NAV_WP_REACH_PX)
	while _nav_wp_idx < _nav_path.size() and global_position.distance_to(_nav_path[_nav_wp_idx]) < reach_px:
		_nav_wp_idx += 1
	if _nav_wp_idx >= _nav_path.size():
		return player.global_position
	var target: Vector2 = _nav_path[_nav_wp_idx]
	var base_dir: Vector2 = (target - global_position).normalized()
	var lim: int = mini(_nav_wp_idx + 4, _nav_path.size())
	for i in range(_nav_wp_idx + 1, lim):
		var cand: Vector2 = _nav_path[i]
		var cand_dir: Vector2 = (cand - global_position).normalized()
		if base_dir.dot(cand_dir) > 0.966:  # cos15° ≈ 0.966
			# 禁止贴墙切角：直线到该 waypoint 若贴墙则不跳过中间点
			if nav.has_method("segment_too_close_to_solid") and nav.segment_too_close_to_solid(global_position, cand):
				break
			target = cand
		else:
			break
	return target


# 隐形精英：spawn tween 结束后，4 秒内把 self.modulate.a 渐变到 PHANTOM_MIN_ALPHA。
# 走 self.modulate 通道（与 _apply_status_tint 的 anim_sprite.modulate 互不影响），
# 死亡时被 _apply_death_modulate 整体覆盖，无冲突。
func _update_phantom_alpha(delta: float) -> void:
	if elite_kind != "phantom" or dying or not alive:
		return
	if spawn_lock_timer > 0.0:
		# 等 begin_spawn 的出生 tween 自己跑完（它也在写 modulate.a），避免互相覆盖
		return
	_phantom_fade_time = minf(PHANTOM_FADE_DUR, _phantom_fade_time + delta)
	var t: float = _phantom_fade_time / PHANTOM_FADE_DUR
	modulate.a = lerpf(1.0, _phantom_target_alpha, t)


# 精英怪头顶金色五角星图标（带 pulse）；alpha 自然继承 self.modulate.a（phantom 同步透明）
func _draw_elite_icon() -> void:
	var head := to_local(get_head_top_global_position())
	var center := head + Vector2(0.0, -GameConfig.scale_world(12.0))
	var pulse := 0.70 + 0.30 * sin(Time.get_ticks_msec() * 0.006)
	var col := Color(ELITE_ICON_COLOR_HEX)
	col.a = pulse
	var px: int = int(maxf(2.0, GameConfig.scale_world(1.5)))
	var star := [
		[0, 0, 1, 0, 0],
		[0, 1, 1, 1, 0],
		[1, 1, 1, 1, 1],
		[0, 1, 0, 1, 0],
		[1, 0, 0, 0, 1],
	]
	for r in range(5):
		for c in range(5):
			if star[r][c] == 0:
				continue
			var x: float = center.x + float(c - 2) * float(px)
			var y: float = center.y + float(r - 2) * float(px)
			draw_rect(Rect2(x, y, float(px), float(px)), col)


# 自爆精英死亡时触发：玩家近距离掉血 + 屏震 + 复用 ability_manager.abyss_explosions 池播放视觉
const _EffectHelperT = preload("res://scripts/utils/effect_helper.gd")

func _trigger_bomb_aoe() -> void:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null:
		return
	var cfg: Dictionary = ELITE_CONFIG["bomb"]
	var radius: float = GameConfig.scale_world(float(cfg.aoe_r))
	var dmg_mul: float = float(cfg.aoe_dmg_mul)
	# 1) 玩家伤害（独立距离判定，不依赖 abyss 系统）
	if battle.player and is_instance_valid(battle.player):
		var player_r: float = 0.0
		if battle.player.has_method("get_effective_radius"):
			player_r = float(battle.player.get_effective_radius())
		var d: float = global_position.distance_to(battle.player.global_position)
		if d <= radius + player_r:
			var dmg: int = int(round(float(attack) * dmg_mul))
			if battle.player.has_method("take_damage"):
				battle.player.take_damage(dmg)
	# 2) 屏震
	if battle.has_method("shake_camera"):
		battle.shake_camera(6.0, 0.18)
	# 3) 视觉：复用 abyss_explosions 池（damage_applied:true 阻止 abyss 系统二次伤害）
	if battle.abilities and "abyss_explosions" in battle.abilities and "_explosion_frames" in battle.abilities:
		var frames = battle.abilities._explosion_frames
		var anim_life: float = 0.55
		if frames:
			anim_life = _EffectHelperT.one_shot_anim_duration(frames)
			if anim_life <= 0.0:
				anim_life = 0.55
		battle.abilities.abyss_explosions.append({
			"kind": "abyss_explosion",
			"pos": global_position,
			"radius": radius,
			"life": anim_life,
			"max_life": anim_life,
			"anim_t": 0.0,
			"dmg_mul": 1.0,
			"damage": 0,
			"hit": {},
			"damage_applied": true,
		})
