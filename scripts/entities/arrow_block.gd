extends FieldElement
class_name ArrowBlock

# 单向 / 十字飞箭块：每 1s 朝正对方向（单向）或十字四向（十字）射出飞箭，阻挡移动/画线/子弹。
# 箭只伤害玩家，对敌人无效。朝向由编辑器设定（up/down/left/right）。
# 视觉走美术素材：单向 arrow_block_one_sight（默认朝上，按 facing 旋转）/ 十字 arrow_block_cross_sight（四向，不旋转）。

const FIRE_INTERVAL := 1.0
const ArrowProjectileScript := preload("res://scripts/entities/arrow_projectile.gd")
const FIRE_OFFSET := 33.0  # 箭生成时离块中心的偏移（放大后随块变大）

const TEX_SINGLE := preload("res://assets/ui/terrains/arrow_block_one_sight.png")
const TEX_CROSS := preload("res://assets/ui/terrains/arrow_block_cross_sight.png")

const DIRS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}

# arrow_block_one_sight 默认朝上；按 facing 旋转（屏幕坐标系 y 向下，顺时针为正角）。
const FACING_ROTATION := {
	"up": 0.0,
	"right": PI * 0.5,
	"down": PI,
	"left": -PI * 0.5,
}

var _fire_timer := 0.0


func setup_block(col: int, row: int, p_kind: String, p_facing: String) -> void:
	setup(col, row, p_kind, p_facing)  # kind = "arrow_single" / "arrow_cross"
	_configure_blocking(true, true, true)
	queue_redraw()


func _process(delta: float) -> void:
	if consumed:
		return
	if _battle == null:
		_battle = get_tree().get_first_node_in_group("battle")
	# 画线时停（bullet time, time_scale < 1.0）：冻结 —— 不射箭、不计时，与怪物/弹道一致
	if _battle and "time_scale" in _battle and _battle.time_scale < 1.0:
		return
	_fire_timer += delta
	if _battle == null or _battle.player == null:
		return
	if _battle.state != GameState.PLAYING:
		return
	if _fire_timer >= FIRE_INTERVAL:
		_fire_timer = 0.0
		_fire_arrows()


func _fire_arrows() -> void:
	if _battle == null:
		return
	var dirs: Array = []
	if kind == "arrow_cross":
		dirs = [DIRS.up, DIRS.down, DIRS.left, DIRS.right]
	else:
		dirs = [DIRS.get(facing, Vector2.RIGHT)]
	for d in dirs:
		var proj := ArrowProjectileScript.new()
		_battle.field_elements.get_parent().add_child(proj)  # 加到 $Entities 下
		proj.setup(global_position + d * FIRE_OFFSET, Vector2(d), _battle)


func _draw() -> void:
	var tex: Texture2D = TEX_CROSS if kind == "arrow_cross" else TEX_SINGLE
	var sz: Vector2 = tex.get_size()
	# 十字块四向对称不转；单向块按 facing 旋转（默认 up 不转）
	var rot: float = 0.0 if kind == "arrow_cross" else FACING_ROTATION.get(facing, 0.0)
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture(tex, -sz * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # 复位，避免影响后续绘制
