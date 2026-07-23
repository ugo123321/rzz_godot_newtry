extends FieldElement
class_name ChestNormal

# 普通宝箱：碰撞后打开。内容：70% 概率 1-3 银币，30% 概率 1 钥匙。开启后消失。
# 不阻挡移动/画线/子弹（玩家碰上去就开，参考 LotteryPortal 的 proximity 触发）。
# 对敌人无效（敌人不会触发）。
# 视觉走美术素材 chest.png；开启瞬间切到 chest_open.png，OPEN_DURATION 后消失
# （闭→开 两帧，营造"打开"动画感）。

const TRIGGER_RADIUS := 38.0  # 玩家进入该格内时开（< 一格 40）
const OPEN_DURATION := 0.2  # 开盖帧持续时间（闭→开→消失）

const TEX := preload("res://assets/ui/terrains/chest.png")
const TEX_OPEN := preload("res://assets/ui/terrains/chest_open.png")

var _opening := false
var _open_timer := 0.0


func setup_chest(col: int, row: int, p_kind: String) -> void:
	setup(col, row, p_kind, "up")
	_configure_blocking(false, false, false)  # 宝箱不阻挡


func _process(delta: float) -> void:
	# 开盖动画计时：到点 queue_free（不再触发开启）
	if _opening:
		_open_timer -= delta
		queue_redraw()  # 让 chest_open 帧可见（静态纹理其实只需画一次，这里保险）
		if _open_timer <= 0.0:
			queue_free()
		return
	if consumed:
		return
	if _battle == null:
		_battle = get_tree().get_first_node_in_group("battle")
	if _battle == null or _battle.player == null:
		return
	if _battle.state != GameState.PLAYING:
		return
	if global_position.distance_to(_battle.player.global_position) <= TRIGGER_RADIUS:
		_open()


func _open() -> void:
	if consumed:
		return
	consumed = true
	# 70% 银 1-3；30% 钥 1。货币入账延后到 orb 飞达左上角 icon（pickup_orb_manager._on_arrive）
	var is_key := randf() >= 0.7
	if _battle and _battle.pickup_orb_manager:
		if is_key:
			_battle.pickup_orb_manager.spawn_burst(global_position, "key", 1)
		else:
			var n: int = 1 + (randi() % 3)
			_battle.pickup_orb_manager.spawn_burst(global_position, "silver", n)
	# 切开盖帧 → 计时消失（宝箱本就不阻挡，unregister 只是清理注册表）
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = TEX_OPEN if _opening else TEX
	var sz: Vector2 = tex.get_size()
	draw_texture(tex, -sz * 0.5)
