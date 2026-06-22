#!/usr/bin/env python3
"""Excel -> JSON export for Godot runtime.

Normal usage (after editing Excel):
    python tools/export_config.py

First-time / reset Excel templates from defaults:
    python tools/export_config.py --init-excel
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill

ROOT = Path(__file__).resolve().parents[1]
EXCEL_DIR = ROOT / "config" / "excel"
JSON_DIR = ROOT / "config" / "json"

HEADER_FILL = PatternFill("solid", fgColor="4472C4")
HEADER_FONT = Font(color="FFFFFF", bold=True)

EXCEL_SHEETS = [
    "chapters",
    "stages",
    "monsters",
    "player",
    "upgrades",
    "upgrade_fx",
    "game_tuning",
    "asset_mapping",
    "rewards_v6",
]

# rewards_v6: 99 项 roguelike 奖励规范化表（22 列，schema 详见 plan）。
# 数据由 tools/build_rewards_v6.py 生成；JSON 为权威源，不在 init-excel 写默认行。
REWARDS_V6_HEADERS = [
    "id", "name_cn", "group", "rarity", "icon", "desc_cn",
    "max_level", "pool_weight", "once_per_run", "once_per_chapter",
    "dmg_layer", "secondary_layer", "element", "category",
    "apply_type", "apply_value", "weapon_mult",
    "trigger", "cooldown", "extra_params",
    "special_rule", "notes",
]
REWARDS_V6_ROWS: list[list] = []  # 由 build_rewards_v6.py 填充，不在此处写死

CHAPTER_HEADERS = [
    "chapter_id", "chapter_name", "stages_per_chapter", "description",
]
CHAPTER_ROWS = [
    [1, "第一章", 4, "入门章节"],
    [2, "第二章", 4, "Boss 与高强度混合战"],
]

STAGE_HEADERS = [
    "stage_index", "chapter_id", "stage_in_chapter", "display_name",
    "room_type", "reward_rooms",
    "normal", "elite", "shield", "berserker", "splitter", "archer", "fire_mage",
    "shotgun", "cross_shooter", "bounce_slime", "boss_id",
]
STAGE_ROWS = [
    [0, 1, 1, "第1关", "", "", 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, ""],
    [1, 1, 2, "第2关", "", "", 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, ""],
    [2, 1, 3, "第3关", "", "", 10, 0, 0, 0, 0, 6, 0, 0, 0, 0, ""],
    [3, 1, 4, "第4关", "", "", 10, 0, 0, 0, 0, 8, 0, 0, 0, 0, ""],
    [4, 2, 1, "第5关", "reward", "wheel", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ""],
    [5, 2, 2, "第6关", "", "", 5, 4, 0, 0, 0, 4, 0, 0, 0, 0, ""],
    [6, 2, 3, "第7关", "", "", 5, 4, 0, 0, 0, 5, 0, 0, 0, 0, ""],
    [7, 2, 4, "第8关", "", "", 4, 4, 0, 0, 0, 4, 3, 0, 0, 0, ""],
    [8, 2, 5, "第9关", "", "", 4, 3, 3, 0, 0, 3, 3, 0, 0, 0, ""],
    [9, 2, 6, "第10关", "", "", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "lancer_knight"],
]

MONSTER_HEADERS = [
    "kind_id", "spawn_order", "unlock_at_stage", "name_cn", "hp", "def", "attack", "attack_interval", "size", "speed",
    "color_hex", "grade", "can_move", "attack_range", "arrow_speed", "ranged",
    "ki_drain_on_hit", "max_split_tier", "split_count", "exp_reward",
    "character_folder", "sprite_prefix", "projectile_folder",
    "attack_pattern", "projectile_effect", "spread_count", "spread_angle_deg",
    "bounce_count", "sprite_tint_hex",
]
MONSTER_ROWS = [
    ["NORMAL", 1, 1, "普通怪", 100, 4, 10, 1.15, 13, 19, "#526078", "B", 1, 0, 0, 0, 0, 0, 0, 6, "Skeleton", "Skeleton", "", "", "", 5, 50, 1, ""],
    ["ARCHER", 2, 3, "射箭怪", 95, 3, 12, 1.35, 12, 17, "#6a8a5a", "B", 1, 215, 85, 1, 0, 0, 0, 7, "Archer", "Archer", "Arrow(projectile)", "", "", 5, 50, 1, ""],
    ["ELITE", 3, 5, "高级怪", 135, 6, 14, 1.05, 14, 21, "#8a6aa8", "B+", 1, 0, 0, 0, 0, 0, 0, 10, "Elite Orc", "Elite Orc", "", "", "", 5, 50, 1, ""],
    ["FIRE_MAGE", 4, 7, "火焰法师", 90, 2, 16, 2.4, 12, 15, "#501818", "B", 1, 250, 0, 1, 0, 0, 0, 8, "Wizard", "Wizard", "Magic(projectile)", "", "", 5, 50, 1, ""],
    ["SHIELD", 5, 9, "盾牌怪", 150, 5, 12, 1.25, 15, 16, "#5f7a88", "B+", 1, 0, 0, 0, 0, 0, 0, 8, "Knight", "Knight", "", "", "", 5, 50, 1, ""],
    ["CROSS_SHOOTER", 6, 11, "十字子弹怪", 80, 4, 12, 1.6, 12, 15, "#8a7898", "S/A/B/A", 1, -1, 75, 1, 0, 0, 0, 3, "Priest", "Priest", "Magic(projectile)", "cross", "enemy_cross_magic", 5, 50, 1, ""],
    ["BERSERKER", 7, 13, "狂战士", 90, 2, 18, 0.85, 14, 26, "#b85a4a", "C/B", 1, 0, 0, 0, 10, 0, 0, 4, "Armored Axeman", "Armored Axeman", "", "", "", 5, 50, 1, ""],
    ["SHOTGUN", 8, 15, "霰弹怪", 80, 4, 12, 1.5, 12, 16, "#6a7078", "S/A/B/A", 1, 215, 85, 1, 0, 0, 0, 3, "Skeleton Archer", "Skeleton Archer", "Arrow(projectile)", "spread", "enemy_shotgun_arrow", 5, 50, 1, ""],
    ["SPLITTER", 9, 17, "分裂怪", 70, 2, 8, 1.2, 18, 14, "#7b9f5a", "A+/C/C", 1, 0, 0, 0, 0, 3, 2, 3, "Slime", "Slime", "", "", "", 5, 50, 1, ""],
    ["BOUNCE_SLIME", 10, 19, "反弹子弹怪", 80, 4, 12, 1.55, 12, 14, "#b84040", "S/A/B/A", 1, -1, 70, 1, 0, 0, 0, 3, "Slime", "Slime", "", "bounce", "enemy_bounce_blob", 5, 50, 1, "#ff6868"],
]

PLAYER_HEADERS = ["key", "value", "description"]
PLAYER_ROWS = [
    ["base_attack", 95, "基础攻击力"],
    ["base_hp", 100, "基础生命"],
    ["base_ki", 234, "基础气力上限"],
    ["base_crit_rate", 0.08, "暴击率"],
    ["base_crit_damage", 1.6, "暴击伤害倍率"],
    ["attack_speed", 2300, "路径冲刺速度 px/s"],
    ["hitbox_radius", 12, "碰撞半径"],
    ["trigger_radius_ratio", 0.06, "触发圈相对屏宽比例"],
    ["trigger_radius_min", 30, "触发圈最小半径"],
    ["trigger_ring_fade_in", 0.35, "攻击后触发圈渐显时长(s)"],
    ["ki_per_pixel", 0.18, "划线每像素消耗气力"],
    ["basic_attack_speed", 2.0, "普攻攻速(次/秒，决定普攻子弹频率)"],
    ["ki_regen_speed", 135, "气力回复速度(点/秒)"],
    ["combo_damage_bonus", 0.01, "每连击伤害加成"],
    ["invincible_time", 0.45, "受击无敌时间"],
    ["auto_bullet_damage_mult", 0.20, "普攻子弹伤害倍率"],
    ["auto_bullet_speed", 420, "普攻子弹速度"],
    ["auto_bullet_life", 0.9, "普攻子弹存活时间（已弃用：当前由 auto_bullet_range 控制飞行距离，保留仅供绘制兜底）"],
    ["auto_bullet_range", 378, "普攻子弹有效射程(px)：怪进入此距离才开火，子弹飞行此距离后消失"],
    ["auto_bullet_pierce_range_mul", 0.85, "穿透子弹攻击距离倍率(相对 auto_bullet_range)"],
    ["character_folder", "Swordsman", "主角素材文件夹"],
    ["sprite_prefix", "Swordsman", "主角精灵前缀"],
    ["sprite_scale", 2, "显示缩放(100px素材，2=200px显示)"],
]

UPGRADE_FX_HEADERS = [
    "rarity", "name_cn", "chance", "color_hex", "overlay", "edge_glow", "card_glow",
    "shimmer", "pulse", "spark_count", "rays",
]
UPGRADE_FX_ROWS = [
    ["white", "普通", 0, "#d8d8d8", 0.76, 0, 0.12, 0, 0, 0, 0],
    ["blue", "稀有", 0.4, "#58a8ff", 0.8, 0.28, 0.32, 1, 0, 6, 0],
    ["purple", "史诗", 0.4, "#b070ff", 0.84, 0.48, 0.5, 1, 1, 12, 0],
    ["orange", "传奇", 0.2, "#ff9830", 0.88, 0.78, 0.85, 1, 1, 22, 1],
]

TUNING_HEADERS = ["key", "value", "description"]
TUNING_ROWS = [
    ["logical_width", 390, "逻辑宽度"],
    ["logical_height", 700, "逻辑高度"],
    ["unit_scale", 1.3, "单位缩放"],
    ["camera_zoom", 1.0, "战斗镜头缩放(1=正常，勿随意改大)"],
    ["monster_sprite_scale", 2, "怪物显示缩放"],
    ["bullet_time_scale", 0.14, "子弹时间缩放"],
    ["bullet_time_dim_alpha", 0.42, "子弹时间暗化"],
    ["stages_per_chapter", 4, "每章关卡数"],
    ["stage_hp_growth", 1.2, "关卡HP缩放幂次"],
    ["stage_def_growth", 1.1, "关卡DEF缩放幂次"],
    ["stage_atk_growth", 1.12, "关卡攻击缩放幂次"],
    ["stage_monster_base", 8, "第1关怪物总数（stages表为权威）"],
    ["stage_monster_per_stage", 1, "每过一关怪物总数+1"],
    ["stage_type_unlock_interval", 2, "每N关解锁下一种怪物"],
    ["stage_monster_scale", 1.3, "关卡怪物数量缩放(已弃用)"],
    ["stage_count_mul", 0.666667, "怪物数量乘数(已弃用)"],
    ["shield_count_mul", 0.333333, "盾牌怪数量乘数(已弃用)"],
    ["exp_base_to_level", 100, "升级所需基础经验"],
    ["exp_growth", 1.22, "升级经验增长"],
    ["terrain_folder", "Terrain", "地形素材目录"],
    ["ui_folder", "ui", "UI素材目录"],
    ["effects_folder", "effects", "特效素材目录"],
    ["fire_pillar_radius", 60, "火柱半径"],
    ["fire_pillar_warning_time", 1.1, "火柱预警时间"],
    ["fire_pillar_active_time", 0.5, "火柱持续时间"],
    ["fire_pillar_fade_time", 0.3, "火柱淡出时间"],
    ["stage_intro_slide_in", 0.38, "关卡 intro 滑入时长"],
    ["stage_intro_hold", 0.85, "关卡 intro 停留时长"],
    ["stage_intro_slide_out", 0.38, "关卡 intro 滑出时长"],
    ["stage_intro_sakura_extra", 0.8, "intro 樱花额外停留"],
    ["stage_clear_flash_duration", 1.1, "过关闪白时长"],
    ["stage_fail_label_duration", 1.2, "失败字幕时长"],
    ["stage_fail_overlay_fade", 0.65, "失败遮罩淡入时长"],
    ["fail_death_windup", 0.3, "失败动画蓄力"],
    ["fail_death_spear_stagger", 0.065, "失败投矛错峰"],
    ["fail_death_spear_speed", 640, "失败投矛速度"],
    ["fail_death_impact_pause", 0.24, "失败插矛停顿"],
    ["fail_death_duration", 0.9, "失败倒地时长"],
    ["fail_death_playback_speed", 2.0, "失败动画加速"],
    ["combat_first_hit_delay", 0.04, "连击首击延迟"],
    ["combat_hit_interval", 0.012, "连击命中间隔"],
    ["combat_afterimage_life", 0.1, "连击残影寿命"],
    ["combat_death_stagger", 0.012, "死亡错峰间隔"],
    ["monster_spawn_anim", 0.42, "怪物出生动画时长"],
    ["sakura_petal_count", 42, "樱花花瓣数量"],
    ["sakura_default_duration", 5.5, "樱花默认时长"],
    ["sakura_fade_out_duration", 1.8, "樱花淡出时长"],
    ["grass_cluster_max", 22, "草簇最大数量"],
    ["terrain_prop_count", 8, "地形装饰数量"],
    ["target_fps", 60, "目标帧率(0=不限制)"],
]

ASSET_HEADERS = ["asset_key", "category", "folder_path", "file_pattern", "notes"]
ASSET_ROWS = [
    ["terrain_bg", "terrain", "Terrain", "*.png", "战斗背景/地形"],
    ["ui_hud", "ui", "ui", "*.png", "HUD界面元素"],
    ["effect_magic", "effect", "effects", "*.png", "魔法特效序列帧"],
    ["character_base", "character", "Characters/Characters(100x100)", "*/*/*.png", "角色动画精灵表"],
]

DEFAULT_DATASETS = {
    "chapters": (CHAPTER_HEADERS, CHAPTER_ROWS),
    "stages": (STAGE_HEADERS, STAGE_ROWS),
    "monsters": (MONSTER_HEADERS, MONSTER_ROWS),
    "player": (PLAYER_HEADERS, PLAYER_ROWS),
    "upgrade_fx": (UPGRADE_FX_HEADERS, UPGRADE_FX_ROWS),
    "game_tuning": (TUNING_HEADERS, TUNING_ROWS),
    "asset_mapping": (ASSET_HEADERS, ASSET_ROWS),
    "rewards_v6": (REWARDS_V6_HEADERS, REWARDS_V6_ROWS),
}


def write_sheet(ws, headers: list[str], rows: list[list]):
    ws.append(headers)
    for cell in ws[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
    for row in rows:
        ws.append(row)
    for col in ws.columns:
        max_len = max(len(str(c.value or "")) for c in col)
        ws.column_dimensions[col[0].column_letter].width = min(max_len + 2, 40)


def normalize_cell(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    text = str(value).strip()
    if text == "":
        return ""
    if text.lower() in ("true", "false"):
        return text.lower() == "true"
    try:
        if "." in text:
            return float(text)
        return int(text)
    except ValueError:
        return text


def normalize_stage_row(item: dict) -> dict:
    rooms = item.pop("reward_rooms", "")
    if isinstance(rooms, str):
        parsed = [part.strip() for part in rooms.split(",") if part.strip()]
        if parsed:
            item["reward_rooms"] = parsed
    elif isinstance(rooms, list):
        item["reward_rooms"] = rooms
    room_type = str(item.get("room_type", "")).strip()
    if room_type == "":
        item.erase("room_type")
    else:
        item["room_type"] = room_type
    return item


def rows_to_dicts(headers: list[str], rows: list[list]) -> list[dict]:
    out = []
    for row in rows:
        item = {}
        for i, h in enumerate(headers):
            if not h:
                continue
            val = normalize_cell(row[i] if i < len(row) else None)
            item[h] = "" if val is None else val
        if any(str(v).strip() != "" for v in item.values() if v is not None):
            out.append(item)
    return out


def save_json(name: str, data):
    JSON_DIR.mkdir(parents=True, exist_ok=True)
    path = JSON_DIR / f"{name}.json"
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  -> {path}")


def read_excel(name: str) -> tuple[list[str], list[list]]:
    path = EXCEL_DIR / f"{name}.xlsx"
    if not path.exists():
        raise FileNotFoundError(f"找不到 Excel 文件: {path}")
    wb = load_workbook(path, data_only=True)
    ws = wb.active
    raw_rows = [list(row) for row in ws.iter_rows(values_only=True)]
    if not raw_rows:
        return [], []
    headers = [str(h).strip() if h is not None else "" for h in raw_rows[0]]
    rows = []
    for raw in raw_rows[1:]:
        if all(cell is None or str(cell).strip() == "" for cell in raw):
            continue
        rows.append(list(raw))
    return headers, rows


def build_workbooks():
    EXCEL_DIR.mkdir(parents=True, exist_ok=True)
    for name, (headers, rows) in DEFAULT_DATASETS.items():
        # rewards_v6 由 build_rewards_v6.py 单独生成，init-excel 不要覆盖
        if name == "rewards_v6":
            continue
        wb = Workbook()
        ws = wb.active
        ws.title = name
        write_sheet(ws, headers, rows)
        path = EXCEL_DIR / f"{name}.xlsx"
        wb.save(path)
        print(f"Excel: {path}")


def merge_dataset_excel(name: str) -> int:
    """Append missing rows from DEFAULT_DATASETS without overwriting existing Excel values."""
    path = EXCEL_DIR / f"{name}.xlsx"
    if not path.exists():
        return 0
    _, default_rows = DEFAULT_DATASETS[name]
    wb = load_workbook(path)
    ws = wb.active
    existing_keys: set[str] = set()
    for row in ws.iter_rows(min_row=2, values_only=True):
        if row and row[0] is not None and str(row[0]).strip():
            existing_keys.add(str(row[0]).strip())
    added = 0
    for row in default_rows:
        key = str(row[0]).strip()
        if key and key not in existing_keys:
            ws.append(row)
            added += 1
    if added:
        wb.save(path)
        print(f"  {name}: merged {added} missing key(s) into Excel")
    return added


def merge_tuning_excel() -> int:
    """Append missing tuning keys from TUNING_ROWS without overwriting existing Excel values."""
    return merge_dataset_excel("game_tuning")


def export_json_from_excel():
    JSON_DIR.mkdir(parents=True, exist_ok=True)
    merge_tuning_excel()
    merge_dataset_excel("player")
    # upgrades / upgrade_fx / rewards_v6 以 config/json 为准，勿用旧 Excel 覆盖
    skip_excel_overwrite = {"upgrades", "upgrade_fx", "rewards_v6"}
    print("Reading Excel files...")
    for name in EXCEL_SHEETS:
        if name in skip_excel_overwrite:
            print(f"  {name}: skipped (authoritative: config/json)")
            continue
        headers, rows = read_excel(name)
        data = rows_to_dicts(headers, rows)
        if name == "stages":
            data = [normalize_stage_row(item) for item in data]
        save_json(name, data)
        print(f"  {name}: {len(data)} rows")

    boss = {
        "centipede": {
            "name": "千足虫",
            "warning_time": 3,
            "segment_hp": 320,
            "hp_scale": 3.5,
            "segment_def": 3,
            "segment_radius": 23,
            "crawl_speed": 240,
            "bullet_interval": 0.38,
            "bullets_per_shot": 20,
            "bullet_damage": 24,
            "bullet_speed": 130,
            "defeat_exp": 140,
        },
        "lancer_knight": {
            "name": "冲锋骑士",
            "warning_time": 3,
            "hp": 1600,
            "def": 8,
            "hitbox_radius": 14,
            "move_speed": 48,
            "super_speed_mult": 2.0,
            "skill_interval": 5.0,
            "skill_windup": 1.5,
            "super_speed_duration": 5.0,
            "specter_count": 1,
            "specter_alpha": 0.52,
            "specter_tint_hex": "#9a5acc",
            "specter_attack_mult": 1.0,
            "contact_damage": 18,
            "contact_interval": 0.8,
            "defeat_exp": 140,
            "character_folder": "Lancer",
            "sprite_prefix": "Lancer",
        },
    }
    save_json("bosses", boss)

    buff_orbs = {
        "base_types": ["attack", "ki", "combo"],
        "radius": 13,
        "max_per_type": 4,
        "spawn_chance": {"attack": 0.55, "ki": 0.45, "combo": 0.42, "ice": 0.28},
        "extra_spawn_chance": 0.48,
        "min_ki_per_stage": 2,
    }
    save_json("buff_orbs", buff_orbs)


def main():
    if "--init-excel" in sys.argv:
        print("Resetting Excel templates from defaults...")
        build_workbooks()
        print("Excel templates created.")
    export_json_from_excel()
    print("Done. Restart Godot game (F5) to apply changes.")


if __name__ == "__main__":
    main()
