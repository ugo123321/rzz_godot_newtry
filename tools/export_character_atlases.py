#!/usr/bin/env python3
"""Export character Aseprite atlases (JSON + PNG) for runtime SpriteHelper loading."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "Characters"
ASE_DIR = ASSETS / "Aseprite file"
JSON_DIR = ASSETS / "atlases" / "json"
SHEET_DIR = ASSETS / "atlases" / "sheets"

# folder/prefix used in game config -> Aseprite source basename
CHARACTERS = [
    "Swordsman",
    "Skeleton",
    "Elite Orc",
    "Knight",
    "Armored Axeman",
    "Slime",
    "Archer",
    "Wizard",
    "Werewolf",
    "Werebear",
    "Knight Templar",
    "Skeleton Archer",
    "Priest",
    "Lancer",
]


def find_aseprite() -> str:
    candidates = [
        os.environ.get("ASEPRITE"),
        r"D:\Steam\steamapps\common\Aseprite\Aseprite.exe",
        r"C:\Program Files\Aseprite\Aseprite.exe",
        r"C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe",
        "aseprite",
    ]
    for cmd in candidates:
        if not cmd:
            continue
        path = shutil.which(cmd) if os.path.basename(cmd) == cmd else cmd
        if path and Path(path).exists():
            return path
    raise FileNotFoundError("Aseprite CLI not found. Set ASEPRITE env var.")


def source_path(name: str) -> Path:
    for ext in (".aseprite", ".ase"):
        candidate = ASE_DIR / f"{name}{ext}"
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"Missing Aseprite source for {name}")


def export_one(aseprite: str, name: str) -> None:
    src = source_path(name)
    JSON_DIR.mkdir(parents=True, exist_ok=True)
    SHEET_DIR.mkdir(parents=True, exist_ok=True)
    json_path = JSON_DIR / f"{name}.json"
    sheet_path = SHEET_DIR / f"{name}.png"
    cmd = [
        aseprite,
        "-b",
        "--list-tags",
        "--data",
        str(json_path),
        "--format",
        "json-array",
        "--sheet",
        str(sheet_path),
        "--sheet-type",
        "horizontal",
        str(src),
    ]
    subprocess.run(cmd, check=True)
    with json_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    data.setdefault("meta", {})["image"] = f"../sheets/{name}.png"
    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    tags = data.get("meta", {}).get("frameTags", [])
    print(f"OK {name}: {len(data.get('frames', []))} frames, {len(tags)} tags")


def main() -> int:
    try:
        aseprite = find_aseprite()
    except FileNotFoundError as exc:
        print(exc, file=sys.stderr)
        return 1
    for name in CHARACTERS:
        try:
            export_one(aseprite, name)
        except FileNotFoundError as exc:
            print(f"SKIP {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
