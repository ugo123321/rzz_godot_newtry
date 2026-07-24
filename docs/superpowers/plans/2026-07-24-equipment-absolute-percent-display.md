# 装备绝对值 + 百分比显示 + 每级成长 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把装备表（equipments.xlsx）的绝对值属性加成，在 UI 换算为基础值的百分比显示（整数、向上取整），白阶含升级成长；新增 G 列每级效果数据驱动战斗数值；新增 4 种绝对值属性接进 player.gd 实战。

**Architecture:** 三层数据流：xlsx →（export 脚本）→ equipments.json →（lobby_state）→ player.gd 实战 + equipment_panel 显示。显示百分比在 lobby_state `get_item_skill_entries` 运行时算（读 GameConfig base），不烤进 json。

**Tech Stack:** Python（openpyxl，导出脚本）/ Godot 4 GDScript / i18n JSON。

**前置说明（无测试框架）：** 本项目是 Godot 游戏，无 pytest。验证方式：跑导出脚本 + 读回 json 校验 + 进游戏核对显示与实战。每个脚本性任务以「跑脚本 → 校验输出 → commit」为节奏，代替 TDD 的红绿循环。

**玩家基础值（换算基准，`config/json/player.json`）：** attack=52, max_hp=3.0, max_ki=234, crit_rate=0.08, crit_damage=1.6, move_speed=60, ki_regen=60, invincible_time=0.45, ki_per_pixel=0.18。

**百分比公式：** `pct = ceil(abs_value / base × 100)`，带符号（负值用标准 ceil，如 ceil(-5.56)=-5）。GDScript：`ceilf(abs_value / base * 100.0)` 返回 float，转 int。

---

## 文件结构

- **修改** `tools/export_equipments_json.py` — 重写解析 A–G 列，新 key，per_level_bonuses。
- **修改** `config/json/equipments.json` — 由导出脚本重生（不手编）。
- **修改** `scripts/autoload/lobby_state.gd` — stat_bonus 累加新 key + G 列每级；skill_entries 算 pct 文本；battle_modifiers 透传；preview 默认值对齐。
- **修改** `scripts/entities/player.gd` — crit_damage 绝对加、max_ki/ki_regen/invincible_time/ki_per_pixel 接进实战。
- **修改** `scripts/ui/equipment_panel.gd` — 显示走 get_item_skill_entries 的 pct 文本（基本不变，核对）。
- **修改** `config/i18n/ui_zh_CN.json` + `config/i18n/ui_en.json` — 9 个 stat 名 key。

---

## Task 1: 新增 i18n stat 显示名 key

**Files:**
- Modify: `config/i18n/ui_zh_CN.json`
- Modify: `config/i18n/ui_en.json`

- [ ] **Step 1: 在 zh_CN.json 的 `UI_EQUIP_DETAIL_QUALITY_HEADER` 行后插入 9 个 stat 名 key**

在 `config/i18n/ui_zh_CN.json` 找到 `"UI_EQUIP_DETAIL_QUALITY_HEADER": "品质奖励属性",` 行，在其后加：

```json
	"UI_EQUIP_STAT_ATTACK": "攻击力",
	"UI_EQUIP_STAT_MAX_HP": "生命",
	"UI_EQUIP_STAT_CRIT_RATE": "暴击率",
	"UI_EQUIP_STAT_CRIT_DAMAGE": "暴击伤害倍率",
	"UI_EQUIP_STAT_MOVE_SPEED": "移动速度",
	"UI_EQUIP_STAT_MAX_KI": "气力上限",
	"UI_EQUIP_STAT_KI_REGEN": "气力回复速度",
	"UI_EQUIP_STAT_INVINCIBLE_TIME": "受击无敌时间",
	"UI_EQUIP_STAT_KI_PER_PIXEL": "划线气力消耗",
```

- [ ] **Step 2: 在 en.json 同位置插入 9 个英文 key**

在 `config/i18n/ui_en.json` 找到 `"UI_EQUIP_DETAIL_QUALITY_HEADER": "Quality Bonus Attributes",` 行，在其后加：

```json
	"UI_EQUIP_STAT_ATTACK": "Attack",
	"UI_EQUIP_STAT_MAX_HP": "HP",
	"UI_EQUIP_STAT_CRIT_RATE": "Crit Rate",
	"UI_EQUIP_STAT_CRIT_DAMAGE": "Crit Damage",
	"UI_EQUIP_STAT_MOVE_SPEED": "Move Speed",
	"UI_EQUIP_STAT_MAX_KI": "Max Ki",
	"UI_EQUIP_STAT_KI_REGEN": "Ki Regen",
	"UI_EQUIP_STAT_INVINCIBLE_TIME": "Invincible Time",
	"UI_EQUIP_STAT_KI_PER_PIXEL": "Draw Ki Cost",
```

- [ ] **Step 3: 校验 JSON 合法**

Run: `python -c "import json; json.load(open('config/i18n/ui_zh_CN.json',encoding='utf-8')); json.load(open('config/i18n/ui_en.json',encoding='utf-8')); print('OK')"`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add config/i18n/ui_zh_CN.json config/i18n/ui_en.json
git commit -m "feat(i18n): 新增装备 stat 显示名 key（9 个，中英双语）"
```

---

## Task 2: 重写 export_equipments_json.py 解析（A–G 列 + 新 key + per_level_bonuses）

**Files:**
- Modify: `tools/export_equipments_json.py`

- [ ] **Step 1: 重写 `EFFECT_PATTERNS` 为新文案（去「基础值」后缀，绝对值）**

把 `tools/export_equipments_json.py:60-100` 的 `EFFECT_PATTERNS` 整段替换为：

```python
# stat_key → 该 stat 是否「倍率型」（百分比加成，旧 pct 语义）。
# v6 改版后全部走绝对值；crit_damage 也改为绝对加（不再 pct 乘）。
# 这里 EFFECT_PATTERNS 只负责把中文文案解析成 (stat_bonuses, flag, effect_desc_en)。
# 数值型 tier 不再需要 effect_desc_en（运行时算百分比），只 flag 保留 desc。
EFFECT_PATTERNS = [
    # 攻击力 +N
    (re.compile(r"^攻击力\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"attack": float(m.group(1))}, None, "")),
    # 生命 +N（浮点心数，如 0.5）
    (re.compile(r"^生命\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"max_hp": float(m.group(1))}, None, "")),
    # 暴击率 +N（0–1 浮点，如 0.05）
    (re.compile(r"^暴击率\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"crit_rate": float(m.group(1))}, None, "")),
    # 暴击伤害倍率基础值 +N（绝对加成，如 0.3 / 1）
    (re.compile(r"^暴击伤害倍率基础值\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"crit_damage": float(m.group(1))}, None, "")),
    # 移动速度 +N
    (re.compile(r"^移动速度\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"move_speed": float(m.group(1))}, None, "")),
    # 气力上限 +N（绝对，新 key；旧是 max_ki_pct）
    (re.compile(r"^气力上限\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"max_ki": float(m.group(1))}, None, "")),
    # 气力回复速度 +N（绝对，新 key；旧是 ki_regen_pct）
    (re.compile(r"^气力回复速度\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"ki_regen": float(m.group(1))}, None, "")),
    # 受击无敌时间 +N（全新）
    (re.compile(r"^受击无敌时间\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"invincible_time": float(m.group(1))}, None, "")),
    # 划线气力消耗 +N（可为负；负=降消耗）
    (re.compile(r"^划线气力消耗\+(-?\d+(?:\.\d+)?)$"),
     lambda m: ({"ki_per_pixel": float(m.group(1))}, None, "")),
    # 4 个 flag（纯机制，保留 desc）
    (re.compile(r"^子弹获得追踪效果$"),
     lambda m: ({}, "bullet_homing", "Bullets seek nearby enemies")),
    (re.compile(r"^持续电击靠近的敌人$"),
     lambda m: ({}, "shock_aura", "Continuously shocks nearby enemies")),
    (re.compile(r"^每关随机刷出的树木数量翻倍$"),
     lambda m: ({}, "tree_x2", "Trees spawned per stage x2")),
    (re.compile(r"^受击时(\d+)%概率免伤$"),
     lambda m: ({}, "hit_dodge_5pct",
                f"{m.group(1)}% chance to negate incoming hits")),
]
```

- [ ] **Step 2: 改 `parse_effect` 容错：flag 有 desc、数值型 desc 留空**

把 `tools/export_equipments_json.py:103-110` 的 `parse_effect` 函数替换为：

```python
def parse_effect(text: str) -> tuple[dict, str | None, str]:
    """(stat_bonuses, flag, effect_desc_en) —— 数值型 desc 留空（运行时算百分比）；
    flag 型保留英文 desc。找不到匹配就报错，避免静默失败。"""
    text = (text or "").strip()
    for pat, builder in EFFECT_PATTERNS:
        m = pat.match(text)
        if m:
            return builder(m)
    raise ValueError(f"Unknown effect text: {text!r}")
```

- [ ] **Step 3: 改 `convert()` 读 G 列 + 存 per_level_bonuses + 数值型 desc 留空**

把 `tools/export_equipments_json.py:117-185` 的 `convert()` 函数替换为：

```python
def convert():
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    if "Sheet1" not in wb.sheetnames:
        raise RuntimeError(f"Sheet1 missing in {SRC_XLSX}")
    ws = wb["Sheet1"]
    rows = list(ws.iter_rows(values_only=True))[1:]  # skip header row

    equipments: dict[str, dict] = {}  # def_id -> record
    order: list[str] = []             # keep insertion order for stable output
    per_level_seen: dict[str, dict] = {}  # def_id -> per_level_bonuses（校验 4 行一致）

    for r in rows:
        if not r or r[0] is None:
            continue
        name_cn = str(r[0]).strip()
        if name_cn not in NAME_TO_META:
            raise ValueError(f"Unknown equipment name: {name_cn!r}")
        def_id, name_en = NAME_TO_META[name_cn]
        is_rare = int(r[1] or 0)
        slot_cn = str(r[2] or "").strip()
        slot_key = SLOT_CN_TO_KEY.get(slot_cn)
        if slot_key is None:
            raise ValueError(f"Unknown slot: {slot_cn!r}")
        icon_key = str(r[3] or "").strip()
        if not icon_key:
            raise ValueError(f"{def_id}: missing icon slug in column D")
        quality_cn = str(r[4] or "").strip()
        if quality_cn not in QUALITY_CN_TO_CODE:
            raise ValueError(f"Unknown quality: {quality_cn!r}")
        quality = QUALITY_CN_TO_CODE[quality_cn]
        effect_cn = str(r[5] or "").strip()
        stat_bonuses, flag, effect_en = parse_effect(effect_cn)
        # G 列：升级每级实际效果（每装备一份，4 行相同）
        per_level_cn = str(r[6] or "").strip()
        per_level_bonuses, _pl_flag, _pl_en = parse_effect(per_level_cn)
        if _pl_flag is not None:
            raise ValueError(f"{def_id}: per-level effect must be a stat, got flag: {per_level_cn!r}")

        if def_id not in equipments:
            equipments[def_id] = {
                "def_id": def_id,
                "name_cn": name_cn,
                "name_en": name_en,
                "slot": slot_key,
                "icon_path": icon_path_for(icon_key),
                "is_rare": is_rare,
                "tiers": [None, None, None, None],
                "per_level_bonuses": {},
            }
            order.append(def_id)
            per_level_seen[def_id] = per_level_bonuses
        else:
            # 校验 4 行的 G 列一致
            if per_level_bonuses != per_level_seen[def_id]:
                raise ValueError(
                    f"{def_id}: per-level effect inconsistent across quality rows: "
                    f"{per_level_bonuses} vs {per_level_seen[def_id]}")
        rec = equipments[def_id]
        if rec["tiers"][quality] is not None:
            raise ValueError(
                f"Duplicate tier for {def_id} quality={quality}")
        tier_rec = {
            "quality": quality,
            "stat_bonuses": stat_bonuses,
            "flag": flag,
        }
        # 数值型 tier 不写 desc（运行时算百分比）；flag tier 保留 desc
        if flag is not None:
            tier_rec["effect_desc_cn"] = effect_cn
            tier_rec["effect_desc_en"] = effect_en
        rec["tiers"][quality] = tier_rec

    # Validate all 4 tiers present
    for def_id in order:
        rec = equipments[def_id]
        for q in range(4):
            if rec["tiers"][q] is None:
                raise ValueError(
                    f"{def_id} missing tier quality={q}")

    out = {"equipments": [equipments[d] for d in order]}
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"Wrote {OUT_JSON} ({len(out['equipments'])} equipments)")
    return out
```

- [ ] **Step 4: 更新脚本顶部 docstring 的 schema 说明**

把 `tools/export_equipments_json.py:2-20` 的模块 docstring 替换为：

```python
"""Convert config/excel/equipments.xlsx Sheet1 -> config/json/equipments.json

Schema (per equipment):
    {
      "def_id": "iron_dagger",
      "name_cn": "铁制短刀", "name_en": "Iron Dagger",
      "slot": "weapon",
      "icon_path": "res://assets/.../icon_equip_iron_dagger.png",
      "is_rare": 0,
      "per_level_bonuses": {"attack": 1},   # G 列：每次升级叠加的绝对值（每装备一份）
      "tiers": [
        {"quality": 0, "stat_bonuses": {...}, "flag": null},                 # 数值型无 desc
        {"quality": 1, "stat_bonuses": {...}, "flag": null},
        {"quality": 2, "stat_bonuses": {...}, "flag": null},
        {"quality": 3, "stat_bonuses": {}, "flag": "bullet_homing",
         "effect_desc_cn": "...", "effect_desc_en": "..."},                 # flag 保留 desc
      ]
    }

Columns A-G: 名称 / 是否稀有 / 部位 / icon / 品质 / 实际效果(F) / 升级每级实际效果(G).
数值型属性 stat_bonuses 用绝对值 key（attack/max_hp/crit_rate/crit_damage/move_speed/
max_ki/ki_regen/invincible_time/ki_per_pixel）。显示百分比由 lobby_state 运行时算。

Skip the "草稿，无视此sheet" sheet. Row-groups of 4 rows per equipment (name
repeats in column A). Runtime consumer: scripts/autoload/lobby_state.gd.
"""
```

- [ ] **Step 5: Commit（先不跑，下一 Task 跑）**

```bash
git add tools/export_equipments_json.py
git commit -m "feat(tools): 装备导出脚本解析 A-G 列 + per_level_bonuses + 绝对值 key"
```

---

## Task 3: 跑导出脚本，校验 json

**Files:**
- Regenerate: `config/json/equipments.json`

- [ ] **Step 1: 跑导出脚本**

Run: `python tools/export_equipments_json.py`
Expected: `Wrote D:\workspace\rzz_godot_newtry\config\json\equipments.json (8 equipments)`

- [ ] **Step 2: 校验 json 结构（per_level_bonuses + 新 key + 数值 tier 无 desc）**

Run:
```bash
python -c "
import json
d=json.load(open('config/json/equipments.json',encoding='utf-8'))
for e in d['equipments']:
    assert 'per_level_bonuses' in e, e['def_id']+' missing per_level'
    for t in e['tiers']:
        sb=t['stat_bonuses']
        for k in sb:
            assert k in ('attack','max_hp','crit_rate','crit_damage','move_speed','max_ki','ki_regen','invincible_time','ki_per_pixel'), (e['def_id'],k)
        if t['flag'] is None:
            assert 'effect_desc_cn' not in t, (e['def_id'],'numerical tier should have no desc')
        else:
            assert 'effect_desc_cn' in t, (e['def_id'],'flag tier should have desc')
print('OK', json.dumps(d['equipments'][0]['per_level_bonuses']), json.dumps(d['equipments'][0]['tiers'][0]['stat_bonuses']))
"
```
Expected: `OK {"attack": 1.0} {"attack": 5.0}`（铁制短刀）

- [ ] **Step 3: 抽检暴风大剑蓝阶 crit_damage = 0.3**

Run:
```bash
python -c "
import json
d=json.load(open('config/json/equipments.json',encoding='utf-8'))
sg=[e for e in d['equipments'] if e['def_id']=='storm_greatsword'][0]
print('blue tier:', json.dumps(sg['tiers'][1]['stat_bonuses'], ensure_ascii=False))
print('per_level:', json.dumps(sg['per_level_bonuses']))
"
```
Expected: `blue tier: {"crit_damage": 0.3}` / `per_level: {"attack": 1.0}`

- [ ] **Step 4: Commit json**

```bash
git add config/json/equipments.json
git commit -m "chore(data): 重生 equipments.json（绝对值 key + per_level_bonuses）"
```

---

## Task 4: lobby_state — get_item_stat_bonus 加新 key + G 列每级，删硬编码

**Files:**
- Modify: `scripts/autoload/lobby_state.gd:801-852`

- [ ] **Step 1: 读现状确认行号**

Run: `grep -n "func get_item_stat_bonus" scripts/autoload/lobby_state.gd`
确认函数体在 801–852（含硬编码每级 845–852）。

- [ ] **Step 2: 替换 `get_item_stat_bonus` 函数体**

把 `scripts/autoload/lobby_state.gd` 的 `get_item_stat_bonus` 函数（801 起）整体替换为：

```gdscript
func get_item_stat_bonus(item: Dictionary) -> Dictionary:
	# 累加 tier 0..quality 的 stat_bonuses（加法叠加，绝不连乘）。
	# v6 改版：stat_bonuses 用绝对值 key（max_ki/ki_regen/invincible_time/ki_per_pixel 为绝对加成；
	# crit_damage 也改为绝对加，不再 pct 乘）。
	# per_level_bonuses（G 列）× (level-1) 叠加在顶层，替换旧的硬编码每级加成。
	var bonus := {
		"attack": 0.0,
		"max_hp": 0.0,
		"crit_rate": 0.0,
		"crit_damage": 0.0,
		"move_speed": 0.0,
		"max_ki": 0.0,
		"ki_regen": 0.0,
		"invincible_time": 0.0,
		"ki_per_pixel": 0.0,
		"item_power": get_item_power(item),
	}
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		return bonus
	var quality := int(item.get("quality", QUALITY_COMMON))
	for tier in range(QUALITY_COMMON, quality + 1):
		if tier >= def["tiers"].size():
			break
		var tier_rec: Dictionary = def["tiers"][tier]
		var sb = tier_rec.get("stat_bonuses", {})
		if typeof(sb) != TYPE_DICTIONARY:
			continue
		for key in sb:
			var val := float(sb[key])
			match key:
				"attack":          bonus.attack += val
				"max_hp":          bonus.max_hp += val
				"crit_rate":       bonus.crit_rate += val
				"crit_damage":     bonus.crit_damage += val          # 绝对加（v6）
				"move_speed":      bonus.move_speed += val
				"max_ki":          bonus.max_ki += val               # 绝对（v6 新）
				"ki_regen":        bonus.ki_regen += val              # 绝对（v6 新）
				"invincible_time": bonus.invincible_time += val      # 绝对（v6 新）
				"ki_per_pixel":    bonus.ki_per_pixel += val         # 绝对，可为负（v6 新）
				# 旧 pct key 兼容（旧 json 残留 max_ki_pct/ki_regen_pct）—— 保留但当前 json 不产出
				"max_ki_pct":      pass
				"ki_regen_pct":    pass
				_:                 push_warning("equip stat_bonus unknown key: %s" % key)
	# G 列 per_level_bonuses × (level-1) —— 数据驱动每级成长，替换旧硬编码
	var level := int(item.get("level", 1))
	var plv := def.get("per_level_bonuses", {})
	if typeof(plv) == TYPE_DICTIONARY and level > 1:
		var lv_factor := float(level - 1)
		for key in plv:
			var val := float(plv[key]) * lv_factor
			match key:
				"attack":          bonus.attack += val
				"max_hp":          bonus.max_hp += val
				"crit_rate":       bonus.crit_rate += val
				"crit_damage":     bonus.crit_damage += val
				"move_speed":      bonus.move_speed += val
				"max_ki":          bonus.max_ki += val
				"ki_regen":        bonus.ki_regen += val
				"invincible_time": bonus.invincible_time += val
				"ki_per_pixel":    bonus.ki_per_pixel += val
				_:                 push_warning("equip per_level unknown key: %s" % key)
	return bonus
```

- [ ] **Step 3: 校验脚本语法（Godot headless 若可用，否则靠进游戏）**

如果没有 Godot CLI，跳过；进游戏时统一验证。若可：
Run: `godot --headless --check-only --script scripts/autoload/lobby_state.gd`（视环境）
Expected: 无语法错误。

- [ ] **Step 4: Commit**

```bash
git add scripts/autoload/lobby_state.gd
git commit -m "feat(equip): get_item_stat_bonus 支持 9 种绝对值 key + G 列每级成长"
```

---

## Task 5: lobby_state — get_battle_modifiers 透传新 key

**Files:**
- Modify: `scripts/autoload/lobby_state.gd:911-922`（get_battle_modifiers）

- [ ] **Step 1: 读现状**

Run: `grep -n "func get_battle_modifiers" scripts/autoload/lobby_state.gd`

- [ ] **Step 2: 替换 get_battle_modifiers，透传新 key**

把 `get_battle_modifiers` 函数替换为（保留原有 key，新增 4 个）：

```gdscript
func get_battle_modifiers() -> Dictionary:
	# 把装备 totals 透传给 player.gd（_load_base_stats / _rebuild_upgrades）。
	var totals := get_equipment_totals()
	return {
		"attack": float(totals.get("attack", 0.0)),
		"max_hp": float(totals.get("max_hp", 0.0)),
		"crit_rate": float(totals.get("crit_rate", 0.0)),
		"crit_damage": float(totals.get("crit_damage", 0.0)),       # 绝对加（v6）
		"move_speed": float(totals.get("move_speed", 0.0)),
		"max_ki": float(totals.get("max_ki", 0.0)),                 # 绝对（v6 新）
		"ki_regen": float(totals.get("ki_regen", 0.0)),             # 绝对（v6 新）
		"invincible_time": float(totals.get("invincible_time", 0.0)),   # 绝对（v6 新）
		"ki_per_pixel": float(totals.get("ki_per_pixel", 0.0)),     # 绝对，可为负（v6 新）
		# 旧 pct 路径保留（当前 json 不产出，forge/技能石 用 pct 走另一条线）
		"max_ki_pct": float(totals.get("max_ki_pct", 0.0)),
		"ki_regen_pct": float(totals.get("ki_regen_pct", 0.0)),
	}
```

- [ ] **Step 3: 确认 get_equipment_totals 也累加了新 key**

`get_equipment_totals`（883–908）调 `get_item_stat_bonus` 后把每个 key 加进 total。由于它用 `total[k] += bonus[k]` 模式，需确认新 key 在 total 初始化里有。读现状：

Run: `grep -n "func get_equipment_totals" scripts/autoload/lobby_state.gd` 然后读该函数。

若 total 初始化用的是 `get_item_stat_bonus({})` 返回的 dict 作为模板（含全部 9 key），则无需改。若是手列 key，则补 `max_ki/ki_regen/invincible_time/ki_per_pixel`。**实现时按实际写法改**：若 total 初始化为 `var total := get_item_stat_bonus({})`，跳过本步；否则在 total 初始化 dict 里补 4 个 key 初始化为 0.0，并在累加循环里覆盖它们。

- [ ] **Step 4: Commit**

```bash
git add scripts/autoload/lobby_state.gd
git commit -m "feat(equip): get_battle_modifiers 透传 max_ki/ki_regen/invincible_time/ki_per_pixel"
```

---

## Task 6: lobby_state — get_item_skill_entries 计算百分比显示文本

**Files:**
- Modify: `scripts/autoload/lobby_state.gd:777-798`（get_item_skill_entries + _skill_text_for_quality）

- [ ] **Step 1: 在 lobby_state 顶部加 base 值映射 + 显示助手**

先读 lobby_state 顶部已有 const 区，找一个合适插入点（`_skill_text_for_quality` 上方）。

把以下加在 `_skill_text_for_quality` 函数**上方**：

```gdscript
# 装备 stat_key → (GameConfig base key, i18n stat 名 key)。
# 用于把绝对值换算为基础值的百分比显示（运行时算，不烤进 json）。
const _EQUIP_STAT_META := {
	"attack":          ["base_attack",      "UI_EQUIP_STAT_ATTACK"],
	"max_hp":          ["base_hp",          "UI_EQUIP_STAT_MAX_HP"],
	"crit_rate":       ["base_crit_rate",   "UI_EQUIP_STAT_CRIT_RATE"],
	"crit_damage":     ["base_crit_damage", "UI_EQUIP_STAT_CRIT_DAMAGE"],
	"move_speed":      ["move_speed",       "UI_EQUIP_STAT_MOVE_SPEED"],
	"max_ki":          ["base_ki",          "UI_EQUIP_STAT_MAX_KI"],
	"ki_regen":        ["ki_regen_speed",   "UI_EQUIP_STAT_KI_REGEN"],
	"invincible_time": ["invincible_time",  "UI_EQUIP_STAT_INVINCIBLE_TIME"],
	"ki_per_pixel":    ["ki_per_pixel",     "UI_EQUIP_STAT_KI_PER_PIXEL"],
}


# 把单个 stat 的绝对值换算为「stat 名 +N%」文本（整数、向上取整、带符号）。
func _equip_stat_display(stat_key: String, abs_value: float) -> String:
	var meta := _EQUIP_STAT_META.get(stat_key, null)
	if meta == null:
		return str(abs_value)
	var base_key: String = meta[0]
	var name_key: String = meta[1]
	var base := float(GameConfig.get_player_value(base_key, 1.0))
	if base == 0.0:
		base = 1.0
	var pct := int(ceilf(abs_value / base * 100.0))
	var sign := "+"
	if pct < 0:
		sign = ""
	return "%s %s%d%%" % [LanguageManager.tr_ui(name_key), sign, pct]
```

- [ ] **Step 2: 重写 `get_item_skill_entries` 用新显示文本**

把 `get_item_skill_entries`（777–787）替换为：

```gdscript
func get_item_skill_entries(item: Dictionary) -> Array[Dictionary]:
	# 每条 = 一个 quality tier 的显示条目。数值型 tier 文本由绝对值换算为百分比
	# （白阶含 per_level 成长）；flag tier 用原 desc。
	var result: Array[Dictionary] = []
	var def := get_item_def(str(item.get("def_id", "")))
	if def.is_empty():
		return result
	var quality := int(item.get("quality", QUALITY_COMMON))
	var level := int(item.get("level", 1))
	var plv := def.get("per_level_bonuses", {})
	for tier in range(QUALITY_COMMON, QUALITY_LEGENDARY + 1):
		if tier >= def["tiers"].size():
			break
		var tier_rec: Dictionary = def["tiers"][tier]
		var flag = tier_rec.get("flag", null)
		var text := ""
		if flag != null:
			text = LanguageManager.localize_field(tier_rec, "effect_desc_en", "effect_desc_cn")
		else:
			var sb = tier_rec.get("stat_bonuses", {})
			text = _equip_tier_display_text(sb, tier, level, plv)
		result.append({
			"quality": tier,
			"quality_name": get_quality_name(tier),
			"text": text,
			"unlocked": tier <= quality,
		})
	return result
```

- [ ] **Step 3: 加 `_equip_tier_display_text` 助手（白阶含 per_level）**

在 `_equip_stat_display` 下方加：

```gdscript
# 把一个 tier 的 stat_bonuses 拼成显示文本。白阶（tier 0）叠加 per_level×(level-1)。
# 一个 tier 一般只有一个 stat；若有多个，用换行拼（当前数据都是单 stat/tier）。
func _equip_tier_display_text(sb, tier: int, level: int, plv) -> String:
	if typeof(sb) != TYPE_DICTIONARY or sb.is_empty():
		return ""
	var lines: PackedStringArray = []
	for key in sb:
		var abs_value := float(sb[key])
		if tier == QUALITY_COMMON and typeof(plv) == TYPE_DICTIONARY and level > 1:
			abs_value += float(plv.get(key, 0.0)) * float(level - 1)
		lines.append(_equip_stat_display(key, abs_value))
	return "\n".join(lines)
```

- [ ] **Step 4: 删旧的 `_skill_text_for_quality`（已不再被调用）**

确认 `_skill_text_for_quality`（790–798）不再被引用：

Run: `grep -rn "_skill_text_for_quality" scripts/`
Expected: 只剩定义那一处（若还有调用方，需先把调用改到 get_item_skill_entries）。

删掉 `_skill_text_for_quality` 函数整段。

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/lobby_state.gd
git commit -m "feat(equip): get_item_skill_entries 绝对值→百分比显示（白阶含每级成长）"
```

---

## Task 7: player.gd — crit_damage 绝对加 + 接 max_ki/ki_regen/invincible_time/ki_per_pixel

**Files:**
- Modify: `scripts/entities/player.gd`（_load_base_stats 369-404, _rebuild_upgrades 1430-1463, take_damage 1099, consume_ki_by_distance 680, 字段声明区）

- [ ] **Step 1: 加玩家字段声明（equip add 缓存）**

在 `scripts/entities/player.gd` 找到 `equip_max_ki_pct` / `equip_ki_regen_pct` 等字段声明处（grep `equip_max_ki_pct`），在其附近加：

```gdscript
var equip_max_ki_add := 0.0           # 装备气力上限绝对加成（v6）
var equip_ki_regen_add := 0.0         # 装备气力回复绝对加成（v6）
var equip_invincible_time_add := 0.0  # 装备受击无敌时间绝对加成（v6）
var equip_ki_per_pixel_add := 0.0     # 装备划线气力消耗绝对加成（v6，可为负）
var equip_crit_damage_add := 0.0      # 装备暴击伤害绝对加成（v6，替代旧 pct 乘）
```

- [ ] **Step 2: 改 `_load_base_stats`（369-404）的 equip 应用段**

把 `_load_base_stats` 里 `if LobbyState:` 块内（约 381-394）替换为：

```gdscript
	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += float(equip.get("max_hp", 0.0))
		crit_rate += float(equip.get("crit_rate", 0.0))
		# v6：crit_damage 装备为绝对加成（替代旧 pct 乘）
		equip_crit_damage_add = float(equip.get("crit_damage", 0.0))
		crit_damage += equip_crit_damage_add
		# v6 新绝对值装备属性
		equip_max_ki_add = float(equip.get("max_ki", 0.0))
		equip_ki_regen_add = float(equip.get("ki_regen", 0.0))
		equip_invincible_time_add = float(equip.get("invincible_time", 0.0))
		equip_ki_per_pixel_add = float(equip.get("ki_per_pixel", 0.0))
		base_ki += equip_max_ki_add
		ki_regen_speed += equip_ki_regen_add
		# 缓存 pct / flat 供 _rebuild_upgrades 复用（rebuild 会重置 base 值，需重新 apply）
		equip_max_ki_pct = float(equip.get("max_ki_pct", 0.0))
		equip_ki_regen_pct = float(equip.get("ki_regen_pct", 0.0))
		equip_move_speed_add = float(equip.get("move_speed", 0.0))
		equip_crit_damage_pct = 0.0  # v6 后装备 crit_damage 走绝对加，pct 路径恒 0
```

注意：原 387-389 的 `crit_damage += crit_damage * eq_crit_dmg_pct` **删除**（已并入上面的绝对加）。

- [ ] **Step 3: 改 `_rebuild_upgrades`（1430-1463）的 equip 应用段**

把 `_rebuild_upgrades` 里 `if LobbyState:` 块（约 1430-1445）中 equip 部分替换为：

```gdscript
	if LobbyState:
		var equip := LobbyState.get_battle_modifiers()
		base_attack += float(equip.get("attack", 0.0))
		max_hp += float(equip.get("max_hp", 0.0))
		crit_rate += float(equip.get("crit_rate", 0.0))
		# v6：crit_damage 绝对加（替代旧 pct 乘）
		equip_crit_damage_add = float(equip.get("crit_damage", 0.0))
		crit_damage += equip_crit_damage_add
		# v6 新绝对值装备属性
		equip_max_ki_add = float(equip.get("max_ki", 0.0))
		equip_ki_regen_add = float(equip.get("ki_regen", 0.0))
		equip_invincible_time_add = float(equip.get("invincible_time", 0.0))
		equip_ki_per_pixel_add = float(equip.get("ki_per_pixel", 0.0))
		base_ki += equip_max_ki_add
		ki_regen_speed += equip_ki_regen_add
		# 装备 flag（tree_x2 由 battle.gd 直接读；这里只处理玩家自身 flag）
		var flags: Dictionary = LobbyState.get_active_equipment_flags()
		apply_equipment_flags(flags)
```

注意：原 1436-1438 的 `crit_damage += crit_damage * eq_crit_dmg_pct2` 与 1440-1442 的技能石 crit_damage pct 乘**保留技能石那段**（技能石仍 pct 乘），只删装备 pct 乘那段。即 1436-1438 删除，1440-1442（`ss_crit_dmg_pct`）保留。

- [ ] **Step 4: 把 invincible_time 装备加成 apply 到 take_damage**

`player.gd:1099` 当前：
```gdscript
	invincible_timer = float(GameConfig.get_player_value("invincible_time", 0.45))
```
改为：
```gdscript
	invincible_timer = float(GameConfig.get_player_value("invincible_time", 0.45)) + equip_invincible_time_add
```

- [ ] **Step 5: 把 ki_per_pixel 装备加成 apply 到 consume_ki_by_distance**

`player.gd:680` 当前：
```gdscript
	var cost := distance * float(GameConfig.get_player_value("ki_per_pixel", 0.18))
```
改为：
```gdscript
	var cost := distance * (float(GameConfig.get_player_value("ki_per_pixel", 0.18)) + equip_ki_per_pixel_add)
```

（下方 682 的 `forge_draw_cost_pct_total` pct 乘保留不动——那是打造关 pct 层，叠加在绝对加之后。）

- [ ] **Step 6: 校验无残留旧 crit_damage pct 乘**

Run: `grep -n "crit_damage \* eq_crit_dmg" scripts/entities/player.gd`
Expected: 无输出（已删）。若 `equip_crit_damage_pct` 字段还有别处引用，保持其声明不删（避免别处报错），只是恒 0。

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/player.gd
git commit -m "feat(player): 装备 crit_damage 绝对加 + max_ki/ki_regen/invincible_time/ki_per_pixel 接进实战"
```

---

## Task 8: equipment_panel.gd 核对显示（应基本无需改）

**Files:**
- Modify: `scripts/ui/equipment_panel.gd:923-976`（_refresh_detail_content）

- [ ] **Step 1: 确认 _refresh_detail_content 用的就是 get_item_skill_entries 的 text**

读 `scripts/ui/equipment_panel.gd:944-968`（上一轮已改过的 base/quality 分段逻辑）。确认它读 `entry.get("text", "")` 且不再依赖 `effect_desc_cn`。

Run: `grep -n "effect_desc" scripts/ui/equipment_panel.gd`
Expected: 无输出（已不直读 desc）。

- [ ] **Step 2: 若 _build_active_effect_lines 也读 text，确认一致**

读 `scripts/ui/equipment_panel.gd:1010-1028`。它调 `get_item_skill_entries` 取 `entry.text`。新 text 已是百分比，无需改。**无需编辑**，仅核对。

- [ ] **Step 3: Commit（仅当有改动；无改动则跳过 commit，记录"无需改"）**

若有调整：
```bash
git add scripts/ui/equipment_panel.gd
git commit -m "chore(equip-ui): 核对显示走百分比文本"
```

---

## Task 9: lobby_state — 修正 get_player_preview_attributes 的 stale 默认值

**Files:**
- Modify: `scripts/autoload/lobby_state.gd:925-972`（get_player_preview_attributes）

- [ ] **Step 1: 读现状确认 stale 默认值**

Run: `grep -n "95\|135" scripts/autoload/lobby_state.gd | head`
确认 925-932 区有 `base_attack=95` / `base_ki_regen=135` 等默认值。

- [ ] **Step 2: 把默认值对齐 player.json**

在 `get_player_preview_attributes` 里把硬编码默认改为读 GameConfig（与 player.gd 一致），或直接把字面量改为 52/60。**推荐**：把默认值改成 GameConfig 读取，彻底消除不一致。将该函数顶部 base 读取段改为：

```gdscript
	var base_attack := float(GameConfig.get_player_value("base_attack", 52))
	var base_hp := float(GameConfig.get_player_value("base_hp", 3.0))
	var base_crit_rate := float(GameConfig.get_player_value("base_crit_rate", 0.08))
	var move_speed := float(GameConfig.get_player_value("move_speed", 60))
	var base_crit_damage := float(GameConfig.get_player_value("base_crit_damage", 1.6))
	var base_ki := float(GameConfig.get_player_value("base_ki", 234))
	var base_ki_regen := float(GameConfig.get_player_value("ki_regen_speed", 60))
```

注意：该函数其余处若引用 `equip_crit_damage` 做 pct 乘（preview 也要绝对加），同步把 preview 的 crit_damage 计算也改为绝对加。读该函数后续行，把 `crit_damage *= (1 + equip_crit_damage)` 类逻辑改为 `crit_damage += equip_crit_damage`。

- [ ] **Step 3: Commit**

```bash
git add scripts/autoload/lobby_state.gd
git commit -m "fix(equip): preview 属性默认值对齐 player.json + crit_damage 绝对加"
```

---

## Task 10: 进游戏端到端验证

**Files:** 无（验证任务）

- [ ] **Step 1: 启动游戏到装备页**

跑 Godot 项目，进主菜单 → 装备页。

- [ ] **Step 2: 逐件点开装备，核对白阶显示%**

对照 spec 第三节表：
- 铁制短刀 Lv1 白阶：`攻击力 +10%`
- 轻布甲 Lv1 白阶：`受击无敌时间 +12%`
- 硬木鞋 Lv1 白阶：`暴击率 +63%`
- 毛绒帽 Lv1 白阶：`气力上限 +5%`
- 暴风大剑 Lv1 白阶：`攻击力 +20%`
- 轻灵之靴 Lv1 白阶：`移动速度 +17%`
- 丛林甲 Lv1 白阶：`气力回复速度 +5%`
- 坚固头盔 Lv1 白阶：`划线气力消耗 -5%`

- [ ] **Step 3: 升级一件装备，核对白阶% 增长**

升级铁制短刀到 Lv3，白阶应显示 `攻击力 +14%`（(5+1×2)/52×100=13.46→14）。

- [ ] **Step 4: 核对蓝/紫/橙行显示%**

暴风大剑蓝阶：`暴击伤害倍率 +19%`（0.3/1.6=18.75→19）。

- [ ] **Step 5: 装备实战核对**

装备暴风大剑（蓝）进战斗，核对暴击伤害 1.6→1.9x；装备毛绒帽核对气力上限 234→244；装备轻灵之靴核对移速；装备坚固头盔核对划线消耗下降。

- [ ] **Step 6: 切 English，核对无中文残留**

暂停菜单 → English → 装备页，核对 stat 名全英文（Attack / HP / Crit Rate ...）。

- [ ] **Step 7: 全量 commit（若前面有未提交的微调）**

```bash
git add -A
git commit -m "feat(equip): 装备绝对值百分比显示 + 每级成长 + 新属性实战（端到端验证通过）"
```

---

## 自检清单（写完 plan 后自查）

- [x] spec 每节有对应 task：数据层→T2/T3，状态层→T4/T5/T6/T9，战斗层→T7，显示层→T8，i18n→T1，验证→T10。
- [x] 无 placeholder：每步都有实际代码/命令/期望。
- [x] 类型一致：`per_level_bonuses`（dict of abs）在 T2/T4/T6 命名一致；`equip_*_add` 字段在 T7 各步一致；`_EQUIP_STAT_META` 在 T6 定义、T6/T8 使用一致。
- [x] crit_damage 语义翻转在 T4（bonus 绝对加）、T7（player 绝对加，删 pct 乘）、T9（preview 绝对加）三处一致。
