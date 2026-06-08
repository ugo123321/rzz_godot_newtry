#!/usr/bin/env python3
"""Copy upgrade-related VFX from sucai and generate pixel upgrade icons."""
from __future__ import annotations

import json
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUCAI = Path(r"D:\workspace\godot1\sucai\effects")
ASSETS = ROOT / "assets" / "effects"
ICONS = ROOT / "assets" / "icons" / "upgrades"

COPY_JOBS = [
    (
        SUCAI / "3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark-3",
        ASSETS / "3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark-3",
        "spirit_bomb frames",
    ),
    (
        SUCAI / "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/flame-loop",
        ASSETS / "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/flame-loop",
        "charge flame loop",
    ),
    (
        SUCAI / "6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash-e",
        ASSETS / "6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash-e",
        "blade whirl slash-e",
    ),
    (
        SUCAI / "6.GothicVania Magic Pack 6/Magic Pack 6/sprites/slash-e",
        ASSETS / "custom/laser-blast/sprites",
        "laser blast placeholder frames",
    ),
]


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError(path)
        f.read(4)
        if f.read(4) != b"IHDR":
            raise ValueError(path)
        w, h = struct.unpack(">II", f.read(8))
        return w, h


def copy_tree(src: Path, dst: Path) -> int:
    if not src.is_dir():
        print(f"  SKIP missing: {src}")
        return 0
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("*.import"))
    return len(list(dst.glob("*.png")))


def write_sequence_json(name: str, sprite_dir: Path, prefix: str) -> None:
    files = sorted(sprite_dir.glob(f"{prefix}*.png"), key=lambda p: p.stem)
    if not files:
        return
    fw, fh = png_size(files[0])
    frames = []
    for i, fp in enumerate(files):
        frames.append(
            {
                "filename": fp.name,
                "frame": {"x": i * fw, "y": 0, "w": fw, "h": fh},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": fw, "h": fh},
                "sourceSize": {"w": fw, "h": fh},
                "duration": 70,
            }
        )
    sheet_dir = sprite_dir.parent.parent / "spritesheets"
    sheet_dir.mkdir(parents=True, exist_ok=True)
    ase_dir = sprite_dir.parent.parent / "aseprite"
    ase_dir.mkdir(parents=True, exist_ok=True)
    meta = {
        "frames": frames,
        "meta": {
            "app": "https://www.aseprite.org/",
            "version": "1.3.12-x64",
            "image": f"../spritesheets/{name}.png",
            "format": "RGBA8888",
            "size": {"w": fw * len(files), "h": fh},
            "scale": "1",
        },
    }
    (ase_dir / f"{name}.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


def _px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def _rect(img, x, y, w, h, color):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            _px(img, xx, yy, color)


def _circle(img, cx, cy, r, color):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                _px(img, x, y, color)


def draw_icon(icon_id: str):
    from PIL import Image

    s = 48
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bg = (18, 22, 38, 255)
    _rect(img, 2, 2, 44, 44, bg)
    _rect(img, 4, 4, 40, 40, (28, 32, 52, 255))

    def fireball(cx, cy, r):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r
                if d > 1:
                    continue
                if d < 0.25:
                    c = (255, 248, 210, 255)
                elif d < 0.5:
                    c = (255, 180, 70, 255)
                elif d < 0.75:
                    c = (255, 110, 35, 255)
                else:
                    c = (180, 45, 18, 255)
                _px(img, x, y, c)

    drawers = {
        "luck": lambda: (_circle(img, 24, 22, 10, (120, 210, 255, 255)), _rect(img, 20, 30, 8, 10, (90, 160, 220, 255))),
        "multi_bullet": lambda: [fireball(16 + i * 8, 24, 5) for i in range(3)],
        "shuriken": lambda: [
            _rect(img, 22, 10, 4, 28, (200, 220, 255, 255)),
            _rect(img, 10, 22, 28, 4, (200, 220, 255, 255)),
            _rect(img, 14, 14, 6, 6, (140, 160, 200, 255)),
            _rect(img, 28, 14, 6, 6, (140, 160, 200, 255)),
            _rect(img, 14, 28, 6, 6, (140, 160, 200, 255)),
            _rect(img, 28, 28, 6, 6, (140, 160, 200, 255)),
        ],
        "multi_combo": lambda: (_rect(img, 18, 14, 12, 20, (255, 90, 30, 255)), _rect(img, 22, 10, 4, 6, (255, 220, 80, 255))),
        "healing_combo": lambda: (_circle(img, 24, 24, 12, (60, 180, 90, 255)), _rect(img, 22, 16, 4, 16, (230, 255, 230, 255))),
        "holy_shield": lambda: (_circle(img, 24, 24, 14, (120, 180, 255, 255)), _rect(img, 22, 12, 4, 24, (230, 240, 255, 255))),
        "vampire_bat": lambda: (
            _circle(img, 24, 22, 8, (80, 50, 120, 255)),
            _rect(img, 10, 18, 8, 4, (60, 40, 90, 255)),
            _rect(img, 30, 18, 8, 4, (60, 40, 90, 255)),
        ),
        "lightning_chain": lambda: [_rect(img, 20 + (i % 2) * 4, 12 + i * 5, 4, 6, (180, 230, 255, 255)) for i in range(5)],
        "water_tornado": lambda: (_circle(img, 24, 26, 13, (70, 180, 255, 180)), _circle(img, 24, 20, 8, (180, 240, 255, 255))),
        "black_hole": lambda: (_circle(img, 24, 24, 14, (40, 10, 70, 255)), _circle(img, 24, 24, 8, (10, 0, 20, 255)), _circle(img, 24, 24, 3, (180, 120, 255, 255))),
        "blade_whirl": lambda: (_circle(img, 24, 24, 14, (255, 220, 80, 120)), _rect(img, 8, 22, 32, 4, (255, 240, 120, 255))),
        "great_fireball": lambda: fireball(24, 24, 16),
        "heavenly_thunder": lambda: (_rect(img, 22, 8, 4, 32, (255, 240, 120, 255)), _rect(img, 16, 20, 16, 4, (255, 240, 120, 255))),
        "wild_wolf": lambda: (_circle(img, 24, 24, 12, (140, 140, 160, 255)), _rect(img, 14, 14, 6, 6, (220, 220, 230, 255)), _rect(img, 28, 14, 6, 6, (220, 220, 230, 255))),
        "wild_bull": lambda: (_rect(img, 14, 20, 20, 12, (120, 90, 70, 255)), _rect(img, 10, 16, 6, 8, (160, 120, 90, 255)), _rect(img, 32, 16, 6, 8, (160, 120, 90, 255))),
        "divine_god": lambda: (_circle(img, 24, 20, 10, (255, 230, 140, 255)), _rect(img, 18, 28, 12, 14, (220, 200, 255, 255))),
        "nurturing_heart": lambda: (
            _circle(img, 18, 22, 5, (255, 90, 120, 255)),
            _circle(img, 30, 22, 5, (255, 90, 120, 255)),
            _rect(img, 20, 26, 8, 10, (255, 90, 120, 255)),
        ),
        "spirit_bomb": lambda: (_circle(img, 24, 24, 14, (180, 120, 255, 200)), _circle(img, 24, 24, 8, (240, 220, 255, 255))),
        "bounce_bullet": lambda: (fireball(16, 24, 6), fireball(32, 20, 6), _rect(img, 20, 22, 12, 2, (255, 200, 80, 255))),
        "four_leaf_clover": lambda: [_circle(img, x, y, 5, (70, 200, 80, 255)) for x, y in ((24, 16), (16, 24), (32, 24), (24, 32))],
        "godspeed": lambda: (_rect(img, 14, 24, 20, 4, (255, 240, 120, 255)), _rect(img, 30, 20, 8, 4, (255, 240, 120, 200)), _rect(img, 30, 28, 8, 4, (255, 240, 120, 200))),
        "laser_blast": lambda: (_rect(img, 8, 22, 28, 4, (255, 80, 180, 255)), _rect(img, 34, 20, 6, 8, (255, 200, 240, 255))),
        "charge_strike": lambda: (_circle(img, 24, 30, 8, (255, 120, 30, 180)), _rect(img, 20, 12, 8, 18, (255, 200, 120, 255))),
        "abyss_explosion": lambda: (_circle(img, 24, 24, 14, (255, 80, 30, 255)), _circle(img, 24, 24, 8, (255, 220, 120, 255))),
        "mirror_bullet": lambda: (fireball(16, 24, 6), fireball(32, 24, 6), _rect(img, 22, 22, 4, 4, (255, 220, 120, 255))),
        "pierce": lambda: (fireball(24, 24, 6), _rect(img, 8, 22, 32, 4, (255, 180, 60, 255))),
        "super_mushroom": lambda: (_rect(img, 16, 24, 16, 10, (240, 220, 180, 255)), _rect(img, 12, 14, 24, 12, (220, 60, 70, 255)), _circle(img, 20, 20, 2, (255, 255, 255, 255)), _circle(img, 28, 20, 2, (255, 255, 255, 255))),
    }
    fn = drawers.get(icon_id)
    if fn:
        fn()
    else:
        _rect(img, 18, 18, 12, 12, (255, 255, 255, 255))
    return img


def generate_icons(ids: list[str]) -> None:
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        print("Pillow not installed; skip icon generation")
        return
    ICONS.mkdir(parents=True, exist_ok=True)
    for icon_id in ids:
        out = ICONS / f"{icon_id}.png"
        draw_icon(icon_id).save(out)
        print(f"  icon: {out.name}")


def _run_copy_explosion_c() -> None:
    import importlib.util

    script = ROOT / "tools" / "copy_explosion_c.py"
    spec = importlib.util.spec_from_file_location("copy_explosion_c", script)
    if spec is None or spec.loader is None:
        print(f"  SKIP explosion-c: cannot load {script}")
        return
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.main()


def main() -> None:
    print("Copying VFX...")
    _run_copy_explosion_c()
    for src, dst, label in COPY_JOBS:
        n = copy_tree(src, dst)
        print(f"  {label}: {n} png -> {dst.relative_to(ROOT)}")

    spirit_dir = ASSETS / "3.Gothicvania Magic Pack N3/Magic Pack 3 files/sprites/small-spark-3"
    if spirit_dir.is_dir():
        write_sequence_json("small-spark-3", spirit_dir, "small-spark-3-preview")

    flame_dir = ASSETS / "2.Gothicvania Magic Pack N2 - Fire/Magic Pack Fire files/sprites/flame-loop"
    if flame_dir.is_dir():
        write_sequence_json("flame-loop", flame_dir, "flame")

    explosion_dir = ASSETS / "9.Warped Explosion Pack 5/Explosions Pack 5 Files/sprites/explosion-c"
    if explosion_dir.is_dir() and any(explosion_dir.glob("explosion-c*.png")):
        pass  # json + sheet already written by copy_explosion_c.py
    elif explosion_dir.is_dir():
        write_sequence_json("explosion-c", explosion_dir, "explosion-c")

    icon_ids = [
        "luck", "multi_bullet", "shuriken", "multi_combo", "healing_combo", "holy_shield",
        "vampire_bat", "lightning_chain", "water_tornado", "black_hole", "blade_whirl",
        "great_fireball", "heavenly_thunder", "wild_wolf", "wild_bull", "divine_god",
        "nurturing_heart", "spirit_bomb", "bounce_bullet", "four_leaf_clover", "godspeed",
        "laser_blast", "charge_strike", "abyss_explosion", "mirror_bullet", "pierce",
        "super_mushroom",
    ]
    print("Generating icons...")
    generate_icons(icon_ids)
    print("Done.")


if __name__ == "__main__":
    main()
