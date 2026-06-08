#!/usr/bin/env python3
"""Export Aseprite atlases (JSON + PNG) for runtime EffectHelper atlas loading.

Requires Aseprite CLI. Re-run after editing source .ase files.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "effects"

# (ase relative to ASSETS, json dir name under pack, sheet dir name, output basename)
EXPORTS = [
    (
        "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/Aseprite files/fire.ase",
        "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/aseprite",
        "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/spritesheets",
        "fire",
    ),
    (
        "1.Gothicvania Magic Pack N1/Magic Pack  files/aseprite/ice.ase",
        "1.Gothicvania Magic Pack N1/Magic Pack  files/aseprite",
        "1.Gothicvania Magic Pack N1/Magic Pack  files/spritesheets",
        "ice",
    ),
    (
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/small-spark.ase",
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite",
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets",
        "small-spark",
    ),
    (
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/big-bolt.ase",
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite",
        "3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets",
        "big-bolt",
    ),
    (
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fireball.ase",
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite",
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets",
        "fireball",
    ),
    (
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fire-missile.ase",
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite",
        "5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets",
        "fire-missile",
    ),
    (
        "6.GothicVania Magic Pack 6/Magic Pack 6/Aseprite files/slash.ase",
        "6.GothicVania Magic Pack 6/Magic Pack 6/aseprite",
        "6.GothicVania Magic Pack 6/Magic Pack 6/spritesheets",
        "slash",
    ),
    (
        "7.Warped Explosion Pack 3/Explosions Pack 3 files/aseprite/explosion-j.ase",
        "7.Warped Explosion Pack 3/Explosions Pack 3 files/aseprite",
        "7.Warped Explosion Pack 3/Explosions Pack 3 files/spritesheets",
        "explosion-j",
    ),
    (
        "13.Gothicvania Magic Pack 8/Magic Pack 8 files/aseprite/water.ase",
        "13.Gothicvania Magic Pack 8/Magic Pack 8 files/aseprite",
        "13.Gothicvania Magic Pack 8/Magic Pack 8 files/spritesheets",
        "water",
    ),
    (
        "9.Warped Explosion Pack 5/Explosions Pack 5 Files/Aseprite files/explosion-c.ase",
        "9.Warped Explosion Pack 5/Explosions Pack 5 Files/aseprite",
        "9.Warped Explosion Pack 5/Explosions Pack 5 Files/spritesheets",
        "explosion-c",
    ),
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


def export_one(aseprite: str, ase_rel: str, json_dir_rel: str, sheet_dir_rel: str, name: str) -> None:
    ase_path = ASSETS / ase_rel
    if not ase_path.exists():
        print(f"SKIP missing {ase_path}")
        return
    json_dir = ASSETS / json_dir_rel
    sheet_dir = ASSETS / sheet_dir_rel
    json_dir.mkdir(parents=True, exist_ok=True)
    sheet_dir.mkdir(parents=True, exist_ok=True)
    json_path = json_dir / f"{name}.json"
    sheet_path = sheet_dir / f"{name}.png"
    cmd = [
        aseprite,
        "-b",
        "--data",
        str(json_path),
        "--format",
        "json-array",
        "--sheet",
        str(sheet_path),
        "--sheet-type",
        "horizontal",
        str(ase_path),
    ]
    subprocess.run(cmd, check=True)
    with json_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    data.setdefault("meta", {})["image"] = f"../spritesheets/{name}.png"
    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    print(f"OK {name}: {len(data.get('frames', []))} frames -> {sheet_path.name}")


def main() -> int:
    try:
        aseprite = find_aseprite()
    except FileNotFoundError as exc:
        print(exc, file=sys.stderr)
        return 1
    for row in EXPORTS:
        export_one(aseprite, *row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
