extends Node

signal game_state_changed(old_state: int, new_state: int)
signal stage_started(stage_index: int)
signal stage_cleared(stage_index: int)
signal stage_transition_started(from_stage: int, to_stage: int)
signal stage_transition_completed(stage_index: int)
signal player_damaged(amount: float, remaining_hp: float)
signal player_healed(amount: float, remaining_hp: float)
signal monster_killed(monster: Node)
signal exp_changed(level: int, exp: int, exp_to_next: int)
signal upgrade_selected(upgrade_id: String)
signal combo_changed(combo: int)
signal gold_changed(total_gold: int)
signal enhance_gem_changed(total_enhance_gem: int)
signal wood_changed(total_wood: int)
signal key_changed(total_keys: int)
signal silver_changed(total_silver: int)
signal stage_countdown_changed(remaining_sec: float)
signal tower_height_changed(height_m: float, target_m: float)
signal equipment_changed
signal forge_buff_applied(buff_name_cn: String, delta_pct: float, world_pos: Vector2)
signal forge_session_complete(rarity: String, stacked_count: int)
signal language_changed(lang: String)
signal talent_changed(id: String, old_level: int, new_level: int)
signal scout_claimed(gold: int)
signal skill_stones_changed
# 云存档读回 / 玩家档案就绪 → 通知 UI 刷新名字、战力、货币等
signal player_profile_loaded
