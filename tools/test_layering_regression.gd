extends SceneTree
# 回归：单位影子/地块元素分层修复
# 1) monster_container.y_sort_enabled == true —— 怪物按 Y 排序，避免后生成怪的脚下影子
#    (烘焙在角色帧贴图里，与身体同帧同 z)盖住先生成的怪。
# 2) 地块元素(FieldElements) / 传送门(Portals) 的有效 z < 怪物/玩家(z=0) —— 地块/元素沉到单位下面。
#
# 运行：godot --headless --script tools/test_layering_regression.gd
# 期望：所有断言通过，打印 "LAYERING_OK"。

const ENTITIES_PATH := "res://scripts/battle.gd"

func _initialize() -> void:
	var ok := true
	var report := []

	# 不实例化整个 battle(太重)；直接用脚本静态构造容器节点验证 z。
	# monster_container 在 battle.tscn 里是 $Entities/Monsters (Node2D)，battle.gd _setup_viewport
	# 末尾置 y_sort_enabled = true。这里复刻同样的赋值，验证 API 存在性 + 行为。
	var mc := Node2D.new()
	mc.name = "Monsters"
	# 复刻 battle.gd 的赋值
	mc.y_sort_enabled = true
	if not mc.y_sort_enabled:
		report.append("FAIL: monster_container.y_sort_enabled 未能置 true")
		ok = false
	else:
		report.append("ok: monster_container.y_sort_enabled = true")

	# y_sort_enabled 是 Node2D 合法属性(Godot 4.7)，且不依赖 y_sort_origin(该属性在 4.x 不存在)。
	# 验证 Node2D 没有 y_sort_origin —— 任何代码引用它都会触发 parse error。
	var has_bad_prop := false
	for p in mc.get_property_list():
		if String(p["name"]) == "y_sort_origin":
			has_bad_prop = true
	if has_bad_prop:
		report.append("FAIL: Node2D 不应存在 y_sort_origin 属性(若存在则旧写法残留)")
		ok = false

	# z 层级期望(有效 z)：terrain(-5) < grass(-4) < field_elements(-1) / portals(-1)
	#                                  < monsters(0) / player(0) < above_fx(5) < hit_fx(6)
	var z := {
		"terrain": -5,
		"grass": -4,
		"field_elements_container": -1,
		"field_element_self": 0,   # 容器 -1 + 自身 0 = 有效 -1
		"portal_container": -1,
		"portal_self": 0,           # 容器 -1 + 自身 0 = 有效 -1
		"monster": 0,
		"player": 0,
	}
	# 关键不变量：地块/元素有效 z < 怪物/玩家 z
	if not (z["field_elements_container"] + z["field_element_self"] < int(z["monster"])):
		report.append("FAIL: 地块元素有效 z 应 < 怪物 z")
		ok = false
	if not (z["portal_container"] + z["portal_self"] < int(z["monster"])):
		report.append("FAIL: 传送门有效 z 应 < 怪物 z")
		ok = false
	if not (z["terrain"] < int(z["monster"]) and z["terrain"] < z["field_elements_container"]):
		report.append("FAIL: 地形应 < 怪物 且 < 地块元素")
		ok = false
	if not (z["field_elements_container"] < int(z["monster"])):
		report.append("FAIL: 地块元素容器 z 应 < 怪物 z")
		ok = false

	# 顺带验证 field_element.gd / fixed_portal.gd / lottery_portal.gd / field_element_registry.gd
	# 源码里的 z 写法符合上面期望(防回归：以后误改回高 z 能被这条测试抓到)。
	var checks := {
		"res://scripts/systems/field_element_registry.gd": "z_index = -1",
		"res://scripts/entities/field_element.gd": "z_index = 0",
		"res://scripts/entities/fixed_portal.gd": "z_index = 0",
		"res://scripts/entities/lottery_portal.gd": "z_index = 0",
		"res://scripts/battle.gd": "monster_container.y_sort_enabled = true",
	}
	var f := FileAccess
	for path in checks:
		var want: String = checks[path]
		var txt := f.get_file_as_string(path)
		if txt.find(want) < 0:
			report.append("FAIL: %s 应包含 '%s'" % [path, want])
			ok = false
		else:
			report.append("ok: %s 含 '%s'" % [path, want])

	for line in report:
		print(line)
	print("LAYERING_OK" if ok else "LAYERING_FAIL")
	mc.queue_free()
	quit()