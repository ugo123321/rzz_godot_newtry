extends Node2D
class_name BattleController

const SummonAbilityManagerScript = preload("res://scripts/core/summon_ability_manager.gd")
const SwordOrbitManagerScript = preload("res://scripts/core/sword_orbit_manager.gd")
const AuraOrbitManagerScript = preload("res://scripts/core/aura_orbit_manager.gd")
const ParticleManagerScript = preload("res://scripts/core/particle_manager.gd")
const BloodStainManagerScript = preload("res://scripts/core/blood_stain_manager.gd")
const GroundEffectManagerScript = preload("res://scripts/core/ground_effect_manager.gd")
const LevelOverlayScript = preload("res://scripts/ui/level_overlay.gd")
const CombatAfterimagesScript = preload("res://scripts/ui/combat_afterimages.gd")
const EquipmentDropFxScript = preload("res://scripts/ui/equipment_drop_fx.gd")
const BossIntroPopupScript = preload("res://scripts/ui/boss_intro_popup.gd")
const SoulOrbManagerScript = preload("res://scripts/effects/soul_orb_manager.gd")
const PickupOrbManagerScript = preload("res://scripts/effects/pickup_orb_manager.gd")
const SakuraSystemScript = preload("res://scripts/systems/sakura_system.gd")
const GrassSystemScript = preload("res://scripts/systems/grass_system.gd")
const EnemyArrowScript = preload("res://scripts/entities/enemy_arrow.gd")
const RewardWheelPopupScript = preload("res://scripts/ui/reward_wheel_popup.gd")
const ThemedRewardPopupScene = preload("res://scenes/ui/themed_reward_popup.tscn")
const ForgeSettlementPopupScript = preload("res://scripts/ui/forge_settlement_popup.gd")
const VirtualJoystickScript = preload("res://scripts/ui/virtual_joystick.gd")
const TreeSpawnerScript = preload("res://scripts/systems/tree_spawner.gd")
const PortalSpawnerScript = preload("res://scripts/systems/portal_spawner.gd")
const FieldElementRegistryScript = preload("res://scripts/systems/field_element_registry.gd")
const MonsterNavigatorScript = preload("res://scripts/systems/monster_navigator.gd")
const LevelLayoutLoaderScript = preload("res://scripts/systems/level_layout_loader.gd")
const ArrowBlockScript = preload("res://scripts/entities/arrow_block.gd")
const LockedBlockScript = preload("res://scripts/entities/locked_block.gd")
const FixedPortalScript = preload("res://scripts/entities/fixed_portal.gd")
const ChestNormalScript = preload("res://scripts/entities/chest_normal.gd")
const ChestLockedScript = preload("res://scripts/entities/chest_locked.gd")
const PitBlockScript = preload("res://scripts/entities/pit_block.gd")
const BlockingStoneBlockScript = preload("res://scripts/entities/blocking_stone_block.gd")
const BuildHouseDirectorScript = preload("res://scripts/systems/build_house_director.gd")
const AttrForgeDirectorScript = preload("res://scripts/systems/attr_forge_director.gd")
const WoodDropScript = preload("res://scripts/entities/wood_drop.gd")
const StageTransitionScript = preload("res://scripts/systems/stage_transition.gd")
const PortalTraverseAnimatorScript = preload("res://scripts/systems/portal_traverse_animator.gd")
const ForgePortalScript = preload("res://scripts/entities/forge_portal.gd")
const BattleTreeScript = preload("res://scripts/entities/battle_tree.gd")
const WaterOverlayScript = preload("res://scripts/systems/water_overlay.gd")

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
# wheel 关固定套用的关卡模板编号：模板里中间放固定传送门，玩家触发后弹转盘。
# 该模板由关卡编辑器保存为 res://config/levels/999.json（策划自行放置 fixed_portal）。
const WHEEL_STAGE_LAYOUT := "999"

@export var stage_index := 0

var state := GameState.MENU
var time_scale := 1.0
var pending_stage_clear := false
# boss 关技能石掉落防重发：记录已发过的 stage_index
var _boss_skill_stone_dropped_stage_index := -1

@onready var player: BattlePlayer = $Entities/Player
@onready var monster_container: Node2D = $Entities/Monsters
@onready var projectiles: Node2D = $Entities/Projectiles
@onready var camera: Camera2D = $Camera2D
@onready var dim_overlay: ColorRect = $DimOverlay
@onready var background: ColorRect = $Background
@onready var hud: GameHud = $UI/HUD
@onready var upgrade_popup: UpgradePopup = $UI/UpgradePopup
@onready var intro_label: Label = $UI/IntroLabel

var combat: CombatDirector
var experience: ExperienceManager
var upgrades: UpgradeManager
var spawner: MonsterSpawner
var path_input
var buff_orbs: BuffOrbManager
var abilities: AbilityManager
var summons
var swords
var auras
var damage_overlay: DamageNumbersOverlay
var equipment_drop_fx: EquipmentDropFxOverlay
var soul_orb_manager: SoulOrbManager
var pickup_orb_manager: PickupOrbManager
var afterimages_overlay
var terrain: TerrainBackground
var pause_menu: PauseMenu
var _editor_test_btn: Button  # 编辑器测试模式：停止测试按钮
var fail_animator: StageFailAnimator
var particles
var blood_stains
var ground_effects
var level_overlay
var grass_field
var sakura_field
var reward_wheel_popup
var themed_reward_popup
var _pending_themed_next_index := -1
var _pending_themed_theme := ""
var _pending_reward_stage_index := -1
# 当前正在进行的 wheel 关 stage_index（-1 = 非 wheel 关）。
# wheel 关不再直接弹转盘：改为载入 WHEEL_STAGE_LAYOUT 模板正常进入关卡，
# 玩家走到模板里的固定传送门触发转盘，奖励结束（portal 退出）后据此跳下一关。
var _wheel_stage_index := -1
var tree_spawner
var portal_spawner
var build_house
var attr_forge
var tree_container: Node2D
var portal_container: Node2D
var field_elements: Node  # FieldElementRegistry：放置元素格注册表（箭块/锁定块/宝箱/固定传送门）
var _navigator: Node = null  # MonsterNavigator：怪物 A* 网格寻路（懒创建）
var wood_drops_container: Node2D
var build_house_container: Node2D
var attr_forge_container: Node2D
var _pending_attr_forge_advance := false
var forge_settlement_popup
var _pending_forge_buffs: Array = []
var _pending_forge_rarity := ""
var _pending_forge_totals: Dictionary = {}
var _portal_paused_remaining := -1.0
var _initial_camera_y := 640.0
var _initial_camera_x := 360.0
var _portal_active_pause := false
var _current_chapter_id := -1
# 每第 4 关随机选 demon/angel 主题（idx=3,7,11,15,19,23...；跳过 room_type==reward 的奖励关）。
# 一次开局内同一 stage_index 复用首次随机结果，避免视觉来回切换；start_game/_enter_wait_start/_begin_from_lobby 时清空。
var _themed_stage_overrides: Dictionary = {}
var hit_fx_overlay: Node2D
var under_monster_fx_overlay: Node2D
var above_monster_fx_overlay: Node2D
var stage_transition: StageTransition
var portal_traverse: PortalTraverseAnimator
# 当前活跃的传送门引用 — 抽奖 portal / 打造 portal 触发后保留对象，
# 等 play_exit 完成回调里才 queue_free（中途要 stored_position 当落地点）。
var _active_lottery_portal: Node = null
var _active_forge_portal: Node = null
var _pending_next_forge_portal: Node = null
var _transition_damage_lock := false
var _pending_next_terrain: TerrainBackground = null
var _next_stage_root: Node2D = null
var _pending_next_grass: GrassSystem = null
var _pending_next_tree_container: Node2D = null
var _pending_next_trees: Array = []
var water_overlay: WaterOverlay = null

var stage_intro_timer := 0.0
var _lobby_entry_intro_active := false
var _lobby_intro_phase := ""
var _lobby_intro_timer := 0.0
var _boss_intro_popup: CanvasLayer = null
# 当玩家在"点击开始"等待界面时，世界（地块/草地/樱花/树）已经预先生成好。
# 点击进入 _start_run 时跳过这些重建步骤，避免视觉上的"场景重置"。
var _world_pre_populated := false

const LOBBY_INTRO_FADE_IN := 0.55
const LOBBY_INTRO_HOLD := 0.75
const LOBBY_INTRO_FADE_OUT := 0.55
const LOBBY_INTRO_GAP := 0.25

var shake_mag := 0.0
var shake_dur := 0.0
var shake_timer := 0.0
# iOS Safari 一次触摸会同时派发 touchstart + 合成的 mousedown / mouseup，
# 导致 attr_forge 一次点击落两个方块。touch 事件进来时记一个时间窗口，
# 期间所有 InputEventMouseButton / InputEventMouseMotion 直接丢弃。
# 桌面只有 mouse 没 touch，永远不会进窗口，因此完全不受影响。
const _TOUCH_SWALLOW_WINDOW_MS := 500
var _touch_swallow_until_ms := 0
var _fail_death_player_parent: Node = null
var virtual_joystick: VirtualJoystickScript


func _ready() -> void:
	add_to_group("battle")
	GameConfig.reload()
	combat = CombatDirector.new()
	add_child(combat)
	experience = ExperienceManager.new()
	add_child(experience)
	upgrades = UpgradeManager.new()
	add_child(upgrades)
	spawner = MonsterSpawner.new()
	add_child(spawner)
	path_input = PathInput.new()
	add_child(path_input)
	path_input.setup(self)
	buff_orbs = BuffOrbManager.new()
	buff_orbs.name = "BuffOrbs"
	add_child(buff_orbs)
	buff_orbs.setup(self)
	abilities = AbilityManager.new()
	add_child(abilities)
	abilities.setup(self)
	summons = SummonAbilityManagerScript.new()
	summons.name = "Summons"
	add_child(summons)
	summons.setup(self)
	# Phase 7 sword orbit manager
	swords = SwordOrbitManagerScript.new()
	swords.name = "SwordOrbits"
	add_child(swords)
	swords.setup(self)
	# 环绕玩家的视觉光环（光之守护 / 吸血鬼 / 九命猫）
	auras = AuraOrbitManagerScript.new()
	auras.name = "Auras"
	add_child(auras)
	auras.setup(self)
	damage_overlay = DamageNumbersOverlay.new()
	damage_overlay.name = "DamageNumbers"
	damage_overlay.z_index = 50
	add_child(damage_overlay)
	damage_overlay.setup(combat)
	equipment_drop_fx = EquipmentDropFxScript.new()
	equipment_drop_fx.name = "EquipmentDropFx"
	add_child(equipment_drop_fx)

	soul_orb_manager = SoulOrbManagerScript.new()
	soul_orb_manager.name = "SoulOrbManager"
	add_child(soul_orb_manager)
	soul_orb_manager.setup(self)
	pickup_orb_manager = PickupOrbManagerScript.new()
	pickup_orb_manager.name = "PickupOrbManager"
	add_child(pickup_orb_manager)
	pickup_orb_manager.setup(self)
	afterimages_overlay = CombatAfterimagesScript.new()
	afterimages_overlay.name = "CombatAfterimages"
	afterimages_overlay.z_index = 46
	add_child(afterimages_overlay)
	afterimages_overlay.setup(combat, player)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	$UI.add_child(pause_menu)
	pause_menu.setup(self)
	_setup_editor_test_button()
	fail_animator = StageFailAnimator.new()
	add_child(fail_animator)
	fail_animator.setup(self)
	particles = ParticleManagerScript.new()
	particles.name = "Particles"
	particles.z_index = 40
	add_child(particles)
	blood_stains = BloodStainManagerScript.new()
	blood_stains.name = "BloodStains"
	blood_stains.z_index = -4
	add_child(blood_stains)
	var blood_world_w := float(GameConfig.get_tuning("logical_width", 720))
	var blood_world_h := float(GameConfig.get_tuning("logical_height", 1280))
	blood_stains.configure(blood_world_w, blood_world_h)
	ground_effects = GroundEffectManagerScript.new()
	ground_effects.name = "GroundEffects"
	ground_effects.z_index = -3
	add_child(ground_effects)
	ground_effects.setup(self)
	level_overlay = LevelOverlayScript.new()
	level_overlay.name = "LevelOverlay"
	level_overlay.z_index = 60
	$UI.add_child(level_overlay)
	level_overlay.setup(self)
	reward_wheel_popup = RewardWheelPopupScript.new()
	reward_wheel_popup.name = "RewardWheelPopup"
	reward_wheel_popup.z_index = 110
	$UI.add_child(reward_wheel_popup)
	reward_wheel_popup.setup(self)
	reward_wheel_popup.reward_finished.connect(_on_reward_wheel_finished)
	themed_reward_popup = ThemedRewardPopupScene.instantiate()
	themed_reward_popup.name = "ThemedRewardPopup"
	themed_reward_popup.z_index = 115
	$UI.add_child(themed_reward_popup)
	themed_reward_popup.setup(self)
	themed_reward_popup.reward_resolved.connect(_on_themed_reward_resolved)
	forge_settlement_popup = ForgeSettlementPopupScript.new()
	forge_settlement_popup.name = "ForgeSettlementPopup"
	forge_settlement_popup.z_index = 115
	$UI.add_child(forge_settlement_popup)
	forge_settlement_popup.setup(self)
	forge_settlement_popup.continue_pressed.connect(_on_forge_settlement_continue)
	tree_container = Node2D.new()
	tree_container.name = "Trees"
	tree_container.z_index = 0
	$Entities.add_child(tree_container)
	wood_drops_container = Node2D.new()
	wood_drops_container.name = "WoodDrops"
	wood_drops_container.z_index = 3
	$Entities.add_child(wood_drops_container)
	portal_container = Node2D.new()
	portal_container.name = "Portals"
	portal_container.z_index = -1  # 沉到怪物/玩家(z0)之下：传送门是"踩上去"的地面元素，不应盖住单位
	$Entities.add_child(portal_container)
	field_elements = FieldElementRegistryScript.new()
	$Entities.add_child(field_elements)  # name "FieldElements" 由 _ready 设；z=-1（沉到怪物/玩家之下，地形/草地之上）
	if field_elements.has_signal("blocking_cells_changed"):
		field_elements.blocking_cells_changed.connect(_invalidate_nav)
	build_house_container = Node2D.new()
	build_house_container.name = "BuildHouse"
	build_house_container.z_index = 30
	build_house_container.visible = false
	add_child(build_house_container)
	attr_forge_container = Node2D.new()
	attr_forge_container.name = "AttrForge"
	attr_forge_container.z_index = 30
	attr_forge_container.visible = false
	add_child(attr_forge_container)
	tree_spawner = TreeSpawnerScript.new()
	tree_spawner.name = "TreeSpawner"
	add_child(tree_spawner)
	portal_spawner = PortalSpawnerScript.new()
	portal_spawner.name = "PortalSpawner"
	add_child(portal_spawner)
	build_house = BuildHouseDirectorScript.new()
	build_house.name = "BuildHouseDirector"
	build_house_container.add_child(build_house)
	attr_forge = AttrForgeDirectorScript.new()
	attr_forge.name = "AttrForgeDirector"
	attr_forge_container.add_child(attr_forge)
	virtual_joystick = VirtualJoystickScript.new()
	virtual_joystick.name = "VirtualJoystick"
	$UI.add_child(virtual_joystick)
	terrain = TerrainBackground.new()
	terrain.name = "Terrain"
	terrain.z_index = -5
	add_child(terrain)
	grass_field = GrassSystemScript.new()
	grass_field.name = "GrassField"
	grass_field.z_index = -4
	add_child(grass_field)
	sakura_field = SakuraSystemScript.new()
	sakura_field.name = "SakuraField"
	sakura_field.z_index = -2
	add_child(sakura_field)
	hit_fx_overlay = Node2D.new()
	hit_fx_overlay.name = "HitFxOverlay"
	hit_fx_overlay.z_index = 6
	add_child(hit_fx_overlay)
	hit_fx_overlay.draw.connect(_draw_hit_fx_overlay)
	under_monster_fx_overlay = Node2D.new()
	under_monster_fx_overlay.name = "UnderMonsterFxOverlay"
	under_monster_fx_overlay.z_index = -1
	add_child(under_monster_fx_overlay)
	under_monster_fx_overlay.draw.connect(_draw_under_monster_fx_overlay)
	above_monster_fx_overlay = Node2D.new()
	above_monster_fx_overlay.name = "AboveMonsterFxOverlay"
	above_monster_fx_overlay.z_index = 5
	add_child(above_monster_fx_overlay)
	above_monster_fx_overlay.draw.connect(_draw_above_monster_fx_overlay)
	stage_transition = StageTransitionScript.new()
	stage_transition.name = "StageTransition"
	add_child(stage_transition)
	portal_traverse = PortalTraverseAnimatorScript.new()
	portal_traverse.name = "PortalTraverseAnimator"
	add_child(portal_traverse)
	water_overlay = WaterOverlayScript.new()
	water_overlay.name = "WaterOverlay"
	add_child(water_overlay)
	water_overlay.setup(self)
	terrain.setup_for_stage(0, _get_safe_zone())
	water_overlay.refresh_from_terrain()
	_sync_background_layer()
	# 怪物按脚 Y 排序：影子烘焙在角色帧贴图里(与身体同帧同 z)，不开 y-sort 时按生成顺序绘制，
	# 后生成的怪整帧(含脚下影子)会盖住先生成的怪。开 y_sort 后脚下方的怪画在更上层，影子不再错盖。
	monster_container.y_sort_enabled = true
	_refresh_stage_ambience()
	upgrade_popup.setup(self, upgrades)
	upgrade_popup.upgrade_picked.connect(_on_upgrade_picked)
	PixelUi.apply_ui_font_tree($UI)
	combat.resolve_finished.connect(_on_resolve_finished)
	EventBus.monster_killed.connect(_on_monster_killed)
	_setup_viewport()
	player.apply_config()
	hud.bind_player(player)
	intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial_camera_x = camera.position.x
	_initial_camera_y = camera.position.y
	if LobbyState.consume_battle_launch():
		_begin_from_lobby()
	else:
		_enter_wait_start()


func _setup_viewport() -> void:
	var w := int(GameConfig.get_tuning("logical_width", 720))
	var h := int(GameConfig.get_tuning("logical_height", 1280))
	dim_overlay.size = Vector2(w, h)
	dim_overlay.visible = false
	dim_overlay.z_index = -1  # 让暗罩只覆盖地形/草/血迹/sakura 等装饰层；怪物/玩家/水 overlay 在 z=0 不受影响
	var zoom := maxf(1.0, round(float(GameConfig.get_tuning("camera_zoom", 1.0))))
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2(w * 0.5, h * 0.5)
	player.global_position = Vector2(w * 0.5, h * 0.58)
	player.home_position = player.global_position


func start_game() -> void:
	stage_index = 0
	_current_chapter_id = -1
	_themed_stage_overrides.clear()
	experience.reset()
	player.reset_for_new_run()
	if fail_animator:
		fail_animator.reset()
	if level_overlay:
		level_overlay.reset_all()
	if sakura_field:
		sakura_field.stop_field()
	if blood_stains:
		blood_stains.clear()
	if equipment_drop_fx:
		equipment_drop_fx.clear()
	if soul_orb_manager:
		soul_orb_manager.clear()
	if pickup_orb_manager:
		pickup_orb_manager.clear()
	_clear_projectiles()
	state = GameState.MENU
	hud.show_message(LanguageManager.tr_ui("UI_BATTLE_TAP_START"), 999.0)
	intro_label.text = LanguageManager.tr_ui("UI_BATTLE_INTRO")


func _enter_wait_start() -> void:
	stage_index = 0
	_current_chapter_id = -1
	_themed_stage_overrides.clear()
	experience.reset()
	player.reset_for_new_run()
	LobbyState.reset_wood()
	LobbyState.reset_chapter_tower(0)
	if fail_animator:
		fail_animator.reset()
	if level_overlay:
		level_overlay.reset_all()
	if sakura_field:
		sakura_field.stop_field()
	if blood_stains:
		blood_stains.clear()
	if equipment_drop_fx:
		equipment_drop_fx.clear()
	if soul_orb_manager:
		soul_orb_manager.clear()
	if pickup_orb_manager:
		pickup_orb_manager.clear()
	if tree_spawner:
		if get_stage_theme(stage_index) == "":
			tree_spawner.begin(self)
		else:
			tree_spawner.reset()
	if portal_spawner:
		portal_spawner.reset()
	_clear_projectiles()
	# Pre-populate the battle background so the player sees the actual scene
	_apply_stage_meta(false)
	if terrain:
		terrain.setup_for_stage(stage_index, _get_safe_zone())
	if water_overlay:
		water_overlay.refresh_from_terrain()
	_invalidate_nav()
	_sync_background_layer()
	_refresh_stage_ambience()
	intro_label.visible = false
	hud.hide_message()
	hud.show_click_to_start()
	_world_pre_populated = true
	state = GameState.WAIT_START


func _exit_wait_start_and_begin() -> void:
	hud.hide_click_to_start()
	_start_run()


func _begin_from_lobby() -> void:
	stage_index = clampi(LobbyState.stage_index, 0, maxi(0, GameConfig.stages.size() - 1))
	_current_chapter_id = -1
	_themed_stage_overrides.clear()
	experience.reset()
	player.reset_for_new_run()
	# 技能石：技能部分作为升级奖励一次性授予（属性部分由 _rebuild_upgrades 处理）
	player.apply_equipped_skill_stones()
	if fail_animator:
		fail_animator.reset()
	if level_overlay:
		level_overlay.reset_all()
	if sakura_field:
		sakura_field.stop_field()
	if blood_stains:
		blood_stains.clear()
	if equipment_drop_fx:
		equipment_drop_fx.clear()
	if soul_orb_manager:
		soul_orb_manager.clear()
	if pickup_orb_manager:
		pickup_orb_manager.clear()
	_clear_projectiles()
	intro_label.visible = false
	hud.hide_message()
	_start_run()
	call_deferred("_start_lobby_battle_intro")


func _start_lobby_battle_intro() -> void:
	_lobby_entry_intro_active = true
	state = GameState.STAGE_INTRO
	intro_label.text = LanguageManager.tr_ui("UI_BATTLE_BATTLE_START")
	intro_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	intro_label.visible = true
	PixelUi.apply_ui_font(intro_label)
	intro_label.add_theme_font_size_override("font_size", 32)
	intro_label.add_theme_color_override("font_color", Color("#ffe9a8"))
	_lobby_intro_phase = "fade_in"
	_lobby_intro_timer = LOBBY_INTRO_FADE_IN


func _update_lobby_entry_intro(delta: float) -> void:
	if not _lobby_entry_intro_active:
		return
	_lobby_intro_timer -= delta
	match _lobby_intro_phase:
		"fade_in":
			var t := 1.0 - clampf(_lobby_intro_timer / LOBBY_INTRO_FADE_IN, 0.0, 1.0)
			intro_label.modulate.a = t
			if _lobby_intro_timer <= 0.0:
				_lobby_intro_phase = "hold"
				_lobby_intro_timer = LOBBY_INTRO_HOLD
		"hold":
			intro_label.modulate.a = 1.0
			if _lobby_intro_timer <= 0.0:
				_lobby_intro_phase = "fade_out"
				_lobby_intro_timer = LOBBY_INTRO_FADE_OUT
		"fade_out":
			var t := clampf(_lobby_intro_timer / LOBBY_INTRO_FADE_OUT, 0.0, 1.0)
			intro_label.modulate.a = t
			if _lobby_intro_timer <= 0.0:
				intro_label.visible = false
				intro_label.modulate.a = 0.0
				_lobby_intro_phase = "wait"
				_lobby_intro_timer = LOBBY_INTRO_GAP
		"wait":
			if _lobby_intro_timer <= 0.0:
				_finish_lobby_entry_intro()


func _finish_lobby_entry_intro() -> void:
	_lobby_entry_intro_active = false
	_lobby_intro_phase = ""
	_trigger_lobby_start_upgrade()


## Boss 出场原画特写（屏幕变暗 → 长条原画从左滑入正中 + 下方白字 boss 名 → 滑出 → 恢复）。
## 无特写映射的 boss（如 centipede）→ 返回 false，调用方按原 wave_delay 生成。
func start_boss_intro(boss_id: String) -> bool:
	if _boss_intro_popup == null:
		_boss_intro_popup = BossIntroPopupScript.new()
		add_child(_boss_intro_popup)
	return _boss_intro_popup.play(boss_id)


func _trigger_lobby_start_upgrade() -> void:
	if experience == null:
		state = GameState.PLAYING
		return
	state = GameState.PLAYING
	# 先发制人卡门控：未解锁 → 直接跳过开局升级，进 PLAYING
	# 同时 per-run 保护，已给过就不重复
	if LobbyState and (not LobbyState.has_unlock("first_reward") or LobbyState._first_reward_given_this_run):
		return
	if LobbyState:
		LobbyState._first_reward_given_this_run = true
	experience.pending_level_ups += 1
	experience.try_trigger_upgrade(self)


func _start_run() -> void:
	pending_stage_clear = false
	var skip_world_setup := _world_pre_populated
	_world_pre_populated = false
	if fail_animator:
		fail_animator.reset()
	player.begin_stage()
	_clear_stage_transition_presentation(stage_index > 0)
	if level_overlay:
		level_overlay.reset_all()
	if sakura_field:
		sakura_field.stop_field()
	if _try_enter_reward_room(stage_index):
		intro_label.visible = false
		hud.hide_message()
		return
	spawner.spawn_stage(stage_index, self)
	if not skip_world_setup:
		if terrain:
			terrain.setup_for_stage(stage_index, _get_safe_zone())
		if water_overlay:
			water_overlay.refresh_from_terrain()
		_sync_background_layer()
		_refresh_stage_ambience()
	_apply_stage_meta(true)
	# 先重置 tree_spawner（清上一关残留树），再载入编辑器布局——
	# 顺序不能反：begin()/reset() 会把布局刚 register_tree 进来的树 queue_free 掉，
	# 那正是"编辑器里放的树进测试就消失"的根因。
	if not skip_world_setup and tree_spawner:
		if get_stage_theme(stage_index) == "":
			tree_spawner.begin(self)
		else:
			tree_spawner.reset()
	# 关卡编辑器布局：若该关配置了 layout_number，载入对应 res://config/levels/<编号>.json 放置元素/地块。
	_apply_stage_layout_if_any(stage_index)
	_invalidate_nav()
	if portal_spawner:
		portal_spawner.begin()
	state = GameState.PLAYING
	intro_label.visible = false
	hud.hide_message()
	if experience:
		EventBus.exp_changed.emit(experience.level, experience.exp, experience.exp_to_next)
	EventBus.stage_started.emit(stage_index)


func _enter_build_house() -> void:
	state = GameState.BUILD_HOUSE
	# 清空残留战斗特效（伤害数字、残影、粒子、命中 fx、投射物、地表 fx 等）
	_clear_stage_transition_presentation(true)
	# Hide combat entities
	monster_container.visible = false
	projectiles.visible = false
	if tree_container:
		tree_container.visible = false
	if portal_container:
		portal_container.visible = false
	if wood_drops_container:
		wood_drops_container.visible = false
	player.visible = false
	if terrain:
		terrain.visible = false
	if grass_field:
		grass_field.visible = false
	if sakura_field:
		sakura_field.visible = false
	if background:
		background.visible = false
	build_house_container.visible = true
	var chapter := GameConfig.get_chapter_for_stage(stage_index)
	var chapter_id := int(chapter.get("chapter_id", 1))
	var chapter_target: float = float(chapter.get("chapter_target_height_m", 200))
	LobbyState.ensure_chapter_tower(chapter_id)
	build_house.begin(
		self,
		chapter_target,
		LobbyState.chapter_tower_height,
		LobbyState.chapter_tower_blocks.duplicate(true)
	)


func on_build_house_phase_done(height_m: float, blocks: Array) -> void:
	state = GameState.BUILD_HOUSE_DONE
	# Persist tower state into LobbyState
	LobbyState.save_chapter_tower(height_m, blocks)
	var chapter := GameConfig.get_chapter_for_stage(stage_index)
	var chapter_target: float = float(chapter.get("chapter_target_height_m", 200))
	var chapter_id := int(chapter.get("chapter_id", 1))
	if height_m >= chapter_target:
		_announce_chapter_complete(chapter_id, height_m, chapter_target)
		return
	# Not done — check if there's a next stage in this chapter
	var next_idx := stage_index + 1
	var has_next := next_idx < GameConfig.stages.size()
	var next_in_same_chapter := false
	if has_next:
		var next_stage := GameConfig.get_stage(next_idx)
		next_in_same_chapter = int(next_stage.get("chapter_id", -1)) == chapter_id
	if not next_in_same_chapter:
		# Last stage of chapter, target not reached → chapter failed
		_announce_chapter_fail(chapter_id, height_m, chapter_target)
		return
	# Advance to next stage in chapter (carry tower over)
	if level_overlay:
		level_overlay.show_phase_fade(
			LanguageManager.tr_ui("UI_BATTLE_NEXT_STAGE"),
			LanguageManager.tr_ui("UI_BATTLE_BUILT_FMT") % [height_m, int(chapter_target)],
			Callable(self, "_advance_after_build"),
			0.55, 0.6, 0.55
		)


func _announce_chapter_complete(chapter_id: int, height_m: float, target_m: float) -> void:
	if level_overlay:
		level_overlay.show_phase_fade(
			LanguageManager.tr_ui("UI_BATTLE_CHAPTER_CLEARED_FMT") % chapter_id,
			LanguageManager.tr_ui("UI_BATTLE_TOWER_FMT") % [height_m, int(target_m)],
			Callable(self, "_back_to_menu_after_chapter"),
			0.8, 1.5, 0.8
		)


func _announce_chapter_fail(chapter_id: int, height_m: float, target_m: float) -> void:
	if level_overlay:
		level_overlay.show_phase_fade(
			LanguageManager.tr_ui("UI_BATTLE_CHAPTER_FAILED_FMT") % chapter_id,
			LanguageManager.tr_ui("UI_BATTLE_TOWER_FMT") % [height_m, int(target_m)],
			Callable(self, "_back_to_menu_after_chapter"),
			0.8, 1.5, 0.8
		)


func _back_to_menu_after_chapter() -> void:
	_exit_build_house()
	LobbyState.reset_wood()
	LobbyState.reset_chapter_tower(0)
	_enter_wait_start()


func _exit_build_house() -> void:
	build_house_container.visible = false
	build_house.reset()
	monster_container.visible = true
	projectiles.visible = true
	if tree_container:
		tree_container.visible = true
	if portal_container:
		portal_container.visible = true
	if wood_drops_container:
		wood_drops_container.visible = true
	player.visible = true
	if terrain:
		terrain.visible = true
	if grass_field:
		grass_field.visible = true
	if sakura_field:
		sakura_field.visible = true
	if background:
		background.visible = true
	# Restore camera
	camera.global_position = Vector2(_initial_camera_x, _initial_camera_y)
	# All wood consumed during build
	LobbyState.reset_wood()


# === 属性打造关（attr_forge）===
# 新流程（v3，传送门版）：
#   1. _try_enter_reward_room 检测 attr_forge → 调 _begin_forge_stage()
#   2. _begin_forge_stage：hud 提示 → 等 0.5s（让玩家看到自己站在门上）→ portal_traverse.play_enter
#   3. 中点回调 _on_forge_enter_midpoint：state=ATTR_FORGE + attr_forge.begin + portal 隐藏
#   4. 10 块落完 → on_attr_forge_phase_done：评品质 → attr_forge.reset → portal 显示 → play_exit
#   5. 退出回调 _on_forge_exit_complete：portal 销毁 → 弹结算 popup
#   6. 玩家点继续 → _on_forge_settlement_continue：apply buff + 头顶箭头 + 弹 3 选 1
#   7. 选完升级卡 → _advance_after_attr_forge：await 1.6s 等箭头淡完 → 跳下一关
#
# 不再隐藏战斗实体（场景已是紫色专属场景）。_enter_attr_forge / _exit_attr_forge 只切 state。


func _begin_forge_stage() -> void:
	# REBASE 完成后立即被 _try_enter_reward_room 调用。
	# 此刻玩家已落地正好在 ForgePortal 上 (_active_forge_portal.stored_position)。
	state = GameState.STAGE_TRANSITION
	hud.show_message(LanguageManager.tr_ui("UI_BATTLE_FORGE_INTRO"), 1.0)
	# 等 0.5s 让玩家感受"我落在了门上"的瞬间
	await get_tree().create_timer(0.5).timeout
	if _active_forge_portal == null or not is_instance_valid(_active_forge_portal):
		# 容错：portal 丢失，直接走旧的 _enter_attr_forge 路径
		push_warning("_begin_forge_stage: _active_forge_portal missing, fallback to direct enter")
		_enter_attr_forge()
		return
	if portal_traverse == null:
		# 容错：动画器缺失，直接进入
		_enter_attr_forge()
		return
	portal_traverse.play_enter(self, _active_forge_portal.stored_position, Callable(self, "_on_forge_enter_midpoint"))


func _on_forge_enter_midpoint() -> void:
	# 黑色 phase_fade 中段（屏幕全黑）：此刻安全切场景。
	_enter_attr_forge()
	# 把门视觉藏起来（打造小游戏期间不显示门）
	if _active_forge_portal and is_instance_valid(_active_forge_portal):
		_active_forge_portal.visible = false


func _enter_attr_forge() -> void:
	# v3：场景已经是打造关专属场景（紫色地面 + 中心门 + 无树无草），
	# 不再隐藏战斗实体（怪物在 attr_forge 关本来就 0 怪 + 没有 portal_spawner 输出）。
	# 只切 state 并启动 attr_forge_director；摄像机由 attr_forge_director._update_camera 接管。
	state = GameState.ATTR_FORGE
	_clear_stage_transition_presentation(true)
	attr_forge_container.visible = true
	attr_forge.begin(self)


func _exit_attr_forge() -> void:
	# v3：不再恢复战斗实体 visible（它们本来就一直可见 — attr_forge 关怪物本就是 0）。
	# attr_forge.reset() 会把相机平滑拉回 _initial_camera_y，让玩家从门长出时画面对齐。
	attr_forge_container.visible = false
	if attr_forge:
		attr_forge.reset()
	# 强制把相机拉回标准位（attr_forge_director 跟随塔顶时挪过相机）
	if camera:
		camera.global_position = Vector2(_initial_camera_x, _initial_camera_y)


# 由 AttrForgeDirector 在 10 块落完 + 沉降稳定后回调（v3：经 portal_traverse.play_exit 退出）。
# 流程：评品质 → 黑色 fade 覆盖相机回正 → 中点 _start_forge_exit_sequence → play_exit → 弹结算 popup
func on_attr_forge_phase_done(surviving_buffs: Array) -> void:
	state = GameState.ATTR_FORGE_DONE
	var stacked := surviving_buffs.size()
	var rarity := _rarity_for_stacked_count(stacked)
	EventBus.forge_session_complete.emit(rarity, stacked)
	# 暂存 — 等结算面板「继续」回调时再 commit + 弹升级
	_pending_forge_buffs = surviving_buffs
	_pending_forge_rarity = rarity
	_pending_forge_totals = _aggregate_forge_buffs(surviving_buffs)
	# 黑色 phase_fade 覆盖相机从塔顶回正的瞬间；中点跑场景切换 + play_exit
	if level_overlay:
		level_overlay.show_phase_fade("", "", Callable(self, "_start_forge_exit_sequence"), 0.18, 0.0, 0.18)
	else:
		_start_forge_exit_sequence()


func _start_forge_exit_sequence() -> void:
	# 黑色全屏遮罩期间：清打造小游戏 + 相机回正 + 重新显示门
	_exit_attr_forge()
	if _active_forge_portal and is_instance_valid(_active_forge_portal):
		_active_forge_portal.visible = true
	# 异常兜底：portal_traverse / popup 缺失时直接走旧的「直接弹结算」路径
	if portal_traverse == null or _active_forge_portal == null or not is_instance_valid(_active_forge_portal):
		if forge_settlement_popup:
			forge_settlement_popup.show_for(_pending_forge_rarity, _pending_forge_buffs.size(), _pending_forge_totals)
		else:
			_on_forge_settlement_continue()
		return
	portal_traverse.play_exit(self, _active_forge_portal.stored_position, Callable(self, "_on_forge_exit_complete"))


func _on_forge_exit_complete() -> void:
	# play_exit 完成（玩家已落到门正下方）：销毁门，弹结算 popup
	if _active_forge_portal and is_instance_valid(_active_forge_portal):
		_active_forge_portal.queue_free()
	_active_forge_portal = null
	if forge_settlement_popup == null:
		_on_forge_settlement_continue()
		return
	forge_settlement_popup.show_for(_pending_forge_rarity, _pending_forge_buffs.size(), _pending_forge_totals)


# 把 surviving_buffs 按 name_cn 聚合成 {name_cn: total_delta} 字典（结算面板显示用）。
func _aggregate_forge_buffs(buffs: Array) -> Dictionary:
	var totals: Dictionary = {}
	for b in buffs:
		var n := str(b.get("name_cn", ""))
		if n.is_empty():
			continue
		var d: float = float(b.get("delta", 0.0))
		totals[n] = float(totals.get(n, 0.0)) + d
	return totals


# 结算面板「继续」回调：把所有暂存的 buff 一次性 apply 到 player，然后走原 3 选 1 流程。
func _on_forge_settlement_continue() -> void:
	if player != null:
		for b in _pending_forge_buffs:
			var idx: int = int(b.get("buff_idx", -1))
			if idx >= 0:
				player.apply_forge_buff(idx)
		# 头顶绿色 ↑ 箭头：1.8s，玩家在选 3 选 1 升级卡时也能看到
		if player.has_method("show_forge_buff_arrow"):
			player.show_forge_buff_arrow(1.8)
	var rarity: String = _pending_forge_rarity
	# 清空暂存
	_pending_forge_buffs = []
	_pending_forge_rarity = ""
	_pending_forge_totals = {}
	# 弹 3 选 1
	if upgrades == null or player == null or upgrade_popup == null:
		_advance_after_attr_forge()
		return
	_pending_attr_forge_advance = true
	state = GameState.LEVEL_UP
	upgrades.generate_choices_with_rarity(player, rarity)
	upgrade_popup.show_popup()
	upgrade_popup.move_to_front()
	if hud:
		hud.show_message(LanguageManager.tr_ui("UI_BATTLE_ATTR_UP"), 1.6)


func _rarity_for_stacked_count(stacked: int) -> String:
	if stacked <= 0:
		return "white"
	if stacked <= 3:
		return "white"
	if stacked <= 6:
		return "blue"
	if stacked <= 9:
		return "purple"
	return "orange"


func _rarity_zh(rarity: String) -> String:
	match rarity:
		"white":
			return "白"
		"blue":
			return "蓝"
		"purple":
			return "紫"
		"orange":
			return "橙"
		_:
			return rarity


func _advance_after_attr_forge() -> void:
	_pending_attr_forge_advance = false
	EventBus.stage_cleared.emit(stage_index)
	# 给头顶 ↑ 箭头留一小段尾巴时间（结算 popup → 选 3 选 1 升级卡期间箭头已经飘了好几秒，
	# 这里 0.5s 足够剩余 alpha 收尾，再长玩家会觉得卡顿）。
	await get_tree().create_timer(0.5).timeout
	# 走标准 _advance_to_next_stage 流程（含主题关 popup / stage_transition）
	_advance_to_next_stage()


func _advance_after_build() -> void:
	_exit_build_house()
	EventBus.stage_cleared.emit(stage_index)
	stage_index += 1
	if stage_index >= GameConfig.stages.size():
		_clear_stage_transition_presentation(true)
		state = GameState.COMPLETE
		if level_overlay:
			level_overlay.show_game_complete()
		hud.hide_message()
		return
	if _try_enter_reward_room(stage_index):
		return
	_clear_stage_transition_presentation(stage_index > 0)
	spawner.spawn_stage(stage_index, self)
	_apply_stage_meta(false)
	if tree_spawner:
		if get_stage_theme(stage_index) == "":
			tree_spawner.begin(self)
		else:
			tree_spawner.reset()
	_apply_stage_layout_if_any(stage_index)
	_invalidate_nav()
	if portal_spawner:
		portal_spawner.begin()
	state = GameState.PLAYING
	EventBus.stage_started.emit(stage_index)


func _fail_back_to_main() -> void:
	_exit_build_house()
	LobbyState.reset_wood()
	LobbyState.reset_chapter_tower(0)
	_enter_wait_start()


# Trees / wood / portal helpers exposed to entities
func get_active_trees() -> Array:
	if tree_spawner == null:
		return []
	return tree_spawner.get_active_trees()


func get_combat_targets() -> Array:
	# 斩击/划线命中：包含树（树可被斩击）
	var targets := spawner.get_active_monsters()
	for t in get_active_trees():
		targets.append(t)
	return targets


func get_ability_targets() -> Array:
	# 普攻/技能/召唤/球的锁定与命中：只含怪物，树不参与
	return spawner.get_active_monsters()


func is_blocked_by_tree(pos: Vector2) -> bool:
	for t in get_active_trees():
		if pos.distance_to(t.global_position) < t.get_block_radius():
			return true
	return false


# 怪物被夹住时的脱困推力方向：把所有"正在阻挡移动"的来源（树 + 地形墙 + 放置块元素）
# 的反向推力相加并归一。返回 ZERO 表示无推力来源。
# 单位推力来源半径：树 = get_block_radius()；地块墙/块元素 = 半格 20（与 is_move_blocked_radius 的 BLOCK_BODY_RADIUS 一致）。
func get_monster_escape_dir(from_pos: Vector2, mover_radius: float) -> Vector2:
	var push := Vector2.ZERO
	# 树
	for t in get_active_trees():
		if not is_instance_valid(t):
			continue
		var to_self: Vector2 = from_pos - t.global_position
		var d: float = to_self.length()
		if d <= 0.0001:
			push += Vector2(1.0, 0.0)
			continue
		var r: float = t.get_block_radius() + mover_radius
		if d < r + 8.0:
			var weight: float = 1.0 - clampf(d / (r + 8.0), 0.0, 1.0)
			push += to_self / d * (0.4 + weight)
	# 放置块元素（锁定块/箭块/阻挡石实体等，move-blocking）
	if field_elements and field_elements.has_method("get_move_blocking_entities"):
		const BLOCK_R := 20.0
		for e in field_elements.get_move_blocking_entities():
			if not is_instance_valid(e):
				continue
			var to_self2: Vector2 = from_pos - e.global_position
			var d2: float = to_self2.length()
			if d2 <= 0.0001:
				push += Vector2(-1.0, 0.0)
				continue
			var r2: float = BLOCK_R + mover_radius
			if d2 < r2 + 8.0:
				var weight2: float = 1.0 - clampf(d2 / (r2 + 8.0), 0.0, 1.0)
				push += to_self2 / d2 * (0.4 + weight2)
	# 地形墙（深坑/阻挡石格）：把格中心当半径 20 的阻挡圆
	if terrain and terrain.has_method("is_blocking_for_movement"):
		const TS := 40
		const BR := 20.0
		var cc := int(from_pos.x / TS)
		var cr := int(from_pos.y / TS)
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var nc := cc + dc
				var nr := cr + dr
				if not terrain.is_blocking_for_movement(nc, nr):
					continue
				var center := Vector2(nc * TS + TS * 0.5, nr * TS + TS * 0.5)
				var to_self3: Vector2 = from_pos - center
				var d3: float = to_self3.length()
				if d3 <= 0.0001:
					push += Vector2(-1.0, 0.0)
					continue
				var r3: float = BR + mover_radius
				if d3 < r3 + 8.0:
					var weight3: float = 1.0 - clampf(d3 / (r3 + 8.0), 0.0, 1.0)
					push += to_self3 / d3 * (0.4 + weight3)
	if push == Vector2.ZERO:
		return Vector2.ZERO
	return push.normalized()


# 子弹/投掷物/视线是否在 world_pos 处被地形（阻挡石）或放置元素（箭块/锁定块未解锁）阻挡。
# 深坑不在此列——子弹从深坑上方飞过，视线也穿过深坑（玩家可隔深坑攻击敌人）。
func is_bullet_blocked_at(world_pos: Vector2) -> bool:
	if terrain and terrain.has_method("is_blocking_for_bullet"):
		var ts: int = TerrainBackground.TILE_SIZE
		var col := int(world_pos.x / ts)
		var row := int(world_pos.y / ts)
		if terrain.is_blocking_for_bullet(col, row):
			return true
	if field_elements and field_elements.has_method("has_bullet_blocking_at"):
		var ts2: int = TerrainBackground.TILE_SIZE
		var col := int(world_pos.x / ts2)
		var row := int(world_pos.y / ts2)
		if field_elements.has_bullet_blocking_at(col, row):
			return true
	return false


# 玩家/怪物移动是否在 world_pos 处被阻挡石/深坑/未解锁锁定块/箭块挡住。
# 用半径版（块体半径 20 + mover 半径），避免身体视觉重叠进块里。
func is_move_blocked_at(world_pos: Vector2, mover_radius: float = 20.0) -> bool:
	if terrain and terrain.has_method("is_blocking_for_movement"):
		var ts: int = TerrainBackground.TILE_SIZE
		var col := int(world_pos.x / ts)
		var row := int(world_pos.y / ts)
		if terrain.is_blocking_for_movement(col, row):
			return true
	if field_elements and field_elements.has_method("is_move_blocked_radius"):
		if field_elements.is_move_blocked_radius(world_pos, mover_radius):
			return true
	return false


func get_monster_navigator() -> Node:
	if _navigator == null:
		_navigator = MonsterNavigatorScript.new()
		add_child(_navigator)
		_navigator.configure(terrain, field_elements)
	return _navigator


func _invalidate_nav() -> void:
	if _navigator != null and _navigator.has_method("mark_dirty"):
		_navigator.mark_dirty()


func _nudge_player_out_of_trees() -> void:
	if player == null:
		return
	var pos: Vector2 = player.global_position
	for t in get_active_trees():
		var d: float = pos.distance_to(t.global_position)
		var r: float = t.get_block_radius() + 4.0
		if d < r and d > 0.0001:
			var push_dir: Vector2 = (pos - t.global_position).normalized()
			pos = t.global_position + push_dir * r
		elif d <= 0.0001:
			pos = t.global_position + Vector2(r, 0.0)
	if pos != player.global_position:
		player.global_position = pos
		player.home_position = pos


func spawn_wood_drop(pos: Vector2, amount: int) -> void:
	if wood_drops_container == null:
		return
	# Split into multiple smaller drops for visual flair
	var drops := mini(3, maxi(1, int(round(amount / 8.0))))
	var per := maxi(1, int(round(float(amount) / float(drops))))
	for i in range(drops):
		var d = WoodDropScript.new()
		wood_drops_container.add_child(d)
		var jitter := Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		d.setup(pos + jitter, per)


func spawn_wood_popup(pos: Vector2, amount: int) -> void:
	if combat:
		combat.spawn_damage_number(pos + Vector2(0.0, -16.0), amount, false, true, Color("#c08a52"))


func on_tree_killed(tree_node: Node) -> void:
	# 不立即 queue_free —— BattleTree 内部播放倒下动画并在动画结束时自行 queue_free()。
	# tree_spawner 会等所有实例真正释放后再补刷一波。
	pass


func on_portal_entered(portal_node: Node) -> void:
	# v3：玩家触碰抽奖传送门 → 小跳跃进入 + 黑色 phase_fade + 弹转盘 popup。
	# portal 不立即销毁，保留 stored_position 供 play_exit 用（玩家落回门正下方原地）。
	_portal_active_pause = true
	if portal_spawner:
		portal_spawner.stop()
	_active_lottery_portal = portal_node
	state = GameState.STAGE_TRANSITION  # 屏蔽输入直到 play_enter 中点切到 REWARD_ROOM
	_pending_reward_stage_index = -2  # sentinel: portal-driven
	# 容错：portal_traverse 或 portal 缺失时退化为旧的"原地弹 popup"
	if portal_traverse == null or portal_node == null:
		state = GameState.REWARD_ROOM
		if portal_node and portal_node.has_method("queue_free"):
			portal_node.queue_free()
		_active_lottery_portal = null
		if reward_wheel_popup:
			reward_wheel_popup.show_for_stage(stage_index)
		return
	var portal_pos: Vector2 = portal_node.global_position
	# 抽奖 portal 暂存 stored_position 给 play_exit 用
	if "stored_position" in portal_node:
		portal_node.stored_position = portal_pos
	portal_traverse.play_enter(self, portal_pos, Callable(self, "_on_lottery_enter_midpoint"))


func _on_lottery_enter_midpoint() -> void:
	# play_enter 中点（屏幕全黑）：state 切到 REWARD_ROOM + 弹转盘
	state = GameState.REWARD_ROOM
	if reward_wheel_popup:
		reward_wheel_popup.show_for_stage(stage_index)


func _resume_from_portal_reward() -> void:
	# wheel 关：转盘关闭后跳下一关（play_exit 落地或兜底直切都走 _advance_from_wheel_stage）
	if _wheel_stage_index >= 0:
		if portal_traverse == null or _active_lottery_portal == null or not is_instance_valid(_active_lottery_portal):
			if _active_lottery_portal and is_instance_valid(_active_lottery_portal):
				_active_lottery_portal.queue_free()
			_active_lottery_portal = null
			_advance_from_wheel_stage()
			return
		var portal_pos: Vector2 = _active_lottery_portal.stored_position
		portal_traverse.play_exit(self, portal_pos, Callable(self, "_on_lottery_exit_complete"))
		return
	# v3：转盘关闭后走 play_exit（玩家从门里跳出，落到门正下方原地），完成后才恢复 PLAYING。
	if portal_traverse == null or _active_lottery_portal == null or not is_instance_valid(_active_lottery_portal):
		# 兜底：动画器或 portal 缺失，直接恢复
		state = GameState.PLAYING
		_portal_active_pause = false
		if _active_lottery_portal and is_instance_valid(_active_lottery_portal):
			_active_lottery_portal.queue_free()
		_active_lottery_portal = null
		if portal_spawner:
			portal_spawner.begin()
		return
	var portal_pos: Vector2 = _active_lottery_portal.stored_position
	portal_traverse.play_exit(self, portal_pos, Callable(self, "_on_lottery_exit_complete"))


func _on_lottery_exit_complete() -> void:
	# play_exit 完成：销毁门。wheel 关 → 跳下一关；普通随机抽奖 portal → 恢复 PLAYING。
	if _active_lottery_portal and is_instance_valid(_active_lottery_portal):
		_active_lottery_portal.queue_free()
	_active_lottery_portal = null
	if _wheel_stage_index >= 0:
		_advance_from_wheel_stage()
		return
	state = GameState.PLAYING
	_portal_active_pause = false
	if portal_spawner:
		portal_spawner.begin()


# === 关卡编辑器布局载入 ===
# 读取 res://config/levels/<编号>.json，按 elements 列表放置地块/元素。
# 地板类（水地板/石地板）走 terrain.set_tile 作为底面；其余（含深坑/阻挡石）走对应 FieldElement 实体，
# 这样"水地板上放深坑/阻挡石"能同时保留地板与阻挡实体两层。
# stage→编号 绑定属未来工作（在 stages.json 加 layout_number 字段）；此处通过编号直接载入。
const _TILE_LAYOUT_TYPES := ["water", "stone_floor"]

# 清空上一关遗留的放置元素实体（箭头/锁定块/深坑/阻挡石/宝箱）。
# field_elements 是跨关共享容器，_clear_stage_transition_presentation 不清它；模板载入前必须清，否则跨关堆积。
# clear() 同时清注册表 _by_cell，避免 stale 条目让 has_*_blocking_at 误报阻挡。
func _clear_field_elements() -> void:
	if field_elements == null:
		return
	field_elements.clear()
	for c in field_elements.get_children():
		if is_instance_valid(c):
			c.queue_free()


func _apply_level_layout(number) -> void:
	if not LevelLayoutLoaderScript:
		return
	var layout: Dictionary = LevelLayoutLoaderScript.load_layout(number)
	if layout.is_empty():
		print("[layout]   template=%s file_missing" % number)
		return
	var elements: Array = layout.get("elements", [])
	if elements.is_empty():
		print("[layout]   template=%s (0 elements)" % number)
		return
	print("[layout]   template=%s (%d elements)" % [number, elements.size()])
	# 地板类先攒成批量，末尾 terrain.set_tiles_batch 一次性写 grid + bake；
	# 逐格 set_tile 每格都会 _rebake_texture 整张图，N 格水 = N 次全图重绘 → 进测试卡顿。
	var tile_changes: Array = []
	for elem in elements:
		if not (elem is Dictionary):
			continue
		var t: String = String(elem.get("type", ""))
		var col: int = int(elem.get("col", 0))
		var row: int = int(elem.get("row", 0))
		var facing: String = String(elem.get("facing", "up"))
		if _TILE_LAYOUT_TYPES.has(t):
			tile_changes.append({"col": col, "row": row, "type": t})
			continue
		_spawn_field_element(t, col, row, facing)
	if not tile_changes.is_empty() and terrain and terrain.has_method("set_tiles_batch"):
		terrain.set_tiles_batch(tile_changes)


# 按 kind 实例化一个放置元素到 field_elements 容器，并注册到注册表。
func _spawn_field_element(kind: String, col: int, row: int, facing: String) -> Node:
	var elem: Node = null
	match kind:
		"arrow_single", "arrow_cross":
			var b := ArrowBlockScript.new()
			field_elements.add_child(b)
			b.setup_block(col, row, kind, facing)
			b.register_self(self)
			elem = b
		"locked_block":
			var b := LockedBlockScript.new()
			field_elements.add_child(b)
			b.setup_block(col, row)
			b.register_self(self)
			elem = b
		"pit":
			var b := PitBlockScript.new()
			field_elements.add_child(b)
			b.setup_block(col, row)
			b.register_self(self)
			elem = b
		"blocking_stone":
			var b := BlockingStoneBlockScript.new()
			field_elements.add_child(b)
			b.setup_block(col, row)
			b.register_self(self)
			elem = b
		"tree":
			# 真实 BattleTree 进 tree_container：可被砍、is_blocked_by_tree 挡路
			var t := BattleTreeScript.new()
			tree_container.add_child(t)
			t.setup(_cell_center(col, row), stage_index)
			if tree_spawner:
				tree_spawner.register_tree(t)  # 让 get_active_trees / is_blocked_by_tree 识别
			elem = t
		"fixed_portal":
			var p := FixedPortalScript.new()
			portal_container.add_child(p)
			p.setup_portal(col, row)
			elem = p
		"chest_normal":
			var c := ChestNormalScript.new()
			field_elements.add_child(c)
			c.setup_chest(col, row, kind)
			elem = c
		"chest_locked":
			var c := ChestLockedScript.new()
			field_elements.add_child(c)
			c.setup_chest(col, row, kind)
			elem = c
		_:
			push_warning("battle._spawn_field_element: unknown kind '%s'" % kind)
	return elem


func _cell_center(col: int, row: int) -> Vector2:
	var ts: int = TerrainBackground.TILE_SIZE
	return Vector2((col + 0.5) * float(ts), (row + 0.5) * float(ts))


# 关卡模板载入：
# - 编辑器测试模式：载入 __editor_test__（编辑器自动保存）。
# - reward / attr_forge / boss 关：不套模板（特殊房间 / boss 竞技场保持干净）。
# - 第一关：固定模板 0。
# - 其余普通战斗关（含恶魔/天使主题关）：40% 模板 0，60% 其他纯数字名模板随机（见 _roll_stage_template）。
# 场景贴图（草地→石地→…→王宫）由 terrain_background 按 stage_index 烘焙，与此处模板无关；
# 模板只在底图烘焙后追加 water/stone_floor 局部地块 + FieldElement 实体（树/坑/阻挡石/宝箱/传送门）。
func _apply_stage_layout_if_any(stage_idx: int) -> void:
	_clear_field_elements()  # 清上一关遗留的放置元素（field_elements 跨关共享，否则堆积）
	if LobbyState and LobbyState.editor_test_mode and not LobbyState.editor_test_layout.is_empty():
		print("[layout] stage=%d EDITOR_TEST" % stage_idx)
		_apply_level_layout(LobbyState.editor_test_layout)
		return
	var stage_dict: Dictionary = GameConfig.get_stage(stage_idx)
	var rt := str(stage_dict.get("room_type", ""))
	if rt == "reward":
		# wheel 关：固定套用 WHEEL_STAGE_LAYOUT 模板（中间放固定传送门，玩家触发后弹转盘）
		print("[layout] stage=%d WHEEL_LAYOUT_%s" % [stage_idx, WHEEL_STAGE_LAYOUT])
		_apply_level_layout(WHEEL_STAGE_LAYOUT)
		return
	if rt == "attr_forge":
		print("[layout] stage=%d SKIP(special room %s)" % [stage_idx, rt])
		return  # 特殊房间不套模板
	if str(stage_dict.get("boss_id", "")) != "":
		print("[layout] stage=%d SKIP(boss)" % stage_idx)
		return  # boss 关不套模板
	# 第一关：固定模板 0。
	if stage_idx == 0:
		print("[layout] stage=%d FORCED_0" % stage_idx)
		_apply_level_layout("0")
		return
	# 其余普通战斗关（含恶魔/天使主题关）：40% 模板 0，60% 其他模板随机。
	var picked := _roll_stage_template()
	print("[layout] stage=%d ROLL -> %s" % [stage_idx, picked])
	_apply_level_layout(picked)


# 40% 概率模板 0；否则在纯数字命名的已保存编号里等权随机抽一个（排除 "0"，它是 40% 桶）。
# 非纯数字名（default / __editor_test__ 等）不入随机池。池空回落到 "0"。
func _roll_stage_template() -> String:
	if randf() < 0.4:
		return "0"
	var others: Array = []
	for n in LevelLayoutLoaderScript.list_numbers():
		var ns := String(n)
		if not ns.is_valid_int():
			continue  # default / __editor_test__ 等非纯数字名不入池
		if ns == "0":
			continue
		others.append(ns)
	if others.is_empty():
		return "0"
	return String(others[randi() % others.size()])


# 编辑器测试模式：在战斗 UI 右上角加「停止测试」按钮，点击回关卡编辑器并恢复布局。
func _setup_editor_test_button() -> void:
	if not (LobbyState and LobbyState.editor_test_mode):
		return
	_editor_test_btn = Button.new()
	_editor_test_btn.text = LanguageManager.tr_ui("UI_LEVEL_EDITOR_STOP_TEST")
	_editor_test_btn.add_theme_font_size_override("font_size", 20)
	_editor_test_btn.offset_left = 540.0
	_editor_test_btn.offset_top = 12.0
	_editor_test_btn.offset_right = 700.0
	_editor_test_btn.offset_bottom = 52.0
	_editor_test_btn.pressed.connect(_on_stop_test)
	$UI.add_child(_editor_test_btn)


func _on_stop_test() -> void:
	# 不在此清 editor_test_mode —— 留给编辑器 _ready 检测以恢复测试布局，恢复后清。
	get_tree().change_scene_to_file("res://scenes/level_editor.tscn")


func apply_debug_settings(target_level: int, target_stage: int) -> void:
	pending_stage_clear = false
	stage_index = clampi(target_stage, 0, maxi(0, GameConfig.stages.size() - 1))
	experience.set_debug_level(target_level, player)
	player.begin_stage()
	_clear_stage_transition_presentation(false)
	if level_overlay:
		level_overlay.reset_all()
	if _try_enter_reward_room(stage_index):
		intro_label.visible = false
		hud.hide_message()
		hud.show_message(LanguageManager.tr_ui("UI_BATTLE_DEBUG_APPLIED"), 1.5)
		return
	spawner.spawn_stage(stage_index, self)
	if terrain:
		terrain.setup_for_stage(stage_index, _get_safe_zone())
	if water_overlay:
		water_overlay.refresh_from_terrain()
	_sync_background_layer()
	_refresh_stage_ambience()
	_apply_stage_meta(true)
	_apply_stage_layout_if_any(stage_index)
	_invalidate_nav()
	state = GameState.PLAYING
	intro_label.visible = false
	hud.hide_message()
	hud.show_message(LanguageManager.tr_ui("UI_BATTLE_DEBUG_APPLIED"), 1.5)


# 调试入口：直接跳到指定关卡的盖房子阶段（绕过 PLAYING / portal 等流程）。
func enter_build_house_debug(target_stage: int) -> void:
	pending_stage_clear = false
	stage_index = clampi(target_stage, 0, maxi(0, GameConfig.stages.size() - 1))
	# 停止战斗端的 spawner / portal / tree
	_portal_active_pause = false
	if portal_spawner:
		portal_spawner.stop()
		portal_spawner.clear_active_portal()
	if spawner:
		spawner.stop_infinite()
		spawner.clear_active_monsters()
	if tree_spawner:
		tree_spawner.stop()
	if level_overlay:
		level_overlay.reset_all()
	intro_label.visible = false
	hud.hide_message()
	_enter_build_house()


func _apply_stage_meta(_spawn_buff_orbs: bool) -> void:
	var stage := GameConfig.get_stage(stage_index)
	var chapter := GameConfig.get_chapter_for_stage(stage_index)
	var chapter_id := int(chapter.get("chapter_id", 1))
	if chapter_id != _current_chapter_id:
		_current_chapter_id = chapter_id
		if player:
			player.on_chapter_started(chapter_id)
	# Buff orbs 系统已禁用：恒 reset，不再 spawn
	if buff_orbs:
		buff_orbs.reset()
	hud.set_stage_text(LanguageManager.localize_field(stage, "display_name_en", "display_name"))


func get_stage_theme(idx: int) -> String:
	if idx < 0 or idx >= GameConfig.stages.size():
		return ""
	if _themed_stage_overrides.has(idx):
		return String(_themed_stage_overrides[idx])
	var s := GameConfig.get_stage(idx)
	var rt := str(s.get("room_type", ""))
	if rt == "reward" or rt == "attr_forge":
		return ""  # 特殊房不做主题
	# Boss 关优先：与主题关冲突时 boss 关胜出，否则操场会画 demon/angel sigil 视觉会乱。
	if str(s.get("boss_id", "")) != "":
		return ""
	# 主题改由 stages.xlsx theme 列配置驱动（demon/angel/random/空），不再每 4 关随机 + 天赋卡门控。
	var theme := str(s.get("theme", ""))
	if theme == "random":
		theme = "demon" if randi() % 2 == 0 else "angel"  # 本局内固定（缓存在 _themed_stage_overrides）
	_themed_stage_overrides[idx] = theme  # 缓存，本关内一致
	return theme


func shake_camera(magnitude: float, duration: float) -> void:
	if magnitude >= shake_mag:
		shake_mag = magnitude
		shake_dur = duration
	shake_timer = maxf(shake_timer, duration)


func _sync_background_layer() -> void:
	if background == null:
		return
	background.z_index = -100
	background.visible = true


func _refresh_stage_ambience() -> void:
	if grass_field == null:
		return
	if get_stage_theme(stage_index) != "":
		grass_field.clear_field()
		return
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var play_bottom := PixelUiHelper.get_play_area_bottom(h)
	grass_field.init_field(w, h, play_bottom, _get_safe_zone(), terrain)


func _get_safe_zone() -> Dictionary:
	if player == null:
		return {}
	return {
		"x": player.home_position.x,
		"y": player.home_position.y,
		"r": player.get_trigger_radius(),
	}


func _update_ambience(delta: float) -> void:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	if grass_field:
		grass_field.update_field(delta)
	if sakura_field:
		sakura_field.update_field(delta, w, h)


func _update_camera_shake(delta: float) -> void:
	if shake_timer <= 0.0:
		camera.offset = Vector2.ZERO
		return
	shake_timer -= delta
	var intensity := shake_timer / maxf(0.001, shake_dur)
	camera.offset = Vector2(
		randf_range(-1.0, 1.0) * 2.0 * shake_mag * intensity,
		randf_range(-1.0, 1.0) * 2.0 * shake_mag * intensity
	)
	if shake_timer <= 0.0:
		camera.offset = Vector2.ZERO
		shake_mag = 0.0


func enter_bullet_time() -> void:
	time_scale = float(GameConfig.get_tuning("bullet_time_scale", 0.14))
	dim_overlay.visible = true
	dim_overlay.color = Color(0, 0, 0, float(GameConfig.get_tuning("bullet_time_dim_alpha", 0.42)))
	_record_zoom_in()


# [RECORD-ONLY] 画线时相机轻拉近 + 平移到主角附近
var _record_cam_tween: Tween = null
func _record_zoom_in() -> void:
	if camera == null or player == null:
		return
	if _record_cam_tween:
		_record_cam_tween.kill()
	_record_cam_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_record_cam_tween.tween_property(camera, "zoom", Vector2.ONE * 1.06, 0.25)
	var initial := Vector2(_initial_camera_x, _initial_camera_y)
	var target := initial.lerp(player.global_position, 0.25)
	_record_cam_tween.parallel().tween_property(camera, "position", target, 0.25)

func _record_zoom_out() -> void:
	if camera == null:
		return
	if _record_cam_tween:
		_record_cam_tween.kill()
	_record_cam_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_record_cam_tween.tween_property(camera, "zoom", Vector2.ONE, 0.2)
	_record_cam_tween.parallel().tween_property(camera, "position", Vector2(_initial_camera_x, _initial_camera_y), 0.2)


func exit_bullet_time(cancelled: bool) -> void:
	_record_zoom_out()
	if cancelled:
		resume_battle_time()
		if buff_orbs:
			buff_orbs.cancel_draw_session()
		if player.state == BattlePlayer.State.BULLET_TIME:
			player.invalidate_path()
		return
	player.start_attack()


func resume_battle_time() -> void:
	time_scale = 1.0
	dim_overlay.visible = false


func enter_fail_death_presentation() -> void:
	resume_battle_time()
	path_input.cancel_active()
	time_scale = 0.0
	dim_overlay.z_index = 1
	dim_overlay.color = Color(0, 0, 0, 0.0)
	dim_overlay.visible = true
	_raise_player_above_dim()


func exit_fail_death_presentation() -> void:
	time_scale = 1.0
	dim_overlay.visible = false
	dim_overlay.z_index = -1  # 回到 _setup_viewport 设置的基线
	_restore_player_parent()


func set_fail_death_dim(alpha: float) -> void:
	if dim_overlay:
		dim_overlay.color = Color(0, 0, 0, clampf(alpha, 0.0, 1.0))


func _raise_player_above_dim() -> void:
	if player == null:
		return
	if _fail_death_player_parent == null:
		_fail_death_player_parent = player.get_parent()
	if player.get_parent() == self:
		return
	var pos := player.global_position
	_fail_death_player_parent.remove_child(player)
	add_child(player)
	player.global_position = pos
	player.z_index = 2


func _restore_player_parent() -> void:
	if player == null or _fail_death_player_parent == null:
		return
	if player.get_parent() == _fail_death_player_parent:
		_fail_death_player_parent = null
		return
	var pos := player.global_position
	player.get_parent().remove_child(player)
	_fail_death_player_parent.add_child(player)
	player.global_position = pos
	player.z_index = 0
	_fail_death_player_parent = null


func resume_from_pause() -> void:
	if state != GameState.PAUSED:
		return
	state = GameState.PLAYING
	if pause_menu:
		pause_menu.close_menu()
	hud.show_message(LanguageManager.tr_ui("UI_BATTLE_CONTINUE"), 1.0)


# 从暂停菜单「返回主界面」：直接切场景，battle 节点树随之释放。
func return_to_main_menu_from_pause() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func pause_game() -> void:
	if _lobby_entry_intro_active:
		return
	if state in [GameState.MENU, GameState.WAIT_START, GameState.FAIL_DEATH, GameState.STAGE_CLEAR, GameState.COMPLETE, GameState.FAIL, GameState.STAGE_FAIL, GameState.LEVEL_UP, GameState.BUILD_HOUSE, GameState.BUILD_HOUSE_DONE, GameState.ATTR_FORGE, GameState.ATTR_FORGE_DONE, GameState.STAGE_TRANSITION]:
		return
	if state == GameState.REWARD_ROOM:
		return
	# 关卡 intro 期间也允许暂停
	state = GameState.PAUSED
	path_input.cancel_active()
	if pause_menu:
		pause_menu.z_index = 200
		pause_menu.open_menu()
		pause_menu.move_to_front()


func enter_level_up() -> void:
	state = GameState.LEVEL_UP
	path_input.cancel_active()
	upgrades.generate_choices(player)
	upgrade_popup.z_index = 80
	upgrade_popup.show_popup()
	upgrade_popup.move_to_front()


func _on_monster_killed(monster: Node) -> void:
	if not (monster is BattleMonster):
		return
	if blood_stains and is_instance_valid(monster) and monster is BattleMonster:
		var bm := monster as BattleMonster
		var hit_r: float = bm.get_hitbox_radius()
		var intensity := 1.65 if hit_r > 13.0 else 1.25
		var hit_angle := randf() * TAU
		if player:
			hit_angle = (monster.global_position - player.global_position).angle()
		blood_stains.spawn(
			monster.global_position.x,
			monster.global_position.y + hit_r * 0.35,
			intensity,
			hit_angle
		)
	if player and player.ice_ready:
		combat.try_ice_burst(player, monster.global_position)
	# 经验改走灵魂球延迟：orb 飞到经验条才 add_exp（兜底：reward<=0 直接走原路径）
	var exp_reward := experience.get_kill_reward(monster)
	if exp_reward > 0 and soul_orb_manager != null:
		soul_orb_manager.spawn(monster.global_position, exp_reward)
	else:
		experience.on_monster_killed(monster)
	if player:
		player.on_enemy_killed(monster.global_position)
	var dropped := LobbyState.try_drop_random_equipment()
	if not dropped.is_empty() and equipment_drop_fx and is_instance_valid(monster):
		equipment_drop_fx.spawn(dropped, monster.global_position)
	# 技能石掉落（小怪 1%，规则见 skill_stones.json rules.small_drop_rate）
	var ss_drop := LobbyState.roll_skill_stone_drop(false)
	if not ss_drop.is_empty() and equipment_drop_fx and is_instance_valid(monster):
		equipment_drop_fx.spawn(ss_drop, monster.global_position)


func _on_upgrade_picked(_index: int) -> void:
	if _pending_attr_forge_advance:
		_advance_after_attr_forge()
		return
	state = GameState.PLAYING
	experience.try_trigger_upgrade(self)
	_try_finish_stage_clear()


func _on_resolve_finished() -> void:
	experience.try_trigger_upgrade(self)
	_try_finish_stage_clear()


func _needs_fx_redraw() -> bool:
	if combat and combat.has_active_hit_fx():
		return true
	if abilities and abilities.has_active_fx():
		return true
	if summons and summons.has_active_fx():
		return true
	if swords and swords.has_active_fx():
		return true
	if auras and auras.has_active_fx():
		return true
	if particles and particles.has_active_effects():
		return true
	if fail_animator and fail_animator.is_active():
		return true
	return false


func _update_path_preview() -> void:
	var targets := get_combat_targets()
	if player.state == BattlePlayer.State.BULLET_TIME and player.attack_path.size() >= 2:
		combat.update_path_preview_highlights(player.attack_path, player, targets)
		var preview_hits := combat.get_path_preview_total_hits(player.attack_path, player, targets)
		player.update_combo_preview(preview_hits)
	else:
		combat.clear_path_preview_highlights(targets)


func _try_finish_stage_clear() -> void:
	if not pending_stage_clear:
		return
	if combat.is_resolving() or combat.has_combat_presentation() or state == GameState.LEVEL_UP:
		return
	if abilities and abilities.has_active_fx():
		return
	if summons and summons.has_active_fx():
		return
	# 等最后一只怪的死亡动画结束（防止死亡动画播了一半就切场景）
	if spawner and spawner.has_pending_death_presentation():
		return
	pending_stage_clear = false
	# boss 关技能石掉落（100%）：在切关前发，FX 落在 boss 位置
	_maybe_drop_boss_skill_stone()
	_advance_to_next_stage()


func _maybe_drop_boss_skill_stone() -> void:
	if _boss_skill_stone_dropped_stage_index == stage_index:
		return
	var stage := GameConfig.get_stage(stage_index)
	if str(stage.get("boss_id", "")) == "":
		return
	_boss_skill_stone_dropped_stage_index = stage_index
	var ss := LobbyState.roll_skill_stone_drop(true)
	if ss.is_empty() or equipment_drop_fx == null:
		return
	var pos: Vector2 = player.global_position if player != null else Vector2.ZERO
	if spawner != null and is_instance_valid(spawner.boss):
		pos = spawner.boss.global_position
	equipment_drop_fx.spawn(ss, pos)


func _advance_to_next_stage() -> void:
	# 关卡推进：先做"跳跃 + 竖向滚轴"过场，落地后再切换 stage_index。
	# 通关早出口直接走原 game-complete 流程，不跑滚轴。
	var next_index := stage_index + 1
	if next_index >= GameConfig.stages.size():
		EventBus.stage_cleared.emit(stage_index)
		stage_index = next_index
		_clear_stage_transition_presentation(true)
		state = GameState.COMPLETE
		if level_overlay:
			level_overlay.show_game_complete()
		hud.hide_message()
		return
	# 主题关（demon / angel）专属奖励：在跳跃之前弹 popup，玩家选完才 stage_transition.play()
	if _maybe_open_themed_reward(next_index):
		return
	if stage_transition:
		stage_transition.play(self, next_index, _on_stage_transition_complete.bind(next_index))
	else:
		# Fallback：编排器异常时退化为旧的直接切关逻辑
		_legacy_advance_to_next_stage()


func _maybe_open_themed_reward(next_index: int) -> bool:
	if themed_reward_popup == null or upgrades == null or player == null:
		return false
	var cleared_theme := get_stage_theme(stage_index)
	if cleared_theme != "demon" and cleared_theme != "angel":
		return false
	var group_name := "恶魔" if cleared_theme == "demon" else "天使"
	var pick: Dictionary = upgrades.roll_themed(group_name, player)
	if pick.is_empty():
		return false
	_pending_themed_next_index = next_index
	_pending_themed_theme = cleared_theme
	# 关键：切到 STAGE_TRANSITION state，否则下一帧 spawner.all_dead() 会再次触发
	# _try_finish_stage_clear → _advance_to_next_stage → re-roll 新卡（导致 popup 卡牌疯狂闪变）
	state = GameState.STAGE_TRANSITION
	themed_reward_popup.show_for_theme(cleared_theme, pick)
	return true


func _on_stage_transition_complete(next_index: int) -> void:
	stage_index = next_index
	if _try_enter_reward_room(stage_index):
		return
	_apply_stage_meta(false)
	# 正常切关路径（stage_transition 落地后）在此载入关卡模板：
	# prespawn/rebase 只搭地形/草地/树容器，没载模板，必须在这里补。
	_apply_stage_layout_if_any(stage_index)
	_invalidate_nav()
	state = GameState.PLAYING
	EventBus.stage_started.emit(stage_index)


func _on_themed_reward_resolved(accepted: bool, upgrade: Dictionary) -> void:
	if accepted and player != null and not upgrade.is_empty():
		player.apply_upgrade(upgrade)
		if hud:
			hud.show_message(LanguageManager.tr_ui("UI_BATTLE_PICKED_FMT") % LanguageManager.localize(upgrade, "name"), 1.6)
	var next_idx: int = _pending_themed_next_index
	_pending_themed_next_index = -1
	_pending_themed_theme = ""
	if next_idx < 0:
		return
	# 玩家选完才播跳跃动画 → 落地后切关
	if stage_transition:
		stage_transition.play(self, next_idx, _on_stage_transition_complete.bind(next_idx))
	else:
		stage_index = next_idx
		if _try_enter_reward_room(stage_index):
			return
		_apply_stage_meta(false)
		state = GameState.PLAYING
		EventBus.stage_started.emit(stage_index)


func _legacy_advance_to_next_stage() -> void:
	# 旧的直接切关流程，仅作为编排器异常时的兜底。
	EventBus.stage_cleared.emit(stage_index)
	stage_index += 1
	if stage_index >= GameConfig.stages.size():
		_clear_stage_transition_presentation(true)
		state = GameState.COMPLETE
		if level_overlay:
			level_overlay.show_game_complete()
		hud.hide_message()
		return
	if _try_enter_reward_room(stage_index):
		return
	_clear_stage_transition_presentation(stage_index > 0)
	spawner.spawn_stage(stage_index, self)
	_apply_stage_meta(false)
	if tree_spawner:
		if get_stage_theme(stage_index) == "":
			tree_spawner.begin(self)
		else:
			tree_spawner.reset()
	_apply_stage_layout_if_any(stage_index)
	_invalidate_nav()
	if portal_spawner:
		portal_spawner.begin()
	state = GameState.PLAYING
	EventBus.stage_started.emit(stage_index)


func _try_enter_reward_room(next_stage_index: int) -> bool:
	var stage := GameConfig.get_stage(next_stage_index)
	if stage.is_empty():
		return false
	var rt := str(stage.get("room_type", ""))
	# 属性打造关：配置写了 room_type=attr_forge 即进打造房，不再需要天赋卡 forge_stage 解锁
	if rt == "attr_forge":
		stage_index = next_stage_index
		# v3：不再直接进入打造小游戏，先走"小跳跃跳进门"动画
		_begin_forge_stage()
		return true
	if rt != "reward":
		return false
	# wheel 关：不再主动弹转盘页面。改为标记当前关为 wheel 关并返回 false，
	# 让正常切关流程接管（spawner 怪数=0 + _apply_stage_layout_if_any 套 WHEEL_STAGE_LAYOUT 模板）。
	# 玩家进入后走到模板中间的固定传送门 → on_portal_entered → 转盘 → _advance_from_wheel_stage 跳下一关。
	_wheel_stage_index = next_stage_index
	return false


# wheel 关奖励结束（portal 退出完成 / 兜底直切）后调用：跳入下一关。
# 逻辑同旧的 _on_reward_wheel_finished 非.portal 推进分支：跳跃 + 滚轴过场落地后切关。
func _advance_from_wheel_stage() -> void:
	var idx: int = _wheel_stage_index
	_wheel_stage_index = -1
	_pending_reward_stage_index = -1
	_portal_active_pause = false
	if idx < 0:
		state = GameState.PLAYING
		return
	var next_index: int = idx + 1
	if next_index >= GameConfig.stages.size():
		stage_index = next_index
		_clear_stage_transition_presentation(true)
		state = GameState.COMPLETE
		if level_overlay:
			level_overlay.show_game_complete()
		hud.hide_message()
		return
	# 离开 wheel 关 → 与普通关一样走"跳跃 + 滚轴"过场
	if stage_transition:
		stage_transition.play(self, next_index, _on_stage_transition_complete.bind(next_index))
	else:
		stage_index = next_index
		_clear_stage_transition_presentation(stage_index > 0)
		spawner.spawn_stage(stage_index, self)
		_apply_stage_meta(false)
		if tree_spawner:
			if get_stage_theme(stage_index) == "":
				tree_spawner.begin(self)
			else:
				tree_spawner.reset()
		_apply_stage_layout_if_any(stage_index)
		_invalidate_nav()
		if portal_spawner:
			portal_spawner.begin()
		state = GameState.PLAYING
		EventBus.stage_started.emit(stage_index)


func _on_reward_wheel_finished(reward_text: String) -> void:
	# wheel 关奖励现在只走 portal-driven 路径（_pending_reward_stage_index == -2）：
	# 玩家在 wheel 关触发固定传送门 → 转盘 → 这里 → _resume_from_portal_reward →
	# play_exit → _on_lottery_exit_complete → _advance_from_wheel_stage 跳下一关。
	if _pending_reward_stage_index == -2:
		if not reward_text.is_empty():
			hud.show_message(LanguageManager.tr_ui("UI_BATTLE_REWARD_GOT_FMT") % reward_text, 1.6)
		_pending_reward_stage_index = -1
		_resume_from_portal_reward()
		return
	if _wheel_stage_index >= 0:
		# 兜底：portal 流程异常但仍在 wheel 关 → 直接推进
		if not reward_text.is_empty():
			hud.show_message(LanguageManager.tr_ui("UI_BATTLE_REWARD_GOT_FMT") % reward_text, 1.6)
		_advance_from_wheel_stage()
		return


func _process(delta: float) -> void:
	if virtual_joystick:
		virtual_joystick.set_battle_enabled(state == GameState.PLAYING)
	var scaled_delta := delta * time_scale
	match state:
		GameState.MENU:
			_update_ambience(delta)
		GameState.WAIT_START:
			_update_ambience(delta)
		GameState.STAGE_INTRO:
			_update_ambience(delta)
			if _lobby_entry_intro_active:
				player.update_idle(delta, 1.0)
				_update_lobby_entry_intro(delta)
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.PLAYING:
			_update_playing(scaled_delta, delta)
			if tree_spawner:
				tree_spawner.update_trees(delta, self)
			# wheel 关不刷随机抽奖 portal——固定传送门由 WHEEL_STAGE_LAYOUT 模板提供
			if portal_spawner and not _portal_active_pause and _wheel_stage_index < 0:
				portal_spawner.update(delta, self)
		GameState.BUILD_HOUSE:
			if build_house:
				build_house.update(delta)
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.BUILD_HOUSE_DONE:
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.ATTR_FORGE:
			if attr_forge:
				attr_forge.update(delta)
			if particles:
				particles.update_particles(delta)
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.ATTR_FORGE_DONE:
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.PAUSED:
			pass
		GameState.STAGE_CLEAR:
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.FAIL_DEATH:
			_update_ambience(delta)
			if fail_animator:
				fail_animator.update(delta)
			queue_redraw()
		GameState.STAGE_FAIL:
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.COMPLETE:
			pass
		GameState.LEVEL_UP:
			upgrades.update(delta)
		GameState.REWARD_ROOM:
			_update_ambience(delta)
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.STAGE_TRANSITION:
			_update_ambience(delta)
			player.update_idle(delta, 1.0)
			# 关键：portal_traverse 期间用 level_overlay.show_phase_fade 做黑色淡入淡出，
			# overlay 必须每帧推进 — 否则 phase_fade 卡在 fade_in，midpoint 回调（弹 popup +
			# 切 state）永远不触发，game 卡死。
			if level_overlay:
				level_overlay.update_overlay(delta)
	_update_camera_shake(delta)


func _update_playing(scaled_delta: float, real_delta: float) -> void:
	_update_ambience(real_delta)
	player.update_idle(real_delta, time_scale if time_scale < 1.0 else 1.0)
	if virtual_joystick and player.state == BattlePlayer.State.IDLE:
		player.update_joystick_locomotion(virtual_joystick.get_output(), real_delta, self)
	_nudge_player_out_of_trees()
	player.update_combo_display(real_delta)
	if level_overlay and (level_overlay.is_stage_intro_active() or level_overlay.is_phase_fade_active()):
		level_overlay.update_overlay(real_delta)
	if player.state == BattlePlayer.State.ATTACKING:
		var attack_delta := real_delta if time_scale < 1.0 else scaled_delta
		var attack_finished := player.update_attack(attack_delta, combat, get_combat_targets())
		if attack_finished:
			resume_battle_time()
	combat.update_afterimages(real_delta)
	combat.update_slash_hit_fx(real_delta)
	combat.update_resolve(scaled_delta, player)
	combat.update_damage_numbers(real_delta)
	if buff_orbs:
		buff_orbs.update(real_delta, player)
	if abilities:
		var ability_delta := 0.0 if time_scale < 1.0 else real_delta
		abilities.update(ability_delta, player, get_ability_targets())
	if summons:
		var summon_delta := 0.0 if time_scale < 1.0 else real_delta
		summons.update(summon_delta, player, get_ability_targets())
	if swords:
		var sword_delta := 0.0 if time_scale < 1.0 else real_delta
		swords.update(sword_delta, player, get_ability_targets())
	if auras:
		var aura_delta := 0.0 if time_scale < 1.0 else real_delta
		auras.update(aura_delta, player)
	if particles:
		particles.update_particles(real_delta)
	if blood_stains:
		blood_stains.update_stains(real_delta)
	if ground_effects:
		var effect_delta := 0.0 if time_scale < 1.0 else real_delta
		ground_effects.update_effects(effect_delta, player)
	var boss_delta := scaled_delta if time_scale >= 1.0 else 0.0
	_update_enemy_arrows(boss_delta)
	spawner.update_boss(boss_delta, player)
	spawner.update_spawns(real_delta, self)
	for monster in spawner.monsters:
		if is_instance_valid(monster) and monster.has_method("update_death"):
			monster.update_death(real_delta)
		if is_instance_valid(monster) and monster.has_method("update_ai"):
			monster.update_ai(scaled_delta if time_scale >= 1.0 else 0.0, player, self)
	_update_path_preview()
	experience.try_trigger_upgrade(self)
	if _needs_fx_redraw():
		queue_redraw()
		if hit_fx_overlay:
			hit_fx_overlay.queue_redraw()
		if under_monster_fx_overlay:
			under_monster_fx_overlay.queue_redraw()
		if above_monster_fx_overlay:
			above_monster_fx_overlay.queue_redraw()
	if player.hp <= 0 and state == GameState.PLAYING:
		_begin_fail_death()
		return
	# Phase fade transition (e.g., into BUILD_HOUSE) blocks stage-clear so we don't
	# accidentally bump to the next stage while waiting for the fade callback.
	if level_overlay and level_overlay.is_phase_fade_active():
		return
	var summon_fx_active: bool = summons != null and summons.has_active_fx()
	# wheel 关没有怪物（怪数=0），不能因 all_dead 自动通关——必须等玩家走到固定传送门触发转盘。
	if _wheel_stage_index < 0 and spawner.all_dead() and not spawner.has_pending_death_presentation() and not spawner.is_spawning() and not combat.is_resolving() and not combat.has_combat_presentation() and player.state == BattlePlayer.State.IDLE and not abilities.has_active_fx() and not summon_fx_active:
		pending_stage_clear = true
		_try_finish_stage_clear()


func _begin_fail_death() -> void:
	if fail_animator and fail_animator.is_active():
		return
	_clear_fail_death_combat_fx()
	state = GameState.FAIL_DEATH
	path_input.cancel_active()
	if fail_animator:
		fail_animator.start(_on_fail_death_finished)


func _clear_stage_transition_presentation(keep_companions: bool) -> void:
	if combat:
		combat.reset_for_stage()
	if abilities:
		abilities.reset()
	if summons:
		summons.reset(keep_companions)
	if swords:
		swords.reset()
	if auras:
		auras.reset()
	if particles:
		particles.clear()
	if blood_stains:
		blood_stains.clear()
	if equipment_drop_fx:
		equipment_drop_fx.clear()
	if soul_orb_manager:
		soul_orb_manager.clear()
	if pickup_orb_manager:
		pickup_orb_manager.clear()
	_clear_projectiles()
	if ground_effects:
		ground_effects.reset()
	_queue_combat_fx_redraw()


func _prespawn_next_stage_world(next_index: int) -> void:
	# StageTransition PRESPAWN：把下一关的地形 + 草地 + 树等"非怪物"装饰提前画到世界 Y = -1280 处。
	# 怪物（含传送门 / 木材）不在这里生成，留给 REBASE 之后（坐标系恢复标准）由 spawner 处理。
	if _next_stage_root and is_instance_valid(_next_stage_root):
		_next_stage_root.queue_free()
		_next_stage_root = null
	_pending_next_terrain = null
	_pending_next_grass = null
	_pending_next_tree_container = null
	_pending_next_trees = []
	_pending_next_forge_portal = null

	var root := Node2D.new()
	root.name = "NextStageRoot"
	root.position = Vector2(0, -1280)
	add_child(root)
	_next_stage_root = root

	# 检查下一关是否是打造关 — 是的话走差异化分支：紫色地面 / 不生草 / 不生树 / 中心生 ForgePortal
	var next_stage_dict: Dictionary = GameConfig.get_stage(next_index)
	var is_forge_stage := str(next_stage_dict.get("room_type", "")) == "attr_forge"

	# 1) 地形
	var new_terrain := TerrainBackground.new()
	new_terrain.name = "NextTerrain"
	new_terrain.z_index = -5  # z_index 在 Godot 2D 不继承，需显式设置
	root.add_child(new_terrain)
	# 用"下一关的玩家落地点"作 safe_zone，避免水簇盖在落地位置
	var next_w := float(GameConfig.get_tuning("logical_width", 720))
	var next_h := float(GameConfig.get_tuning("logical_height", 1280))
	var next_safe := {
		"x": next_w * 0.5,
		"y": next_h * 0.58,
		"r": float(player.get_trigger_radius()) if player else 80.0,
	}
	new_terrain.setup_for_stage(next_index, next_safe)
	_pending_next_terrain = new_terrain

	# 2) 草地（init_field 在下一关 safe_zone = 玩家落地点周围）
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var new_grass := GrassSystemScript.new()
	new_grass.name = "NextGrassField"
	new_grass.z_index = -4
	root.add_child(new_grass)
	var next_theme := get_stage_theme(next_index)
	# 打造关：不生成草，让紫色地面干净
	if next_theme.is_empty() and not is_forge_stage:
		var play_bottom := PixelUiHelper.get_play_area_bottom(h)
		var safe_zone := {"x": w * 0.5, "y": h * 0.58, "r": 60.0}
		new_grass.init_field(w, h, play_bottom, safe_zone, new_terrain)
	_pending_next_grass = new_grass

	# 3) 树 —— 直接实例化（不经 tree_spawner），生成进 next_tree_container
	# 打造关：不生成树（保留空容器供 REBASE 替换战斗关的旧树容器）
	var new_tree_container := Node2D.new()
	new_tree_container.name = "NextTrees"
	new_tree_container.z_index = 0
	root.add_child(new_tree_container)
	_pending_next_tree_container = new_tree_container
	if next_theme.is_empty() and not is_forge_stage:
		_pending_next_trees = _spawn_prespawn_trees(new_tree_container, next_index, w, h)
	else:
		_pending_next_trees = []

	# 4) 打造关：在场景中心实例化 ForgePortal（落地点位置 = 玩家落地点）
	# 注意用 LOCAL position 而非 global_position（NextStageRoot 在 y=-1280，REBASE 后才到 0）。
	if is_forge_stage:
		var forge_portal: Node = ForgePortalScript.new()
		forge_portal.name = "ForgePortal"
		root.add_child(forge_portal)
		var local_pos := Vector2(next_w * 0.5, next_h * 0.58)
		forge_portal.setup(local_pos)
		_pending_next_forge_portal = forge_portal


func _spawn_prespawn_trees(container: Node2D, stage_idx: int, w: float, h: float) -> Array:
	# 随机树预生成已停用：树改为关卡编辑器布局放置（_apply_level_layout）。
	# 保留函数签名供 _prespawn_next_stage_world 调用，返回空数组。
	return []


func _pick_prespawn_tree_pos(w: float, h: float, safe: Vector2, placed: Array) -> Vector2:
	var t = _pending_next_terrain
	for attempt in range(60):
		var x := randf_range(60.0, w - 60.0)
		var y := randf_range(130.0, h - 200.0)
		var pos := Vector2(x, y)
		if pos.distance_to(safe) < 200.0:
			continue
		# 不在水格里生成
		if t and t.has_method("get_tile_at_world") and t.get_tile_at_world(x, y) == "water":
			continue
		var clash := false
		for tr in placed:
			if is_instance_valid(tr) and pos.distance_to(tr.position) < 110.0:
				clash = true
				break
		if not clash:
			return pos
	return Vector2(randf_range(80.0, w - 80.0), randf_range(140.0, h - 220.0))


func _rebase_after_transition(next_index: int) -> void:
	# StageTransition REBASE：单帧原子地把新地形 / 草地 / 树从 (0,-1280) 拉回到 (0,0)，
	# 同时把摄像机和玩家瞬移回标准坐标。摄像机 +1280、内容 -1280 在同一帧抵消，玩家无感。
	# 1) 地形：替换 battle.terrain 引用
	if terrain and is_instance_valid(terrain):
		terrain.queue_free()
	if _pending_next_terrain and is_instance_valid(_pending_next_terrain):
		_pending_next_terrain.reparent(self, false)
		_pending_next_terrain.position = Vector2.ZERO
		terrain = _pending_next_terrain
		_pending_next_terrain = null
	# 2) 草地：替换 battle.grass_field 引用
	if grass_field and is_instance_valid(grass_field):
		grass_field.queue_free()
	if _pending_next_grass and is_instance_valid(_pending_next_grass):
		_pending_next_grass.reparent(self, false)
		_pending_next_grass.position = Vector2.ZERO
		grass_field = _pending_next_grass
		_pending_next_grass = null
	# 3) 树容器：替换 battle.tree_container 引用 + 同步 tree_spawner.trees 状态
	if tree_container and is_instance_valid(tree_container):
		tree_container.queue_free()
	if _pending_next_tree_container and is_instance_valid(_pending_next_tree_container):
		_pending_next_tree_container.reparent($Entities, false)
		_pending_next_tree_container.position = Vector2.ZERO
		tree_container = _pending_next_tree_container
		_pending_next_tree_container = null
	if tree_spawner:
		# 让 tree_spawner 认领新树（_pending_next_trees 现为空——预生成树已停用），避免 update_trees 误判"全死"。
		tree_spawner.trees = _pending_next_trees.duplicate()
		# 随机树生成已停用：树改为模板布局放置（见 _apply_stage_layout_if_any）。
		# active=false 让 update_trees 直接 early return，不再程序化补刷树（否则普通关每帧 _spawn_wave 刷树）。
		tree_spawner.active = false
	_pending_next_trees = []
	# 3.5) 打造关 ForgePortal：reparent 到 $Entities/Portals，赋值 _active_forge_portal
	if _pending_next_forge_portal and is_instance_valid(_pending_next_forge_portal):
		_pending_next_forge_portal.reparent(portal_container, false)
		# REBASE 后世界坐标系已恢复标准（NextStageRoot y=-1280 被替换为 0），
		# portal 的 local position 现在等于 global_position，sync 一下让 stored_position 对齐
		if _pending_next_forge_portal.has_method("sync_stored_global"):
			_pending_next_forge_portal.sync_stored_global()
		_active_forge_portal = _pending_next_forge_portal
		_pending_next_forge_portal = null
	# 4) NextStageRoot 空了，干掉
	if _next_stage_root and is_instance_valid(_next_stage_root):
		_next_stage_root.queue_free()
		_next_stage_root = null
	# 5) 摄像机 + 玩家瞬移回标准坐标
	if camera:
		camera.position = Vector2(_initial_camera_x, _initial_camera_y)
	if player:
		var view_h := float(GameConfig.get_tuning("logical_height", 1280))
		player.global_position = Vector2(_initial_camera_x, view_h * 0.58)
		player.home_position = player.global_position
		player.scale = Vector2.ONE
	# 5.5) 召唤物吸附到玩家身边 — 旧 c.pos 是 REBASE 前的世界坐标，不修就会从奇怪地方平滑跟过来
	if summons and summons.has_method("snap_to_player"):
		summons.snap_to_player(player)
	# 6) 通知 water_overlay 拉新水格列表
	if water_overlay:
		water_overlay.refresh_from_terrain()


func _queue_combat_fx_redraw() -> void:
	if hit_fx_overlay:
		hit_fx_overlay.queue_redraw()
	if under_monster_fx_overlay:
		under_monster_fx_overlay.queue_redraw()
	if above_monster_fx_overlay:
		above_monster_fx_overlay.queue_redraw()
	if ground_effects:
		ground_effects.queue_redraw()
	queue_redraw()


func _clear_fail_death_combat_fx() -> void:
	if combat:
		combat.clear_presentation()
	if abilities:
		abilities.clear_death_presentation()
	_queue_combat_fx_redraw()


func _on_fail_death_finished() -> void:
	var initial_overlay_alpha := 0.0
	if dim_overlay.visible:
		initial_overlay_alpha = clampf(dim_overlay.color.a / 0.72, 0.0, 1.0)
	state = GameState.STAGE_FAIL
	hud.hide_message()
	if level_overlay:
		level_overlay.show_fail_intro(
			Callable(self, "_retry_after_fail"),
			Callable(self, "_back_to_main_menu"),
			initial_overlay_alpha
		)
	exit_fail_death_presentation()


func _retry_after_fail() -> void:
	if state != GameState.STAGE_FAIL:
		return
	hud.hide_message()
	_enter_wait_start()
	_exit_wait_start_and_begin()


func _back_to_main_menu() -> void:
	if state != GameState.STAGE_FAIL:
		return
	get_tree().change_scene_to_file(MAIN_SCENE)


func _draw_hit_fx_overlay() -> void:
	if state in [GameState.FAIL_DEATH, GameState.STAGE_FAIL]:
		return
	if combat:
		combat.draw_slash_hit_fx(hit_fx_overlay)
	if abilities:
		abilities.draw_hit_fx(hit_fx_overlay)


func _draw_under_monster_fx_overlay() -> void:
	if state in [GameState.FAIL_DEATH, GameState.STAGE_FAIL]:
		return
	if abilities:
		abilities.draw_fx(under_monster_fx_overlay, true)
	if summons:
		summons.draw_fx(under_monster_fx_overlay, true)


func _draw_above_monster_fx_overlay() -> void:
	if state in [GameState.FAIL_DEATH, GameState.STAGE_FAIL]:
		return
	if particles:
		particles.draw_particles(above_monster_fx_overlay)
	if abilities:
		abilities.draw_fx(above_monster_fx_overlay, false)
	if summons:
		summons.draw_fx(above_monster_fx_overlay, false)
	if swords:
		swords.draw_fx(above_monster_fx_overlay, false)
	if auras:
		auras.draw_fx(above_monster_fx_overlay, false)


func _pointer_flow_uses_early_input() -> bool:
	return state in [
		GameState.MENU,
		GameState.STAGE_INTRO,
		GameState.WAIT_START,
		GameState.BUILD_HOUSE,
		GameState.ATTR_FORGE,
		GameState.FAIL,
		GameState.COMPLETE,
		GameState.STAGE_FAIL,
	]


func _input(event: InputEvent) -> void:
	if pause_menu and pause_menu.visible:
		return
	if upgrade_popup.visible:
		return
	if state == GameState.STAGE_FAIL and level_overlay and level_overlay.has_active_fail_actions():
		return
	if event.is_action_pressed("ui_cancel") and state in [GameState.PLAYING, GameState.STAGE_INTRO]:
		if _lobby_entry_intro_active:
			get_viewport().set_input_as_handled()
			return
		pause_game()
		get_viewport().set_input_as_handled()
		return
	if _pointer_flow_uses_early_input():
		_dispatch_pointer_event(event, true)
		return
	# 战斗中画线必须在 _input 处理：全屏 HUD 会挡住 _unhandled_input
	if state == GameState.PLAYING:
		_dispatch_pointer_event(event, false)


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu and pause_menu.visible:
		return
	if upgrade_popup.visible:
		return
	if _pointer_flow_uses_early_input() or state == GameState.PLAYING:
		return
	_dispatch_pointer_event(event, false)


func _dispatch_pointer_event(event: InputEvent, mark_handled: bool) -> void:
	# iOS Safari 双事件去重：触摸进来时开 500ms 窗口，期间丢弃浏览器合成的鼠标事件
	var now_ms := Time.get_ticks_msec()
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_swallow_until_ms = now_ms + _TOUCH_SWALLOW_WINDOW_MS
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if now_ms < _touch_swallow_until_ms:
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_pointer(event.position, "down")
		if mark_handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_pointer(event.position, "up")
		if mark_handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_handle_pointer(event.position, "move")
	elif event is InputEventScreenTouch and event.pressed:
		_handle_pointer(event.position, "down")
		if mark_handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		_handle_pointer(event.position, "up")
		if mark_handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_handle_pointer(event.position, "move")


func _should_start_virtual_joystick(screen_pos: Vector2) -> bool:
	if state != GameState.PLAYING or virtual_joystick == null:
		return false
	if player.state != BattlePlayer.State.IDLE:
		return false
	var world_pos := screen_to_world(screen_pos)
	if not is_in_bounds(world_pos):
		return false
	return world_pos.distance_to(player.home_position) > player.get_trigger_radius()


func _try_feed_virtual_joystick(screen_pos: Vector2, phase: String) -> bool:
	if state != GameState.PLAYING or virtual_joystick == null:
		return false
	if phase == "down":
		if not _should_start_virtual_joystick(screen_pos):
			return false
	elif not virtual_joystick.is_active():
		return false
	return virtual_joystick.feed_pointer(screen_pos, phase)


func _handle_pointer(screen_pos: Vector2, phase: String) -> void:
	if state == GameState.WAIT_START:
		if phase == "down":
			_exit_wait_start_and_begin()
		return
	if state == GameState.BUILD_HOUSE:
		if phase == "down" and build_house:
			build_house.handle_drop_click()
		return
	if state == GameState.ATTR_FORGE:
		if phase == "down" and attr_forge:
			attr_forge.handle_drop_click()
		return
	if state == GameState.MENU:
		if phase == "down":
			hud.hide_message()
			_enter_wait_start()
		return
	if state == GameState.FAIL or state == GameState.COMPLETE:
		if phase == "down":
			hud.hide_message()
			_enter_wait_start()
		return
	if state == GameState.STAGE_FAIL:
		return
	if state == GameState.REWARD_ROOM:
		return
	if _lobby_entry_intro_active:
		return
	if state == GameState.LEVEL_UP:
		return
	if state == GameState.PAUSED or state == GameState.FAIL_DEATH:
		return
	if phase == "down" and hud.is_pause_button_at(screen_pos):
		return
	if _try_feed_virtual_joystick(screen_pos, phase):
		return
	match phase:
		"down":
			path_input.handle_start(screen_pos)
		"move":
			path_input.handle_move(screen_pos)
		"up":
			path_input.handle_end()


func screen_to_world(screen_pos: Vector2) -> Vector2:
	var xform := get_viewport().get_canvas_transform()
	return xform.affine_inverse() * screen_pos


func is_in_bounds(pos: Vector2) -> bool:
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	return pos.x >= 0 and pos.y >= 0 and pos.x <= w and pos.y <= h


func spawn_arrow(
	from_pos: Vector2,
	to_pos: Vector2,
	damage: int,
	speed: float = 85.0,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn(self, from_pos, to_pos, damage, speed, effect_key, tint)


func spawn_enemy_spread(
	from_pos: Vector2,
	to_pos: Vector2,
	damage: int,
	speed: float,
	count: int,
	spread_deg: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn_spread(
		self,
		from_pos,
		to_pos,
		damage,
		speed,
		count,
		spread_deg,
		effect_key,
		tint
	)


func spawn_enemy_cross(
	from_pos: Vector2,
	damage: int,
	speed: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn_cross(self, from_pos, damage, speed, effect_key, tint)


func spawn_enemy_bounce(
	from_pos: Vector2,
	to_pos: Vector2,
	damage: int,
	speed: float,
	bounces: int,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn_bounce(
		self,
		from_pos,
		to_pos,
		damage,
		speed,
		bounces,
		effect_key,
		tint
	)


func spawn_enemy_snake(
	from_pos: Vector2,
	to_pos: Vector2,
	damage: int,
	speed: float,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn_snake(self, from_pos, to_pos, damage, speed, effect_key, tint)


func spawn_enemy_radial(
	from_pos: Vector2,
	damage: int,
	speed: float,
	count: int,
	effect_key: String = "",
	tint: Color = Color.WHITE
) -> void:
	EnemyArrowScript.spawn_radial(self, from_pos, damage, speed, count, effect_key, tint)


func _clear_projectiles() -> void:
	if projectiles == null:
		return
	for child in projectiles.get_children():
		if is_instance_valid(child):
			child.queue_free()


func _update_enemy_arrows(delta: float) -> void:
	if projectiles == null:
		return
	for child in projectiles.get_children():
		if child is EnemyArrow:
			(child as EnemyArrow).update_arrow(delta)


func block_projectiles_on_path_segment(
	from: Vector2,
	to: Vector2,
	segment_index: int,
	actor: BattlePlayer,
	offsets: Array = [0.0],
) -> void:
	if projectiles == null or actor == null:
		return
	if from.distance_squared_to(to) < 0.000001:
		return
	var block_pad := actor.get_effective_radius() * 0.38
	var seg_dir: Vector2 = (to - from).normalized()
	var normal: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
	for child in projectiles.get_children():
		if not child is EnemyArrow:
			continue
		var arrow := child as EnemyArrow
		if not arrow.is_alive():
			continue
		var key := "%d:%d" % [arrow.get_instance_id(), segment_index]
		if actor.hit_projectiles_this_attack.has(key):
			continue
		var blocked: bool = false
		var hit_from: Vector2 = from
		var hit_to: Vector2 = to
		for off in offsets:
			var a: Vector2 = from + normal * float(off)
			var b: Vector2 = to + normal * float(off)
			var dist := MathUtils.point_segment_distance(arrow.global_position, a, b)
			if dist <= EnemyArrow.HIT_RADIUS + block_pad:
				blocked = true
				hit_from = a
				hit_to = b
				break
		if not blocked:
			continue
		actor.hit_projectiles_this_attack[key] = true
		arrow.destroy_blocked(hit_from, hit_to)
