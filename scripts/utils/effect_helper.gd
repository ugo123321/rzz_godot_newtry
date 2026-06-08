class_name EffectHelper

const ANIM_PREVIEW := "preview"
const PREVIEW_TARGET_SIZE := 56.0
const DEFAULT_MAX_FRAMES := 24

## 图集 + JSON（Aseprite 导出）优先；fallback 为 PNG 序列目录。
const EFFECT_ATLAS := {
	"dart": {
		"json": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/small-spark.json",
		"sheet": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/small-spark.png",
		"fallback": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark",
		"fps": 12.0,
	},
	"auto_bullet": {
		"json": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fire-missile.json",
		"sheet": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets/fire-missile.png",
		"fallback": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/fire-missile/sprites",
		"fps": 14.0,
	},
	"giant_dart": {
		"json": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/big-bolt.json",
		"sheet": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/big-bolt.png",
		"fallback": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/big-bolt",
		"fps": 12.0,
	},
	"lightning": {
		"json": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/big-bolt.json",
		"sheet": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/big-bolt.png",
		"fallback": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/big-bolt",
		"fps": 12.0,
	},
	"ice": {
		"json": "res://assets/effects/1.Gothicvania Magic Pack N1/Magic Pack  files/aseprite/ice.json",
		"sheet": "res://assets/effects/1.Gothicvania Magic Pack N1/Magic Pack  files/spritesheets/ice.png",
		"fallback": "res://assets/effects/1.Gothicvania Magic Pack N1/Magic Pack  files/ice",
		"fps": 12.0,
	},
	"spirit_bomb": {
		"json": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/small-spark-3.json",
		"sheet": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/small-spark-3.png",
		"fallback": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark-3",
		"fps": 12.0,
	},
	"fireball": {
		"json": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fireball.json",
		"sheet": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets/fireball.png",
		"fallback": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/fireball/sprites",
		"fps": 12.0,
	},
	"smoke_hit": {
		"fallback": "res://assets/effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/Smoke/sprites",
		"fps": 20.0,
		"max_frames": 17,
	},
	"hit_a": {
		"fallback": "res://assets/effects/12.Warped VFX Pack 1/Warped Fx Pack 1 Files/Sprites/Hit-a",
		"fps": 18.0,
		"max_frames": 6,
	},
	"tornado": {
		"json": "res://assets/effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/aseprite/water.json",
		"sheet": "res://assets/effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/spritesheets/water.png",
		"fallback": "res://assets/effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/sprites/water",
		"fps": 15.0,
		"tail_frames": 2,
	},
	"black_hole": {
		"json": "res://assets/effects/10.GothicVania Magic Pack 7/Magic Pack 7 files/aseprite/vfx-d.json",
		"sheet": "res://assets/effects/10.GothicVania Magic Pack 7/Magic Pack 7 files/spritesheets/vfx-d.png",
		"fallback": "res://assets/effects/10.GothicVania Magic Pack 7/Magic Pack 7 files/sprites/vfx-d",
		"fps": 12.0,
		"max_frames": 9,
	},
	"whirl": {
		"json": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/aseprite/electric-slash.json",
		"sheet": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/spritesheets/electric-slash.png",
		"fallback": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash-e",
		"fps": 14.0,
	},
	"slash_e": {
		"json": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/aseprite/electric-slash.json",
		"sheet": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/spritesheets/electric-slash.png",
		"fallback": "res://assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash-e",
		"fps": 14.0,
	},
	"flame_loop": {
		"json": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/aseprite/flame-loop.json",
		"sheet": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/spritesheets/flame-loop.png",
		"fallback": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/flame-loop",
		"fps": 12.0,
	},
	"explosion_c": {
		"json": "res://assets/effects/9.Warped Explosion Pack 5/Explosions Pack 5 Files/aseprite/explosion-c.json",
		"sheet": "res://assets/effects/9.Warped Explosion Pack 5/Explosions Pack 5 Files/spritesheets/explosion-c.png",
		"fallback": "res://assets/effects/9.Warped Explosion Pack 5/Explosions Pack 5 Files/sprites/explosion-c",
		"fps": 14.0,
		"max_frames": 15,
	},
	"laser_blast": {
		"fallback": "res://assets/effects/custom/laser-blast/sprites",
		"fps": 18.0,
		"max_frames": 4,
	},
	"fire_pillar": {
		"json": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/aseprite/fire.json",
		"sheet": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/spritesheets/fire.png",
		"fallback": "res://assets/effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/fire",
		"fps": 14.0,
	},
	"air_slash": {
		"json": "res://assets/effects/18.Gothicvania Magic Pack 12/Magic Pack 12 Files/aseprite/air-slash.json",
		"sheet": "res://assets/effects/18.Gothicvania Magic Pack 12/Magic Pack 12 Files/Spritesheets/Air-Slash.png",
		"fallback": "res://assets/effects/18.Gothicvania Magic Pack 12/Magic Pack 12 Files/Sprites/AirSlash",
		"fps": 14.0,
		"max_frames": 5,
	},
	"enemy_shotgun_arrow": {
		"json": "res://assets/effects/enemy_projectiles/aseprite/enemy_shotgun_arrow.json",
		"sheet": "res://assets/effects/enemy_projectiles/spritesheets/enemy_shotgun_arrow.png",
		"fallback": "res://assets/Characters/Characters(100x100)/Skeleton Archer/Arrow(projectile)",
		"fps": 12.0,
		"max_frames": 1,
	},
	"enemy_cross_magic": {
		"json": "res://assets/effects/enemy_projectiles/aseprite/enemy_cross_magic.json",
		"sheet": "res://assets/effects/enemy_projectiles/spritesheets/enemy_cross_magic.png",
		"fallback": "res://assets/Characters/Characters(100x100)/Priest/Magic(projectile)",
		"fps": 14.0,
		"max_frames": 8,
	},
	"enemy_bounce_blob": {
		"json": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/small-spark-3.json",
		"sheet": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/small-spark-3.png",
		"fallback": "res://assets/effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark-3",
		"fps": 12.0,
	},
}

const PREVIEW_PATHS := {
	"shuriken": "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/spark",
	"shield": "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/flash/sprites",
	"heal": "effects/4.GothicVania Magic Pack 4/Magic Pack 4 files/sprites/Cure/sprites",
	"clone": "effects/4.GothicVania Magic Pack 4/Magic Pack 4 files/sprites/wisp/sprites",
	"thunder": "effects/1.Gothicvania Magic Pack N1/Magic Pack  files/thunder",
}

const SEARCH_ALIASES := {
	"shuriken": ["spark", "shuriken", "slash"],
	"shield": ["flash", "shield", "puff"],
	"heal": ["cure", "heal"],
	"clone": ["wisp", "clone"],
	"thunder": ["thunder", "thunde", "bolt"],
}

const CHARACTER_ATLAS_JSON_DIR := "res://assets/Characters/atlases/json"
const CHARACTER_ATLAS_SHEET_DIR := "res://assets/Characters/atlases/sheets"
const EFFECT_BLACK_KEY_THRESHOLD := 0.11

static var _cache: Dictionary = {}
static var _effect_sheet_cache: Dictionary = {}


## 换特效素材后若仍显示旧图，在调试控制台执行 EffectHelper.clear_cache()，或重启 Godot。
static func clear_cache() -> void:
	_cache.clear()
	_effect_sheet_cache.clear()


static func build_effect_frames(effect_key: String) -> SpriteFrames:
	var cache_key := "effect_%s" % effect_key
	if _cache.has(cache_key):
		return _cache[cache_key]

	var cfg: Dictionary = EFFECT_ATLAS.get(effect_key, {})
	var frames: SpriteFrames = null
	var max_frames := int(cfg.get("max_frames", DEFAULT_MAX_FRAMES))

	if cfg.has("json") and cfg.has("sheet"):
		frames = _load_aseprite_json_frames(str(cfg.json), str(cfg.sheet), max_frames)

	if frames == null and cfg.has("fallback"):
		var fallback := str(cfg.fallback)
		if _dir_has_pngs(fallback):
			frames = _load_sequence_frames(fallback, max_frames)

	if frames == null and PREVIEW_PATHS.has(effect_key):
		var mapped := "res://assets/%s" % PREVIEW_PATHS[effect_key]
		if _dir_has_pngs(mapped):
			frames = _load_sequence_frames(mapped, max_frames)

	if frames == null:
		var dir_path := _resolve_preview_dir(effect_key, "")
		if not dir_path.is_empty():
			frames = _load_sequence_frames(dir_path, max_frames)

	if frames != null:
		var tail_frames := int(cfg.get("tail_frames", 0))
		if tail_frames > 0:
			frames = _slice_sprite_frames_tail(frames, ANIM_PREVIEW, tail_frames)
		if cfg.has("fps"):
			frames.set_animation_speed(ANIM_PREVIEW, float(cfg.fps))
		frames.set_animation_loop(ANIM_PREVIEW, true)
		_cache[cache_key] = frames

	return frames


static func build_projectile_frames(projectile_key: String) -> SpriteFrames:
	return build_effect_frames(projectile_key)


static func build_tornado_frames() -> SpriteFrames:
	return build_effect_frames("tornado")


static func build_fire_pillar_frames() -> SpriteFrames:
	return build_effect_frames("fire_pillar")


static func build_character_frames(folder: String, prefix: String) -> SpriteFrames:
	var cache_key := "char_%s|%s" % [folder, prefix]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var atlas_name := prefix if not prefix.is_empty() else folder
	var json_path := "%s/%s.json" % [CHARACTER_ATLAS_JSON_DIR, atlas_name]
	var sheet_path := "%s/%s.png" % [CHARACTER_ATLAS_SHEET_DIR, atlas_name]
	var frames: SpriteFrames = _load_character_atlas_frames(json_path, sheet_path)
	if frames != null and not _character_frames_complete(frames):
		frames = null
	if frames == null:
		frames = _load_character_strip_frames(folder, prefix)

	_cache[cache_key] = frames
	return frames


static func projectile_frame_texture(frames: SpriteFrames, spin: float) -> Texture2D:
	if frames == null or frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return null
	var count := frames.get_frame_count(ANIM_PREVIEW)
	var idx := int(floor(abs(spin) * 3.0)) % count
	return frames.get_frame_texture(ANIM_PREVIEW, idx)


static func animation_frame_texture(frames: SpriteFrames, anim_t: float, fps: float = -1.0) -> Texture2D:
	if frames == null or frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return null
	var count := frames.get_frame_count(ANIM_PREVIEW)
	var speed := fps
	if speed <= 0.0:
		speed = frames.get_animation_speed(ANIM_PREVIEW)
	if speed <= 0.0:
		speed = 14.0
	var idx := int(floor(anim_t * speed)) % count
	return frames.get_frame_texture(ANIM_PREVIEW, idx)


static func animation_frame_texture_once(frames: SpriteFrames, anim_t: float, fps: float = -1.0) -> Texture2D:
	if frames == null or frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return null
	var count := frames.get_frame_count(ANIM_PREVIEW)
	var speed := fps
	if speed <= 0.0:
		speed = frames.get_animation_speed(ANIM_PREVIEW)
	if speed <= 0.0:
		speed = 14.0
	var idx := int(floor(anim_t * speed))
	if idx >= count:
		return null
	return frames.get_frame_texture(ANIM_PREVIEW, idx)


static func one_shot_anim_duration(frames: SpriteFrames, fps: float = -1.0) -> float:
	if frames == null or frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return 0.5
	var count := frames.get_frame_count(ANIM_PREVIEW)
	var speed := fps
	if speed <= 0.0:
		speed = frames.get_animation_speed(ANIM_PREVIEW)
	if speed <= 0.0:
		speed = 14.0
	return float(count) / speed


static func build_upgrade_preview_frames(upgrade: Dictionary) -> SpriteFrames:
	var effect_name := str(upgrade.get("effect_name", ""))
	if effect_name.is_empty():
		return null
	var cache_key := "%s|%s" % [upgrade.get("effect_pack", ""), effect_name]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var frames: SpriteFrames = null
	var effect_pack := str(upgrade.get("effect_pack", ""))
	if int(upgrade.get("is_pet", 0)) != 0 or effect_pack.contains("Characters"):
		frames = _build_character_preview(effect_name)
	elif EFFECT_ATLAS.has(effect_name):
		frames = build_effect_frames(effect_name)
	else:
		frames = _build_effect_preview(effect_name, effect_pack)

	if frames != null:
		_cache[cache_key] = frames
	return frames


static func preview_scale(frames: SpriteFrames) -> float:
	if frames == null or frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return 1.0
	var tex := frames.get_frame_texture(ANIM_PREVIEW, 0)
	if tex == null:
		return 1.0
	var size := tex.get_size()
	return SpriteHelper.pixel_scale(PREVIEW_TARGET_SIZE / maxf(size.x, size.y))


static func _build_character_preview(name: String) -> SpriteFrames:
	var source := build_character_frames(name, name)
	if source == null or source.get_frame_count(SpriteHelper.ANIM_IDLE) <= 0:
		return null
	var frames := SpriteFrames.new()
	frames.add_animation(ANIM_PREVIEW)
	for i in range(source.get_frame_count(SpriteHelper.ANIM_IDLE)):
		frames.add_frame(ANIM_PREVIEW, source.get_frame_texture(SpriteHelper.ANIM_IDLE, i))
	frames.set_animation_speed(ANIM_PREVIEW, maxf(6.0, source.get_animation_speed(SpriteHelper.ANIM_IDLE)))
	frames.set_animation_loop(ANIM_PREVIEW, true)
	return frames


static func _build_effect_preview(effect_name: String, effect_pack: String) -> SpriteFrames:
	if EFFECT_ATLAS.has(effect_name):
		return build_effect_frames(effect_name)
	var dir_path := _resolve_preview_dir(effect_name, effect_pack)
	if dir_path.is_empty():
		return null
	return _load_sequence_frames(dir_path, DEFAULT_MAX_FRAMES)


static func _resolve_preview_dir(effect_name: String, effect_pack: String) -> String:
	if PREVIEW_PATHS.has(effect_name):
		var mapped := "res://assets/%s" % PREVIEW_PATHS[effect_name]
		if _dir_has_pngs(mapped):
			return mapped

	if not effect_pack.is_empty():
		var pack_base := "res://assets/%s" % effect_pack
		if _dir_has_pngs(pack_base):
			var aliases: Array = SEARCH_ALIASES.get(effect_name, [effect_name])
			var found := _search_sequence_dir(pack_base, aliases)
			if not found.is_empty():
				return found
	return ""


static func _res_exists(res_path: String) -> bool:
	return ResourceLoader.exists(res_path) or FileAccess.file_exists(res_path)


static func _read_text_from_res(res_path: String) -> String:
	if FileAccess.file_exists(res_path):
		return FileAccess.get_file_as_string(res_path)
	return ""


static func _load_image_from_res(res_path: String) -> Image:
	if not res_path.begins_with("res://"):
		return null
	if ResourceLoader.exists(res_path):
		var res: Resource = load(res_path)
		if res is Texture2D:
			var image := (res as Texture2D).get_image()
			if image != null and not image.is_empty():
				return image
	if FileAccess.file_exists(res_path):
		var image := Image.new()
		if image.load(res_path) == OK:
			return image
	if OS.has_feature("web"):
		return null
	var fs_path := ProjectSettings.globalize_path(res_path)
	if fs_path.is_empty() or not FileAccess.file_exists(fs_path):
		return null
	var fs_image := Image.new()
	if fs_image.load(fs_path) != OK:
		return null
	return fs_image


static func _load_texture_from_path(res_path: String) -> Texture2D:
	var image := _load_image_from_res(res_path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


static func _key_effect_black_to_alpha(image: Image) -> void:
	if image.is_empty():
		return
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) <= EFFECT_BLACK_KEY_THRESHOLD:
				image.set_pixel(x, y, Color(0, 0, 0, 0))


static func _load_effect_texture_res(res_path: String) -> Texture2D:
	if not res_path.begins_with("res://"):
		return null
	if _effect_sheet_cache.has(res_path):
		return _effect_sheet_cache[res_path]
	var image := _load_image_from_res(res_path)
	if image == null:
		return null
	_key_effect_black_to_alpha(image)
	var texture := ImageTexture.create_from_image(image)
	_effect_sheet_cache[res_path] = texture
	return texture


static func _load_effect_sheet_texture(json_path: String, sheet_path: String, parsed: Dictionary) -> Texture2D:
	var sheet := _load_effect_texture_res(sheet_path)
	if sheet != null:
		return sheet
	var image_name := str(parsed.get("meta", {}).get("image", ""))
	if image_name.is_empty():
		return null
	return _load_effect_texture_res(json_path.get_base_dir().path_join(image_name))


static func _load_sheet_texture(json_path: String, sheet_path: String, parsed: Dictionary) -> Texture2D:
	var sheet := _load_texture_from_path(sheet_path)
	if sheet != null:
		return sheet
	var image_name := str(parsed.get("meta", {}).get("image", ""))
	if image_name.is_empty():
		return null
	return _load_texture_from_path(json_path.get_base_dir().path_join(image_name))


static func _search_sequence_dir(root: String, aliases: Array, depth: int = 0) -> String:
	if depth > 6:
		return ""
	var dir := DirAccess.open(root)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			var full := root.path_join(entry)
			var lower := entry.to_lower()
			for alias in aliases:
				if lower.contains(str(alias).to_lower()):
					if _count_png_files(full) > 0:
						dir.list_dir_end()
						return full
			var nested := _search_sequence_dir(full, aliases, depth + 1)
			if not nested.is_empty():
				dir.list_dir_end()
				return nested
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


static func _load_sequence_frames(dir_path: String, max_frames: int = DEFAULT_MAX_FRAMES) -> SpriteFrames:
	var files := _collect_png_files(dir_path)
	if files.is_empty():
		return null
	files = _natural_sort(files)
	var frames := SpriteFrames.new()
	frames.add_animation(ANIM_PREVIEW)
	for path in files:
		if frames.get_frame_count(ANIM_PREVIEW) >= max_frames:
			break
		var tex: Texture2D = _load_effect_texture_res(path)
		if tex == null:
			continue
		var tex_w := tex.get_width()
		var tex_h := tex.get_height()
		if tex_w > 96 and tex_w >= tex_h * 2:
			for atlas in _slice_texture(tex, 48, 48):
				frames.add_frame(ANIM_PREVIEW, atlas)
				if frames.get_frame_count(ANIM_PREVIEW) >= max_frames:
					break
		else:
			frames.add_frame(ANIM_PREVIEW, tex)
	if frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return null
	frames.set_animation_speed(ANIM_PREVIEW, 10.0)
	frames.set_animation_loop(ANIM_PREVIEW, true)
	return frames


static func _slice_sprite_frames_tail(source: SpriteFrames, anim_name: String, tail_count: int) -> SpriteFrames:
	if source == null or not source.has_animation(anim_name):
		return source
	var count := source.get_frame_count(anim_name)
	if count <= tail_count:
		return source
	var frames := SpriteFrames.new()
	frames.add_animation(anim_name)
	var start_idx := count - tail_count
	for i in range(start_idx, count):
		frames.add_frame(
			anim_name,
			source.get_frame_texture(anim_name, i),
			source.get_frame_duration(anim_name, i)
		)
	frames.set_animation_speed(anim_name, source.get_animation_speed(anim_name))
	frames.set_animation_loop(anim_name, true)
	return frames


static func _load_aseprite_json_frames(json_path: String, sheet_path: String, max_frames: int = DEFAULT_MAX_FRAMES) -> SpriteFrames:
	if not _res_exists(json_path):
		return null
	var parsed: Variant = JSON.parse_string(_read_text_from_res(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var frame_list: Array = parsed.get("frames", [])
	if frame_list.is_empty():
		return null

	var sheet: Texture2D = _load_effect_sheet_texture(json_path, sheet_path, parsed)
	if sheet == null:
		return null

	var min_duration := 100000
	for frame_data in frame_list:
		var duration := int(frame_data.get("duration", 100))
		if duration < min_duration:
			min_duration = duration
	if min_duration <= 0:
		min_duration = 100

	var frames := SpriteFrames.new()
	frames.add_animation(ANIM_PREVIEW)
	for frame_data in frame_list:
		if frames.get_frame_count(ANIM_PREVIEW) >= max_frames:
			break
		var rect: Dictionary = frame_data.get("frame", {})
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.filter_clip = true
		atlas.region = Rect2(
			float(rect.get("x", 0)),
			float(rect.get("y", 0)),
			float(rect.get("w", 0)),
			float(rect.get("h", 0))
		)
		var duration: float = float(frame_data.get("duration", min_duration)) / float(min_duration)
		frames.add_frame(ANIM_PREVIEW, atlas, duration)

	if frames.get_frame_count(ANIM_PREVIEW) <= 0:
		return null

	var fps: float = float(ceil(1000.0 / float(min_duration)))
	frames.set_animation_speed(ANIM_PREVIEW, fps)
	frames.set_animation_loop(ANIM_PREVIEW, true)
	return frames


static func _character_frames_complete(frames: SpriteFrames) -> bool:
	for anim_name in [SpriteHelper.ANIM_IDLE, SpriteHelper.ANIM_ATTACK, SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_DEATH]:
		if not frames.has_animation(anim_name) or frames.get_frame_count(anim_name) <= 0:
			return false
	return true


static func _character_tag_to_anim(tag_name: String) -> String:
	var lower := tag_name.to_lower().strip_edges()
	if lower.ends_with("_effect") and not lower.contains("with"):
		return ""
	if lower.contains(" with effect"):
		lower = lower.replace(" with effect", "")
	lower = lower.replace(" ", "")
	if lower == "attack01":
		return SpriteHelper.ANIM_ATTACK01
	if lower.begins_with("attack"):
		return SpriteHelper.ANIM_ATTACK
	if lower.begins_with("walk"):
		return SpriteHelper.ANIM_WALK
	match lower:
		"idle":
			return SpriteHelper.ANIM_IDLE
		"walk":
			return SpriteHelper.ANIM_WALK
		"hurt":
			return SpriteHelper.ANIM_HURT
		"death":
			return SpriteHelper.ANIM_DEATH
		_:
			return ""


static func _load_character_atlas_frames(json_path: String, sheet_path: String) -> SpriteFrames:
	if not _res_exists(json_path):
		return null
	var parsed: Variant = JSON.parse_string(_read_text_from_res(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var frame_list: Array = parsed.get("frames", [])
	var frame_tags: Array = parsed.get("meta", {}).get("frameTags", [])
	if frame_list.is_empty() or frame_tags.is_empty():
		return null

	var sheet: Texture2D = _load_sheet_texture(json_path, sheet_path, parsed)
	if sheet == null:
		return null

	var min_duration := 100000
	for frame_data in frame_list:
		var duration := int(frame_data.get("duration", 100))
		if duration < min_duration:
			min_duration = duration
	if min_duration <= 0:
		min_duration = 100

	var frames := SpriteFrames.new()
	for tag in frame_tags:
		var anim_name := _character_tag_to_anim(str(tag.get("name", "")))
		if anim_name.is_empty():
			continue
		if not frames.has_animation(anim_name):
			frames.add_animation(anim_name)
		var from_idx := int(tag.get("from", 0))
		var to_idx := int(tag.get("to", from_idx))
		for idx in range(from_idx, to_idx + 1):
			if idx < 0 or idx >= frame_list.size():
				continue
			var frame_data: Dictionary = frame_list[idx]
			var rect: Dictionary = frame_data.get("frame", {})
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.filter_clip = true
			atlas.region = Rect2(
				float(rect.get("x", 0)),
				float(rect.get("y", 0)),
				float(rect.get("w", 0)),
				float(rect.get("h", 0))
			)
			var duration: float = float(frame_data.get("duration", min_duration)) / float(min_duration)
			frames.add_frame(anim_name, atlas, duration)

	if not frames.has_animation(SpriteHelper.ANIM_IDLE):
		return null

	for anim_name in [SpriteHelper.ANIM_IDLE, SpriteHelper.ANIM_WALK, SpriteHelper.ANIM_ATTACK, SpriteHelper.ANIM_ATTACK01, SpriteHelper.ANIM_HURT, SpriteHelper.ANIM_DEATH]:
		if frames.has_animation(anim_name):
			SpriteHelper.configure_animation(frames, anim_name)
	return frames


static func _load_character_strip_frames(folder: String, prefix: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var base_dir := "res://assets/Characters/Characters(100x100)/%s/%s" % [folder, prefix]
	var mapping := {
		SpriteHelper.ANIM_IDLE: ["%s-Idle.png" % prefix],
		SpriteHelper.ANIM_WALK: ["%s-Walk.png" % prefix, "%s-Walk01.png" % prefix, "%s-Walk02.png" % prefix],
		SpriteHelper.ANIM_ATTACK01: ["%s-Attack01.png" % prefix],
		SpriteHelper.ANIM_ATTACK: ["%s-Attack.png" % prefix, "%s-Attack02.png" % prefix, "%s-Attack03.png" % prefix, "%s-Attack3.png" % prefix],
		SpriteHelper.ANIM_HURT: ["%s-Hurt.png" % prefix],
		SpriteHelper.ANIM_DEATH: ["%s-Death.png" % prefix, "%s-DEATH.png" % prefix],
	}
	for anim_name in mapping.keys():
		frames.add_animation(anim_name)
		for file_name in mapping[anim_name]:
			var path := base_dir.path_join(file_name)
			if not ResourceLoader.exists(path):
				continue
			var tex: Texture2D = load(path)
			if tex == null:
				continue
			for region in SpriteHelper.slice_texture_grid(tex, SpriteHelper.FRAME_W, SpriteHelper.FRAME_H):
				frames.add_frame(anim_name, region)
		SpriteHelper.configure_animation(frames, anim_name)
		if anim_name == SpriteHelper.ANIM_IDLE and frames.get_frame_count(anim_name) == 0:
			SpriteHelper.add_fallback_idle_frame(frames, base_dir, prefix)
	if not frames.has_animation(SpriteHelper.ANIM_IDLE) or frames.get_frame_count(SpriteHelper.ANIM_IDLE) <= 0:
		return null
	return frames


static func _collect_png_files(dir_path: String) -> Array:
	var result := _collect_png_files_diraccess(dir_path)
	if not result.is_empty():
		return result
	return _collect_png_files_by_name_probe(dir_path)


static func _collect_png_files_diraccess(dir_path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			result.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	if result.is_empty():
		dir = DirAccess.open(dir_path)
		if dir == null:
			return result
		dir.list_dir_begin()
		entry = dir.get_next()
		while entry != "":
			if entry != "." and entry != ".." and dir.current_is_dir():
				var nested := _collect_png_files_diraccess(dir_path.path_join(entry))
				if not nested.is_empty():
					dir.list_dir_end()
					return nested
			entry = dir.get_next()
		dir.list_dir_end()
	return result


static func _guess_name_prefixes(dir_path: String) -> Array:
	var prefixes: Array = []
	var seen: Dictionary = {}
	for raw_name in [dir_path.get_file(), dir_path.get_base_dir().get_file()]:
		for variant in [raw_name, raw_name.to_lower()]:
			if variant.is_empty() or seen.has(variant):
				continue
			seen[variant] = true
			if variant.to_lower() == "sprites":
				continue
			prefixes.append(variant)
	return prefixes


static func _collect_png_files_by_name_probe(dir_path: String) -> Array:
	for prefix in _guess_name_prefixes(dir_path):
		var files: Array = []
		for i in range(1, DEFAULT_MAX_FRAMES + 1):
			var found := false
			for fmt in ["%s%d.png", "%s%02d.png", "%s%03d.png"]:
				var path := dir_path.path_join(fmt % [prefix, i])
				if _res_exists(path):
					files.append(path)
					found = true
			if not found and not files.is_empty():
				break
		if not files.is_empty():
			return _natural_sort(files)
	return []


static func _dir_has_pngs(dir_path: String) -> bool:
	return not _collect_png_files(dir_path).is_empty()


static func _count_png_files(dir_path: String) -> int:
	return _collect_png_files(dir_path).size()


static func _natural_sort(paths: Array) -> Array:
	paths.sort_custom(func(a, b): return _extract_num(str(a)) < _extract_num(str(b)))
	return paths


static func _extract_num(path: String) -> int:
	var file := path.get_file().get_basename()
	var digits := ""
	for i in range(file.length() - 1, -1, -1):
		var ch := file[i]
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif not digits.is_empty():
			break
	if digits.is_empty():
		return 0
	return int(digits)


static func _slice_texture(tex: Texture2D, frame_w: int, frame_h: int) -> Array:
	var result: Array = []
	var cols := maxi(1, int(tex.get_width() / frame_w))
	var rows := maxi(1, int(tex.get_height() / frame_h))
	for row in range(rows):
		for col in range(cols):
			if (col + 1) * frame_w > tex.get_width() or (row + 1) * frame_h > tex.get_height():
				continue
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.filter_clip = true
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			result.append(atlas)
	return result
