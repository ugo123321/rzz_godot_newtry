extends Node2D
class_name BattlePlayer

const AttrEngineT = preload("res://scripts/core/attr_engine.gd")
const TriggerDispatcherT = preload("res://scripts/core/trigger_dispatcher.gd")
const SpecialRuleDispatcherT = preload("res://scripts/core/special_rule_dispatcher.gd")

signal auto_bullet_released

enum State { IDLE, BULLET_TIME, ATTACKING }

const AUTO_BULLET_RELEASE_RATIO := 0.42
const PATH_LINE_WIDTH := 6.0
const PATH_LINE_COLOR := Color(1.0, 0.85, 0.2, 0.9)
const PATH_LINE_COLOR_ATTACK := Color(1.0, 0.85, 0.2, 0.35)
const PATH_HIT_PAD_RATIO := 0.68
const DRAW_START_FX_SCALE := 1.3
const TRIGGER_RING_VISUAL_SCALE := 0.6
const HP_BAR_Y_OFFSET := 8

var home_position: Vector2
var state := State.IDLE

var base_attack := 95.0
var attack_power_scale := 1.0
var crit_rate := 0.08
var crit_damage := 1.6
var size_scale := 1.0

var max_hp := 100
var hp := 100
var invincible_timer := 0.0
var damage_flash_timer := 0.0

var base_ki := 234.0
var ki_max := 234.0
var ki := 234.0
var ki_regen_speed := 135.0
var basic_attack_speed := 2.0
var next_turn_ki_bonus := 0.0

var combo_count := 0.0
var combo_hit_count := 0
var combo_display_peak := 0
var combo_display_weight := 0.0
var combo_display_timer := 0.0
var combo_display_fading := false
var combo_damage_bonus := 0.01

var attack_path: Array[Vector2] = []
var path_index := 0
var path_progress := 0.0
var _path_hit_inside: Dictionary = {}
# sr=24 trail_multi：平行轨迹的额外 Line2D（不含主线），按 _trail_offsets() 顺序对应
var _trail_extra_lines: Array[Line2D] = []
var _last_attack_pos := Vector2.ZERO
var _attack_hits_primmed := false
var hit_projectiles_this_attack: Dictionary = {}

var upgrade_stacks: Dictionary = {}
var turn_buff_attack_mult := 1.0
var turn_buff_combo_mult := 1.0
var ice_ready := false
var draw_session_snapshot = null
var collected_orb_buffs: Array = []
var ki_at_draw_start := 0.0

var bullet_count := 1
var attack_speed_mult := 1.0
var ki_regen_mult := 1.0
var slash_damage_mult := 1.0
var bonus_attack_mult := 1.0
var bonus_attack_speed_mult := 1.0
var bonus_crit_rate := 0.0
var bonus_crit_damage := 0.0
var bonus_damage_reduction := 0.0
var move_speed_penalty_mult := 1.0
# 水地块相关：on_water_terrain 表示当前是否站在水上；water_tint_timer 控制蓝色色调淡出
var on_water_terrain := false
var water_tint_timer := 0.0
const WATER_SLOW_MULT := 0.55                        # 走水时移速倍率
const WATER_TINT_FADE := 0.2                         # 离开水后蓝色 0.2s 内淡出
const WATER_TINT_COLOR := Color(0.65, 0.85, 1.0, 1.0)  # 复用怪物冰 tint
const WATER_TINT_BLEND := 0.45                       # 复用怪物冰 lerp 强度
var luck_roll_blue_offset := 0.0
var luck_roll_purple_offset := 0.0
var luck_roll_orange_offset := 0.0
var run_acquired_once: Dictionary = {}
# 卡牌获得顺序：apply_upgrade 时 _card_acquired_counter += 1，并把当前值写到 _card_acquired_seq[id]
# 用途：两张"普攻整把换形态"卡（元气弹 / 血飞刀）同时装备时，按 seq 大小决定哪张的视觉胜出（后获得的覆盖之前）
var _card_acquired_seq: Dictionary = {}
var _card_acquired_counter: int = 0

# === v2 分层 stat 字段 (默认 0，待 v6 emitter 迁移时填充；v==1 路径完全忽略) ===
# ATK 层：同层加和。effective_atk = base_attack × (1 + atk_pct_total) [v2 启用时]
var atk_pct_total := 0.0
# Phase 1 新增：表驱动 attr 累加字段（AttrEngine 写入；_rebuild_upgrades 末段整合到实际生效字段）
var atk_speed_pct_total := 0.0
var move_speed_pct_total := 0.0
var max_hp_pct_total := 0.0
var ki_max_pct_total := 0.0
var ki_regen_pct_total := 0.0
var dodge_pct_total := 0.0
var luck_pct_total := 0.0
var size_pct_total := 0.0
var bullet_count_bonus := 0
var elem_proc_freq_pct := 0.0
var slow_pct_bonus := 0.0
var chain_targets_bonus := 0
var elem_fire_attach_atk_mult := 0.0
var elem_ice_attach_atk_mult := 0.0
var elem_thunder_attach_atk_mult := 0.0
var elem_poison_attach_atk_mult := 0.0
var cooldown_sec_total := 0.0
var duration_sec_total := 0.0
var tick_interval_sec_total := 0.0
# === 属性打造关 forge buff 累加器 ===
# 整局持续，_rebuild_upgrades() 不重置（声明在 reset 段外，整局结束 / 死亡 / 回主菜单时 reset_run_forge_buffs 清零）。
# 每次 _rebuild_upgrades() 末段加进对应的 *_pct_total / crit_rate 累加器，与卡牌同层叠加。
var forge_atk_pct_total := 0.0
var forge_atk_speed_pct_total := 0.0
var forge_move_speed_pct_total := 0.0
var forge_max_hp_pct_total := 0.0
var forge_ki_max_pct_total := 0.0
var forge_ki_regen_pct_total := 0.0
var forge_crit_rate_total := 0.0
# 注：画线气力消耗用负值存（例如 -0.03 = -3%），consume_ki_by_distance 中以 (1 + forge_draw_cost_pct_total) 倍率消耗。
var forge_draw_cost_pct_total := 0.0
# DMG 层(按来源细分)：(1 + dmg_all_pct + dmg_[source]_pct) 同层加和
var dmg_all_pct := 0.0
var dmg_slash_pct := 0.0
var dmg_bullet_pct := 0.0
var dmg_combo_pct := 0.0
var dmg_trail_pct := 0.0
var dmg_sword_pct := 0.0
var dmg_summon_pct := 0.0
# ELEM 层(按四元素细分)：(1 + elem_all_pct + elem_[type]_pct) 仅在 info.element != "" 时启用
var elem_all_pct := 0.0
var elem_fire_pct := 0.0
var elem_ice_pct := 0.0
var elem_thunder_pct := 0.0
var elem_poison_pct := 0.0
# 元素挂载触发率(由子弹/剑/球等持续命中触发对应元素 DoT/控制)
var elem_proc_fire := 0.0
var elem_proc_ice := 0.0
var elem_proc_thunder := 0.0
var elem_proc_poison := 0.0
var chapter_acquired_once: Dictionary = {}
var force_legendary_upgrade_count := 0
var _trigger_ring_fade_t := 0.0
var death_anim: Dictionary = {}
var _auto_bullet_cycle_active := false
var _auto_bullet_released := false
var _draw_start_fx_frames: SpriteFrames
var _draw_start_fx_t := -1.0
var _draw_start_fx_duration := 0.0
var _draw_start_fx_sprite: Sprite2D


var trigger_dispatcher: Node = null

# v6 applies_<elem> 按卡牌路径分组缓存（每次 _rebuild_upgrades 末段重建）
# {"bullet": {"fire": bool, "ice": bool, "thunder": bool, "poison": bool}, "sword": {...}, ...}
var current_applies: Dictionary = {}

# Phase 3 SR 状态字段
var kill_stack_count: int = 0
var kill_stack_timer: float = 0.0
var revive_used: bool = false
var boss_target_active: bool = false

# Phase 4 v6 召唤数量（AttrEngine 写入；SummonAbilityManager 读取）
var summon_king_count: int = 0
var summon_god_count: int = 0
var summon_gorilla_count: int = 0
var summon_thunder_count: int = 0
var summon_bear_count: int = 0
var summon_snake_count: int = 0
var summon_fire_count: int = 0
# sr=44 summon_pact buffs（每次 rebuild 重置；on_rebuild 中累加）
var summon_size_pct: float = 0.0
var summon_atk_speed_pct: float = 0.0

# Phase 5 SR 状态字段
var on_hit_window_timer: float = 0.0     # sr=1 on_hit_window 受击触发限时增伤窗口
var trail_width_pct_total: float = 0.0   # sr=29 trail_width 累加
var stand_guard_timer: float = 0.0       # sr=9 stand_guard 累计静止时长
var stand_guard_active: bool = false     # sr=9 stand_guard 当前是否激活
var combo_charge_time: float = 0.0       # sr=21 combo_charge 蓄力时长
var bullet_homing_enabled: bool = false  # sr=12 bullet_homing 标记 / 装备 storm_greatsword 传奇也置 true
var bullet_mirror_mult: float = 0.0      # sr=16 bullet_mirror 回弹伤害倍率(0=关)
var iframe_cd_timer: float = 0.0         # sr=10 iframe_on_hit CD 计时
var flame_walk_timer: float = 0.0        # sr=5 trail_burn_walk tick 计时
var aura_tick_timer: float = 0.0         # sr=3 aura tick 计时

# ---- 装备（equipments.json）驱动的属性 / flag ----
# 全部走加法叠加：pct 类先求和 total_pct，再一次性 base × total_pct 作用一次。
var equip_max_ki_pct: float = 0.0        # 累加进 ki_max_pct_total
var equip_ki_regen_pct: float = 0.0      # 累加进 ki_regen_pct_total
var equip_move_speed_add: float = 0.0    # move_speed 直接加法（flat）
var equip_crit_damage_pct: float = 0.0   # 已在 _load_base_stats 里 apply（base × pct 一次），此变量仅供 rebuild 复用

# ---- 天赋卡牌（talents.json）flat 加成缓存 ----
# 全部走加法，_load_base_stats 中一次性 apply；_rebuild_upgrades 中同样重加一次（rebuild 会重置 base 值）。
var talent_attack_add: float = 0.0
var talent_max_hp_add: int = 0
var talent_max_ki_add: float = 0.0
var talent_ki_regen_add: float = 0.0
var talent_crit_rate_add: float = 0.0
var talent_crit_damage_add: float = 0.0
var talent_move_speed_add: float = 0.0
var talent_attack_interval_add: float = 0.0   # 攻速卡：累加负值 → 缩短 attack_interval（get_auto_bullet_cycle_interval 里 apply）
var talent_bullet_range_add: float = 0.0      # 射程卡：累加 px；ability_manager 通过 get_effective_auto_bullet_range() 读取
# 装备 flag（sturdy_helmet 橙 / nimble_boots 橙）
var hit_dodge_chance: float = 0.0        # 5% 概率免伤（受击时判定）
var aura_shock_enabled: bool = false     # 持续电击靠近的敌人
var aura_shock_tick_timer: float = 0.0
const AURA_SHOCK_RADIUS: float = 90.0
const AURA_SHOCK_TICK: float = 0.5
const AURA_SHOCK_ATK_MULT: float = 0.15

# Phase 6 SR 字段
var trail_multi_count: int = 0           # sr=24 trail_multi 多重轨迹（影响 path_hit_pad）
var trail_pierce_obstacles: bool = false # sr=28 trail_pierce（占位）

# Phase 7 sr=40 sword units（6 张剑单位 attr_code 13~18）
var sword_guard_count: int = 0
var sword_blood_count: int = 0
var sword_flame_count: int = 0
var sword_thunder_count: int = 0
var sword_poison_count: int = 0
var sword_frost_count: int = 0
# Phase 7 sword buffs（sr=38/41/42/43）
var sword_count_mult: float = 1.0        # sr=38 sword_double：剑数倍率
var sword_length_pct: float = 0.0        # sr=41 sword_length：剑半径加成
var sword_speed_pct: float = 0.0         # sr=42 sword_speed：旋转角速度加成
var sword_dmg_pct: float = 0.0           # sr=43 sword_dmg：剑伤加成

# Phase 7 orb buffs（sr=33/34/36 等静态字段）
var orb_field_pct: float = 0.0           # sr=33 orb_field：场上球数量百分比
var orb_pickup_radius_pct: float = 0.0   # sr=34 orb_magnet：拾取半径百分比
var orb_line_magnet_pct: float = 0.0     # sr=34 orb_magnet：划线磁吸百分比
var orb_glow_dmg_pct: float = 0.0        # sr=36 orb_glow：拾取后下一斩击增伤
var orb_glow_pending_active: bool = false  # 下一斩击是否启用 orb_glow buff
var orb_mark_dup_chance: float = 0.0     # sr=32 orb_mark：拾取后复制概率
var orb_tide_interval_sec: float = 0.0   # sr=31 orb_tide：周期生成间隔（>0 启用）

# 主题关字段（恶魔 / 天使）
var summon_demon_baby_count: int = 0     # attr 43 恶魔宝宝（远程激光）
var summon_angel_baby_count: int = 0     # attr 44 天使宝宝（远程单体雷）
var sword_spear_count: int = 0           # attr 45 命运之矛
# sr=48 multi_revive（九命猫）
var multi_revive_extra: int = 0          # 剩余复活次数（初始 = sv[0]）
var multi_revive_post_hp: int = 1        # 复活后绝对 HP 值（sv[1]）
var multi_revive_used: bool = false      # 本局是否已用过至少一次（避免 rebuild 时重置剩余次数）
# sr=47 periodic_laser（硫磺火）
var sulfur_laser_cd: float = 4.0         # 冷却（attr 40）— 距下次释放的周期
var sulfur_laser_duration: float = 1.0   # 单条激光持续秒数（attr 41）
var sulfur_laser_atk_mult: float = 0.5   # 每 tick ATK 倍率
var sulfur_laser_tick: float = 0.1       # 内部 tick 间隔
var sulfur_laser_timer: float = 0.0      # 距下次释放秒数（≤0 → 触发并重置为 cd）
# sr=49 blood_bullet（血飞刀）
var blood_blade_pierce: bool = false
var blood_blade_range_mult: float = 1.0
# sr=6 sv_holy_guard（圣盾）— dispatcher.on_stage_start 时每关补满
var holy_shield_charges: int = 0
# sr=0 angel_light_ward（光之守护）— 装备后开启环绕小盾视觉
var angel_light_ward_active: bool = false
# sr=0 demon_vampire（吸血鬼）— 装备数量驱动环绕小蝙蝠视觉
var demon_vampire_count: int = 0
# sr=46 scythe_on_slash_end（死神镰刀）
var scythe_atk_mult: float = 0.0         # 0 = 关
var scythe_pierce: bool = false
var slash_end_ki_drained: bool = false    # 仅当本次画线把气力耗尽时为 true；on_slash_end 读取并清零（避免短画线反复触发"画线末释放"类奖励）
# sr=50 proximity_slow（无下限术式）
var proximity_slow_radius: float = 0.0   # 0 = 关

# sr=51 psychic_petrify_all（念力）— on_slash_end 时全场石化。仅一个数值持续时长，由 sv+level 决定
var psychic_petrify_duration: float = 0.0   # 0 = 未装备

# sr=52 periodic_iframe（独角兽）— 定时无敌 + 彩虹色 modulate 视觉
var unicorn_cd: float = 0.0                # 触发间隔（attr 40）
var unicorn_duration: float = 0.0          # 每次持续（attr 41）
var unicorn_timer: float = 0.0             # 距离下一次触发秒数
var unicorn_rainbow_active: bool = false   # invincible 期间为 true，_apply_combat_modulate 走 HSV

# sr=53 laser_cannon_basic（普攻改激光炮）
var laser_cannon_active: bool = false
var laser_cannon_atk_mult: float = 3.0
var laser_cannon_pierce: bool = true
var laser_cannon_color_key: String = "white"

# sr=54 melee_basic（普攻改近战）
var melee_basic_active: bool = false
var melee_basic_atk_bonus: float = 0.5
var melee_range_px: float = 60.0

# sr=55 bomb_on_slash_end（炸弹人）
var bomber_atk_mult: float = 0.0           # 0 = 未装备
var bomber_fuse_sec: float = 2.0
var bomber_cross_arm_px: float = 180.0

# sr=56 orbit_shield（环绕盾）— 数量走 attr 46 shield_orbit_count_add
var shield_orbit_count: int = 0
var shield_orbit_radius: float = 280.0
var shield_orbit_speed: float = 1.5
var shield_orbit_angle: float = 0.0        # 当前旋转角度，_process 累加

# 打造关结算后头顶 ↑ 箭头：表示"属性提升"。
# show_forge_buff_arrow(duration) 启动；duration 秒后自动淡出消失。
var _forge_arrow_timer := 0.0
var _forge_arrow_duration := 0.0
var _forge_arrow_t := 0.0
# 传送门进出动画期间标记 — true 时 _apply_combat_modulate 不再覆盖 modulate，
# 让 portal_traverse_animator 的 scale/rot/alpha tween 能正常生效。
var _portal_traverse_active := false
var proximity_slow_max: float = 0.0      # 最大减速% (0~1)
var _last_position := Vector2.ZERO
var _joystick_locomotion_active := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var trigger_area: Area2D = $TriggerArea
@onready var path_line: Line2D = $PathLine


func _ready() -> void:
	_load_base_stats()
	_draw_start_fx_frames = EffectHelper.build_effect_frames("air_slash")
	if _draw_start_fx_frames != null:
		_draw_start_fx_duration = EffectHelper.one_shot_anim_duration(_draw_start_fx_frames)
	home_position = global_position
	_last_position = global_position
	_setup_sprite()
	_update_trigger_radius()
	path_line.width = GameConfig.scale_world(PATH_LINE_WIDTH)
	path_line.default_color = PATH_LINE_COLOR
	path_line.top_level = true
	trigger_dispatcher = TriggerDispatcherT.new()
	trigger_dispatcher.name = "TriggerDispatcher"
	add_child(trigger_dispatcher)
	trigger_dispatcher.setup(self)
	# Phase 3 dispatcher hooks（不是节点，直接订阅 EventBus）
	if not EventBus.monster_killed.is_connected(_on_sr_monster_killed):
		EventBus.monster_killed.connect(_on_sr_monster_killed)
	if not EventBus.stage_started.is_connected(_on_sr_stage_started):
		EventBus.stage_started.connect(_on_sr_stage_started)


func _on_sr_monster_killed(monster: Node) -> void:
	SpecialRuleDispatcherT.on_kill(self, monster)


func _on_sr_stage_started(_stage_idx: int) -> void:
	SpecialRuleDispatcherT.on_stage_start(self)
	# 新关开始时，boss_target 可能改变了 → rebuild 让 boss 检测生效
	_rebuild_upgrades()


func _load_base_stats() -> void:
	base_attack = float(GameConfig.get_player_value("base_attack", 95))
	max_hp = int(GameConfig.get_player_value("base_hp", 100))
	hp = max_hp
	base_ki = float(GameConfig.get_player_value("base_ki", 234))
	ki_max = base_ki
	ki = ki_max
	crit_rate = float(GameConfig.get_player_value("base_crit_rate", 0.08))
	crit_damage = float(GameConfig.get_player_value("base_crit_damage", 1.6))
	combo_damage_bonus = float(GameConfig.get_player_value("combo_damage_bonus", 0.01))
	basic_attack_speed = maxf(0.01, float(GameConfig.get_player_value("basic_attack_speed", 2.0)))
	ki_regen_speed = maxf(0.0, float(GameConfig.get_player_value("ki_regen_speed", 135.0)))
	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += int(equip.get("max_hp", 0))
		crit_rate += float(equip.get("crit_rate", 0.0))
		# 加法叠加：crit_damage 的 +% 只在 base × total_pct 上作用一次，不复利。
		var eq_crit_dmg_pct := float(equip.get("crit_damage", 0.0))
		if eq_crit_dmg_pct != 0.0:
			crit_damage += crit_damage * eq_crit_dmg_pct
		# 缓存 pct / flat 供 _rebuild_upgrades 复用（rebuild 会重置 base 值，需重新 apply）
		equip_max_ki_pct = float(equip.get("max_ki_pct", 0.0))
		equip_ki_regen_pct = float(equip.get("ki_regen_pct", 0.0))
		equip_move_speed_add = float(equip.get("move_speed", 0.0))
		equip_crit_damage_pct = eq_crit_dmg_pct
		# 天赋卡：读取当前 owned 卡的 flat 加成并 apply（下一次 rebuild 也会再 apply 一次）
		var talent := LobbyState.get_talent_modifiers()
		talent_attack_add = float(talent.get("attack", 0.0))
		talent_max_hp_add = int(talent.get("max_hp", 0))
		talent_max_ki_add = float(talent.get("max_ki", 0.0))
		talent_ki_regen_add = float(talent.get("ki_regen", 0.0))
		talent_crit_rate_add = float(talent.get("crit_rate", 0.0))
		talent_crit_damage_add = float(talent.get("crit_damage", 0.0))
		talent_move_speed_add = float(talent.get("move_speed", 0.0))
		talent_attack_interval_add = float(talent.get("attack_interval", 0.0))
		talent_bullet_range_add = float(talent.get("bullet_range", 0.0))
		base_attack += talent_attack_add
		max_hp += talent_max_hp_add
		base_ki += talent_max_ki_add
		ki_regen_speed += talent_ki_regen_add
		crit_rate += talent_crit_rate_add
		crit_damage += talent_crit_damage_add
		hp = max_hp
		ki_max = base_ki
		ki = ki_max
	size_scale = 1.0
	bullet_count = 1


func _apply_sprite_scale() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		return
	SpriteHelper.apply_pixel_art(anim_sprite)
	var scale_val := float(GameConfig.get_player_value("sprite_scale", 1.0))
	var final_scale := SpriteHelper.pixel_scale(scale_val, size_scale)
	anim_sprite.scale = Vector2.ONE * final_scale


func _get_sprite() -> AnimatedSprite2D:
	if sprite != null:
		return sprite
	return get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func get_sprite_node() -> AnimatedSprite2D:
	return _get_sprite()


func _setup_sprite() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		push_warning("BattlePlayer: AnimatedSprite2D not ready")
		return
	var folder := str(GameConfig.get_player_value("character_folder", "Swordsman"))
	var prefix := str(GameConfig.get_player_value("sprite_prefix", "Swordsman"))
	anim_sprite.sprite_frames = SpriteHelper.build_character_frames(folder, prefix)
	SpriteHelper.apply_pixel_art(anim_sprite)
	SpriteHelper.sync_attack01_speed(
		anim_sprite.sprite_frames,
		get_auto_bullet_cycle_interval()
	)
	if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	if not anim_sprite.animation_finished.is_connected(_on_animation_finished):
		anim_sprite.animation_finished.connect(_on_animation_finished)
	if not anim_sprite.frame_changed.is_connected(_on_sprite_frame_changed):
		anim_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_apply_sprite_scale()


func apply_config() -> void:
	_load_base_stats()
	_setup_sprite()
	_update_trigger_radius()
	queue_redraw()


func _update_trigger_radius() -> void:
	var ref_w := float(GameConfig.get_tuning("logical_width", 720))
	var min_r := GameConfig.scale_world(float(GameConfig.get_player_value("trigger_radius_min", 30)))
	var ratio := float(GameConfig.get_player_value("trigger_radius_ratio", 0.06))
	var radius := maxf(min_r, ratio * ref_w) * size_scale
	if trigger_area.get_child_count() > 0:
		var shape := trigger_area.get_child(0) as CollisionShape2D
		if shape and shape.shape is CircleShape2D:
			(shape.shape as CircleShape2D).radius = radius


func get_effective_radius() -> float:
	return GameConfig.scale_world(float(GameConfig.get_player_value("hitbox_radius", 12))) * size_scale


func get_path_hit_pad() -> float:
	# sr=24 trail_multi 现已改为真正的平行多线打击（见 _record_path_crossings），此处不再加胖度
	return get_effective_radius() * PATH_HIT_PAD_RATIO


func get_trigger_radius() -> float:
	var ref_w := float(GameConfig.get_tuning("logical_width", 720))
	var min_r := GameConfig.scale_world(float(GameConfig.get_player_value("trigger_radius_min", 30)))
	var ratio := float(GameConfig.get_player_value("trigger_radius_ratio", 0.06))
	return maxf(min_r, ratio * ref_w) * size_scale


func _get_trigger_ring_fade_duration() -> float:
	return maxf(0.001, float(GameConfig.get_player_value("trigger_ring_fade_in", 0.35)))


func _get_trigger_ring_alpha() -> float:
	var t := clampf(_trigger_ring_fade_t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _update_trigger_ring_fade(delta: float) -> void:
	var should_show := state == State.IDLE and is_ki_full()
	if should_show:
		if _trigger_ring_fade_t >= 1.0:
			return
		_trigger_ring_fade_t = minf(1.0, _trigger_ring_fade_t + delta / _get_trigger_ring_fade_duration())
		queue_redraw()
	elif _trigger_ring_fade_t > 0.0:
		_trigger_ring_fade_t = 0.0
		queue_redraw()


func is_ki_full() -> bool:
	return ki >= ki_max - 0.01


func is_in_attack_mode() -> bool:
	return state == State.ATTACKING


func is_attack_invincible() -> bool:
	return state == State.ATTACKING


func get_auto_bullet_cycle_interval() -> float:
	var interval := 1.0 / maxf(0.01, basic_attack_speed * attack_speed_mult * bonus_attack_speed_mult * move_speed_penalty_mult)
	# 攻速卡：talent_attack_interval_add 为负值 → 缩短 interval；clamp 最小 0.05s 避免刷屏
	return maxf(0.05, interval + talent_attack_interval_add)


# 射程卡：base auto_bullet_range + talent bullet_range 加成（ability_manager 消费）
func get_effective_auto_bullet_range() -> float:
	var base_range := float(GameConfig.get_player_value("auto_bullet_range", 378))
	return base_range + talent_bullet_range_add


func sync_auto_bullet_anim_speed() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	SpriteHelper.sync_attack01_speed(anim_sprite.sprite_frames, get_auto_bullet_cycle_interval())


func begin_auto_bullet_cycle() -> bool:
	if state != State.IDLE:
		return false
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return false
	if not anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK01):
		return false
	sync_auto_bullet_anim_speed()
	_auto_bullet_cycle_active = true
	_auto_bullet_released = false
	_play_anim(SpriteHelper.ANIM_ATTACK01, true)
	if _get_auto_bullet_release_frame() <= 0:
		_auto_bullet_released = true
		auto_bullet_released.emit()
	return true


func _get_auto_bullet_release_frame() -> int:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return 0
	if not anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK01):
		return 0
	var count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_ATTACK01)
	return clampi(int(floor(float(count) * AUTO_BULLET_RELEASE_RATIO)), 0, maxi(0, count - 1))


func _on_sprite_frame_changed() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite != null and is_fail_death_pose() and not bool(death_anim.get("frozen", false)):
		_update_fail_death_last_frame_speed(anim_sprite)
	if not _auto_bullet_cycle_active or _auto_bullet_released:
		return
	if anim_sprite == null or anim_sprite.animation != SpriteHelper.ANIM_ATTACK01:
		return
	if anim_sprite.frame >= _get_auto_bullet_release_frame():
		_auto_bullet_released = true
		auto_bullet_released.emit()


func begin_stage() -> void:
	state = State.IDLE
	damage_flash_timer = 0.0
	_reset_sprite_pose()
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	combo_count = 0.0
	combo_hit_count = 0
	combo_display_peak = 0
	combo_display_weight = 0.0
	combo_display_fading = false
	_auto_bullet_cycle_active = false
	_auto_bullet_released = false
	turn_buff_attack_mult = 1.0
	turn_buff_combo_mult = 1.0
	ice_ready = false
	draw_session_snapshot = null
	collected_orb_buffs.clear()
	ki_max = round(base_ki * (1.0 + next_turn_ki_bonus))
	ki = ki_max
	next_turn_ki_bonus = 0.0
	_trigger_ring_fade_t = 0.0
	queue_redraw()
	_update_path_line()


func start_bullet_time() -> void:
	state = State.BULLET_TIME
	clear_drawing_combo_preview()
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	hit_projectiles_this_attack.clear()
	_play_draw_start_fx()
	_play_anim(SpriteHelper.ANIM_CHARGE)
	add_path_point(home_position)


func _play_draw_start_fx() -> void:
	if _draw_start_fx_frames == null or _draw_start_fx_duration <= 0.0:
		return
	var fx_sprite := _ensure_draw_start_fx_sprite()
	_draw_start_fx_t = 0.0
	fx_sprite.visible = true
	_update_draw_start_fx_sprite()


func _ensure_draw_start_fx_sprite() -> Sprite2D:
	if _draw_start_fx_sprite == null:
		_draw_start_fx_sprite = Sprite2D.new()
		_draw_start_fx_sprite.centered = true
		_draw_start_fx_sprite.z_index = 2
		SpriteHelper.apply_pixel_art(_draw_start_fx_sprite)
		add_child(_draw_start_fx_sprite)
	return _draw_start_fx_sprite


func _update_draw_start_fx(delta: float) -> void:
	if _draw_start_fx_t < 0.0:
		return
	_draw_start_fx_t += delta
	if _draw_start_fx_t >= _draw_start_fx_duration:
		_draw_start_fx_t = -1.0
		if _draw_start_fx_sprite:
			_draw_start_fx_sprite.visible = false
		return
	_update_draw_start_fx_sprite()


func _update_draw_start_fx_sprite() -> void:
	if _draw_start_fx_t < 0.0 or _draw_start_fx_frames == null:
		return
	var fx_sprite := _ensure_draw_start_fx_sprite()
	var tex := EffectHelper.animation_frame_texture_once(_draw_start_fx_frames, _draw_start_fx_t)
	if tex == null:
		fx_sprite.visible = false
		return
	var life_t := clampf(_draw_start_fx_t / maxf(0.001, _draw_start_fx_duration), 0.0, 1.0)
	fx_sprite.texture = tex
	fx_sprite.scale = Vector2.ONE * DRAW_START_FX_SCALE
	fx_sprite.modulate = Color(1.0, 0.98, 0.82, 1.0 - life_t * 0.25)
	fx_sprite.visible = true


func add_path_point(point: Vector2) -> void:
	if attack_path.is_empty() or attack_path.back().distance_to(point) >= 2.0:
		attack_path.append(point)
		_update_path_line()


func consume_ki_by_distance(distance: float) -> bool:
	var cost := distance * float(GameConfig.get_player_value("ki_per_pixel", 0.18))
	# 属性打造关「画线气力消耗 -X%」：负值减少消耗，正值增加，钳到 5% 下限避免 0 消耗。
	cost *= maxf(0.05, 1.0 + forge_draw_cost_pct_total)
	if ki < cost:
		return false
	ki -= cost
	return true


func invalidate_path() -> void:
	state = State.IDLE
	attack_path.clear()
	path_index = 0
	path_progress = 0.0
	clear_drawing_combo_preview()
	_update_path_line()


func start_attack() -> void:
	if attack_path.size() < 2:
		invalidate_path()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.buff_orbs:
		battle.buff_orbs.commit_draw_session()
	state = State.ATTACKING
	combo_count = 0.0
	combo_hit_count = 0
	if battle and battle.combat:
		battle.combat.begin_round_attack()
	if battle and battle.abilities:
		battle.abilities.on_resolve_started()
		battle.abilities.try_abyss_explosion(self, attack_path)
	path_index = 0
	path_progress = 0.0
	_path_hit_inside.clear()
	_attack_hits_primmed = false
	_last_attack_pos = attack_path[0]
	hit_projectiles_this_attack.clear()
	_apply_path_line_color()
	_play_anim(SpriteHelper.ANIM_ATTACK)


func update_attack(delta: float, combat: CombatDirector, monsters: Array) -> bool:
	if state != State.ATTACKING or attack_path.size() < 2:
		return false
	if not _attack_hits_primmed:
		_prime_path_start_hits(combat, monsters)
		_attack_hits_primmed = true
	var speed := float(GameConfig.get_player_value("attack_speed", 2300))
	path_progress += speed * delta
	while path_index < attack_path.size() - 1:
		var from := attack_path[path_index]
		var to := attack_path[path_index + 1]
		var seg_len := from.distance_to(to)
		if seg_len < 0.001:
			path_index += 1
			continue
		if path_progress >= seg_len:
			_record_path_crossings(_last_attack_pos, to, combat, monsters, path_index)
			_last_attack_pos = to
			path_progress -= seg_len
			path_index += 1
			continue
		var t := path_progress / seg_len
		var pos := from.lerp(to, t)
		global_position = pos
		_record_path_crossings(_last_attack_pos, pos, combat, monsters, path_index)
		_last_attack_pos = pos
		return false
	_finish_attack(combat)
	return true


func _prime_path_start_hits(combat: CombatDirector, monsters: Array) -> void:
	var hit_pad := get_path_hit_pad()
	var start := attack_path[0]
	# 起点法线：用 path 第一段方向
	var first_dir: Vector2 = Vector2.RIGHT
	if attack_path.size() >= 2:
		first_dir = (attack_path[1] - attack_path[0]).normalized()
	var normal: Vector2 = Vector2(-first_dir.y, first_dir.x)
	var distances: Array = [0.0]
	distances.append_array(_trail_offset_distances())
	var line_count: int = distances.size()
	for monster in monsters:
		if not is_instance_valid(monster) or not monster.is_combat_targetable():
			continue
		var hit_r: float = monster.get_hitbox_radius() + hit_pad
		var id: int = monster.get_instance_id()
		var inside_arr: Array = []
		var queued: bool = false
		for li in range(line_count):
			var sp: Vector2 = start + normal * float(distances[li])
			var ins: bool = sp.distance_to(monster.global_position) <= hit_r
			inside_arr.append(ins)
			if ins and not queued:
				combat.queue_hit(monster, 0, monster.global_position)
				queued = true
		_path_hit_inside[id] = inside_arr


func _record_path_crossings(
	prev: Vector2,
	curr: Vector2,
	combat: CombatDirector,
	monsters: Array,
	segment_index: int,
) -> void:
	if prev.distance_squared_to(curr) < 0.0001:
		return
	var hit_pad := get_path_hit_pad()
	# sr=24 trail_multi：1 条主线 + N 条平行线，每条独立扫描 / 独立 inside 状态
	var distances: Array = [0.0]
	distances.append_array(_trail_offset_distances())
	var seg_dir: Vector2 = (curr - prev).normalized()
	var normal: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
	var line_count: int = distances.size()
	for monster in monsters:
		if not is_instance_valid(monster) or not monster.is_combat_targetable():
			continue
		var hit_r: float = monster.get_hitbox_radius() + hit_pad
		var center: Vector2 = monster.global_position
		var id: int = monster.get_instance_id()
		var inside_arr: Array = _path_hit_inside.get(id, [])
		if inside_arr.size() != line_count:
			# 首次或线数变化：按当前距离初始化
			inside_arr = []
			for li in range(line_count):
				var p0: Vector2 = prev + normal * float(distances[li])
				inside_arr.append(p0.distance_to(center) <= hit_r)
		for li in range(line_count):
			var off: float = float(distances[li])
			var a: Vector2 = prev + normal * off
			var b: Vector2 = curr + normal * off
			var inside: bool = bool(inside_arr[li])
			for ev in MathUtils.segment_circle_crossings(a, b, center, hit_r):
				if bool(ev.get("enter", false)):
					if not inside:
						combat.queue_hit(monster, segment_index, center)
					inside = true
				else:
					inside = false
			inside_arr[li] = inside
		_path_hit_inside[id] = inside_arr
	var battle := get_tree().get_first_node_in_group("battle") as BattleController
	if battle:
		battle.block_projectiles_on_path_segment(prev, curr, segment_index, self, distances)


func _finish_attack(combat: CombatDirector) -> void:
	home_position = global_position
	state = State.IDLE
	_reset_sprite_pose()
	_play_anim(SpriteHelper.ANIM_IDLE)
	combat.consume_round_attack()
	combat.begin_resolve(self)
	# Phase 5 sr=22 combo_shuriken：斩击末段 spawn 辅助子弹
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.abilities:
		var slash_end_pos: Vector2 = global_position
		var slash_end_ang: float = 0.0
		if attack_path.size() >= 2:
			var p_last: Vector2 = attack_path[attack_path.size() - 1]
			var p_prev: Vector2 = attack_path[attack_path.size() - 2]
			slash_end_pos = p_last
			var d: Vector2 = (p_last - p_prev)
			slash_end_ang = d.angle() if d.length() > 0.01 else 0.0
		SpecialRuleDispatcherT.on_slash_end(self, battle.abilities, slash_end_pos, slash_end_ang)
		# Phase 6 sr=26 trail_slash_wave：末段 spawn 推开 AOE
		SpecialRuleDispatcherT.on_slash_wave(self, battle.abilities, global_position)
		# Phase 6 sr=25 trail_elem_field：沿 path 生成元素场域
		SpecialRuleDispatcherT.on_trail_field_spawn(self, battle.abilities, attack_path)
	# 清零气力耗尽标记：sr=22/26/27/46 都已读完，下次画线重新累计
	slash_end_ki_drained = false
	attack_path.clear()
	_update_path_line()


func end_combo_turn() -> void:
	if combo_display_peak >= 2:
		combo_display_fading = true
		combo_display_timer = 0.4
	else:
		clear_drawing_combo_preview()
	combo_count = 0.0
	combo_hit_count = 0


func get_combo_bonus_percent(_combo: int = -1) -> int:
	var weighted := combo_display_weight if combo_display_weight > 0.0 else combo_count
	if weighted <= 1.0:
		return 0
	return int(round((weighted - 1.0) * combo_damage_bonus * 100.0))


func _combo_hit_increment() -> float:
	return turn_buff_combo_mult


func clear_drawing_combo_preview() -> void:
	combo_display_peak = 0
	combo_display_weight = 0.0
	combo_display_fading = false
	combo_display_timer = 0.0
	combo_count = 0.0
	combo_hit_count = 0


func is_combo_display_visible() -> bool:
	if combo_display_peak < 2:
		return false
	if combo_display_fading:
		return combo_display_timer > 0.0
	return true


func update_combo_preview(total_hits: int) -> void:
	if state != State.BULLET_TIME:
		return
	if total_hits < 2:
		if combo_display_peak >= 2:
			clear_drawing_combo_preview()
		return
	if total_hits == combo_display_peak:
		return
	var weighted := float(total_hits) * _combo_hit_increment()
	combo_display_peak = total_hits
	combo_display_weight = weighted
	combo_display_fading = false
	combo_display_timer = 1.0


func update_combo_display(delta: float) -> void:
	if combo_display_fading and combo_display_timer > 0.0:
		combo_display_timer = maxf(0.0, combo_display_timer - delta)


func get_ability_damage(mult: float) -> int:
	# Sheet3 L1+L2 折叠进 raw：base × (1 + atk_pct_total) × scale × bonus_atk × weapon_mult
	return int(max(1, round(base_attack * (1.0 + atk_pct_total) * attack_power_scale * bonus_attack_mult * mult)))


func get_auto_bullet_damage() -> int:
	return make_auto_bullet_damage().raw_amount


func register_combo_hit() -> float:
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or not battle.combat.is_resolving():
		return combo_count
	combo_hit_count += 1
	var inc := _combo_hit_increment()
	# Phase 3 sr=19 combo_count_mult：连击数倍率
	inc = SpecialRuleDispatcherT.transform_combo_inc(self, inc)
	combo_count += inc
	EventBus.combo_changed.emit(combo_hit_count)
	return combo_count


func get_effective_crit_rate() -> float:
	return minf(0.95, crit_rate + bonus_crit_rate)


func roll_crit_damage(raw: float) -> Dictionary:
	var is_crit := randf() < get_effective_crit_rate()
	var final := raw
	if is_crit:
		final *= crit_damage + bonus_crit_damage
	return {"amount": int(max(1, round(final))), "is_crit": is_crit}


func get_attack_damage(combo: float) -> Dictionary:
	var info := make_slash_damage(combo)
	return {"amount": info.raw_amount, "is_crit": info.is_crit_resolved}


# === DamageInfo 工厂 ===
# 通用工厂：构造 DamageInfo 并写入当前玩家面板快照。
# Sheet3 L1+L2 已折叠到 raw_amount（emitter 端 base × (1+atk_pct_total) × weapon_mult）；
# L3-L8 由 DamageResolver 基于此处快照独立计算。
func make_damage(source: String, weapon_mult: float, category: String, element: String = "", can_crit: bool = true, is_dot: bool = false) -> DamageInfo:
	var info := DamageInfo.make(source, category, weapon_mult, element, can_crit, is_dot)
	# L1 ATK 已折叠到 emitter 端 raw_amount（见 get_ability_damage）；此字段仅给 ElementEffectManager 用作 DoT 基底
	info.snapshot_atk_with_pct = base_attack * (1.0 + atk_pct_total) * attack_power_scale * bonus_attack_mult * turn_buff_attack_mult
	info.snapshot_crit_rate = get_effective_crit_rate()
	info.snapshot_crit_dmg = crit_damage + bonus_crit_damage
	# L3 DMG 同层加和
	var dmg_src_pct := 0.0
	match category:
		"slash":  dmg_src_pct = dmg_slash_pct
		"bullet": dmg_src_pct = dmg_bullet_pct
		"combo":  dmg_src_pct = dmg_combo_pct
		"trail":  dmg_src_pct = dmg_trail_pct
		"sword":  dmg_src_pct = dmg_sword_pct
		"summon": dmg_src_pct = dmg_summon_pct
		_: dmg_src_pct = 0.0
	info.snapshot_dmg_all_pct = dmg_all_pct
	info.snapshot_dmg_source_pct = dmg_src_pct
	# L4 COMBO 默认 1.0；make_slash_damage 内单独覆盖
	info.snapshot_combo_mult = 1.0
	# L8 ELEM 同层加和
	var elem_pct := 0.0
	match element:
		"fire":    elem_pct = elem_fire_pct
		"ice":     elem_pct = elem_ice_pct
		"thunder": elem_pct = elem_thunder_pct
		"poison":  elem_pct = elem_poison_pct
		_: elem_pct = 0.0
	info.snapshot_elem_pct = (elem_all_pct + elem_pct) if element != "" else 0.0
	# Sheet4 元素状态注入：按 category 查 current_applies；非伤害卡 path 没有 applies
	var applies: Dictionary = current_applies.get(category, {})
	info.applies_fire = bool(applies.get("fire", false))
	info.applies_ice = bool(applies.get("ice", false))
	info.applies_thunder = bool(applies.get("thunder", false))
	info.applies_poison = bool(applies.get("poison", false))
	info.snapshot_elem_proc_freq_pct = elem_proc_freq_pct
	info.snapshot_slow_pct_bonus = slow_pct_bonus
	info.snapshot_chain_targets_bonus = chain_targets_bonus
	return info


# 斩击主路径：raw = base × (1+atk_pct) × scale × bonus_atk × slash_dmg_mult；combo 进 snapshot_combo_mult
func make_slash_damage(combo: float) -> DamageInfo:
	var info := make_damage("slash_main", 1.0, "slash", "", true, false)
	var raw := base_attack * (1.0 + atk_pct_total) * attack_power_scale * turn_buff_attack_mult * slash_damage_mult * bonus_attack_mult
	# Phase 7 sr=36 orb_glow：拾取后下一斩击吃 buff
	if orb_glow_pending_active and orb_glow_dmg_pct > 0.0:
		raw *= 1.0 + orb_glow_dmg_pct
		orb_glow_pending_active = false
	info.raw_amount = int(max(1, round(raw)))
	# COMBO 层走 snapshot；resolver 计算 (1 + combo_damage_bonus × combo)
	info.snapshot_combo_mult = 1.0 + combo_damage_bonus * float(combo)
	# Phase 3 sr=23 combo_crit：连击里程碑必暴；预 set is_crit_resolved 让 resolver 跳 roll
	if SpecialRuleDispatcherT.force_crit_on_combo(self, int(combo)):
		info.is_crit_resolved = true
	else:
		info.is_crit_resolved = false
	return info


# 自动子弹路径：raw = base × (1+atk_pct) × scale × bonus_atk × auto_bullet_mult；不参与 combo
func make_auto_bullet_damage() -> DamageInfo:
	var info := make_damage("bullet_auto", 0.5, "bullet", "", true, false)
	var mult := float(GameConfig.get_player_value("auto_bullet_damage_mult", 0.2))
	var dmg := float(get_ability_damage(1)) * turn_buff_attack_mult * mult
	info.raw_amount = int(max(1, round(dmg)))
	info.is_crit_resolved = false
	return info


# 通用技能伤害工厂：raw 折叠 ATK × WEAPON_mult；crit/combo/dmg_*/elem_* 全部交 resolver
func make_ability_damage(source: String, mult: float, category: String, element: String = "", can_crit: bool = true, is_dot: bool = false) -> DamageInfo:
	var info := make_damage(source, mult, category, element, can_crit, is_dot)
	info.raw_amount = get_ability_damage(mult)
	# crit roll 留给 resolver
	info.is_crit_resolved = false
	return info


func take_damage(amount: int) -> int:
	if invincible_timer > 0.0 or is_attack_invincible():
		return 0
	# 装备 sturdy_helmet 橙：5% 概率完全免伤（加法概率，不复利）
	if hit_dodge_chance > 0.0 and randf() < hit_dodge_chance:
		var battle_dodge := get_tree().get_first_node_in_group("battle")
		if battle_dodge and battle_dodge.hud:
			battle_dodge.hud.show_message(LanguageManager.tr_ui("UI_HUD_DODGE", "闪避"), 0.6)
		return 0
	# 过场期间免伤（玩家在跳跃 / 滚轴中不可被命中）
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and "_transition_damage_lock" in battle and battle._transition_damage_lock:
		return 0
	# Phase 5 sr=10 iframe_on_hit：CD ≤ 0 时本次伤害免疫；sr=1 on_hit_window：开启 buff 窗口
	if SpecialRuleDispatcherT.on_player_damaged(self, amount):
		return 0
	var final_damage := DamageResolver.compute_player_incoming(amount, bonus_damage_reduction)
	hp = maxi(0, hp - final_damage)
	# Phase 3 sr=7 revive：致死前给一次机会
	if hp <= 0:
		if SpecialRuleDispatcherT.on_death(self):
			final_damage = maxi(0, final_damage - 1)  # 复活：当次伤害不致死
	invincible_timer = float(GameConfig.get_player_value("invincible_time", 0.45))
	damage_flash_timer = 0.42
	queue_redraw()
	if state == State.IDLE:
		_auto_bullet_cycle_active = false
		_auto_bullet_released = false
		_play_anim(SpriteHelper.ANIM_HURT)
	EventBus.player_damaged.emit(final_damage, hp)
	AudioManager.play_player_hurt()
	if battle:
		battle.shake_camera(4.0, 0.12)
	return final_damage


func apply_equipment_flags(flags: Dictionary) -> void:
	# 由 _rebuild_upgrades 末尾调用；负责把 LobbyState.get_active_equipment_flags() 的布尔状态
	# 映射到 player 上的行为变量。tree_x2 属于关卡侧，由 battle.gd 单独读。
	# 装 storm_greatsword 传奇 → 与卡片 sr=12 逻辑或运算（两者任一 true 都开启）
	if bool(flags.get("bullet_homing", false)):
		bullet_homing_enabled = true
	# 5% 概率免伤
	hit_dodge_chance = 0.05 if bool(flags.get("hit_dodge_5pct", false)) else 0.0
	# 持续电击靠近的敌人
	aura_shock_enabled = bool(flags.get("shock_aura", false))
	if not aura_shock_enabled:
		aura_shock_tick_timer = 0.0


func _process_aura_shock(delta: float) -> void:
	if not aura_shock_enabled:
		return
	aura_shock_tick_timer -= delta
	if aura_shock_tick_timer > 0.0:
		return
	aura_shock_tick_timer = AURA_SHOCK_TICK
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null:
		return
	var monsters := get_tree().get_nodes_in_group("monster")
	if monsters.is_empty():
		return
	var origin := global_position
	var radius_sq := AURA_SHOCK_RADIUS * AURA_SHOCK_RADIUS
	var dmg := maxi(1, int(round(get_ability_damage(AURA_SHOCK_ATK_MULT))))
	for m in monsters:
		if m == null or not is_instance_valid(m):
			continue
		if not (m is Node2D):
			continue
		if origin.distance_squared_to(m.global_position) > radius_sq:
			continue
		# 走 DamageInfo（雷元素 → Sheet4 element_effects 自动应用麻痹，遵守 CLAUDE.md 第一条）
		var info := DamageInfo.legacy(dmg)
		info.source = "equip_shock_aura"
		info.category = "ability"
		info.element = "thunder"
		info.can_crit = false
		info.is_dot = true
		if m.has_method("take_damage_info"):
			m.take_damage_info(info, origin)
		elif m.has_method("take_damage"):
			m.take_damage(dmg, origin)

func heal_percent(ratio: float) -> void:
	var amount := int(round(max_hp * ratio))
	hp = mini(max_hp, hp + amount)
	queue_redraw()
	EventBus.player_healed.emit(amount, hp)


func apply_upgrade(upgrade: Dictionary) -> void:
	var id := str(upgrade.get("id", ""))
	var def := GameConfig.get_upgrade(id)
	if def.is_empty():
		def = upgrade
	if int(def.get("once_per_run", 0)) != 0:
		run_acquired_once[id] = true
	if int(def.get("once_per_chapter", 0)) != 0:
		chapter_acquired_once[id] = true
	upgrade_stacks[id] = int(upgrade_stacks.get(id, 0)) + 1
	# 记录获得顺序（后获得的覆盖之前，用于"普攻换形态"等视觉互斥卡）
	_card_acquired_counter += 1
	_card_acquired_seq[id] = _card_acquired_counter
	_rebuild_upgrades()
	# v6 sv_life_spring 等 on_pickup 卡：选卡瞬间也算一次拾取触发
	if trigger_dispatcher != null and str(def.get("trigger", "")) == "on_pickup":
		trigger_dispatcher.fire_on_pickup()


# 返回当前普攻子弹视觉类型（后获得的"换形态"卡胜出）：
#   "spirit"      → 元气弹（蓝白能量球，由 bullet_spirit_bomb 触发）
#   "blood_blade" → 血飞刀（红刃匕首，由 demon_blood_blade 触发）
#   ""            → 默认普攻（像素小火球）
# 顺序由 _card_acquired_seq 比较：seq 大 = 后获得 = 视觉胜出
func get_active_bullet_visual_kind() -> String:
	const CONVERTERS := {
		"bullet_spirit_bomb": "spirit",
		"demon_blood_blade":  "blood_blade",
	}
	var best_kind: String = ""
	var best_seq: int = -1
	for card_id in CONVERTERS:
		if int(upgrade_stacks.get(card_id, 0)) <= 0:
			continue
		var seq: int = int(_card_acquired_seq.get(card_id, 0))
		if seq > best_seq:
			best_seq = seq
			best_kind = String(CONVERTERS[card_id])
	return best_kind


func is_upgrade_pool_blocked(id: String) -> bool:
	var def := GameConfig.get_upgrade(id)
	if def.is_empty():
		return false
	if int(def.get("once_per_run", 0)) != 0 and bool(run_acquired_once.get(id, false)):
		return true
	if int(def.get("once_per_chapter", 0)) != 0 and bool(chapter_acquired_once.get(id, false)):
		return true
	return false


func get_luck_roll_offsets() -> Dictionary:
	return {
		"blue": luck_roll_blue_offset,
		"purple": luck_roll_purple_offset,
		"orange": luck_roll_orange_offset,
	}


func on_chapter_started(_chapter_id: int) -> void:
	chapter_acquired_once.clear()


func get_upgrade_level(id: String) -> int:
	return int(upgrade_stacks.get(id, 0))


func rebuild_upgrades_from_stacks(stacks: Dictionary, silent := false) -> void:
	var hp_ratio := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	upgrade_stacks.clear()
	for u in GameConfig.upgrades:
		var id := str(u.get("id", ""))
		var lv := clampi(int(stacks.get(id, 0)), 0, int(u.get("max_level", 9)))
		if lv > 0:
			upgrade_stacks[id] = lv
	_rebuild_upgrades()
	hp = maxi(1, int(round(float(max_hp) * hp_ratio)))
	ki = minf(ki, ki_max)
	if not silent:
		var battle := get_tree().get_first_node_in_group("battle")
		if battle and battle.hud:
			battle.hud.show_message("调试: 强化已更新", 1.2)


func _rebuild_upgrades() -> void:
	base_attack = float(GameConfig.get_player_value("base_attack", 95))
	base_ki = float(GameConfig.get_player_value("base_ki", 234))
	max_hp = int(GameConfig.get_player_value("base_hp", 100))
	crit_rate = float(GameConfig.get_player_value("base_crit_rate", 0.08))
	basic_attack_speed = maxf(0.01, float(GameConfig.get_player_value("basic_attack_speed", 2.0)))
	ki_regen_speed = maxf(0.0, float(GameConfig.get_player_value("ki_regen_speed", 135.0)))
	size_scale = 1.0
	bullet_count = 1
	attack_speed_mult = 1.0
	ki_regen_mult = 1.0
	slash_damage_mult = 1.0
	bonus_attack_mult = 1.0
	bonus_attack_speed_mult = 1.0
	bonus_crit_rate = 0.0
	bonus_crit_damage = 0.0
	bonus_damage_reduction = 0.0
	move_speed_penalty_mult = 1.0
	luck_roll_blue_offset = 0.0
	luck_roll_purple_offset = 0.0
	luck_roll_orange_offset = 0.0
	# v2 分层字段重置(每次 _rebuild_upgrades 都从零重建)
	atk_pct_total = 0.0
	dmg_all_pct = 0.0
	dmg_slash_pct = 0.0
	dmg_bullet_pct = 0.0
	dmg_combo_pct = 0.0
	dmg_trail_pct = 0.0
	dmg_sword_pct = 0.0
	dmg_summon_pct = 0.0
	elem_all_pct = 0.0
	elem_fire_pct = 0.0
	elem_ice_pct = 0.0
	elem_thunder_pct = 0.0
	elem_poison_pct = 0.0
	elem_proc_fire = 0.0
	elem_proc_ice = 0.0
	elem_proc_thunder = 0.0
	elem_proc_poison = 0.0
	# v6 表驱动 attr 累加字段重置
	atk_speed_pct_total = 0.0
	move_speed_pct_total = 0.0
	max_hp_pct_total = 0.0
	ki_max_pct_total = 0.0
	ki_regen_pct_total = 0.0
	dodge_pct_total = 0.0
	luck_pct_total = 0.0
	size_pct_total = 0.0
	bullet_count_bonus = 0
	elem_proc_freq_pct = 0.0
	slow_pct_bonus = 0.0
	chain_targets_bonus = 0
	elem_fire_attach_atk_mult = 0.0
	elem_ice_attach_atk_mult = 0.0
	elem_thunder_attach_atk_mult = 0.0
	elem_poison_attach_atk_mult = 0.0
	cooldown_sec_total = 0.0
	duration_sec_total = 0.0
	tick_interval_sec_total = 0.0
	# Phase 4 召唤
	summon_king_count = 0
	summon_god_count = 0
	summon_gorilla_count = 0
	summon_thunder_count = 0
	summon_bear_count = 0
	summon_snake_count = 0
	summon_fire_count = 0
	summon_size_pct = 0.0
	summon_atk_speed_pct = 0.0
	# Phase 5 SR 静态字段重置（动态计时不重置）
	trail_width_pct_total = 0.0
	bullet_homing_enabled = false
	bullet_mirror_mult = 0.0
	stand_guard_active = false
	# Phase 6 SR 静态字段重置
	trail_multi_count = 0
	trail_pierce_obstacles = false
	# Phase 7 sword 字段重置
	sword_guard_count = 0
	sword_blood_count = 0
	sword_flame_count = 0
	sword_thunder_count = 0
	sword_poison_count = 0
	sword_frost_count = 0
	sword_count_mult = 1.0
	sword_length_pct = 0.0
	sword_speed_pct = 0.0
	sword_dmg_pct = 0.0
	# Phase 7 orb 字段重置（pending buff / dup_chance 等动态状态不重置）
	orb_field_pct = 0.0
	orb_pickup_radius_pct = 0.0
	orb_line_magnet_pct = 0.0
	orb_glow_dmg_pct = 0.0
	orb_mark_dup_chance = 0.0
	orb_tide_interval_sec = 0.0
	# 主题关静态字段重置（动态计时如 sulfur_laser_timer / multi_revive_extra 不重置）
	summon_demon_baby_count = 0
	summon_angel_baby_count = 0
	sword_spear_count = 0
	scythe_atk_mult = 0.0
	scythe_pierce = false
	blood_blade_pierce = false
	blood_blade_range_mult = 1.0
	sulfur_laser_atk_mult = 0.0  # 0 = 未装备硫磺火
	proximity_slow_radius = 0.0
	proximity_slow_max = 0.0
	# 追加：sr 51-56 静态字段重置（动态计时如 unicorn_timer / shield_orbit_angle 不重置）
	psychic_petrify_duration = 0.0
	unicorn_cd = 0.0
	unicorn_duration = 0.0
	laser_cannon_active = false
	laser_cannon_atk_mult = 3.0
	laser_cannon_pierce = true
	laser_cannon_color_key = "white"
	melee_basic_active = false
	melee_basic_atk_bonus = 0.5
	melee_range_px = 60.0
	bomber_atk_mult = 0.0
	bomber_fuse_sec = 2.0
	bomber_cross_arm_px = 180.0
	shield_orbit_count = 0
	shield_orbit_radius = 280.0
	shield_orbit_speed = 1.5

	# 表驱动写入：遍历所有 v6 卡，AttrEngine 按 trigger 判断是否激活
	AttrEngineT.apply_cards(self, upgrade_stacks, GameConfig.upgrades_by_id)

	# 属性打造关 forge buff：加在卡牌同层（*_pct_total），最终一起换算成实际生效字段。
	atk_pct_total += forge_atk_pct_total
	atk_speed_pct_total += forge_atk_speed_pct_total
	move_speed_pct_total += forge_move_speed_pct_total
	max_hp_pct_total += forge_max_hp_pct_total
	ki_max_pct_total += forge_ki_max_pct_total
	ki_regen_pct_total += forge_ki_regen_pct_total
	crit_rate += forge_crit_rate_total
	# 装备（equipments.json）% 加成也进 total_pct，一起在下面一次性 apply（不复利）
	ki_max_pct_total += equip_max_ki_pct
	ki_regen_pct_total += equip_ki_regen_pct

	# v6 attr 累加 -> 实际生效字段
	attack_speed_mult = 1.0 + atk_speed_pct_total
	ki_regen_mult = 1.0 + ki_regen_pct_total
	move_speed_penalty_mult = maxf(0.05, 1.0 + move_speed_pct_total)
	size_scale = maxf(0.1, 1.0 + size_pct_total)
	bullet_count = maxi(0, bullet_count + bullet_count_bonus)
	max_hp = maxi(1, int(round(float(max_hp) * (1.0 + max_hp_pct_total))))
	base_ki = base_ki * (1.0 + ki_max_pct_total)
	# 闪避 / 幸运 累加（暂以加法形式存入对应字段）
	bonus_crit_rate += 0.0  # crit_rate 由 attr_code 7 直接累加到 crit_rate 字段（_is_active 决定）
	# 幸运按 1% per luck_pct -> orange/purple offsets 简单转换：luck_pct 直接灌进 orange offset
	luck_roll_orange_offset += luck_pct_total

	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += int(equip.get("max_hp", 0))
		crit_rate += float(equip.get("crit_rate", 0.0))
		# crit_damage +% 在 rebuild 后再作用一次（因 base 值刚被卡片系统重设）
		var eq_crit_dmg_pct2 := float(equip.get("crit_damage", 0.0))
		if eq_crit_dmg_pct2 != 0.0:
			crit_damage += crit_damage * eq_crit_dmg_pct2
		# 装备 flag（tree_x2 由 battle.gd 直接读；这里只处理玩家自身 flag）
		var flags: Dictionary = LobbyState.get_active_equipment_flags()
		apply_equipment_flags(flags)
		# 天赋卡 flat 加成：rebuild 会重置 base_attack/max_hp/base_ki/crit_rate/ki_regen_speed，需要重新加上
		var talent := LobbyState.get_talent_modifiers()
		talent_attack_add = float(talent.get("attack", 0.0))
		talent_max_hp_add = int(talent.get("max_hp", 0))
		talent_max_ki_add = float(talent.get("max_ki", 0.0))
		talent_ki_regen_add = float(talent.get("ki_regen", 0.0))
		talent_crit_rate_add = float(talent.get("crit_rate", 0.0))
		talent_crit_damage_add = float(talent.get("crit_damage", 0.0))
		talent_move_speed_add = float(talent.get("move_speed", 0.0))
		talent_attack_interval_add = float(talent.get("attack_interval", 0.0))
		talent_bullet_range_add = float(talent.get("bullet_range", 0.0))
		base_attack += talent_attack_add
		max_hp += talent_max_hp_add
		base_ki += talent_max_ki_add
		ki_regen_speed += talent_ki_regen_add
		crit_rate += talent_crit_rate_add
		crit_damage += talent_crit_damage_add
	ki_max = base_ki
	ki_regen_speed *= ki_regen_mult
	hp = mini(hp, max_hp)
	_update_trigger_radius()
	_apply_sprite_scale()
	sync_auto_bullet_anim_speed()
	# Phase 5 sr=29 trail_width：path_line 加宽
	if path_line:
		path_line.width = GameConfig.scale_world(PATH_LINE_WIDTH) * (1.0 + trail_width_pct_total)
	_update_trail_extra_lines()
	# v6 元素状态注入：按 card_path 分组的 applies_<elem>
	_rebuild_current_applies()
	# Phase 3 SR 调整 player 字段（boss_target / kill_stack 累积等）
	SpecialRuleDispatcherT.on_rebuild(self)
	# 把 trigger 卡注册给 dispatcher
	if trigger_dispatcher != null:
		trigger_dispatcher.register(AttrEngineT.collect_trigger_bindings(upgrade_stacks, GameConfig.upgrades_by_id))


# 遍历当前装备的 v6 卡：把 applies_<elem>=1 按 emitter category 累积到 current_applies。
# 让 make_damage 按 emitter category 取出对应 4 个布尔写到 DamageInfo。
#
# 注：v6 表 card_path='element' 仅表示走 ELEM 层增伤，不代表 emitter 作用域。
# 真实作用域按卡 id 前缀映射：
#   elem_*_bullet → "bullet"
#   sword_*  → "sword"
#   trail_*  → "trail"
#   orb_*    → "trail"（球体生成场域 / 命中走轨迹通道；待 Phase 3 special_rule 细化）
#   summon_* → "summon"
#   combo_*  → "combo"（含 fireball/water_tornado/blade_storm/thunder）
#   basic_flame_walk 不在此映射 — 它的 applies_fire 由 sr=5 dispatcher 直接在
#   _flame_walk_tick 里施加（脚下 fire 场域），不应附在普攻子弹上。
func _rebuild_current_applies() -> void:
	current_applies = {}
	for id in upgrade_stacks.keys():
		var level := int(upgrade_stacks[id])
		if level <= 0:
			continue
		var def: Dictionary = GameConfig.upgrades_by_id.get(id, {})
		if def.is_empty():
			continue
		var has_any: bool = (int(def.get("applies_fire", 0)) != 0
			or int(def.get("applies_ice", 0)) != 0
			or int(def.get("applies_thunder", 0)) != 0
			or int(def.get("applies_poison", 0)) != 0)
		if not has_any:
			continue
		var cat: String = _infer_emitter_category(id, str(def.get("card_path", "")))
		if cat.is_empty():
			continue
		var bucket: Dictionary = current_applies.get(cat, {"fire": false, "ice": false, "thunder": false, "poison": false})
		if int(def.get("applies_fire", 0)) != 0:
			bucket["fire"] = true
		if int(def.get("applies_ice", 0)) != 0:
			bucket["ice"] = true
		if int(def.get("applies_thunder", 0)) != 0:
			bucket["thunder"] = true
		if int(def.get("applies_poison", 0)) != 0:
			bucket["poison"] = true
		current_applies[cat] = bucket


func _infer_emitter_category(card_id: String, card_path: String) -> String:
	if card_path == "combo":
		return "combo"
	if card_id.begins_with("elem_") and card_id.ends_with("_bullet"):
		return "bullet"
	if card_id.begins_with("sword_"):
		return "sword"
	if card_id.begins_with("trail_"):
		return "trail"
	if card_id.begins_with("orb_"):
		return "trail"
	if card_id.begins_with("summon_"):
		return "summon"
	if card_id.begins_with("combo_"):
		return "combo"
	return ""


func grant_force_legendary_upgrade() -> void:
	force_legendary_upgrade_count += 1


func consume_force_legendary_upgrade() -> bool:
	if force_legendary_upgrade_count <= 0:
		return false
	force_legendary_upgrade_count -= 1
	return true


func _play_anim(anim_name: String, force: bool = false) -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if anim_name == SpriteHelper.ANIM_HURT:
		force = true
	if not force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	if force and anim_sprite.animation == anim_name and anim_sprite.is_playing():
		anim_sprite.stop()
		anim_sprite.frame = 0
	anim_sprite.play(anim_name)
	_apply_combat_modulate()


func _on_animation_finished() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if anim_sprite.animation == SpriteHelper.ANIM_DEATH:
		if is_fail_death_pose() and not bool(death_anim.get("frozen", false)):
			death_anim["anim_finished"] = true
		return
	if anim_sprite.animation == SpriteHelper.ANIM_CHARGE:
		if state == State.BULLET_TIME and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_CHARGE_LOOP):
			anim_sprite.play(SpriteHelper.ANIM_CHARGE_LOOP)
		return
	if anim_sprite.animation in [SpriteHelper.ANIM_ATTACK, SpriteHelper.ANIM_ATTACK01, SpriteHelper.ANIM_HURT]:
		if state == State.ATTACKING and anim_sprite.animation == SpriteHelper.ANIM_ATTACK:
			return
		if anim_sprite.animation == SpriteHelper.ANIM_ATTACK01:
			_auto_bullet_cycle_active = false
			_auto_bullet_released = false
		if anim_sprite.animation == SpriteHelper.ANIM_HURT and state == State.BULLET_TIME and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_CHARGE_LOOP):
			anim_sprite.play(SpriteHelper.ANIM_CHARGE_LOOP)
			return
		if anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)


func _apply_combat_modulate() -> void:
	# 传送门进出动画期间：portal_traverse 用 tween 控制 modulate.a，
	# 这里不能用 Color.WHITE / 受伤色覆盖。
	if _portal_traverse_active:
		return
	# sr=52 独角兽：无敌期间彩虹 modulate（优先级高于受伤/普通无敌闪烁）
	if unicorn_rainbow_active and invincible_timer > 0.0 and damage_flash_timer <= 0.0:
		var hue: float = fmod(float(Time.get_ticks_msec()) * 0.0005, 1.0)
		modulate = Color.from_hsv(hue, 0.85, 1.0)
		return
	if damage_flash_timer > 0.0 and int(floor(damage_flash_timer * 22.0)) % 2 == 0:
		modulate = Color(1.0, 0.45, 0.45)
	elif invincible_timer > 0.0 and damage_flash_timer <= 0.0 and int(floor(invincible_timer * 18.0)) % 2 == 0:
		modulate = Color(1.0, 1.0, 1.0, 0.55)
	else:
		modulate = Color.WHITE
	# 水地块蓝色 tint：与受伤/无敌闪烁分层；用 timer 衰减
	if water_tint_timer > 0.0:
		var blend: float = WATER_TINT_BLEND * (water_tint_timer / WATER_TINT_FADE)
		if blend > 0.001:
			modulate = modulate.lerp(WATER_TINT_COLOR, blend)


func _check_water_under_feet(battle: Node) -> void:
	on_water_terrain = false
	if battle == null:
		return
	var t = battle.terrain if "terrain" in battle else null
	if t == null or not t.has_method("get_tile_at_world"):
		return
	if t.get_tile_at_world(global_position.x, global_position.y) == "water":
		on_water_terrain = true
		water_tint_timer = WATER_TINT_FADE  # 持续踩水时每帧刷新计时器


func trigger_combo_abilities(_combo: int, _target_pos: Vector2) -> void:
	pass


func update_joystick_locomotion(dir: Vector2, delta: float, battle: Node) -> void:
	if state != State.IDLE:
		_stop_joystick_locomotion_visual()
		return
	if dir.length_squared() < 0.01:
		_stop_joystick_locomotion_visual()
		return
	_check_water_under_feet(battle)
	var water_mult := WATER_SLOW_MULT if on_water_terrain else 1.0
	var base_move := float(GameConfig.get_player_value("move_speed", 120.0)) + equip_move_speed_add + talent_move_speed_add
	var speed := base_move * move_speed_penalty_mult * water_mult
	var next_pos := global_position + dir.normalized() * speed * delta
	var blocked: bool = battle != null and battle.has_method("is_blocked_by_tree") and battle.is_blocked_by_tree(next_pos)
	if battle != null and battle.has_method("is_in_bounds") and battle.is_in_bounds(next_pos) and not blocked:
		global_position = next_pos
		home_position = global_position
	var anim_sprite := _get_sprite()
	if anim_sprite:
		if dir.x < -0.01:
			anim_sprite.flip_h = true
		elif dir.x > 0.01:
			anim_sprite.flip_h = false
	_joystick_locomotion_active = true
	if not SpriteHelper.is_playing_priority_anim(anim_sprite):
		_play_anim(SpriteHelper.ANIM_WALK)


func _stop_joystick_locomotion_visual() -> void:
	if not _joystick_locomotion_active:
		return
	_joystick_locomotion_active = false
	if state != State.IDLE:
		return
	var anim_sprite := _get_sprite()
	if anim_sprite and not SpriteHelper.is_playing_priority_anim(anim_sprite):
		_play_anim(SpriteHelper.ANIM_IDLE)


func update_idle(delta: float, time_scale: float) -> void:
	if state != State.IDLE:
		return
	if invincible_timer > 0.0:
		invincible_timer -= delta
	if damage_flash_timer > 0.0:
		damage_flash_timer -= delta
	if water_tint_timer > 0.0:
		water_tint_timer = maxf(0.0, water_tint_timer - delta)
	_apply_combat_modulate()
	if _can_regen_ki():
		ki = minf(ki_max, ki + ki_regen_speed * delta * time_scale)


func _can_regen_ki() -> bool:
	if state != State.IDLE or ki >= ki_max - 0.01:
		return false
	var battle := get_tree().get_first_node_in_group("battle")
	if battle == null or battle.combat == null:
		return false
	if battle.combat.is_resolving():
		return false
	if not battle.combat.round_attack_resolved:
		return false
	if battle.state == GameState.LEVEL_UP:
		return false
	return true


func reset_for_new_run() -> void:
	upgrade_stacks.clear()
	run_acquired_once.clear()
	chapter_acquired_once.clear()
	_card_acquired_seq.clear()
	_card_acquired_counter = 0
	force_legendary_upgrade_count = 0
	clear_fail_death_visuals()
	reset_run_forge_buffs()
	_load_base_stats()
	hp = max_hp
	ki = ki_max
	home_position = global_position
	begin_stage()
	_rebuild_upgrades()


# 属性打造关 forge buff 重置：开局 / 回主菜单 / 死亡新开时清零。
func reset_run_forge_buffs() -> void:
	forge_atk_pct_total = 0.0
	forge_atk_speed_pct_total = 0.0
	forge_move_speed_pct_total = 0.0
	forge_max_hp_pct_total = 0.0
	forge_ki_max_pct_total = 0.0
	forge_ki_regen_pct_total = 0.0
	forge_crit_rate_total = 0.0
	forge_draw_cost_pct_total = 0.0


# 属性打造关：每块成功堆稳调一次，按 idx 选 1 个基础属性 ±3%，调 _rebuild_upgrades() 立即生效。
# idx 范围 0..7，返回 {name_cn, delta} 供 UI 显示。
func apply_forge_buff(idx: int) -> Dictionary:
	var name_cn := ""
	var delta := 0.0
	match idx:
		0:
			forge_max_hp_pct_total += 0.03
			name_cn = "基础生命"
			delta = 0.03
		1:
			forge_atk_pct_total += 0.03
			name_cn = "基础攻击力"
			delta = 0.03
		2:
			forge_ki_max_pct_total += 0.03
			name_cn = "气力上限"
			delta = 0.03
		3:
			forge_crit_rate_total += 0.03
			name_cn = "暴击率"
			delta = 0.03
		4:
			forge_move_speed_pct_total += 0.03
			name_cn = "移速"
			delta = 0.03
		5:
			forge_atk_speed_pct_total += 0.03
			name_cn = "攻速"
			delta = 0.03
		6:
			forge_ki_regen_pct_total += 0.03
			name_cn = "气力恢复"
			delta = 0.03
		7:
			forge_draw_cost_pct_total = maxf(-0.95, forge_draw_cost_pct_total - 0.03)
			name_cn = "画线消耗"
			delta = -0.03
		_:
			return {}
	# Preserve current hp/ki ratios so max_hp/ki_max growth doesn't drop us proportionally.
	var hp_ratio := float(hp) / float(maxi(1, max_hp))
	var ki_ratio := ki / maxf(0.001, ki_max)
	_rebuild_upgrades()
	hp = clampi(int(round(float(max_hp) * hp_ratio)), 1, max_hp)
	ki = clampf(ki_max * ki_ratio, 0.0, ki_max)
	return {"name_cn": name_cn, "delta": delta}


func on_enemy_killed(_kill_pos: Vector2) -> void:
	pass


func get_bonus_damage_reduction() -> float:
	return clampf(bonus_damage_reduction, 0.0, 0.8)


func is_near_stationary() -> bool:
	return global_position.distance_to(_last_position) <= 2.0


func on_summon_hit() -> void:
	pass


func _update_new_upgrade_states(_delta: float) -> void:
	# 每帧重置 bonus_* 字段。这些字段被 sr=9 stand_guard / attr_engine id=11 等
	# 累加式写入；必须每帧清零，否则会无限堆叠。
	bonus_attack_mult = 1.0
	bonus_attack_speed_mult = 1.0
	bonus_crit_rate = 0.0
	bonus_crit_damage = 0.0
	bonus_damage_reduction = 0.0
	_last_position = global_position


func _apply_path_line_color() -> void:
	path_line.default_color = PATH_LINE_COLOR_ATTACK if state == State.ATTACKING else PATH_LINE_COLOR


func _update_path_line() -> void:
	path_line.clear_points()
	for p in attack_path:
		path_line.add_point(p)
	_apply_path_line_color()
	_update_trail_extra_lines()


# sr=24 trail_multi：返回平行线偏移距离（不含主线 0）。i%2==0 走 +侧，i%2==1 走 -侧
func _trail_offset_distances() -> Array:
	var distances: Array = []
	var extra_count: int = trail_multi_count
	if extra_count <= 0:
		return distances
	var spacing: float = GameConfig.scale_world(28.0)
	for i in range(extra_count):
		var d: float = spacing * float(i / 2 + 1) * (1.0 if i % 2 == 0 else -1.0)
		distances.append(d)
	return distances


# 把 attack_path 沿"顶点法线"偏移 offset 像素，得到平行 polyline。
# 顶点法线 = 前后段法线平均，端点用所在段法线
func _offset_polyline(offset: float) -> Array:
	var n: int = attack_path.size()
	if n < 2 or absf(offset) < 0.001:
		return attack_path.duplicate()
	var out: Array = []
	for i in range(n):
		var prev_dir: Vector2 = Vector2.ZERO
		var next_dir: Vector2 = Vector2.ZERO
		if i > 0:
			prev_dir = (attack_path[i] - attack_path[i - 1]).normalized()
		if i < n - 1:
			next_dir = (attack_path[i + 1] - attack_path[i]).normalized()
		var tan: Vector2
		if prev_dir == Vector2.ZERO:
			tan = next_dir
		elif next_dir == Vector2.ZERO:
			tan = prev_dir
		else:
			tan = (prev_dir + next_dir).normalized()
		if tan == Vector2.ZERO:
			tan = Vector2.RIGHT
		var normal: Vector2 = Vector2(-tan.y, tan.x)
		out.append(attack_path[i] + normal * offset)
	return out


func _update_trail_extra_lines() -> void:
	var distances: Array = _trail_offset_distances()
	var needed: int = distances.size()
	# 同步节点数量
	while _trail_extra_lines.size() < needed:
		var line := Line2D.new()
		line.top_level = true
		line.z_index = path_line.z_index
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(line)
		_trail_extra_lines.append(line)
	while _trail_extra_lines.size() > needed:
		var line: Line2D = _trail_extra_lines.pop_back()
		line.queue_free()
	if needed == 0:
		return
	var base_color: Color = path_line.default_color
	var base_width: float = path_line.width
	for i in range(needed):
		var line: Line2D = _trail_extra_lines[i]
		line.clear_points()
		if attack_path.size() >= 2:
			for p in _offset_polyline(distances[i]):
				line.add_point(p)
		line.default_color = Color(base_color.r, base_color.g, base_color.b, base_color.a * 0.78)
		line.width = base_width * 0.88
		line.visible = path_line.visible


func begin_fail_death(info: Dictionary) -> void:
	death_anim = info.duplicate()
	death_anim["active"] = true
	_trigger_ring_fade_t = 0.0
	path_line.visible = false
	for _l in _trail_extra_lines:
		_l.visible = false
	modulate = Color.WHITE
	z_index = 2
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		queue_redraw()
		return
	anim_sprite.rotation = 0.0
	anim_sprite.position = Vector2.ZERO
	var speed_scale := maxf(0.05, float(info.get("speed_scale", 0.35)))
	var frame_count := 0
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		frame_count = anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if frame_count <= 1:
		anim_sprite.speed_scale = 1.0
	else:
		anim_sprite.speed_scale = speed_scale
	death_anim["slow_speed_scale"] = speed_scale
	death_anim["last_frame_normal"] = frame_count <= 1
	death_anim["anim_finished"] = false
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		anim_sprite.play(SpriteHelper.ANIM_DEATH)
	elif anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		anim_sprite.play(SpriteHelper.ANIM_IDLE)
	queue_redraw()


func freeze_fail_death_pose() -> void:
	if death_anim.is_empty():
		return
	var anim_sprite := _get_sprite()
	if anim_sprite == null:
		death_anim["frozen"] = true
		return
	anim_sprite.stop()
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_DEATH):
		var frame_count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
		if frame_count > 0:
			anim_sprite.frame = frame_count - 1
	death_anim["frozen"] = true
	queue_redraw()


func _reset_sprite_pose() -> void:
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.rotation = 0.0
		anim_sprite.position = Vector2.ZERO
	modulate = Color.WHITE


func clear_fail_death_visuals() -> void:
	death_anim.clear()
	var anim_sprite := _get_sprite()
	if anim_sprite:
		anim_sprite.speed_scale = 1.0
		anim_sprite.rotation = 0.0
		anim_sprite.position = Vector2.ZERO
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			anim_sprite.play(SpriteHelper.ANIM_IDLE)
	z_index = 0
	modulate = Color.WHITE
	queue_redraw()


func is_fail_death_pose() -> bool:
	return not death_anim.is_empty() and bool(death_anim.get("active", false))


func is_fail_death_anim_finished() -> bool:
	return bool(death_anim.get("anim_finished", false))


func _update_fail_death_last_frame_speed(anim_sprite: AnimatedSprite2D) -> void:
	if anim_sprite.sprite_frames == null or anim_sprite.animation != SpriteHelper.ANIM_DEATH:
		return
	if bool(death_anim.get("last_frame_normal", false)):
		return
	var frame_count := anim_sprite.sprite_frames.get_frame_count(SpriteHelper.ANIM_DEATH)
	if frame_count <= 1:
		return
	if anim_sprite.frame >= frame_count - 2:
		death_anim["last_frame_normal"] = true
		anim_sprite.speed_scale = 1.0


func _process(delta: float) -> void:
	_update_draw_start_fx(delta)
	if trigger_dispatcher != null:
		trigger_dispatcher.tick(delta)
	SpecialRuleDispatcherT.on_tick(self, delta)
	_process_aura_shock(delta)
	if is_fail_death_pose():
		path_line.visible = false
		for _l in _trail_extra_lines:
			_l.visible = false
		queue_redraw()
		return
	if state == State.IDLE:
		_apply_combat_modulate()
	_update_new_upgrade_states(delta)
	path_line.visible = attack_path.size() >= 2
	for _l in _trail_extra_lines:
		_l.visible = path_line.visible
	_update_trigger_ring_fade(delta)
	# sr=50 无下限术式：领域圈有脉冲动画，需每帧重绘
	if float(proximity_slow_radius) > 0.0:
		queue_redraw()
	# 打造关头顶 ↑ 箭头 tick：放 _process（而非 update_idle）让 LEVEL_UP 状态下也能更新
	if _forge_arrow_timer > 0.0:
		_forge_arrow_timer = maxf(0.0, _forge_arrow_timer - delta)
		_forge_arrow_t += delta
		queue_redraw()


func _should_show_hp_bar() -> bool:
	return hp < max_hp


func get_head_top_global_position() -> Vector2:
	return SpriteHelper.get_character_head_top_global(
		_get_sprite(),
		global_position + Vector2(0.0, -get_effective_radius() * 1.5)
	)


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
			"border_color": "#122028",
			"panel_fill": "#101a20",
			"empty_a": "#18303a",
			"empty_b": "#10262f",
			"fill_color": "#36b88a",
			"shine_color": "#9cffd4",
			"segment_count": 8,
			"segment_gap": 1
		}
	)


func _draw_closed_ring(center: Vector2, radius: float, point_count: int, color: Color, width: float) -> void:
	# draw_arc at exactly [0, TAU] can show a visible seam at 0 angle on some scales.
	# Expand a tiny angle on both sides so both caps overlap and hide the gap.
	var overlap := TAU / maxf(96.0, float(point_count) * 2.0)
	draw_arc(center, radius, -overlap, TAU + overlap, point_count + 2, color, width)


func _draw() -> void:
	if is_fail_death_pose():
		return
	if _should_show_hp_bar():
		_draw_hp_bar()
	# 打造关结算后头顶 ↑ 箭头
	if _forge_arrow_timer > 0.0:
		_draw_forge_buff_arrow()
	# 无下限术式（sr=50）：脚下减速领域 — 半径 = proximity_slow_radius
	# 与触发环独立，独立于 ring_alpha：玩家移动 / 战斗中也始终可见
	if float(proximity_slow_radius) > 0.0:
		_draw_proximity_slow_aura(float(proximity_slow_radius))
	# sr=6 圣盾：每层 charges 画一圈金色像素环绕（旋转 + 闪烁）
	if holy_shield_charges > 0:
		_draw_holy_shield(holy_shield_charges)
	# sr=56 orbit_shield：环绕盾（数量 = shield_orbit_count）
	if shield_orbit_count > 0:
		_draw_orbit_shields()
	var ring_alpha := _get_trigger_ring_alpha()
	if ring_alpha <= 0.0:
		return
	var radius := get_trigger_radius() * lerpf(0.88, 1.0, ring_alpha)
	var visual_radius := radius * TRIGGER_RING_VISUAL_SCALE
	_draw_closed_ring(
		Vector2.ZERO,
		visual_radius,
		64,
		Color(1.0, 1.0, 1.0, 0.35 * ring_alpha),
		GameConfig.scale_world(2.0)
	)
	_draw_closed_ring(
		Vector2.ZERO,
		visual_radius,
		64,
		Color(1.0, 0.9, 0.3, 0.12 * ring_alpha),
		visual_radius * 1.3
	)


# 圣盾视觉：像素栅格金色光环，按 charges 数堆叠不同半径同心环。
# 参考 _draw_pixel_fireball / _draw_pixel_scythe_blade 的 4 档调色板 + 周期闪烁 + 旋转。
const HOLY_SHIELD_PIXEL := 3.0
const HOLY_SHIELD_BASE_RADIUS := 11.0   # 单位：块数（基础半径 11 块 × 3px ≈ 33px）
const HOLY_SHIELD_RADIUS_PER_LAYER := 1.6

func _draw_holy_shield(charges: int) -> void:
	var t_ms: int = Time.get_ticks_msec()
	var flicker: bool = int(t_ms / 120) % 2 == 0
	var rot: float = float(t_ms) * 0.002
	for layer in range(charges):
		var rb: float = HOLY_SHIELD_BASE_RADIUS + HOLY_SHIELD_RADIUS_PER_LAYER * float(layer)
		_draw_holy_shield_ring(rb, rot + float(layer) * 0.6, flicker)


func _draw_holy_shield_ring(rb: float, rot: float, flicker: bool) -> void:
	var px: float = HOLY_SHIELD_PIXEL
	# 旋转坐标系，逐像素块绘制空心圆环（厚度约 1.4 块）
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	for by in range(-int(rb) - 1, int(rb) + 2):
		for bx in range(-int(rb) - 1, int(rb) + 2):
			var d: float = sqrt(float(bx * bx + by * by))
			# 环厚：rb-1.4 < d < rb+0.3
			if d > rb + 0.3 or d < rb - 1.4:
				continue
			# 环上四档颜色：外圈深 → 中亮 → 高光
			var ring_t: float = (d - (rb - 1.4)) / 1.7  # 0~1，外 → 内
			var col: Color = _holy_shield_color(ring_t, flicker)
			draw_rect(Rect2(bx * px - px * 0.5, by * px - px * 0.5, px, px), col)
	# 4 个旋转高光点（环上 90° 均分）
	for i in range(4):
		var ang: float = float(i) * (TAU * 0.25)
		var hx: float = cos(ang) * rb * px
		var hy: float = sin(ang) * rb * px
		var hi_col: Color = Color("#ffffff") if not flicker else Color("#fffae0")
		draw_rect(Rect2(hx - px * 0.5, hy - px * 0.5, px, px), hi_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 外发光圆晕（双层）
	var glow_r1: float = rb * px * 1.35
	var glow_r2: float = rb * px * 1.05
	var glow_outer: Color = Color(1.0, 0.85, 0.35, 0.18 if flicker else 0.22)
	var glow_inner: Color = Color(1.0, 0.95, 0.6, 0.10 if flicker else 0.14)
	draw_circle(Vector2.ZERO, glow_r1, glow_outer)
	draw_circle(Vector2.ZERO, glow_r2, glow_inner)


func _holy_shield_color(ring_t: float, flicker: bool) -> Color:
	# ring_t: 0=外圈深棕，1=内圈白
	if ring_t < 0.25:
		return Color("#5a4810") if not flicker else Color("#3a3008")
	if ring_t < 0.55:
		return Color("#a87810") if not flicker else Color("#8a6010")
	if ring_t < 0.80:
		return Color("#ffd848") if not flicker else Color("#ffe890")
	return Color("#fff8d8") if not flicker else Color("#ffffff")


# 无下限术式视觉：紫红色双层减速领域圈 + 周期脉冲外晕
func _draw_proximity_slow_aura(aura_r: float) -> void:
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var pulse: float = 0.5 + 0.5 * sin(t * 2.4)
	var inner_a: float = 0.05 + pulse * 0.05
	var ring_a: float = 0.35 + pulse * 0.15
	var aura_color := Color(0.85, 0.25, 0.55)  # 紫红
	# 内填淡色
	draw_circle(Vector2.ZERO, aura_r, Color(aura_color, inner_a))
	# 外环主线
	_draw_closed_ring(Vector2.ZERO, aura_r, 64, Color(aura_color, ring_a), GameConfig.scale_world(2.5))
	# 内环（次圈，给层次感）
	_draw_closed_ring(Vector2.ZERO, aura_r * 0.62, 48, Color(aura_color, ring_a * 0.55), GameConfig.scale_world(1.5))
	# 脉冲外晕（向外扩散同时淡出）
	var ripple_t: float = fmod(t * 0.7, 1.0)
	var ripple_r: float = aura_r * (0.55 + ripple_t * 0.55)
	var ripple_a: float = (1.0 - ripple_t) * 0.28
	_draw_closed_ring(Vector2.ZERO, ripple_r, 56, Color(aura_color, ripple_a), GameConfig.scale_world(1.8))


# 打造关结算后头顶 ↑ 绿色像素箭头（表示属性提升）。
# 由 battle._on_forge_settlement_continue 调用，duration 秒后自动淡出。
func show_forge_buff_arrow(duration: float) -> void:
	_forge_arrow_timer = maxf(0.0, duration)
	_forge_arrow_duration = _forge_arrow_timer
	_forge_arrow_t = 0.0
	queue_redraw()


func _draw_forge_buff_arrow() -> void:
	# alpha 包络：前 0.3s 0→1，最后 0.4s 1→0，中间 hold 1.0
	var elapsed: float = _forge_arrow_duration - _forge_arrow_timer
	var fade_in := 0.3
	var fade_out := 0.4
	var alpha := 1.0
	if elapsed < fade_in:
		alpha = clampf(elapsed / fade_in, 0.0, 1.0)
	elif _forge_arrow_timer < fade_out:
		alpha = clampf(_forge_arrow_timer / fade_out, 0.0, 1.0)
	# 头顶 y 偏移 + 上下浮动（amplitude 4px，period 0.6s）
	var head_y: float = -42.0
	var bob: float = sin(_forge_arrow_t * TAU / 0.6) * 4.0
	var cx: float = 0.0
	var cy: float = head_y + bob
	# 绿色 ↑ 像素箭头：3 行（顶尖 1px + 中部 3px 翼 + 4px 杆），缩放到约 16px 宽 × 18px 高
	# 调色板：亮绿主色 + 深绿描边
	var bright := Color(0.37, 1.0, 0.56, alpha)   # #5eff90
	var outline := Color(0.10, 0.23, 0.13, alpha)  # #1a3a20
	var px := 2.0  # 像素块大小
	# 描边层（外扩 1px）
	_draw_arrow_grid(cx, cy, px, outline, true)
	# 主色层
	_draw_arrow_grid(cx, cy, px, bright, false)


# ↑ 箭头像素网格（9 像素宽 × 11 像素高）。
# outline=true 时画外扩 1px 的描边版本（先画，让主色叠在上面）。
func _draw_arrow_grid(cx: float, cy: float, px: float, color: Color, outline: bool) -> void:
	# 网格定义：每个 (gx, gy) 表示像素单元的相对位置（gy 越小越靠上）
	# 形状：
	#   row -5:        ▓
	#   row -4:       ▓▓▓
	#   row -3:      ▓▓▓▓▓
	#   row -2:     ▓▓ ▓ ▓▓     (V 字开口处用 -2 顶层)
	#   row -1:         ▓
	#   row  0:         ▓
	#   row  1:         ▓
	#   row  2:         ▓
	#   row  3:         ▓
	# 即：箭头三角形 + 主杆
	var arrow_cells := [
		Vector2(0, -5),
		Vector2(-1, -4), Vector2(0, -4), Vector2(1, -4),
		Vector2(-2, -3), Vector2(-1, -3), Vector2(0, -3), Vector2(1, -3), Vector2(2, -3),
		Vector2(-3, -2), Vector2(-2, -2), Vector2(0, -2), Vector2(2, -2), Vector2(3, -2),
		Vector2(0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(0, 3),
	]
	for cell in arrow_cells:
		var gx: float = cell.x
		var gy: float = cell.y
		if outline:
			# 描边层：在每个 cell 外扩 1px 画 8 邻
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					if ox == 0 and oy == 0:
						continue
					var px_x: float = cx + (gx * px) + (ox * px)
					var px_y: float = cy + (gy * px) + (oy * px)
					draw_rect(Rect2(px_x - px * 0.5, px_y - px * 0.5, px, px), color)
		else:
			var px_x: float = cx + gx * px
			var px_y: float = cy + gy * px
			draw_rect(Rect2(px_x - px * 0.5, px_y - px * 0.5, px, px), color)


# sr=56 orbit_shield：绕玩家一圈画 N 面盾。
# 每面盾：圆润盾牌轮廓（4 档蓝调色板 + 中心十字纹章 + 外层 glow）。
const SHIELD_PALETTE := [
	Color("#c0d8ff"),  # 高光
	Color("#6b9dff"),  # 主色
	Color("#2a5cd0"),  # 暗
	Color("#0f2870"),  # 描边
]

func _draw_orbit_shields() -> void:
	var count: int = shield_orbit_count
	if count <= 0:
		return
	var r: float = float(shield_orbit_radius)
	var base_ang: float = float(shield_orbit_angle)
	for i in range(count):
		var a: float = base_ang + TAU * float(i) / float(count)
		var pos: Vector2 = Vector2(cos(a), sin(a)) * r
		_draw_pixel_orbit_shield(pos)


func _draw_pixel_orbit_shield(pos: Vector2) -> void:
	var t_ms: int = Time.get_ticks_msec()
	var flicker: float = 1.0 if (int(t_ms / 90) % 2 == 0) else 0.85
	var glow_col: Color = SHIELD_PALETTE[1]
	glow_col.a = 0.28 * flicker
	# 外层 glow 圆
	draw_circle(pos, GameConfig.scale_world(18.0), glow_col)
	# 盾形：中间圆 + 底部小三角尖
	var r_main: float = GameConfig.scale_world(11.0)
	draw_circle(pos, r_main + 1.0, SHIELD_PALETTE[3])  # 描边
	draw_circle(pos, r_main, SHIELD_PALETTE[1])         # 主色
	draw_circle(pos + Vector2(0.0, -r_main * 0.35), r_main * 0.55, SHIELD_PALETTE[0])  # 顶部高光
	# 中心十字纹章
	var cross_w: float = GameConfig.scale_world(2.0)
	var cross_l: float = GameConfig.scale_world(7.0)
	draw_rect(Rect2(pos.x - cross_w * 0.5, pos.y - cross_l * 0.5, cross_w, cross_l), SHIELD_PALETTE[0])
	draw_rect(Rect2(pos.x - cross_l * 0.5, pos.y - cross_w * 0.5, cross_l, cross_w), SHIELD_PALETTE[0])
