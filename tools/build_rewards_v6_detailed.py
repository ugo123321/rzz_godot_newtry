#!/usr/bin/env python3
"""一次性脚本：把 ys构思_v6.xlsx 的 99 项规范化为「每属性一列」的细粒度 Excel。

设计目标：给程序员评审用。
- 每个面板属性、每种状态效果、每种数量/机制单独一列
- 触发条件拆成 trigger_type + trigger_value + trigger_value_per_lv + proc_chance
- 主属性区分 base / per_lv / max_total 三段
- 双行 header：第 1 行中文说明、第 2 行 snake_case 英文 key

输出：config/excel/rewards_v6_detailed.xlsx
不动现有 rewards_v6.xlsx / rewards_v6.json / 工具链。
"""
from __future__ import annotations

import json
from pathlib import Path

import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "ys构思_v6.xlsx"
OUT_XLSX = ROOT / "config" / "excel" / "rewards_v6_detailed.xlsx"

# ===== Schema：双行 header (cn, en) =====
# 顺序按 [元信息] [标签] [触发器] [概率/冷却] [主属性 base/per_lv/cap]
#       [子弹/弹射] [机制布尔] [技能法术] [持续时间] [状态效果]
#       [叠层] [生存复活] [召唤] [剑] [轨迹] [球] [蓄力] [击杀类] [Boss针对]

HEADERS_CN_EN: list[tuple[str, str]] = [
    # --- A. 元信息 ---
    ("ID", "id"),
    ("名称", "name_cn"),
    ("分组", "group"),
    ("品质", "rarity"),
    ("图标", "icon"),
    ("描述", "desc_cn"),
    ("最大等级", "max_level"),
    ("池权重", "pool_weight"),
    ("本局一次", "once_per_run"),
    ("本章一次", "once_per_chapter"),
    ("专属规则", "special_rule"),
    ("备注", "notes"),
    # --- B. 分层标签 ---
    ("伤害分层", "dmg_layer"),
    ("副分层", "secondary_layer"),
    ("元素", "element"),
    ("品类", "category"),
    # --- C. 触发条件 ---
    ("触发条件", "trigger_type"),
    ("条件数值", "trigger_value"),
    ("条件数值每级", "trigger_value_per_lv"),
    ("触发概率", "proc_chance"),
    ("触发概率每级", "proc_chance_per_lv"),
    # --- D. 通用计时 ---
    ("冷却秒", "cooldown_sec"),
    ("持续秒", "duration_sec"),
    ("持续秒每级", "duration_sec_per_lv"),
    ("tick间隔秒", "tick_interval_sec"),
    # --- E. 主属性：攻击 ---
    ("攻击%", "atk_pct"),
    ("攻击%每级", "atk_pct_per_lv"),
    ("攻击%上限", "atk_pct_max_total"),
    # --- 攻速 ---
    ("攻速%", "atk_speed_pct"),
    ("攻速%每级", "atk_speed_pct_per_lv"),
    # --- 移速 ---
    ("移速%", "move_speed_pct"),
    ("移速%每级", "move_speed_pct_per_lv"),
    # --- 生命 ---
    ("最大生命%", "max_hp_pct"),
    ("最大生命%每级", "max_hp_pct_per_lv"),
    ("最大生命%上限", "max_hp_pct_max_total"),
    # --- 气力 ---
    ("气力上限%", "ki_max_pct"),
    ("气力上限%每级", "ki_max_pct_per_lv"),
    ("气力回复%", "ki_regen_pct"),
    ("气力回复%每级", "ki_regen_pct_per_lv"),
    # --- 暴击 ---
    ("暴击率", "crit_rate"),
    ("暴击率每级", "crit_rate_per_lv"),
    ("暴击伤害", "crit_dmg"),
    ("暴击伤害每级", "crit_dmg_per_lv"),
    # --- 闪避/幸运 ---
    ("闪避%", "dodge_pct"),
    ("闪避%每级", "dodge_pct_per_lv"),
    ("幸运%", "luck_pct"),
    ("幸运%每级", "luck_pct_per_lv"),
    # --- 体型 / 减伤 ---
    ("体型%", "size_pct"),
    ("减伤%", "damage_reduction_pct"),
    ("减伤%每级", "damage_reduction_pct_per_lv"),
    ("减伤%上限", "damage_reduction_pct_max_total"),
    # --- F. 子弹/弹射 ---
    ("子弹数量+", "bullet_count_add"),
    ("子弹数量+每级", "bullet_count_add_per_lv"),
    ("子弹数量上限", "bullet_count_max_total"),
    ("子弹倍乘", "bullet_count_mult"),
    ("弹射+", "bounce_add"),
    ("弹射+每级", "bounce_add_per_lv"),
    ("弹射上限", "bounce_max"),
    ("弹射衰减", "bounce_falloff"),
    ("侧射数量", "side_bullet_count"),
    ("侧射角度", "side_bullet_angle_deg"),
    ("分裂子弹数", "split_count"),
    ("分裂子弹倍率", "split_atk_mult"),
    ("分裂子弹每级", "split_atk_mult_per_lv"),
    # --- G. 子弹机制布尔 ---
    ("追踪", "homing_bool"),
    ("穿透敌人", "pierce_enemies_bool"),
    ("穿越障碍", "pierce_obstacles_bool"),
    ("镜像回弹", "mirror_return_bool"),
    ("镜像回弹倍率", "mirror_return_atk_mult"),
    # --- H. 技能/法术 ---
    ("武器ATK倍率", "weapon_mult"),
    ("武器ATK倍率每级", "weapon_mult_per_lv"),
    ("AOE半径px", "aoe_radius_px"),
    ("AOE半径每级", "aoe_radius_per_lv"),
    # --- I. 元素状态效果 ---
    ("燃烧倍率/秒", "burn_atk_per_sec"),
    ("燃烧倍率每级", "burn_atk_per_sec_per_lv"),
    ("燃烧持续秒", "burn_duration_sec"),
    ("中毒倍率/秒", "poison_atk_per_sec"),
    ("中毒持续秒", "poison_duration_sec"),
    ("冰冻秒", "freeze_duration_sec"),
    ("冰冻秒每级", "freeze_duration_sec_per_lv"),
    ("减速%", "slow_pct"),
    ("减速秒", "slow_duration_sec"),
    ("麻痹", "paralyze_bool"),
    ("雷链目标", "chain_targets"),
    ("雷链目标每级", "chain_targets_per_lv"),
    ("元素加成%每级", "elem_dmg_pct_per_lv"),
    ("元素触发频率%每级", "elem_proc_freq_per_lv"),
    ("元素附伤倍率", "elem_attach_atk_mult"),
    ("元素附伤每级", "elem_attach_atk_mult_per_lv"),
    # --- J. 叠层 ---
    ("叠层增益%/层", "stack_value_per_stack"),
    ("叠层上限", "stack_max_count"),
    ("叠层持续秒", "stack_duration_sec"),
    # --- K. 生存/复活/治疗 ---
    ("护盾层数", "shield_charges"),
    ("复活生命%", "revive_hp_pct"),
    ("回血%", "heal_pct"),
    ("回血%每级", "heal_pct_per_lv"),
    ("回血概率", "heal_proc_chance"),
    ("受击无敌秒", "iframe_secs"),
    ("HP阈值再生%/秒", "low_hp_regen_pct_per_sec"),
    ("HP阈值再生目标%", "low_hp_regen_target_pct"),
    # --- L. 召唤 ---
    ("召唤伤害%", "summon_dmg_pct"),
    ("召唤伤害%每级", "summon_dmg_pct_per_lv"),
    ("召唤伤害%上限", "summon_dmg_pct_max_total"),
    ("召唤攻速%", "summon_atk_speed_pct"),
    ("召唤体型%", "summon_size_pct"),
    ("召唤间隔%每级", "summon_interval_pct_per_lv"),
    ("嘲讽半径", "taunt_radius_px"),
    # --- M. 环绕剑 ---
    ("剑数量+", "sword_count_add"),
    ("剑数量+每级", "sword_count_add_per_lv"),
    ("剑数量倍乘", "sword_count_mult"),
    ("剑伤害%", "sword_dmg_pct"),
    ("剑伤害%每级", "sword_dmg_pct_per_lv"),
    ("剑伤害%上限", "sword_dmg_pct_max_total"),
    ("剑长度%每级", "sword_length_pct_per_lv"),
    ("剑长度%上限", "sword_length_pct_max_total"),
    ("剑转速%每级", "sword_speed_pct_per_lv"),
    ("剑转速%上限", "sword_speed_pct_max_total"),
    ("阻挡子弹", "sword_block_bullets_bool"),
    # --- N. 画线轨迹 ---
    ("额外轨迹数", "trail_extra_count"),
    ("轨迹宽度%每级", "trail_width_pct_per_lv"),
    ("轨迹宽度%上限", "trail_width_pct_max_total"),
    ("轨迹伤害%每级", "trail_dmg_pct_per_lv"),
    ("轨迹伤害%上限", "trail_dmg_pct_max_total"),
    ("末端冲击半径px", "trail_endwave_radius_px"),
    ("末端冲击半径%每级", "trail_endwave_radius_pct_per_lv"),
    ("闭合最小面积", "loop_min_area"),
    # --- O. 强化球 ---
    ("球生成间隔秒", "orb_spawn_interval_sec"),
    ("球生成间隔每级减", "orb_spawn_interval_reduction_per_lv"),
    ("球数量%每级", "orb_count_pct_per_lv"),
    ("球数量%上限", "orb_count_pct_max_total"),
    ("球磁吸半径%每级", "orb_magnet_pct_per_lv"),
    ("球印记复制概率", "orb_mark_dup_chance"),
    ("球印记概率每级", "orb_mark_dup_chance_per_lv"),
    ("球拾取增益%每级", "orb_glow_buff_pct_per_lv"),
    # --- P. 蓄力 ---
    ("蓄力每0.4s%", "charge_per_04s_pct"),
    ("蓄力上限倍率", "charge_max_mult"),
    # --- Q. 击杀类 ---
    ("击杀回血概率", "kill_heal_proc_chance"),
    ("击杀回血%每级", "kill_heal_pct_per_lv"),
    ("击杀叠层%/层", "kill_stack_pct_per_stack"),
    ("击杀叠层上限", "kill_stack_max_count"),
    ("击杀叠层持续秒", "kill_stack_duration_sec"),
    # --- R. Boss / 条件 ---
    ("Boss伤害%每级", "boss_dmg_pct_per_lv"),
    ("Boss战回满HP", "boss_heal_full_bool"),
    # --- S. 站立/光环 ---
    ("站立触发秒", "stand_trigger_sec"),
    ("光环易伤%每级", "aura_vuln_pct_per_lv"),
    ("光环易伤%上限", "aura_vuln_pct_max_total"),
    ("光环ATK倍率", "aura_atk_mult"),
    # --- T. 连击里程碑 ---
    ("里程碑基础", "milestone_base"),
    ("里程碑每级减", "milestone_step_per_lv"),
    ("里程碑每级加刀", "milestone_blade_add_per_lv"),
    ("连击步长", "combo_step"),
    # --- U. 普攻强化 ---
    ("普攻伤害%每级惩罚", "bullet_dmg_pct_per_lv_penalty"),
    ("元气弹距离系数%上限", "spirit_bomb_distance_pct_max"),
    ("AOE炸弹概率%每级", "aoe_bomb_proc_chance_per_lv"),
    ("AOE炸弹ATK倍率", "aoe_bomb_atk_mult"),
    ("能量束概率%每级", "beam_proc_chance_per_lv"),
    ("能量束ATK倍率", "beam_atk_mult"),
    # --- V. 轨迹爆炸 / 火墙 ---
    ("闭合爆炸ATK倍率", "loop_explode_atk_mult"),
    ("闭合爆炸%每级", "loop_explode_pct_per_lv"),
    # --- W. 多属性混合标记 ---
    ("解锁单位", "unlock_unit"),
    ("权重每段", "weight_per_hit"),
    ("解除上限", "no_cap_bool"),
    ("条件持续秒", "condition_duration_sec"),
]

# ===== 数据生成 =====

COLOUR_TO_RARITY = {"橙": "orange", "紫": "purple", "蓝": "blue", "白": "white"}
GROUP_TO_CATEGORY = {
    "基础属性": "physical", "生存防御": "survive", "普攻子弹": "bullet",
    "连击": "combo", "画线轨迹": "trail", "强化球": "meta",
    "环绕剑": "sword", "召唤": "summon", "元素": "bullet",
}
DMG_LAYER_TO_ELEMENT = {"E_FIRE": "fire", "E_ICE": "ice", "E_THUNDER": "thunder", "E_POISON": "poison"}
GROUP_DEFAULT_ICON = {
    "基础属性": "💪", "生存防御": "🛡️", "普攻子弹": "🔫", "连击": "🌀",
    "画线轨迹": "✨", "强化球": "🔮", "环绕剑": "⚔️", "召唤": "👥", "元素": "🌈",
}
SPECIAL_RULE_IDS = {
    "trail_multi", "trail_pierce", "trail_loop_explode",
    "trail_fire_wall", "trail_thunder_field", "trail_poison_fog",
    "trail_frost", "trail_slash_wave",
    "combo_black_hole", "combo_fireball", "combo_water_tornado",
    "combo_blade_storm", "combo_thunder",
    "summon_pact",
    "basic_giant_might", "basic_berserker", "basic_demon_hunter",
    "basic_weak_aura", "basic_flame_walk",
    "orb_magnet", "basic_tri_force",
}

TRIGGER_NORMALIZE = {
    "passive": "passive", "on_kill": "on_kill", "on_hit": "on_hit",
    "on_pickup": "on_pickup", "on_loop_close": "on_loop_close",
    "on_combo": "on_combo", "on_slash_end": "on_slash_end",
    "on_death": "on_death", "stage_start": "stage_start", "timer": "timer",
    "condition_hp_50": "hp_below", "condition_hp_30": "hp_below",
    "condition_boss": "vs_boss", "condition_stand": "stand",
    "combo_milestone_5": "combo_milestone",
    "combo_milestone_6": "combo_milestone",
    "combo_milestone_8": "combo_milestone",
    "combo_milestone_10": "combo_milestone",
    "combo_milestone_12": "combo_milestone",
    "combo_milestone_14": "combo_milestone",
}

# 每个 id 的明确字段填值（只填该 id 用到的列；空着的列在 Excel 留空）
# 排列顺序：分组 → 同组按原 xlsx 顺序
PER_ID_FIELDS: dict[str, dict] = {
    # ========== 基础属性 (19) ==========
    "basic_warrior_soul": {"atk_pct": 0.35},
    "basic_tri_force": {"move_speed_pct": 0.10, "atk_speed_pct": 0.15, "max_hp_pct": 0.15},
    "basic_giant_might": {
        "atk_pct_per_lv": 0.15, "max_hp_pct_per_lv": 0.10,
        "move_speed_pct_per_lv": -0.05, "size_pct": 0.10,
    },
    "basic_swift_soul": {"atk_speed_pct_per_lv": 0.15, "move_speed_pct_per_lv": 0.10},
    "basic_godspeed": {"atk_speed_pct_per_lv": 0.10, "ki_regen_pct_per_lv": 0.10},
    "basic_berserker": {
        "trigger_value": 0.50,
        "atk_pct_per_lv": 0.10, "atk_pct_max_total": 0.40,
        "atk_speed_pct": 0.10,
    },
    "basic_demon_hunter": {
        "kill_stack_pct_per_stack": 0.08, "kill_stack_max_count": 5,
        "kill_stack_duration_sec": 3.0,
    },
    "basic_four_leaf": {"luck_pct_per_lv": 0.08},
    "basic_ki_spring": {"ki_regen_pct_per_lv": 0.15, "ki_max_pct_per_lv": 0.08},
    "basic_weak_aura": {
        "aura_vuln_pct_per_lv": 0.20, "aura_vuln_pct_max_total": 0.60,
        "aura_atk_mult": 0.4, "tick_interval_sec": 0.3,
    },
    "basic_luck": {"luck_pct_per_lv": 0.06, "dodge_pct_per_lv": 0.04},
    "basic_wounded": {
        "trigger_value": 5.0,  # 5s 持续
        "atk_pct_per_lv": 0.15, "condition_duration_sec": 5.0,
    },
    "basic_ki_plus": {"ki_max_pct_per_lv": 0.08},
    "basic_move": {"move_speed_pct_per_lv": 0.08},
    "basic_ki_regen": {"ki_regen_pct_per_lv": 0.08},
    "basic_warrior_breath": {"atk_pct_per_lv": 0.08},
    "basic_shrink": {"move_speed_pct": 0.10, "dodge_pct": 0.10, "size_pct": -0.30},
    "basic_boss_slayer": {"boss_dmg_pct_per_lv": 0.15, "boss_heal_full_bool": True},
    "basic_flame_walk": {
        "burn_atk_per_sec": 0.15, "tick_interval_sec": 0.5,
        "duration_sec": 2.0,
    },
    # ========== 生存防御 (11) ==========
    "sv_holy_guard": {"shield_charges": 1},
    "sv_power_soul": {"max_hp_pct_per_lv": 0.15},
    "sv_desperate_heart": {
        "trigger_value": 0.50,
        "atk_pct_per_lv": 0.10, "atk_pct_max_total": 0.30,
    },
    "sv_revive": {"revive_hp_pct": 0.50},
    "sv_desperate_regen": {
        "trigger_value": 0.30,
        "low_hp_regen_pct_per_sec": 0.01, "low_hp_regen_target_pct": 0.30,
    },
    "sv_kill_revive": {
        "heal_proc_chance": 0.20, "heal_pct_per_lv": 0.06,
    },
    "sv_stand_guard": {
        "trigger_value": 1.5,  # 站立 1.5s
        "stand_trigger_sec": 1.5,
        "damage_reduction_pct": 0.30,
        "damage_reduction_pct_per_lv": 0.05,
        "damage_reduction_pct_max_total": 0.50,
    },
    "sv_angel_shelter": {
        "max_hp_pct_per_lv": 0.10,
        "iframe_secs": 1.5, "cooldown_sec": 6.0,
    },
    "sv_blood_power": {"max_hp_pct_per_lv": 0.10, "max_hp_pct_max_total": 0.50},
    "sv_demon_recover": {"heal_proc_chance": 0.15, "heal_pct_per_lv": 0.05},
    "sv_life_spring": {"max_hp_pct_per_lv": 0.08, "heal_pct": 0.30},
    # ========== 普攻子弹 (11) ==========
    "bullet_storm_king": {"bullet_count_add": 3, "atk_speed_pct": 0.15},
    "bullet_spirit_bomb": {"spirit_bomb_distance_pct_max": 0.50},
    "bullet_swift_shoot": {
        "atk_speed_pct_per_lv": 0.30,
        "bullet_dmg_pct_per_lv_penalty": -0.10,
    },
    "bullet_homing": {"homing_bool": True, "atk_pct_per_lv": -0.05},
    "bullet_fire_support": {
        "aoe_bomb_proc_chance_per_lv": 0.10, "aoe_bomb_atk_mult": 0.80,
    },
    "bullet_split": {
        "split_count": 3, "split_atk_mult": 0.50,
        "split_atk_mult_per_lv": 0.10,
    },
    "bullet_bounce": {
        "bounce_add_per_lv": 1, "bounce_max": 3, "bounce_falloff": 0.6,
    },
    "bullet_mirror": {"mirror_return_bool": True, "mirror_return_atk_mult": 0.6},
    "bullet_side": {"side_bullet_count": 2, "side_bullet_angle_deg": 30},
    "bullet_count": {"bullet_count_add_per_lv": 1, "bullet_count_max_total": 3},
    "bullet_beam": {
        "beam_proc_chance_per_lv": 0.10, "beam_atk_mult": 1.0,
        "pierce_enemies_bool": True,
    },
    # ========== 连击 (9) ==========
    "combo_multi": {"weight_per_hit": 0.05, "no_cap_bool": True},
    "combo_black_hole": {
        "weapon_mult": 2.0,
        "milestone_base": 8, "milestone_step_per_lv": -2,
    },
    "combo_fireball": {
        "weapon_mult": 2.5,
        "milestone_base": 14, "milestone_step_per_lv": -2,
    },
    "combo_water_tornado": {
        "weapon_mult": 2.2,
        "milestone_base": 6, "milestone_step_per_lv": -1,
    },
    "combo_blade_storm": {
        "weapon_mult": 2.0,
        "milestone_base": 8, "milestone_blade_add_per_lv": 1,
    },
    "combo_charge": {
        "charge_per_04s_pct": 0.20, "charge_max_mult": 1.5,
    },
    "combo_thunder": {
        "weapon_mult": 3.0,
        "milestone_base": 8, "milestone_step_per_lv": -1,
    },
    "combo_shuriken": {
        "weapon_mult": 0.6,
        "bullet_count_add_per_lv": 2,
    },
    "combo_crit": {
        "crit_rate_per_lv": 0.10, "combo_step": 10,
    },
    # ========== 画线轨迹 (10) ==========
    "trail_multi": {"trail_extra_count": 2},
    "trail_fire_wall": {
        "weapon_mult": 0.8, "tick_interval_sec": 0.5,
        "duration_sec": 5.0, "duration_sec_per_lv": 1.0,
    },
    "trail_thunder_field": {
        "weapon_mult": 0.5, "tick_interval_sec": 0.5,
        "duration_sec": 3.0, "duration_sec_per_lv": 1.0,
        "paralyze_bool": True,
    },
    "trail_poison_fog": {
        "poison_atk_per_sec": 0.35, "tick_interval_sec": 1.0,
        "duration_sec": 4.0, "duration_sec_per_lv": 1.0,
    },
    "trail_frost": {
        "weapon_mult": 0.5, "tick_interval_sec": 0.5,
        "duration_sec": 3.0, "duration_sec_per_lv": 1.0,
        "slow_pct": 0.40,
    },
    "trail_slash_wave": {
        "weapon_mult": 2.5,
        "trail_endwave_radius_px": 200.0,
        "trail_endwave_radius_pct_per_lv": 0.30,
    },
    "trail_loop_explode": {
        "weapon_mult": 3.0,
        "loop_explode_pct_per_lv": 0.30,
        "loop_min_area": 1000.0,
    },
    "trail_pierce": {"pierce_obstacles_bool": True},
    "trail_width": {"trail_width_pct_per_lv": 0.10, "trail_width_pct_max_total": 0.50},
    "trail_dmg": {"trail_dmg_pct_per_lv": 0.08, "trail_dmg_pct_max_total": 0.40},
    # ========== 强化球 (10) ==========
    "orb_tide": {
        "orb_spawn_interval_sec": 8.0, "orb_spawn_interval_reduction_per_lv": 2.0,
    },
    "orb_mark": {"orb_mark_dup_chance": 0.30, "orb_mark_dup_chance_per_lv": 0.05},
    "orb_field": {"orb_count_pct_per_lv": 0.30, "orb_count_pct_max_total": 1.20},
    "orb_magnet": {"orb_magnet_pct_per_lv": 0.30},
    "orb_burst": {"weapon_mult": 1.5, "loop_explode_pct_per_lv": 0.30},
    "orb_glow": {"orb_glow_buff_pct_per_lv": 0.15, "duration_sec": 6.0},
    "orb_fire": {"burn_atk_per_sec": 1.0, "burn_atk_per_sec_per_lv": 0.20},
    "orb_ice": {"freeze_duration_sec": 2.0, "freeze_duration_sec_per_lv": 0.2},
    "orb_poison": {"poison_atk_per_sec": 0.6, "poison_duration_sec": 3.0},
    "orb_thunder": {"weapon_mult": 1.5, "chain_targets_per_lv": 1},
    # ========== 环绕剑 (11) ==========
    "sword_double": {"sword_count_mult": 2.0},
    "sword_rage": {
        "weapon_mult": 2.5, "proc_chance": 0.15,
        "aoe_radius_per_lv": 0.05,
    },
    "sword_guard": {"sword_count_add": 2, "sword_block_bullets_bool": True},
    "sword_length": {"sword_length_pct_per_lv": 0.15, "sword_length_pct_max_total": 0.45},
    "sword_speed": {"sword_speed_pct_per_lv": 0.15, "sword_speed_pct_max_total": 0.45},
    "sword_blood": {
        "sword_count_add": 2, "heal_pct": 0.01, "cooldown_sec": 0.6,
    },
    "sword_dmg": {"sword_dmg_pct_per_lv": 0.15, "sword_dmg_pct_max_total": 0.60},
    "sword_flame": {
        "sword_count_add_per_lv": 1, "burn_atk_per_sec": 0.40,
        "tick_interval_sec": 0.5, "burn_duration_sec": 2.0,
    },
    "sword_thunder": {
        "sword_count_add_per_lv": 1, "weapon_mult": 0.40,
    },
    "sword_poison": {
        "sword_count_add_per_lv": 1, "poison_atk_per_sec": 0.30,
        "poison_duration_sec": 3.0,
    },
    "sword_frost": {
        "sword_count_add_per_lv": 1, "weapon_mult": 0.30,
        "slow_pct": 0.30, "slow_duration_sec": 1.0,
    },
    # ========== 召唤 (10) ==========
    "summon_pact": {
        "summon_dmg_pct": 0.50, "summon_size_pct": 0.15,
        "summon_atk_speed_pct": 0.50, "unlock_unit": "精灵王",
    },
    "summon_rage": {
        "summon_dmg_pct_per_lv": 0.12, "summon_interval_pct_per_lv": -0.12,
    },
    "summon_king": {"weapon_mult": 2.5, "tick_interval_sec": 2.0, "unlock_unit": "精灵王"},
    "summon_god": {"weapon_mult": 1.8, "tick_interval_sec": 1.5, "unlock_unit": "天神"},
    "summon_gorilla": {
        "taunt_radius_px": 500.0, "damage_reduction_pct": 0.30,
        "unlock_unit": "大猩猩",
    },
    "summon_dmg": {"summon_dmg_pct_per_lv": 0.10, "summon_dmg_pct_max_total": 0.50},
    "summon_thunder": {
        "weapon_mult": 1.2, "tick_interval_sec": 2.0,
        "chain_targets": 3, "unlock_unit": "天雷",
    },
    "summon_bear": {
        "weapon_mult": 1.0, "slow_pct": 0.30, "unlock_unit": "北极熊",
    },
    "summon_snake": {
        "poison_atk_per_sec": 1.0, "poison_duration_sec": 4.0, "unlock_unit": "毒蛇",
    },
    "summon_fire": {"weapon_mult": 1.2, "unlock_unit": "火焰精灵"},
    # ========== 元素 (8) ==========
    "elem_fire_plus": {
        "elem_dmg_pct_per_lv": 0.30, "elem_proc_freq_per_lv": 0.15,
    },
    "elem_thunder_plus": {
        "elem_dmg_pct_per_lv": 0.30, "chain_targets_per_lv": 1,
    },
    "elem_poison_plus": {
        "elem_dmg_pct_per_lv": 0.30, "proc_chance": 0.08, "proc_chance_per_lv": 0.08,
    },
    "elem_ice_plus": {
        "elem_dmg_pct_per_lv": 0.30, "proc_chance": 0.08, "proc_chance_per_lv": 0.08,
    },
    "elem_fire_bullet": {
        "proc_chance": 0.45, "proc_chance_per_lv": 0.05,
        "elem_attach_atk_mult": 0.30, "burn_duration_sec": 2.0,
    },
    "elem_thunder_bullet": {
        "proc_chance": 0.45, "proc_chance_per_lv": 0.05,
        "elem_attach_atk_mult": 0.45,
    },
    "elem_poison_bullet": {
        "proc_chance": 0.45, "proc_chance_per_lv": 0.05,
        "elem_attach_atk_mult": 0.25, "poison_duration_sec": 3.0,
    },
    "elem_ice_bullet": {
        "proc_chance": 0.45, "proc_chance_per_lv": 0.05,
        "slow_pct": 0.50, "slow_duration_sec": 1.5,
        "freeze_duration_sec_per_lv": 0.2,
    },
}


def read_v6_raw() -> list[dict]:
    wb = openpyxl.load_workbook(SRC_XLSX, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    headers = [str(h).strip().replace(" ", "_") if h is not None else "" for h in rows[0]]
    out = []
    for raw in rows[1:]:
        if not raw or all(v is None for v in raw):
            continue
        item = {headers[i]: raw[i] for i in range(len(headers)) if headers[i]}
        if not item.get("id"):
            continue
        out.append(item)
    return out


def build_row(raw: dict) -> dict:
    rid = str(raw["id"])
    desc = str(raw["desc_cn"])
    colour = str(raw["colour"])
    group = str(raw["group"])
    raw_dmg_layer = str(raw["dmg_layer"])

    secondary = ""
    dmg_layer = raw_dmg_layer
    if "+" in raw_dmg_layer:
        parts = raw_dmg_layer.split("+", 1)
        dmg_layer = parts[0].strip()
        sec = parts[1].strip().upper()
        secondary = "SURVIVE" if sec == "HP" else sec

    trigger_raw = str(raw.get("trigger", "passive"))
    trigger_type = TRIGGER_NORMALIZE.get(trigger_raw, trigger_raw)

    row: dict = {h_en: "" for _, h_en in HEADERS_CN_EN}
    # 元信息
    row["id"] = rid
    row["name_cn"] = str(raw["name_cn"])
    row["group"] = group
    row["rarity"] = COLOUR_TO_RARITY.get(colour, "white")
    row["icon"] = GROUP_DEFAULT_ICON.get(group, "")
    row["desc_cn"] = desc
    row["max_level"] = int(raw.get("max_level", 1))
    row["pool_weight"] = int(raw.get("pool_weight", 100))
    row["once_per_run"] = 1 if rid == "sv_revive" else 0
    row["once_per_chapter"] = 0
    row["special_rule"] = 1 if rid in SPECIAL_RULE_IDS else 0
    row["notes"] = str(raw.get("notes", ""))
    # 标签
    row["dmg_layer"] = dmg_layer
    row["secondary_layer"] = secondary
    row["element"] = DMG_LAYER_TO_ELEMENT.get(dmg_layer, "")
    row["category"] = GROUP_TO_CATEGORY.get(group, "")
    # 触发器
    row["trigger_type"] = trigger_type
    # combo_milestone 的 value 从原始 trigger 名抽数字
    if trigger_type == "combo_milestone":
        for n in (5, 6, 8, 10, 12, 14):
            if str(n) in trigger_raw:
                row["trigger_value"] = n
                break
    # 应用 PER_ID_FIELDS 覆盖
    explicit = PER_ID_FIELDS.get(rid, {})
    for k, v in explicit.items():
        if isinstance(v, bool):
            row[k] = 1 if v else 0
        else:
            row[k] = v
    return row


def write_xlsx(rows: list[dict]) -> None:
    OUT_XLSX.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "rewards_v6_detailed"

    fill_cn = PatternFill("solid", fgColor="4472C4")
    fill_en = PatternFill("solid", fgColor="A5C4F2")
    font_cn = Font(color="FFFFFF", bold=True)
    font_en = Font(color="1F3864", bold=False, italic=True)
    center = Alignment(horizontal="center", vertical="center", wrap_text=True)

    # 第 1 行：中文 header
    cn_headers = [cn for cn, _ in HEADERS_CN_EN]
    en_headers = [en for _, en in HEADERS_CN_EN]
    ws.append(cn_headers)
    for c in ws[1]:
        c.fill = fill_cn
        c.font = font_cn
        c.alignment = center
    # 第 2 行：英文 key
    ws.append(en_headers)
    for c in ws[2]:
        c.fill = fill_en
        c.font = font_en
        c.alignment = center

    # 数据行
    for r in rows:
        ws.append([r.get(en, "") for en in en_headers])

    # 冻结前 4 列（id/name/group/rarity）+ 前 2 行 header
    ws.freeze_panes = "E3"

    # 列宽：根据中文长度 + 4
    for col_idx, cn in enumerate(cn_headers, start=1):
        letter = get_column_letter(col_idx)
        ws.column_dimensions[letter].width = max(8, min(len(cn) * 2 + 2, 24))

    # 头两行行高
    ws.row_dimensions[1].height = 32
    ws.row_dimensions[2].height = 20

    wb.save(OUT_XLSX)
    print(f"Wrote {OUT_XLSX}")


def main() -> None:
    raw = read_v6_raw()
    print(f"Loaded {len(raw)} entries from {SRC_XLSX.name}")
    rows = [build_row(r) for r in raw]
    write_xlsx(rows)
    print(f"Total columns: {len(HEADERS_CN_EN)}")
    print(f"Total rows: {len(rows)}")
    print("Done.")


if __name__ == "__main__":
    main()
