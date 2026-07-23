extends Node2D
class_name PickupOrbManager

# 通用飞行拾取工厂：spawn_burst(pos, kind, count) → 多个 PickupOrb 逐个掉 → 飞达左上角 icon → 入账
# kind 注册表驱动 icon + credit；新增掉落物只加一行
# battle.gd 在 _ready 实例化并 add_child；与 SoulOrbManager 同级

const PickupOrbScript = preload("res://scripts/effects/pickup_orb.gd")

const KEY_ICON := preload("res://assets/ui/icons/system/icon_key.png")
const SILVER_ICON := preload("res://assets/ui/icons/currency/icon_cur_silver.png")

var battle: Node = null
var _registry: Dictionary = {}   # kind -> { icon: Texture2D, credit: Callable }


func setup(battle_node: Node) -> void:
	battle = battle_node
	_registry["key"] = {
		"icon": KEY_ICON,
		"credit": func(amount: int) -> void: _credit_key(amount),
	}
	_registry["silver"] = {
		"icon": SILVER_ICON,
		"credit": func(amount: int) -> void: _credit_silver(amount),
	}


func spawn_burst(world_pos: Vector2, kind: String, count: int) -> void:
	if count <= 0 or battle == null:
		return
	if not _registry.has(kind):
		push_warning("PickupOrbManager: unknown kind %s" % kind)
		return
	var icon: Texture2D = _registry[kind]["icon"]
	for i in range(count):
		# 逐个掉：小幅位置抖动 + 错开起飞延迟
		var jitter := Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		var pos := world_pos + jitter
		var delay := float(i) * 0.09
		if delay <= 0.0:
			_instantiate_orb(pos, kind, 1, icon)
		else:
			var t := get_tree().create_timer(delay)
			t.timeout.connect(_instantiate_orb.bind(pos, kind, 1, icon))


func _instantiate_orb(pos: Vector2, kind: String, amount: int, icon: Texture2D) -> void:
	if not is_instance_valid(self) or battle == null:
		return
	var orb: Node2D = PickupOrbScript.new()
	add_child(orb)
	orb.setup(pos, kind, amount, _make_arrive_callable(kind), icon)


func _make_arrive_callable(kind: String) -> Callable:
	# orb 在 _finish_arrival 里以 on_arrive.call(amount) 回调；这里把 kind 绑进去
	return func(amount: int) -> void: _on_arrive(kind, amount)


func _on_arrive(kind: String, amount: int) -> void:
	if battle == null or battle.player == null:
		return
	if not _registry.has(kind):
		return
	var credit: Callable = _registry[kind]["credit"]
	credit.call(amount)


func _credit_key(amount: int) -> void:
	if battle and battle.player:
		battle.player.add_key(amount)


func _credit_silver(amount: int) -> void:
	if battle and battle.player:
		battle.player.add_silver(amount)


func clear() -> void:
	for child in get_children():
		child.queue_free()
