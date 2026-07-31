extends Control
class_name SettingsPopup

# 主界面设置弹窗：从主界面右上角设置按钮打开。
# 当前只放一个「关卡编辑器」入口；未来可扩展语言/音量等设置项。

signal level_editor_requested
signal delete_save_requested
signal closed

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const UiStyle := preload("res://scripts/utils/ui_style_helper.gd")

var _overlay: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_texts()
	EventBus.language_changed.connect(_on_language_changed)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.05, 0.1, 0.6)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_gui)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 200)
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -140
	_panel.offset_right = 140
	_panel.offset_top = -100
	_panel.offset_bottom = 100
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_vbox)

	# 标题
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	_vbox.add_child(title)

	# 关卡编辑器按钮
	var editor_btn := Button.new()
	editor_btn.name = "EditorBtn"
	editor_btn.custom_minimum_size = Vector2(200, 0)
	UiStyle.apply_primary_button(editor_btn, Color("#7a6a90"), 8)
	PixelUi.apply_ui_font(editor_btn)
	editor_btn.pressed.connect(_on_editor_pressed)
	_vbox.add_child(editor_btn)

	# 删除存档按钮（破坏性操作，红色调）
	var delete_btn := Button.new()
	delete_btn.name = "DeleteBtn"
	delete_btn.custom_minimum_size = Vector2(200, 0)
	UiStyle.apply_primary_button(delete_btn, Color("#785555"), 8)
	PixelUi.apply_ui_font(delete_btn)
	delete_btn.pressed.connect(_on_delete_save_pressed)
	_vbox.add_child(delete_btn)

	# 返回按钮
	var back_btn := Button.new()
	back_btn.name = "BackBtn"
	back_btn.custom_minimum_size = Vector2(200, 0)
	UiStyle.apply_primary_button(back_btn, Color("#5a6a90"), 8)
	PixelUi.apply_ui_font(back_btn)
	back_btn.pressed.connect(_on_back_pressed)
	_vbox.add_child(back_btn)


func _apply_texts() -> void:
	if _vbox:
		var t := _vbox.get_node_or_null("Title")
		if t:
			t.text = LanguageManager.tr_ui("UI_SETTINGS_TITLE")
		var e := _vbox.get_node_or_null("EditorBtn")
		if e:
			e.text = LanguageManager.tr_ui("UI_SETTINGS_LEVEL_EDITOR")
		var d := _vbox.get_node_or_null("DeleteBtn")
		if d:
			d.text = LanguageManager.tr_ui("UI_SETTINGS_DELETE_SAVE")
		var b := _vbox.get_node_or_null("BackBtn")
		if b:
			b.text = LanguageManager.tr_ui("UI_SETTINGS_BACK")


func _on_language_changed(_lang: String) -> void:
	_apply_texts()


func _on_editor_pressed() -> void:
	level_editor_requested.emit()
	_close()


func _on_delete_save_pressed() -> void:
	delete_save_requested.emit()
	_close()


func _on_back_pressed() -> void:
	_close()


func _on_overlay_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	closed.emit()
	queue_free()
