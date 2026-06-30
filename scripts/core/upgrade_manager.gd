extends Node
class_name UpgradeManager

var active := false
var choices: Array = []
var rolled_rarity := "blue"
var popup_timer := 0.0
var popup_duration := 0.45


func generate_choices(player: Node) -> void:
	active = true
	popup_timer = 0.0
	choices.clear()
	rolled_rarity = _roll_rarity(player)
	var pool: Array = _build_pool(rolled_rarity, player)
	if pool.is_empty():
		pool = _build_pool("", player)
	var available := pool.duplicate()
	for i in range(3):
		if available.is_empty():
			var fallback := pool if not pool.is_empty() else _build_pool("", player)
			if fallback.is_empty():
				fallback = GameConfig.upgrades
			choices.append(_weighted_pick(fallback))
		else:
			var idx := _weighted_index(available)
			choices.append(available[idx])
			available.remove_at(idx)
	_record_force_inject(player)


# [RECORD-ONLY] 第二次升级强制把弹幕之王塞到 choices[0]，方便录制买量视频
func _record_force_inject(player: Node) -> void:
	if player == null:
		return
	var stacks: Dictionary = player.get("upgrade_stacks") if player.get("upgrade_stacks") != null else {}
	if stacks.size() != 1:
		return
	if stacks.has("bullet_storm_king"):
		return  # 玩家第一次就选了弹幕之王（max_level=1），别再塞
	var already_has := false
	for c in choices:
		if String(c.get("id", "")) == "bullet_storm_king":
			already_has = true
			break
	if already_has:
		return
	for u in GameConfig.upgrades:
		if String(u.get("id", "")) == "bullet_storm_king":
			if choices.is_empty():
				choices.append(u)
			else:
				choices[0] = u
			return


# 属性打造关结束时：以指定品质强制 roll 3 选 1（不走 _roll_rarity），
# 其余卡池过滤 / 空池回退 / 加权抽取逻辑与 generate_choices 一致。
func generate_choices_with_rarity(player: Node, forced_rarity: String) -> void:
	active = true
	popup_timer = 0.0
	choices.clear()
	rolled_rarity = forced_rarity
	var pool: Array = _build_pool(forced_rarity, player)
	if pool.is_empty():
		pool = _build_pool("", player)
	var available := pool.duplicate()
	for i in range(3):
		if available.is_empty():
			var fallback := pool if not pool.is_empty() else _build_pool("", player)
			if fallback.is_empty():
				fallback = GameConfig.upgrades
			choices.append(_weighted_pick(fallback))
		else:
			var idx := _weighted_index(available)
			choices.append(available[idx])
			available.remove_at(idx)


func _weighted_index(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var total := 0.0
	for u in arr:
		total += maxf(0.0, float(u.get("pool_weight", 1.0)))
	if total <= 0.0:
		return randi() % arr.size()
	var r := randf() * total
	var acc := 0.0
	for i in arr.size():
		acc += maxf(0.0, float(arr[i].get("pool_weight", 1.0)))
		if r <= acc:
			return i
	return arr.size() - 1


func _weighted_pick(arr: Array) -> Dictionary:
	return arr[_weighted_index(arr)]


func _build_pool(rarity: String, player: Node) -> Array:
	var pool: Array = []
	for u in GameConfig.upgrades:
		if not rarity.is_empty() and str(u.get("rarity", "")) != rarity:
			continue
		# pool_weight==0 = 不入常规池（强化球 / 恶魔 / 天使 / 手动剔除 6 张基础卡，详见 build_rewards_v6_compact.py FORCE_NOT_IN_POOL_*）
		if float(u.get("pool_weight", 1.0)) <= 0.0:
			continue
		if not _is_upgrade_available(u, player):
			continue
		pool.append(u)
	return pool


# 主题关用：按 group 过滤的卡池（无视 rarity / pool_weight），返回所有该组未达上限的可选卡。
# 由 battle.gd 在 demon/angel 主题关结束时调，随机抽 1 张展示给玩家。
func get_themed_pool(group_name: String, player: Node) -> Array:
	var pool: Array = []
	for u in GameConfig.upgrades:
		if str(u.get("group", "")) != group_name:
			continue
		if not _is_upgrade_available(u, player):
			continue
		pool.append(u)
	return pool


# 主题关用：从 group 池子里随机抽 1 张
func roll_themed(group_name: String, player: Node) -> Dictionary:
	var pool := get_themed_pool(group_name, player)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


func _is_upgrade_available(def: Dictionary, player: Node) -> bool:
	var id := str(def.get("id", ""))
	if id.is_empty():
		return false
	if player == null:
		return true
	if player.has_method("is_upgrade_pool_blocked") and player.is_upgrade_pool_blocked(id):
		return false
	var max_lv := int(def.get("max_level", 9))
	if player.has_method("get_upgrade_level") and player.get_upgrade_level(id) >= max_lv:
		return false
	return true


func update(delta: float) -> void:
	if active and popup_timer < popup_duration:
		popup_timer += delta


func can_interact() -> bool:
	return active and popup_timer / popup_duration >= 0.55


func select_upgrade(index: int, player: Node) -> Dictionary:
	if not can_interact() or index < 0 or index >= choices.size():
		return {}
	var upgrade: Dictionary = choices[index]
	player.apply_upgrade(upgrade)
	active = false
	choices.clear()
	EventBus.upgrade_selected.emit(str(upgrade.get("id", "")))
	return upgrade


func _roll_rarity(player: Node) -> String:
	if player != null and player.has_method("consume_force_legendary_upgrade") and player.consume_force_legendary_upgrade():
		return "orange"
	var white_w := float(GameConfig.get_upgrade_fx("white").get("chance", 0.20))
	var blue_w := float(GameConfig.get_upgrade_fx("blue").get("chance", 0.30))
	var purple_w := float(GameConfig.get_upgrade_fx("purple").get("chance", 0.30))
	var orange_w := float(GameConfig.get_upgrade_fx("orange").get("chance", 0.10))
	if white_w <= 0.0:
		white_w = 0.20
	if player != null and player.has_method("get_luck_roll_offsets"):
		var offsets: Dictionary = player.get_luck_roll_offsets()
		blue_w = maxf(0.01, blue_w + float(offsets.get("blue", 0.0)))
		purple_w = maxf(0.01, purple_w + float(offsets.get("purple", 0.0)))
		orange_w = maxf(0.01, orange_w + float(offsets.get("orange", 0.0)))
	var total: float = white_w + blue_w + purple_w + orange_w
	var r := randf() * total
	if r <= white_w:
		return "white"
	if r <= white_w + blue_w:
		return "blue"
	if r <= white_w + blue_w + purple_w:
		return "purple"
	return "orange"
