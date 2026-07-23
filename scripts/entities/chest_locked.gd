extends FieldElement
class_name ChestLocked

# 锁闭宝箱：玩家持有钥匙时碰撞才能打开；开启消耗 1 钥匙；内容同普通宝箱（70% 银 / 30% 钥）。
# 无钥匙时碰撞提示「需要钥匙」并不打开。对敌人无效。
# 视觉走美术素材 lock_chest.png；开启瞬间切到 chest_open.png，OPEN_DURATION 后消失
# （闭→开 两帧，营造"打开"动画感）。

const TRIGGER_RADIUS := 38.0  # 玩家进入该格内时开（< 一格 40）
const OPEN_DURATION := 0.2  # 开盖帧持续时间（闭→开→消失）

const TEX := preload("res://assets/ui/terrains/lock_chest.png")
const TEX_OPEN := preload("res://assets/ui/terrains/chest_open.png")

var _opening := false
var _open_timer := 0.0


func setup_chest(col: int, row: int, p_kind: String) -> void:
	setup(col, row, p_kind, "up")
	_configure_blocking(false, false, false)


func _process(delta: float) -> void:
	# 开盖动画计时：到点 queue_free（不再触发开启 / 提示）
	if _opening:
		_open_timer -= delta
		queue_redraw()
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
		if not _battle.player.has_key():
			if _battle.hud and _battle.hud.has_method("show_message"):
				_battle.hud.show_message(LanguageManager.tr_ui("UI_CHEST_LOCKED_NEED_KEY"), 1.2)
			# 短冷却避免刷屏（用 consumed 之外的简单计时）
			set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
			_battle.get_tree().create_timer(1.2).timeout.connect(_re_enable)
			return
		_battle.player.spend_key()
		_open()


func _re_enable() -> void:
	if consumed or _opening:
		return
	process_mode = Node.PROCESS_MODE_INHERIT


func _open() -> void:
	if consumed:
		return
	consumed = true
	var is_key := randf() >= 0.7
	if _battle and _battle.pickup_orb_manager:
		if is_key:
			_battle.pickup_orb_manager.spawn_burst(global_position, "key", 1)
		else:
			var n: int = 1 + (randi() % 3)
			_battle.pickup_orb_manager.spawn_burst(global_position, "silver", n)
	unregister_self(_battle)
	_opening = true
	_open_timer = OPEN_DURATION
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = TEX_OPEN if _opening else TEX
	var sz: Vector2 = tex.get_size()
	draw_texture(tex, -sz * 0.5)
