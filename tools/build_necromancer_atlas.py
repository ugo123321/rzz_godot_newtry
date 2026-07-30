"""生成 Necromancer 角色图集（atlas json + 合并 sheet png）。
读取 assets/Characters/Characters(100x100)/Necromancer/Necromancer/ 下的条带 PNG，
按"每动画一行"拼成单张 sheet，并输出 Aseprite 导出格式 json 供
EffectHelper._load_character_atlas_frames 加载。

运行：python tools/build_necromancer_atlas.py
产物：
  assets/Characters/atlases/sheets/Necromancer.png
  assets/Characters/atlases/json/Necromancer.json
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "assets/Characters/Characters(100x100)/Necromancer/Necromancer"
OUT_SHEET = ROOT / "assets/Characters/atlases/sheets/Necromancer.png"
OUT_JSON = ROOT / "assets/Characters/atlases/json/Necromancer.json"

FRAME = 100  # 100x100

# (tag_name, 源文件名, 帧数)
ANIMS = [
    ("Idle",     "Necromancer_Idle.png",     6),
    ("Walk",     "Necromancer_Walk.png",     6),
    ("Attack",   "Necromancer_Attack02.png", 10),
    ("Hurt",     "Necromancer_Hurt.png",     4),
    ("Death",    "Necromancer_DEATH.png",     9),
    ("Attack01", "Necromancer_Attack01.png",  9),
]


def main() -> int:
    if not SRC_DIR.is_dir():
        raise SystemExit(f"源目录不存在: {SRC_DIR}")

    # 1) 读每张条带，按声明的帧数切片（每帧 FRAME 宽）
    rows: list[list[Image.Image]] = []
    for tag, fname, count in ANIMS:
        path = SRC_DIR / fname
        if not path.exists():
            raise SystemExit(f"缺少素材: {path}")
        sheet = Image.open(path).convert("RGBA")
        if sheet.height < FRAME:
            raise SystemExit(f"{fname} 高度 {sheet.height} < {FRAME}")
        frames: list[Image.Image] = []
        for i in range(count):
            x = i * FRAME
            if x + FRAME > sheet.width:
                raise SystemExit(f"{fname} 第 {i} 帧越界 (sheet宽={sheet.width})")
            frames.append(sheet.crop((x, 0, x + FRAME, FRAME)))
        rows.append(frames)

    # 2) 拼成单张 sheet：每动画一行，宽 = 最大帧数 * FRAME
    cols = max(len(r) for r in rows)
    sheet_w = cols * FRAME
    sheet_h = len(rows) * FRAME
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    frame_list: list[dict] = []  # 行优先顺序的 Aseprite frame 描述
    frame_tags: list[dict] = []
    idx = 0
    for row_idx, row in enumerate(rows):
        tag_name = ANIMS[row_idx][0]
        start_idx = idx
        for col_idx, frame_img in enumerate(row):
            x = col_idx * FRAME
            y = row_idx * FRAME
            sheet.paste(frame_img, (x, y))
            frame_list.append({
                "filename": f"Necromancer {idx}.aseprite",
                "frame": {"x": x, "y": y, "w": FRAME, "h": FRAME},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": FRAME, "h": FRAME},
                "sourceSize": {"w": FRAME, "h": FRAME},
                "duration": 100,
            })
            idx += 1
        frame_tags.append({"name": tag_name, "from": start_idx, "to": idx - 1})

    OUT_SHEET.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_SHEET)

    doc = {
        "frames": frame_list,
        "meta": {
            "image": OUT_SHEET.name,
            "size": {"w": sheet_w, "h": sheet_h},
            "frameTags": frame_tags,
        },
    }
    OUT_JSON.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"sheet: {OUT_SHEET} ({sheet_w}x{sheet_h})")
    print(f"json : {OUT_JSON} ({len(frame_list)} frames, {len(frame_tags)} tags)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
