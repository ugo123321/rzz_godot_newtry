#!/usr/bin/env python3
"""Convert config/excel/card.xlsx Sheet1 -> config/json/talents.json

Talent card definitions consumed by LobbyState. Schema (v2, 17 cards):

    {
      "id": "lethal_strike",
      "name_cn": "致命一击", "name_en": "Lethal Strike",
      "quality": 2,                 # 0=white 1=blue 2=purple 3=orange
      "weight": 5, "max_level": 3,
      "pity_target": 0,             # H column; 0 = no pity
      "effects": [                  # drives LobbyState.get_talent_modifiers
        {"key": "crit_rate", "per_level": 0.05},
        {"key": "crit_damage", "per_level": 0.05}
      ],
      "unlock_flag": "",            # non-empty for orange unlock cards
      "desc_template_cn": "暴击率+{v0}, 暴击伤害+{v1}",
      "desc_template_en": "Crit Rate +{v0}, Crit Damage +{v1}",
      "display": [                  # per-effect display value for desc_template
        {"per_level": 5.0, "pct": true},
        {"per_level": 5.0, "pct": true}
      ]
    }

Note: `effects[i].per_level` drives real gameplay math (may differ from display).
`display[i].per_level` drives UI text only (e.g. range card: effects +15 game units,
display "+5%" per level — arbitrary designer-facing text).

Run: `python tools/export_card_json.py` whenever card.xlsx changes.
"""
from __future__ import annotations

import json
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "config" / "excel" / "card.xlsx"
OUT_JSON = ROOT / "config" / "json" / "talents.json"

CN_TO_ID = {
    # 白 4
    "力量": "strength", "生命": "hp", "射程": "range", "攻速": "atk_speed",
    # 蓝 5
    "气力": "ki", "回气": "ki_regen", "暴击率": "crit_rate",
    "暴伤": "crit_damage", "移速": "move_speed",
    # 紫 5
    "致命一击": "lethal_strike", "电光石火": "lightning_dash", "冥想": "meditation",
    "超级强化": "super_enhance", "远程打击": "long_range_strike",
    # 橙 3（天使关/恶魔关/属性打造三张 stage 解锁卡已移除，改由 stages.xlsx theme/room_type 配置控制）
    "先发制人": "unlock_first_reward",
    "神秘大奖": "unlock_mystery_portal", "精英化": "unlock_elite_enemy",
}

CN_TO_EN_NAME = {
    "力量": "Strength", "生命": "Vitality", "射程": "Range", "攻速": "Attack Speed",
    "气力": "Ki", "回气": "Ki Regen", "暴击率": "Crit Rate",
    "暴伤": "Crit Damage", "移速": "Move Speed",
    "致命一击": "Lethal Strike", "电光石火": "Lightning Dash", "冥想": "Meditation",
    "超级强化": "Super Enhance", "远程打击": "Long-Range Strike",
    "先发制人": "First Strike",
    "神秘大奖": "Mystery Grand Prize", "精英化": "Elite Mutation",
}

# id -> {
#   effects_game: [(effect_key, per_level_game), ...]  drives gameplay math
#   template_cn / template_en: with {v0}, {v1}...      drives desc UI
#   display: [(per_level_display, is_pct), ...]        drives {vN} substitution in desc
#   unlock_flag: "..."                                  non-empty for orange cards (no effects)
# }
ID_META = {
    # ---------- 白 4 ----------
    "strength": {
        "effects_game": [("attack", 2.0)],
        "template_cn": "攻击力+{v0}",
        "template_en": "ATK +{v0}",
        "display": [(2.0, False)],
    },
    "hp": {
        "effects_game": [("max_hp", 2.0)],
        "template_cn": "生命+{v0}",
        "template_en": "HP +{v0}",
        "display": [(2.0, False)],
    },
    "range": {
        "effects_game": [("bullet_range", 15.0)],
        "template_cn": "射程+{v0}",
        "template_en": "Range +{v0}",
        "display": [(5.0, True)],  # UI shows "+5%/lv" though game applies +15/lv
    },
    "atk_speed": {
        "effects_game": [("attack_interval", -0.05)],
        "template_cn": "攻速+{v0}",
        "template_en": "Attack Speed +{v0}",
        "display": [(2.0, True)],  # UI shows "+2%/lv" though game applies -0.05s/lv
    },
    # ---------- 蓝 5 ----------
    "ki": {
        "effects_game": [("max_ki", 5.0)],
        "template_cn": "气力上限+{v0}",
        "template_en": "Max Ki +{v0}",
        "display": [(5.0, False)],
    },
    "ki_regen": {
        "effects_game": [("ki_regen", 2.0)],
        "template_cn": "气力回复速度+{v0}",
        "template_en": "Ki Regen +{v0}",
        "display": [(2.0, False)],
    },
    "crit_rate": {
        "effects_game": [("crit_rate", 0.005)],
        "template_cn": "暴击率+{v0}",
        "template_en": "Crit Rate +{v0}",
        "display": [(0.5, True)],
    },
    "crit_damage": {
        "effects_game": [("crit_damage", 0.02)],
        "template_cn": "暴击伤害倍率+{v0}",
        "template_en": "Crit Damage +{v0}",
        "display": [(2.0, True)],
    },
    "move_speed": {
        "effects_game": [("move_speed", 5.0)],
        "template_cn": "移动速度+{v0}",
        "template_en": "Move Speed +{v0}",
        "display": [(5.0, False)],
    },
    # ---------- 紫 5（多属性） ----------
    "lethal_strike": {
        "effects_game": [("crit_rate", 0.05), ("crit_damage", 0.05)],
        "template_cn": "暴击率+{v0}, 暴击伤害倍率+{v1}",
        "template_en": "Crit Rate +{v0}, Crit Damage +{v1}",
        "display": [(5.0, True), (5.0, True)],
    },
    "lightning_dash": {
        "effects_game": [("move_speed", 5.0), ("attack_interval", -0.1)],
        "template_cn": "移动速度+{v0}, 攻速+{v1}",
        "template_en": "Move Speed +{v0}, Attack Speed +{v1}",
        "display": [(5.0, False), (5.0, True)],
    },
    "meditation": {
        "effects_game": [("max_ki", 10.0), ("ki_regen", 5.0)],
        "template_cn": "气力上限+{v0}, 气力回复速度+{v1}",
        "template_en": "Max Ki +{v0}, Ki Regen +{v1}",
        "display": [(5.0, False), (5.0, False)],  # G列 UI 值 (5,5)，与 E 列游戏值 (10,5) 不同
    },
    "super_enhance": {
        "effects_game": [("attack", 10.0), ("max_hp", 5.0)],
        "template_cn": "攻击力+{v0}, 生命+{v1}",
        "template_en": "ATK +{v0}, HP +{v1}",
        "display": [(10.0, False), (5.0, False)],
    },
    "long_range_strike": {
        "effects_game": [("attack", 5.0), ("bullet_range", 20.0)],
        "template_cn": "攻击力+{v0}, 射程+{v1}",
        "template_en": "ATK +{v0}, Range +{v1}",
        "display": [(5.0, False), (6.0, True)],  # UI 显示 +6%/lv
    },
    # ---------- 橙 3（unlock） ----------
    # 天使关/恶魔关/属性打造三张 stage 解锁卡已移除：stage 开启改由
    # stages.xlsx 的 theme / room_type 列配置控制，不再走天赋卡 unlock。
    "unlock_first_reward": {
        "effects_game": [],
        "template_cn": "进入游戏时触发一次奖励",
        "template_en": "Trigger one reward on game start",
        "display": [],
        "unlock_flag": "first_reward",
    },
    "unlock_mystery_portal": {
        "effects_game": [],
        "template_cn": "偶尔会出现神秘传送门",
        "template_en": "Mystery portals may appear",
        "display": [],
        "unlock_flag": "mystery_portal",
    },
    "unlock_elite_enemy": {
        "effects_game": [],
        "template_cn": "敌人小概率变异",
        "template_en": "Enemies may mutate into elites",
        "display": [],
        "unlock_flag": "elite_enemy",
    },
}

QUALITY_CN_TO_INT = {"白": 0, "蓝": 1, "紫": 2, "橙": 3}


def _num(v, default=0):
    if v is None or v == "":
        return default
    if isinstance(v, (int, float)):
        return v
    try:
        f = float(str(v).strip())
        return int(f) if f.is_integer() else f
    except Exception:
        return default


def convert():
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    ws = wb["Sheet1"]
    rows = list(ws.iter_rows(values_only=True))[1:]  # skip header
    out = []
    for r in rows:
        if not r or r[0] is None:
            continue
        name_cn = str(r[0]).strip()
        if name_cn not in CN_TO_ID:
            continue
        rid = CN_TO_ID[name_cn]
        meta = ID_META[rid]
        quality_raw = str(r[2] or "").strip()
        quality = QUALITY_CN_TO_INT.get(quality_raw, 0)
        # B column (index 1) — icon file name (strip optional .png suffix)
        icon_name = str(r[1] or "").strip()
        if icon_name.lower().endswith(".png"):
            icon_name = icon_name[:-4]
        # H column (index 7) — pity target
        pity_target = int(_num(r[7], 0)) if len(r) > 7 else 0

        effects_json = [
            {"key": k, "per_level": float(pl)}
            for (k, pl) in meta["effects_game"]
        ]
        display_json = [
            {"per_level": float(pl), "pct": bool(is_pct)}
            for (pl, is_pct) in meta["display"]
        ]
        rec = {
            "id": rid,
            "name_cn": name_cn,
            "name_en": CN_TO_EN_NAME[name_cn],
            "quality": quality,
            "weight": int(_num(r[3], 1)),
            "max_level": int(_num(r[5], 1)),
            "pity_target": pity_target,
            "effects": effects_json,
            "unlock_flag": meta.get("unlock_flag", ""),
            "desc_template_cn": meta["template_cn"],
            "desc_template_en": meta["template_en"],
            "display": display_json,
            "icon": icon_name,
        }
        out.append(rec)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(
        json.dumps({"talents": out}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"[export_card_json] wrote {len(out)} talents -> {OUT_JSON}")


if __name__ == "__main__":
    convert()
