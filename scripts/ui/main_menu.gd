extends Control
class_name MainMenu

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")
const ScoutRewardPopupT = preload("res://scripts/ui/scout_reward_popup.gd")
const LOADING_SCENE := "res://scenes/ui/loading_screen.tscn"

enum Tab {
	GACHA,
	EQUIPMENT,
	STAGE,
	DUNGEON,
	ACHIEVEMENT,
}

const TAB_COUNT := 5
const DEFAULT_TAB := Tab.STAGE

@export_group("Background")
@export var background_texture: Texture2D
@export var bottom_bar_texture: Texture2D

@export_group("Tab Icons")
@export var icon_gacha: Texture2D
@export var icon_equipment: Texture2D
@export var icon_stage: Texture2D
@export var icon_dungeon: Texture2D
@export var icon_achievement: Texture2D
@export var tab_focus_texture: Texture2D
@export var tab_center_focus_texture: Texture2D
@export var tab_rail_texture: Texture2D
@export var tab_slot_texture: Texture2D
@export var tab_slot_active_texture: Texture2D
@export var tab_slot_center_texture: Texture2D
@export var tab_slot_center_active_texture: Texture2D

@export_group("Stage Panel")
@export var play_button_texture: Texture2D
@export var chapter_prev_texture: Texture2D
@export var chapter_next_texture: Texture2D
@export var stage_icon_texture: Texture2D
@export var stage_ground_texture: Texture2D
@export var stage_sky_glow_texture: Texture2D
@export var stage_sky_glow_scroll_speed := 22.0
@export var stage_icon_base_scale := 1.0
@export var stage_icon_pulse_amount := 0.035
@export var stage_icon_pulse_speed := 1.1
@export var tab_selected_lift := 14.0
@export var tab_lift_duration := 0.22
@export var tab_focus_pulse_speed := 4.2
@export var start_button_pressed_scale := 0.9
@export var start_button_bottom_clearance := 28.0
@export_group("Top Bar")
@export var top_money_bg_texture: Texture2D
@export var top_gold_icon_texture: Texture2D
@export var top_gem_icon_texture: Texture2D

@onready var _content: MarginContainer = $Content
@onready var _bottom_bar: Control = $BottomBar
@onready var _background: TextureRect = %Background
@onready var _bottom_bg: TextureRect = %BottomBg
@onready var _tab_focus: TextureRect = %TabFocus
@onready var _tab_rail: TextureRect = %TabRail
@onready var _tab_buttons: Array[TextureButton] = [
	%TabGacha, %TabEquipment, %TabStage, %TabDungeon, %TabAchievement,
]
@onready var _tab_icons: Array[TextureRect] = [
	%TabGacha/Icon, %TabEquipment/Icon, %TabStage/Icon, %TabDungeon/Icon, %TabAchievement/Icon,
]
@onready var _tab_labels: Array[Label] = [
	%TabGacha/TabLabel, %TabEquipment/TabLabel, %TabStage/TabLabel, %TabDungeon/TabLabel, %TabAchievement/TabLabel,
]
@onready var _top_gold_label: Label = $TopBarBg/MarginContainer/TopBar/GoldBar/Value
@onready var _top_gem_label: Label = $TopBarBg/MarginContainer/TopBar/GemBar/Value
@onready var _top_gold_bg: TextureRect = $TopBarBg/MarginContainer/TopBar/GoldBar/Bg
@onready var _top_gem_bg: TextureRect = $TopBarBg/MarginContainer/TopBar/GemBar/Bg
@onready var _top_gold_icon: TextureRect = $TopBarBg/MarginContainer/TopBar/GoldBar/Icon
@onready var _top_gem_icon: TextureRect = $TopBarBg/MarginContainer/TopBar/GemBar/Icon
@onready var _panels: Array[Control] = [
	%GachaPanel, %EquipmentPanel, %StagePanel, %DungeonPanel, %AchievementPanel,
]
@onready var _chapter_label: Label = %ChapterName
@onready var _chapter_desc: Label = %ChapterDesc
@onready var _start_button: TextureButton = %StartButton
@onready var _chapter_prev: TextureButton = %ChapterPrev
@onready var _chapter_next: TextureButton = %ChapterNext
@onready var _stage_viewport: Control = %StageViewport
@onready var _stage_icon_pivot: Control = %StageIconPivot
@onready var _stage_icon: TextureRect = %StageIcon
@onready var _stage_ground: TextureRect = %GroundStrip
@onready var _stage_sky_glow: TextureRect = %SkyGlow

var _current_tab := DEFAULT_TAB
var _chapter_list_index := 0
var _tab_focus_anim_time := 0.0
var _stage_icon_pulse_time := 0.0
var _start_button_pressed := false
var _tab_base_positions: Array[Vector2] = []
var _tab_lift_tweens: Array[Tween] = []
var _sky_glow_scroll_layer: Control
var _sky_glow_tiles: Array[TextureRect] = []
var _sky_glow_tile_width := 0.0
var _stage_icon_pulse_material: ShaderMaterial
var _scout_popup: ScoutRewardPopupT
var _scout_entry_button: Button
var _scout_entry_label: Label


func _ui_scale() -> float:
	return GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()


func _scaled(v: float) -> float:
	return v * _ui_scale()


func get_bottom_bar_height() -> float:
	if _bottom_bar == null:
		return 168.0
	var h := _bottom_bar.size.y
	if h > 0.0:
		return h
	return maxf(_bottom_bar.custom_minimum_size.y, 168.0)


func _sync_content_bottom_inset() -> void:
	if _content == null:
		return
	_content.offset_bottom = -get_bottom_bar_height()


func _apply_start_button_safe_margin() -> void:
	# 开始按钮位置以场景里 StartButtonWrap 的 offset 为准，不在运行时覆盖。
	pass


func _ready() -> void:
	_apply_default_textures()
	_apply_pixel_filter()
	PixelUi.apply_ui_font_tree(self)
	_sync_content_bottom_inset()
	call_deferred("_cache_stage_visual_state")
	_connect_signals()
	_connect_tab_row_layout()
	_setup_start_button()
	_setup_top_bar()
	_setup_scout_entry()
	_connect_top_bar_signals()
	_apply_static_texts()
	if not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	_refresh_chapter_display()


func _on_language_changed(_lang: String) -> void:
	_apply_static_texts()
	_refresh_chapter_display()


func _apply_static_texts() -> void:
	# 底部 5 个 tab label：抽奖 / 装备 / Battle / 副本 / 图鉴
	const TAB_KEYS := ["UI_MAIN_DRAW", "UI_MAIN_EQUIPMENT", "", "UI_MAIN_DUNGEONS", "UI_MAIN_GALLERY"]
	for i in _tab_labels.size():
		if i >= TAB_KEYS.size():
			continue
		var key: String = TAB_KEYS[i]
		if key == "":
			continue  # Stage tab 保留英文 "Battle"
		if _tab_labels[i] != null:
			_tab_labels[i].text = LanguageManager.tr_ui(key)
	# StartButton 内的 Label（"开始"）
	if _start_button != null:
		var label := _start_button.get_node_or_null("Label") as Label
		if label != null:
			label.text = LanguageManager.tr_ui("UI_MAIN_START")
	# 占位面板（抽奖/副本/成就 — "敬请期待"）
	var gacha_ph := get_node_or_null("Content/GachaPanel/Placeholder") as Label
	if gacha_ph != null:
		gacha_ph.text = LanguageManager.tr_ui("UI_MAIN_GACHA_PLACEHOLDER")
	var dungeon_ph := get_node_or_null("Content/DungeonPanel/Placeholder") as Label
	if dungeon_ph != null:
		dungeon_ph.text = LanguageManager.tr_ui("UI_MAIN_DUNGEON_PLACEHOLDER")
	var achieve_ph := get_node_or_null("Content/AchievementPanel/Placeholder") as Label
	if achieve_ph != null:
		achieve_ph.text = LanguageManager.tr_ui("UI_MAIN_ACHIEVE_PLACEHOLDER")
	# 侦察入口按钮 label
	if _scout_entry_label != null:
		_scout_entry_label.text = LanguageManager.tr_ui("UI_MAIN_SCOUT_BTN")


func _process(delta: float) -> void:
	_animate_stage_panel(delta)
	_animate_tab_focus(delta)


func _apply_default_textures() -> void:
	# 优先保留场景里已拖好的纹理，避免运行时被空 export 覆盖掉。
	background_texture = _resolve_texture(background_texture, _background, "res://assets/ui/home/bg_stage01.png")
	bottom_bar_texture = _resolve_texture(bottom_bar_texture, _bottom_bg, "res://assets/ui/battle/decoration_wave.png")
	tab_focus_texture = _resolve_texture(tab_focus_texture, _tab_focus, "res://assets/ui/home/menu_bottom_focus.png")
	tab_rail_texture = _resolve_texture(tab_rail_texture, _tab_rail, "")
	if bottom_bar_texture == null:
		bottom_bar_texture = _build_bottom_bar_texture()
	if tab_rail_texture == null:
		tab_rail_texture = _build_tab_rail_texture()
	if tab_focus_texture == null:
		tab_focus_texture = _build_tab_focus_texture(false)

	if icon_gacha == null:
		icon_gacha = _load_tex("res://assets/ui/icons/nav/icon_nav_gacha.png")
		if icon_gacha == null:
			icon_gacha = _load_tex("res://assets/ui/home/icon_shop.png")
		if icon_gacha == null:
			icon_gacha = _build_tab_icon_texture(Tab.GACHA)
	if icon_equipment == null:
		icon_equipment = _load_tex("res://assets/ui/icons/nav/icon_nav_equipment.png")
		if icon_equipment == null:
			icon_equipment = _load_tex("res://assets/ui/home/icon_bag.png")
		if icon_equipment == null:
			icon_equipment = _build_tab_icon_texture(Tab.EQUIPMENT)
	if icon_stage == null:
		icon_stage = _load_tex("res://assets/ui/icons/nav/icon_nav_battle.png")
		if icon_stage == null:
			icon_stage = _load_tex("res://assets/ui/home/icon_battle.png")
		if icon_stage == null:
			icon_stage = _build_tab_icon_texture(Tab.STAGE)
	if icon_dungeon == null:
		icon_dungeon = _load_tex("res://assets/ui/icons/nav/icon_nav_dungeon.png")
		if icon_dungeon == null:
			icon_dungeon = _load_tex("res://assets/ui/home/icon_map.png")
		if icon_dungeon == null:
			icon_dungeon = _build_tab_icon_texture(Tab.DUNGEON)
	if icon_achievement == null:
		icon_achievement = _load_tex("res://assets/ui/icons/nav/icon_nav_achievement.png")
		if icon_achievement == null:
			icon_achievement = _load_tex("res://assets/ui/home/icon_book.png")
		if icon_achievement == null:
			icon_achievement = _build_tab_icon_texture(Tab.ACHIEVEMENT)
	if tab_center_focus_texture == null:
		tab_center_focus_texture = _load_tex("res://assets/ui/home/menu_middle_focus.png")
		if tab_center_focus_texture == null:
			tab_center_focus_texture = _build_tab_focus_texture(true)
	if tab_slot_texture == null:
		tab_slot_texture = _load_tex("res://assets/ui/bottom/normal_button.png")
		if tab_slot_texture == null:
			tab_slot_texture = _load_tex("res://assets/ui/home/btn_white_bg.png")
		if tab_slot_texture == null:
			tab_slot_texture = _build_tab_slot_texture(false, false)
	if tab_slot_active_texture == null:
		tab_slot_active_texture = _load_tex("res://assets/ui/bottom/picked_button.png")
		if tab_slot_active_texture == null:
			tab_slot_active_texture = _load_tex("res://assets/ui/home/menu_bottom_focus_light.png")
		if tab_slot_active_texture == null:
			tab_slot_active_texture = _build_tab_slot_texture(false, true)
	if tab_slot_center_texture == null:
		tab_slot_center_texture = _load_tex("res://assets/ui/bottom/normal_button.png")
		if tab_slot_center_texture == null:
			tab_slot_center_texture = _load_tex("res://assets/ui/home/tab_center_blue.png")
		if tab_slot_center_texture == null:
			tab_slot_center_texture = _build_tab_slot_texture(true, false)
	if tab_slot_center_active_texture == null:
		tab_slot_center_active_texture = _load_tex("res://assets/ui/bottom/picked_button.png")
		if tab_slot_center_active_texture == null:
			tab_slot_center_active_texture = _load_tex("res://assets/ui/home/menu_middle_focus.png")
		if tab_slot_center_active_texture == null:
			tab_slot_center_active_texture = _build_tab_slot_texture(true, true)
	if top_money_bg_texture == null:
		top_money_bg_texture = _load_tex("res://assets/ui/battle/money_bg.png")
	if top_gold_icon_texture == null:
		top_gold_icon_texture = _load_tex("res://assets/ui/icons/currency/icon_cur_gold.png")
	if top_gem_icon_texture == null:
		top_gem_icon_texture = _load_tex("res://assets/ui/icons/currency/icon_cur_gem.png")
	if play_button_texture == null:
		if _start_button != null and _start_button.texture_normal != null:
			play_button_texture = _start_button.texture_normal
		else:
			play_button_texture = _load_tex("res://assets/ui/battle/start_button.png")
	if chapter_prev_texture == null:
		chapter_prev_texture = _load_tex("res://assets/ui/home/arrow_prev.png")
	if chapter_next_texture == null:
		chapter_next_texture = _load_tex("res://assets/ui/home/arrow_next.png")
	if stage_icon_texture == null:
		if _stage_icon != null and _stage_icon.texture != null:
			stage_icon_texture = _stage_icon.texture
		else:
			stage_icon_texture = _build_default_portal_texture()
	stage_ground_texture = _resolve_texture(
		stage_ground_texture, _stage_ground, "res://assets/ui/home/bg_stage01_bottom.png"
	)
	stage_sky_glow_texture = _resolve_texture(
		stage_sky_glow_texture, _stage_sky_glow, "res://assets/ui/home/sky_light.png"
	)
	if background_texture != null:
		_background.texture = background_texture
	if bottom_bar_texture != null:
		_bottom_bg.texture = bottom_bar_texture
	if tab_focus_texture != null:
		_tab_focus.texture = tab_focus_texture
	if tab_rail_texture != null:
		_tab_rail.texture = tab_rail_texture
	_sync_background_fallback()

	var icons := [icon_gacha, icon_equipment, icon_stage, icon_dungeon, icon_achievement]
	for i in TAB_COUNT:
		if i < _tab_icons.size():
			_set_texture_rect_texture(_tab_icons[i], icons[i])
		else:
			_set_tab_icon(_tab_buttons[i], icons[i])

	_apply_start_button_textures()
	_set_button_texture(_chapter_prev, chapter_prev_texture)
	_set_button_texture(_chapter_next, chapter_next_texture)
	_set_texture_rect_texture(_stage_icon, stage_icon_texture)
	_set_texture_rect_texture(_stage_ground, stage_ground_texture)
	_set_texture_rect_texture(_stage_sky_glow, stage_sky_glow_texture)
	_sync_sky_glow_tile_textures()
	_apply_top_bar_textures()


# v1.1 抗锯齿：UI 图默认 LINEAR（高清美术），只有装备物品 icon（BagSlot/SlotXxx 里的 ItemIcon）
# 是像素艺术要保持 NEAREST。判断依据：TextureRect 的 name == "ItemIcon" 或父节点是 BagSlot* / Slot* TextureButton。
func _apply_pixel_filter() -> void:
	for node in _collect_texture_nodes(self):
		if not (node is TextureRect or node is TextureButton):
			continue
		if _should_keep_nearest(node):
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _should_keep_nearest(node: Node) -> bool:
	# 装备物品图标（像素艺术）保持 NEAREST
	if str(node.name) == "ItemIcon":
		return true
	# 保留原来 _stage_icon 的 LINEAR 逻辑（stage_icon 是关卡图，本来就是 LINEAR，跳过）
	return false


func _collect_texture_nodes(root: Node) -> Array:
	var result: Array = []
	if root is TextureRect or root is TextureButton:
		result.append(root)
	for child in root.get_children():
		result.append_array(_collect_texture_nodes(child))
	return result


func _connect_tab_row_layout() -> void:
	var tab_row := get_node_or_null("BottomBar/TabRow") as Control
	if tab_row == null:
		return
	if not tab_row.resized.is_connected(_refresh_tab_layout_state):
		tab_row.resized.connect(_refresh_tab_layout_state)


func _connect_signals() -> void:
	for i in TAB_COUNT:
		_tab_buttons[i].pressed.connect(_on_tab_pressed.bind(i))
	_chapter_prev.pressed.connect(_on_chapter_prev)
	_chapter_next.pressed.connect(_on_chapter_next)
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.button_down.connect(_on_start_button_down)
	_start_button.button_up.connect(_on_start_button_up)


func _on_tab_pressed(tab_index: int) -> void:
	_select_tab(tab_index)


func _select_tab(tab_index: int) -> void:
	_current_tab = clampi(tab_index, 0, TAB_COUNT - 1)
	for i in TAB_COUNT:
		var panel := _panels[i] if i < _panels.size() else null
		if panel != null:
			panel.visible = i == _current_tab
	_apply_tab_button_visuals()
	call_deferred("_refresh_tab_layout_state")
	call_deferred("_update_tab_focus")


func _update_tab_focus() -> void:
	if _tab_focus == null:
		return
	# 已改为仅使用页签本身的选中样式，不再显示额外的缩放框。
	_tab_focus.visible = false
	_tab_focus.scale = Vector2.ONE


func _apply_tab_button_visuals() -> void:
	for i in TAB_COUNT:
		var selected := i == _current_tab
		var btn := _tab_buttons[i]
		var icon := _tab_icons[i] if i < _tab_icons.size() else null
		var label := _tab_labels[i] if i < _tab_labels.size() else null
		_set_tab_slot_texture(btn, i, selected)
		btn.modulate = Color.WHITE
		btn.scale = Vector2.ONE
		if icon != null:
			icon.modulate = Color.WHITE if selected else Color(0.78, 0.82, 0.9)
		if label != null and label.visible:
			label.modulate = Color.WHITE if selected else Color(0.76, 0.84, 0.9)
	_animate_tab_lifts()


func _animate_tab_lifts(immediate: bool = false) -> void:
	_ensure_tab_lift_tween_slots()
	var duration := maxf(tab_lift_duration, 0.001)
	for i in TAB_COUNT:
		var btn := _tab_buttons[i]
		if btn == null or i >= _tab_base_positions.size():
			continue
		var base_pos := _tab_base_positions[i]
		var target_pos := base_pos + Vector2(0.0, -tab_selected_lift if i == _current_tab else 0.0)
		if _tab_lift_tweens[i] != null and _tab_lift_tweens[i].is_valid():
			_tab_lift_tweens[i].kill()
		if immediate or is_equal_approx(duration, 0.0):
			btn.position = target_pos
			continue
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(btn, "position", target_pos, duration)
		_tab_lift_tweens[i] = tween


func _ensure_tab_lift_tween_slots() -> void:
	if _tab_lift_tweens.size() == TAB_COUNT:
		return
	_tab_lift_tweens.clear()
	_tab_lift_tweens.resize(TAB_COUNT)


func _reset_tab_buttons_to_layout() -> void:
	_ensure_tab_lift_tween_slots()
	for i in TAB_COUNT:
		var btn := _tab_buttons[i]
		if btn == null:
			continue
		if _tab_lift_tweens[i] != null and _tab_lift_tweens[i].is_valid():
			_tab_lift_tweens[i].kill()
		btn.scale = Vector2.ONE
		if i < _tab_base_positions.size():
			btn.position = _tab_base_positions[i]


func _refresh_tab_layout_state() -> void:
	for btn in _tab_buttons:
		if btn == null:
			continue
		btn.pivot_offset = Vector2(floorf(btn.size.x * 0.5), btn.size.y)
	_reset_tab_buttons_to_layout()
	_tab_base_positions.clear()
	for btn in _tab_buttons:
		_tab_base_positions.append(btn.position if btn != null else Vector2.ZERO)
	_apply_tab_button_visuals()
	_apply_start_button_safe_margin()


func _set_tab_slot_texture(btn: TextureButton, index: int, selected: bool) -> void:
	if btn == null:
		return
	var center := index == Tab.STAGE
	var tex: Texture2D = null
	if center:
		tex = tab_slot_center_active_texture if selected else tab_slot_center_texture
	else:
		tex = tab_slot_active_texture if selected else tab_slot_texture
	if tex == null:
		return
	btn.texture_normal = tex
	btn.texture_pressed = tex
	btn.texture_hover = tex


func _animate_tab_focus(delta: float) -> void:
	if _tab_focus == null:
		return
	_tab_focus.visible = false
	_tab_focus.scale = Vector2.ONE


func _on_chapter_prev() -> void:
	if GameConfig.chapters.is_empty():
		return
	_chapter_list_index = (_chapter_list_index - 1 + GameConfig.chapters.size()) % GameConfig.chapters.size()
	_refresh_chapter_display()


func _on_chapter_next() -> void:
	if GameConfig.chapters.is_empty():
		return
	_chapter_list_index = (_chapter_list_index + 1) % GameConfig.chapters.size()
	_refresh_chapter_display()


func _refresh_chapter_display() -> void:
	if GameConfig.chapters.is_empty():
		_chapter_label.text = LanguageManager.tr_ui("UI_MAIN_NO_CHAPTER")
		_chapter_desc.text = ""
		return
	_chapter_list_index = clampi(_chapter_list_index, 0, GameConfig.chapters.size() - 1)
	var chapter: Dictionary = GameConfig.chapters[_chapter_list_index]
	var name_text := LanguageManager.localize_field(chapter, "chapter_name_en", "chapter_name")
	if name_text.is_empty():
		name_text = LanguageManager.tr_ui("UI_MAIN_DEFAULT_CHAPTER")
	_chapter_label.text = name_text
	_chapter_desc.text = LanguageManager.localize_field(chapter, "description_en", "description")


func _get_selected_chapter_id() -> int:
	if GameConfig.chapters.is_empty():
		return 1
	return int(GameConfig.chapters[_chapter_list_index].get("chapter_id", 1))


func _first_stage_index_for_chapter(chapter_id: int) -> int:
	for i in range(GameConfig.stages.size()):
		var stage: Dictionary = GameConfig.stages[i]
		if int(stage.get("chapter_id", 0)) == chapter_id:
			return i
	return 0


func _on_start_pressed() -> void:
	_start_button_pressed = false
	_update_start_button_scale()
	var chapter_id := _get_selected_chapter_id()
	var stage_idx := _first_stage_index_for_chapter(chapter_id)
	LobbyState.request_battle_launch(stage_idx)
	get_tree().change_scene_to_file(LOADING_SCENE)


func _setup_start_button() -> void:
	if _start_button == null:
		return
	_start_button.focus_mode = Control.FOCUS_NONE
	call_deferred("_cache_start_button_pivot")


func _cache_start_button_pivot() -> void:
	if _start_button == null:
		return
	_start_button.pivot_offset = Vector2(
		floorf(_start_button.size.x * 0.5),
		floorf(_start_button.size.y)
	)
	_update_start_button_scale()


func _apply_start_button_textures() -> void:
	if _start_button == null:
		return
	var normal := play_button_texture
	if normal == null:
		normal = _build_start_adventure_button_texture(false)
	var pressed_tex := normal
	if play_button_texture == null:
		pressed_tex = _build_start_adventure_button_texture(true)
	_start_button.texture_normal = normal
	_start_button.texture_pressed = pressed_tex
	_start_button.texture_hover = normal
	_start_button.texture_disabled = normal


func _on_start_button_down() -> void:
	_start_button_pressed = true
	_update_start_button_scale()


func _on_start_button_up() -> void:
	_start_button_pressed = false
	_update_start_button_scale()


func _update_start_button_scale() -> void:
	if _start_button == null:
		return
	var scale := start_button_pressed_scale if _start_button_pressed else 1.0
	_start_button.scale = Vector2.ONE * scale
	if _start_button_pressed:
		_start_button.modulate = Color(0.92, 0.92, 0.96)
	else:
		_start_button.modulate = Color.WHITE


func _animate_stage_panel(delta: float) -> void:
	if _panels.is_empty() or not _panels[Tab.STAGE].visible:
		return

	if _stage_icon_pulse_material != null:
		_stage_icon_pulse_time += delta * stage_icon_pulse_speed
		# 只在基准尺寸以下缩放，避免放大时 UV 裁切贴图顶部。
		var pulse := (1.0 + sin(_stage_icon_pulse_time * TAU)) * 0.5
		_stage_icon_pulse_material.set_shader_parameter(
			"scale_factor", stage_icon_base_scale * (1.0 - pulse * stage_icon_pulse_amount)
		)
	if _stage_icon_pivot != null:
		_stage_icon_pivot.rotation = 0.0
	_animate_sky_glow_scroll(delta)


func _setup_sky_glow_scroll() -> void:
	if _stage_sky_glow == null or _stage_viewport == null:
		return
	if _sky_glow_scroll_layer != null:
		_refresh_sky_glow_scroll_layout()
		return

	_stage_viewport.clip_contents = false
	if not _stage_viewport.resized.is_connected(_refresh_sky_glow_scroll_layout):
		_stage_viewport.resized.connect(_refresh_sky_glow_scroll_layout)

	var layer := Control.new()
	layer.name = "SkyGlowScroll"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.clip_contents = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_viewport.add_child(layer)
	_stage_viewport.move_child(layer, 0)

	var sky := _stage_sky_glow
	sky.get_parent().remove_child(sky)
	layer.add_child(sky)
	sky.name = "SkyGlowA"
	sky.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sky.grow_horizontal = Control.GROW_DIRECTION_END
	sky.grow_vertical = Control.GROW_DIRECTION_END

	var sky_glow_copy := sky.duplicate() as TextureRect
	sky_glow_copy.name = "SkyGlowB"
	layer.add_child(sky_glow_copy)

	_sky_glow_scroll_layer = layer
	_sky_glow_tiles = [sky, sky_glow_copy]
	_refresh_sky_glow_scroll_layout()


func _refresh_sky_glow_scroll_layout() -> void:
	if _sky_glow_tiles.size() < 2 or _stage_viewport == null:
		return
	var view_size := _stage_viewport.size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	_sky_glow_tile_width = view_size.x
	for tile in _sky_glow_tiles:
		tile.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		tile.size = view_size
	_sky_glow_tiles[0].position = Vector2.ZERO
	_sky_glow_tiles[1].position = Vector2(_sky_glow_tile_width, 0.0)


func _sync_sky_glow_tile_textures() -> void:
	if _sky_glow_tiles.size() < 2 or stage_sky_glow_texture == null:
		return
	for tile in _sky_glow_tiles:
		tile.texture = stage_sky_glow_texture


func _animate_sky_glow_scroll(delta: float) -> void:
	if _sky_glow_tiles.size() < 2 or stage_sky_glow_scroll_speed <= 0.0:
		return
	if _panels.is_empty() or not _panels[Tab.STAGE].visible:
		return
	if _sky_glow_tile_width <= 0.0:
		_refresh_sky_glow_scroll_layout()
		return

	var dx := stage_sky_glow_scroll_speed * delta
	for tile in _sky_glow_tiles:
		tile.position.x += dx
	for i in 2:
		var tile := _sky_glow_tiles[i]
		if tile.position.x >= _sky_glow_tile_width:
			var other := _sky_glow_tiles[1 - i]
			tile.position.x = other.position.x - _sky_glow_tile_width


func _cache_stage_visual_state() -> void:
	if _stage_icon_pivot != null:
		_stage_icon_pivot.rotation = 0.0
	if _stage_icon != null:
		_stage_icon.scale = Vector2.ONE
		# 用 shader 做呼吸缩放，避免项目开启 snap_2d_transforms_to_pixel 时改 scale 产生抖动。
		_stage_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if _stage_icon_pulse_material == null:
			var shader := load("res://shaders/ui/stage_icon_pulse.gdshader") as Shader
			_stage_icon_pulse_material = ShaderMaterial.new()
			_stage_icon_pulse_material.shader = shader
			_stage_icon.material = _stage_icon_pulse_material
		_stage_icon_pulse_material.set_shader_parameter("scale_factor", stage_icon_base_scale)
	if _tab_focus != null:
		_tab_focus.pivot_offset = _tab_focus.size * 0.5
	if _start_button != null:
		_start_button.pivot_offset = Vector2(
			floorf(_start_button.size.x * 0.5),
			floorf(_start_button.size.y)
		)
		_update_start_button_scale()
	_sync_content_bottom_inset()
	_setup_sky_glow_scroll()
	_select_tab(DEFAULT_TAB)


func _setup_top_bar() -> void:
	if _top_gold_label != null:
		_top_gold_label.text = str(LobbyState.gold)
	if _top_gem_label != null:
		_top_gem_label.text = "0"


func _setup_scout_entry() -> void:
	# 侦察入口：作为 StagePanel/StageViewport 的子节点，锚定在 StartButton 上方约 60px。
	# 全代码构建 —— 不改 tscn，避免场景 diff。
	var viewport := get_node_or_null("Content/StagePanel/StageViewport") as Control
	if viewport == null:
		return
	var start_wrap := viewport.get_node_or_null("StartButtonWrap") as Control
	# 主按钮：显示"[图标] 侦察"
	_scout_entry_button = Button.new()
	_scout_entry_button.name = "ScoutEntryButton"
	_scout_entry_button.custom_minimum_size = Vector2(180, 68)
	_scout_entry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_scout_entry_button.focus_mode = Control.FOCUS_NONE
	PixelUi.apply_ui_font(_scout_entry_button)
	# 用 9-slice 主按钮样式（暖色调，与开始按钮配色一致但更小）
	UiStyle.apply_primary_button(_scout_entry_button, Color("#8fb078"), 10)
	viewport.add_child(_scout_entry_button)
	# 锚定：横向居中，纵向落在 StartButton 上方
	_scout_entry_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_scout_entry_button.anchor_left = 0.5
	_scout_entry_button.anchor_right = 0.5
	_scout_entry_button.anchor_top = 1.0
	_scout_entry_button.anchor_bottom = 1.0
	_scout_entry_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scout_entry_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_scout_entry_button.offset_left = -90.0
	_scout_entry_button.offset_right = 90.0
	# 高度定位：贴在 StartButtonWrap.offset_top 上方 12px
	var wrap_top := -216.0
	if start_wrap != null:
		wrap_top = start_wrap.offset_top
	_scout_entry_button.offset_top = wrap_top - 80.0
	_scout_entry_button.offset_bottom = wrap_top - 12.0
	# 内嵌的中央 label（保留 unique 引用便于 i18n 刷新；不用 Button.text，方便配图标）
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scout_entry_button.add_child(row)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(36, 36)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _load_tex("res://assets/ui/icons/system/icon_detail.png")
	if icon.texture == null:
		icon.texture = _load_tex("res://assets/ui/icons/nav/icon_nav_dungeon.png")
	row.add_child(icon)
	_scout_entry_label = Label.new()
	_scout_entry_label.name = "ScoutLabel"
	_scout_entry_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	PixelUi.apply_ui_font(_scout_entry_label)
	_scout_entry_label.add_theme_font_size_override("font_size", 26)
	_scout_entry_label.add_theme_color_override("font_color", Color("#0f2410"))
	_scout_entry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_scout_entry_label)
	_scout_entry_button.pressed.connect(_on_scout_entry_pressed)
	# Popup 实例：挂在 MainMenu 根节点上，覆盖全屏
	_scout_popup = ScoutRewardPopupT.new()
	add_child(_scout_popup)
	_scout_popup.setup()


func _on_scout_entry_pressed() -> void:
	if _scout_popup == null:
		return
	_scout_popup.show_popup()


func _connect_top_bar_signals() -> void:
	if EventBus == null:
		return
	if not EventBus.gold_changed.is_connected(_on_gold_changed):
		EventBus.gold_changed.connect(_on_gold_changed)


func _on_gold_changed(total_gold: int) -> void:
	if _top_gold_label != null:
		_top_gold_label.text = str(maxi(0, total_gold))


func _apply_top_bar_textures() -> void:
	if _top_gold_bg != null and top_money_bg_texture != null:
		_top_gold_bg.texture = top_money_bg_texture
	if _top_gem_bg != null and top_money_bg_texture != null:
		_top_gem_bg.texture = top_money_bg_texture
	if _top_gold_icon != null and top_gold_icon_texture != null:
		_top_gold_icon.texture = top_gold_icon_texture
	if _top_gem_icon != null and top_gem_icon_texture != null:
		_top_gem_icon.texture = top_gem_icon_texture


func _build_start_adventure_button_texture(pressed: bool) -> Texture2D:
	var size := Vector2i(163, 48)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var y_shift := 2 if pressed else 0
	if not pressed:
		_draw_image_rect(image, Rect2i(5, 43, 154, 3), Color(0.05, 0.08, 0.14, 0.45))
		_draw_image_rect(image, Rect2i(6, 45, 150, 2), Color(0.12, 0.18, 0.28, 0.35))
	var panel := Rect2i(3, 3 + y_shift, 157, 38)
	var border := Color("#5a3410") if pressed else Color("#9a5c14")
	var fill := Color("#c88420") if pressed else Color("#efb840")
	var shine := Color("#d9a848") if pressed else Color("#ffe9a8")
	_draw_image_panel(image, panel, border, fill, 3)
	_draw_image_rect(image, Rect2i(panel.position.x + 6, panel.position.y + 4, panel.size.x - 12, 2), shine)
	_draw_image_rect(image, Rect2i(panel.position.x + 6, panel.position.y + panel.size.y - 5, panel.size.x - 12, 2), Color("#8a5518"))
	for x in range(panel.position.x + 8, panel.position.x + panel.size.x - 5, 5):
		var band := Color("#f5cc62") if not pressed else Color("#d39a2c")
		_draw_image_rect(image, Rect2i(x, panel.position.y + 7, 2, panel.size.y - 11), band)
	_draw_start_button_icon(image, Vector2i(panel.position.x + 10, panel.position.y + 13), pressed)
	_draw_image_rect(image, Rect2i(panel.position.x + panel.size.x - 11, panel.position.y + 6, 3, 3), Color("#fff2b8") if not pressed else Color("#e8c878"))
	_draw_image_rect(image, Rect2i(panel.position.x + 4, panel.position.y + panel.size.y - 6, 3, 3), Color("#6b4212"))
	return ImageTexture.create_from_image(image)


func _draw_start_button_icon(image: Image, origin: Vector2i, pressed: bool) -> void:
	var blade := Color("#fff6d8") if not pressed else Color("#e8d090")
	var guard_col := Color("#8a5518")
	_draw_image_rect(image, Rect2i(origin.x + 4, origin.y, 3, 14), blade)
	_draw_image_rect(image, Rect2i(origin.x + 1, origin.y + 12, 9, 2), guard_col)
	_draw_image_rect(image, Rect2i(origin.x + 3, origin.y + 14, 5, 4), Color("#c49446"))
	_draw_image_rect(image, Rect2i(origin.x + 4, origin.y + 18, 3, 2), Color("#6b4212"))


func _build_default_portal_texture() -> Texture2D:
	var tex_size := 224
	var image := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(tex_size * 0.5, tex_size * 0.5)
	var outer_r := 96.0
	var ring_r := 74.0
	var core_r := 56.0
	var dark_outline := Color("#1a2818")
	var stone_a := Color("#4a5c3a")
	var stone_b := Color("#667a52")
	var portal_a := Color("#6dd85a")
	var portal_b := Color("#2d6b3a")
	var portal_core := Color("#d4ffb0")
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(center)
			if d <= outer_r and d >= ring_r:
				var wave := sin(float(x) * 0.2 + float(y) * 0.14)
				image.set_pixel(x, y, stone_a if wave > 0.0 else stone_b)
				if d >= outer_r - 1.5 or d <= ring_r + 1.5:
					image.set_pixel(x, y, dark_outline)
			elif d < ring_r:
				var t := clampf(d / ring_r, 0.0, 1.0)
				var swirl := sin(d * 0.42 + atan2(p.y - center.y, p.x - center.x) * 3.2)
				var col := portal_b.lerp(portal_a, t)
				col = col.lerp(portal_core, clampf((1.0 - t) * 0.72 + (swirl + 1.0) * 0.08, 0.0, 1.0))
				if d <= core_r:
					col = col.lerp(portal_core, 0.32)
				image.set_pixel(x, y, col)
				if absf(d - ring_r) < 1.5:
					image.set_pixel(x, y, Color("#7a9a6a"))
				if absf(d - outer_r) < 1.5:
					image.set_pixel(x, y, Color("#8fb078"))
	return ImageTexture.create_from_image(image)


func _build_bottom_bar_texture() -> Texture2D:
	var bar_w := int(GameConfig.get_tuning("logical_width", 720))
	bar_w = maxi(1, bar_w)
	var bar_h := maxi(88, int(round(_scaled(88.0))))
	var image := Image.create(bar_w, bar_h, false, Image.FORMAT_RGBA8)
	image.fill(Color("#1a2140"))
	var top_h := maxi(2, int(round(_scaled(6.0))))
	var top_h2 := maxi(1, int(round(_scaled(2.0))))
	var bottom_h := maxi(4, int(round(_scaled(10.0))))
	_draw_image_rect(image, Rect2i(0, 0, bar_w, top_h), Color("#2a355f"))
	_draw_image_rect(image, Rect2i(0, top_h, bar_w, top_h2), Color("#3f4f86"))
	_draw_image_rect(image, Rect2i(0, bar_h - bottom_h, bar_w, bottom_h), Color("#131832"))
	return ImageTexture.create_from_image(image)


func _build_tab_rail_texture() -> Texture2D:
	var image := Image.create(324, 58, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_image_panel(image, Rect2i(0, 0, 324, 58), Color("#2c355e"), Color("#1a2142"), 3)
	_draw_image_rect(image, Rect2i(8, 8, 308, 3), Color("#475992"))
	return ImageTexture.create_from_image(image)


func _build_tab_focus_texture(center: bool) -> Texture2D:
	var size := Vector2i(78, 74) if center else Vector2i(68, 66)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border := Color("#f8e8a1") if center else Color("#c8dbff")
	var fill := Color("#5563d9") if center else Color("#3e4f9f")
	_draw_image_panel(image, Rect2i(0, 8, size.x, size.y - 8), border, fill, 3)
	_draw_image_rect(image, Rect2i(6, 12, size.x - 12, 3), Color("#8fa0ff"))
	return ImageTexture.create_from_image(image)


func _build_tab_slot_texture(center: bool, active: bool) -> Texture2D:
	var size := Vector2i(76, 90) if center else Vector2i(56, 72)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border := Color("#9aacd8")
	var fill := Color("#2a3566")
	if active:
		border = Color("#f0d98a")
		fill = Color("#4b57c7") if center else Color("#3f4fa8")
	_draw_image_panel(image, Rect2i(0, 0, size.x, size.y), border, fill, 3)
	_draw_image_rect(image, Rect2i(5, 4, size.x - 10, 2), Color("#b7c7f5") if not active else Color("#ffe9ae"))
	return ImageTexture.create_from_image(image)


func _build_tab_icon_texture(tab_index: int) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	match tab_index:
		Tab.GACHA:
			_draw_image_panel(image, Rect2i(7, 11, 18, 16), Color("#4a3a30"), Color("#dc9f4f"), 2)
			_draw_image_rect(image, Rect2i(12, 7, 8, 3), Color("#f0c37f"))
			_draw_image_rect(image, Rect2i(10, 9, 12, 2), Color("#4a3a30"))
		Tab.EQUIPMENT:
			_draw_image_panel(image, Rect2i(8, 7, 16, 20), Color("#293d55"), Color("#5d8ab9"), 2)
			_draw_image_rect(image, Rect2i(14, 4, 4, 4), Color("#9ec4ee"))
			_draw_image_rect(image, Rect2i(12, 15, 8, 6), Color("#9ec4ee"))
		Tab.STAGE:
			for i in range(10):
				_draw_image_rect(image, Rect2i(6 + i, 6 + i, 2, 2), Color("#d8e0f0"))
				_draw_image_rect(image, Rect2i(22 - i, 6 + i, 2, 2), Color("#d8e0f0"))
			_draw_image_rect(image, Rect2i(5, 19, 5, 3), Color("#c49446"))
			_draw_image_rect(image, Rect2i(22, 19, 5, 3), Color("#c49446"))
		Tab.DUNGEON:
			_draw_image_panel(image, Rect2i(6, 12, 20, 14), Color("#3f2b1f"), Color("#8a5a34"), 2)
			_draw_image_rect(image, Rect2i(6, 15, 20, 2), Color("#c6934a"))
			_draw_image_rect(image, Rect2i(14, 16, 4, 6), Color("#f0d48a"))
		Tab.ACHIEVEMENT:
			_draw_image_panel(image, Rect2i(6, 8, 20, 16), Color("#325a63"), Color("#59a8ad"), 2)
			_draw_image_rect(image, Rect2i(10, 10, 2, 12), Color("#d5f3ea"))
			_draw_image_rect(image, Rect2i(16, 10, 2, 12), Color("#d5f3ea"))
			_draw_image_rect(image, Rect2i(20, 10, 3, 12), Color("#7ad2d6"))
	return ImageTexture.create_from_image(image)


static func _resolve_texture(export_tex: Texture2D, node: TextureRect, fallback_path: String) -> Texture2D:
	if export_tex != null:
		return export_tex
	if node != null and node.texture != null:
		return node.texture
	return _load_tex(fallback_path)


func _sync_background_fallback() -> void:
	var fallback := get_node_or_null("BackgroundFallback") as ColorRect
	if fallback == null:
		return
	fallback.visible = _background == null or _background.texture == null


static func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _set_tab_icon(btn: TextureButton, tex: Texture2D) -> void:
	if tex == null:
		return
	var icon := btn.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = tex
	else:
		btn.texture_normal = tex
		btn.texture_pressed = tex
		btn.texture_hover = tex


static func _set_button_texture(btn: TextureButton, tex: Texture2D) -> void:
	if tex == null:
		return
	btn.texture_normal = tex
	btn.texture_pressed = tex
	btn.texture_hover = tex


static func _set_texture_rect_texture(node: TextureRect, tex: Texture2D) -> void:
	if node == null or tex == null:
		return
	node.texture = tex


static func _draw_image_rect(image: Image, rect: Rect2i, color: Color) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	image.fill_rect(rect, color)


static func _draw_image_panel(image: Image, rect: Rect2i, border: Color, fill: Color, border_px: int) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var border_size := maxi(1, border_px)
	image.fill_rect(rect, border)
	var inner := Rect2i(
		rect.position.x + border_size,
		rect.position.y + border_size,
		rect.size.x - border_size * 2,
		rect.size.y - border_size * 2
	)
	if inner.size.x > 0 and inner.size.y > 0:
		image.fill_rect(inner, fill)
