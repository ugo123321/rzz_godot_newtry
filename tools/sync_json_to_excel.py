#!/usr/bin/env python3
"""Push config/json into Excel. Run after editing JSON; before export_config for stages/monsters only."""
from __future__ import annotations

import json
from pathlib import Path

from openpyxl import Workbook

from export_config import (
    CHAPTER_HEADERS,
    EXCEL_DIR,
    JSON_DIR,
    MONSTER_HEADERS,
    REWARDS_V6_HEADERS,
    STAGE_HEADERS,
    UPGRADE_FX_HEADERS,
    write_sheet,
)


def _load_json(name: str) -> list[dict]:
    with (JSON_DIR / f"{name}.json").open(encoding="utf-8") as f:
        return json.load(f)


def _monster_row(item: dict) -> list:
    return [item.get(h, "") for h in MONSTER_HEADERS]


def _stage_row(item: dict) -> list:
    row: list = []
    for h in STAGE_HEADERS:
        val = item.get(h, "")
        if h == "reward_rooms" and isinstance(val, list):
            val = ",".join(str(x) for x in val)
        row.append(val)
    return row


def _chapter_row(item: dict) -> list:
    return [item.get(h, "") for h in CHAPTER_HEADERS]


def _upgrade_fx_row(item: dict) -> list:
    return [item.get(h, "") for h in UPGRADE_FX_HEADERS]


def _reward_v6_row(item: dict) -> list:
    """rewards_v6.json 里 extra_params 是 dict，要回写成 JSON 字符串再进 Excel 单元格。"""
    row: list = []
    for h in REWARDS_V6_HEADERS:
        val = item.get(h, "")
        if h == "extra_params" and isinstance(val, dict):
            val = json.dumps(val, ensure_ascii=False, sort_keys=True) if val else ""
        row.append(val)
    return row


def _rewrite_sheet(path: Path, headers: list[str], rows: list[list]) -> None:
    if path.exists():
        path.unlink()
    wb = Workbook()
    ws = wb.active
    write_sheet(ws, headers, rows)
    wb.save(path)
    print(f"Excel: {path}")


def main() -> None:
    EXCEL_DIR.mkdir(parents=True, exist_ok=True)
    chapters = _load_json("chapters")
    monsters = _load_json("monsters")
    stages = _load_json("stages")
    _rewrite_sheet(
        EXCEL_DIR / "chapters.xlsx",
        CHAPTER_HEADERS,
        [_chapter_row(c) for c in chapters],
    )
    _rewrite_sheet(
        EXCEL_DIR / "monsters.xlsx",
        MONSTER_HEADERS,
        [_monster_row(m) for m in monsters],
    )
    _rewrite_sheet(
        EXCEL_DIR / "stages.xlsx",
        STAGE_HEADERS,
        [_stage_row(s) for s in stages],
    )
    upgrade_fx = _load_json("upgrade_fx")
    _rewrite_sheet(
        EXCEL_DIR / "upgrade_fx.xlsx",
        UPGRADE_FX_HEADERS,
        [_upgrade_fx_row(u) for u in upgrade_fx],
    )
    # rewards_v6: JSON 为权威源，回写到 Excel 便于策划编辑
    rewards_v6_path = JSON_DIR / "rewards_v6.json"
    if rewards_v6_path.exists():
        rewards_v6 = _load_json("rewards_v6")
        _rewrite_sheet(
            EXCEL_DIR / "rewards_v6.xlsx",
            REWARDS_V6_HEADERS,
            [_reward_v6_row(r) for r in rewards_v6],
        )
    print("Done.")


if __name__ == "__main__":
    main()
