#!/usr/bin/env python3
"""Re-apply Cursor global storage path fix after fully quitting Cursor."""
from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path

APPDATA = Path(os.environ["APPDATA"]) / "Cursor" / "User"
GLOBAL_STORAGE = APPDATA / "globalStorage" / "storage.json"
OLD = "renzhezhan"
NEW = "rzz_godot"
OLD_WS = "c2fe870add59e715286052a773fdba25"
NEW_WS = "570311389e91a68247f32a94d9c45429"


def replace_text(text: str) -> str:
    return (
        text.replace(OLD, NEW)
        .replace(OLD_WS, NEW_WS)
        .replace("d-workspace-godot1-renzhezhan", "d-workspace-godot1-rzz-godot")
    )


def main() -> None:
    text = GLOBAL_STORAGE.read_text(encoding="utf-8")
    new_text = replace_text(text)
    if new_text != text:
        GLOBAL_STORAGE.write_text(new_text, encoding="utf-8")
        print("Updated storage.json")

    global_db = APPDATA / "globalStorage" / "state.vscdb"
    if global_db.exists():
        conn = sqlite3.connect(global_db)
        try:
            rows = conn.execute("SELECT rowid, key, value FROM ItemTable").fetchall()
            changed = 0
            for rowid, key, value in rows:
                if not isinstance(value, str):
                    continue
                new_value = replace_text(value)
                if new_value != value:
                    conn.execute(
                        "UPDATE ItemTable SET value=? WHERE rowid=?",
                        (new_value, rowid),
                    )
                    changed += 1
            conn.commit()
            print(f"Updated {changed} rows in global state.vscdb")
        finally:
            conn.close()

    print("Done. Now open D:\\workspace\\godot1\\rzz_godot in Cursor.")


if __name__ == "__main__":
    main()
