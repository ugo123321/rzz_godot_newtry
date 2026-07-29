#!/usr/bin/env python3
"""把 bat 的 strip PNG 拼成单张 atlas sheet + 生成 Aseprite-hash 格式 JSON。
运行：python tools/build_bat_atlas.py
产物：assets/Characters/atlases/sheets/Bat.png + atlases/json/Bat.json
被 effect_helper._load_character_atlas_frames 加载，与其他怪一致。
"""
from __future__ import annotations
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BAT_DIR = ROOT / "assets/Characters/Characters(100x100)/Bat/Bat"
SHEET_DIR = ROOT / "assets/Characters/atlases/sheets"
JSON_DIR = ROOT / "assets/Characters/atlases/json"
FRAME = 100  # 每帧 100x100

# strip 文件名 + 对应 tag 名 + 起始帧索引 + 帧数
# tag 顺序决定 frames 数组顺序；Walk 复用 Flying 第一帧，故 Flying 排最前。
STRIPS = [
    ("Bat_Flying.png", "Walk", 0, 6),     # 6 帧飞 → Walk
    ("Bat_Attack01.png", "Attack01", 6, 6),
    ("Bat_Attack02.png", "Attack", 12, 7),
    ("Bat_Hurt.png", "Hurt", 19, 4),
    ("Bat_Death.png", "Death", 23, 4),
]
IDLE_FRAME_INDEX = 0

def main() -> None:
    SHEET_DIR.mkdir(parents=True, exist_ok=True)
    JSON_DIR.mkdir(parents=True, exist_ok=True)

    frames_meta = {}
    for fname, _tag, start, count in STRIPS:
        for i in range(count):
            frames_meta[start + i] = (fname, i)
    total = max(frames_meta) + 1  # 27

    cols = 9
    rows = (total + cols - 1) // cols
    sheet_w = cols * FRAME
    sheet_h = rows * FRAME
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))

    frames_arr = []
    for idx in range(total):
        fname, sub = frames_meta[idx]
        strip = Image.open(BAT_DIR / fname).convert("RGBA")
        cell = strip.crop((sub * FRAME, 0, (sub + 1) * FRAME, FRAME))
        cx = (idx % cols) * FRAME
        cy = (idx // cols) * FRAME
        sheet.paste(cell, (cx, cy))
        frames_arr.append({
            "filename": "Bat %d.aseprite" % idx,
            "frame": {"x": cx, "y": cy, "w": FRAME, "h": FRAME},
            "rotated": False,
            "trimmed": False,
            "spriteSourceSize": {"x": 0, "y": 0, "w": FRAME, "h": FRAME},
            "sourceSize": {"w": FRAME, "h": FRAME},
            "duration": 100,
        })

    sheet_path = SHEET_DIR / "Bat.png"
    sheet.save(sheet_path)
    print("sheet:", sheet_path, sheet.size)

    tags = [
        {"name": "Idle", "from": 0, "to": 0, "direction": "forward", "color": "#000000ff"},
        {"name": "Walk", "from": 0, "to": 5, "direction": "forward", "color": "#000000ff"},
        {"name": "Attack01", "from": 6, "to": 11, "direction": "forward", "color": "#000000ff"},
        {"name": "Attack", "from": 12, "to": 18, "direction": "forward", "color": "#000000ff"},
        {"name": "Hurt", "from": 19, "to": 22, "direction": "forward", "color": "#000000ff"},
        {"name": "Death", "from": 23, "to": 26, "direction": "forward", "color": "#000000ff"},
    ]
    data = {
        "frames": frames_arr,
        "meta": {
            "app": "https://www.aseprite.org/",
            "version": "1.3.12-x64",
            "image": "../sheets/Bat.png",
            "format": "RGBA8888",
            "size": {"w": sheet_w, "h": sheet_h},
            "scale": "1",
            "frameTags": tags,
        },
    }
    json_path = JSON_DIR / "Bat.json"
    json_path.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    print("json:", json_path)

if __name__ == "__main__":
    main()
