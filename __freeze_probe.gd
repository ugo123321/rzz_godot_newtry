extends SceneTree

# THROWAWAY headless probe — run with:
#   godot --headless --path <project> --script res://__freeze_probe.gd
# Goal: drive the exact skill-stone equip + battle-entry path repeatedly under
# headless (no GPU), watching for a hang (infinite loop) or unbounded memory.
# Safe to run: headless can't freeze the OS. Delete this file after.

var _iter := 0

func _init() -> void:
	print("=== FREEZE PROBE (headless) ===")
	if LobbyState == null:
		print("LobbyState autoload is null — autoloads not loaded under --script; abort")
		quit(2)
		return
	# DEBUG_TEST_GRANT already ran in LobbyState._ready -> we have ~15 stones.
	var inv: Array = LobbyState.get_skill_stone_inventory_sorted()
	print("startup inventory size: ", inv.size())
	if inv.is_empty():
		print("no stones to test; abort")
		quit(0)
		return
	# Pick a summon-class stone (sr=45) if present, else first.
	var test_uid := int(inv[0].get("uid", -1))
	for s in inv:
		var sid := str(s.get("skill_id", ""))
		if sid.begins_with("summon_") or sid in ["bullet_laser_cannon","trail_psychic","basic_unicorn","bullet_melee","trail_bomber","summon_orbit_shield"]:
			test_uid = int(s.get("uid", -1))
			print("picked special stone: ", sid)
			break
	print("test uid: ", test_uid)

	# Loop: equip -> unequip, repeatedly. Watch memory + detect hang via iteration count.
	for i in 1000:
		var slot := LobbyState.equip_skill_stone(test_uid)
		if slot < 0:
			# maybe already equipped / no slot; unequip all then retry
			for s2 in range(LobbyState.skill_stone_equipped.size()):
				LobbyState.unequip_skill_stone(s2)
			continue
		LobbyState.unequip_skill_stone(slot)
		if i % 100 == 0:
			print("iter ", i, " static_mem=", OS.get_static_memory_usage(),
				" dynamic_mem=", int(Performance.get_monitor(Performance.RENDER_MEMORY)))
		_iter = i
	print("equip/unequip loop done. iters=", _iter)

	# Now exercise the panel scene itself (UI refresh path the user hits).
	var panel_scene := load("res://scenes/ui/skill_stone_panel.tscn")
	if panel_scene != null:
		var root := Control.new()
		get_root().add_child(root)
		var panel = panel_scene.instantiate()
		root.add_child(panel)
		print("panel instantiated; calling _refresh x200")
		for i in 200:
			if panel.has_method("_refresh"):
				panel._refresh()
			if i % 50 == 0:
				print("  panel refresh ", i, " mem=", OS.get_static_memory_usage())
		# Simulate opening detail for first bag slot
		if panel.has_method("_on_bag_slot_pressed") and panel.get("_bag_slot_uids").size() > 0:
			panel._on_bag_slot_pressed(0)
			print("opened detail slot 0 ok")
		panel.queue_free()
		root.queue_free()

	print("=== PROBE COMPLETE — no hang ===")
	quit(0)
