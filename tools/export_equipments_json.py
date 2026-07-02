#!/usr/bin/env python3
"""Convert config/excel/equipments.xlsx Sheet1 -> config/json/equipments.json

Schema (per equipment):
    {
      "def_id": "iron_dagger",
      "name_cn": "铁制短刀", "name_en": "Iron Dagger",
      "slot": "weapon",
      "icon_path": "res://assets/icons/equipment/icon_equip_iron_dagger.svg",
      "is_rare": 0,
      "tiers": [
        {"quality": 0, "stat_bonuses": {...}, "flag": null,
         "effect_desc_cn": "...", "effect_desc_en": "..."},
        ... four tiers, quality 0..3 for white/blue/purple/orange ...
      ]
    }

Skip the "草稿，无视此sheet" sheet. Row-groups of 4 rows per equipment (name
repeats in column A). Runtime consumer: scripts/autoload/lobby_state.gd.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "config" / "excel" / "equipments.xlsx"
OUT_JSON = ROOT / "config" / "json" / "equipments.json"

# 名称（xlsx 中文名）→ def_id / 英文名
NAME_TO_META = {
    "铁制短刀":   ("iron_dagger",        "Iron Dagger"),
    "轻布甲":     ("light_cloth_armor",  "Light Cloth Armor"),
    "硬木鞋":     ("hard_wood_shoes",    "Hard Wood Shoes"),
    "毛绒帽":     ("fur_hat",            "Fur Hat"),
    "暴风大剑":   ("storm_greatsword",   "Storm Greatsword"),
    "轻灵之靴":   ("nimble_boots",       "Nimble Boots"),
    "丛林甲":     ("jungle_armor",       "Jungle Armor"),
    "坚固头盔":   ("sturdy_helmet",      "Sturdy Helmet"),
}

# 部位（xlsx）→ slot key（游戏内）
SLOT_CN_TO_KEY = {
    "武器": "weapon",
    "衣服": "armor",
    "鞋":   "shoes",
    "头盔": "helmet",
    "项链": "necklace",
    "戒指": "ring",
}

# 品质（xlsx 单字）→ 品质代码
QUALITY_CN_TO_CODE = {"白": 0, "蓝": 1, "紫": 2, "橙": 3}

# 中文效果模板 → 抽取的 stat_bonuses / flag / 英文文案。
# 用 regex 精确匹配 —— 表里出现的每种模板都在这里显式声明，避免语义漂移。
EFFECT_PATTERNS = [
    # 攻击力 +N
    (re.compile(r"^攻击力\+(\d+)$"),
     lambda m: ({"attack": int(m.group(1))}, None, f"ATK +{m.group(1)}")),
    # 生命 +N
    (re.compile(r"^生命\+(\d+)$"),
     lambda m: ({"max_hp": int(m.group(1))}, None, f"HP +{m.group(1)}")),
    # 暴击率基础值 +N%
    (re.compile(r"^暴击率基础值\+(\d+)%$"),
     lambda m: ({"crit_rate": int(m.group(1)) / 100.0}, None,
                f"Crit Rate +{m.group(1)}%")),
    # 暴击伤害倍率基础值 +N%
    (re.compile(r"^暴击伤害倍率基础值\+(\d+)%$"),
     lambda m: ({"crit_damage": int(m.group(1)) / 100.0}, None,
                f"Crit DMG +{m.group(1)}%")),
    # 移速基础值 +N
    (re.compile(r"^移速基础值\+(\d+)$"),
     lambda m: ({"move_speed": int(m.group(1))}, None,
                f"Move Speed +{m.group(1)}")),
    # 气力上限基础值 +N%
    (re.compile(r"^气力上限基础值\+(\d+)%$"),
     lambda m: ({"max_ki_pct": int(m.group(1)) / 100.0}, None,
                f"Max Ki +{m.group(1)}%")),
    # 气力回复速度基础值 +N%
    (re.compile(r"^气力回复速度基础值\+(\d+)%$"),
     lambda m: ({"ki_regen_pct": int(m.group(1)) / 100.0}, None,
                f"Ki Regen +{m.group(1)}%")),
    # 传奇特效（纯 flag，无 stat_bonuses）
    (re.compile(r"^子弹获得追踪效果$"),
     lambda m: ({}, "bullet_homing",
                "Bullets seek nearby enemies")),
    (re.compile(r"^持续电击靠近的敌人$"),
     lambda m: ({}, "shock_aura",
                "Continuously shocks nearby enemies")),
    (re.compile(r"^每关随机刷出的树木数量翻倍$"),
     lambda m: ({}, "tree_x2",
                "Trees spawned per stage x2")),
    (re.compile(r"^受击时(\d+)%概率免伤$"),
     lambda m: ({}, "hit_dodge_5pct",
                f"{m.group(1)}% chance to negate incoming hits")),
]


def parse_effect(text: str) -> tuple[dict, str | None, str]:
    """(stat_bonuses, flag, effect_desc_en) —— 找不到匹配就报错，避免静默失败。"""
    text = (text or "").strip()
    for pat, builder in EFFECT_PATTERNS:
        m = pat.match(text)
        if m:
            return builder(m)
    raise ValueError(f"Unknown effect text: {text!r}")


def icon_path_for(def_id: str) -> str:
    return f"res://assets/icons/equipment/icon_equip_{def_id}.svg"


def convert():
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    if "Sheet1" not in wb.sheetnames:
        raise RuntimeError(f"Sheet1 missing in {SRC_XLSX}")
    ws = wb["Sheet1"]
    rows = list(ws.iter_rows(values_only=True))[1:]  # skip header row

    equipments: dict[str, dict] = {}  # def_id -> record
    order: list[str] = []             # keep insertion order for stable output

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
        quality_cn = str(r[4] or "").strip()
        if quality_cn not in QUALITY_CN_TO_CODE:
            raise ValueError(f"Unknown quality: {quality_cn!r}")
        quality = QUALITY_CN_TO_CODE[quality_cn]
        effect_cn = str(r[5] or "").strip()
        stat_bonuses, flag, effect_en = parse_effect(effect_cn)

        if def_id not in equipments:
            equipments[def_id] = {
                "def_id": def_id,
                "name_cn": name_cn,
                "name_en": name_en,
                "slot": slot_key,
                "icon_path": icon_path_for(def_id),
                "is_rare": is_rare,
                "tiers": [None, None, None, None],
            }
            order.append(def_id)
        rec = equipments[def_id]
        if rec["tiers"][quality] is not None:
            raise ValueError(
                f"Duplicate tier for {def_id} quality={quality}")
        rec["tiers"][quality] = {
            "quality": quality,
            "stat_bonuses": stat_bonuses,
            "flag": flag,
            "effect_desc_cn": effect_cn,
            "effect_desc_en": effect_en,
        }

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


if __name__ == "__main__":
    convert()
