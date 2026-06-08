#!/usr/bin/env python3
"""Restore upgrades.json / upgrade_fx.json from export_config canonical rows + icon assets."""
from __future__ import annotations

import json
from pathlib import Path

from export_config import (
    JSON_DIR,
    UPGRADE_FX_HEADERS,
    UPGRADE_FX_ROWS,
    UPGRADE_HEADERS,
    UPGRADE_ROWS,
    save_json,
)

ICON_DIR = Path(__file__).resolve().parents[1] / "assets" / "icons" / "upgrades"
AUTO_BULLET_IDS = {
    "multi_bullet",
    "bounce_bullet",
    "mirror_bullet",
    "pierce",
    "laser_blast",
    "spirit_bomb",
}


def _row_to_upgrade(row: list) -> dict:
    item = {h: row[i] if i < len(row) else "" for i, h in enumerate(UPGRADE_HEADERS)}
    uid = str(item.get("id", ""))
    if uid in AUTO_BULLET_IDS:
        item["category"] = "auto_bullet"
    icon_path = ICON_DIR / f"{uid}.png"
    if icon_path.is_file():
        item["icon_file"] = f"res://assets/icons/upgrades/{uid}.png"
    # Drop empty optional fields for cleaner JSON.
    cleaned = {}
    for k, v in item.items():
        if v == "" or v is None:
            continue
        if k == "fx_below_monsters" and int(v) == 0:
            continue
        if k in ("once_per_run", "once_per_chapter", "is_pet") and int(v) == 0:
            cleaned[k] = 0
            continue
        cleaned[k] = v
    return cleaned


def _row_to_fx(row: list) -> dict:
    return {h: row[i] if i < len(row) else "" for i, h in enumerate(UPGRADE_FX_HEADERS)}


def main() -> None:
    upgrades = [_row_to_upgrade(row) for row in UPGRADE_ROWS]
    fx = [_row_to_fx(row) for row in UPGRADE_FX_ROWS]
    save_json("upgrades", upgrades)
    save_json("upgrade_fx", fx)
    print(f"Restored {len(upgrades)} upgrades, {len(fx)} rarity tiers.")


if __name__ == "__main__":
    main()
