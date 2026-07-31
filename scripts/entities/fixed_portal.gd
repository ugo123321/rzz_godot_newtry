extends FieldElement
class_name FixedPortal

# 固定抽奖传送门：与随机刷出的 LotteryPortal 效果一致，但无倒计时、固定存在。
# 碰撞后进入抽奖页面（battle.on_portal_entered → reward_wheel 流程），碰撞后传送门消失。
# 销毁交给 battle._on_lottery_exit_complete 处理（与 LotteryPortal 一致）。
# 由关卡编辑器 / battle._apply_level_layout 放置。继承 FieldElement 以获得 cell_col/row/serialize。
#
# 视觉走美术素材：portal01.png（主体）+ portal_effect.png（后层效果，代码持续旋转）。

const TRIGGER_RADIUS := 56.0
const VISUAL_RADIUS := 48.0
const EFFECT_ROT_SPEED := 2.5  # 后层效果自转角速度（rad/s）

const PORTAL_TEX := preload("res://assets/ui/terrains/portal01.png")
const PORTAL_EFFECT_TEX := preload("res://assets/ui/terrains/portal_effect.png")
const PORTAL_EFFECT_BG_TEX := preload("res://assets/ui/terrains/portal_effect_bg.png")

var _t := 0.0
var _consumed := false
# 出生后延迟武装：让门先渲染可见，再允许触发。避免玩家出生点与门重叠时第一帧就被瞬间吸入、
# _draw 还没渲染就 visible=false 导致"没看到门就被吸进去"。仍按原来的"进入半径即触发"。
const ACTIVATION_DELAY := 0.5
var _armed := false
var stored_position: Vector2 = Vector2.ZERO


# 编辑器/战斗统一入口：按格放置，stored_position = 格中心（落回原地用）。
func setup_portal(col: int, row: int) -> void:
	setup(col, row, "fixed_portal", "up")  # FieldElement.setup 设 cell/pos/z=0
	stored_position = global_position
	z_index = 0  # 容器(Portals z=-1)已沉到怪物/玩家之下；传送门自身 z=0 → 有效 z=-1
	queue_redraw()


func _process(delta: float) -> void:
	if _consumed:
		return
	_t += delta
	if not _armed and _t >= ACTIVATION_DELAY:
		_armed = true
	var battle := get_tree().get_first_node_in_group("battle")
	if battle and battle.player and battle.state == GameState.PLAYING and not battle.get("_portal_active_pause"):
		if _armed and global_position.distance_to(battle.player.global_position) <= TRIGGER_RADIUS:
			_consumed = true
			stored_position = global_position
			visible = false  # 销毁由 battle.play_exit 完成回调处理
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
