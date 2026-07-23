extends FieldElement
class_name LockedBlock

# 锁定块（块上是钥匙 icon）：玩家持有钥匙时碰撞才会解锁开，每次解锁消耗 1 钥匙。
# 未解锁时与阻挡石块效果一致：阻挡移动 + 画线 + 子弹。解锁后消失（变空地）。
# 对敌人无效（敌人撞上也不会解锁，但敌人本身不会在此格刷出 / 不受地块影响）。
# 视觉走美术素材 lock_block.png（40×40，与 TILE_SIZE 对齐）。

const TRIGGER_RADIUS := 38.0  # 玩家进入该格内时解锁（< 一格 40）

const TEX := preload("res://assets/ui/terrains/lock_block.png")


func setup_block(col: int, row: int) -> void:
	setup(col, row, "locked_block", "up")
	_configure_blocking(true, true, true)  # 未解锁：line/move/bullet 全阻挡


func _process(delta: float) -> void:
	if consumed:
		return
	if _battle == null:
		_battle = get_tree().get_first_node_in_group("battle")
	if _battle == null or _battle.player == null:
		return
	if _battle.state != GameState.PLAYING:
		return
	if not _battle.player.has_key():
		return
	if global_position.distance_to(_battle.player.global_position) <= TRIGGER_RADIUS:
		# 持钥匙 + 碰撞 → 解锁（消耗 1 钥匙，块消失）
		if _battle.player.spend_key():
			consume(_battle)


func _draw() -> void:
	var sz: Vector2 = TEX.get_size()
	draw_texture(TEX, -sz * 0.5)
