extends RefCounted
class_name SpecialRuleDispatcher

# Phase 3：special_rule 分发器。
# 把 70 张 sr!=0 卡按 sr 类型分发到对应 handler；事件驱动，与 player.gd 解耦。
#
# 本相落地 10 个 sr：2 / 4 / 6 / 7 / 11 / 14 / 15 / 17 / 19 / 23（10 张卡覆盖）。
# 其余 36 个 sr 走 stub TODO 注释，命中时不做事，方便后续相按需补全。
#
# 调用方式：
#   on_rebuild(player)             ← player._rebuild_upgrades 末尾
#   on_kill(player, monster)       ← EventBus.monster_killed
#   on_tick(player, delta)         ← player._process
#   on_stage_start(player)         ← EventBus.stage_started
#   on_death(player) → bool revived ← player.take_damage 致死前
#   transform_combo_inc(player, inc) → inc   ← register_combo_hit
#   force_crit_on_combo(player, combo) → bool ← make_slash_damage
#   collect_extra_bullet_angles(player, base_ang) → Array[float] ← fire_auto_bullets
#   on_bullet_hit(player, abilities, projectile, monster, info, dealt) ← _apply_projectile_hit
#   transform_bullet_damage(player, projectile, raw_dmg) → raw_dmg ← spawn bullet

# Sheet5 SR 索引（46 entry）：见 rewards_v6_compact.xlsx Sheet5
# 已实现 SR set
const IMPLEMENTED_SR := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56]


# ============= 工具：迭代 player 所有当前装备的卡，按 sr 过滤 =============
static func _iter_sr(player: Node, sr: int) -> Array:
	var out: Array = []
	for id in player.upgrade_stacks.keys():
		var level := int(player.upgrade_stacks[id])
		if level <= 0:
			continue
		var def: Dictionary = GameConfig.upgrades_by_id.get(id, {})
		if def.is_empty():
			continue
		if int(def.get("special_rule", 0)) == sr:
			out.append({"id": id, "level": level, "def": def, "sv": def.get("special_values", []), "sv_per_lv": def.get("special_values_per_lv", [])})
	return out


static func _sv(b: Dictionary, idx: int, default_v: float = 0.0) -> float:
	var sv: Array = b.get("sv", [])
	if idx < 0 or idx >= sv.size():
		return default_v
	var v = sv[idx]
	return float(v) if v != null else default_v


# ============= 主入口：on_rebuild =============
# rebuild 末段执行所有"被动调整 player 字段"的 sr。
# boss_target / 其它需要 rebuild 阶段调整的 sr 在这里写。
static func on_rebuild(player: Node) -> void:
	# sr=0 主题关被动卡：rebuild 前重置视觉状态字段，再按当前装备数填回
	# （这两张卡 sr=0 不走 _iter_sr，直接读 upgrade_stacks）
	if "angel_light_ward_active" in player:
		player.angel_light_ward_active = int(player.upgrade_stacks.get("angel_light_ward", 0)) > 0
	if "demon_vampire_count" in player:
		player.demon_vampire_count = int(player.upgrade_stacks.get("demon_vampire", 0))
	# sr=4 boss_target：vs_boss 关进入时给 atk + 满血
	for b in _iter_sr(player, 4):
		var level: int = int(b.level)
		var dmg_per_lv: float = _sv(b, 0, 0.15)
		var heal_full: bool = _sv(b, 1, 0.0) >= 1.0
		if _is_boss_stage(player):
			player.atk_pct_total += dmg_per_lv * float(level)
			if heal_full:
				player.hp = player.max_hp
				player.boss_target_active = true
		else:
			player.boss_target_active = false
	# sr=2 kill_stack：每层 atk_pct_total += stack_pct
	for b in _iter_sr(player, 2):
		var stacks := mini(int(player.kill_stack_count), int(_sv(b, 1, 5)))
		player.atk_pct_total += _sv(b, 0, 0.08) * float(stacks)
	# sr=44 summon_pact：召唤体型 + 攻速 buff
	for b3 in _iter_sr(player, 44):
		player.summon_size_pct += _sv(b3, 0, 0.15) * float(b3.level)
		player.summon_atk_speed_pct += _sv(b3, 1, 0.5) * float(b3.level)
	# sr=45 summon_unit：spawn 由 SummonAbilityManager 在 update 时按 summon_*_count 自驱
	# 此处仅记录 player 字段，无需 dispatcher 处理

	# sr=29 trail_width：path_line 加宽
	for b29 in _iter_sr(player, 29):
		var pct: float = _sv(b29, 0, 0.1)
		# per_lv 累积：sv_per_lv[0] = 0.1
		player.trail_width_pct_total += pct + (pct * float(maxi(0, b29.level - 1)))

	# sr=30 trail_dmg：dmg_trail_pct 累加
	for b30 in _iter_sr(player, 30):
		var pct2: float = _sv(b30, 0, 0.1)
		player.dmg_trail_pct += pct2 + (pct2 * float(maxi(0, b30.level - 1)))

	# sr=1 on_hit_window：当前 buff 计时器 > 0 时累加 atk_pct
	for b1 in _iter_sr(player, 1):
		if player.on_hit_window_timer > 0.0:
			# attr 1 已经被 AttrEngine 写入 atk_pct_total（trig=on_hit 但本相当作 conditional buff）
			# 实际增益：on_hit 触发后开窗，期间生效
			# AttrEngine 默认不 apply trig=on_hit 的卡（只 passive + hp_below）→ 在这里补写
			for slot in b1.def.get("attrs", []):
				if int(slot.get("id", 0)) == 1:
					var v: float = float(slot.get("value", 0.0))
					var pl = slot.get("per_lv")
					var per_lv: float = float(pl) if pl != null else 0.0
					player.atk_pct_total += v + per_lv * float(maxi(0, b1.level - 1))

	# sr=9 stand_guard：静止累计 >= trigger_value 秒时激活 dmg_reduction
	for b9 in _iter_sr(player, 9):
		var threshold: float = float(b9.def.get("trigger_value", 1.5))
		if player.stand_guard_timer >= threshold:
			for slot in b9.def.get("attrs", []):
				if int(slot.get("id", 0)) == 11:  # damage_reduction_pct
					var v2: float = float(slot.get("value", 0.0))
					var pl2 = slot.get("per_lv")
					var per_lv2: float = float(pl2) if pl2 != null else 0.0
					player.bonus_damage_reduction += v2 + per_lv2 * float(maxi(0, b9.level - 1))
					player.stand_guard_active = true
		else:
			player.stand_guard_active = false

	# sr=21 combo_charge：静止累计 → 增伤百分比（player._process 更新 combo_charge_time）
	for b21 in _iter_sr(player, 21):
		var per_step: float = _sv(b21, 0, 0.2) + _sv_per_lv(b21, 0, 0.2) * float(maxi(0, b21.level - 1))
		var max_mult: float = _sv(b21, 1, 1.5)
		# 充能 0.4s 一档；player 字段 combo_charge_time 由 _process 累加
		var steps: int = int(floor(float(player.combo_charge_time) / 0.4))
		var bonus: float = minf(per_step * float(steps), max_mult - 1.0)
		player.dmg_all_pct += bonus

	# sr=12 bullet_homing：标记开启（ability_manager 每帧读）
	player.bullet_homing_enabled = false
	for b12 in _iter_sr(player, 12):
		if int(_sv(b12, 0, 1.0)) != 0:
			player.bullet_homing_enabled = true

	# sr=16 bullet_mirror：mirror 倍率，0 = 关闭
	player.bullet_mirror_mult = 0.0
	for b16 in _iter_sr(player, 16):
		player.bullet_mirror_mult = maxf(player.bullet_mirror_mult, _sv(b16, 0, 0.6))

	# Phase 6 sr=24 trail_multi：累计 extra_count
	for b24 in _iter_sr(player, 24):
		player.trail_multi_count += int(_sv(b24, 0, 2.0)) * int(b24.level)

	# Phase 6 sr=28 trail_pierce：开关
	for b28 in _iter_sr(player, 28):
		if int(_sv(b28, 0, 1.0)) != 0:
			player.trail_pierce_obstacles = true

	# ============= Phase 7 sword buffs =============
	# sr=38 sword_double：count_mult（满 mult，不累加）
	for b38 in _iter_sr(player, 38):
		player.sword_count_mult = maxf(player.sword_count_mult, _sv(b38, 0, 2.0))
	# sr=41 sword_length：剑半径百分比
	for b41 in _iter_sr(player, 41):
		var pct: float = _sv(b41, 0, 0.15) + _sv_per_lv(b41, 0, 0.15) * float(maxi(0, b41.level - 1))
		player.sword_length_pct += pct
	# sr=42 sword_speed：剑旋转角速度
	for b42 in _iter_sr(player, 42):
		var pct2: float = _sv(b42, 0, 0.15) + _sv_per_lv(b42, 0, 0.15) * float(maxi(0, b42.level - 1))
		player.sword_speed_pct += pct2
	# sr=43 sword_dmg：剑伤百分比
	for b43 in _iter_sr(player, 43):
		var pct3: float = _sv(b43, 0, 0.15) + _sv_per_lv(b43, 0, 0.15) * float(maxi(0, b43.level - 1))
		player.sword_dmg_pct += pct3

	# ============= Phase 7 orb buffs =============
	# sr=33 orb_field：场上球数量百分比
	for b33 in _iter_sr(player, 33):
		var pct4: float = _sv(b33, 0, 0.3) + _sv_per_lv(b33, 0, 0.3) * float(maxi(0, b33.level - 1))
		player.orb_field_pct += pct4
	# sr=34 orb_magnet：拾取半径 + 划线磁吸
	for b34 in _iter_sr(player, 34):
		var pickup_pct: float = _sv(b34, 0, 0.3) + _sv_per_lv(b34, 0, 0.3) * float(maxi(0, b34.level - 1))
		var line_pct: float = _sv(b34, 1, 0.3) + _sv_per_lv(b34, 1, 0.3) * float(maxi(0, b34.level - 1))
		player.orb_pickup_radius_pct += pickup_pct
		player.orb_line_magnet_pct += line_pct
	# sr=36 orb_glow：拾取后下一斩击增伤百分比
	for b36 in _iter_sr(player, 36):
		var pct5: float = _sv(b36, 0, 0.15) + _sv_per_lv(b36, 0, 0.15) * float(maxi(0, b36.level - 1))
		player.orb_glow_dmg_pct += pct5
	# sr=32 orb_mark：拾取后复制概率
	for b32 in _iter_sr(player, 32):
		var pct6: float = _sv(b32, 0, 0.3) + _sv_per_lv(b32, 1, 0.05) * float(maxi(0, b32.level - 1))
		player.orb_mark_dup_chance = maxf(player.orb_mark_dup_chance, pct6)
	# sr=31 orb_tide：周期生成间隔（sv[0]=10 秒/球；sv_per_lv[1]=-1 缩短 1s/级）
	for b31 in _iter_sr(player, 31):
		var base_interval: float = _sv(b31, 0, 10.0)
		var per_lv: float = _sv_per_lv(b31, 1, -1.0)
		var interval: float = maxf(2.0, base_interval + per_lv * float(maxi(0, b31.level - 1)))
		# 取多张卡里最快的（值最小）
		if player.orb_tide_interval_sec <= 0.0 or interval < player.orb_tide_interval_sec:
			player.orb_tide_interval_sec = interval

	# ===== 主题关：恶魔 / 天使 =====
	# sr=46 scythe_on_slash_end：记录倍率 + 贯通；on_slash_end 时投射
	for b46 in _iter_sr(player, 46):
		player.scythe_atk_mult = _sv(b46, 0, 4.0)
		player.scythe_pierce = _sv(b46, 1, 1.0) >= 0.5
	# sr=47 periodic_laser：填好运行时计时参数；on_tick 周期发射
	# 卡片 trigger=timer，AttrEngine 不会把 attr 40/41 写入 cooldown_sec_total / duration_sec_total
	# （_is_card_active 只放过 passive / hp_below）→ 这里直接读卡上的 attrs。
	for b47 in _iter_sr(player, 47):
		player.sulfur_laser_atk_mult = _sv(b47, 0, 0.5)
		player.sulfur_laser_tick = maxf(0.02, _sv(b47, 1, 0.1))
		var cd_sec: float = 6.0
		var dur_sec: float = 1.0
		for slot47 in b47.def.get("attrs", []):
			var aid47 := int(slot47.get("id", 0))
			if aid47 == 40:
				cd_sec = float(slot47.get("value", 6.0))
			elif aid47 == 41:
				dur_sec = float(slot47.get("value", 1.0))
		player.sulfur_laser_cd = maxf(0.5, cd_sec)
		player.sulfur_laser_duration = maxf(0.1, dur_sec)
		# 装备瞬间不立刻喷激光（首次也走完整 cd），避免选完卡画面就被亮闪一下
		if float(player.sulfur_laser_timer) <= 0.0:
			player.sulfur_laser_timer = player.sulfur_laser_cd
	# sr=48 multi_revive：装备时初始化剩余复活次数（仅第一次进入时；rebuild 不应清零）
	for b48 in _iter_sr(player, 48):
		var extra_lives: int = int(_sv(b48, 0, 8.0))
		player.multi_revive_post_hp = maxi(1, int(_sv(b48, 1, 1.0)))
		# 仅当当前剩余次数 < 表上的总数时补足（避免每次 rebuild 重置已用次数）
		if player.multi_revive_extra <= 0 and not bool(player.multi_revive_used):
			player.multi_revive_extra = extra_lives
	# sr=49 blood_bullet：穿透 / 射程倍率
	for b49 in _iter_sr(player, 49):
		player.blood_blade_pierce = _sv(b49, 0, 1.0) >= 0.5
		player.blood_blade_range_mult = _sv(b49, 1, 2.0)
	# sr=50 proximity_slow：范围 / 最大减速%
	for b50 in _iter_sr(player, 50):
		player.proximity_slow_radius = maxf(player.proximity_slow_radius, _sv(b50, 0, 300.0))
		player.proximity_slow_max = maxf(player.proximity_slow_max, _sv(b50, 1, 0.5))

	# ===== 追加：sr 51-56 =====
	# sr=51 psychic_petrify_all：记录石化持续秒（每级 +_sv_per_lv[0]）
	for b51 in _iter_sr(player, 51):
		var pd: float = _sv(b51, 0, 1.0) + _sv_per_lv(b51, 0, 0.3) * float(maxi(0, b51.level - 1))
		player.psychic_petrify_duration = maxf(player.psychic_petrify_duration, pd)
	# sr=52 periodic_iframe（独角兽）：CD 走 attr 40，持续走 attr 41
	for b52 in _iter_sr(player, 52):
		var u_cd: float = 15.0
		var u_dur: float = 5.0
		for slot52 in b52.def.get("attrs", []):
			var aid52 := int(slot52.get("id", 0))
			if aid52 == 40:
				u_cd = float(slot52.get("value", 15.0)) + float(slot52.get("per_lv", 0.0)) * float(maxi(0, b52.level - 1))
			elif aid52 == 41:
				u_dur = float(slot52.get("value", 5.0)) + float(slot52.get("per_lv", 0.0)) * float(maxi(0, b52.level - 1))
		player.unicorn_cd = maxf(3.0, u_cd)
		player.unicorn_duration = maxf(0.5, u_dur)
		# 首次装备：预热到 CD 秒（避免选卡瞬间就无敌）
		if player.unicorn_timer <= 0.0:
			player.unicorn_timer = player.unicorn_cd
	# sr=53 laser_cannon_basic：普攻改激光炮
	for b53 in _iter_sr(player, 53):
		player.laser_cannon_active = true
		player.laser_cannon_atk_mult = _sv(b53, 0, 3.0)
		player.laser_cannon_color_key = _sv_str(b53, 1, "white")
		player.laser_cannon_pierce = _sv(b53, 2, 1.0) >= 0.5
	# sr=54 melee_basic：普攻改近战
	for b54 in _iter_sr(player, 54):
		player.melee_basic_active = true
		player.melee_basic_atk_bonus = _sv(b54, 0, 0.5)
		player.melee_range_px = _sv(b54, 1, 60.0)
	# sr=55 bomb_on_slash_end：炸弹人
	for b55 in _iter_sr(player, 55):
		player.bomber_atk_mult = _sv(b55, 0, 3.0) + _sv_per_lv(b55, 0, 0.5) * float(maxi(0, b55.level - 1))
		player.bomber_fuse_sec = _sv(b55, 1, 2.0)
		player.bomber_cross_arm_px = _sv(b55, 2, 180.0)
	# sr=56 orbit_shield：数量已由 attr 46 (shield_orbit_count_add) 累加，读 sv 拿轨道参数
	for b56 in _iter_sr(player, 56):
		player.shield_orbit_radius = _sv(b56, 0, 280.0)
		player.shield_orbit_speed = _sv(b56, 1, 1.5)


# 工具：取 sv_per_lv[idx]
static func _sv_per_lv(b: Dictionary, idx: int, default_v: float = 0.0) -> float:
	var sv: Array = b.get("sv_per_lv", [])
	if idx < 0 or idx >= sv.size():
		return default_v
	var v = sv[idx]
	return float(v) if v != null else default_v


# ============= on_kill：怪被杀时 =============
static func on_kill(player: Node, _monster) -> void:
	for b in _iter_sr(player, 2):
		var max_stacks: int = int(_sv(b, 1, 5))
		var duration: float = _sv(b, 2, 3.0)
		player.kill_stack_count = mini(player.kill_stack_count + 1, max_stacks)
		player.kill_stack_timer = duration
		# 立即 rebuild 让叠层生效
		if player.has_method("_rebuild_upgrades"):
			player._rebuild_upgrades()


# ============= on_tick：每帧 =============
static func on_tick(player: Node, delta: float) -> void:
	# sr=2 kill_stack 超时清零
	if player.kill_stack_count > 0:
		player.kill_stack_timer = maxf(0.0, player.kill_stack_timer - delta)
		if player.kill_stack_timer <= 0.0:
			player.kill_stack_count = 0
			if player.has_method("_rebuild_upgrades"):
				player._rebuild_upgrades()

	# sr=1 on_hit_window：buff 计时器衰减；归零触发 rebuild 清除 buff
	if player.on_hit_window_timer > 0.0:
		player.on_hit_window_timer = maxf(0.0, player.on_hit_window_timer - delta)
		if player.on_hit_window_timer <= 0.0:
			if player.has_method("_rebuild_upgrades"):
				player._rebuild_upgrades()

	# sr=10 iframe_on_hit CD 衰减
	if player.iframe_cd_timer > 0.0:
		player.iframe_cd_timer = maxf(0.0, player.iframe_cd_timer - delta)

	# sr=9 stand_guard + sr=21 combo_charge：静止时累加
	if _is_player_stationary(player):
		player.stand_guard_timer += delta
		player.combo_charge_time += delta
	else:
		if player.stand_guard_timer > 0.0 or player.combo_charge_time > 0.0:
			player.stand_guard_timer = 0.0
			player.combo_charge_time = 0.0
			if player.has_method("_rebuild_upgrades"):
				player._rebuild_upgrades()

	# sr=8 low_hp_regen
	for b8 in _iter_sr(player, 8):
		var hp_threshold: float = _sv(b8, 0, 0.3)
		var regen_base: float = _sv(b8, 1, 0.01)
		var regen_per_lv: float = _sv_per_lv(b8, 2, 0.01)
		var target_hp_pct: float = _sv(b8, 3, 0.3)
		if float(player.max_hp) <= 0.0:
			continue
		var ratio: float = float(player.hp) / float(player.max_hp)
		if ratio >= hp_threshold:
			continue
		var regen_pct_per_sec: float = regen_base + regen_per_lv * float(maxi(0, b8.level - 1))
		var regen_amount: float = float(player.max_hp) * regen_pct_per_sec * delta
		var max_target: int = int(round(float(player.max_hp) * target_hp_pct))
		var new_hp: int = mini(max_target, player.hp + int(round(regen_amount)))
		if new_hp > player.hp:
			player.hp = new_hp

	# sr=3 aura：周期 tick 给周围怪伤害（vuln 简化省略）
	for b3 in _iter_sr(player, 3):
		var tick_interval: float = _sv(b3, 1, 0.3)
		if not "aura_tick_timer" in player:
			continue
		player.aura_tick_timer = float(player.aura_tick_timer) - delta
		if float(player.aura_tick_timer) > 0.0:
			continue
		player.aura_tick_timer = tick_interval
		_aura_tick(player, b3)

	# sr=5 trail_burn_walk：脚下火地（每 tick 检测玩家周围怪）
	for b5 in _iter_sr(player, 5):
		var tick5: float = _sv(b5, 1, 0.5)
		player.flame_walk_timer = float(player.flame_walk_timer) - delta
		if float(player.flame_walk_timer) > 0.0:
			continue
		player.flame_walk_timer = tick5
		_flame_walk_tick(player, b5)

	# sr=47 periodic_laser（硫磺火）：每 cd 秒触发一次持续 duration 秒的跟随激光
	# 单条激光由 ability_manager 自己管寿命/跟随/tick；这里只负责按 cd 周期 spawn
	if float(player.sulfur_laser_atk_mult) > 0.0:
		player.sulfur_laser_timer -= delta
		if player.sulfur_laser_timer <= 0.0:
			player.sulfur_laser_timer = player.sulfur_laser_cd
			var battle_node = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
			var abilities_node = battle_node.abilities if battle_node else null
			if abilities_node and abilities_node.has_method("spawn_v6_sulfur_laser"):
				abilities_node.spawn_v6_sulfur_laser(player, float(player.sulfur_laser_atk_mult), float(player.sulfur_laser_duration), float(player.sulfur_laser_tick))

	# sr=50 proximity_slow（无下限术式）：把范围内怪物当前帧 slow_pct 写回（按距离线性）
	if float(player.proximity_slow_radius) > 0.0 and float(player.proximity_slow_max) > 0.0:
		var battle2 = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
		if battle2 and battle2.spawner:
			var r: float = float(player.proximity_slow_radius)
			var max_slow: float = float(player.proximity_slow_max)
			for m in battle2.spawner.get_active_monsters():
				if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
					continue
				var d: float = player.global_position.distance_to(m.global_position)
				if d > r:
					if "proximity_slow_pct" in m:
						m.proximity_slow_pct = 0.0
					continue
				var pct: float = clampf(max_slow * (1.0 - d / r), 0.0, max_slow)
				if "proximity_slow_pct" in m:
					m.proximity_slow_pct = pct

	# sr=52 periodic_iframe（独角兽）：定时无敌
	if float(player.unicorn_cd) > 0.0:
		player.unicorn_timer = maxf(0.0, float(player.unicorn_timer) - delta)
		if player.unicorn_timer <= 0.0:
			player.unicorn_timer = player.unicorn_cd
			player.invincible_timer = maxf(float(player.invincible_timer), float(player.unicorn_duration))
	# invincible 时开启彩虹 modulate 标志（真正 modulate 由 player.gd 自绘时读取）
	player.unicorn_rainbow_active = float(player.unicorn_cd) > 0.0 and float(player.invincible_timer) > 0.0

	# sr=56 orbit_shield：轨道旋转 + 挡敌方子弹检测
	if int(player.shield_orbit_count) > 0:
		player.shield_orbit_angle = fmod(float(player.shield_orbit_angle) + float(player.shield_orbit_speed) * delta, TAU)
		_orbit_shield_tick(player)


# sr=3 aura 实际 tick：给范围内每个怪一次性伤害
static func _aura_tick(player: Node, b: Dictionary) -> void:
	var radius_px: float = _sv(b, 0, 200.0)
	var atk_mult: float = _sv(b, 2, 0.4)
	var battle = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
	if battle == null or battle.spawner == null:
		return
	for m in battle.spawner.get_active_monsters():
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		if player.global_position.distance_to(m.global_position) > radius_px:
			continue
		var info = player.make_ability_damage("aura_tick", atk_mult, "physical", "", false, false)
		if m.has_method("take_damage_info"):
			m.take_damage_info(info, player.global_position)


# sr=5 flame walk：玩家走过的脚下生成 fire 场域瓦片（视觉沿路径 + 持续燃烧 tick）
# 复用 trail_fire_wall 的 v6_trail_field 通道：每 spawn_tick 秒在玩家当前位置放一片，
# 每片自带 duration 秒寿命 + 每 0.5s 一次的伤害 tick，过路的怪自动被烧。
static func _flame_walk_tick(player: Node, b: Dictionary) -> void:
	var atk_mult: float = _sv(b, 0, 0.15)
	var duration: float = _sv(b, 2, 2.0)
	var battle = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
	if battle == null:
		return
	var abilities_node = battle.abilities
	if abilities_node == null or not abilities_node.has_method("spawn_v6_trail_field"):
		return
	abilities_node.spawn_v6_trail_field(
		player, [player.global_position], "fire",
		atk_mult, 0.5, 0.0, 0.0, 0.0, duration, false, "basic_flame_walk"
	)


static func _is_player_stationary(player: Node) -> bool:
	if not "_last_position" in player:
		return false
	return player.global_position.distance_to(player._last_position) <= 2.0


# ============= on_player_damaged：take_damage 触发后 =============
# 返回 true 表示本次伤害应改为 0（sr=10 iframe）
static func on_player_damaged(player: Node, raw_damage: int) -> bool:
	# sr=10 iframe_on_hit：CD ≤ 0 时给予无敌
	for b10 in _iter_sr(player, 10):
		var iframe_sec: float = _sv(b10, 0, 1.5)
		# CD 走 attr 40 cooldown_sec：sv=[1.5]; attrs 含 attr_40=6
		var cd: float = 6.0
		for slot in b10.def.get("attrs", []):
			if int(slot.get("id", 0)) == 40:
				cd = float(slot.get("value", 6.0))
		if player.iframe_cd_timer <= 0.0:
			player.invincible_timer = maxf(player.invincible_timer, iframe_sec)
			player.iframe_cd_timer = cd
			return true  # 本次伤害免疫
	# sr=1 on_hit_window：开启 buff 计时（duration 走 attr 41 默认 5s）
	for b1 in _iter_sr(player, 1):
		var dur: float = 5.0
		for slot2 in b1.def.get("attrs", []):
			if int(slot2.get("id", 0)) == 41:
				dur = float(slot2.get("value", 5.0))
		player.on_hit_window_timer = maxf(player.on_hit_window_timer, dur)
		if player.has_method("_rebuild_upgrades"):
			player._rebuild_upgrades()
	return false


# ============= on_slash_end：slash 路径完成后 =============
# 触发"画线末释放"类奖励 — 仅当本次画线把气力耗尽时才触发，避免短画线反复释放。
# 受门控：sr=22 combo_shuriken / sr=46 scythe_on_slash_end
static func on_slash_end(player: Node, abilities: Node, end_pos: Vector2 = Vector2.INF, end_ang: float = 0.0) -> void:
	var ki_drained: bool = bool(player.slash_end_ki_drained)
	if ki_drained:
		for b22 in _iter_sr(player, 22):
			if abilities and abilities.has_method("spawn_combo_shuriken"):
				abilities.spawn_combo_shuriken(player, str(_sv_str(b22, 0, "line")))
		# sr=46 死神镰刀
		if float(player.scythe_atk_mult) > 0.0 and abilities and abilities.has_method("spawn_v6_demon_scythe"):
			var pos: Vector2 = end_pos if end_pos.x != INF else player.global_position
			abilities.spawn_v6_demon_scythe(player, pos, end_ang, float(player.scythe_atk_mult), bool(player.scythe_pierce))
		# sr=51 念力：全场石化
		if float(player.psychic_petrify_duration) > 0.0:
			var battle_p = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
			if battle_p and battle_p.spawner:
				var dur: float = float(player.psychic_petrify_duration)
				for m in battle_p.spawner.get_active_monsters():
					if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
						continue
					if m.has_method("apply_petrify"):
						m.apply_petrify(dur)
		# sr=55 炸弹人：末端埋十字炸弹
		if float(player.bomber_atk_mult) > 0.0 and abilities and abilities.has_method("spawn_v6_cross_bomb"):
			var bpos: Vector2 = end_pos if end_pos.x != INF else player.global_position
			abilities.spawn_v6_cross_bomb(player, bpos, float(player.bomber_atk_mult), float(player.bomber_fuse_sec), float(player.bomber_cross_arm_px))
	# 注：标记清零放在 player.gd 调用完所有 slash-end 系列后（on_slash_end + on_slash_wave + 闭合爆炸）统一清零


static func _sv_str(b: Dictionary, idx: int, default_s: String = "") -> String:
	var sv: Array = b.get("sv", [])
	if idx < 0 or idx >= sv.size():
		return default_s
	var v = sv[idx]
	return str(v) if v != null else default_s


# ============= apply_bullet_homing：子弹每帧调整 =============
# 返回新 velocity Vector2；ability_manager 在 update 子弹时调
# 关键：用角度差转向而不是 vec.lerp(vec, t) —— 后者两个等长但异向的向量做 lerp 长度会减小，
#       导致 homing 子弹每帧丢速度，越拐越慢 + 看起来"移速怪异"。
static func apply_bullet_homing(player: Node, projectile: Dictionary, monsters: Array, delta: float) -> Vector2:
	if not bool(player.bullet_homing_enabled):
		return projectile.get("vel", Vector2.ZERO)
	# 找最近的怪
	var pos: Vector2 = projectile.get("pos", Vector2.ZERO)
	var best = null
	var best_d := 9e9
	for m in monsters:
		if not is_instance_valid(m) or not bool(m.get("alive")) or bool(m.get("dying")):
			continue
		var d: float = pos.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return projectile.get("vel", Vector2.ZERO)
	var current_vel: Vector2 = projectile.get("vel", Vector2.ZERO)
	var speed: float = current_vel.length()
	if speed < 0.001:
		return current_vel
	# 角度转向（保速度），每秒最多 1.5 圈
	var current_ang: float = current_vel.angle()
	var target_ang: float = (best.global_position - pos).angle()
	var diff: float = wrapf(target_ang - current_ang, -PI, PI)
	var max_turn: float = TAU * 1.5 * delta
	var step: float = clampf(diff, -max_turn, max_turn)
	var new_ang: float = current_ang + step
	return Vector2(cos(new_ang), sin(new_ang)) * speed


# ============= on_bullet_first_hit_mirror：子弹首次命中后，若 mirror 启用，返回回弹方向 =============
# 返回 Vector2.ZERO 表示无 mirror；否则返回回弹起点指向玩家的方向
static func on_bullet_first_hit_mirror(player: Node, projectile: Dictionary, monster) -> float:
	if float(player.bullet_mirror_mult) <= 0.0:
		return 0.0
	if bool(projectile.get("is_split", false)) or bool(projectile.get("is_bounce", false)) or bool(projectile.get("mirror_used", false)):
		return 0.0
	return float(player.bullet_mirror_mult)


# ============= on_stage_start：每关开始 =============
static func on_stage_start(player: Node) -> void:
	# sr=6 shield：每关开始时给护盾（charges = sv[0] × level）
	for b in _iter_sr(player, 6):
		var charges: int = int(round(_sv(b, 0, 1.0) * float(b.level)))
		var on_stage: bool = _sv(b, 2, 1.0) >= 1.0
		if on_stage and charges > 0 and "holy_shield_charges" in player:
			player.holy_shield_charges = maxi(player.holy_shield_charges, charges)


# ============= on_death：致死前给一次复活机会，返回 true 则继续活 =============
static func on_death(player: Node) -> bool:
	# sr=48 multi_revive（九命猫）：剩余次数 > 0 时复活到固定 HP
	for b48 in _iter_sr(player, 48):
		if int(player.multi_revive_extra) <= 0:
			continue
		player.hp = maxi(1, int(player.multi_revive_post_hp))
		player.invincible_timer = 1.5
		player.multi_revive_extra -= 1
		player.multi_revive_used = true
		return true
	for b in _iter_sr(player, 7):
		var revive_hp_pct: float = _sv(b, 0, 0.5)
		var once_per_run: bool = _sv(b, 1, 1.0) >= 1.0
		if once_per_run and bool(player.revive_used):
			continue
		# 复活
		player.hp = maxi(1, int(round(float(player.max_hp) * revive_hp_pct)))
		player.invincible_timer = 1.5  # 复活后短暂无敌
		player.revive_used = true
		return true
	return false


# ============= transform_combo_inc：sr=19 连击数翻倍 =============
static func transform_combo_inc(player: Node, inc: float) -> float:
	var mult := 1.0
	for b in _iter_sr(player, 19):
		mult *= _sv(b, 0, 2.0)
	return inc * mult


# ============= force_crit_on_combo：sr=23 连击里程碑必暴 =============
static func force_crit_on_combo(player: Node, combo: int) -> bool:
	for b in _iter_sr(player, 23):
		var step: int = maxi(1, int(_sv(b, 0, 10)))
		if combo > 0 and combo % step == 0:
			return true
	return false


# ============= collect_extra_bullet_angles：sr=17 斜射 =============
static func collect_extra_bullet_angles(player: Node, base_ang: float) -> Array:
	var out: Array = []
	for b in _iter_sr(player, 17):
		var count: int = int(_sv(b, 0, 2))
		var angle_deg: float = _sv(b, 1, 30.0)
		var ang_rad: float = deg_to_rad(angle_deg)
		# 左右对称；count=2 → 一边一颗；count=4 → 一边两颗
		var per_side: int = maxi(1, count / 2)
		for i in range(per_side):
			var step: float = ang_rad * float(i + 1) / float(per_side)
			out.append(base_ang + step)
			out.append(base_ang - step)
	return out


# ============= on_bullet_hit：sr=14 split / sr=15 bounce =============
# abilities = ability_manager（spawn 入口）；info 含 player 引用
# split 命中就分裂（dealt 可以 = 0，例如被护盾挡掉）；bounce 需要 dealt > 0 作为衰减基数。
static func on_bullet_hit(player: Node, abilities: Node, projectile: Dictionary, monster, info, dealt: int) -> void:
	var is_split: bool = bool(projectile.get("is_split", false))
	var is_bounce: bool = bool(projectile.get("is_bounce", false))
	# split 子弹自身不再 split / bounce 避免连锁
	if is_split:
		return
	# bounce 子弹命中后继续 bounce（直到 remaining=0）；不允许 split
	if is_bounce:
		if dealt <= 0:
			return
		var remaining: int = int(projectile.get("bounce_remaining", 0))
		var falloff: float = float(projectile.get("bounce_falloff", 0.6))
		if remaining > 0 and abilities and abilities.has_method("spawn_bounce_bullet"):
			var next_dmg: int = int(max(1, round(float(dealt) * falloff)))
			abilities.spawn_bounce_bullet(player, monster, remaining, next_dmg, falloff)
		return
	# 普通命中：触发 split + bounce
	# sr=14 bullet_split — 命中就触发（不依赖 dealt），即使被护盾挡掉也分裂
	for b in _iter_sr(player, 14):
		var count: int = int(_sv(b, 0, 3))
		var base_mult: float = _sv(b, 1, 0.5)
		var per_lv: float = _sv(b, 2, 0.1)
		var atk_mult: float = base_mult + per_lv * float(maxi(0, b.level - 1))
		var split_dmg: int = int(max(1, round(float(player.get_ability_damage(1.0)) * atk_mult * float(GameConfig.get_player_value("auto_bullet_damage_mult", 0.2)))))
		if abilities and abilities.has_method("spawn_split_bullet"):
			for i in range(count):
				var ang: float = randf() * TAU
				abilities.spawn_split_bullet(player, monster.global_position, ang, split_dmg)
	# sr=15 bullet_bounce — 需要 dealt > 0 作为衰减基数
	if dealt <= 0:
		return
	for b2 in _iter_sr(player, 15):
		var bounce_per_lv: int = int(_sv(b2, 0, 1))
		var bf: float = _sv(b2, 1, 0.6)
		var bounces_remaining: int = bounce_per_lv * int(b2.level)
		if bounces_remaining <= 0:
			continue
		var bounce_dmg: int = int(max(1, round(float(dealt) * bf)))
		if abilities and abilities.has_method("spawn_bounce_bullet"):
			abilities.spawn_bounce_bullet(player, monster, bounces_remaining, bounce_dmg, bf)


# ============= transform_bullet_damage：sr=11 spirit_bomb 飞行距离加成 =============
# raw_dmg = 命中时 dmg；按 projectile 飞行距离 / range_px 比例加最高 +50%
# （projectile 上字段名是 range_px，原代码读 max_range 落到默认值 320 → 与实际 378 略差）
static func transform_bullet_damage(player: Node, projectile: Dictionary, raw_dmg: int) -> int:
	var scale_total := 1.0
	for b in _iter_sr(player, 11):
		var pct_max: float = _sv(b, 0, 0.5)
		var pos: Vector2 = projectile.get("pos", Vector2.ZERO)
		var origin: Vector2 = projectile.get("origin", Vector2.ZERO)
		var travel: float = pos.distance_to(origin)
		var max_range: float = maxf(50.0, float(projectile.get("range_px", 378.0)))
		var t: float = clampf(travel / max_range, 0.0, 1.0)
		scale_total *= 1.0 + pct_max * t
	return int(max(1, round(float(raw_dmg) * scale_total)))


# ============= 工具 =============

static func _is_boss_stage(player: Node) -> bool:
	# 简单兜底：从 GameConfig 当前 stage 取 is_boss 字段
	var battle := player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
	if battle == null:
		return false
	var stage_idx: int = int(battle.get("stage_index")) if "stage_index" in battle else 0
	var stage_def: Dictionary = GameConfig.get_stage(stage_idx)
	return int(stage_def.get("is_boss", 0)) != 0


# ============= Phase 6: sr=20 combo_milestone_spell =============
# ability_manager.on_combo_hit 末尾调用；按已装备的 5 张 combo_* 卡的 trigger_value 触发对应 spell。
static func on_combo_milestone(player: Node, abilities: Node, combo_count: int, hit_pos: Vector2, seg_ang: float) -> void:
	if combo_count <= 0 or abilities == null:
		return
	for b in _iter_sr(player, 20):
		var step: int = int(b.def.get("trigger_value", 0))
		if step <= 0:
			continue
		if combo_count % step != 0:
			continue
		var card_id: String = str(b.id)
		var lv: int = int(b.level)
		var weapon_mult: float = float(b.def.get("weapon_mult", 1.0))
		_spawn_combo_v6(abilities, player, card_id, lv, weapon_mult, hit_pos, seg_ang, b)


static func _spawn_combo_v6(abilities: Node, player: Node, card_id: String, level: int, weapon_mult: float, hit_pos: Vector2, seg_ang: float, b: Dictionary) -> void:
	# 复用 ability_manager 现有 spawn helpers；v6 weapon_mult 通过 abilities 接口注入
	match card_id:
		"combo_black_hole":
			if abilities.has_method("spawn_v6_black_hole"):
				abilities.spawn_v6_black_hole(player, hit_pos, level, weapon_mult)
		"combo_fireball":
			if abilities.has_method("spawn_v6_fireballs"):
				abilities.spawn_v6_fireballs(player, hit_pos, seg_ang, level, weapon_mult)
		"combo_water_tornado":
			if abilities.has_method("spawn_v6_water_tornado"):
				abilities.spawn_v6_water_tornado(player, hit_pos, seg_ang, level, weapon_mult)
		"combo_blade_storm":
			var extra_per_lv: int = int(_sv_per_lv(b, 2, 1.0))
			var radius: float = _sv(b, 1, 150.0)
			if abilities.has_method("spawn_v6_blade_storm"):
				abilities.spawn_v6_blade_storm(player, hit_pos, level, weapon_mult, radius, extra_per_lv)
		"combo_thunder":
			var radius2: float = _sv(b, 1, 200.0)
			if abilities.has_method("spawn_v6_thunder"):
				abilities.spawn_v6_thunder(player, hit_pos, level, weapon_mult, radius2)


# ============= Phase 6: sr=13 bullet_fire_support / sr=18 bullet_beam =============
# proc_chance = sv[0] + sv[1]*(level-1)
# sr=13: atk_mult=sv[2], radius=sv[3] → spawn 小 AOE
# sr=18: atk_mult=sv[2], pierce=sv[3] → spawn laser
static func on_bullet_proc(player: Node, abilities: Node, hit_pos: Vector2, dir_ang: float) -> void:
	if abilities == null:
		return
	for b13 in _iter_sr(player, 13):
		var p_base: float = _sv(b13, 0, 0.1)
		var p_per_lv: float = _sv_per_lv(b13, 1, 0.1)
		var proc: float = p_base + p_per_lv * float(maxi(0, b13.level - 1))
		if randf() < proc:
			var atk_mult: float = _sv(b13, 2, 0.8)
			var radius: float = _sv(b13, 3, 100.0)
			# 区分火力支援 (bullet_fire_support) vs 圣光子弹 (angel_holy_bullet)
			var style: String = "holy" if str(b13.id) == "angel_holy_bullet" else "bomb"
			# 火力支援走抛物线手榴弹弹道（玩家投出 → 落到 hit_pos → bomb 爆炸）；
			# 圣光子弹是天降光柱，直接走旧的 spawn_v6_bullet_aoe（grenade_arc 内部识别 style 转发）
			if style == "bomb" and abilities.has_method("spawn_v6_grenade_arc"):
				abilities.spawn_v6_grenade_arc(player, player.global_position, hit_pos, atk_mult, radius, style)
			elif abilities.has_method("spawn_v6_bullet_aoe"):
				abilities.spawn_v6_bullet_aoe(player, hit_pos, atk_mult, radius, style)
	for b18 in _iter_sr(player, 18):
		var p_base2: float = _sv(b18, 0, 0.1)
		var p_per_lv2: float = _sv_per_lv(b18, 1, 0.1)
		var proc2: float = p_base2 + p_per_lv2 * float(maxi(0, b18.level - 1))
		if randf() < proc2:
			var atk_mult2: float = _sv(b18, 2, 1.0)
			if abilities.has_method("spawn_v6_bullet_beam"):
				abilities.spawn_v6_bullet_beam(player, hit_pos, dir_ang, atk_mult2)


# ============= Phase 6: sr=26 trail_slash_wave =============
# slash 末段 spawn 推开 + 伤害 AOE。radius = sv[0] + sv_per_lv[1] * (level-1)
# 仅当本次画线把气力耗尽时触发（避免短画线反复释放）
static func on_slash_wave(player: Node, abilities: Node, end_pos: Vector2) -> void:
	if abilities == null:
		return
	if not bool(player.slash_end_ki_drained):
		return
	for b in _iter_sr(player, 26):
		var radius_base: float = _sv(b, 0, 200.0)
		var radius_per_lv: float = _sv_per_lv(b, 1, 100.0)
		var radius: float = radius_base + radius_per_lv * float(maxi(0, b.level - 1))
		var weapon_mult: float = float(b.def.get("weapon_mult", 2.5))
		if abilities.has_method("spawn_v6_slash_wave"):
			abilities.spawn_v6_slash_wave(player, end_pos, radius, weapon_mult)


# ============= Phase 6: sr=27 trail_loop_explode =============
# 闭合 path 检测后 spawn 爆炸；weapon_mult = base_mult * level（per_lv 提供 0.3）
# min_area = sv[1] 用于过滤过小闭环
# 仅当本次画线把气力耗尽时触发（避免短闭环反复刷爆炸）
static func on_loop_explode(player: Node, abilities: Node, loops: Array) -> Array:
	# 返回 [{"center": Vec2, "radius": float, "weapon_mult": float}, ...]
	var out: Array = []
	if abilities == null or loops.is_empty():
		return out
	if not bool(player.slash_end_ki_drained):
		return out
	for b in _iter_sr(player, 27):
		var base_mult: float = float(b.def.get("weapon_mult", 3.0))
		var per_lv: float = _sv_per_lv(b, 0, 0.3)
		var min_area: float = _sv(b, 1, 1000.0)
		var total_mult: float = base_mult * (1.0 + per_lv * float(maxi(0, b.level - 1)))
		for loop in loops:
			var area: float = _polygon_area(loop)
			if area < min_area:
				continue
			var center: Vector2 = _polygon_centroid(loop)
			var radius: float = _polygon_max_radius(loop, center)
			out.append({"center": center, "radius": radius, "weapon_mult": total_mult})
	return out


static func _polygon_area(loop: Array) -> float:
	if loop.size() < 3:
		return 0.0
	var s := 0.0
	for i in range(loop.size()):
		var a: Vector2 = loop[i]
		var bb: Vector2 = loop[(i + 1) % loop.size()]
		s += a.x * bb.y - bb.x * a.y
	return absf(s) * 0.5


static func _polygon_centroid(loop: Array) -> Vector2:
	if loop.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for p in loop:
		c += p
	return c / float(loop.size())


static func _polygon_max_radius(loop: Array, center: Vector2) -> float:
	var r := 0.0
	for p in loop:
		r = maxf(r, center.distance_to(p))
	return r


# ============= Phase 6: sr=24 trail_multi =============
# 返回平行偏移 vector 列表，给 _record_path_crossings 调用
static func get_trail_offsets(player: Node, seg_dir: Vector2) -> Array:
	var offsets: Array = [Vector2.ZERO]
	var normal: Vector2 = Vector2(-seg_dir.y, seg_dir.x).normalized()
	for b in _iter_sr(player, 24):
		var extra_count: int = int(_sv(b, 0, 2.0))
		var spacing: float = 28.0  # 平行线间距
		for i in range(extra_count):
			var offset_dist: float = spacing * (float(i / 2 + 1)) * (1.0 if i % 2 == 0 else -1.0)
			offsets.append(normal * offset_dist)
	return offsets


# ============= Phase 7: sr=39 sword_rage =============
# special_values 约定（与 SPECIAL_RULE_CODES schema 一致）：
#   sv[0] = proc       触发概率（描述里的 15%）
#   sv[1] = atk_mult   旋风伤害倍率（描述里的 2.5×ATK）
#   sv_per_lv[2] = radius_per_lv 半径每级 +X%（描述里的 +5%/级）
# 视觉：spawn_v6_sword_whirlwind —— 从剑当前位置朝命中方向直线飞行的旋风（whirl 视觉自带旋转），
# 行进中持续 AOE 命中。区别于 combo_blade_storm 的固定原地转刀阵。
const SWORD_RAGE_BASE_RADIUS := 130.0
static func on_sword_hit(player: Node, abilities: Node, target_pos: Vector2, sword_pos: Vector2) -> void:
	if abilities == null:
		return
	for b in _iter_sr(player, 39):
		var proc: float = _sv(b, 0, 0.15)
		if randf() >= proc:
			continue
		var atk_mult: float = _sv(b, 1, 2.5)
		var radius_per_lv: float = _sv_per_lv(b, 2, 0.05)
		var radius: float = SWORD_RAGE_BASE_RADIUS * (1.0 + radius_per_lv * float(maxi(0, b.level - 1)))
		var dir: Vector2 = target_pos - sword_pos
		if abilities.has_method("spawn_v6_sword_whirlwind"):
			abilities.spawn_v6_sword_whirlwind(player, sword_pos, dir, atk_mult, radius)


# ============= Phase 7: sr=32 orb_mark dup chance accessor =============
static func roll_orb_dup(player: Node) -> bool:
	return randf() < float(player.orb_mark_dup_chance)


# ============= Phase 7: sr=35 orb_burst =============
# 拾取时按 weapon_mult * (1+per_lv*(level-1)) spawn 一次 AOE
static func on_orb_pickup(player: Node, abilities: Node, pos: Vector2, _orb_type: String) -> void:
	if abilities == null:
		return
	for b in _iter_sr(player, 35):
		var base_mult: float = float(b.def.get("weapon_mult", 1.5))
		var per_lv: float = _sv_per_lv(b, 0, 0.3)
		var atk_mult: float = base_mult * (1.0 + per_lv * float(maxi(0, b.level - 1)))
		if abilities.has_method("spawn_v6_bullet_aoe"):
			abilities.spawn_v6_bullet_aoe(player, pos, atk_mult, 120.0)
	# Phase 7 sr=36 orb_glow：标记下次斩击启用 buff（dmg_pct 已在 on_rebuild 计算）
	if float(player.orb_glow_dmg_pct) > 0.0:
		player.orb_glow_pending_active = true
	# sr=37 元素球：按 orb_type 给附近怪施元素状态（取所有装备的元素球卡的 elem 字段）
	_apply_orb_element_aoe(player, abilities, pos)


static func _apply_orb_element_aoe(player: Node, abilities: Node, pos: Vector2) -> void:
	for b in _iter_sr(player, 37):
		var elem: String = _sv_str(b, 1, "")
		var atk_mult: float = _sv(b, 0, 1.0) + _sv_per_lv(b, 0, 0.2) * float(maxi(0, b.level - 1))
		if elem == "":
			continue
		if abilities.has_method("spawn_v6_orb_elem_aoe"):
			abilities.spawn_v6_orb_elem_aoe(player, pos, elem, atk_mult, 100.0)


# ============= Phase 6: sr=25 trail_elem_field =============
# 4 张元素场域卡：沿 attack_path 取样生成场域格，每格 element + tick + slow/stun/ramp
const TRAIL_ELEM_MAP: Dictionary = {
	"trail_fire_wall":      "fire",
	"trail_thunder_field":  "thunder",
	"trail_poison_fog":     "poison",
	"trail_frost":          "ice",
}

static func on_trail_field_spawn(player: Node, abilities: Node, path: Array) -> void:
	if abilities == null or path.size() < 2:
		return
	for b in _iter_sr(player, 25):
		var card_id: String = str(b.id)
		var element: String = TRAIL_ELEM_MAP.get(card_id, "")
		if element == "":
			continue
		var atk_mult: float = _sv(b, 0, 0.5)
		var tick_interval: float = _sv(b, 1, 0.5)
		var slow_pct: float = _sv(b, 2, 0.0)
		var stun_sec: float = _sv(b, 3, 0.0)
		var ramp_pct: float = _sv(b, 4, 0.0)
		var bullet_attach: bool = _sv(b, 5, 0.0) >= 1.0
		var duration: float = 3.0 + float(maxi(0, b.level - 1)) * 0.5
		# 沿 path 取样生成格子
		var sample_pts: Array = _sample_path(path, 36.0)
		if abilities.has_method("spawn_v6_trail_field"):
			abilities.spawn_v6_trail_field(player, sample_pts, element, atk_mult, tick_interval, slow_pct, stun_sec, ramp_pct, duration, bullet_attach, card_id)


static func _sample_path(path: Array, spacing: float) -> Array:
	var out: Array = []
	if path.size() < 2:
		return out
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var bb: Vector2 = path[i + 1]
		var d: float = a.distance_to(bb)
		if d <= 0.001:
			continue
		var steps: int = maxi(1, int(d / spacing))
		for j in range(steps):
			var t: float = float(j) / float(steps)
			out.append(a.lerp(bb, t))
	out.append(path[path.size() - 1])
	return out


# sr=56 orbit_shield：每帧枚举敌方远程子弹，若距离盾中心 < BLOCK_RADIUS 则 queue_free + 命中粒子
const SHIELD_BLOCK_RADIUS := 22.0

static func _orbit_shield_tick(player: Node) -> void:
	var count: int = int(player.shield_orbit_count)
	if count <= 0:
		return
	var battle = player.get_tree().get_first_node_in_group("battle") if player.is_inside_tree() else null
	if battle == null:
		return
	# 敌方远程子弹一般在 group "enemy_projectiles" — 若没有，走 spawner 找 monster_projectiles
	var projectiles: Array = []
	if player.get_tree().has_group("enemy_projectiles"):
		projectiles = player.get_tree().get_nodes_in_group("enemy_projectiles")
	elif battle.has_node("Projectiles"):
		var pn = battle.get_node("Projectiles")
		for c in pn.get_children():
			if c.is_in_group("enemy_projectiles"):
				projectiles.append(c)
	if projectiles.is_empty():
		return
	# 计算所有盾的位置
	var base_ang: float = float(player.shield_orbit_angle)
	var r: float = float(player.shield_orbit_radius)
	var origin: Vector2 = player.global_position
	var shield_positions: Array = []
	for i in range(count):
		var a: float = base_ang + TAU * float(i) / float(count)
		shield_positions.append(origin + Vector2(cos(a), sin(a)) * r)
	# 检测子弹距任一盾 < BLOCK_RADIUS 则销毁
	for p in projectiles:
		if not is_instance_valid(p):
			continue
		var ppos: Vector2 = p.global_position
		for sp in shield_positions:
			if ppos.distance_to(sp) <= SHIELD_BLOCK_RADIUS:
				# 命中特效：如 battle 有 combat.spawn_impact_burst 用它，否则简易 particles
				if battle.combat and battle.combat.has_method("spawn_impact_burst"):
					battle.combat.spawn_impact_burst(sp, Color(0.75, 0.85, 1.0, 1.0))
				p.queue_free()
				break


# ============= 未实现 SR 列表（注释，无 handler）=============
# sr=1  on_hit_window           受击触发限时增伤    [duration via attr 41]
# sr=3  aura                    光环易伤+伤害       [radius, tick, atk_mult, vuln_per_lv]
# sr=5  trail_burn_walk         火焰行走            [atk_mult, tick, duration]
# sr=8  low_hp_regen            低血再生            [hp_threshold, regen_pct, regen_per_lv, target_hp_pct]
# sr=9  stand_guard             站立减伤            [duration via tv]
# sr=10 iframe_on_hit           受击无敌            [iframe_sec / cd via attr 40]
# sr=12 bullet_homing           追踪                [homing_flag]
# sr=13 bullet_proc_spell       普攻概率触发法术    [proc_base, proc_per_lv, atk_mult, radius]
# sr=16 bullet_mirror           镜像回弹            [return_atk_mult]
# sr=18 bullet_beam             能量光束            [proc_base, proc_per_lv, atk_mult, pierce]
# sr=20 combo_milestone_spell   连击里程碑法术(5 张) [shape, radius, extra_blade_per_lv]
# sr=21 combo_charge            蓄力击               [charge_per_04s_pct, charge_max_mult]
# sr=22 combo_shuriken          连击辅助子弹         [shape, random_dir]
# sr=24 trail_extra             多重轨迹            [extra_count]
# sr=25 trail_elem_field        元素轨迹场域(4 张)  [atk_mult, tick, slow_pct, stun, ramp, bullet_attach]
# sr=26 trail_endwave           划线末端推开        [radius_base, radius_per_lv]
# sr=27 trail_loop_explode      闭合爆炸            [weapon_mult_per_lv, min_area]
# sr=28 trail_pierce            穿障碍              [pierce_obstacles]
# sr=29 trail_width_buff        轨迹宽度            [width_pct_per_lv]
# sr=30 trail_dmg_buff          轨迹伤害            [dmg_pct_per_lv]
# sr=31 orb_spawn               球生成间隔          [interval_base, interval_per_lv]
# sr=32 orb_mark                球印记复制          [dup_chance_base, dup_chance_per_lv]
# sr=33 orb_field               场上球数量          [count_pct_per_lv]
# sr=34 orb_magnet              球磁吸              [pickup_radius_pct, line_magnet_pct]
# sr=35 orb_burst               拾取爆炸            [weapon_mult]
# sr=36 orb_glow                球之微光            [dmg_pct_per_lv]
# sr=37 orb_elem_aoe            元素球 AOE(4 张)    [weapon_mult, element]
# sr=38 sword_count_mult        剑数翻倍            [count_mult]
# sr=39 sword_proc_spell        剑触发法术          [proc, atk_mult, radius_per_lv]
# sr=40 sword_unit              剑单位(6 张)         [atk_mult, hit_interval, element, p1-p3]
# sr=41 sword_length_buff       剑长度              [length_pct_per_lv]
# sr=42 sword_speed_buff        剑转速              [speed_pct_per_lv]
# sr=43 sword_dmg_buff          剑伤害              [dmg_pct_per_lv]
# sr=44 summon_pact             召唤盟约            [size_pct, atk_speed_pct]
# sr=45 summon_unit             召唤单位(7 张)       [atk_mult, interval, range, element, mechanic, p1-p2]
# 注：elem_*_bullet 4 张（火/雷/毒/冰）走 sr=0，不需 dispatcher 实现；
#     机制由 applies_<elem> 布尔 → ElementEffectManager.try_apply 自动触发（ability_manager.gd:1235）。
