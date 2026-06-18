#!/usr/bin/env python3
"""Build rewards_v6.xlsx + rewards_v6.json from ys构思_v6.xlsx.

ys构思_v6.xlsx 是策划的设计草稿（99 项奖励、列头偏自由文本、缺数值字段）。
本脚本规范化为 22 列正式配置表，并标记 21 项需要专属 GDScript 处理的奖励。

输出:
  - config/excel/rewards_v6.xlsx
  - config/json/rewards_v6.json

一次性脚本，运行后可手工再调 Excel。
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "ys构思_v6.xlsx"
OUT_XLSX = ROOT / "config" / "excel" / "rewards_v6.xlsx"
OUT_JSON = ROOT / "config" / "json" / "rewards_v6.json"

HEADER_FILL = PatternFill("solid", fgColor="4472C4")
HEADER_FONT = Font(color="FFFFFF", bold=True)

# 最终 schema（与 plan 文件中表格 1:1 对齐）
HEADERS = [
    "id", "name_cn", "group", "rarity", "icon", "desc_cn",
    "max_level", "pool_weight", "once_per_run", "once_per_chapter",
    "dmg_layer", "secondary_layer", "element", "category",
    "apply_type", "apply_value", "weapon_mult",
    "trigger", "cooldown", "extra_params",
    "special_rule", "notes",
]

# ---------------- 字典映射 ----------------

COLOUR_TO_RARITY = {
    "橙": "orange",
    "紫": "purple",
    "蓝": "blue",
    "白": "white",
}

GROUP_TO_CATEGORY = {
    "基础属性": "physical",  # 默认；个别项会被 SPECIAL_OVERRIDES 改
    "生存防御": "survive",
    "普攻子弹": "bullet",
    "连击": "combo",
    "画线轨迹": "trail",
    "强化球": "meta",
    "环绕剑": "sword",
    "召唤": "summon",
    "元素": "bullet",  # 元素附伤主要挂普攻子弹
}

# dmg_layer 携带元素时，element 直接派生
DMG_LAYER_TO_ELEMENT = {
    "E_FIRE": "fire",
    "E_ICE": "ice",
    "E_THUNDER": "thunder",
    "E_POISON": "poison",
}

# 默认图标（rarity / group 派生），策划可改
GROUP_DEFAULT_ICON = {
    "基础属性": "💪",
    "生存防御": "🛡️",
    "普攻子弹": "🔫",
    "连击": "🌀",
    "画线轨迹": "✨",
    "强化球": "🔮",
    "环绕剑": "⚔️",
    "召唤": "👥",
    "元素": "🌈",
}

# 21 项需要独立 GDScript 规则的奖励：special_rule=1
SPECIAL_RULE_IDS = {
    # 画线轨迹（8）
    "trail_multi", "trail_pierce", "trail_loop_explode",
    "trail_fire_wall", "trail_thunder_field", "trail_poison_fog",
    "trail_frost", "trail_slash_wave",
    # 连击（5）—— combo_multi 其实是数值卡(combo_weight)，但权重 +0.05 含特殊规则就归入
    "combo_black_hole", "combo_fireball", "combo_water_tornado",
    "combo_blade_storm", "combo_thunder",
    # 召唤（1）
    "summon_pact",
    # 基础属性（5）
    "basic_giant_might", "basic_berserker", "basic_demon_hunter",
    "basic_weak_aura", "basic_flame_walk",
    # 强化球（1）
    "orb_magnet",
    # 三相之力（多属性混合）
    "basic_tri_force",
}

# ---------------- 字段抽取工具 ----------------

# 从 desc_cn 中匹配 X.X×ATK / X.XX×ATK 的第一个倍率
_WEAPON_MULT_RE = re.compile(r"(\d+(?:\.\d+)?)\s*[×x*]\s*ATK")

# +30%/级 → 0.30
_PERCENT_PER_LV_RE = re.compile(r"\+\s*(\d+(?:\.\d+)?)\s*%\s*/\s*级")

# +N/级 数量类(剑 +1/级，子弹 +1/级)
_COUNT_PER_LV_RE = re.compile(r"\+\s*(\d+)\s*(?:把|颗|枚|条|个|名|只)?\s*/\s*级")


def extract_weapon_mult(desc: str) -> float | None:
    """desc_cn 里第一个 X.X×ATK 视为该技能的 weapon_mult。"""
    m = _WEAPON_MULT_RE.search(desc)
    if not m:
        return None
    return float(m.group(1))


def extract_apply_value(desc: str, default: float = 0.0) -> float:
    """从 desc_cn 抽出 +N%/级 或 +N/级 作为 apply_value。"""
    m = _PERCENT_PER_LV_RE.search(desc)
    if m:
        return round(float(m.group(1)) / 100.0, 4)
    m = _COUNT_PER_LV_RE.search(desc)
    if m:
        return float(m.group(1))
    return default


# ---------------- 触发器归一化 ----------------

TRIGGER_NORMALIZE = {
    "passive": "passive",
    "on_kill": "on_kill",
    "on_hit": "on_hit",
    "on_pickup": "on_pickup",
    "on_loop_close": "on_loop_close",
    "on_combo": "on_combo",
    "on_slash_end": "on_slash_end",
    "on_death": "on_death",
    "stage_start": "stage_start",
    "timer": "timer",
    "condition_hp_50": "hp_below_50",
    "condition_hp_30": "hp_below_30",
    "condition_boss": "vs_boss",
    "condition_stand": "stand_1.5s",
    # 连击里程碑：保留原始 numeric 段位
    "combo_milestone_5": "combo_milestone_5",
    "combo_milestone_6": "combo_milestone_6",
    "combo_milestone_8": "combo_milestone_8",
    "combo_milestone_10": "combo_milestone_10",
    "combo_milestone_12": "combo_milestone_12",
    "combo_milestone_14": "combo_milestone_14",
}


def normalize_trigger(t: str) -> str:
    return TRIGGER_NORMALIZE.get(t, t)


# ---------------- 单项规则覆盖 ----------------
# 对个别奖励手工补充结构化数值（weapon_mult / apply_value / extra_params / cooldown）
# 这里只填那些自动抽取不完整或多参数的项，剩下的走默认规则。
OVERRIDES: dict[str, dict] = {
    # 基础属性
    "basic_warrior_soul": {"apply_value": 0.35},
    "basic_tri_force": {
        "apply_value": 0.10,
        "extra_params": {"move_pct": 0.10, "atk_speed_pct": 0.15, "max_hp_pct": 0.15},
    },
    "basic_giant_might": {
        "apply_value": 0.15,
        "secondary_layer": "SURVIVE",
        "extra_params": {"atk_pct_per_lv": 0.15, "hp_pct_per_lv": 0.10,
                          "move_penalty_per_lv": -0.05, "size_pct": 0.10},
    },
    "basic_swift_soul": {
        "apply_value": 0.15,
        "extra_params": {"atk_speed_pct_per_lv": 0.15, "move_pct_per_lv": 0.10},
    },
    "basic_godspeed": {
        "apply_value": 0.10,
        "extra_params": {"atk_speed_pct_per_lv": 0.10, "ki_regen_pct_per_lv": 0.10},
    },
    "basic_berserker": {
        "apply_value": 0.10,
        "extra_params": {"atk_pct_per_lv": 0.10, "max_lv_cap": 0.40,
                          "atk_speed_pct": 0.10, "hp_threshold": 0.50},
    },
    "basic_demon_hunter": {
        "apply_value": 0.08,
        "extra_params": {"atk_pct_per_stack": 0.08, "max_stacks": 5,
                          "duration": 3.0},
    },
    "basic_four_leaf": {"apply_value": 0.08},
    "basic_ki_spring": {
        "apply_value": 0.15,
        "extra_params": {"ki_regen_pct_per_lv": 0.15, "ki_max_pct_per_lv": 0.08},
    },
    "basic_weak_aura": {
        "apply_value": 0.20,
        "weapon_mult": 0.4,
        "cooldown": 0.3,
        "extra_params": {"vuln_pct_per_lv": 0.20, "max_lv_cap": 0.60,
                          "tick_atk_mult": 0.4, "tick_interval": 0.3},
    },
    "basic_luck": {
        "apply_value": 0.06,
        "extra_params": {"luck_pct_per_lv": 0.06, "dodge_pct_per_lv": 0.04},
    },
    "basic_wounded": {
        "apply_value": 0.15,
        "extra_params": {"atk_pct_per_lv": 0.15, "duration": 5.0},
    },
    "basic_ki_plus": {"apply_value": 0.08},
    "basic_move": {"apply_value": 0.08},
    "basic_ki_regen": {"apply_value": 0.08},
    "basic_warrior_breath": {"apply_value": 0.08},
    "basic_shrink": {
        "apply_value": 0.10,
        "extra_params": {"move_pct": 0.10, "dodge_pct": 0.10, "size_pct": -0.30},
    },
    "basic_boss_slayer": {
        "apply_value": 0.15,
        "extra_params": {"boss_dmg_pct_per_lv": 0.15, "heal_to_full_at_boss": True},
    },
    "basic_flame_walk": {
        "apply_value": 0.15,
        "weapon_mult": 0.15,
        "extra_params": {"tick_atk_mult": 0.15, "tick_interval": 0.5,
                          "duration": 2.0, "burn_attached": True},
    },

    # 生存防御
    "sv_holy_guard": {"apply_value": 1.0, "extra_params": {"charges": 1}},
    "sv_power_soul": {"apply_value": 0.15},
    "sv_desperate_heart": {
        "apply_value": 0.10,
        "extra_params": {"atk_pct_per_lv": 0.10, "max_lv_cap": 0.30, "hp_threshold": 0.50},
    },
    "sv_revive": {"apply_value": 0.50, "extra_params": {"revive_hp_pct": 0.50, "once_per_run": True}},
    "sv_desperate_regen": {
        "apply_value": 0.01,
        "extra_params": {"regen_pct_per_lv_per_sec": 0.01, "until_hp_pct": 0.30, "hp_threshold": 0.30},
    },
    "sv_kill_revive": {
        "apply_value": 0.06,
        "extra_params": {"heal_pct_per_lv": 0.06, "proc_chance": 0.20},
    },
    "sv_stand_guard": {
        "apply_value": 0.30,
        "extra_params": {"base_dr": 0.30, "dr_per_lv": 0.05, "max_dr": 0.50, "stand_secs": 1.5},
    },
    "sv_angel_shelter": {
        "apply_value": 0.10,
        "extra_params": {"hp_pct_per_lv": 0.10, "iframe_secs": 1.5, "cd": 6.0},
    },
    "sv_blood_power": {"apply_value": 0.10},
    "sv_demon_recover": {
        "apply_value": 0.05,
        "extra_params": {"heal_pct_per_lv": 0.05, "proc_chance": 0.15},
    },
    "sv_life_spring": {
        "apply_value": 0.08,
        "extra_params": {"hp_pct_per_lv": 0.08, "heal_on_pickup_pct": 0.30},
    },

    # 普攻子弹
    "bullet_storm_king": {
        "apply_value": 3,
        "extra_params": {"bullet_count_add": 3, "atk_speed_pct": 0.15},
    },
    "bullet_spirit_bomb": {
        "apply_value": 0.50,
        "extra_params": {"dmg_pct_max": 0.50, "ramp_by_distance": True},
    },
    "bullet_swift_shoot": {
        "apply_value": 0.30,
        "extra_params": {"atk_speed_pct_per_lv": 0.30, "bullet_dmg_pct_per_lv": -0.10},
    },
    "bullet_homing": {
        "apply_value": 1,
        "extra_params": {"homing": True, "atk_pct_per_lv": -0.05},
    },
    "bullet_fire_support": {
        "apply_value": 0.10,
        "weapon_mult": 0.8,
        "extra_params": {"proc_chance_per_lv": 0.10, "aoe_atk_mult": 0.80},
    },
    "bullet_split": {
        "apply_value": 0.50,
        "weapon_mult": 0.50,
        "extra_params": {"split_count": 3, "child_atk_mult": 0.50, "child_atk_pct_per_lv": 0.10},
    },
    "bullet_bounce": {
        "apply_value": 1,
        "extra_params": {"bounce_per_lv": 1, "max_bounces": 3, "dmg_falloff": 0.6},
    },
    "bullet_mirror": {"apply_value": 1, "weapon_mult": 0.6,
                       "extra_params": {"return_dmg_mult": 0.6}},
    "bullet_side": {"apply_value": 2, "extra_params": {"side_bullets": 2, "angle_deg": 30}},
    "bullet_count": {"apply_value": 1, "extra_params": {"max_total": 3}},
    "bullet_beam": {
        "apply_value": 0.10,
        "weapon_mult": 1.0,
        "extra_params": {"proc_chance_per_lv": 0.10, "beam_atk_mult": 1.0, "pierce": True},
    },

    # 连击
    "combo_multi": {
        "apply_value": 0.05,
        "extra_params": {"weight_per_hit": 0.05, "no_cap": True},
    },
    "combo_black_hole": {
        "apply_value": 1,
        "weapon_mult": 2.0,
        "extra_params": {"base_milestone": 8, "milestone_step_per_lv": -2},
    },
    "combo_fireball": {
        "apply_value": 1,
        "weapon_mult": 2.5,
        "extra_params": {"base_milestone": 14, "milestone_step_per_lv": -2,
                          "element": "fire"},
    },
    "combo_water_tornado": {
        "apply_value": 1,
        "weapon_mult": 2.2,
        "extra_params": {"base_milestone": 6, "milestone_step_per_lv": -1,
                          "element": "ice"},
    },
    "combo_blade_storm": {
        "apply_value": 1,
        "weapon_mult": 2.0,
        "extra_params": {"base_milestone": 8, "blade_count": 6, "blade_add_per_lv": 1,
                          "element": "poison"},
    },
    "combo_charge": {
        "apply_value": 0.20,
        "extra_params": {"per_04s_pct_per_lv": 0.20, "max_mult": 1.5},
    },
    "combo_thunder": {
        "apply_value": 1,
        "weapon_mult": 3.0,
        "extra_params": {"base_milestone": 8, "milestone_step_per_lv": -1,
                          "element": "thunder"},
    },
    "combo_shuriken": {
        "apply_value": 2,
        "weapon_mult": 0.6,
        "extra_params": {"count_per_lv": 2, "shuriken_atk_mult": 0.6},
    },
    "combo_crit": {
        "apply_value": 0.10,
        "extra_params": {"crit_pct_per_lv": 0.10, "combo_per_step": 10},
    },

    # 画线轨迹
    "trail_multi": {"apply_value": 2, "extra_params": {"extra_trails": 2}},
    "trail_fire_wall": {
        "apply_value": 1,
        "weapon_mult": 0.8,
        "extra_params": {"base_duration": 5.0, "duration_per_lv": 1.0,
                          "tick_atk_mult": 0.8, "tick_interval": 0.5,
                          "bullets_pass_attach_fire": True},
    },
    "trail_thunder_field": {
        "apply_value": 1,
        "weapon_mult": 0.5,
        "extra_params": {"base_duration": 3.0, "duration_per_lv": 1.0,
                          "tick_atk_mult": 0.5, "tick_interval": 0.5,
                          "paralyze": True},
    },
    "trail_poison_fog": {
        "apply_value": 1,
        "weapon_mult": 0.35,
        "extra_params": {"base_duration": 4.0, "duration_per_lv": 1.0,
                          "tick_atk_mult": 0.35, "tick_interval": 1.0,
                          "ramp_per_sec": 0.25},
    },
    "trail_frost": {
        "apply_value": 1,
        "weapon_mult": 0.5,
        "extra_params": {"base_duration": 3.0, "duration_per_lv": 1.0,
                          "tick_atk_mult": 0.5, "tick_interval": 0.5,
                          "slow_pct": 0.40},
    },
    "trail_slash_wave": {
        "apply_value": 0.3,
        "weapon_mult": 2.5,
        "extra_params": {"wave_atk_mult": 2.5, "radius": 200, "radius_pct_per_lv": 0.30},
    },
    "trail_loop_explode": {
        "apply_value": 0.30,
        "weapon_mult": 3.0,
        "extra_params": {"explode_atk_mult": 3.0, "explode_atk_pct_per_lv": 0.30,
                          "min_loop_area": 1000},
    },
    "trail_pierce": {"apply_value": 1, "extra_params": {"pierce_obstacles": True}},
    "trail_width": {"apply_value": 0.10, "extra_params": {"width_pct_per_lv": 0.10, "max_total": 0.50}},
    "trail_dmg": {"apply_value": 0.08, "extra_params": {"slash_dmg_pct_per_lv": 0.08, "max_total": 0.40}},

    # 强化球
    "orb_tide": {
        "apply_value": 8.0,
        "extra_params": {"base_interval": 8.0, "interval_reduction_per_lv": 2.0},
    },
    "orb_mark": {
        "apply_value": 0.30,
        "extra_params": {"base_chance": 0.30, "chance_per_lv": 0.05},
    },
    "orb_field": {"apply_value": 0.30,
                   "extra_params": {"count_pct_per_lv": 0.30, "max_total": 1.20}},
    "orb_magnet": {
        "apply_value": 0.30,
        "extra_params": {"pickup_radius_pct_per_lv": 0.30, "attract_radius_pct_per_lv": 0.30},
    },
    "orb_burst": {
        "apply_value": 0.30,
        "weapon_mult": 1.5,
        "extra_params": {"burst_atk_mult": 1.5, "burst_atk_pct_per_lv": 0.30},
    },
    "orb_glow": {
        "apply_value": 0.15,
        "extra_params": {"trail_buff_pct_per_lv": 0.15, "duration": 6.0},
    },
    "orb_fire": {
        "apply_value": 0.20,
        "weapon_mult": 1.0,
        "extra_params": {"burn_atk_mult": 1.0, "burn_pct_per_lv": 0.20},
    },
    "orb_ice": {
        "apply_value": 0.2,
        "extra_params": {"freeze_secs": 2.0, "freeze_per_lv": 0.2},
    },
    "orb_poison": {
        "apply_value": 0.6,
        "weapon_mult": 0.6,
        "extra_params": {"poison_atk_per_sec": 0.6, "duration": 3.0},
    },
    "orb_thunder": {
        "apply_value": 1,
        "weapon_mult": 1.5,
        "extra_params": {"thunder_atk_mult": 1.5, "chain_add_per_lv": 1},
    },

    # 环绕剑
    "sword_double": {"apply_value": 2, "extra_params": {"sword_count_mult": 2}},
    "sword_rage": {
        "apply_value": 0.05,
        "weapon_mult": 2.5,
        "extra_params": {"proc_chance": 0.15, "rage_atk_mult": 2.5,
                          "range_pct_per_lv": 0.05},
    },
    "sword_guard": {"apply_value": 2, "extra_params": {"guard_swords": 2, "blocks_bullets": True}},
    "sword_length": {"apply_value": 0.15, "extra_params": {"length_pct_per_lv": 0.15, "max_total": 0.45}},
    "sword_speed": {"apply_value": 0.15, "extra_params": {"speed_pct_per_lv": 0.15, "max_total": 0.45}},
    "sword_blood": {
        "apply_value": 2,
        "extra_params": {"blood_swords": 2, "heal_pct": 0.01, "cd": 0.6},
    },
    "sword_dmg": {"apply_value": 0.15, "extra_params": {"sword_dmg_pct_per_lv": 0.15, "max_total": 0.60}},
    "sword_flame": {
        "apply_value": 1,
        "weapon_mult": 0.40,
        "extra_params": {"sword_count_per_lv": 1, "burn_atk_mult": 0.40,
                          "burn_interval": 0.5, "burn_duration": 2.0},
    },
    "sword_thunder": {
        "apply_value": 1,
        "weapon_mult": 0.40,
        "extra_params": {"sword_count_per_lv": 1, "chain_atk_mult": 0.40},
    },
    "sword_poison": {
        "apply_value": 1,
        "weapon_mult": 0.30,
        "extra_params": {"sword_count_per_lv": 1, "poison_atk_per_sec": 0.30,
                          "duration": 3.0},
    },
    "sword_frost": {
        "apply_value": 1,
        "weapon_mult": 0.30,
        "extra_params": {"sword_count_per_lv": 1, "frost_atk_mult": 0.30,
                          "slow_pct": 0.30, "slow_secs": 1.0},
    },

    # 召唤
    "summon_pact": {
        "apply_value": 0.50,
        "extra_params": {"summon_dmg_pct": 0.50, "summon_size_pct": 0.15,
                          "summon_atk_speed_pct": 0.50, "unlock_king": True},
    },
    "summon_rage": {
        "apply_value": 0.12,
        "extra_params": {"summon_dmg_pct_per_lv": 0.12, "interval_pct_per_lv": -0.12},
    },
    "summon_king": {
        "apply_value": 1,
        "weapon_mult": 2.5,
        "extra_params": {"aoe_atk_mult": 2.5, "interval": 2.0},
    },
    "summon_god": {
        "apply_value": 1,
        "weapon_mult": 1.8,
        "extra_params": {"single_atk_mult": 1.8, "interval": 1.5},
    },
    "summon_gorilla": {
        "apply_value": 0.30,
        "extra_params": {"taunt_radius": 500, "player_dr": 0.30},
    },
    "summon_dmg": {"apply_value": 0.10, "extra_params": {"summon_dmg_pct_per_lv": 0.10, "max_total": 0.50}},
    "summon_thunder": {
        "apply_value": 1,
        "weapon_mult": 1.2,
        "extra_params": {"strike_atk_mult": 1.2, "interval": 2.0, "chain": True},
    },
    "summon_bear": {
        "apply_value": 1,
        "weapon_mult": 1.0,
        "extra_params": {"bear_atk_mult": 1.0, "slow_pct": 0.30},
    },
    "summon_snake": {
        "apply_value": 1,
        "weapon_mult": 1.0,
        "extra_params": {"poison_atk_per_sec": 1.0, "duration": 4.0},
    },
    "summon_fire": {
        "apply_value": 1,
        "weapon_mult": 1.2,
        "extra_params": {"fire_atk_mult": 1.2, "burn_attached": True},
    },

    # 元素
    "elem_fire_plus": {
        "apply_value": 0.30,
        "extra_params": {"elem_pct_per_lv": 0.30, "burn_freq_pct_per_lv": 0.15},
    },
    "elem_thunder_plus": {
        "apply_value": 0.30,
        "extra_params": {"elem_pct_per_lv": 0.30, "chain_targets_per_lv": 1},
    },
    "elem_poison_plus": {
        "apply_value": 0.30,
        "extra_params": {"elem_pct_per_lv": 0.30, "poison_burst_chance": 0.08,
                          "poison_burst_pct_per_lv": 0.08},
    },
    "elem_ice_plus": {
        "apply_value": 0.30,
        "extra_params": {"elem_pct_per_lv": 0.30, "freeze_chance": 0.08,
                          "freeze_chance_per_lv": 0.08},
    },
    "elem_fire_bullet": {
        "apply_value": 0.05,
        "weapon_mult": 0.30,
        "extra_params": {"base_chance": 0.45, "chance_per_lv": 0.05,
                          "burn_atk_per_sec": 0.30, "duration": 2.0},
    },
    "elem_thunder_bullet": {
        "apply_value": 0.05,
        "weapon_mult": 0.45,
        "extra_params": {"base_chance": 0.45, "chance_per_lv": 0.05,
                          "chain_atk_mult": 0.45},
    },
    "elem_poison_bullet": {
        "apply_value": 0.05,
        "weapon_mult": 0.25,
        "extra_params": {"base_chance": 0.45, "chance_per_lv": 0.05,
                          "poison_atk_per_sec": 0.25, "duration": 3.0},
    },
    "elem_ice_bullet": {
        "apply_value": 0.2,
        "extra_params": {"base_chance": 0.45, "chance_per_lv": 0.05,
                          "slow_pct": 0.50, "base_duration": 1.5, "duration_per_lv": 0.2},
    },
}


def normalize_row(raw: dict) -> dict:
    rid = str(raw["id"])
    name_cn = str(raw["name_cn"])
    group = str(raw["group"])
    desc = str(raw["desc_cn"])
    colour = str(raw["colour"])
    rarity = COLOUR_TO_RARITY.get(colour, "white")
    raw_dmg_layer = str(raw["dmg_layer"])

    # dmg_layer + secondary_layer 拆分（H1+HP → H1 / SURVIVE）
    secondary = ""
    dmg_layer = raw_dmg_layer
    if "+" in raw_dmg_layer:
        parts = raw_dmg_layer.split("+", 1)
        dmg_layer = parts[0].strip()
        sec_raw = parts[1].strip().upper()
        if sec_raw == "HP":
            secondary = "SURVIVE"
        else:
            secondary = sec_raw

    # element 派生
    element = DMG_LAYER_TO_ELEMENT.get(dmg_layer, "")

    # category 派生（GROUP 默认；override 可覆盖）
    category = GROUP_TO_CATEGORY.get(group, "")
    # E_xxx 层但 group=召唤/环绕剑/画线/强化球，category 仍跟随 group（保留物理类型来源）

    # trigger 归一化
    trigger = normalize_trigger(str(raw.get("trigger", "passive")))

    # 数值字段：从 desc 抽取默认值
    weapon_mult = extract_weapon_mult(desc)
    apply_value = extract_apply_value(desc, default=0.0)
    cooldown = 0.0

    apply_type = str(raw.get("apply_type", ""))
    pool_weight = int(raw.get("pool_weight", 100))
    max_level = int(raw.get("max_level", 1))

    # 应用 OVERRIDES
    over = OVERRIDES.get(rid, {})
    if "apply_value" in over:
        apply_value = float(over["apply_value"])
    if "weapon_mult" in over:
        weapon_mult = float(over["weapon_mult"])
    if "cooldown" in over:
        cooldown = float(over["cooldown"])
    if "secondary_layer" in over:
        secondary = over["secondary_layer"]
    extra_params_obj = over.get("extra_params", {})
    extra_params = json.dumps(extra_params_obj, ensure_ascii=False, sort_keys=True) if extra_params_obj else ""

    # special_rule
    special_rule = 1 if rid in SPECIAL_RULE_IDS else 0

    # icon 默认
    icon = GROUP_DEFAULT_ICON.get(group, "")

    return {
        "id": rid,
        "name_cn": name_cn,
        "group": group,
        "rarity": rarity,
        "icon": icon,
        "desc_cn": desc,
        "max_level": max_level,
        "pool_weight": pool_weight,
        "once_per_run": 1 if rid == "sv_revive" else 0,
        "once_per_chapter": 0,
        "dmg_layer": dmg_layer,
        "secondary_layer": secondary,
        "element": element,
        "category": category,
        "apply_type": apply_type,
        "apply_value": float(apply_value) if apply_value is not None else 0.0,
        "weapon_mult": float(weapon_mult) if weapon_mult is not None else 0.0,
        "trigger": trigger,
        "cooldown": float(cooldown),
        "extra_params": extra_params,
        "special_rule": special_rule,
        "notes": str(raw.get("notes", "")),
    }


def read_v6_raw() -> list[dict]:
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    headers = [str(h).strip() if h is not None else "" for h in rows[0]]
    # 兼容 "max level" 空格
    headers_norm = [h.replace(" ", "_") for h in headers]
    out = []
    for raw in rows[1:]:
        if not raw or all(v is None for v in raw):
            continue
        item = {headers_norm[i]: raw[i] for i in range(len(headers_norm)) if headers_norm[i]}
        if not item.get("id"):
            continue
        out.append(item)
    return out


def write_xlsx(rows: list[dict]):
    OUT_XLSX.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "rewards_v6"
    ws.append(HEADERS)
    for cell in ws[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
    for r in rows:
        ws.append([r.get(h, "") for h in HEADERS])
    for col in ws.columns:
        max_len = max(len(str(c.value or "")) for c in col)
        ws.column_dimensions[col[0].column_letter].width = min(max_len + 2, 50)
    wb.save(OUT_XLSX)
    print(f"Wrote {OUT_XLSX}")


def write_json(rows: list[dict]):
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    # JSON 中 extra_params 还原为对象更易代码侧读取
    out = []
    for r in rows:
        item = dict(r)
        ep = item.get("extra_params", "")
        if isinstance(ep, str) and ep.strip():
            try:
                item["extra_params"] = json.loads(ep)
            except json.JSONDecodeError as e:
                print(f"  WARNING: {item['id']} extra_params 不是合法 JSON: {e}")
                item["extra_params"] = {}
        else:
            item["extra_params"] = {}
        out.append(item)
    with OUT_JSON.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"Wrote {OUT_JSON}")


def main():
    if not SRC_XLSX.exists():
        print(f"ERROR: 找不到源文件 {SRC_XLSX}", file=sys.stderr)
        sys.exit(1)
    raw = read_v6_raw()
    print(f"Loaded {len(raw)} raw entries from {SRC_XLSX.name}")
    rows = [normalize_row(r) for r in raw]
    print(f"Normalized {len(rows)} rows")
    # 统计
    group_counts: dict[str, int] = {}
    for r in rows:
        group_counts[r["group"]] = group_counts.get(r["group"], 0) + 1
    print("Group distribution:")
    for g, c in sorted(group_counts.items()):
        print(f"  {g}: {c}")
    special_count = sum(1 for r in rows if r["special_rule"] == 1)
    print(f"special_rule=1 count: {special_count}")
    write_xlsx(rows)
    write_json(rows)
    print("Done.")


if __name__ == "__main__":
    main()
