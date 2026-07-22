extends FieldElement
class_name PlacedTree

# 关卡编辑器里可放置的树（包装 BattleTree 做视觉 + 序列化 + 编辑接口）。
# 战斗侧 _spawn_field_element 对 "tree" 直接生成真实 BattleTree 进 tree_container（可被砍、挡路走 is_blocked_by_tree）。
# 树只阻挡移动（与 is_blocked_by_tree 一致），不挡画线/子弹。

const BattleTreeScript := preload("res://scripts/entities/battle_tree.gd")

var _tree: BattleTree


func setup_tree(col: int, row: int) -> void:
	setup(col, row, "tree", "up")
	_configure_blocking(false, true, false)  # 只挡移动
	_tree = BattleTreeScript.new()
	add_child(_tree)
	# BattleTree.setup 会改 global_position，这里手动设局部属性让它跟 PlacedTree（格中心）对齐
	_tree.position = Vector2.ZERO
	_tree._sway_seed = randf() * TAU
	_tree.scale = Vector2.ONE * 1.6
	_tree.z_index = 1
	_tree.queue_redraw()


func _process(_delta: float) -> void:
	# 让树冠摇曳在编辑器里也刷新（BattleTree._draw 用 Time.get_ticks_msec 算 sway）
	if _tree and is_instance_valid(_tree):
		_tree.queue_redraw()


func serialize() -> Dictionary:
	return {
		"type": "tree",
		"col": cell_col,
		"row": cell_row,
		"facing": "up",
	}
