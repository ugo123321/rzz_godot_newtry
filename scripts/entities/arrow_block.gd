extends FieldElement
class_name ArrowBlock

# 单向 / 十字飞箭块：每 1s 朝正对方向（单向）或十字四向（十字）射出飞箭，阻挡移动/画线/子弹。
# 箭只伤害玩家，对敌人无效。朝向由编辑器设定（up/down/left/right）。
# 视觉走美术素材 arrow_block.png（40×40 底座）+ 弓箭手箭矢素材叠加朝向指示，不再过程化绘制。

const FIRE_INTERVAL := 1.0
const ArrowProjectileScript := preload("res://scripts/entities/arrow_projectile.gd")
const FIRE_OFFSET := 33.0  # 箭生成时离块中心的偏移（放大后随块变大）

# 底座 + 朝向指示箭头（弓箭手射出的箭素材，Arrow01 32×32，默认朝 +x）
const BASE_TEX := preload("res://assets/ui/terrains/arrow_block.png")
const ARROW_TEX := preload("res://assets/Characters/Characters(100x100)/Archer/Arrow(projectile)/Arrow01(32x32).png")
const INDICATOR_SIZE := 14.0  # 指示箭头缩放后边长（px）
const INDICATOR_OFFSET := 10.0  # 指示箭头离块中心的偏移（朝边方向，让箭指向外）

const DIRS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
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
	# 底座（arrow_block.png，居中，占满一格）
	var base_sz: Vector2 = BASE_TEX.get_size()
	draw_texture(BASE_TEX, -base_sz * 0.5)
	# 朝向指示：单向 = 1 支朝 facing；十字 = 4 支朝四向。
	# 均用弓箭手箭矢素材，旋转到朝向、缩放到 INDICATOR_SIZE、偏移到边附近指向外。
	var dirs: Array
	if kind == "arrow_cross":
		dirs = [DIRS.up, DIRS.down, DIRS.left, DIRS.right]
	else:
		dirs = [DIRS.get(facing, Vector2.RIGHT)]
	for d in dirs:
		_draw_arrow_indicator(d * INDICATOR_OFFSET, d)


func _draw_arrow_indicator(pos: Vector2, dir: Vector2) -> void:
	var tex_sz: Vector2 = ARROW_TEX.get_size()  # 32×32
	var sc: float = INDICATOR_SIZE / tex_sz.x
	# 箭头素材默认朝 +x；旋转到 dir、中心放到 pos、缩放到 INDICATOR_SIZE
	var t := Transform2D(dir.angle(), pos).scaled_local(Vector2(sc, sc))
	draw_set_transform_matrix(t)
	draw_texture(ARROW_TEX, -tex_sz * 0.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)  # 复位，避免影响后续绘制
