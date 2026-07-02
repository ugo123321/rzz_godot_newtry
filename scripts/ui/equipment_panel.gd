@tool
extends Control
class_name EquipmentPanelView

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")
const SYNTHESIS_PANEL_SCENE := preload("res://scenes/ui/synthesis_panel.tscn")
const ICON_CLOSE_PATH := "res://assets/ui/icons/system/icon_close.png"
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
const INVENTORY_SLOT_TEX := preload("res://assets/ui/equipment/equipment_slot02.png")
const BAG_SLOT_SCENE := preload("res://scenes/ui/bag_slot.tscn")

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
@onready var _battle_power_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/MarginContainer/StatsBlock/PowerRow/BattlePowerLabel
@onready var _attack_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/MarginContainer/StatsBlock/SubStatsRow/AttackBox/Row/AttackLabel
@onready var _hp_label: Label = $Frame/RootMargin/BaseRoot/UpperArea/MarginContainer/StatsBlock/SubStatsRow/HpBox/Row/HpLabel
@onready var _preview_viewport: SubViewport = $Frame/RootMargin/BaseRoot/UpperArea/CharacterRow/PreviewWrap/PreviewContainer/PreviewViewport
@onready var _preview_sprite: AnimatedSprite2D = %PreviewSprite

@onready var _detail_popup: PopupPanel = $DetailPopup
@onready var _detail_icon: TextureRect = $DetailPopup/Margin/VBox/Head/DetailIcon
@onready var _detail_name_label: Label = $DetailPopup/Margin/VBox/Head/HeadText/DetailNameLabel
@onready var _detail_level_label: Label = $DetailPopup/Margin/VBox/Head/HeadText/DetailLevelLabel
@onready var _detail_skill_text: RichTextLabel = $DetailPopup/Margin/VBox/DetailSkillText
@onready var _detail_tip_label: Label = $DetailPopup/Margin/VBox/DetailTipLabel
@onready var _btn_equip: Button = $DetailPopup/Margin/VBox/ActionRow/BtnEquip
@onready var _btn_unequip: Button = $DetailPopup/Margin/VBox/ActionRow/BtnUnequip
@onready var _btn_upgrade: Button = $DetailPopup/Margin/VBox/ActionRow/BtnUpgrade
@onready var _details_popup: AcceptDialog = $DetailsPopup
@onready var _details_label: Label = $DetailsPopup/DetailsLabel

var _icon_cache: Dictionary = {}
var _preview_state := "walk"
var _preview_timer := 0.0
var _current_detail_uid := -1
var _slot_buttons: Dictionary = {}

var _bag_slot_uids: Array[int] = []


func _should_fill_parent() -> bool:
	var parent_node := get_parent()
	return parent_node is MarginContainer and parent_node.name == "Content"


func _ready() -> void:
	# 默认 LINEAR：文字 / stat icon 走抗锯齿；ItemIcon / 预览像素艺术在 _apply_pixel_filter_tree
	# 里显式改回 NEAREST。绝不能在 root 用 NEAREST（会污染 Label 字形 atlas 采样）。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if Engine.is_editor_hint():
		call_deferred("_setup_preview_sprite")
		return
	_setup_scene_ui()
	_connect_signals()
	_apply_static_texts()
	_refresh_all()
	set_process(true)


func _on_language_changed(_lang: String) -> void:
	_apply_static_texts()
	_refresh_all()


func _apply_static_texts() -> void:
	if _inventory_empty_label != null:
		_inventory_empty_label.text = LanguageManager.tr_ui("UI_EQUIP_NO_ITEMS")
	if _btn_equip != null:
		_btn_equip.text = LanguageManager.tr_ui("UI_EQUIP_WEAR")
	if _btn_unequip != null:
		_btn_unequip.text = LanguageManager.tr_ui("UI_EQUIP_UNEQUIP")
	if _btn_upgrade != null:
		_btn_upgrade.text = LanguageManager.tr_ui("UI_EQUIP_UPGRADE_BTN")


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
	_style_detail_buttons()  # 必须在 _apply_pixel_filter_tree 之后，否则 LINEAR filter 被覆盖回 NEAREST
	_style_detail_popup_panel()


# 详情弹窗里的"装备 / 卸下 / 强化"3 个按钮：从默认 Godot 样式升级到 9-slice
func _style_detail_buttons() -> void:
	if _btn_equip != null:
		UiStyle.apply_primary_button(_btn_equip, Color("#4dd07a"), 10)  # 绿：装备
		_btn_equip.add_theme_color_override("font_color", Color(0.06, 0.10, 0.06))
	if _btn_unequip != null:
		UiStyle.apply_primary_button(_btn_unequip, Color(0.55, 0.60, 0.78), 10)  # 蓝灰：卸下
		_btn_unequip.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	if _btn_upgrade != null:
		UiStyle.apply_primary_button(_btn_upgrade, Color("#efb840"), 10)  # 金：强化
		_btn_upgrade.add_theme_color_override("font_color", Color(0.18, 0.10, 0.04))


# 详情弹窗背景改用 panel_tooltip_std_9s（比 dialog 尺寸更近、圆角更小、更贴合物品详情弹窗定位）
# 注意：PopupPanel 继承自 Window（不是 CanvasItem），不能设 texture_filter；LINEAR 由 StyleBoxTexture 自带
func _style_detail_popup_panel() -> void:
	if _detail_popup == null:
		return
	var tooltip_style := UiStyle.make_tooltip_stylebox(Color(0.20, 0.18, 0.16, 0.98), 12)
	if tooltip_style != null:
		_detail_popup.add_theme_stylebox_override("panel", tooltip_style)
	_attach_detail_close_button()


# 详情弹窗右上角挂 icon_close.png（Head HBox 现有：DetailIcon + HeadText，追加 spacer + close）
func _attach_detail_close_button() -> void:
	if _detail_popup == null:
		return
	var head := _detail_popup.get_node_or_null("Margin/VBox/Head") as HBoxContainer
	if head == null or head.get_node_or_null("CloseBtn") != null:
		return
	if not ResourceLoader.exists(ICON_CLOSE_PATH):
		return
	var tex := load(ICON_CLOSE_PATH) as Texture2D
	if tex == null:
		return
	var spacer := Control.new()
	spacer.name = "HeadSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var btn := TextureButton.new()
	btn.name = "CloseBtn"
	btn.texture_normal = tex
	btn.texture_hover = tex
	btn.texture_pressed = tex
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.ignore_texture_size = true
	btn.custom_minimum_size = Vector2(32, 32)
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_detail_close_pressed)
	head.add_child(btn)


func _on_detail_close_pressed() -> void:
	if _detail_popup != null:
		_detail_popup.hide()
	_current_detail_uid = -1


func _bind_slot_buttons() -> void:
	_slot_buttons.clear()
	for slot in SLOT_ORDER:
		var node_name: StringName = SLOT_BUTTON_NODES.get(slot, &"")
		var btn := find_child(str(node_name), true, false) as TextureButton
		if btn == null:
			continue
		_slot_buttons[slot] = btn
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
	sprite.sprite_frames = SpriteHelper.build_character_frames(folder, prefix)
	SpriteHelper.apply_pixel_art(sprite)
	if sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation(SpriteHelper.ANIM_WALK):
			sprite.play(SpriteHelper.ANIM_WALK)
		elif sprite.sprite_frames.has_animation(SpriteHelper.ANIM_IDLE):
			sprite.play(SpriteHelper.ANIM_IDLE)
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
	return false


func _on_synthesis_pressed() -> void:
	var host := _synthesis_overlay_host()
	if host == null:
		return
	if _detail_popup != null:
		_detail_popup.hide()
	_current_detail_uid = -1
	var panel := SYNTHESIS_PANEL_SCENE.instantiate() as Control
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
		_open_item_detail(_current_detail_uid)


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
			_apply_quality_visual(btn, 0, false)
			continue
		var quality := int(item.get("quality", 0))
		var icon := _get_item_icon(item)
		if icon_rect != null:
			icon_rect.texture = icon
			icon_rect.visible = icon != null
		# slot 边框（self_modulate）+ icon 后底色（QualityBg）双重品质提示
		_apply_quality_visual(btn, quality, true)


# 保证按钮内有一个 QualityBg ColorRect，作为 ItemIcon 的背景板；返回它。
# 首次创建时插在最前（索引 0）→ 位于 button 纹理之上、ItemIcon 之下。
func _ensure_quality_bg(btn: TextureButton) -> ColorRect:
	var bg := btn.get_node_or_null("QualityBg") as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "QualityBg"
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		# 收边给 slot 边框留可视区
		bg.offset_left = 6
		bg.offset_top = 6
		bg.offset_right = -6
		bg.offset_bottom = -6
		bg.color = Color(1, 1, 1, 0)
		btn.add_child(bg)
		btn.move_child(bg, 0)  # 索引 0 → 最底
	return bg


# 统一：slot 边框 self_modulate + icon 后底色 QualityBg；空槽两者都关。
func _apply_quality_visual(btn: TextureButton, quality: int, has_item: bool) -> void:
	var bg := _ensure_quality_bg(btn)
	if not has_item:
		bg.visible = false
		btn.self_modulate = Color.WHITE
		return
	var color := LobbyState.get_quality_color(quality)
	btn.self_modulate = color
	bg.visible = true
	var bg_color := color
	bg_color.a = 0.72  # 保证颜色鲜明又能透一点 slot 花纹
	bg.color = bg_color


func _refresh_attributes() -> void:
	if _battle_power_label == null or _attack_label == null or _hp_label == null:
		return
	var attrs := LobbyState.get_player_preview_attributes()
	_battle_power_label.text = str(int(attrs.get("battle_power", 0)))
	_attack_label.text = str(int(round(float(attrs.get("attack", 0.0)))))
	_hp_label.text = str(int(attrs.get("hp", 0)))


func _setup_inventory_slots() -> void:
	if _inventory_grid == null:
		return
	_ensure_inventory_slot_count(INVENTORY_BASE_SLOTS)
	for i in range(_inventory_grid.get_child_count()):
		var btn := _inventory_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		btn.texture_normal = INVENTORY_SLOT_TEX
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
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		btn.pressed.connect(_on_bag_slot_pressed.bind(index))
		_inventory_grid.add_child(btn)
	while _inventory_grid.get_child_count() > count:
		_inventory_grid.get_child(_inventory_grid.get_child_count() - 1).queue_free()


func _apply_item_to_bag_slot(btn: TextureButton, item: Dictionary, uid: int) -> void:
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	var icon := _get_item_icon(item)
	if icon_rect != null:
		icon_rect.texture = icon
		icon_rect.visible = icon != null
	_apply_quality_visual(btn, int(item.get("quality", 0)), true)
	btn.set_meta("bag_uid", uid)


func _apply_empty_bag_slot(btn: TextureButton) -> void:
	var icon_rect := btn.get_node_or_null("ItemIcon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = null
		icon_rect.visible = false
	_apply_quality_visual(btn, 0, false)
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
	if _detail_popup == null or _btn_equip == null or _btn_unequip == null or _btn_upgrade == null:
		return
	var item := LobbyState.get_item_by_uid(uid)
	if item.is_empty():
		return
	_current_detail_uid = uid
	_detail_icon.texture = _get_item_icon(item)
	var quality := int(item.get("quality", 0))
	var quality_color := LobbyState.get_quality_color(quality)
	_detail_name_label.text = LobbyState.get_item_name(item)
	_detail_name_label.self_modulate = quality_color
	_detail_level_label.text = LanguageManager.tr_ui("UI_EQUIP_LEVEL_PART_FMT") % [
		int(item.get("level", 1)),
		LobbyState.get_slot_display_name(str(item.get("slot", ""))),
	]

	var lines: PackedStringArray = []
	for entry in LobbyState.get_item_skill_entries(item):
		var unlocked := bool(entry.get("unlocked", false))
		var quality_tier := int(entry.get("quality", LobbyState.QUALITY_COMMON))
		var text := str(entry.get("text", ""))
		var ball := _make_quality_pixel_ball(quality_tier, unlocked)
		if unlocked:
			lines.append("%s [color=#d6f7d2]%s[/color]" % [ball, text])
		else:
			lines.append("%s [color=#7a7a7a]%s[/color]" % [ball, text])
	_detail_skill_text.text = "\n".join(lines)

	var equipped := LobbyState.is_item_equipped(uid)
	_btn_equip.visible = not equipped
	_btn_unequip.visible = equipped
	_btn_upgrade.visible = equipped
	if equipped:
		var cost := LobbyState.get_upgrade_cost(item)
		_btn_upgrade.text = LanguageManager.tr_ui("UI_EQUIP_UPGRADE_COST_FMT") % cost
		_btn_upgrade.disabled = int(LobbyState.gold) < cost
		_detail_tip_label.text = LanguageManager.tr_ui("UI_EQUIP_TIP_UPGRADE")
	else:
		_detail_tip_label.text = LanguageManager.tr_ui("UI_EQUIP_TIP_WEAR")
	_detail_popup.popup_centered()


func _on_detail_equip() -> void:
	if _current_detail_uid < 0:
		return
	if LobbyState.equip_item(_current_detail_uid):
		_detail_popup.hide()
		_current_detail_uid = -1


func _on_detail_unequip() -> void:
	if _current_detail_uid < 0:
		return
	var item := LobbyState.get_item_by_uid(_current_detail_uid)
	if item.is_empty():
		return
	var slot := str(item.get("slot", ""))
	if LobbyState.unequip_slot(slot):
		_detail_popup.hide()
		_current_detail_uid = -1


func _on_detail_upgrade() -> void:
	if _current_detail_uid < 0:
		return
	var upgraded := LobbyState.upgrade_item(_current_detail_uid)
	if upgraded.is_empty():
		_detail_tip_label.text = LanguageManager.tr_ui("UI_EQUIP_TIP_NO_GOLD")
		return
	_open_item_detail(_current_detail_uid)


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


func _make_quality_pixel_ball(quality: int, unlocked: bool) -> String:
	var base := LobbyState.get_quality_color(quality)
	var fill := base if unlocked else base.lightened(0.45)
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
