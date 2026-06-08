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
			choices.append(MathUtils.pick_random(fallback if not fallback.is_empty() else GameConfig.upgrades))
		else:
			var idx := randi() % available.size()
			choices.append(available[idx])
			available.remove_at(idx)


func _build_pool(rarity: String, player: Node) -> Array:
	var pool: Array = []
	for u in GameConfig.upgrades:
		if not rarity.is_empty() and str(u.get("rarity", "")) != rarity:
			continue
		if not _is_upgrade_available(u, player):
			continue
		pool.append(u)
	return pool


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
	var blue_w := float(GameConfig.get_upgrade_fx("blue").get("chance", 0.30))
	var purple_w := float(GameConfig.get_upgrade_fx("purple").get("chance", 0.30))
	var orange_w := float(GameConfig.get_upgrade_fx("orange").get("chance", 0.10))
	if player != null and player.has_method("get_luck_roll_offsets"):
		var offsets: Dictionary = player.get_luck_roll_offsets()
		blue_w = maxf(0.01, blue_w + float(offsets.get("blue", 0.0)))
		purple_w = maxf(0.01, purple_w + float(offsets.get("purple", 0.0)))
		orange_w = maxf(0.01, orange_w + float(offsets.get("orange", 0.0)))
	var total: float = blue_w + purple_w + orange_w
	var r := randf() * total
	if r <= blue_w:
		return "blue"
	if r <= blue_w + purple_w:
		return "purple"
	return "orange"
