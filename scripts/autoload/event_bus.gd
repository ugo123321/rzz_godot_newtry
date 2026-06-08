extends Node

signal game_state_changed(old_state: int, new_state: int)
signal stage_started(stage_index: int)
signal stage_cleared(stage_index: int)
signal player_damaged(amount: int, remaining_hp: int)
signal player_healed(amount: int, remaining_hp: int)
signal monster_killed(monster: Node)
signal exp_changed(level: int, exp: int, exp_to_next: int)
signal upgrade_selected(upgrade_id: String)
signal combo_changed(combo: int)
signal gold_changed(total_gold: int)
signal equipment_changed
