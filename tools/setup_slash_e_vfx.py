#!/usr/bin/env python3
"""Copy Magic Pack 6 Slash-e assets and generate Aseprite JSON + spritesheet.

Source : sucai/.../Magic Pack 6/sprites/slash-e (12 frames, 95x96)
         sucai/.../Magic Pack 6/Aseprite files/electric-slash.ase
Output : assets/effects/6.GothicVania Magic Pack 6/Magic Pack 6/
            ├── sprites/slash-e/electric-slash{1..12}.png     (fallback)
            ├── spritesheets/electric-slash.png               (12*95 x 96)
            ├── aseprite/electric-slash.json                  (12-frame entry)
            └── Aseprite files/electric-slash.ase             (source .ase)
"""
import json
import shutil
import struct
from pathlib import Path
from PIL import Image

SRC_ROOT = Path(r"D:\workspace\godot1\sucai\effects\6.GothicVania Magic Pack 6\Magic Pack 6")
DST_ROOT = Path(r"D:\workspace\godot1\rzz_godot\assets\effects\6.GothicVania Magic Pack 6\Magic Pack 6")
FRAME_COUNT = 12
DURATION = 70  # ms per frame, matches slash.json sibling


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        f.read(16)
        w, h = struct.unpack(">II", f.read(8))
    return w, h


def build_json(frame_w: int, frame_h: int, count: int) -> dict:
    frames = []
    for i in range(count):
        frames.append(
            {
                "filename": f"electric-slash {i}.ase",
                "frame": {"x": i * frame_w, "y": 0, "w": frame_w, "h": frame_h},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": frame_w, "h": frame_h},
                "sourceSize": {"w": frame_w, "h": frame_h},
                "duration": DURATION,
            }
        )
    return {
        "frames": frames,
        "meta": {
            "app": "https://www.aseprite.org/",
            "version": "1.3.12-x64",
            "image": "../spritesheets/electric-slash.png",
            "format": "RGBA8888",
            "size": {"w": frame_w * count, "h": frame_h},
            "scale": "1",
        },
    }


def main() -> None:
    src_sprite_dir = SRC_ROOT / "sprites" / "slash-e"
    src_ase = SRC_ROOT / "Aseprite files" / "electric-slash.ase"
    if not src_sprite_dir.is_dir():
        raise SystemExit(f"Missing source sprite dir: {src_sprite_dir}")

    dst_sprite_dir = DST_ROOT / "sprites" / "slash-e"
    dst_sheet_dir = DST_ROOT / "spritesheets"
    dst_ase_json_dir = DST_ROOT / "aseprite"
    dst_ase_src_dir = DST_ROOT / "Aseprite files"
    for d in (dst_sprite_dir, dst_sheet_dir, dst_ase_json_dir, dst_ase_src_dir):
        d.mkdir(parents=True, exist_ok=True)

    # 1) Copy single-frame PNGs (fallback)
    for i in range(1, FRAME_COUNT + 1):
        src = src_sprite_dir / f"electric-slash{i}.png"
        if src.is_file():
            shutil.copy2(src, dst_sprite_dir / f"electric-slash{i}.png")

    # 2) Stitch horizontal spritesheet from in-order single frames
    sample = dst_sprite_dir / "electric-slash1.png"
    frame_w, frame_h = png_size(sample)
    sheet = Image.new("RGBA", (frame_w * FRAME_COUNT, frame_h), (0, 0, 0, 0))
    for i in range(1, FRAME_COUNT + 1):
        frame = Image.open(dst_sprite_dir / f"electric-slash{i}.png").convert("RGBA")
        if frame.size != (frame_w, frame_h):
            raise SystemExit(f"Frame {i} size mismatch: {frame.size} vs {(frame_w, frame_h)}")
        sheet.paste(frame, ((i - 1) * frame_w, 0))
    sheet_path = dst_sheet_dir / "electric-slash.png"
    sheet.save(sheet_path)

    # 3) Aseprite-style JSON sidecar
    json_path = dst_ase_json_dir / "electric-slash.json"
    json_path.write_text(
        json.dumps(build_json(frame_w, frame_h, FRAME_COUNT), indent=1) + "\n",
        encoding="utf-8",
    )

    # 4) Copy original .ase source (for traceability / future re-export)
    if src_ase.is_file():
        shutil.copy2(src_ase, dst_ase_src_dir / "electric-slash.ase")

    print(f"sheet : {sheet_path}  ({frame_w * FRAME_COUNT}x{frame_h})")
    print(f"json  : {json_path}   ({FRAME_COUNT} frames @ {frame_w}x{frame_h})")
    print(f"ase   : {dst_ase_src_dir / 'electric-slash.ase'}")


if __name__ == "__main__":
    main()
