#!/usr/bin/env python3
"""Migrate Cursor chat history from renzhezhan to rzz_godot."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path

OLD_PATH = Path(r"D:\workspace\godot1\renzhezhan")
NEW_PATH = Path(r"D:\workspace\godot1\rzz_godot")

APPDATA = Path(os.environ["APPDATA"]) / "Cursor" / "User"
WORKSPACE_ROOT = APPDATA / "workspaceStorage"
GLOBAL_STORAGE = APPDATA / "globalStorage" / "storage.json"
CURSOR_PROJECTS = Path.home() / ".cursor" / "projects"

OLD_WS = "c2fe870add59e715286052a773fdba25"
NEW_WS = "570311389e91a68247f32a94d9c45429"
OLD_PROJECT_DIR = "d-workspace-godot1-renzhezhan"
NEW_PROJECT_DIR = "d-workspace-godot1-rzz-godot"


def workspace_hash(path: Path) -> str:
    resolved = path.resolve()
    st = resolved.stat()
    birth_ms = int(st.st_ctime * 1000)
    payload = str(resolved).lower() + str(birth_ms)
    return hashlib.md5(payload.encode()).hexdigest()


def replace_bytes(data: bytes) -> bytes:
    replacements = [
        (b"D:\\workspace\\godot1\\renzhezhan", b"D:\\workspace\\godot1\\rzz_godot"),
        (b"d:\\workspace\\godot1\\renzhezhan", b"d:\\workspace\\godot1\\rzz_godot"),
        (b"D:/workspace/godot1/renzhezhan", b"D:/workspace/godot1/rzz_godot"),
        (b"d:/workspace/godot1/renzhezhan", b"d:/workspace/godot1/rzz_godot"),
        (b"file:///d%3A/workspace/godot1/renzhezhan", b"file:///d%3A/workspace/godot1/rzz_godot"),
        (OLD_WS.encode(), NEW_WS.encode()),
        (OLD_PROJECT_DIR.encode(), NEW_PROJECT_DIR.encode()),
    ]
    for old, new in replacements:
        data = data.replace(old, new)
    return data


def replace_text(text: str) -> str:
    return replace_bytes(text.encode()).decode()


def checkpoint_sqlite(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        conn.commit()
    finally:
        conn.close()


def rewrite_sqlite(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    try:
        tables = [
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        ]
        for table in tables:
            cols = [row[1] for row in conn.execute(f"PRAGMA table_info({table})")]
            if "key" in cols and "value" in cols:
                rows = conn.execute(f"SELECT rowid, key, value FROM {table}").fetchall()
                for rowid, key, value in rows:
                    if isinstance(value, memoryview):
                        value = value.tobytes()
                    if isinstance(value, bytes):
                        new_value = replace_bytes(value)
                    elif isinstance(value, str):
                        new_value = replace_text(value)
                    else:
                        continue
                    if new_value != value:
                        conn.execute(
                            f"UPDATE {table} SET value=? WHERE rowid=?",
                            (new_value, rowid),
                        )
            elif len(cols) == 2:
                rows = conn.execute(f"SELECT rowid, * FROM {table}").fetchall()
                for row in rows:
                    rowid = row[0]
                    updated = False
                    new_row = list(row[1:])
                    for idx, value in enumerate(new_row):
                        if isinstance(value, memoryview):
                            value = value.tobytes()
                        if isinstance(value, bytes):
                            new_value = replace_bytes(value)
                        elif isinstance(value, str):
                            new_value = replace_text(value)
                        else:
                            continue
                        if new_value != value:
                            new_row[idx] = new_value
                            updated = True
                    if updated:
                        placeholders = ", ".join("?" for _ in new_row)
                        col_names = ", ".join(cols)
                        conn.execute(
                            f"UPDATE {table} SET ({col_names})=({placeholders}) WHERE rowid=?",
                            (*new_row, rowid),
                        )
        conn.commit()
    finally:
        conn.close()


def update_json_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    new_text = replace_text(text)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8")


def main() -> None:
    assert OLD_PATH.exists(), f"Missing old path: {OLD_PATH}"
    assert NEW_PATH.exists(), f"Missing new path: {NEW_PATH}"

    computed = workspace_hash(NEW_PATH)
    if computed != NEW_WS:
        raise SystemExit(f"Unexpected new workspace hash: {computed} != {NEW_WS}")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root = NEW_PATH / "tools" / f"cursor-migration-backup-{stamp}"
    backup_root.mkdir(parents=True, exist_ok=True)

    old_ws_dir = WORKSPACE_ROOT / OLD_WS
    new_ws_dir = WORKSPACE_ROOT / NEW_WS
    old_proj_dir = CURSOR_PROJECTS / OLD_PROJECT_DIR
    new_proj_dir = CURSOR_PROJECTS / NEW_PROJECT_DIR

    print(f"Backup -> {backup_root}")

    if old_ws_dir.exists():
        shutil.copytree(old_ws_dir, backup_root / "workspaceStorage-old", dirs_exist_ok=True)
    if GLOBAL_STORAGE.exists():
        shutil.copy2(GLOBAL_STORAGE, backup_root / "storage.json")
    if old_proj_dir.exists():
        shutil.copytree(old_proj_dir, backup_root / "projects-old", dirs_exist_ok=True)

    if new_ws_dir.exists():
        shutil.copytree(new_ws_dir, backup_root / "workspaceStorage-new-existing", dirs_exist_ok=True)
        shutil.rmtree(new_ws_dir)

    print(f"Copy workspaceStorage {OLD_WS} -> {NEW_WS}")
    shutil.copytree(old_ws_dir, new_ws_dir)

    workspace_json = new_ws_dir / "workspace.json"
    workspace_json.write_text(
        json.dumps({"folder": "file:///d%3A/workspace/godot1/rzz_godot"}, indent=2) + "\n",
        encoding="utf-8",
    )

    db_path = new_ws_dir / "state.vscdb"
    for suffix in ("-wal", "-shm"):
        sidecar = new_ws_dir / f"state.vscdb{suffix}"
        if sidecar.exists():
            sidecar.unlink()

    checkpoint_sqlite(db_path)
    rewrite_sqlite(db_path)

    if GLOBAL_STORAGE.exists():
        update_json_file(GLOBAL_STORAGE)

    global_db = APPDATA / "globalStorage" / "state.vscdb"
    if global_db.exists():
        rewrite_sqlite(global_db)

    if new_proj_dir.exists():
        shutil.copytree(new_proj_dir, backup_root / "projects-new-existing", dirs_exist_ok=True)
        shutil.rmtree(new_proj_dir)

    if old_proj_dir.exists():
        print(f"Copy .cursor/projects {OLD_PROJECT_DIR} -> {NEW_PROJECT_DIR}")
        shutil.copytree(old_proj_dir, new_proj_dir)
    else:
        new_proj_dir.mkdir(parents=True, exist_ok=True)

    print("Done.")
    print("Next steps:")
    print("  1. Completely quit Cursor (not just reload)")
    print("  2. Open folder: D:\\workspace\\godot1\\rzz_godot")
    print("  3. Check chat sidebar for previous conversations")


if __name__ == "__main__":
    main()
