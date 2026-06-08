extends Control
class_name LoadingScreen

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const MIN_LOAD_TIME := 0.3
const PROGRESS_SPEED := 1.2

@onready var _background: TextureRect = %Background
@onready var _title_label: Label = %TitleLabel
@onready var _status_label: Label = %StatusLabel
@onready var _tip_label: Label = %TipLabel
@onready var _progress_fill: ColorRect = %ProgressFill
@onready var _progress_track: Control = %ProgressTrack

var _elapsed := 0.0
var _scene_ready := false
var _transitioning := false
var _display_progress := 0.0


func _ready() -> void:
	PixelUi.apply_ui_font_tree(self)
	_apply_background()
	_refresh_tip()
	_status_label.text = "加载中"
	_title_label.text = "准备出发"
	_display_progress = 0.0
	_apply_progress_bar(0.0)
	ResourceLoader.load_threaded_request(BATTLE_SCENE)


func _process(delta: float) -> void:
	if _transitioning:
		return
	_elapsed += delta
	_update_load_progress(delta)
	_update_status_dots()
	if _scene_ready and _elapsed >= MIN_LOAD_TIME and _display_progress >= 0.999:
		_finish_loading()


func _apply_background() -> void:
	if _background == null:
		return
	var tex := load("res://assets/ui/home/bg_stage01.png") as Texture2D
	if tex != null:
		_background.texture = tex
		_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _refresh_tip() -> void:
	if _tip_label == null:
		return
	var idx := LobbyState.stage_index
	var stage := GameConfig.get_stage(idx)
	var chapter := GameConfig.get_chapter_for_stage(idx)
	var chapter_name := str(chapter.get("chapter_name", "冒险"))
	var stage_name := str(stage.get("display_name", ""))
	if stage_name.is_empty():
		_tip_label.text = chapter_name
	else:
		_tip_label.text = "%s · %s" % [chapter_name, stage_name]


func _update_load_progress(delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(BATTLE_SCENE)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			_scene_ready = true
		ResourceLoader.THREAD_LOAD_FAILED:
			_status_label.text = "加载失败，请重试"
			set_process(false)
			return

	var time_ratio := clampf(_elapsed / MIN_LOAD_TIME, 0.0, 1.0)
	var target := time_ratio * 0.94
	if _scene_ready:
		target = maxf(target, 0.94)
	if _scene_ready and _elapsed >= MIN_LOAD_TIME:
		target = 1.0
	_display_progress = move_toward(_display_progress, target, delta * PROGRESS_SPEED)
	_apply_progress_bar(_display_progress)


func _apply_progress_bar(ratio: float) -> void:
	if _progress_fill == null or _progress_track == null:
		return
	var width := _progress_track.size.x * clampf(ratio, 0.0, 1.0)
	_progress_fill.size.x = width


func _update_status_dots() -> void:
	if _status_label == null:
		return
	var dot_count := int(floorf(_elapsed * 2.0)) % 4
	_status_label.text = "加载中" + ".".repeat(dot_count)


func _finish_loading() -> void:
	if _transitioning:
		return
	_transitioning = true
	set_process(false)
	_status_label.text = "出发！"
	_apply_progress_bar(1.0)
	var scene := ResourceLoader.load_threaded_get(BATTLE_SCENE) as PackedScene
	if scene == null:
		scene = load(BATTLE_SCENE) as PackedScene
	if scene == null:
		_transitioning = false
		_status_label.text = "加载失败，请重试"
		set_process(true)
		return
	get_tree().change_scene_to_packed(scene)
