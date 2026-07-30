extends Node
# 回归：5 种新怪（SNAKE_SHOOTER / JUMPER / LASER / MINI_CENTIPEDE / DASHER）
# 以场景方式运行（autoload 可用，monster.gd 能编译）。
# 验证：配置可加载、setup 不崩、update_ai 多帧推进状态机不崩、_draw 不崩、
#       snake/radial 投射物 spawn+update 不崩、smash 地面效果 spawn+update 不崩。
# 运行：godot --headless res://tools/test_new_monsters.tscn
# 期望：打印 "NEW_MONSTERS_OK"。

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
func is_in_bounds(p): return p.x >= -50 and p.y >= -50 and p.x <= 770 and p.y <= 1330
func shake_camera(_a, _b): pass
func is_bullet_blocked_at(_p): return false
func spawn_arrow(_f, _t, _d, _s, _e, _c): pass
"""

const COMBAT_SRC := """
extends Node
func should_monsters_attack(_p): return true
func schedule_death_fade(): return 0.0
func spawn_damage_number(_pos, _d, _a, _b, _c): pass
"""

func _make_script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func _ready() -> void:
	var ok := true
	var report := []
	var kinds := ["SNAKE_SHOOTER", "JUMPER", "LASER", "MINI_CENTIPEDE", "DASHER", "TELEPORTER"]

	# 1) 配置加载
	for k in kinds:
		var cfg := GameConfig.get_monster(k)
		if cfg.is_empty():
			report.append("FAIL: 缺 kind_id=%s" % k); ok = false
		else:
			report.append("ok: config %s hp=%s pattern=%s" % [k, cfg.get("hp"), cfg.get("attack_pattern")])

	# 2) battle 替身
	var battle = Node2D.new()
	battle.name = "Battle"
	battle.add_to_group("battle")
	battle.set_script(_make_script(BATTLE_SRC))
	battle.state = GameState.PLAYING
	add_child(battle)

	var mc := Node2D.new(); mc.name = "Monsters"; battle.add_child(mc)
	battle.monster_container = mc
	var proj := Node2D.new(); proj.name = "Projectiles"; battle.add_child(proj)
	battle.projectiles = proj

	var GroundEffectMgr := load("res://scripts/core/ground_effect_manager.gd")
	var ge = GroundEffectMgr.new(); ge.name = "GroundEffects"; battle.add_child(ge); ge.setup(battle)
	battle.ground_effects = ge

	var Particles := load("res://scripts/core/particle_manager.gd")
	var pm = Particles.new(); pm.name = "Particles"; battle.add_child(pm)
	battle.particles = pm

	var combat = Node.new(); combat.set_script(_make_script(COMBAT_SRC)); battle.add_child(combat)
	battle.combat = combat

	var Spawner := load("res://scripts/core/monster_spawner.gd")
	var spawner = Spawner.new(); battle.add_child(spawner)
	battle.spawner = spawner

	# player：真实 BattlePlayer（满足 update_ai 的类型签名），不加进树避免 _ready 副作用。
	# 放在远离怪/弹道的位置，确保 take_damage 永不被调用。
	var player = BattlePlayer.new()
	player.global_position = Vector2(2000, 2000)
	battle.player = player

	# 3) 实例化每种怪，跑多帧 update_ai + update_death + _draw
	var scene := load(MONSTER_SCENE) as PackedScene
	for k in kinds:
		var m = scene.instantiate()
		mc.add_child(m)
		m.setup(k, 5, Vector2(120, 300), "")
		m.begin_spawn(0.01)
		report.append("ok: setup %s alive=%s hp=%s/%s code_drawn=%s" % [k, m.alive, m.hp, m.max_hp, m.get("_code_drawn")])
		for _i in range(5):
			m.update_ai(0.05, player, battle)
		# 玩家在远处，jumper 不进触发范围、laser 锁定远方方向射偏、子弹打不到
		for _i in range(160):
			m.update_ai(0.05, player, battle)
			m.update_death(0.05)
			m._draw()
		m.begin_dying(0.0)
		for _i in range(20):
			m.update_death(0.05)
		m.queue_free()
	report.append("ok: 6 怪 update_ai/update_death/_draw 跑完无崩溃")

	# 4) smash 地面效果（玩家在远处，不中弹）
	ge.spawn_smash(Vector2(200, 300), 30, 70.0, 2.0)
	for _i in range(80):
		ge.update_effects(0.05, player)
	report.append("ok: smash ground effect warning→active→fade")

	# 5) snake / radial 投射物
	EnemyArrow.spawn_snake(battle, Vector2(100, 100), Vector2(300, 300), 10, 80.0, "enemy_snake_bullet", Color("#4fd6a0"))
	EnemyArrow.spawn_radial(battle, Vector2(200, 200), 10, 80.0, 8, "enemy_cross_magic")
	EnemyArrow.spawn(battle, Vector2(100, 100), Vector2(300, 300), 10, 140.0, "enemy_teleport_bolt", Color("#6a3a98"))
	for _i in range(30):
		for c in proj.get_children():
			if c is EnemyArrow and is_instance_valid(c):
				c.update_arrow(0.05)
				c._draw()
	report.append("ok: snake+radial 投射物 spawn+update+_draw 完成，存活=%d" % proj.get_children().size())

	for line in report:
		print(line)
	print("NEW_MONSTERS_OK" if ok else "NEW_MONSTERS_FAIL")
	get_tree().quit(0 if ok else 1)
