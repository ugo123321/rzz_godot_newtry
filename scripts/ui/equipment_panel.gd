@tool
extends Control
class_name EquipmentPanelView

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const SYNTHESIS_PANEL_SCENE := preload("res://scenes/ui/synthesis_panel.tscn")
const SKILL_STONE_PANEL_SCENE := preload("res://scenes/ui/skill_stone_panel.tscn")
const ICON_BACK_PATH := "res://assets/ui/icons/system/icon_back.png"

const SLOT_ORDER := [
	"weapon",
	"helmet",
	"necklace",
	"ring",
	"armor",
	"shoes",
]

const INVENTORY_COLUMNS := 5
const INVENTORY_VISIBLE_ROWS := 4
const INVENTORY_BASE_SLOTS := INVENTORY_COLUMNS * INVENTORY_VISIBLE_ROWS
const BAG_SLOT_SCENE := preload("res://scenes/ui/bag_slot.tscn")
# 空槽框图（有装备时由 SlotBg 子节点按品质铺背景盖住，空槽露出此框）
const BAG_SLOT_TEX := preload("res://assets/ui/equipment/equipment_slot02.png")
const EQUIP_SLOT_TEX := preload("res://assets/ui/equipment/equipment_slot01.png")

# 槽位品质背景（替代旧的 QualityBg ColorRect + self_modulate 染色逻辑）
# key = quality 整数：0 白 / 1 蓝 / 2 紫 / 3 橙
const SLOT_BG_TEX := {
	0: preload("res://assets/ui/equipment/slot_bg_white.png"),
	1: preload("res://assets/ui/equipment/slot_bg_blue.png"),
	2: preload("res://assets/ui/equipment/slot_bg_purple.png"),
	3: preload("res://assets/ui/equipment/slot_bg_orange.png"),
}
# 部位 icon（左上角小图）—— slot_key → sort_icon 贴图
const SORT_ICON_TEX := {
	"weapon": preload("res://assets/ui/equipment/sort_icon_sord.png"),
	"helmet": preload("res://assets/ui/equipment/sort_icon_helmet.png"),
	"necklace": preload("res://assets/ui/equipment/sort_icon_neckless.png"),
	"ring": preload("res://assets/ui/equipment/sort_icon_ring.png"),
	"armor": preload("res://assets/ui/equipment/sort_icon_armor.png"),
	"shoes": preload("res://assets/ui/equipment/sort_icon_boot.png"),
}
const SORT_BG_TEX := preload("res://assets/ui/equipment/sort_bg.png")
# 详情弹窗顶部品质装饰带：0 白 / 1 蓝 / 2 紫 / 3 橙
# deco_rare_common=白 / deco_rare_rare=蓝 / deco_rare_epic=紫 / deco_rare_legendary=橙
const QUALITY_DECO_TEX := {
	0: preload("res://assets/ui/decorations/deco_rare_common.png"),
	1: preload("res://assets/ui/decorations/deco_rare_rare.png"),
	2: preload("res://assets/ui/decorations/deco_rare_epic.png"),
	3: preload("res://assets/ui/decorations/deco_rare_legendary.png"),
}
const GOLD_ICON_TEX := preload("res://assets/ui/icons/currency/icon_cur_gold.png")
const SORT_BADGE_SIZE := 33   # sort_bg 33×33
const SORT_ICON_INNER := 20   # sort_icon 20×20，居中放在 sort_bg 内
const LEVEL_FONT_SIZE := 18
# 装备槽(107×107) / 背包槽(126×126) 内 部位徽章 与 等级文字 相对槽位左上角偏移（来自 PS）
# 部位徽章 33×33 在槽左上角，再往右下偏 (4,4) 不贴边；icon 居中落在徽章内 (10.5,10.5)
# 装备：等级文字 (62,78)
const _EQUIP_SORT_OFFSET := Vector2(4, 4)
const _EQUIP_LEVEL_OFFSET := Vector2(62, 78)
# 背包：等级文字 (77,92)
const _BAG_SORT_OFFSET := Vector2(4, 4)
const _BAG_LEVEL_OFFSET := Vector2(77, 92)

## 装备页主角预览缩放（与战斗 sprite_scale 独立）。选 EquipmentPanel 根节点调节；步进 0.1。
@export_range(0.5, 8.0, 0.1, "or_greater") var preview_sprite_scale: float = 2.0:
	set(value):
		preview_sprite_scale = value
		if is_node_ready() or Engine.is_editor_hint():
			_apply_preview_sprite_scale()

const SLOT_BUTTON_NODES := {
	"weapon": &"SlotWeapon",
	"helmet": &"SlotHelmet",
	"necklace": &"SlotNecklace",
	"ring": &"SlotRing",
	"armor": &"SlotArmor",
	"shoes": &"SlotShoes",
}

@onready var _main_vbox: VBoxContainer = $Frame/RootMargin/BaseRoot
@onready var _inventory_grid: GridContainer = $Frame/RootMargin/BaseRoot/BagScroll/InventoryGrid
@onready var _inventory_empty_label: Label = $Frame/RootMargin/BaseRoot/InventoryEmptyLabel
@onready var _battle_power_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/PowerRow/BattlePowerLabel
@onready var _attack_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/SubStatsRow/AttackBox/Row/AttackLabel
@onready var _hp_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/SubStatsRow/HpBox/Row/HpLabel
# 新增属性胶囊行：攻击 / 生命 / 移速（stat_capsule_9s 背景 + system icon + 数值）
@onready var _capsule_attack_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/StatCapsuleRow/AttackCapsule/Value
@onready var _capsule_hp_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/StatCapsuleRow/HpCapsule/Value
@onready var _capsule_speed_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/StatCapsuleRow/SpeedCapsule/Value
@onready var _preview_viewport: SubViewport = $Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/PreviewWrap/PreviewContainer/PreviewViewport
@onready var _preview_sprite: AnimatedSprite2D = %PreviewSprite

@onready var _detail_popup: Control = $DetailPopup
@onready var _detail_dim: ColorRect = $DetailPopup/Dim
@onready var _detail_panel: TextureRect = $DetailPopup/Panel
@onready var _detail_quality_deco: TextureRect = $DetailPopup/Panel/QualityDeco
@onready var _detail_icon_slot: TextureButton = $DetailPopup/Panel/DetailIconSlot
@onready var _detail_icon: TextureRect = $DetailPopup/Panel/DetailIconSlot/ItemIcon
@onready var _detail_name_label: Label = $DetailPopup/Panel/DetailNameLabel
@onready var _detail_level_label: Label = $DetailPopup/Panel/DetailLevelLabel
@onready var _detail_tip_label: Label = $DetailPopup/Panel/DetailTipLabel
@onready var _detail_skill_text: RichTextLabel = $DetailPopup/Panel/DetailSkillText
@onready var _btn_equip: TextureButton = $DetailPopup/Panel/BtnEquip
@onready var _btn_unequip: TextureButton = $DetailPopup/Panel/BtnUnequip
@onready var _btn_upgrade: TextureButton = $DetailPopup/Panel/BtnUpgrade
@onready var _details_popup: AcceptDialog = $DetailsPopup
@onready var _details_label: Label = $DetailsPopup/DetailsLabel
@onready var _synth_btn: TextureButton = $Frame/RootMargin/BaseRoot/SynthRow/SynthBtn
@onready var _skill_stone_btn: TextureButton = $Frame/RootMargin/BaseRoot/SynthRow/SkillStoneBtn

# 合成 / 技能石 按钮按下缩放（参考 main_menu 开始按钮）
const _ACTION_BTN_PRESS_SCALE := 0.9

var _icon_cache: Dictionary = {}
var _preview_state := "walk"
var _preview_timer := 0.0
var _current_detail_uid := -1
var _slot_buttons: Dictionary = {}

var _bag_slot_uids: Array[int] = []

# 进场动效：每个槽/格子/按钮逐个依次淡入显形
var _intro_playing := false
const INTRO_STEP := 0.018      # 每个元素错峰间隔（秒）
const INTRO_DURATION := 0.22   # 单元素显形时长（秒）
const INTRO_SCALE_FROM := 0.82 # 起始缩放（缩小更明显，回弹放大归位）


func _should_fill_parent() -> bool:
	var parent_node := get_parent()
	return parent_node is MarginContainer and parent_node.name == "Content"


func _ready() -> void:
	# 默认 LINEAR：文字 / stat icon 走抗锯齿；ItemIcon / 预览像素艺术在 _apply_pixel_filter_tree
	# 里显式改回 NEAREST。绝不能在 root 用 NEAREST（会污染 Label 字形 atlas 采样）。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if Engine.is_editor_hint():
		# 编辑器不再动态构建预览角色 SpriteFrames —— 避免 4MB 内嵌进 tscn（跟战斗场景一致，
		# 战斗里 sprite_frames 也不在编辑器预览）。运行时走 _setup_scene_ui → _setup_preview_sprite
		# 从磁盘 PNG 加载，逻辑跟 player.gd / monster.gd 完全一样。
		return
	_setup_scene_ui()
	_connect_signals()
	_apply_static_texts()
	_setup_action_button_press(_synth_btn)
	_setup_action_button_press(_skill_stone_btn)
	_refresh_all()
	set_process(true)
	# 进场动效：每次面板可见时所有区块快速依次淡入显形
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()   # 首次若已可见则立即播


func _on_language_changed(_lang: String) -> void:
	_apply_static_texts()
	_refresh_all()


# ─── 进场动效：所有区块快速依次淡入显形 ───────────────────
func _on_visibility_changed() -> void:
	if visible and not Engine.is_editor_hint():
		call_deferred("_play_intro")


func _play_intro() -> void:
	if _main_vbox == null:
		return
	# 收集要"依次显形"的细粒度元素，按视觉从上到下排列
	var elems: Array[Control] = []
	# 0) 顶部标题 icon + 文字
	for title_path in ["Frame/TitleIcon", "Frame/Title"]:
		var t := get_node_or_null(title_path) as Control
		if t != null and t.visible:
			elems.append(t)
	# 1) 人物预览
	if _preview_sprite != null and _preview_sprite.get_parent() is Control:
		elems.append(_preview_sprite.get_parent() as Control)
	# 2) 6 个装备槽（按显示顺序：weapon→helmet→necklace→ring→armor→shoes）
	for slot_key in SLOT_ORDER:
		var btn := _slot_buttons.get(slot_key, null) as Control
		if btn != null and btn.visible:
			elems.append(btn)
	# 3) 战力 / 攻击 / 生命 数值（StatsBlock 下的数值 Label）
	for lbl_path in [
		"Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/PowerRow",
		"Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/SubStatsRow",
		"Frame/RootMargin/BaseRoot/UpperArea/StatCapsuleRow",
	]:
		var block := get_node_or_null(lbl_path) as Control
		if block != null and block.visible:
			elems.append(block)
	# 4) 背包格子（InventoryGrid 的子节点，按网格顺序）
	if _inventory_grid != null:
		for c in _inventory_grid.get_children():
			if c is Control and c.visible:
				elems.append(c as Control)
	# 5) 合成 / 技能石 按钮（SynthRow 的子节点）
	var synth_row := get_node_or_null("Frame/RootMargin/BaseRoot/SynthRow") as Container
	if synth_row != null:
		for c in synth_row.get_children():
			if c is Control and c.visible:
				elems.append(c as Control)
	if elems.is_empty():
		return
	_intro_playing = true
	# 起点：透明 + 轻微缩小（绕中心）
	for c in elems:
		c.modulate.a = 0.0
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(INTRO_SCALE_FROM, INTRO_SCALE_FROM)
	# 逐个错峰淡入 + 回弹归位（全页从上到下依次显形）
	var tw := create_tween()
	tw.set_parallel(true)
	for i in range(elems.size()):
		var c: Control = elems[i]
		var delay := INTRO_STEP * float(i)
		tw.tween_property(c, "modulate:a", 1.0, INTRO_DURATION).set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, INTRO_DURATION).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(Callable(self, "_on_intro_done"))


func _on_intro_done() -> void:
	_intro_playing = false
	# 收尾：归位 scale/alpha，防止残留缩放造成视觉偏移
	_reset_intro_visuals(_slot_buttons.values())
	if _inventory_grid != null:
		_reset_intro_visuals(_inventory_grid.get_children())
	var synth_row := get_node_or_null("Frame/RootMargin/BaseRoot/SynthRow") as Container
	if synth_row != null:
		_reset_intro_visuals(synth_row.get_children())
	if _preview_sprite != null and _preview_sprite.get_parent() is Control:
		_reset_intro_visuals([_preview_sprite.get_parent()])
	for lbl_path in [
		"Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/PowerRow",
		"Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/VBoxContainer/MarginContainer/StatsBlock/SubStatsRow",
		"Frame/RootMargin/BaseRoot/UpperArea/StatCapsuleRow",
	]:
		var block := get_node_or_null(lbl_path) as Control
		if block != null:
			_reset_intro_visuals([block])


func _reset_intro_visuals(nodes: Array) -> void:
	for c in nodes:
		if c is Control:
			var ctrl := c as Control
			ctrl.scale = Vector2.ONE
			ctrl.modulate.a = 1.0


func _apply_static_texts() -> void:
	var title := get_node_or_null("Frame/Title") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_MAIN_EQUIPMENT")
	if _inventory_empty_label != null:
		_inventory_empty_label.text = LanguageManager.tr_ui("UI_EQUIP_NO_ITEMS")
	if _btn_equip != null:
		var lbl := _btn_equip.get_node_or_null("Label") as Label
		if lbl != null:
			lbl.text = LanguageManager.tr_ui("UI_EQUIP_WEAR")
	if _btn_unequip != null:
		var lbl := _btn_unequip.get_node_or_null("Label") as Label
		if lbl != null:
			lbl.text = LanguageManager.tr_ui("UI_EQUIP_UNEQUIP")
	if _btn_upgrade != null:
		var lbl := _btn_upgrade.get_node_or_null("VBox/TitleLabel") as Label
		if lbl != null:
			lbl.text = LanguageManager.tr_ui("UI_EQUIP_UPGRADE_BTN")
	if _detail_tip_label != null:
		_detail_tip_label.text = LanguageManager.tr_ui("UI_EQUIP_DETAIL_ATTR_HEADER")
	if _synth_btn != null:
		var synth_lbl := _synth_btn.get_node_or_null("Label") as Label
		if synth_lbl != null:
			synth_lbl.text = LanguageManager.tr_ui("UI_EQUIP_SYNTHESIZE")
	if _skill_stone_btn != null:
		var ss_lbl := _skill_stone_btn.get_node_or_null("Label") as Label
		if ss_lbl != null:
			ss_lbl.text = LanguageManager.tr_ui("UI_SKILL_STONE_TITLE")


# 合成 / 技能石 按钮按下效果（参考 main_menu 开始按钮：缩放 0.9 + 轻微暗化）
func _setup_action_button_press(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.button_down.connect(_on_action_btn_down.bind(btn))
	btn.button_up.connect(_on_action_btn_up.bind(btn))


func _on_action_btn_down(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.pivot_offset = Vector2(floorf(btn.size.x * 0.5), floorf(btn.size.y * 0.5))
	btn.scale = Vector2.ONE * _ACTION_BTN_PRESS_SCALE
	btn.modulate = Color(0.92, 0.92, 0.96)


func _on_action_btn_up(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.scale = Vector2.ONE
	btn.modulate = Color.WHITE


func _connect_signals() -> void:
	if EventBus:
		EventBus.equipment_changed.connect(_on_equipment_changed)
		EventBus.gold_changed.connect(_on_gold_changed)
		EventBus.language_changed.connect(_on_language_changed)


func _setup_scene_ui() -> void:
	# 嵌入主菜单 Content 时铺满可用区域；单独打开场景时保持 688x1034，与运行时一致。
	if _should_fill_parent():
		set_anchors_preset(Control.PRESET_FULL_RECT)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	_bind_slot_buttons()
	_setup_inventory_slots()
	_setup_preview_sprite()

	PixelUi.apply_ui_font_tree(self)
	_apply_pixel_filter_tree(self)
	# 详情弹窗：编辑器里默认可见方便排版，运行时启动即隐藏
	if _detail_popup != null and not Engine.is_editor_hint():
		_detail_popup.visible = false
	# 弹板按钮按下缩放效果（参考技能石/合成功能按钮）
	_setup_action_button_press(_btn_equip)
	_setup_action_button_press(_btn_unequip)
	_setup_action_button_press(_btn_upgrade)


# 点击弹窗外的暗化区域 → 关闭（替代旧右上角关闭按钮）
func _on_detail_outside_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_close_detail()


func _close_detail() -> void:
	_play_detail_close()


# 弹出 / 弹回动效：Panel 以中心为轴心缩放 + Dim 淡入淡出
const _DETAIL_POP_TIME := 0.18
const _DETAIL_POP_SCALE := Vector2(0.82, 0.82)
var _detail_tween: Tween = null


func _kill_detail_tween() -> void:
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_tween = null


func _play_detail_open() -> void:
	if _detail_popup == null:
		return
	_kill_detail_tween()
	_detail_popup.visible = true
	if _detail_panel != null:
		_detail_panel.pivot_offset = _detail_panel.size * 0.5
		_detail_panel.scale = _DETAIL_POP_SCALE
	if _detail_dim != null:
		_detail_dim.modulate = Color(1, 1, 1, 0.0)
	_detail_tween = create_tween()
	_detail_tween.set_parallel(true)
	if _detail_dim != null:
		_detail_tween.tween_property(_detail_dim, "modulate:a", 0.4, _DETAIL_POP_TIME)
	if _detail_panel != null:
		_detail_tween.tween_property(_detail_panel, "scale", Vector2.ONE, _DETAIL_POP_TIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _play_detail_close() -> void:
	if _detail_popup == null or not _detail_popup.visible:
		return
	_kill_detail_tween()
	if _detail_panel != null:
		_detail_panel.pivot_offset = _detail_panel.size * 0.5
	_detail_tween = create_tween()
	_detail_tween.set_parallel(true)
	if _detail_dim != null:
		_detail_tween.tween_property(_detail_dim, "modulate:a", 0.0, _DETAIL_POP_TIME)
	if _detail_panel != null:
		_detail_tween.tween_property(_detail_panel, "scale", _DETAIL_POP_SCALE, _DETAIL_POP_TIME) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_detail_tween.chain().tween_callback(_hide_detail_after_close)


func _hide_detail_after_close() -> void:
	if _detail_popup != null:
		_detail_popup.visible = false
	_current_detail_uid = -1


# 详情弹窗里的装备 icon 槽：品质背景 + 部位徽章 + 物品 icon（无等级文字）
func _apply_detail_icon_slot(item: Dictionary, quality: int, slot: String) -> void:
	if _detail_icon_slot == null:
		return
	var slot_bg := _detail_icon_slot.get_node_or_null("SlotBg") as TextureRect
	if slot_bg != null:
		slot_bg.texture = SLOT_BG_TEX.get(quality, SLOT_BG_TEX[0])
		slot_bg.visible = true
	var icon := _get_item_icon(item)
	if _detail_icon != null:
		_detail_icon.texture = icon
		_detail_icon.visible = icon != null
	var sort_bg := _detail_icon_slot.get_node_or_null("SortIconBg") as TextureRect
	if sort_bg != null:
		sort_bg.visible = slot != ""
		var sort_icon := sort_bg.get_node_or_null("SortIcon") as TextureRect
		if sort_icon != null and slot != "":
			sort_icon.texture = SORT_ICON_TEX.get(slot, null)
	_detail_icon_slot.self_modulate = Color.WHITE


# 升级按钮：第一行 "升级" + 第二行 [金币 icon] cost/total；金币不足置灰、数字转红
func _refresh_upgrade_button(cost: int) -> void:
	if _btn_upgrade == null:
		return
	var held := int(LobbyState.gold)
	var title := _btn_upgrade.get_node_or_null("VBox/TitleLabel") as Label
	if title != null:
		title.text = LanguageManager.tr_ui("UI_EQUIP_UPGRADE_BTN")
	var cost_label := _btn_upgrade.get_node_or_null("VBox/GoldRow/CostLabel") as Label
	if cost_label != null:
		cost_label.text = "%d/%d" % [cost, held]
		var afford := held >= cost
		cost_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3) if not afford else Color(1, 1, 1))
	var can_afford := held >= cost
	_btn_upgrade.disabled = not can_afford
	_btn_upgrade.modulate = Color(0.6, 0.6, 0.6) if not can_afford else Color.WHITE


func _bind_slot_buttons() -> void:
	_slot_buttons.clear()
	for slot in SLOT_ORDER:
		var node_name: StringName = SLOT_BUTTON_NODES.get(slot, &"")
		var btn := find_child(str(node_name), true, false) as TextureButton
		if btn == null:
			continue
		_slot_buttons[slot] = btn
		# 装备槽：恢复空槽框图；有装备时 SlotBg 子节点按品质铺背景盖住
		btn.texture_normal = EQUIP_SLOT_TEX
		btn.pressed.connect(_on_slot_pressed.bind(slot))


func _setup_preview_sprite() -> void:
	var sprite := _get_preview_sprite()
	if sprite == null:
		return
	# 编辑器 @tool 模式下 GameConfig 是 placeholder，方法不能调 → 用默认值走 preview
	var folder := "Swordsman"
	var prefix := "Swordsman"
	if not Engine.is_editor_hint():
		folder = str(GameConfig.get_player_value("character_folder", "Swordsman"))
		prefix = str(GameConfig.get_player_value("sprite_prefix", "Swordsman"))
	var frames := SpriteHelper.build_character_frames(folder, prefix)
	# 先把 animation 指到 frames 里存在的名字，再赋 sprite_frames，避免 AnimatedSprite2D
	# 拿默认空串 animation 校验时报 "There is no animation with name ''"。
	var pick_anim := ""
	if frames != null:
		if frames.has_animation(SpriteHelper.ANIM_WALK):
			pick_anim = SpriteHelper.ANIM_WALK
		elif frames.has_animation(SpriteHelper.ANIM_IDLE):
			pick_anim = SpriteHelper.ANIM_IDLE
	if pick_anim != "":
		sprite.animation = pick_anim
	sprite.sprite_frames = frames
	SpriteHelper.apply_pixel_art(sprite)
	if frames != null and pick_anim != "":
		sprite.play(pick_anim)
	_apply_preview_sprite_scale()
	if not Engine.is_editor_hint():
		_preview_state = "walk"
		_preview_timer = randf_range(1.8, 3.2)


func _get_preview_sprite() -> AnimatedSprite2D:
	if _preview_sprite != null:
		return _preview_sprite
	if not is_inside_tree():
		return null
	return get_node_or_null("%PreviewSprite") as AnimatedSprite2D


func _apply_preview_sprite_scale() -> void:
	var sprite := _get_preview_sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var s := maxf(0.1, preview_sprite_scale)
	sprite.scale = Vector2.ONE * s


func _apply_pixel_filter_tree(root: Node) -> void:
	# 默认 LINEAR（抗锯齿），只有装备物品 icon（ItemIcon）和角色预览像素动画保 NEAREST。
	# PreviewSprite / PreviewViewport 里的东西也是像素艺术。
	# 注意：不用 LINEAR_WITH_MIPMAPS —— 这些 stat icon 的 .import 里 mipmaps/generate=false，
	# 请求 mipmap 版本时会退化到不理想的采样，反而看起来像 NEAREST。
	if root is CanvasItem:
		var ci := root as CanvasItem
		if _should_keep_ci_nearest(root):
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for child in root.get_children():
		_apply_pixel_filter_tree(child)


func _should_keep_ci_nearest(node: Node) -> bool:
	var n := str(node.name)
	if n == "ItemIcon" or n == "PreviewSprite" or n == "PreviewViewport" or n == "PreviewContainer":
		return true
	# 装备格子新增的像素贴图：品质背景 SlotBg、部位徽章 SortIconBg/SortIcon 也走 NEAREST
	if n == "SlotBg" or n == "SortIconBg" or n == "SortIcon":
		return true
	# 详情弹窗金币 icon 也是像素图
	if n == "GoldIcon":
		return true
	return false


func _on_synthesis_pressed() -> void:
	var host := _synthesis_overlay_host()
	if host == null:
		return
	if _detail_popup != null:
		_detail_popup.visible = false
	_current_detail_uid = -1
	var panel := SYNTHESIS_PANEL_SCENE.instantiate() as Control
	if panel == null:
		return
	host.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if panel.has_signal("closed"):
		panel.connect("closed", _refresh_all)


func _on_skill_stone_pressed() -> void:
	var host := _synthesis_overlay_host()
	if host == null:
		return
	if _detail_popup != null:
		_detail_popup.visible = false
	_current_detail_uid = -1
	var panel := SKILL_STONE_PANEL_SCENE.instantiate() as Control
	if panel == null:
		return
	host.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if panel.has_signal("closed"):
		panel.connect("closed", _refresh_all)


func _synthesis_overlay_host() -> Node:
	# 主菜单根节点在两层之上（Content -> MainMenu）；单独打开场景时回退到自身。
	var content := get_parent()
	if content != null and content.get_parent() != null:
		return content.get_parent()
	return self


func _on_equipment_changed() -> void:
	_refresh_all()


func _on_gold_changed(_value: int) -> void:
	if _current_detail_uid >= 0 and _detail_popup.visible:
		_refresh_detail_content(_current_detail_uid)


func _refresh_all() -> void:
	_refresh_slots()
	_refresh_attributes()
	_refresh_inventory()


func _refresh_slots() -> void:
	for slot in SLOT_ORDER:
		var btn := _slot_buttons.get(slot, null) as TextureButton
		if btn == null:
			continue
		var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
		var item := LobbyState.get_equipped_item(slot)
		if item.is_empty():
			if icon_rect != null:
				icon_rect.visible = false
				icon_rect.texture = null
			_apply_slot_visual(btn, 0, false, slot, 0, false)
			continue
		var quality := int(item.get("quality", 0))
		var icon := _get_item_icon(item)
		if icon_rect != null:
			icon_rect.texture = icon
			icon_rect.visible = icon != null
		_apply_slot_visual(btn, quality, true, slot, int(item.get("level", 1)), false)


# 在槽位内确保四个子节点：SlotBg（品质背景，铺底）/ SortIconBg+SortIcon（左上角部位徽章）/ LevelLabel（右下角等级）
# 首次创建时插在最底（索引 0）→ ItemIcon 在其之上；SortIconBg/LevelLabel 后加 → 叠在物品图标之上做角标
func _ensure_slot_parts(btn: TextureButton) -> void:
	if btn.get_node_or_null("SlotBg") == null:
		var bg := TextureRect.new()
		bg.name = "SlotBg"
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.offset_left = 0
		bg.offset_top = 0
		bg.offset_right = 0
		bg.offset_bottom = 0
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.texture = SLOT_BG_TEX[0]
		btn.add_child(bg)
		btn.move_child(bg, 0)  # 索引 0 → 最底
	if btn.get_node_or_null("SortIconBg") == null:
		var sbg := TextureRect.new()
		sbg.name = "SortIconBg"
		sbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sbg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		sbg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sbg.stretch_mode = TextureRect.STRETCH_SCALE
		sbg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sbg.texture = SORT_BG_TEX
		sbg.custom_minimum_size = Vector2(SORT_BADGE_SIZE, SORT_BADGE_SIZE)
		sbg.size = Vector2(SORT_BADGE_SIZE, SORT_BADGE_SIZE)
		btn.add_child(sbg)
		# 部位 icon 居中嵌在 sort_bg 内（20×20 在 33×33 中心）
		var icon := TextureRect.new()
		icon.name = "SortIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_preset(Control.PRESET_CENTER)
		var half := SORT_ICON_INNER * 0.5
		icon.offset_left = -half
		icon.offset_top = -half
		icon.offset_right = half
		icon.offset_bottom = half
		sbg.add_child(icon)
	if btn.get_node_or_null("LevelLabel") == null:
		var lbl := Label.new()
		lbl.name = "LevelLabel"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", LEVEL_FONT_SIZE)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 3)
		# 黑色投影 shadow（右下偏移 2px，加粗投影）
		lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		lbl.add_theme_constant_override("shadow_outline_size", 4)
		lbl.add_theme_constant_override("shadow_offset_x", 2)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
		lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.add_child(lbl)


# 统一：按品质切 SlotBg 贴图 + 设部位 icon + 显示等级；空槽用白底、无部位徽章/无等级
# is_bag：背包槽(true) 与装备槽(false) 的部位徽章/等级文字偏移不同
func _apply_slot_visual(btn: TextureButton, quality: int, has_item: bool,
		slot_key: String, level: int, is_bag: bool) -> void:
	_ensure_slot_parts(btn)
	var slot_bg := btn.get_node_or_null("SlotBg") as TextureRect
	var sort_bg_rect := btn.get_node_or_null("SortIconBg") as TextureRect
	var sort_icon: TextureRect = null
	if sort_bg_rect != null:
		sort_icon = sort_bg_rect.get_node_or_null("SortIcon") as TextureRect
	var level_lbl := btn.get_node_or_null("LevelLabel") as Label
	var sort_offset := _BAG_SORT_OFFSET if is_bag else _EQUIP_SORT_OFFSET
	var level_offset := _BAG_LEVEL_OFFSET if is_bag else _EQUIP_LEVEL_OFFSET
	# 旧品质染色逻辑已删除——不再用 self_modulate 染槽框
	btn.self_modulate = Color.WHITE
	# 品质背景：仅有装备时显示（盖住根空槽框）；空槽不显示，露出原空槽框图
	var q := quality if has_item else 0
	if slot_bg != null:
		slot_bg.texture = SLOT_BG_TEX.get(q, SLOT_BG_TEX[0])
		slot_bg.visible = has_item
	# 部位徽章：仅有装备时显示（装备槽固定部位 / 背包槽取物品 slot）；空槽不显示
	var show_sort := slot_key != "" and has_item
	if sort_bg_rect != null:
		sort_bg_rect.visible = show_sort
		if show_sort:
			sort_bg_rect.offset_left = sort_offset.x
			sort_bg_rect.offset_top = sort_offset.y
			sort_bg_rect.offset_right = sort_offset.x + SORT_BADGE_SIZE
			sort_bg_rect.offset_bottom = sort_offset.y + SORT_BADGE_SIZE
			if sort_icon != null:
				sort_icon.texture = SORT_ICON_TEX.get(slot_key, null)
				sort_icon.visible = sort_icon.texture != null
	# 等级文字：右下角，仅物品存在时显示
	if level_lbl != null:
		if has_item and level > 0:
			level_lbl.text = "LV.%d" % level
			level_lbl.visible = true
			# 文字基线锚在偏移点，向右下扩展（grow END）
			level_lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
			level_lbl.offset_left = level_offset.x
			level_lbl.offset_top = level_offset.y
			level_lbl.offset_right = level_offset.x
			level_lbl.offset_bottom = level_offset.y
			level_lbl.grow_horizontal = Control.GROW_DIRECTION_END
			level_lbl.grow_vertical = Control.GROW_DIRECTION_END
		else:
			level_lbl.visible = false


func _refresh_attributes() -> void:
	if _battle_power_label == null or _attack_label == null or _hp_label == null:
		return
	var attrs := LobbyState.get_player_preview_attributes()
	_battle_power_label.text = str(int(attrs.get("battle_power", 0)))
	_attack_label.text = str(int(round(float(attrs.get("attack", 0.0)))))
	_hp_label.text = str(int(attrs.get("hp", 0)))
	# 属性胶囊行（攻击 / 生命 / 移速）
	if _capsule_attack_label != null:
		_capsule_attack_label.text = str(int(round(float(attrs.get("attack", 0.0)))))
	if _capsule_hp_label != null:
		_capsule_hp_label.text = str(int(attrs.get("hp", 0)))
	if _capsule_speed_label != null:
		# 移速是 px/s 小数，四舍五入成整数显示
		_capsule_speed_label.text = str(int(round(float(attrs.get("move_speed", 0.0)))))


func _setup_inventory_slots() -> void:
	if _inventory_grid == null:
		return
	_ensure_inventory_slot_count(INVENTORY_BASE_SLOTS)
	for i in range(_inventory_grid.get_child_count()):
		var btn := _inventory_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		# 背包槽：恢复空槽框图；有装备时 SlotBg 子节点按品质铺背景盖住
		btn.texture_normal = BAG_SLOT_TEX
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		if not btn.pressed.is_connected(_on_bag_slot_pressed):
			btn.pressed.connect(_on_bag_slot_pressed.bind(i))


func _ensure_inventory_slot_count(count: int) -> void:
	if _inventory_grid == null:
		return
	while _inventory_grid.get_child_count() < count:
		var index := _inventory_grid.get_child_count()
		var btn := BAG_SLOT_SCENE.instantiate() as TextureButton
		if btn == null:
			break
		btn.name = "BagSlot%02d" % index
		# 背包槽：恢复空槽框图；有装备时 SlotBg 子节点按品质铺背景盖住
		btn.texture_normal = BAG_SLOT_TEX
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		btn.pressed.connect(_on_bag_slot_pressed.bind(index))
		_inventory_grid.add_child(btn)
	while _inventory_grid.get_child_count() > count:
		var extra := _inventory_grid.get_child(_inventory_grid.get_child_count() - 1)
		# remove_child 立即摘除（get_child_count 同步下降），
		# queue_free 延迟到帧末——只 queue_free 不 remove_child 会死循环。
		_inventory_grid.remove_child(extra)
		extra.queue_free()


func _apply_item_to_bag_slot(btn: TextureButton, item: Dictionary, uid: int) -> void:
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	var icon := _get_item_icon(item)
	if icon_rect != null:
		icon_rect.texture = icon
		icon_rect.visible = icon != null
	_apply_slot_visual(btn, int(item.get("quality", 0)), true,
			str(item.get("slot", "")), int(item.get("level", 1)), true)
	btn.set_meta("bag_uid", uid)


func _apply_empty_bag_slot(btn: TextureButton) -> void:
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = null
		icon_rect.visible = false
	_apply_slot_visual(btn, 0, false, "", 0, true)
	btn.set_meta("bag_uid", -1)


func _on_bag_slot_pressed(slot_index: int) -> void:
	var bag_scroll := get_node_or_null("Frame/RootMargin/BaseRoot/BagScroll") as SpringScrollContainer
	if bag_scroll != null and bag_scroll.was_scroll_gesture():
		return
	if slot_index < 0 or slot_index >= _bag_slot_uids.size():
		return
	var uid := int(_bag_slot_uids[slot_index])
	if uid >= 0:
		_open_item_detail(uid)


func _refresh_inventory() -> void:
	if _inventory_grid == null:
		return
	var inventory := LobbyState.get_inventory_sorted()
	var slot_count := maxi(INVENTORY_BASE_SLOTS, inventory.size())
	_ensure_inventory_slot_count(slot_count)
	_bag_slot_uids.resize(slot_count)
	for i in range(slot_count):
		var btn := _inventory_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		if i < inventory.size():
			var item: Dictionary = inventory[i]
			var uid := int(item.get("uid", -1))
			_bag_slot_uids[i] = uid
			_apply_item_to_bag_slot(btn, item, uid)
		else:
			_bag_slot_uids[i] = -1
			_apply_empty_bag_slot(btn)
	if _inventory_empty_label != null:
		_inventory_empty_label.visible = false


func _get_item_icon(item: Dictionary) -> Texture2D:
	var path := LobbyState.get_item_icon_path(item)
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_icon_cache[path] = tex
	return tex


func _on_slot_pressed(slot: String) -> void:
	var item := LobbyState.get_equipped_item(slot)
	if item.is_empty():
		return
	_open_item_detail(int(item.get("uid", -1)))


func _open_item_detail(uid: int) -> void:
	if not _refresh_detail_content(uid):
		return
	_play_detail_open()


# 刷新弹板内容（品质装饰/icon/名称/等级/属性球/按钮）。返回 false=物品不存在。
# 注意：升级 / 金币变化触发的刷新走这里——不带弹出动画，避免每次刷新都 re-pop。
func _refresh_detail_content(uid: int) -> bool:
	if _detail_popup == null or _btn_equip == null or _btn_unequip == null or _btn_upgrade == null:
		return false
	var item := LobbyState.get_item_by_uid(uid)
	if item.is_empty():
		return false
	_current_detail_uid = uid
	var quality := int(item.get("quality", 0))
	var slot := str(item.get("slot", ""))
	# 顶部品质装饰带
	if _detail_quality_deco != null:
		_detail_quality_deco.texture = QUALITY_DECO_TEX.get(quality, QUALITY_DECO_TEX[0])
	# 装备 icon（带部位徽章，无等级文字）
	_apply_detail_icon_slot(item, quality, slot)
	# 名称
	_detail_name_label.text = LobbyState.get_item_name(item)
	# 等级信息
	_detail_level_label.text = LanguageManager.tr_ui("UI_EQUIP_LEVEL_PART_FMT") % [
		int(item.get("level", 1)),
		LobbyState.get_slot_display_name(slot),
	]
	# "属性" 段头
	_detail_tip_label.text = LanguageManager.tr_ui("UI_EQUIP_DETAIL_ATTR_HEADER")

	var lines: PackedStringArray = []
	for entry in LobbyState.get_item_skill_entries(item):
		var unlocked := bool(entry.get("unlocked", false))
		var quality_tier := int(entry.get("quality", LobbyState.QUALITY_COMMON))
		var text := str(entry.get("text", ""))
		var ball := _make_quality_pixel_ball(quality_tier, unlocked)
		if unlocked:
			lines.append("%s [color=#%s]%s[/color]" % [ball, _ATTR_TEXT_ACTIVE.to_html(), text])
		else:
			lines.append("%s [color=#7a7a7a]%s[/color]" % [ball, text])
	_detail_skill_text.text = "\n".join(lines)

	var equipped := LobbyState.is_item_equipped(uid)
	_btn_equip.visible = not equipped
	_btn_unequip.visible = equipped
	_btn_upgrade.visible = true
	_refresh_upgrade_button(LobbyState.get_upgrade_cost(item))
	return true


func _on_detail_equip() -> void:
	if _current_detail_uid < 0:
		return
	if LobbyState.equip_item(_current_detail_uid):
		_close_detail()


func _on_detail_unequip() -> void:
	if _current_detail_uid < 0:
		return
	var item := LobbyState.get_item_by_uid(_current_detail_uid)
	if item.is_empty():
		return
	var slot := str(item.get("slot", ""))
	if LobbyState.unequip_slot(slot):
		_close_detail()


func _on_detail_upgrade() -> void:
	if _current_detail_uid < 0:
		return
	var upgraded := LobbyState.upgrade_item(_current_detail_uid)
	if upgraded.is_empty():
		# 金币不足：刷新按钮置灰，不关弹窗、不动 "属性" 段头
		var cur := LobbyState.get_item_by_uid(_current_detail_uid)
		if not cur.is_empty():
			_refresh_upgrade_button(LobbyState.get_upgrade_cost(cur))
		return
	_refresh_detail_content(_current_detail_uid)


func _build_active_effect_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for slot in SLOT_ORDER:
		var item := LobbyState.get_equipped_item(slot)
		if item.is_empty():
			continue
		var item_name := LobbyState.get_item_name(item)
		for entry in LobbyState.get_item_skill_entries(item):
			if not bool(entry.get("unlocked", false)):
				continue
			if int(entry.get("quality", LobbyState.QUALITY_COMMON)) <= LobbyState.QUALITY_COMMON:
				continue
			lines.append("- %s: %s" % [
				item_name,
				str(entry.get("text", "")),
			])
	if lines.is_empty():
		lines.append(LanguageManager.tr_ui("UI_EQUIP_NO_FX_PLACEHOLDER"))
	return lines


func _show_attr_popup() -> void:
	var attrs := LobbyState.get_player_preview_attributes()
	var effect_lines := _build_active_effect_lines()
	_details_label.text = LanguageManager.tr_ui("UI_EQUIP_DETAILS_FMT") % [
		int(round(float(attrs.get("attack", 0.0)))),
		int(round(float(attrs.get("equip_attack", 0.0)))),
		int(attrs.get("hp", 0)),
		int(attrs.get("equip_hp", 0)),
		float(attrs.get("crit_rate", 0.0)) * 100.0,
		float(attrs.get("equip_crit_rate", 0.0)) * 100.0,
		int(attrs.get("battle_power", 0)),
		"\n".join(effect_lines),
	]
	_details_popup.popup_centered()


# 属性球：按品质取高饱和色；生效=满色，未生效=同色淡（lightened）。
# 生效的属性"文字说明"才是深绿，球本身始终按品质色。
const _ATTR_BALL_COLOR := {
	0: Color(0.86, 0.86, 0.86, 1),   # 白 → 浅灰（白无饱和度可提）
	1: Color(0.30, 0.55, 1.00, 1),   # 蓝 → 高饱和蓝
	2: Color(0.70, 0.30, 1.00, 1),   # 紫 → 高饱和紫
	3: Color(1.00, 0.55, 0.10, 1),   # 橙 → 高饱和橙
}
const _ATTR_TEXT_ACTIVE := Color(0.12, 0.54, 0.24, 1)   # 生效属性文字：深绿


func _make_quality_pixel_ball(quality: int, unlocked: bool) -> String:
	var base: Color = _ATTR_BALL_COLOR.get(quality, _ATTR_BALL_COLOR[0])
	var fill: Color = base if unlocked else base.lightened(0.4)
	return "[color=%s]●[/color]" % fill.to_html()


func _process(delta: float) -> void:
	if _preview_sprite == null or _preview_sprite.sprite_frames == null:
		return
	_preview_timer -= delta
	if _preview_state == "attack":
		if not _preview_sprite.is_playing():
			_preview_state = "walk"
			_play_preview_walk()
			_preview_timer = randf_range(1.8, 3.2)
		return
	if _preview_timer > 0.0:
		return
	if randf() < 0.24 and _preview_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_ATTACK):
		_preview_state = "attack"
		_preview_sprite.play(SpriteHelper.ANIM_ATTACK)
		_preview_timer = _preview_anim_duration(SpriteHelper.ANIM_ATTACK, 0.55)
	else:
		_play_preview_walk()
		_preview_timer = randf_range(1.8, 3.2)


func _play_preview_walk() -> void:
	if _preview_sprite == null or _preview_sprite.sprite_frames == null:
		return
	if _preview_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_WALK):
		_preview_sprite.play(SpriteHelper.ANIM_WALK)
	elif _preview_sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
		_preview_sprite.play(SpriteHelper.ANIM_IDLE)


func _preview_anim_duration(anim_name: String, fallback: float) -> float:
	if _preview_sprite == null or _preview_sprite.sprite_frames == null:
		return fallback
	if not _preview_sprite.sprite_frames.has_animation(anim_name):
		return fallback
	var frame_count := _preview_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return fallback
	var speed := _preview_sprite.sprite_frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return fallback
	var total := 0.0
	for i in range(frame_count):
		total += _preview_sprite.sprite_frames.get_frame_duration(anim_name, i)
	return maxf(0.12, total / speed)
