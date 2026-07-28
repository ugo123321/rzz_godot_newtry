extends Node
# 回归：迷你千足虫冲锋重构（12 节等大方块 + 共享血量 + 全身可击）
# 运行：godot --headless res://tools/test_mini_centipede.tscn
# 期望：打印 "MINI_CENTIPEDE_OK"

const MONSTER_SCENE := "res://scenes/entities/monster.tscn"

const BATTLE_SRC := """
extends Node2D
var player
var projectiles
var ground_effects
var particles
var combat
var spawner
var monster_container
var state := 0
func is_in_bounds(p): return p.x >= -200 and p.y >= -200 and p.x <= 920 and p.y <= 1480
func shake_camera(_a, _b): pass
func is_bullet_blocked_at(_p): return false
func get_stage_theme(_i): return ""
"""

const COMBAT_SRC := """
extends Node
func should_monsters_attack(_p): return true
func schedule_death_fade(): return 0.0
func spawn_damage_number(_pos, _d, _a, _b, _c): pass
"""

# 子类 BattlePlayer 记录受击（绕过 iframe/心数制，便于确定性测试）
const PLAYER_SRC := """
extends BattlePlayer
var dmg_taken := 0.0
func take_damage(_amount):
	dmg_taken += 1.0
	return 1.0
"""

var _ok := true
var _report: Array = []

func _make_script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func _fail(msg: String) -> void:
	_ok = false
	_report.append("FAIL: " + msg)

func _ready() -> void:
	# 1) 配置加载
	var cfg := GameConfig.get_monster("MINI_CENTIPEDE")
	if cfg.is_empty():
		_fail("缺 MINI_CENTIPEDE 配置")
	else:
		if int(cfg.get("segment_count", -1)) != 12: _fail("segment_count!=12 got=%s" % cfg.get("segment_count"))
		if int(cfg.get("charge_speed", -1)) != 260: _fail("charge_speed!=260 got=%s" % cfg.get("charge_speed"))
		if int(cfg.get("ranged", -1)) != 0: _fail("ranged!=0 got=%s" % cfg.get("ranged"))
		if str(cfg.get("attack_pattern", "x")) != "": _fail("attack_pattern 非空 got=%s" % cfg.get("attack_pattern"))
		_report.append("ok: config segment_count=%s charge_speed=%s ranged=%s" % [cfg.get("segment_count"), cfg.get("charge_speed"), cfg.get("ranged")])

	# 2) battle 替身 + spawner
	var battle = Node2D.new()
	battle.name = "Battle"
	battle.add_to_group("battle")
	battle.set_script(_make_script(BATTLE_SRC))
	battle.state = GameState.PLAYING
	add_child(battle)
	var mc := Node2D.new(); mc.name = "Monsters"; battle.add_child(mc)
	battle.monster_container = mc
	var combat = Node.new()
	combat.set_script(_make_script(COMBAT_SRC))
	battle.add_child(combat)
	battle.combat = combat
	var Spawner := load("res://scripts/core/monster_spawner.gd")
	var spawner = Spawner.new(); battle.add_child(spawner)
	battle.spawner = spawner

	# player：子类记录受击，放在场内会被冲锋撞到
	var player_script := _make_script(PLAYER_SRC)
	var player = player_script.new()
	player.global_position = Vector2(360, 640)
	battle.player = player

	# 3) 手动建一只虫（避免依赖 _pick_spawn_pos 的 spawn_clusters 初始化）
	var scene := load(MONSTER_SCENE) as PackedScene
	var worm = scene.instantiate()
	mc.add_child(worm)
	worm.setup("MINI_CENTIPEDE", 5, Vector2(360, 300), "")
	worm.begin_spawn()
	spawner.monsters.append(worm)
	worm._init_centipede_segments(spawner, battle)

	# 节段断言
	if worm._centi_segments.size() != 12:
		_fail("节段数!=12 got=%d" % worm._centi_segments.size())
	var seg_count := 0
	for n in spawner.monsters:
		if n is MiniCentipedeSegment:
			seg_count += 1
	if seg_count != 12:
		_fail("spawner.monsters 里节段数!=12 got=%d" % seg_count)
	else:
		_report.append("ok: 12 节段已创建并注册")
	# 节段 hitbox + targetable 委托
	var s0 = worm._centi_segments[0]
	if absf(s0.get_hitbox_radius() - worm._centi_segment_hitbox) > 0.01:
		_fail("节段 hitbox 半径 != %f" % worm._centi_segment_hitbox)
	# 未进 CHARGING 前不应 targetable
	if s0.is_combat_targetable():
		_fail("REPOSITION 期间节段不应可击")
	worm._centi_phase = BattleMonster.Phase.CHARGING
	if not s0.is_combat_targetable():
		_fail("CHARGING 期间节段应可击")
	if worm.is_combat_targetable():
		_fail("虫头部不应可击（应只有节段可击）")
	worm._centi_phase = BattleMonster.Phase.REPOSITION

	# 4) 状态机：REPOSITION→CHARGING→飞出→REPOSITION
	worm._centi_repos_timer = 0.0  # 立刻进入 CHARGING
	var reached_charging := false
	var reached_reposition_again := false
	var seg_line_ok := true
	for _i in range(600):
		worm.update_ai(0.05, player, battle)
		worm.update_death(0.05)
		worm._draw()
		if worm._centi_phase == BattleMonster.Phase.CHARGING:
			reached_charging = true
			# 节段应在头部后方排成直线
			var head: Vector2 = worm.global_position
			var dir: Vector2 = worm._charge_dir
			for k in range(worm._centi_segments.size()):
				var expect: Vector2 = head - dir * (float(k) * worm._centi_segment_spacing)
				if worm._centi_segments[k].global_position.distance_to(expect) > 1.0:
					seg_line_ok = false
					break
		if reached_charging and worm._centi_phase == BattleMonster.Phase.REPOSITION:
			reached_reposition_again = true
			break
	if not reached_charging:
		_fail("未进入 CHARGING")
	if not reached_reposition_again:
		_fail("未飞出屏外回到 REPOSITION")
	if not seg_line_ok:
		_fail("节段未在头部后方排成直线")
	if not (reached_charging and reached_reposition_again and seg_line_ok):
		_fail("状态机断言失败")
	else:
		_report.append("ok: REPOSITION↔CHARGING 状态机 + 节段排直线")

	# 5) 撞击：冲锋应撞到玩家一次（player 在场内 360,640，子类记录 dmg_taken）
	var dmg_before := float(player.get("dmg_taken"))
	worm._centi_repos_timer = 0.0
	for _i in range(800):
		worm.update_ai(0.05, player, battle)
		worm.update_death(0.05)
		if float(player.get("dmg_taken")) > dmg_before:
			break
	if float(player.get("dmg_taken")) <= dmg_before:
		_fail("冲锋未撞到玩家")
	elif not worm._has_hit_this_pass:
		_fail("_has_hit_this_pass 未置位")
	else:
		_report.append("ok: 撞击一次 dmg_taken=%d" % int(player.get("dmg_taken")))

	# 6) 节段命中 → 共享血量；杀死 → 虫 emit monster_killed 恰好一次
	var scene2 := load(MONSTER_SCENE) as PackedScene
	var worm2 = scene2.instantiate()
	mc.add_child(worm2)
	worm2.setup("MINI_CENTIPEDE", 5, Vector2(360, 300), "")
	worm2.begin_spawn()
	spawner.monsters.append(worm2)
	worm2._init_centipede_segments(spawner, battle)
	worm2._centi_phase = BattleMonster.Phase.CHARGING  # 让节段可击
	var hp_before: int = int(worm2.hp)
	var seg6 = worm2._centi_segments[6]
	var hit_res: Dictionary = seg6.take_damage(50, worm2.global_position)
	if int(hit_res.get("damage", 0)) <= 0:
		_fail("节段命中未造成伤害")
	if worm2.hp >= hp_before:
		_fail("节段命中未扣虫血 hp_before=%d hp_after=%d" % [hp_before, worm2.hp])
	else:
		_report.append("ok: 节段命中扣共享血 %d→%d (dmg=%d)" % [hp_before, worm2.hp, int(hit_res.get("damage", 0))])
	# 杀死：监听 monster_killed，断言只 emit 虫一次
	# 注：GDScript 4.x lambda 对 int 局部变量是值快照，不能跨 lambda 累加；
	# 用 Array 容器（按引用捕获）绕过这个限制。
	var kill_box := {"count": 0, "who": null}
	var _on_kill := func(monster):
		kill_box["count"] += 1
		kill_box["who"] = monster
	EventBus.monster_killed.connect(_on_kill)
	var seg0 = worm2._centi_segments[0]
	seg0.take_damage(99999, worm2.global_position)
	if not worm2.dying:
		_fail("节段命中杀死后虫未 dying")
	if int(kill_box["count"]) != 1:
		_fail("杀死时 monster_killed emit 次数!=1 got=%d" % int(kill_box["count"]))
	elif kill_box["who"] != worm2:
		_fail("monster_killed emit 的不是虫")
	else:
		_report.append("ok: 节段击杀 emit 虫一次 kill_count=1")
	# 跑完死亡动画，确认节段被清理
	for _i in range(40):
		worm2.update_death(0.05)
	# 注：spawner.monsters 里还有第一只虫（worm）的 12 个节段——它没死；
	# 这里只断言 worm2 自己的节段已全部从 spawner 注销 + free。
	var seg_left := 0
	for n in spawner.monsters:
		if not is_instance_valid(n):
			continue
		if n is MiniCentipedeSegment and n.worm == worm2:
			seg_left += 1
	if not worm2._centi_segments.is_empty():
		_fail("worm2._centi_segments 未清空 size=%d" % worm2._centi_segments.size())
	elif seg_left != 0:
		_fail("虫死后节段未清理剩=%d" % seg_left)
	else:
		_report.append("ok: 虫死后节段全部清理")
	EventBus.monster_killed.disconnect(_on_kill)

	for line in _report:
		print(line)
	print("MINI_CENTIPEDE_OK" if _ok else "MINI_CENTIPEDE_FAIL")
	get_tree().quit(0 if _ok else 1)
