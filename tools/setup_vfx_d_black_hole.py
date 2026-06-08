#!/usr/bin/env python3
"""Copy vfx-d assets and generate Aseprite JSON for black hole (first 9 frames)."""
import json
import shutil
import struct
from pathlib import Path

SRC_ROOT = Path(r"D:\workspace\godot1\sucai\effects\10.GothicVania Magic Pack 7\Magic Pack 7 files")
DST_ROOT = Path(r"D:\workspace\godot1\rzz_godot\assets\effects\10.GothicVania Magic Pack 7\Magic Pack 7 files")
FRAME_COUNT = 9
FPS = 12.0
DURATION = 70


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Not a PNG: {path}")
        _length = struct.unpack(">I", f.read(4))[0]
        chunk = f.read(4)
        if chunk != b"IHDR":
            raise ValueError(f"Missing IHDR: {path}")
        w, h = struct.unpack(">II", f.read(8))
        return w, h


def build_json(frame_w: int, frame_h: int, count: int) -> dict:
    frames = []
    for i in range(count):
        frames.append(
            {
                "filename": f"vfx-d {i}.ase",
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
            "image": "../spritesheets/vfx-d.png",
            "format": "RGBA8888",
            "size": {"w": frame_w * count, "h": frame_h},
            "scale": "1",
        },
    }


def main() -> None:
    src_sheet = SRC_ROOT / "spritesheets" / "vfx-d.png"
    src_sprites = SRC_ROOT / "sprites" / "vfx-d"
    if not src_sheet.is_file():
        raise SystemExit(f"Missing source sheet: {src_sheet}")

    sheet_w, sheet_h = png_size(src_sheet)
    sample = src_sprites / "vfx-d1.png"
    if sample.is_file():
        frame_w, frame_h = png_size(sample)
    else:
        frame_w, frame_h = sheet_h, sheet_h
    total_frames = sheet_w // max(1, frame_w)
    if total_frames <= 0:
        total_frames = max(FRAME_COUNT, 1)

    use_count = min(FRAME_COUNT, total_frames)

    dst_ase = DST_ROOT / "aseprite"
    dst_sheet_dir = DST_ROOT / "spritesheets"
    dst_sprite_dir = DST_ROOT / "sprites" / "vfx-d"
    for d in (dst_ase, dst_sheet_dir, dst_sprite_dir):
        d.mkdir(parents=True, exist_ok=True)

    # Copy first 9 individual frames as fallback.
    for i in range(1, use_count + 1):
        src = src_sprites / f"vfx-d{i}.png"
        if src.is_file():
            shutil.copy2(src, dst_sprite_dir / f"vfx-d{i}.png")

    # Copy spritesheet (full sheet; JSON only references first 9 frames).
    shutil.copy2(src_sheet, dst_sheet_dir / "vfx-d.png")

    json_path = dst_ase / "vfx-d.json"
    json_path.write_text(
        json.dumps(build_json(frame_w, frame_h, use_count), indent=1) + "\n",
        encoding="utf-8",
    )
    print(f"Created {json_path}")
    print(f"Frames: {use_count}, size: {frame_w}x{frame_h}, total in sheet: {total_frames}")


if __name__ == "__main__":
    main()
