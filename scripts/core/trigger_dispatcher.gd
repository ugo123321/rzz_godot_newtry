extends Node
class_name TriggerDispatcher

# Phase 1 触发分发器：挂在 Player 上，由 player._rebuild_upgrades() 在每次 rebuild 后调 register()。
# 监听 EventBus.monster_killed / 玩家拾取（暂用 EventBus.upgrade_selected 之外、battle 流程统一调 fire_on_pickup() 触发）/ player._process 监测 hp 阈值。
#
# 仅实现 Phase 1 用到的 3 个触发类型：
#   on_kill   + proc_chance + attr 20(kill_heal_pct)
#   on_pickup + attr 19(heal_pct)
#   hp_below  -> 翻转时触发 player._rebuild_upgrades()（attr 写入由 AttrEngine 按条件判断决定）

const AttrEngineT = preload("res://scripts/core/attr_engine.gd")

var player: Node
var _bindings: Array = []   # 当前激活 bindings 数组（AttrEngine.collect_trigger_bindings 输出）
var _hp_threshold_was_active: Dictionary = {}  # { card_id: bool } 上一帧 hp 阈值状态


func setup(p: Node) -> void:
	player = p
	if not EventBus.monster_killed.is_connected(_on_monster_killed):
		EventBus.monster_killed.connect(_on_monster_killed)


# 由 player._rebuild_upgrades() 调用：把当前 stacks 中所有触发卡注册进来
func register(bindings: Array) -> void:
	_bindings = bindings
	# hp_below 缓存初始化：未在 _bindings 的卡清掉旧状态
	var still_active: Dictionary = {}
	for b in _bindings:
		if str(b.get("trigger", "")) == "hp_below":
			still_active[str(b.get("id", ""))] = _hp_threshold_was_active.get(str(b.get("id", "")), false)
	_hp_threshold_was_active = still_active


# 每帧轮询 hp_below 卡是否翻转；翻转时让 player 重算 attr（AttrEngine 会按条件决定要不要写）
func tick(_delta: float) -> void:
	if player == null:
		return
	var any_flipped := false
	for b in _bindings:
		if str(b.get("trigger", "")) != "hp_below":
			continue
		var id := str(b.get("id", ""))
		var threshold := float(b.get("trigger_value", 0.5))
		var ratio: float = 1.0
		if "max_hp" in player and float(player.max_hp) > 0.0:
			ratio = float(player.hp) / float(player.max_hp)
		var now_active: bool = ratio <= threshold
		var was_active: bool = bool(_hp_threshold_was_active.get(id, false))
		if now_active != was_active:
			_hp_threshold_was_active[id] = now_active
			any_flipped = true
	if any_flipped and player.has_method("_rebuild_upgrades_passive_only"):
		player._rebuild_upgrades_passive_only()
	elif any_flipped and player.has_method("_rebuild_upgrades"):
		player._rebuild_upgrades()


# EventBus monster_killed 钩子
func _on_monster_killed(_monster: Node) -> void:
	if player == null:
		return
	for b in _bindings:
		if str(b.get("trigger", "")) != "on_kill":
			continue
		var proc = b.get("proc_chance")
		var chance := 1.0 if proc == null else float(proc)
		if randf() > chance:
			continue
		# attr 20 = kill_heal_pct
		var ratio: float = AttrEngineT.get_attr_amount(b, 20)
		if ratio > 0.0 and player.has_method("heal_percent"):
			player.heal_percent(ratio)


# 由 battle 流程在玩家拾取奖励/经验时调
func fire_on_pickup() -> void:
	if player == null:
		return
	for b in _bindings:
		if str(b.get("trigger", "")) != "on_pickup":
			continue
		var proc = b.get("proc_chance")
		var chance := 1.0 if proc == null else float(proc)
		if randf() > chance:
			continue
		# attr 19 = heal_pct
		var ratio: float = AttrEngineT.get_attr_amount(b, 19)
		if ratio > 0.0 and player.has_method("heal_percent"):
			player.heal_percent(ratio)
