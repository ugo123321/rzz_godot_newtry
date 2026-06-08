class_name SpriteHelper

const TEXTURE_FILTER_NEAREST := CanvasItem.TEXTURE_FILTER_NEAREST

const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_ATTACK := "attack"
const ANIM_ATTACK01 := "attack01"
const ANIM_HURT := "hurt"
const ANIM_DEATH := "death"

const FRAME_W := 100
const FRAME_H := 100
const CHAR_HEAD_Y_FACTOR := 0.36


static func get_character_head_top_global(sprite: Node2D, fallback_global: Vector2) -> Vector2:
	if sprite == null or not is_instance_valid(sprite):
		return fallback_global
	var head_local_y := -FRAME_H * 0.5 * CHAR_HEAD_Y_FACTOR
	return sprite.to_global(Vector2(0.0, head_local_y))


static func draw_effect_texture(
	canvas: CanvasItem,
	tex: Texture2D,
	position: Vector2,
	rotation: float,
	scale: Vector2,
	modulate: Color = Color.WHITE
) -> void:
	if tex == null:
		return
	apply_pixel_art(canvas)
	canvas.draw_set_transform(position, rotation, scale)
	canvas.draw_texture(tex, -tex.get_size() * 0.5, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_effect_texture_rect(
	canvas: CanvasItem,
	tex: Texture2D,
	rect: Rect2,
	modulate: Color = Color.WHITE
) -> void:
	if tex == null:
		return
	apply_pixel_art(canvas)
	canvas.draw_texture_rect(tex, rect, false, modulate)


static func draw_effect_texture_bottom_center(
	canvas: CanvasItem,
	tex: Texture2D,
	bottom_center: Vector2,
	scale: Vector2,
	modulate: Color = Color.WHITE
) -> void:
	if tex == null:
		return
	apply_pixel_art(canvas)
	var draw_size := tex.get_size() * scale
	var top_left := bottom_center - Vector2(draw_size.x * 0.5, draw_size.y)
	canvas.draw_texture_rect(tex, Rect2(top_left, draw_size), false, modulate)


static func is_priority_anim(anim_name: String) -> bool:
	return anim_name in [ANIM_ATTACK, ANIM_ATTACK01, ANIM_HURT, ANIM_DEATH]


static func is_playing_priority_anim(sprite: AnimatedSprite2D) -> bool:
	if sprite == null or sprite.sprite_frames == null or not sprite.is_playing():
		return false
	return is_priority_anim(sprite.animation)


static func apply_pixel_art(node: CanvasItem) -> void:
	if node == null:
		return
	node.texture_filter = TEXTURE_FILTER_NEAREST


static func pixel_scale(base: float, size_mult: float = 1.0) -> float:
	# 像素素材只用 0.5 步进缩放，避免非整数缩放糊边
	var raw := base * size_mult
	return maxf(0.5, round(raw * 2.0) / 2.0)


static func build_character_frames(folder: String, prefix: String) -> SpriteFrames:
	return EffectHelper.build_character_frames(folder, prefix)


static func configure_animation(frames: SpriteFrames, anim_name: String) -> void:
	var frame_count := frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return
	match anim_name:
		ANIM_IDLE:
			frames.set_animation_speed(anim_name, 6.0 if frame_count > 1 else 0.0)
			frames.set_animation_loop(anim_name, frame_count > 1)
		ANIM_WALK:
			frames.set_animation_speed(anim_name, 10.0)
			frames.set_animation_loop(anim_name, true)
		ANIM_ATTACK:
			frames.set_animation_speed(anim_name, 12.0)
			frames.set_animation_loop(anim_name, false)
		ANIM_ATTACK01:
			frames.set_animation_speed(anim_name, 12.0)
			frames.set_animation_loop(anim_name, false)
		ANIM_HURT, ANIM_DEATH:
			frames.set_animation_speed(anim_name, 8.0)
			frames.set_animation_loop(anim_name, false)
		_:
			frames.set_animation_speed(anim_name, 8.0)
			frames.set_animation_loop(anim_name, frame_count > 1)


static func sync_attack01_speed(frames: SpriteFrames, interval: float) -> void:
	if frames == null or not frames.has_animation(ANIM_ATTACK01) or interval <= 0.0:
		return
	var frame_count := frames.get_frame_count(ANIM_ATTACK01)
	if frame_count <= 0:
		return
	var total_duration := 0.0
	for i in range(frame_count):
		total_duration += frames.get_frame_duration(ANIM_ATTACK01, i)
	if total_duration <= 0.0:
		total_duration = float(frame_count)
	frames.set_animation_speed(ANIM_ATTACK01, total_duration / interval)


static func add_fallback_idle_frame(frames: SpriteFrames, base_dir: String, prefix: String) -> void:
	var path := base_dir.path_join("%s.png" % prefix)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 0, FRAME_W, FRAME_H)
	frames.add_frame(ANIM_IDLE, atlas)
	configure_animation(frames, ANIM_IDLE)


static func slice_texture_grid(tex: Texture2D, frame_w: int, frame_h: int) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []
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
