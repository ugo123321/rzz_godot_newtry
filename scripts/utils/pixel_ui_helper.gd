extends RefCounted
class_name PixelUiHelper

const UI_FONT_PATH := "res://assets/ui/Fonts/NotoSansSC-Regular.otf"
const EXP_BAR_HEIGHT := 18.0
const PIXEL_FONT_BASE := 8
const TITLE_FONT_BASE := 11

static var _ui_font: Font


static func _load_ui_font() -> Font:
	if not ResourceLoader.exists(UI_FONT_PATH):
		return null
	var loaded := load(UI_FONT_PATH)
	if loaded is FontFile:
		var font := (loaded as FontFile).duplicate(true) as FontFile
		font.modulate_color_glyphs = true
		font.clear_cache()
		return font
	return loaded as Font


static func _ensure_fonts_loaded() -> void:
	if _ui_font == null:
		_ui_font = _load_ui_font()


static func get_ui_font(_use_title: bool = false) -> Font:
	_ensure_fonts_loaded()
	if _ui_font != null:
		return _ui_font
	return ThemeDB.fallback_font


static func get_cjk_font() -> Font:
	return get_ui_font()


static func apply_ui_font(control: Control) -> void:
	var font := get_ui_font()
	if font == null:
		return
	control.add_theme_font_override("font", font)


static func apply_ui_font_tree(root: Node) -> void:
	if root is Control:
		apply_ui_font(root as Control)
	for child in root.get_children():
		apply_ui_font_tree(child)


static func snap_pixel_font_size(size: int, base: int = PIXEL_FONT_BASE) -> int:
	return maxi(base, int(round(float(size) / float(base))) * base)


static func _snap_pos(pos: Vector2) -> Vector2:
	return Vector2(roundi(pos.x), roundi(pos.y))


static func _ui_scale() -> float:
	return GameConfig.get_resolution_scale() * GameConfig.get_ui_scale()


static func _scaled(v: float) -> float:
	return v * _ui_scale()


static func get_font() -> Font:
	return get_ui_font()


static func get_title_font() -> Font:
	return get_ui_font()


static func _get_font_for_text(_text: String, _use_title_font: bool = false) -> Font:
	return get_ui_font()


static func _text_shadow_color(color: Color) -> Color:
	return Color(color.r * 0.28, color.g * 0.28, color.b * 0.28, color.a)


static func draw_pixel_panel(
	canvas: CanvasItem,
	rect: Rect2,
	fill: Color,
	border: Color,
	border_px: int = 2
) -> void:
	var bx := int(floor(rect.position.x))
	var by := int(floor(rect.position.y))
	var bw := int(floor(rect.size.x))
	var bh := int(floor(rect.size.y))
	var bp := maxi(1, border_px)
	canvas.draw_rect(Rect2(bx, by, bw, bh), border)
	canvas.draw_rect(Rect2(bx + bp, by + bp, bw - bp * 2, bh - bp * 2), fill)


static func draw_pixel_text(
	canvas: CanvasItem,
	text: String,
	pos: Vector2,
	font_size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
	baseline: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER,
	use_title_font: bool = false
) -> void:
	if text.is_empty():
		return
	var font := _get_font_for_text(text, use_title_font)
	var size := font.get_string_size(text, align, -1, font_size)
	var draw_pos := pos
	match align:
		HORIZONTAL_ALIGNMENT_CENTER:
			draw_pos.x -= size.x * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			draw_pos.x -= size.x
	match baseline:
		VERTICAL_ALIGNMENT_CENTER:
			draw_pos.y += (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			draw_pos.y -= font.get_descent(font_size)
		_:
			draw_pos.y -= font.get_ascent(font_size)
	draw_pos = _snap_pos(draw_pos)
	var shadow := 1
	var shadow_color := _text_shadow_color(color)
	canvas.draw_string(
		font, draw_pos + Vector2(shadow, shadow), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color
	)
	canvas.draw_string(
		font, draw_pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
	)


static func draw_centered_text(
	canvas: CanvasItem,
	text: String,
	center: Vector2,
	font_size: int,
	color: Color,
	outline: bool = false,
	use_title_font: bool = false
) -> Vector2:
	if text.is_empty():
		return Vector2.ZERO
	var font := _get_font_for_text(text, use_title_font)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos := _snap_pos(Vector2(
		center.x - text_size.x * 0.5,
		center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	))
	if outline:
		var outline_color := _text_shadow_color(color)
		for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			canvas.draw_string(
				font, text_pos + offset, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color
			)
	else:
		var shadow_color := _text_shadow_color(color)
		canvas.draw_string(
			font, text_pos + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color
		)
	canvas.draw_string(
		font, text_pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
	)
	return text_size


static func draw_message_style_text(
	canvas: CanvasItem,
	text: String,
	center: Vector2,
	font_size: int,
	color: Color
) -> void:
	draw_centered_text(
		canvas,
		text,
		Vector2(roundi(center.x), roundi(center.y)),
		font_size,
		color
	)


static func draw_pixel_text_stroke(
	canvas: CanvasItem,
	text: String,
	pos: Vector2,
	font_size: int,
	color: Color
) -> void:
	draw_centered_text(canvas, text, pos, font_size, color, true)


static func get_buff_orb_sprite(type_name: String) -> Array:
	match type_name:
		"attack":
			return [
				[null, "#f8f8f8", null, null, "#f8f8f8", null],
				[null, "#f8f8f8", "#ffb070", "#ffb070", "#f8f8f8", null],
				[null, "#f8f8f8", "#ffb070", "#ffb070", "#f8f8f8", null],
				[null, "#f8f8f8", null, null, "#f8f8f8", null],
				[null, "#2a1e16", null, null, "#2a1e16", null],
				[null, "#2a1e16", null, null, "#2a1e16", null],
			]
		"ki":
			return [
				[null, "#9be8ff", null, "#9be8ff", null],
				["#9be8ff", "#f8f8f8", "#9be8ff", "#f8f8f8", "#9be8ff"],
				[null, "#9be8ff", "#f8f8f8", "#9be8ff", null],
				[null, "#9be8ff", "#f8f8f8", "#9be8ff", null],
				["#9be8ff", "#f8f8f8", "#9be8ff", "#f8f8f8", "#9be8ff"],
			]
		"combo":
			return [
				[null, "#ffd0ff", "#f8f8f8", "#ffd0ff", null],
				["#ffd0ff", null, "#f8f8f8", null, "#ffd0ff"],
				["#f8f8f8", "#f8f8f8", "#f8f8f8", "#f8f8f8", "#f8f8f8"],
				["#ffd0ff", null, "#f8f8f8", null, "#ffd0ff"],
				[null, "#ffd0ff", "#f8f8f8", "#ffd0ff", null],
			]
		"ice":
			return [
				[null, null, "#9be8ff", null, null],
				[null, "#9be8ff", "#f8f8f8", "#9be8ff", null],
				["#9be8ff", "#f8f8f8", "#f8f8f8", "#f8f8f8", "#9be8ff"],
				[null, "#9be8ff", "#f8f8f8", "#9be8ff", null],
				[null, null, "#9be8ff", null, null],
			]
	return get_buff_orb_sprite("attack")


static func get_buff_orb_short_label(type_name: String) -> String:
	match type_name:
		"attack":
			return "攻击"
		"ki":
			return "气力"
		"combo":
			return "连击"
		"ice":
			return "冰冻"
	return "强化"


static func buff_frame_color(type_name: String) -> Color:
	match type_name:
		"attack":
			return Color("#ff9050")
		"ki":
			return Color("#58c8ff")
		"combo":
			return Color("#f0a0f0")
		"ice":
			return Color("#88d8ff")
	return Color("#e8d070")


static func draw_pixel_icon(canvas: CanvasItem, sprite: Array, center: Vector2, px: int) -> void:
	if sprite.is_empty():
		return
	var rows: int = sprite.size()
	var cols: int = sprite[0].size()
	var ox := int(floor(center.x - float(cols * px) * 0.5))
	var oy := int(floor(center.y - float(rows * px) * 0.5))
	for row in range(rows):
		for col in range(cols):
			var hex: Variant = sprite[row][col]
			if hex == null:
				continue
			canvas.draw_rect(Rect2(ox + col * px, oy + row * px, px, px), Color(str(hex)))


static func get_combo_font_size(combo: int) -> int:
	if combo < 2:
		return PIXEL_FONT_BASE * 2
	var t := clampf(float(combo - 2) / 28.0, 0.0, 1.0)
	var curved := pow(t, 0.7)
	var raw := lerpf(45.0, 80.0, curved)
	return snap_pixel_font_size(int(round(raw)))


static func get_combo_colors(combo: int) -> Dictionary:
	var t := clampf(float(combo - 2) / 30.0, 0.0, 1.0)
	var main: Color
	var sub: Color
	var glow: Color
	if t < 0.2:
		var u := t / 0.2
		main = _lerp_hex_color("#ffe7c8", "#ffe850", u)
		sub = _lerp_hex_color("#ffd8a8", "#ffc830", u)
		glow = _lerp_hex_color("#ffe0b0", "#ffb020", u)
	elif t < 0.45:
		var u := (t - 0.2) / 0.25
		main = _lerp_hex_color("#ffe850", "#ff9820", u)
		sub = _lerp_hex_color("#ffc830", "#ff7018", u)
		glow = _lerp_hex_color("#ffb020", "#ff5810", u)
	elif t < 0.7:
		var u := (t - 0.45) / 0.25
		main = _lerp_hex_color("#ff9820", "#ff4028", u)
		sub = _lerp_hex_color("#ff7018", "#ff2030", u)
		glow = _lerp_hex_color("#ff5810", "#ff1020", u)
	elif t < 0.88:
		var u := (t - 0.7) / 0.18
		main = _lerp_hex_color("#ff4028", "#ff2088", u)
		sub = _lerp_hex_color("#ff2030", "#ff40c0", u)
		glow = _lerp_hex_color("#ff1020", "#ff60d0", u)
	else:
		var u := (t - 0.88) / 0.12
		main = _lerp_hex_color("#ff2088", "#fff8ff", u)
		sub = _lerp_hex_color("#ff40c0", "#ffd0ff", u)
		glow = _lerp_hex_color("#ff60d0", "#ffffff", u)
	return {"main": main, "sub": sub, "glow": glow}


static func get_play_area_bottom(viewport_h: float) -> float:
	return viewport_h - (_scaled(EXP_BAR_HEIGHT) + _scaled(14.0))


static func compute_hud_layout(
	viewport_size: Vector2,
	player: BattlePlayer,
	boss: Node = null
) -> Dictionary:
	var s := _ui_scale()
	var pad := 12.0 * s
	var ki_y := 30.0 * s
	var ki_h := 22.0 * s
	var show_boss_bar: bool = boss != null and boss.has_method("is_boss_active") and boss.is_boss_active()
	var boss_bar_h := 22.0 * s if show_boss_bar else 0.0
	var boss_bar_y := ki_y + ki_h + 6.0 * s
	var buff_row_y := boss_bar_y + boss_bar_h + ((6.0 if show_boss_bar else 8.0) * s)
	var has_buffs := player != null and not player.collected_orb_buffs.is_empty()
	var second_row_y := buff_row_y + ((30.0 if has_buffs else 0.0) * s)
	return {
		"pad": pad,
		"ki_x": pad,
		"ki_y": ki_y,
		"ki_w": viewport_size.x - pad * 2.0,
		"ki_h": ki_h,
		"boss_bar_y": boss_bar_y,
		"boss_bar_h": boss_bar_h,
		"show_boss_bar": show_boss_bar,
		"buff_row_y": buff_row_y,
		"second_row_y": second_row_y,
		"combo_y": second_row_y + 8.0 * s,
	}


static func draw_ki_ready_glow(canvas: CanvasItem, layout: Dictionary) -> void:
	var pulse := 0.55 + sin(Time.get_ticks_msec() * 0.009) * 0.35
	var glow := Color(0.34, 0.91, 1.0, pulse * 0.42)
	var rect := Rect2(
		float(layout.get("ki_x", 0.0)),
		float(layout.get("ki_y", 0.0)) - 4.0,
		float(layout.get("ki_w", 0.0)),
		float(layout.get("ki_h", 0.0)) + 8.0
	)
	canvas.draw_rect(rect, glow)


static func draw_sword_ki_bar(
	canvas: CanvasItem,
	x: float,
	y: float,
	total_w: float,
	h: float,
	ratio: float,
	is_ki_ready: bool
) -> void:
	var rows := 16
	var px := maxi(2, int(floor(h / float(rows))))
	var bar_h := rows * px
	var bar_y := int(floor(y + (h - bar_h) * 0.5))
	var ox := int(floor(x))

	var pal: Dictionary
	if is_ki_ready:
		pal = {
			"outline": "#1a1418",
			"pommel": "#4a4048", "pommel_hi": "#7a7078",
			"grip0": "#3a2818", "grip1": "#5a4030", "grip_wrap": "#a88868",
			"guard": "#5a5a62", "guard_hi": "#9a9aa8", "guard_edge": "#2a2830",
			"track": "#2a3038", "track_hi": "#3a424c",
			"ki_lo": "#2a6890", "ki_mid": "#58b0d8", "ki_hi": "#9ae8ff", "ki_edge": "#d8f8ff",
			"steel": "#6a7078", "steel_hi": "#aab0b8",
			"warn": "#e04838",
		}
	else:
		pal = {
			"outline": "#1a181c",
			"pommel": "#3a383c", "pommel_hi": "#52545a",
			"grip0": "#2a2428", "grip1": "#3a3438", "grip_wrap": "#5a5458",
			"guard": "#424448", "guard_hi": "#5a5c62", "guard_edge": "#2a2830",
			"track": "#2a2a30", "track_hi": "#34343a",
			"ki_lo": "#3a4048", "ki_mid": "#4a5058", "ki_hi": "#5a6268", "ki_edge": "#6a7078",
			"steel": "#4a4e54", "steel_hi": "#5a5e64",
			"warn": "#6a5050",
		}

	var pommel_cols := 1
	var grip_cols := 18
	var guard_cols := 4
	var tip_cols := 5
	var fixed_cols := pommel_cols + grip_cols + guard_cols + tip_cols
	var blade_cols := maxi(10, int(floor((total_w - fixed_cols * px) / float(px))))
	var total_cols := fixed_cols + blade_cols
	var draw_w := total_cols * px
	var dx := ox + int(floor((total_w - draw_w) * 0.5))
	var blade_start := pommel_cols + grip_cols + guard_cols
	var tip_start := blade_start + blade_cols
	var ki_cols := blade_cols + tip_cols
	var fill_cols := int(floor(ki_cols * clampf(ratio, 0.0, 1.0)))
	var low_ki := not is_ki_ready and ratio < 0.25 and int(Time.get_ticks_msec() / 280) % 2 == 0
	var ki_pulse := is_ki_ready and int(Time.get_ticks_msec() / 220) % 2 == 0

	for col in range(total_cols):
		for row in range(rows):
			var span: Variant = _sword_row_span(col, rows, pommel_cols, grip_cols, guard_cols, blade_cols, tip_cols)
			if span == null:
				continue
			var row_min: int = int(span.get("row_min", 0))
			var row_max: int = int(span.get("row_max", 0))
			if row < row_min or row > row_max:
				continue
			var color_hex := _sword_color_at(
				col, row, rows, pommel_cols, grip_cols, guard_cols, blade_cols, tip_cols,
				blade_start, tip_start, fill_cols, low_ki, ki_pulse, pal
			)
			canvas.draw_rect(Rect2(dx + col * px, bar_y + row * px, px, px), Color(color_hex))


static func draw_compact_hp_bar(
	canvas: CanvasItem,
	top_center: Vector2,
	hp: int,
	max_hp: int,
	bar_w: float = 30.0,
	bar_h: float = 5.0,
	style: Dictionary = {}
) -> void:
	var ratio := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	var bar_x := top_center.x - bar_w * 0.5
	var top_y := top_center.y
	var border_color: Color = Color(str(style.get("border_color", "#1a1020")))
	var panel_fill: Color = Color(str(style.get("panel_fill", "#201018")))
	var empty_a: Color = Color(str(style.get("empty_a", "#2f1418")))
	var empty_b: Color = Color(str(style.get("empty_b", "#3a1a20")))
	var fill_color: Color = Color(str(style.get("fill_color", "#c83030")))
	var shine_color: Color = Color(str(style.get("shine_color", "#ff7a7a")))
	draw_pixel_panel(canvas, Rect2(bar_x, top_y, bar_w, bar_h), panel_fill, border_color, 1)
	var inner_x := bar_x + 1.0
	var inner_y := top_y + 1.0
	var inner_w := bar_w - 2.0
	var inner_h := bar_h - 2.0
	var fill_w := inner_w * ratio
	canvas.draw_rect(Rect2(inner_x, inner_y, inner_w, inner_h), empty_a)
	var inner_wi := maxi(1, int(floor(inner_w)))
	var inner_hi := maxi(1, int(floor(inner_h)))
	var segment_gap := maxi(1, int(style.get("segment_gap", 1)))
	var segment_count := int(style.get("segment_count", 0))
	if segment_count <= 0:
		segment_count = maxi(6, int(floor(float(inner_wi + segment_gap) / 4.0)))
	segment_count = clampi(segment_count, 1, inner_wi)
	while segment_count > 1 and (segment_count + (segment_count - 1) * segment_gap) > inner_wi:
		segment_count -= 1
	var seg_w := maxi(1, int(floor(float(inner_wi - (segment_count - 1) * segment_gap) / float(segment_count))))
	var total_seg_w := segment_count * seg_w + (segment_count - 1) * segment_gap
	var seg_start_x := int(floor(inner_x + (inner_wi - total_seg_w) * 0.5))
	var fill_limit := int(floor(inner_x + fill_w))
	for i in range(segment_count):
		var sx := seg_start_x + i * (seg_w + segment_gap)
		var slot_col := empty_a if i % 2 == 0 else empty_b
		canvas.draw_rect(Rect2(float(sx), inner_y, float(seg_w), float(inner_hi)), slot_col)
		if sx >= fill_limit:
			continue
		var painted_w := mini(seg_w, fill_limit - sx)
		canvas.draw_rect(Rect2(float(sx), inner_y, float(painted_w), float(inner_hi)), fill_color)
		canvas.draw_rect(
			Rect2(float(sx), inner_y, float(painted_w), float(maxi(1, int(floor(float(inner_hi) * 0.34))))),
			shine_color
		)
	if ratio <= 0.25 and ratio > 0.0 and int(Time.get_ticks_msec() / 180) % 2 == 0:
		canvas.draw_rect(Rect2(bar_x, top_y, bar_w, 1.0), Color("#ffd070"))


static func draw_boss_hp_bar(canvas: CanvasItem, boss: Node, layout: Dictionary) -> void:
	if boss == null or not bool(layout.get("show_boss_bar", false)):
		return
	if not boss.has_method("get_hp_ratio") or not boss.has_method("get_display_name"):
		return
	var x: float = float(layout.get("ki_x", 0.0))
	var y: float = float(layout.get("boss_bar_y", 0.0))
	var w: float = float(layout.get("ki_w", 0.0))
	var h: float = float(layout.get("boss_bar_h", 0.0))
	var ratio: float = float(boss.call("get_hp_ratio"))
	var border := maxi(2, int(round(_scaled(2.0))))
	draw_pixel_panel(canvas, Rect2(x, y, w, h), Color("#281820"), Color("#c84848"), border)
	var inner_x := x + border
	var inner_y := y + border
	var inner_w := w - border * 2
	var inner_h := h - border * 2
	var fill_w := int(floor(inner_w * ratio))
	canvas.draw_rect(Rect2(inner_x, inner_y, inner_w, inner_h), Color("#3a1818"))
	if fill_w > 0:
		canvas.draw_rect(Rect2(inner_x, inner_y, fill_w, inner_h), Color("#c83030"))
		canvas.draw_rect(
			Rect2(inner_x, inner_y, fill_w, maxi(2, int(floor(inner_h * 0.4)))),
			Color("#ff6868")
		)
	draw_pixel_text(
		canvas,
		boss.get_display_name(),
		Vector2(x + _scaled(8.0), y + h * 0.5),
		int(round(_scaled(9.0))),
		Color("#ffe0c8"),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var boss_hp: int = int(boss.get("hp")) if boss.get("hp") != null else 0
	var boss_max_hp: int = int(boss.get("max_hp")) if boss.get("max_hp") != null else 1
	draw_pixel_text(
		canvas,
		"%d/%d" % [ceili(boss_hp), boss_max_hp],
		Vector2(x + w - _scaled(8.0), y + h * 0.5),
		int(round(_scaled(8.0))),
		Color("#ffd0c0"),
		HORIZONTAL_ALIGNMENT_RIGHT
	)


static func draw_turn_buff_icons(canvas: CanvasItem, player: BattlePlayer, layout: Dictionary) -> void:
	if player == null or player.collected_orb_buffs.is_empty():
		return
	var counts: Dictionary = {}
	for type_name in player.collected_orb_buffs:
		var key := str(type_name)
		counts[key] = int(counts.get(key, 0)) + 1
	var types: Array = ["attack", "ki", "combo", "ice"].filter(func(t: String) -> bool: return counts.has(t))
	if types.is_empty():
		return
	var s := _ui_scale()
	var icon_px := maxi(3, int(round(3.0 * s)))
	var slot_w := icon_px * 8 + 10.0 * s
	var total_w: float = types.size() * slot_w - 4.0 * s
	var x: float = float(layout.get("ki_x", 0.0)) + float(layout.get("ki_w", 0.0)) * 0.5 - total_w * 0.5
	var cy: float = float(layout.get("buff_row_y", 0.0)) + 12.0 * s
	for type_name in types:
		var count: int = counts[type_name]
		var sx := int(floor(x))
		var sy := int(floor(cy - 12.0 * s))
		var panel_w := slot_w - 4.0 * s
		draw_pixel_panel(canvas, Rect2(sx, sy, panel_w, 24.0 * s), Color("#2a2838"), Color("#c8b888"), maxi(2, int(round(2.0 * s))))
		canvas.draw_rect(Rect2(sx + 3.0 * s, sy + 3.0 * s, panel_w - 6.0 * s, 4.0 * s), buff_frame_color(type_name))
		draw_pixel_icon(canvas, get_buff_orb_sprite(type_name), Vector2(x + panel_w * 0.5, cy), icon_px)
		var label := get_buff_orb_short_label(type_name)
		if count > 1:
			label = "%s×%d" % [label, count]
		draw_pixel_text(canvas, label, Vector2(x + panel_w * 0.5, cy + 14.0 * s), int(round(_scaled(8.0))), Color("#fff0d0"))
		x += slot_w


static func draw_combo_banner(
	canvas: CanvasItem,
	player: BattlePlayer,
	layout: Dictionary,
	viewport_w: float
) -> void:
	if player == null:
		return
	var combo := player.combo_display_peak
	if combo < 2 or not player.is_combo_display_visible():
		return
	var fading := player.combo_display_fading
	var fade_dur := 0.4
	var alpha := clampf(player.combo_display_timer / fade_dur, 0.0, 1.0) if fading else 1.0
	var cx := viewport_w * 0.5
	var s := _ui_scale()
	var cy := float(layout.get("combo_y", 0.0)) + 24.0 * s
	var main_size := get_combo_font_size(combo)
	var sub_size := snap_pixel_font_size(maxi(PIXEL_FONT_BASE + 1, int(round(float(main_size) * 0.56))))
	var colors := get_combo_colors(combo)
	var punch_scale := 1.0
	var main_color: Color = colors["main"]
	main_color.a = alpha
	var sub_color: Color = colors["sub"]
	sub_color.a = alpha
	var main_text := "连击×%d" % combo
	var sub_text := "+%d%%" % player.get_combo_bonus_percent()
	if combo >= 5:
		var glow_size := snap_pixel_font_size(int(round(float(main_size) * 1.1)))
		var glow_color: Color = colors["glow"]
		glow_color.a = clampf(0.18 + float(combo - 4) * 0.012, 0.18, 0.52) * alpha
		draw_message_style_text(canvas, main_text, Vector2(cx, cy - 4.0 * s), glow_size, glow_color)
	canvas.draw_set_transform(Vector2(cx, cy), 0.0, Vector2(punch_scale, punch_scale))
	draw_message_style_text(canvas, main_text, Vector2(0.0, -4.0 * s), main_size, main_color)
	draw_message_style_text(canvas, sub_text, Vector2(0.0, float(main_size - int(round(1.0 * s)))), sub_size, sub_color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_exp_bar(
	canvas: CanvasItem,
	viewport_size: Vector2,
	level: int,
	exp_value: int,
	exp_to_next: int
) -> void:
	var s := _ui_scale()
	var h := int(floor(_scaled(EXP_BAR_HEIGHT)))
	var pad := int(round(12.0 * s))
	var y := int(floor(viewport_size.y - h - 8.0 * s))
	var w := int(floor(viewport_size.x - pad * 2))
	var x := pad
	var border := maxi(2, int(round(3.0 * s)))
	var block := maxi(3, int(round(4.0 * s)))
	var inner_x := x + border
	var inner_y := y + border
	var inner_w := w - border * 2
	var inner_h := h - border * 2
	var ratio := clampf(float(exp_value) / maxf(1.0, float(exp_to_next)), 0.0, 1.0)
	var fill_blocks := int(floor(float(inner_w) / float(block) * ratio))

	draw_pixel_panel(canvas, Rect2(x, y, w, h), Color("#1a2030"), Color("#c8a040"), border)

	var col := 0
	while col * block < inner_w:
		var bx := inner_x + col * block
		var bw := mini(block - 1, inner_w - col * block)
		if bw <= 0:
			break
		if col < fill_blocks:
			canvas.draw_rect(Rect2(bx, inner_y, bw, inner_h), Color("#348848"))
			canvas.draw_rect(Rect2(bx, inner_y, bw, maxi(2, int(floor(inner_h * 0.42)))), Color("#68c878"))
			canvas.draw_rect(Rect2(bx, inner_y, bw, maxi(1, int(floor(inner_h * 0.18)))), Color("#98e8a8"))
		else:
			canvas.draw_rect(Rect2(bx, inner_y, bw, inner_h), Color("#242c3a") if col % 2 == 0 else Color("#1e2430"))
		col += 1

	var rivet := maxi(2, 2)
	canvas.draw_rect(Rect2(x + border, y + border, rivet, rivet), Color("#5a4828"))
	canvas.draw_rect(Rect2(x + w - border - rivet, y + border, rivet, rivet), Color("#5a4828"))
	canvas.draw_rect(Rect2(x + border, y + h - border - rivet, rivet, rivet), Color("#5a4828"))
	canvas.draw_rect(Rect2(x + w - border - rivet, y + h - border - rivet, rivet, rivet), Color("#5a4828"))

	draw_pixel_text(
		canvas,
		"Lv%d" % level,
		Vector2(x + 10.0 * s, y + h * 0.5),
		snap_pixel_font_size(int(round(PIXEL_FONT_BASE * s))),
		Color("#ffe8a8"),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	draw_pixel_text(
		canvas,
		"%d/%d" % [exp_value, exp_to_next],
		Vector2(x + w - 10.0 * s, y + h * 0.5),
		snap_pixel_font_size(int(round(PIXEL_FONT_BASE * s))),
		Color("#e8f4ff"),
		HORIZONTAL_ALIGNMENT_RIGHT
	)


static func draw_message_panel(canvas: CanvasItem, text: String, center: Vector2, alpha: float = 1.0) -> void:
	if text.is_empty() or alpha <= 0.0:
		return
	var s := _ui_scale()
	var font_size := snap_pixel_font_size(int(round(PIXEL_FONT_BASE * 2 * s)))
	var font := _get_font_for_text(text)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pad_x := 12.0 * s
	var pad_y := 8.0 * s
	var box_w := text_size.x + pad_x * 2.0
	var box_h := text_size.y + pad_y * 2.0
	var bx := int(floor(center.x - box_w * 0.5))
	var by := int(floor(center.y - box_h * 0.5))
	var fill := Color(0.165, 0.141, 0.125, 0.94 * alpha)
	var border := Color("#c8b080")
	border.a *= alpha
	draw_pixel_panel(canvas, Rect2(bx, by, box_w, box_h), fill, border, maxi(2, int(round(2.0 * s))))
	var text_color := Color("#ffe7c8")
	text_color.a *= alpha
	draw_message_style_text(
		canvas, text, center, font_size, text_color
	)


static func draw_buff_notice(canvas: CanvasItem, notice: String, viewport_size: Vector2, alpha: float) -> void:
	if notice.is_empty() or alpha <= 0.0:
		return
	var text := notice.replace("获得强化: ", "")
	var s := _ui_scale()
	var font_size := snap_pixel_font_size(int(round(PIXEL_FONT_BASE * 2 * s)))
	var font := _get_font_for_text(text)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pad_x := 14.0 * s
	var pad_y := 10.0 * s
	var bw := text_size.x + pad_x * 2.0
	var bh := text_size.y + pad_y * 2.0
	var cx := roundi(viewport_size.x * 0.5)
	var cy := roundi(viewport_size.y * 0.2)
	var bx := int(floor(cx - bw * 0.5))
	var by := int(floor(cy - bh * 0.5))
	var fill := Color(0.165, 0.125, 0.063, 0.94 * alpha)
	var border := Color("#ffd878")
	border.a *= alpha
	draw_pixel_panel(canvas, Rect2(bx, by, bw, bh), fill, border, maxi(2, int(round(2.0 * s))))
	var text_color := Color("#fff6d0")
	text_color.a *= alpha
	draw_centered_text(canvas, text, Vector2(cx, cy), font_size, text_color)


static func _lerp_hex_color(c1: String, c2: String, t: float) -> Color:
	var a := _parse_hex_color(c1)
	var b := _parse_hex_color(c2)
	var ch := func(i: int) -> float: return a[i] + (b[i] - a[i]) * t
	return Color(ch.call(0) / 255.0, ch.call(1) / 255.0, ch.call(2) / 255.0)


static func _parse_hex_color(hex: String) -> Array:
	var h := hex.replace("#", "")
	if h.length() < 6:
		return [255.0, 255.0, 255.0]
	return [
		float(h.substr(0, 2).hex_to_int()),
		float(h.substr(2, 2).hex_to_int()),
		float(h.substr(4, 2).hex_to_int()),
	]


static func _sword_row_span(
	col: int,
	rows: int,
	pommel_cols: int,
	grip_cols: int,
	guard_cols: int,
	blade_cols: int,
	tip_cols: int
) -> Variant:
	var blade_start := pommel_cols + grip_cols + guard_cols
	var tip_start := blade_start + blade_cols
	if col < pommel_cols:
		var mid := int(floor(rows / 2.0))
		return {"row_min": mid - 1, "row_max": mid + 1}
	if col < pommel_cols + grip_cols:
		var grip_mid := int(floor(rows / 2.0))
		return {"row_min": grip_mid - 3, "row_max": grip_mid + 2}
	if col < blade_start:
		return {"row_min": 0, "row_max": rows - 1}
	if col < tip_start:
		return {"row_min": 2, "row_max": rows - 3}
	var tip_idx := col - tip_start
	var inset := tip_idx + 1
	var row_min := inset + 2
	var row_max := rows - 3 - inset
	if row_min > row_max:
		return null
	return {"row_min": row_min, "row_max": row_max}


static func _sword_color_at(
	col: int,
	row: int,
	rows: int,
	pommel_cols: int,
	grip_cols: int,
	guard_cols: int,
	blade_cols: int,
	tip_cols: int,
	blade_start: int,
	tip_start: int,
	fill_cols: int,
	low_ki: bool,
	ki_pulse: bool,
	pal: Dictionary
) -> String:
	var is_blade := col >= blade_start and col < tip_start
	var is_tip := col >= tip_start
	var is_guard := col >= pommel_cols + grip_cols and col < blade_start
	var is_grip := col >= pommel_cols and col < pommel_cols + grip_cols
	var is_pommel := col < pommel_cols
	var blade_col := col - blade_start
	var tip_col := col - tip_start
	var ki_col := blade_col if is_blade else (blade_cols + tip_col if is_tip else -1)
	var filled := ki_col >= 0 and ki_col < fill_cols
	var edge_row := row == 0 or row == rows - 1
	var mid_row := row == int(floor(rows / 2.0))

	if is_pommel:
		return pal.pommel_hi if mid_row else pal.pommel
	if is_grip:
		if edge_row:
			return pal.outline
		var g := (col + row) % 3
		if g == 0:
			return pal.grip0
		if g == 1:
			return pal.grip_wrap
		return pal.grip1
	if is_guard:
		if edge_row:
			return pal.guard_edge
		var guard_edge_band := row <= 2 or row >= rows - 3
		return pal.guard_hi if guard_edge_band else pal.guard
	if is_blade:
		if not filled:
			if edge_row:
				return pal.outline
			return pal.track_hi if row <= 2 else pal.track
		if edge_row:
			return pal.ki_lo
		if row <= 2:
			return "#e8ffff" if ki_pulse else pal.ki_edge
		if row <= 4:
			return pal.ki_hi
		return pal.ki_mid
	if is_tip:
		if not filled:
			if edge_row:
				return pal.outline
			return pal.steel
		if low_ki and mid_row:
			return pal.warn
		if edge_row:
			return pal.ki_lo
		if row <= 3:
			return "#e8ffff" if ki_pulse else pal.ki_hi
		return pal.ki_mid
	return pal.outline
