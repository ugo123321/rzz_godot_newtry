extends Node2D
class_name LotteryPortal

# 抽奖传送门（正常关倒计时版）。
# v3：触发后不立即 queue_free —— 改为 visible=false 保留对象，
# 让 battle 端的 portal_traverse.play_exit 用 stored_position 落地。
# 销毁交给 battle._on_lottery_exit_complete 处理。
#
# 视觉走美术素材：portal01.png（主体）+ portal_effect.png（后层效果，代码持续旋转）。
# 头顶倒计时文字保留（正常关限时传送门的核心提示）。

const PixelUi := preload("res://scripts/utils/pixel_ui_helper.gd")

const TRIGGER_RADIUS := 56.0
const VISUAL_RADIUS := 48.0
const EFFECT_ROT_SPEED := 2.5  # 后层效果自转角速度（rad/s）

const PORTAL_TEX := preload("res://assets/ui/terrains/portal01.png")
const PORTAL_EFFECT_TEX := preload("res://assets/ui/terrains/portal_effect.png")
const PORTAL_EFFECT_BG_TEX := preload("res://assets/ui/terrains/portal_effect_bg.png")

var lifetime := 5.0
var _t := 0.0
var _consumed := false
var stored_position: Vector2 = Vector2.ZERO


func setup(pos: Vector2, life: float) -> void:
	global_position = pos
	stored_position = pos
	lifetime = life
	z_index = 0  # 容器(Portals z=-1)已沉到怪物/玩家之下；传送门自身 z=0 → 有效 z=-1
	queue_redraw()


func _process(delta: float) -> void:
	if _consumed:
		return
	lifetime -= delta
	_t += delta
	if lifetime <= 0.0:
		queue_free()
		return
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.player and battle.state == GameState.PLAYING and not battle.get("_portal_active_pause"):
		if global_position.distance_to(battle.player.global_position) <= TRIGGER_RADIUS:
			_consumed = true
			stored_position = global_position
			visible = false  # v3：不销毁，只隐藏；销毁由 battle.play_exit 完成回调处理
			if battle.has_method("on_portal_entered"):
				battle.on_portal_entered(self)
			return
	queue_redraw()


func _draw() -> void:
	var base_sz: Vector2 = PORTAL_TEX.get_size()
	var base_sc: float = (VISUAL_RADIUS * 2.0) / maxf(base_sz.x, base_sz.y)
	# 最底层背景：portal_effect_bg（不旋转，衬在旋转特效之下）
	var bg_sz: Vector2 = PORTAL_EFFECT_BG_TEX.get_size()
	var bg_sc: float = (VISUAL_RADIUS * 2.0) / maxf(bg_sz.x, bg_sz.y)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(bg_sc, bg_sc))
	draw_texture(PORTAL_EFFECT_BG_TEX, -bg_sz * 0.5)
	# 中层效果：portal_effect 持续旋转（叠在背景之上、portal01 之下）
	var eff_sz: Vector2 = PORTAL_EFFECT_TEX.get_size()
	var eff_sc: float = (VISUAL_RADIUS * 2.0) / maxf(eff_sz.x, eff_sz.y)
	var rot: float = _t * EFFECT_ROT_SPEED
	draw_set_transform(Vector2.ZERO, rot, Vector2(eff_sc, eff_sc))
	draw_texture(PORTAL_EFFECT_TEX, -eff_sz * 0.5)
	# 主体传送门
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(base_sc, base_sc))
	draw_texture(PORTAL_TEX, -base_sz * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # 复位
	# 倒计时（正常关限时传送门保留）
	var sec_left := int(ceil(lifetime))
	PixelUi.draw_pixel_text(
		self,
		"%ds" % sec_left,
		Vector2(0.0, -VISUAL_RADIUS - 28.0),
		22,
		Color("#ffe090") if sec_left > 2 else Color("#ff8080"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		true
	)
