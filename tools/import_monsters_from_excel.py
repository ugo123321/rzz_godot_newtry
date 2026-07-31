#!/usr/bin/env python3
"""monsters.xlsx -> monsters.json 单向安全导入。

策划在 config/excel/monsters.xlsx 改完怪物数值后，跑这个脚本把改动写回
config/json/monsters.json，重启 Godot (F5) 即生效。

为什么不用 tools/export_config.py？
  export_config.py 是全量 excel->json，会顺带用硬编码 2-boss dict 覆盖 bosses.json
  （现有 5 个 boss 会被洗成 2 个），还会因 monsters.xlsx 缺 elem_resist_*/vuln_*/
  name_en/dash_speed/segment_*/windup_sec 等 json-only 列而把这些字段从
  monsters.json 洗掉。本脚本只动 monsters.json，且按 kind_id 字段级合并——
  只覆盖 MONSTER_HEADERS 里 xlsx 存在的列，json-only 字段原样保留。

跑法：python tools/import_monsters_from_excel.py
"""
from __future__ import annotations

import json

import openpyxl

from export_config import (
    JSON_DIR,
    EXCEL_DIR,
    MONSTER_HEADERS,
    normalize_cell,
    save_json,
)

MONSTERS_XLSX = EXCEL_DIR / "monsters.xlsx"


def _read_monsters_sheet() -> list[dict]:
    if not MONSTERS_XLSX.exists():
        raise FileNotFoundError(f"找不到 {MONSTERS_XLSX}")
    wb = openpyxl.load_workbook(MONSTERS_XLSX, data_only=True)
    # sync_json_to_excel 写出的 monsters.xlsx 默认 sheet 名为 "Sheet"，取 active 即可
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []
    headers = [str(h).strip() if h is not None else "" for h in rows[0]]
    out: list[dict] = []
    for raw in rows[1:]:
        if all(cell is None or str(cell).strip() == "" for cell in raw):
            continue
        item: dict = {}
        for i, h in enumerate(headers):
            if not h:
                continue
            val = normalize_cell(raw[i] if i < len(raw) else None)
            item[h] = "" if val is None else val
        if any(str(v).strip() != "" for v in item.values() if v is not None):
            out.append(item)
    return out


def _merge_row_onto_entry(entry: dict, row: dict) -> None:
    """字段级合并：只覆盖 MONSTER_HEADERS 中 xlsx 行里出现的列。
    json-only 字段（elem_resist_*/vuln_*/name_en/机制字段）不在 MONSTER_HEADERS，
    永远不会被这里碰到，原样保留。"""
    for h in MONSTER_HEADERS:
        if h == "kind_id":
            continue
        if h not in row:
            continue
        entry[h] = row[h]


def _row_to_new_entry(row: dict) -> dict:
    """新 kind：只用 MONSTER_HEADERS 列造一条干净 json 记录（忽略 xlsx 里可能的杂列）。"""
    entry: dict = {}
    for h in MONSTER_HEADERS:
        if h in row:
            entry[h] = row[h]
        else:
            entry[h] = ""
    return entry


def main() -> None:
    xlsx_rows = _read_monsters_sheet()
    json_path = JSON_DIR / "monsters.json"
    existing: list[dict] = json.loads(json_path.read_text(encoding="utf-8"))
    by_id: dict[str, dict] = {str(m.get("kind_id", "")): m for m in existing}

    updated = 0
    added = 0
    new_kinds: list[str] = []
    for row in xlsx_rows:
        kid = str(row.get("kind_id", "")).strip()
        if not kid:
            continue
        target = by_id.get(kid)
        if target is None:
            by_id[kid] = _row_to_new_entry(row)
            new_kinds.append(kid)
            added += 1
            continue
        _merge_row_onto_entry(target, row)
        updated += 1

    # 输出顺序：原 json 顺序在前，xlsx 新增 kind 追加在后
    out: list[dict] = []
    seen: set[str] = set()
    for m in existing:
        kid = str(m.get("kind_id", ""))
        if kid and kid in by_id and kid not in seen:
            out.append(by_id[kid])
            seen.add(kid)
    for kid in new_kinds:
        if kid not in seen:
            out.append(by_id[kid])
            seen.add(kid)

    save_json("monsters", out)
    print(f"[import_monsters] {updated} updated, {added} added, {len(out)} total <- {MONSTERS_XLSX}")
    if new_kinds:
        print(f"  new kind_id: {new_kinds}")
    print("重启 Godot (F5) 生效。")


if __name__ == "__main__":
    main()
