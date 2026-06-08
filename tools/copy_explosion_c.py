#!/usr/bin/env python3
"""Copy Explosion-C from sucai into assets with Aseprite atlas layout."""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUCAI = Path(r"D:\workspace\godot1\sucai\effects\9.Warped Explosion Pack 5\Explosions Pack 5 Files")
DEST = ROOT / "assets/effects/9.Warped Explosion Pack 5/Explosions Pack 5 Files"


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError(path)
        f.read(4)
        if f.read(4) != b"IHDR":
            raise ValueError(path)
        w, h = struct.unpack(">II", f.read(8))
        return w, h


def frame_num(path: Path) -> int:
    digits = "".join(ch for ch in path.stem if ch.isdigit())
    return int(digits or "0")


def main() -> int:
    if not SUCAI.is_dir():
        print(f"Missing sucai pack: {SUCAI}", file=sys.stderr)
        return 1

    src_sprites = SUCAI / "Sprites/Explosion C"
    dst_sprites = DEST / "sprites/explosion-c"
    if dst_sprites.exists():
        shutil.rmtree(dst_sprites)
    dst_sprites.mkdir(parents=True)
    files = sorted(src_sprites.glob("Explosion-C*.png"), key=frame_num)
    for i, fp in enumerate(files, 1):
        shutil.copy2(fp, dst_sprites / f"explosion-c{i}.png")
    print(f"OK sprites: {len(files)} frames")

    sheet_dst_dir = DEST / "spritesheets"
    sheet_dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SUCAI / "Spritesheets/Explosion-C.png", sheet_dst_dir / "explosion-c.png")
    sheet_w, sheet_h = png_size(sheet_dst_dir / "explosion-c.png")
    print(f"OK spritesheet: {sheet_w}x{sheet_h}")

    ase_dst_dir = DEST / "Aseprite files"
    ase_dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SUCAI / "Aseprite/Explosion-C.ase", ase_dst_dir / "explosion-c.ase")
    print("OK ase: explosion-c.ase")

    frames = []
    for i, fp in enumerate(files, 1):
        dst_fp = dst_sprites / f"explosion-c{i}.png"
        fw, fh = png_size(dst_fp)
        frames.append(
            {
                "filename": dst_fp.name,
                "frame": {"x": (i - 1) * fw, "y": 0, "w": fw, "h": fh},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": fw, "h": fh},
                "sourceSize": {"w": fw, "h": fh},
                "duration": 70,
            }
        )

    ase_dir = DEST / "aseprite"
    ase_dir.mkdir(parents=True, exist_ok=True)
    meta = {
        "frames": frames,
        "meta": {
            "app": "https://www.aseprite.org/",
            "version": "1.3.12-x64",
            "image": "../spritesheets/explosion-c.png",
            "format": "RGBA8888",
            "size": {"w": sheet_w, "h": sheet_h},
            "scale": "1",
        },
    }
    (ase_dir / "explosion-c.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"OK json: {len(frames)} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
