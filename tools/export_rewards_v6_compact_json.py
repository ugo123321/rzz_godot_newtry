#!/usr/bin/env python3
"""Convert config/excel/rewards_v6_compact.xlsx Sheet1 -> config/json/rewards_v6.json

Phase 1 runtime loader (GameConfig) consumes this JSON. Schema:
    {
      "id": "basic_warrior_soul",
      "name_cn": "..", "desc_cn": "..", "icon": "💪",
      "group": "基础属性",         # int code -> chinese string
      "rarity": "orange",          # int code -> white/blue/purple/orange
      "max_level": 1, "pool_weight": 30,
      "special_rule": 0,           # raw int
      "special_values": [],        # parsed array
      "special_values_per_lv": [],
      "card_path": "physical",
      "trigger": "passive",        # int code -> string key
      "trigger_value": null, "trigger_value_per_lv": null,
      "proc_chance": null, "weapon_mult": null,
      "attrs": [                   # compact 4-slot -> list (skipping empty slots)
        {"id": 1, "value": 0.35, "per_lv": null},
        ...
      ],
      "applies_fire": 0, "applies_ice": 0, "applies_thunder": 0, "applies_poison": 0,
      "notes": "..."
    }

Run after build_rewards_v6_compact.py whenever xlsx changes.
"""
from __future__ import annotations

import json
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "config" / "excel" / "rewards_v6_compact.xlsx"
OUT_JSON = ROOT / "config" / "json" / "rewards_v6.json"

GROUP_CODE_TO_NAME = {
    1: "基础属性", 2: "生存防御", 3: "普攻子弹", 4: "连击", 5: "画线轨迹",
    6: "强化球", 7: "环绕剑", 8: "召唤", 9: "元素",
    10: "恶魔", 11: "天使",
}
RARITY_CODE_TO_NAME = {1: "white", 2: "blue", 3: "purple", 4: "orange"}
TRIGGER_CODE_TO_KEY = {
    1: "passive", 2: "on_hit", 3: "on_kill", 4: "on_pickup",
    5: "on_combo", 6: "on_slash_end", 7: "on_loop_close",
    8: "on_death", 9: "stage_start", 10: "timer", 11: "hp_below",
    12: "vs_boss", 13: "stand", 14: "combo_milestone",
}


def _parse_array_cell(v):
    if v is None or v == "":
        return []
    if isinstance(v, list):
        return v
    try:
        out = json.loads(v)
        return out if isinstance(out, list) else []
    except Exception:
        return []


def _num(v):
    """Pass through None / int / float; coerce numeric strings."""
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return v
    try:
        s = str(v).strip()
        if s == "":
            return None
        f = float(s)
        return int(f) if f.is_integer() else f
    except Exception:
        return None


def convert():
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    ws = wb["rewards"]
    rows = list(ws.iter_rows(values_only=True))[2:]  # skip 2 header rows
    out = []
    for r in rows:
        if not r or r[0] is None:
            continue
        rid = str(r[0])
        rec = {
            "id": rid,
            "name_cn": str(r[1] or ""),
            "group": GROUP_CODE_TO_NAME.get(int(r[2] or 0), str(r[2] or "")),
            "rarity": RARITY_CODE_TO_NAME.get(int(r[3] or 0), str(r[3] or "")),
            "icon": str(r[4] or ""),
            "desc_cn": str(r[5] or ""),
            "max_level": int(r[6] or 1),
            "pool_weight": int(r[7] or 0),
            "special_rule": int(r[8] or 0),
            "special_values": _parse_array_cell(r[9]),
            "special_values_per_lv": _parse_array_cell(r[10]),
            "card_path": str(r[11] or ""),
            "trigger": TRIGGER_CODE_TO_KEY.get(int(r[12] or 1), "passive"),
            "trigger_value": _num(r[13]),
            "trigger_value_per_lv": _num(r[14]),
            "proc_chance": _num(r[15]),
            "weapon_mult": _num(r[16]),
            "applies_fire": int(r[29] or 0),
            "applies_ice": int(r[30] or 0),
            "applies_thunder": int(r[31] or 0),
            "applies_poison": int(r[32] or 0),
            "notes": str(r[33] or ""),
        }
        attrs = []
        for slot in range(4):
            i = 17 + slot * 3
            aid = r[i]
            if aid is None or aid == "":
                continue
            attrs.append({
                "id": int(aid),
                "value": _num(r[i + 1]),
                "per_lv": _num(r[i + 2]),
            })
        rec["attrs"] = attrs
        out.append(rec)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"Wrote {OUT_JSON} ({len(out)} entries)")
    return out


if __name__ == "__main__":
    convert()
