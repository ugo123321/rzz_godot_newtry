#!/usr/bin/env python3
"""Copy only game-used assets from the reference library into renzhezhan/assets.

Reference library: D:\\workspace\\godot1\\sucai
Project assets:   renzhezhan/assets/  (real folder, not a junction)

When adding new assets later, append paths here and re-run:
  python tools/copy_used_assets.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(r"D:\workspace\godot1\sucai")
DEST = ROOT / "assets"

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

# Files or directories relative to assets/
USED_PATHS: list[str] = [
    # UI
    "ui/UI assets (1x).png",
    "ui/Fonts/FantasyRPGtext (size 8).ttf",
    "ui/Fonts/FantasyRPGtitle (size 11).ttf",
    "ui/equipment/back_button.png",
    "ui/equipment/buttom_bar.png",
    "ui/equipment/decoration01.png",
    "ui/equipment/detail_icon.png",
    "ui/equipment/equipment_slot01.png",
    "ui/equipment/equipment_slot02.png",
    "ui/equipment/equipment_system_reference.png",
    "ui/equipment/full_bg.png",
    "ui/equipment/heart_icon.png",
    "ui/equipment/information_bg.png",
    "ui/equipment/power_icon.png",
    "ui/equipment/sword_icon.png",
    "ui/equipment/Synthesis _button.png",
    "ui/equipment/top_bg.png",
    # Terrain props
    "Terrain/Rocks/6.png",
    "Terrain/Rocks/7.png",
    "Terrain/Rocks/8.png",
    "Terrain/Rocks/9.png",
    "Terrain/Trees/Tree1.png",
    "Terrain/Trees/4.png",
    "Terrain/Trees/5.png",
    # Effects — EFFECT_ATLAS + PREVIEW_PATHS (effect_helper.gd)
    "effects/1.Gothicvania Magic Pack N1/Magic Pack  files/aseprite/ice.json",
    "effects/1.Gothicvania Magic Pack N1/Magic Pack  files/spritesheets/ice.png",
    "effects/1.Gothicvania Magic Pack N1/Magic Pack  files/ice",
    "effects/1.Gothicvania Magic Pack N1/Magic Pack  files/thunder",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/aseprite/fire.json",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/spritesheets/fire.png",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/fire",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/aseprite/flame-loop.json",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/spritesheets/flame-loop.png",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/flame-loop",
    "effects/2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/Aseprite files/flame-loop.ase",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/small-spark.json",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/aseprite/big-bolt.json",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/small-spark.png",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/spritesheets/big-bolt.png",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/big-bolt",
    "effects/3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/spark",
    "effects/4.GothicVania Magic Pack 4/Magic Pack 4 files/sprites/Cure/sprites",
    "effects/4.GothicVania Magic Pack 4/Magic Pack 4 files/sprites/wisp/sprites",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fire-missile.json",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/aseprite/fireball.json",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets/fire-missile.png",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/spritesheets/fireball.png",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/fire-missile/sprites",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/fireball/sprites",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/Smoke/sprites",
    "effects/5.GothicVania Magic Pack 5/Magic Pack 5 Files/sprites/flash/sprites",
    "effects/6.GothicVania Magic Pack 6/Magic Pack 6/aseprite/slash.json",
    "effects/6.GothicVania Magic Pack 6/Magic Pack 6/spritesheets/slash.png",
    "effects/6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash",
    "effects/7.Warped Explosion Pack 3/Explosions Pack 3 files/aseprite/explosion-j.json",
    "effects/7.Warped Explosion Pack 3/Explosions Pack 3 files/spritesheets/explosion-j.png",
    "effects/7.Warped Explosion Pack 3/Explosions Pack 3 files/Sprites/explosion-j",
    "effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/aseprite/water.json",
    "effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/spritesheets/water.png",
    "effects/13.Gothicvania Magic Pack 8/Magic Pack 8 files/sprites/water",
    "effects/enemy_projectiles/aseprite/enemy_cross_magic.json",
    "effects/enemy_projectiles/aseprite/enemy_shotgun_arrow.json",
    "effects/enemy_projectiles/spritesheets/enemy_cross_magic.png",
    "effects/enemy_projectiles/spritesheets/enemy_shotgun_arrow.png",
]


def copy_path(rel: str) -> None:
    src = SRC / rel
    dst = DEST / rel
    if not src.exists():
        print(f"MISSING in sucai: {rel}", file=sys.stderr)
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)
    print(f"OK {rel}")


def copy_character(name: str) -> None:
    for sub in (
        f"Characters/atlases/json/{name}.json",
        f"Characters/atlases/sheets/{name}.png",
        f"Characters/Characters(100x100)/{name}",
    ):
        copy_path(sub)


def remove_junction() -> None:
    if not DEST.exists():
        return
    # Junction / symlink: rmdir only removes the link, not the target.
    try:
        DEST.rmdir()
        print("Removed existing assets junction/link.")
    except OSError:
        shutil.rmtree(DEST)
        print("Removed existing assets directory.")


def copy_explosion_c() -> None:
    import importlib.util

    script = ROOT / "tools" / "copy_explosion_c.py"
    spec = importlib.util.spec_from_file_location("copy_explosion_c", script)
    if spec is None or spec.loader is None:
        print(f"WARN: cannot load {script}", file=sys.stderr)
        return
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.main() != 0:
        print("WARN: explosion-c copy failed", file=sys.stderr)


def main() -> int:
    if not SRC.is_dir():
        print(f"Reference library not found: {SRC}", file=sys.stderr)
        return 1
    remove_junction()
    DEST.mkdir(parents=True, exist_ok=True)
    for rel in USED_PATHS:
        copy_path(rel)
    for name in CHARACTERS:
        copy_character(name)
    copy_explosion_c()
    print(f"\nDone. Assets copied to {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
