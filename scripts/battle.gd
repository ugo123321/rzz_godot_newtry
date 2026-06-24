extends Node2D
class_name BattleController

const SummonAbilityManagerScript = preload("res://scripts/core/summon_ability_manager.gd")
const SwordOrbitManagerScript = preload("res://scripts/core/sword_orbit_manager.gd")
const ParticleManagerScript = preload("res://scripts/core/particle_manager.gd")
const BloodStainManagerScript = preload("res://scripts/core/blood_stain_manager.gd")
const GroundEffectManagerScript = preload("res://scripts/core/ground_effect_manager.gd")
const LevelOverlayScript = preload("res://scripts/ui/level_overlay.gd")
const CombatAfterimagesScript = preload("res://scripts/ui/combat_afterimages.gd")
const EquipmentDropFxScript = preload("res://scripts/ui/equipment_drop_fx.gd")
const SakuraSystemScript = preload("res://scripts/systems/sakura_system.gd")
const GrassSystemScript = preload("res://scripts/systems/grass_system.gd")
const EnemyArrowScript = preload("res://scripts/entities/enemy_arrow.gd")
const RewardWheelPopupScript = preload("res://scripts/ui/reward_wheel_popup.gd")
const VirtualJoystickScript = preload("res://scripts/ui/virtual_joystick.gd")
const TreeSpawnerScript = preload("res://scripts/systems/tree_spawner.gd")
const PortalSpawnerScript = preload("res://scripts/systems/portal_spawner.gd")
const BuildHouseDirectorScript = preload("res://scripts/systems/build_house_director.gd")
const WoodDropScript = preload("res://scripts/entities/wood_drop.gd")

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const MAIN_SCENE := "res://scenes/main.tscn"

@export var stage_index := 0

var state := GameState.MENU
var time_scale := 1.0
var pending_stage_clear := false

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
var damage_overlay: DamageNumbersOverlay
var equipment_drop_fx: EquipmentDropFxOverlay
var afterimages_overlay
var terrain: TerrainBackground
var pause_menu: PauseMenu
var fail_animator: StageFailAnimator
var particles
var blood_stains
var ground_effects
var level_overlay
var grass_field
var sakura_field
var reward_wheel_popup
var _pending_reward_stage_index := -1
var tree_spawner
var portal_spawner
var build_house
var tree_container: Node2D
var portal_container: Node2D
var wood_drops_container: Node2D
var build_house_container: Node2D
var _portal_paused_remaining := -1.0
var _initial_camera_y := 640.0
var _initial_camera_x := 360.0
var _portal_active_pause := false
var _current_chapter_id := -1
var hit_fx_overlay: Node2D
var under_monster_fx_overlay: Node2D
var above_monster_fx_overlay: Node2D

var stage_intro_timer := 0.0
var _lobby_entry_intro_active := false
var _lobby_intro_phase := ""
var _lobby_intro_timer := 0.0
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
	damage_overlay = DamageNumbersOverlay.new()
	damage_overlay.name = "DamageNumbers"
	damage_overlay.z_index = 50
	add_child(damage_overlay)
	damage_overlay.setup(combat)
	equipment_drop_fx = EquipmentDropFxScript.new()
	equipment_drop_fx.name = "EquipmentDropFx"
	add_child(equipment_drop_fx)
	afterimages_overlay = CombatAfterimagesScript.new()
	afterimages_overlay.name = "CombatAfterimages"
	afterimages_overlay.z_index = 46
	add_child(afterimages_overlay)
	afterimages_overlay.setup(combat, player)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	$UI.add_child(pause_menu)
	pause_menu.setup(self)
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
	portal_container.z_index = 4
	$Entities.add_child(portal_container)
	build_house_container = Node2D.new()
	build_house_container.name = "BuildHouse"
	build_house_container.z_index = 30
	build_house_container.visible = false
	add_child(build_house_container)
	tree_spawner = TreeSpawnerScript.new()
	tree_spawner.name = "TreeSpawner"
	add_child(tree_spawner)
	portal_spawner = PortalSpawnerScript.new()
	portal_spawner.name = "PortalSpawner"
	add_child(portal_spawner)
	build_house = BuildHouseDirectorScript.new()
	build_house.name = "BuildHouseDirector"
	build_house_container.add_child(build_house)
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
	terrain.setup_for_stage(0, _get_safe_zone())
	_sync_background_layer()
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
	var zoom := maxf(1.0, round(float(GameConfig.get_tuning("camera_zoom", 1.0))))
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2(w * 0.5, h * 0.5)
	player.global_position = Vector2(w * 0.5, h * 0.58)
	player.home_position = player.global_position


func start_game() -> void:
	stage_index = 0
	_current_chapter_id = -1
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
	_clear_projectiles()
	state = GameState.MENU
	hud.show_message("点击屏幕开始", 999.0)
	intro_label.text = "忍者斩"


func _enter_wait_start() -> void:
	stage_index = 0
	_current_chapter_id = -1
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
	if tree_spawner:
		tree_spawner.begin(self)
	if portal_spawner:
		portal_spawner.reset()
	_clear_projectiles()
	# Pre-populate the battle background so the player sees the actual scene
	_apply_stage_meta(false)
	if terrain:
		terrain.setup_for_stage(stage_index, _get_safe_zone())
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
	_clear_projectiles()
	intro_label.visible = false
	hud.hide_message()
	_start_run()
	call_deferred("_start_lobby_battle_intro")


func _start_lobby_battle_intro() -> void:
	_lobby_entry_intro_active = true
	state = GameState.STAGE_INTRO
	intro_label.text = "战斗开始"
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


func _trigger_lobby_start_upgrade() -> void:
	if experience == null:
		state = GameState.PLAYING
		return
	state = GameState.PLAYING
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
		_sync_background_layer()
		_refresh_stage_ambience()
	_apply_stage_meta(true)
	if not skip_world_setup and tree_spawner:
		tree_spawner.begin(self)
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
			"进入下一关",
			"已建 %.1fm / %dm" % [height_m, int(chapter_target)],
			Callable(self, "_advance_after_build"),
			0.55, 0.6, 0.55
		)


func _announce_chapter_complete(chapter_id: int, height_m: float, target_m: float) -> void:
	if level_overlay:
		level_overlay.show_phase_fade(
			"第%d章 完成！" % chapter_id,
			"塔高 %.1fm / 目标 %dm" % [height_m, int(target_m)],
			Callable(self, "_back_to_menu_after_chapter"),
			0.8, 1.5, 0.8
		)


func _announce_chapter_fail(chapter_id: int, height_m: float, target_m: float) -> void:
	if level_overlay:
		level_overlay.show_phase_fade(
			"第%d章 未达成" % chapter_id,
			"塔高 %.1fm / 目标 %dm" % [height_m, int(target_m)],
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
		tree_spawner.begin(self)
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
	_portal_active_pause = true
	if portal_spawner:
		portal_spawner.stop()
	if portal_node and portal_node.has_method("queue_free"):
		portal_node.queue_free()
	state = GameState.REWARD_ROOM
	_pending_reward_stage_index = -2  # sentinel: portal-driven
	if reward_wheel_popup:
		reward_wheel_popup.show_for_stage(stage_index)


func _resume_from_portal_reward() -> void:
	state = GameState.PLAYING
	_portal_active_pause = false
	if portal_spawner:
		portal_spawner.begin()


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
		hud.show_message("调试跳关已应用", 1.5)
		return
	spawner.spawn_stage(stage_index, self)
	if terrain:
		terrain.setup_for_stage(stage_index, _get_safe_zone())
	_sync_background_layer()
	_refresh_stage_ambience()
	_apply_stage_meta(true)
	state = GameState.PLAYING
	intro_label.visible = false
	hud.hide_message()
	hud.show_message("调试跳关已应用", 1.5)


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
	hud.set_stage_text(str(stage.get("display_name", "第%d关" % (stage_index + 1))))


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
	var w := float(GameConfig.get_tuning("logical_width", 720))
	var h := float(GameConfig.get_tuning("logical_height", 1280))
	var play_bottom := PixelUiHelper.get_play_area_bottom(h)
	grass_field.init_field(w, h, play_bottom, _get_safe_zone())


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


func exit_bullet_time(cancelled: bool) -> void:
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
	dim_overlay.z_index = 0
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
	hud.show_message("继续战斗", 1.0)


func pause_game() -> void:
	if _lobby_entry_intro_active:
		return
	if state in [GameState.MENU, GameState.WAIT_START, GameState.FAIL_DEATH, GameState.STAGE_CLEAR, GameState.COMPLETE, GameState.FAIL, GameState.STAGE_FAIL, GameState.LEVEL_UP, GameState.BUILD_HOUSE, GameState.BUILD_HOUSE_DONE]:
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
	experience.on_monster_killed(monster)
	if player:
		player.on_enemy_killed(monster.global_position)
	var dropped := LobbyState.try_drop_random_equipment()
	if not dropped.is_empty() and equipment_drop_fx and is_instance_valid(monster):
		equipment_drop_fx.spawn(dropped, monster.global_position)


func _on_upgrade_picked(_index: int) -> void:
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
	pending_stage_clear = false
	_advance_to_next_stage()


func _advance_to_next_stage() -> void:
	# Legacy entrypoint kept for compatibility, but countdown flow drives progression now.
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
		tree_spawner.begin(self)
	if portal_spawner:
		portal_spawner.begin()
	state = GameState.PLAYING
	EventBus.stage_started.emit(stage_index)


func _try_enter_reward_room(next_stage_index: int) -> bool:
	var stage := GameConfig.get_stage(next_stage_index)
	if stage.is_empty():
		return false
	if str(stage.get("room_type", "")) != "reward":
		return false
	var room_choices: Array = stage.get("reward_rooms", [])
	var room := "wheel"
	if not room_choices.is_empty():
		room = str(room_choices[randi() % room_choices.size()])
	if room != "wheel":
		room = "wheel"
	_pending_reward_stage_index = next_stage_index
	_enter_reward_room_wheel()
	return true


func _enter_reward_room_wheel() -> void:
	state = GameState.REWARD_ROOM
	_clear_stage_transition_presentation(true)
	spawner.reset()
	_apply_stage_meta(false)
	if reward_wheel_popup:
		reward_wheel_popup.show_for_stage(_pending_reward_stage_index)
	hud.show_message("奖励关：转盘房", 1.8)


func _on_reward_wheel_finished(reward_text: String) -> void:
	if _pending_reward_stage_index == -2:
		# Portal-driven reward inside the battle
		if not reward_text.is_empty():
			hud.show_message("获得奖励：%s" % reward_text, 1.6)
		_pending_reward_stage_index = -1
		_resume_from_portal_reward()
		return
	if _pending_reward_stage_index < 0:
		return
	if not reward_text.is_empty():
		hud.show_message("获得奖励：%s" % reward_text, 1.6)
	stage_index = _pending_reward_stage_index + 1
	if stage_index >= GameConfig.stages.size():
		_clear_stage_transition_presentation(true)
		state = GameState.COMPLETE
		if level_overlay:
			level_overlay.show_game_complete()
		hud.hide_message()
		_pending_reward_stage_index = -1
		return
	_clear_stage_transition_presentation(stage_index > 0)
	spawner.spawn_stage(stage_index, self)
	_apply_stage_meta(false)
	if tree_spawner:
		tree_spawner.begin(self)
	if portal_spawner:
		portal_spawner.begin()
	state = GameState.PLAYING
	EventBus.stage_started.emit(stage_index)
	_pending_reward_stage_index = -1


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
			if portal_spawner and not _portal_active_pause:
				portal_spawner.update(delta, self)
		GameState.BUILD_HOUSE:
			if build_house:
				build_house.update(delta)
			if level_overlay:
				level_overlay.update_overlay(delta)
		GameState.BUILD_HOUSE_DONE:
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
	if spawner.all_dead() and not spawner.is_spawning() and not combat.is_resolving() and not combat.has_combat_presentation() and player.state == BattlePlayer.State.IDLE and not abilities.has_active_fx() and not summon_fx_active:
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
	if particles:
		particles.clear()
	if blood_stains:
		blood_stains.clear()
	if equipment_drop_fx:
		equipment_drop_fx.clear()
	_clear_projectiles()
	if ground_effects:
		ground_effects.reset()
	_queue_combat_fx_redraw()


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


func _pointer_flow_uses_early_input() -> bool:
	return state in [
		GameState.MENU,
		GameState.STAGE_INTRO,
		GameState.WAIT_START,
		GameState.BUILD_HOUSE,
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
