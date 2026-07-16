extends Control
class_name LoadingScreen

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const MIN_LOAD_TIME := 2.0
const LOADING_BG_PATH := "res://assets/ui/backgrounds/loading_bg.png"
const SCROLL_SPEED := 100.0
const FADE_DURATION := 0.35

enum State { FADE_IN, LOADING, FADE_OUT, DONE }

@onready var _background: TextureRect = %Background
@onready var _title_label: Label = %TitleLabel
@onready var _status_label: Label = %StatusLabel
@onready var _tip_label: Label = %TipLabel
@onready var _fade: ColorRect = %Fade

var _elapsed := 0.0
var _scene_ready := false
var _state := State.FADE_IN
var _fade_t := 0.0
var _bg_tex: Texture2D = null
var _scroll_tiles: Array[TextureRect] = []
var _scroll_tile_width := 0.0


func _ready() -> void:
	PixelUi.apply_ui_font_tree(self)
	_apply_background()
	_refresh_tip()
	_status_label.text = LanguageManager.tr_ui("UI_LOADING_LOADING")
	_title_label.text = LanguageManager.tr_ui("UI_LOADING_READY")
	_state = State.FADE_IN
	_fade_t = 0.0
	_set_fade_alpha(1.0)
	ResourceLoader.load_threaded_request(BATTLE_SCENE)


func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	_elapsed += delta
	_animate_bg_scroll(delta)
	match _state:
		State.FADE_IN:
			_fade_t += delta
			_set_fade_alpha(1.0 - clampf(_fade_t / FADE_DURATION, 0.0, 1.0))
			if _fade_t >= FADE_DURATION:
				_state = State.LOADING
				_fade_t = 0.0
				_set_fade_alpha(0.0)
		State.LOADING:
			_poll_load_status()
			_update_status_dots()
			if _scene_ready and _elapsed >= MIN_LOAD_TIME:
				_begin_fade_out()
		State.FADE_OUT:
			_fade_t += delta
			_set_fade_alpha(clampf(_fade_t / FADE_DURATION, 0.0, 1.0))
			_update_status_dots()
			if _fade_t >= FADE_DURATION:
				_change_scene()


func _apply_background() -> void:
	if _background == null:
		return
	_bg_tex = load(LOADING_BG_PATH) as Texture2D
	if _bg_tex == null:
		return
	_setup_bg_scroll()


# 将静态 Background 节点改造成横向卷轴宿主：两个相同贴片左右拼接，
# 每帧右移，移出一屏宽度时跳到另一贴片后方 —— 与主界面背景同款无缝循环。
func _setup_bg_scroll() -> void:
	if _bg_tex == null or _background == null:
		return
	_background.texture = null
	_background.clip_contents = true
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _background.resized.is_connected(_refresh_bg_scroll_layout):
		_background.resized.connect(_refresh_bg_scroll_layout)
	for i in 2:
		var tile := TextureRect.new()
		tile.name = "BgTile" + ("A" if i == 0 else "B")
		tile.texture = _bg_tex
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_background.add_child(tile)
		_scroll_tiles.append(tile)
	_refresh_bg_scroll_layout()


func _refresh_bg_scroll_layout() -> void:
	if _scroll_tiles.size() < 2 or _background == null:
		return
	var view_size := _background.size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	_scroll_tile_width = view_size.x
	for tile in _scroll_tiles:
		tile.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		tile.size = view_size
	_scroll_tiles[0].position = Vector2.ZERO
	_scroll_tiles[1].position = Vector2(_scroll_tile_width, 0.0)


func _animate_bg_scroll(delta: float) -> void:
	if _scroll_tiles.size() < 2 or SCROLL_SPEED <= 0.0:
		return
	if _scroll_tile_width <= 0.0:
		_refresh_bg_scroll_layout()
		return
	var dx := SCROLL_SPEED * delta
	for tile in _scroll_tiles:
		tile.position.x += dx
	for i in 2:
		var tile := _scroll_tiles[i]
		if tile.position.x >= _scroll_tile_width:
			var other := _scroll_tiles[1 - i]
			tile.position.x = other.position.x - _scroll_tile_width


func _refresh_tip() -> void:
	if _tip_label == null:
		return
	var idx := LobbyState.stage_index
	var stage := GameConfig.get_stage(idx)
	var chapter := GameConfig.get_chapter_for_stage(idx)
	var default_chapter := LanguageManager.tr_ui("UI_LOADING_DEFAULT_CHAPTER")
	var chapter_name := LanguageManager.localize_field(chapter, "chapter_name_en", "chapter_name")
	if chapter_name.is_empty():
		chapter_name = default_chapter
	var stage_name := LanguageManager.localize_field(stage, "display_name_en", "display_name")
	if stage_name.is_empty():
		_tip_label.text = chapter_name
	else:
		_tip_label.text = LanguageManager.tr_ui("UI_LOADING_CHAPTER_STAGE_FMT") % [chapter_name, stage_name]


func _poll_load_status() -> void:
	var status := ResourceLoader.load_threaded_get_status(BATTLE_SCENE)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			_scene_ready = true
		ResourceLoader.THREAD_LOAD_FAILED:
			_status_label.text = LanguageManager.tr_ui("UI_LOADING_FAILED")
			_state = State.DONE
			set_process(false)


func _update_status_dots() -> void:
	if _status_label == null:
		return
	var dot_count := int(floorf(_elapsed * 2.0)) % 4
	_status_label.text = LanguageManager.tr_ui("UI_LOADING_LOADING") + ".".repeat(dot_count)


func _begin_fade_out() -> void:
	_state = State.FADE_OUT
	_fade_t = 0.0
	_status_label.text = LanguageManager.tr_ui("UI_LOADING_GO")


func _change_scene() -> void:
	_state = State.DONE
	set_process(false)
	var scene := ResourceLoader.load_threaded_get(BATTLE_SCENE) as PackedScene
	if scene == null:
		scene = load(BATTLE_SCENE) as PackedScene
	if scene == null:
		_state = State.LOADING
		_status_label.text = LanguageManager.tr_ui("UI_LOADING_FAILED")
		set_process(true)
		return
	get_tree().change_scene_to_packed(scene)


func _set_fade_alpha(a: float) -> void:
	if _fade == null:
		return
	_fade.color.a = clampf(a, 0.0, 1.0)
