#!/usr/bin/env python3
"""一次性脚本：5-sheet 格式的奖励配置表（v6 schema，给程序员评审）。

Sheet1 rewards：99 项奖励主表
  - 每张卡最多 4 个属性槽，每槽 3 列 (attr_id, value, value_per_lv)
  - 触发器（含条件数值每级） / 基础伤害 ATK 倍率 / 元素状态布尔列独立维护
  - 专属规则 + 专属数值 + 专属数值每级 表达单卡机制
  - applies_fire / applies_ice / applies_thunder / applies_poison 标记元素状态
Sheet2 attr_codes：42 条共享 attr code（面板 / 计数 / 剑 / 生存 / 召唤 / 元素 / 计时）
Sheet3 damage_formula：完整 v2 战斗伤害公式
Sheet4 element_effects：统一四大元素状态基础值表
Sheet5 lookups：group / rarity / trigger_type / special_rule 编码对照

输出：config/excel/rewards_v6_compact.xlsx
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parents[1]
SRC_XLSX = ROOT / "ys构思_v6.xlsx"
OUT_XLSX = ROOT / "config" / "excel" / "rewards_v6_compact.xlsx"


# ========== 属性编码表 ==========
# 字段顺序：(code, category_cn, name_cn, en_key, description)
ATTR_CODES: list[tuple[int, str, str, str, str]] = [
    # ----- 面板属性 -----
    (1, "面板", "攻击%", "atk_pct", "攻击百分比（base 一次性 / per_lv 每级递增）"),
    (2, "面板", "攻速%", "atk_speed_pct", "攻速百分比"),
    (3, "面板", "移速%", "move_speed_pct", "移速百分比"),
    (4, "面板", "最大生命%", "max_hp_pct", "最大生命百分比"),
    (5, "面板", "气力上限%", "ki_max_pct", "气力上限百分比"),
    (6, "面板", "气力回复%", "ki_regen_pct", "气力回复百分比"),
    (7, "面板", "暴击率", "crit_rate", "暴击率（0.05 = +5%）"),
    (8, "面板", "闪避%", "dodge_pct", "闪避率"),
    (9, "面板", "幸运%", "luck_pct", "幸运（影响品质爆率）"),
    (10, "面板", "体型%", "size_pct", "体型百分比（正=大、负=小）"),
    (11, "面板", "减伤%", "damage_reduction_pct", "受伤减免"),
    # ----- 计数 -----
    (12, "计数", "子弹数量+", "bullet_count_add", "增加子弹数（base / per_lv 均整数）"),
    # ----- 剑（按类型拆分） -----
    (13, "剑", "守护剑数量+", "sword_guard_count_add", "守护剑（阻挡子弹）数量"),
    (14, "剑", "嗜血剑数量+", "sword_blood_count_add", "嗜血剑（命中回血）数量"),
    (15, "剑", "火焰剑数量+", "sword_flame_count_add", "火焰剑数量（附加燃烧）"),
    (16, "剑", "雷霆剑数量+", "sword_thunder_count_add", "雷霆剑数量（附加雷链）"),
    (17, "剑", "毒刺剑数量+", "sword_poison_count_add", "毒刺剑数量（附加中毒）"),
    (18, "剑", "寒霜剑数量+", "sword_frost_count_add", "寒霜剑数量（附加减速 + 冰伤）"),
    # ----- 生存 -----
    (19, "生存", "回血%", "heal_pct", "立即/触发回血百分比（触发概率走「触发概率」列）"),
    (20, "生存", "击杀回血%", "kill_heal_pct", "击杀时回血量（触发概率走「触发概率」列）"),
    # ----- 召唤伤害 -----
    (21, "召唤", "召唤伤害%", "summon_dmg_pct", "召唤物伤害百分比（影响所有召唤）"),
    # ----- 召唤单位（按类型拆分；满级 3，每级多召 1 只） -----
    (22, "召唤", "精灵王召唤数+", "summon_king_count_add", "精灵王（AOE）召唤数量"),
    (23, "召唤", "天神召唤数+", "summon_god_count_add", "天神（远程单体）召唤数量"),
    (24, "召唤", "大猩猩召唤数+", "summon_gorilla_count_add", "大猩猩（嘲讽）召唤数量"),
    (25, "召唤", "天雷召唤数+", "summon_thunder_count_add", "天雷（AOE 雷链）召唤数量"),
    (26, "召唤", "北极熊召唤数+", "summon_bear_count_add", "北极熊（近战冰伤）召唤数量"),
    (27, "召唤", "毒蛇召唤数+", "summon_snake_count_add", "毒蛇（毒伤 DoT）召唤数量"),
    (28, "召唤", "火焰精灵召唤数+", "summon_fire_spirit_count_add", "火焰精灵（火伤）召唤数量"),
    # ----- 元素覆盖（4 元素拆分） -----
    (29, "元素", "火元素伤害%", "elem_fire_pct", "火元素 ELEM 层加成（火伤+ 用）"),
    (30, "元素", "冰元素伤害%", "elem_ice_pct", "冰元素 ELEM 层加成（冰伤+ 用）"),
    (31, "元素", "雷元素伤害%", "elem_thunder_pct", "雷元素 ELEM 层加成（雷伤+ 用）"),
    (32, "元素", "毒元素伤害%", "elem_poison_pct", "毒元素 ELEM 层加成（毒伤+ 用）"),
    (33, "元素", "元素触发频率%", "elem_proc_freq_pct", "燃烧/中毒 tick 频率（火伤+ / 毒伤+ 用）"),
    (34, "元素", "减速增益%", "slow_pct_bonus", "在 Sheet4 base slow_pct 之上额外加成（冰伤+ 用）"),
    (35, "元素", "雷链目标+", "chain_targets_bonus", "在 Sheet4 base chain_targets 之上额外加目标数（雷伤+ 用，整数）"),
    (36, "元素", "火附伤倍率", "elem_fire_attach_atk_mult", "覆盖 Sheet4 burn_atk_per_sec 默认（仅当本卡需偏离 Sheet4 base 时用）"),
    (37, "元素", "冰附伤倍率", "elem_ice_attach_atk_mult", "覆盖 Sheet4 hit_atk_mult 默认（仅当本卡需偏离 Sheet4 base 时用）"),
    (38, "元素", "雷附伤倍率", "elem_thunder_attach_atk_mult", "覆盖 Sheet4 chain_atk_mult 默认（仅当本卡需偏离 Sheet4 base 时用）"),
    (39, "元素", "毒附伤倍率", "elem_poison_attach_atk_mult", "覆盖 Sheet4 poison_atk_per_sec 默认（仅当本卡需偏离 Sheet4 base 时用）"),
    # ----- 通用计时 -----
    (40, "计时", "冷却秒", "cooldown_sec", "触发冷却"),
    (41, "计时", "持续秒", "duration_sec", "通用持续秒（轨迹/光环/buff）"),
    (42, "计时", "tick间隔秒", "tick_interval_sec", "周期性效果间隔"),
    # ----- 主题召唤 / 主题剑（仅恶魔/天使主题关解锁）-----
    (43, "召唤", "恶魔宝宝召唤数+", "summon_demon_baby_count_add", "恶魔宝宝（远程激光穿透）召唤数量"),
    (44, "召唤", "天使宝宝召唤数+", "summon_angel_baby_count_add", "天使宝宝（远程单体雷伤）召唤数量"),
    (45, "剑", "命运之矛数量+", "sword_spear_count_add", "命运之矛（环绕长枪）数量"),
    # ----- 追加 -----
    (46, "剑", "环绕盾数量+", "shield_orbit_count_add", "环绕盾（阻挡敌方远程子弹）数量"),
    # ----- 心数制：绝对心数加成（1.0=1颗心=1HP）。base 3 心。取代旧 attr 4 max_hp_pct 的所有用法 -----
    (47, "面板", "最大生命+", "max_hp_add", "最大生命绝对值（1.0=1颗心，0.5=半心）"),
]

EN_KEY_TO_CODE: dict[str, int] = {en: c for c, _, _, en, _ in ATTR_CODES}


# ========== 元数据编码表 ==========

GROUP_CODES: list[tuple[int, str]] = [
    (1, "基础属性"),
    (2, "生存防御"),
    (3, "普攻子弹"),
    (4, "连击"),
    (5, "画线轨迹"),
    (6, "强化球"),
    (7, "环绕剑"),
    (8, "召唤"),
    (9, "元素"),
    (10, "恶魔"),
    (11, "天使"),
]
GROUP_NAME_TO_CODE = {n: c for c, n in GROUP_CODES}

RARITY_CODES: list[tuple[int, str, str]] = [
    (1, "white", "白"),
    (2, "blue", "蓝"),
    (3, "purple", "紫"),
    (4, "orange", "橙"),
]
COLOUR_TO_RARITY_CODE = {"白": 1, "蓝": 2, "紫": 3, "橙": 4}

TRIGGER_CODES: list[tuple[int, str, str]] = [
    (1, "passive", "常驻"),
    (2, "on_hit", "受击时"),
    (3, "on_kill", "击杀时"),
    (4, "on_pickup", "拾取时"),
    (5, "on_combo", "每次连击时"),
    (6, "on_slash_end", "划线斩击结束"),
    (7, "on_loop_close", "轨迹首次闭合"),
    (8, "on_death", "死亡时"),
    (9, "stage_start", "每关开始"),
    (10, "timer", "定时器"),
    (11, "hp_below", "HP 低于阈值（条件数值 = HP%）"),
    (12, "vs_boss", "对 Boss 战"),
    (13, "stand", "站立达阈值（条件数值 = 秒）"),
    (14, "combo_milestone", "连击数达里程碑（条件数值 = 触发段位；条件数值每级 = 每级段位增量，-1 = 每级少 1 段）"),
]
TRIGGER_KEY_TO_CODE = {k: c for c, k, _ in TRIGGER_CODES}


# ========== 元数据映射 ==========

GROUP_DEFAULT_ICON = {
    "基础属性": "💪", "生存防御": "🛡️", "普攻子弹": "🔫", "连击": "🌀",
    "画线轨迹": "✨", "强化球": "🔮", "环绕剑": "⚔️", "召唤": "👥", "元素": "🌈",
    "恶魔": "👹", "天使": "😇",
}
SPECIAL_RULE_CODES: list[tuple[int, str, str, str, str]] = [
    # (type_id, type_key, name_cn, schema 数组字段顺序, 数组字段中文含义)
    # 0 = 纯属性卡，不需要 GDScript 写专属机制
    (0, "none", "无（纯属性）", "[]", "无专属数值"),
    # ---- 基础属性 ----
    (1, "on_hit_window", "受击触发限时增伤", "[]（duration 走 attr 36）", "无专属数值；持续秒走属性槽 duration_sec"),
    (2, "kill_stack", "击杀叠层", "[stack_pct, max_stacks, duration_sec]",
        "每层攻击%；最大叠层数；叠层持续秒"),
    (3, "aura", "光环易伤+伤害", "[radius_px, tick_sec, atk_mult, vuln_per_lv]",
        "光环半径(像素)；tick 间隔秒；每 tick 的 ATK 倍率；每级易伤增量"),
    (4, "boss_target", "Boss 针对", "[boss_dmg_per_lv, heal_full_on_boss]",
        "对 Boss 每级增伤%；遇 Boss 是否满血(1/0)"),
    (5, "trail_burn_walk", "火焰行走", "[atk_mult, tick_sec, duration_sec]",
        "脚下火地每 tick 的 ATK 倍率；tick 间隔秒；火地持续秒"),
    # ---- 生存 ----
    (6, "shield", "护盾", "[charges, blocks_lethal, on_stage_start]",
        "护盾层数；是否挡致死(1/0)；是否每关开始时给予(1/0)"),
    (7, "revive", "复活", "[revive_hp_pct, once_per_run]",
        "复活时恢复 HP%；是否每局仅一次(1/0)"),
    (8, "low_hp_regen", "低血再生", "[hp_threshold, regen_pct_per_sec, regen_per_lv, target_hp_pct]",
        "触发的 HP 阈值；每秒回血%(基础)；每级回血%增量；最高回到的 HP%"),
    (9, "stand_guard", "站立减伤", "[]（值在 attr/tv）",
        "无专属数值；减伤%走属性槽，触发秒走 trigger_value"),
    (10, "iframe_on_hit", "受击无敌", "[iframe_sec]（CD 走 attr 35）",
        "无敌持续秒；冷却走属性槽 cooldown_sec"),
    # ---- 子弹专属机制 ----
    (11, "bullet_distance_scale", "元气弹", "[dmg_pct_max]",
        "随飞行距离最高加成%"),
    (12, "bullet_homing", "追踪", "[homing_flag]",
        "是否追踪(1/0)"),
    (13, "bullet_proc_spell", "普攻概率触发法术", "[proc_base, proc_per_lv, atk_mult, radius_px]",
        "基础触发概率；每级概率增量；法术 ATK 倍率；法术半径(像素)"),
    (14, "bullet_split", "命中分裂", "[count, atk_mult_base, atk_mult_per_lv]",
        "分裂出的子弹数；基础 ATK 倍率；每级倍率增量"),
    (15, "bullet_bounce", "弹射", "[bounce_per_lv, falloff]",
        "每级增加的弹射次数；每次弹射衰减(0~1)"),
    (16, "bullet_mirror", "镜像回弹", "[return_atk_mult]",
        "回弹弹的 ATK 倍率"),
    (17, "bullet_side", "斜射", "[count, angle_deg]",
        "斜射子弹数；左右偏移角度"),
    (18, "bullet_beam", "能量光束", "[proc_base, proc_per_lv, atk_mult, pierce]",
        "基础触发概率；每级概率增量；光束 ATK 倍率；是否穿透(1/0)"),
    # ---- 连击 ----
    (19, "combo_count_mult", "造成连击数翻倍", "[combo_gain_mult]",
        "单次斩击产生的连击数倍率(2.0 = 双倍连击)"),
    (20, "combo_milestone_spell", "连击里程碑法术", "[shape, radius_px, extra_blade_per_lv]（shape ∈ line/circle/point）",
        "形状(line/circle/point)；半径(像素，0=不适用)；每级追加刀数(空=不用)"),
    (21, "combo_charge", "蓄力击", "[charge_per_04s_pct, charge_max_mult]",
        "每 0.4s 蓄力增伤%；蓄满最大倍率"),
    (22, "combo_shuriken", "连击辅助子弹", "[shape, random_dir]",
        "形状(line/circle 等)；是否随机方向(1/0)"),
    (23, "combo_crit", "连击里程碑暴击", "[combo_step]",
        "每多少连击数触发一次必暴"),
    # ---- 画线轨迹 ----
    (24, "trail_extra", "多重轨迹", "[extra_count]",
        "额外轨迹条数"),
    (25, "trail_elem_field", "元素轨迹场域", "[atk_mult, tick_sec, slow_pct, stun_sec, ramp_per_sec, bullet_attach]",
        "每 tick 的 ATK 倍率；tick 间隔秒；override 减速%(空=用Sheet4)；眩晕秒；每秒伤害爬升%；是否让子弹附状态(1/0)"),
    (26, "trail_endwave", "划线末端推开", "[radius_base, radius_per_lv]",
        "基础推开半径(像素)；每级半径增量(像素)"),
    (27, "trail_loop_explode", "闭合爆炸", "[weapon_mult_per_lv, min_area]",
        "每级闭合爆炸的武器倍率增量；触发的最小闭合面积"),
    (28, "trail_pierce", "穿障碍", "[pierce_obstacles]",
        "是否穿障碍(1/0)"),
    (29, "trail_width_buff", "轨迹宽度", "[width_pct_per_lv]",
        "每级轨迹宽度%"),
    (30, "trail_dmg_buff", "轨迹伤害", "[dmg_pct_per_lv]",
        "每级轨迹伤害%"),
    # ---- 强化球 ----
    (31, "orb_spawn", "球生成间隔", "[spawn_interval_base, spawn_interval_per_lv]",
        "基础生成间隔秒；每级间隔变化秒(负=变快)"),
    (32, "orb_mark", "球印记复制", "[dup_chance_base, dup_chance_per_lv]",
        "基础复制概率；每级概率增量"),
    (33, "orb_field", "场上球数量", "[count_pct_per_lv]",
        "每级场上球数%增量"),
    (34, "orb_magnet", "球磁吸", "[pickup_radius_pct_per_lv, line_magnet_pct_per_lv]",
        "每级拾取半径%；每级划线吸附%"),
    (35, "orb_burst", "拾取爆炸", "[weapon_mult]",
        "拾取爆炸的武器倍率"),
    (36, "orb_glow", "球之微光", "[dmg_pct_per_lv]（duration 在 attr 36）",
        "每级增伤%；持续秒走属性槽 duration_sec"),
    (37, "orb_elem_aoe", "元素球 AOE", "[weapon_mult, element]（元素状态由 Sheet4 自动应用）",
        "AOE 武器倍率；元素 key(fire/ice/thunder/poison)"),
    # ---- 环绕剑 ----
    (38, "sword_count_mult", "剑数翻倍", "[count_mult]",
        "总剑数倍率"),
    (39, "sword_proc_spell", "剑触发法术", "[proc_chance, atk_mult, radius_per_lv]",
        "触发概率；法术 ATK 倍率；每级法术半径增量"),
    (40, "sword_unit", "剑单位（典型剑）", "[atk_mult, hit_interval_sec, element, p1, p2, p3] / p1-3 仅用于守护剑 block_bullets 或 override Sheet4；元素自带状态由 Sheet4 自动应用",
        "ATK 倍率；命中间隔秒；元素(none/fire/ice/thunder/poison)；p1-p3 仅守护剑用(block_bullets)或 override Sheet4 base"),
    (41, "sword_length_buff", "剑长度", "[length_pct_per_lv]",
        "每级剑长度%"),
    (42, "sword_speed_buff", "剑转速", "[speed_pct_per_lv]",
        "每级剑转速%"),
    (43, "sword_dmg_buff", "剑伤害", "[dmg_pct_per_lv]",
        "每级剑伤害%"),
    # ---- 召唤 ----
    (44, "summon_pact", "召唤盟约", "[summon_size_pct, summon_atk_speed_pct]",
        "召唤物体型%；召唤物攻速%（解锁的单位走属性槽 summon_*_count_add += 1 表达，与其他召唤卡一致）"),
    (45, "summon_unit", "召唤单位", "[atk_mult, atk_interval_sec, range_px, element, mechanic, p1, p2] / mechanic ∈ ranged_single/ranged_aoe/ranged_taunt/random_aoe/ranged_laser；p1-2 仅用于 ranged_aoe 的 radius_px 或 ranged_taunt 的 cd/duration；ranged_laser = 持续穿透激光（无 p1/p2）；元素自带状态由 Sheet4 自动应用",
        "ATK 倍率；攻击间隔秒；攻击距离(像素)；元素；机制(ranged_single/ranged_aoe/ranged_taunt/random_aoe/ranged_laser)；p1=AOE 半径或嘲讽 CD；p2=嘲讽持续秒"),
    # 元素子弹 (elem_*_bullet) 走 sr=0：机制由 applies_<elem> 布尔列直接触发 Sheet4 element_effects，
    # 不需要 dispatcher 实现 — 见 CLAUDE.md 第 3 条。
    # ---- 主题关专属（恶魔 / 天使，46-50）----
    (46, "scythe_on_slash_end", "死神镰刀（划线末释放无限射程贯通镰刀）",
        "[atk_mult, pierce]",
        "镰刀 ATK 倍率；是否贯通(1/0)；射程无限"),
    (47, "periodic_laser", "硫磺火（定时无限激光）",
        "[atk_mult_per_tick, tick_interval_sec, element]",
        "激光每 tick 的 ATK 倍率；tick 间隔秒；元素 key(fire/ice/thunder/poison)；冷却走属性槽 cooldown_sec；持续走 duration_sec；元素状态由 Sheet4 自动应用"),
    (48, "multi_revive", "多命复活（九命猫）",
        "[extra_lives, max_hp_after_revive_abs]",
        "额外复活次数（初始 1 命之外）；复活后绝对 HP 值（1 = 1HP）"),
    (49, "blood_bullet", "血飞刀（普攻替换为穿透血刃）",
        "[pierce, range_mult]",
        "是否穿透(1/0)；射程倍率；攻速/攻击调整走属性槽 atk_speed_pct / atk_pct"),
    (50, "proximity_slow", "无下限术式（近距离怪物线性减速）",
        "[aura_radius_px, max_slow_pct]",
        "光环半径(像素)；最大减速%（距离玩家越近减速越高，线性插值）"),
    # ---- 追加：普攻 / 画线 / 召唤 改造类 (51-56) ----
    (51, "psychic_petrify_all", "念力全场石化（画线末尾触发）",
        "[freeze_duration_sec, aura_radius_px]",
        "石化持续秒（每级增量）；aura 半径预留（实际全场）；石化=灰色 tint+完全定身；元素状态由 applies_ice 触发"),
    (52, "periodic_iframe", "定时无敌（独角兽）",
        "[]",
        "CD 走属性槽 attr 40 cooldown_sec；持续走属性槽 attr 41 duration_sec；invincible 期间 player.modulate 走 HSV hue 旋转"),
    (53, "laser_cannon_basic", "普攻改蓄力激光炮",
        "[atk_mult, color_key, pierce]",
        "激光 ATK 倍率；颜色 key（white/fire/ice/thunder）；是否穿透(1/0)；蓄力速度受玩家攻速影响；环形蓄力条跟随玩家右上方"),
    (54, "melee_basic", "普攻改近战挥砍",
        "[atk_bonus_pct, melee_range_px]",
        "额外攻击加成%；近战射程像素；sr 内部强锁 bullet_count=1；无子弹外观"),
    (55, "bomb_on_slash_end", "炸弹人（画线末尾埋炸弹）",
        "[atk_mult, fuse_sec, cross_arm_px]",
        "爆炸 ATK 倍率；引信秒数；十字臂长像素；引信到时十字 AOE"),
    (56, "orbit_shield", "环绕盾（阻挡敌方子弹）",
        "[orbit_radius_px, orbit_speed_rad_per_sec]",
        "轨道半径像素；自转角速 (rad/s)；数量走属性槽 attr 46 shield_orbit_count_add"),
]

# rid -> (type_id, special_values_array)
# 0/未列在内的卡 = 纯属性卡（sr=0，无 special_values）
SPECIAL_RULES: dict[str, tuple[int, list]] = {
    # 基础属性
    "basic_tri_force":      (0, []),
    "basic_giant_might":    (0, []),
    "basic_berserker":      (0, []),
    "basic_demon_hunter":   (2, [0.08, 5, 3]),
    "basic_weak_aura":      (3, [200, 0.3, 0.4, 0.20]),
    "basic_wounded":        (1, []),
    "basic_boss_slayer":    (4, [0.15, 1]),
    "basic_flame_walk":     (5, [0.15, 0.5, 2]),
    # 生存
    "sv_holy_guard":        (6, [1, 1, 1]),
    "sv_desperate_heart":   (0, []),
    "sv_revive":            (7, [0.50, 1]),
    "sv_desperate_regen":   (8, [0.30, 0.01, 0.01, 0.30]),
    "sv_stand_guard":       (9, []),
    "sv_angel_shelter":     (10, [1.5]),
    # 普攻子弹
    "bullet_spirit_bomb":   (11, [0.50]),
    "bullet_swift_shoot":   (0, []),
    "bullet_homing":        (12, [1]),
    "bullet_fire_support":  (13, [0.10, 0.10, 0.80, 100]),
    "bullet_split":         (14, [3, 0.50, 0.10]),
    "bullet_bounce":        (15, [1, 0.6]),
    "bullet_mirror":        (16, [0.6]),
    "bullet_side":          (17, [2, 30]),
    "bullet_beam":          (18, [0.10, 0.10, 1.0, 1]),
    # 连击
    "combo_multi":          (19, [2.0]),
    "combo_black_hole":     (20, ["point", 0, None]),
    "combo_fireball":       (20, ["line", 0, None]),
    "combo_water_tornado":  (20, ["line", 0, None]),
    "combo_blade_storm":    (20, ["circle", 150, 1]),
    "combo_thunder":        (20, ["circle", 200, None]),
    "combo_charge":         (21, [0.20, 1.5]),
    "combo_shuriken":       (22, ["line", 1]),
    "combo_crit":           (23, [10]),
    # 轨迹
    "trail_multi":          (24, [2]),
    "trail_fire_wall":      (25, [0.8, 0.5, None, None, None, 1]),
    "trail_thunder_field":  (25, [0.5, 0.5, None, 0.3, None, None]),
    "trail_poison_fog":     (25, [0.35, 1.0, None, None, 0.25, None]),
    "trail_frost":          (25, [0.5, 0.5, 0.40, None, None, None]),
    "trail_slash_wave":     (26, [200, 100]),
    "trail_loop_explode":   (27, [0.30, 1000]),
    "trail_pierce":         (28, [1]),
    "trail_width":          (29, [0.10]),
    "trail_dmg":            (30, [0.10]),
    # 强化球
    "orb_tide":             (31, [10, -1]),
    "orb_mark":             (32, [0.30, 0.05]),
    "orb_field":            (33, [0.30]),
    "orb_magnet":           (34, [0.30, 0.30]),
    "orb_burst":            (35, [1.5]),
    "orb_glow":             (36, [0.15]),
    "orb_fire":             (37, [1.0, "fire"]),
    "orb_ice":              (37, [1.0, "ice"]),
    "orb_poison":           (37, [1.0, "poison"]),
    "orb_thunder":          (37, [1.0, "thunder"]),
    # 剑
    "sword_double":         (38, [2.0]),
    "sword_rage":           (39, [0.15, 2.5, 0.05]),
    "sword_guard":          (40, [0.8, 0.5, "none", 1, None, None]),
    "sword_length":         (41, [0.15]),
    "sword_speed":          (42, [0.15]),
    "sword_blood":          (40, [1.0, 0.6, "none", None, None, None]),
    "sword_dmg":            (43, [0.15]),
    "sword_flame":          (40, [0.40, 0.5, "fire", None, None, None]),
    "sword_thunder":        (40, [0.40, 0.5, "thunder", None, None, None]),
    "sword_poison":         (40, [0.30, 0.5, "poison", None, None, None]),
    "sword_frost":          (40, [0.30, 0.5, "ice", None, None, None]),
    # 召唤
    "summon_pact":          (44, [0.15, 0.50]),
    "summon_rage":          (0, []),  # 数值全在 attr 21；纯属性卡
    "summon_king":          (45, [1.2, 2.5, 600, "none", "ranged_aoe", 200, None]),
    "summon_god":           (45, [1.8, 1.5, 500, "none", "ranged_single", None, None]),
    "summon_gorilla":       (45, [1.0, 1.0, 400, "none", "ranged_taunt", 10, 3]),
    "summon_thunder":       (45, [1.2, 3.0, 0, "thunder", "random_aoe", None, None]),
    "summon_bear":          (45, [1.0, 1.0, 500, "ice", "ranged_single", None, None]),
    "summon_snake":         (45, [1.0, 1.0, 500, "poison", "ranged_single", None, None]),
    "summon_fire":          (45, [1.2, 1.5, 500, "fire", "ranged_single", None, None]),
    # 元素子弹：sr=0；元素状态由 applies_<elem> 布尔列 → Sheet4 自动触发
    "elem_fire_bullet":     (0, []),
    "elem_thunder_bullet":  (0, []),
    "elem_poison_bullet":   (0, []),
    "elem_ice_bullet":      (0, []),
    # ===== 主题关：恶魔（group=10）=====
    "demon_scythe":         (46, [4.0, 1]),
    "demon_sulfur_laser":   (47, [0.5, 0.1, "fire"]),
    "demon_baby":           (45, [1.5, 1.2, 600, "fire", "ranged_laser", None, None]),
    "demon_nine_lives":     (48, [8, 1]),
    "demon_vampire":        (0, []),  # 纯属性 + trigger=on_kill + proc_chance + attr 20
    "demon_blood_blade":    (49, [1, 2.0]),
    # ===== 主题关：天使（group=11）=====
    # sv_holy_guard 已在生存防御段：(6, [1,1,1])，仅源表改 group → 天使，不动 SR
    "angel_holy_bullet":    (13, [0.10, 0, 2.0, 150]),  # 复用 bullet_proc_spell
    "angel_light_ward":     (0, []),  # 纯属性 attr 11
    "angel_baby":           (45, [1.5, 1.0, 550, "thunder", "ranged_single", None, None]),
    "angel_fate_spear":     (40, [1.5, 0.4, "none", None, None, None]),  # 复用 sword_unit
    "angel_proximity_slow": (50, [300, 0.50]),
}

# rid -> special_values_per_lv 数组（与 SPECIAL_RULES 的 special_values 等长，
# 每位是「该字段每级递增量」；未列出 = 全 0，写表时空白）。
# 例：basic_demon_hunter special_values=[0.08, 5, 3]（每层 8% 攻击，最多 5 层，持续 3s），
#     若策划要求每级 +0.02 攻击 / +1 层 / +0.5s，就写 [0.02, 1, 0.5]
SPECIAL_RULES_PER_LV: dict[str, list] = {
    # 描述里出现"+X/级"的卡，按 sv 数组的位置对位写每级增量。
    # 描述里没说"/级"的位填 None，整张卡没有"/级"的 → 不写在本字典里。
    # 注：单纯属性升级（如 attr_pct/级、元素状态时长/级）走属性槽 / Sheet4，不在本字典。
    "basic_weak_aura":     [None, None, None, 0.20],   # 易伤 +20%/级
    "basic_boss_slayer":   [0.15, None],               # 对 BOSS +15%/级
    "sv_desperate_regen":  [None, None, 0.01, None],   # 每秒回血 +1%/级
    "bullet_fire_support": [None, 0.10, None, None],   # 普攻 +10%/级 概率
    "bullet_split":        [None, None, 0.10],         # 分裂子弹 ATK +10%/级
    "bullet_bounce":       [1, None],                  # 弹射 +1 次/级
    "bullet_beam":         [None, 0.10, None, None],   # 普攻 +10%/级 概率
    "combo_blade_storm":   [None, None, 1],            # 旋风每级 +1 把刀
    "combo_charge":        [0.20, None],               # 斩击伤害 +20%/级
    "trail_slash_wave":    [None, 100],                # 推开半径 +100px/级
    "trail_loop_explode":  [0.30, None],               # 闭合爆炸倍率 +0.3/级
    "trail_width":         [0.10],                     # 轨迹宽度 +10%/级
    "trail_dmg":           [0.10],                     # 画线伤害 +10%/级
    "orb_tide":            [None, -1],                 # 生成间隔每级 -1s
    "orb_mark":            [None, 0.05],               # 复制印记加成 +5%/级
    "orb_field":           [0.30],                     # 场上球数量 +30%/级
    "orb_magnet":          [0.30, 0.30],               # 拾取半径 +30%/级，划线吸附 +30%/级
    "orb_burst":           [0.3],                      # 拾取爆炸倍率 +0.3/级
    "orb_glow":            [0.15],                     # 拾取后画线增伤 +15%/级
    "orb_fire":            [0.2, None],                # AOE 倍率 +0.2/级
    "sword_rage":          [None, None, 0.05],         # 旋风范围 +5%/级
    "sword_length":        [0.15],                     # 剑长度 +15%/级
    "sword_speed":         [0.15],                     # 剑转速 +15%/级
    "sword_dmg":           [0.15],                     # 剑伤害 +15%/级
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


# 源表 dmg_layer 值 → (主表「卡牌路径」, build 标签) 两轴拆分
# H1/H2/H3/H4/META 是策划 build 标签（路径默认 physical，下面按 group 微调到实际路径）；build 标签仅作内部判断，不写主表
# 其他值是直接的卡牌路径或非伤害类
DMG_LAYER_SPLIT: dict[str, tuple[str, str]] = {
    "H1":        ("physical", "H1"),
    "H1+HP":     ("survive",  "H1"),  # basic_giant_might（原来唯一走 secondary 的卡）
    "H2":        ("physical", "H2"),
    "H3":        ("physical", "H3"),
    "H4":        ("physical", "H4"),
    "META":      ("meta",     "META"),
    "BULLET":    ("bullet",   ""),
    "COMBO":     ("combo",    ""),
    "TRAIL":     ("trail",    ""),
    "SWORD":     ("sword",    ""),
    "SUMMON":    ("summon",   ""),
    "E_FIRE":    ("element",  ""),    # 具体元素由 applies_<elem> 布尔列决定
    "E_ICE":     ("element",  ""),
    "E_THUNDER": ("element",  ""),
    "E_POISON":  ("element",  ""),
    "SURVIVE":   ("survive",  ""),
    "DEBUFF":    ("debuff",   ""),
}

# group 编码 → 默认来源（用于把 H1-H4/META 这些 build 标签里的卡微调到正确来源）
GROUP_CODE_TO_DMG_SOURCE: dict[int, str] = {
    3: "bullet", 4: "combo", 5: "trail", 6: "meta", 7: "sword", 8: "summon", 9: "element",
}

# 给 lookups Sheet 展示用的"卡牌路径"取值说明
# 前 7 个会进伤害结算（增伤层按路径独立加和 dmg_<path>_pct）；后 3 个不进
CARD_PATH_CODES: list[tuple[str, str]] = [
    ("physical", "物理（基础属性卡 / 受击触发等；进伤害结算）"),
    ("bullet",   "普攻子弹（进伤害结算）"),
    ("combo",    "连击触发法术（进伤害结算）"),
    ("trail",    "划线轨迹（进伤害结算）"),
    ("sword",    "环绕剑（进伤害结算）"),
    ("summon",   "召唤物（进伤害结算）"),
    ("element",  "元素附伤（具体元素由「附加燃烧/冰伤/雷链/中毒」布尔列决定；进伤害结算）"),
    ("survive",  "生存类（护盾/回血/减伤；不进伤害结算）"),
    ("meta",     "元规则类（球生成 / 拾取磁吸 / 纯属性 buff 等；不进伤害结算）"),
    ("debuff",   "仅施加 debuff（不直接造成伤害；不进伤害结算）"),
]


# ========== 每个 reward 的属性槽（最多 3 组 (en_key, base, per_lv)）==========
def A(name: str, base: float = 0, per_lv: float = 0) -> tuple[str, float, float]:
    return (name, base, per_lv)


PER_ID_ATTRS: dict[str, list[tuple[str, float, float]]] = {
    # ===== 基础属性 (19) =====
    "basic_warrior_soul": [A("atk_pct", 0.35, 0)],
    "basic_tri_force": [A("move_speed_pct", 0.10, 0), A("atk_speed_pct", 0.15, 0), A("max_hp_add", 1.0, 0)],
    "basic_giant_might": [A("atk_pct", 0.15, 0.15), A("max_hp_add", 1.0, 1.0), A("move_speed_pct", -0.05, -0.05), A("size_pct", 0.10, 0)],
    "basic_swift_soul": [A("atk_speed_pct", 0.15, 0.15), A("move_speed_pct", 0.10, 0.10)],
    "basic_godspeed": [A("atk_speed_pct", 0.10, 0.10), A("ki_regen_pct", 0.10, 0.10)],
    "basic_berserker": [A("atk_pct", 0.10, 0.10), A("atk_speed_pct", 0.10, 0)],
    "basic_demon_hunter": [],  # 叠层 → special_rule 处理
    "basic_four_leaf": [A("luck_pct", 0.10, 0.10)],
    "basic_ki_spring": [A("ki_regen_pct", 0.15, 0.15), A("ki_max_pct", 0.10, 0.10)],
    "basic_weak_aura": [],  # 光环 → special_rule
    "basic_luck": [A("luck_pct", 0.06, 0.06), A("dodge_pct", 0.05, 0.05)],
    "basic_wounded": [A("atk_pct", 0.15, 0.15), A("duration_sec", 5.0, 0)],
    "basic_ki_plus": [A("ki_max_pct", 0.10, 0.10)],
    "basic_move": [A("move_speed_pct", 0.10, 0.10)],
    "basic_ki_regen": [A("ki_regen_pct", 0.10, 0.10)],
    "basic_warrior_breath": [A("atk_pct", 0.10, 0.10)],
    "basic_shrink": [A("move_speed_pct", 0.10, 0), A("dodge_pct", 0.10, 0), A("size_pct", -0.30, 0)],
    "basic_boss_slayer": [],  # Boss 战满血 + 对 boss +15%/级 → special_rule
    "basic_flame_walk": [A("duration_sec", 2.0, 0), A("tick_interval_sec", 0.5, 0)],
    # ===== 生存防御 (11) =====
    "sv_holy_guard": [],  # shield 单卡 → special_rule（这里也是占位，无 attr）
    "sv_power_soul": [A("max_hp_add", 1.0, 1.0)],
    "sv_desperate_heart": [A("atk_pct", 0.10, 0.10)],
    "sv_revive": [],  # 复活单卡 → special_rule
    "sv_desperate_regen": [],  # 低血再生单卡 → special_rule
    "sv_kill_revive": [A("kill_heal_pct", 0.06, 0.06)],
    "sv_stand_guard": [A("damage_reduction_pct", 0.30, 0.05)],
    "sv_angel_shelter": [A("max_hp_add", 1.0, 1.0), A("cooldown_sec", 6.0, 0)],
    "sv_blood_power": [A("max_hp_add", 1.0, 1.0)],
    "sv_demon_recover": [A("kill_heal_pct", 0.05, 0.05)],
    "sv_life_spring": [A("max_hp_add", 0.5, 0.5), A("heal_pct", 0.30, 0)],
    # ===== 普攻子弹 (11) =====
    "bullet_storm_king": [A("bullet_count_add", 3, 0), A("atk_speed_pct", 0.15, 0)],
    "bullet_spirit_bomb": [],  # 元气弹机制 → special_rule
    "bullet_swift_shoot": [A("atk_speed_pct", 0.30, 0.30), A("atk_pct", -0.10, -0.10)],  # 攻速换攻击
    "bullet_homing": [A("atk_pct", -0.05, -0.05)],  # 追踪机制 → special_rule
    "bullet_fire_support": [],  # AOE 炸弹 → special_rule
    "bullet_split": [],  # 分裂 → special_rule
    "bullet_bounce": [],  # 弹射 → special_rule
    "bullet_mirror": [],  # 镜像 → special_rule
    "bullet_side": [],  # 斜射 → special_rule
    "bullet_count": [A("bullet_count_add", 1, 1)],
    "bullet_beam": [],  # 能量束 → special_rule
    # ===== 连击 (9) =====
    "combo_multi": [],  # 连击权重 → special_rule
    "combo_black_hole": [],  # 法术 → 看 weapon_mult/milestone 列
    "combo_fireball": [],
    "combo_water_tornado": [],
    "combo_blade_storm": [],
    "combo_charge": [],  # 蓄力 → special_rule
    "combo_thunder": [],
    "combo_shuriken": [A("bullet_count_add", 2, 2)],
    "combo_crit": [A("crit_rate", 0.10, 0.10)],
    # ===== 画线轨迹 (10) =====
    "trail_multi": [],  # 多重轨迹 → special_rule
    # 四元素轨迹：在路径作用范围内持续施加对应元素状态，无 ATK 直伤，沿用 Sheet4 base
    "trail_fire_wall": [A("duration_sec", 5.0, 1.0)],
    "trail_thunder_field": [A("duration_sec", 3.0, 1.0)],
    "trail_poison_fog": [A("duration_sec", 4.0, 1.0)],
    "trail_frost": [A("duration_sec", 3.0, 1.0)],
    "trail_slash_wave": [],  # 末端冲击半径 → special_rule
    "trail_loop_explode": [],  # 闭合爆炸 → special_rule
    "trail_pierce": [],  # 穿障碍 → special_rule
    "trail_width": [],  # 轨迹宽度 → special_rule
    "trail_dmg": [],  # 轨迹伤害 → special_rule
    # ===== 强化球 (10) =====
    "orb_tide": [],  # 球生成 → special_rule
    "orb_mark": [],  # 球印记 → special_rule
    "orb_field": [],  # 球数量 → special_rule
    "orb_magnet": [],  # 球磁吸 → special_rule
    "orb_burst": [],  # 拾取爆炸 → special_rule
    "orb_glow": [A("duration_sec", 6.0, 0)],  # 拾取增益由 special_rule 处理百分比；保留 duration
    # 四元素球：在 AOE 范围内持续施加对应元素状态，无 ATK 直伤，全部沿用 Sheet4 base
    "orb_fire": [],
    "orb_ice": [],
    "orb_poison": [],
    "orb_thunder": [],
    # ===== 环绕剑 (11) =====
    "sword_double": [],  # 剑数倍乘 → special_rule
    "sword_rage": [],  # 触发法术 → 看 proc_chance/weapon_mult
    "sword_guard": [A("sword_guard_count_add", 2, 0)],
    "sword_length": [],  # 剑长度 → special_rule
    "sword_speed": [],  # 剑转速 → special_rule
    "sword_blood": [A("sword_blood_count_add", 2, 0), A("heal_pct", 0.01, 0), A("cooldown_sec", 0.6, 0)],
    "sword_dmg": [],  # 剑伤害 → special_rule
    # 4 把元素剑：具体伤害/长度/转速/附状态详见 Sheet6 unit_stats
    "sword_flame": [A("sword_flame_count_add", 1, 1)],
    "sword_thunder": [A("sword_thunder_count_add", 1, 1)],
    "sword_poison": [A("sword_poison_count_add", 1, 1)],
    "sword_frost": [A("sword_frost_count_add", 1, 1)],
    # ===== 召唤 (10) =====
    # 7 张召唤单位卡：满级 3，每级多召 1 只；按类型各占独立 attr code
    "summon_pact": [A("summon_dmg_pct", 0.50, 0), A("summon_king_count_add", 1, 0)],  # 体型 / 攻速 → special_rule；解锁精灵王走 count_add
    "summon_rage": [A("summon_dmg_pct", 0.12, 0.12)],
    "summon_king": [A("summon_king_count_add", 1, 1)],
    "summon_god": [A("summon_god_count_add", 1, 1)],
    "summon_gorilla": [A("summon_gorilla_count_add", 1, 1), A("damage_reduction_pct", 0.30, 0)],
    "summon_dmg": [A("summon_dmg_pct", 0.10, 0.10)],
    "summon_thunder": [A("summon_thunder_count_add", 1, 1)],
    "summon_bear": [A("summon_bear_count_add", 1, 1)],
    "summon_snake": [A("summon_snake_count_add", 1, 1)],
    "summon_fire": [A("summon_fire_spirit_count_add", 1, 1)],
    # ===== 元素 (8) =====
    "elem_fire_plus": [A("elem_fire_pct", 0.30, 0.30), A("elem_proc_freq_pct", 0.15, 0.15)],
    "elem_thunder_plus": [A("elem_thunder_pct", 0.30, 0.30), A("chain_targets_bonus", 1, 1)],
    "elem_poison_plus": [A("elem_poison_pct", 0.30, 0.30), A("elem_proc_freq_pct", 0.15, 0.15)],
    "elem_ice_plus": [A("elem_ice_pct", 0.30, 0.30), A("slow_pct_bonus", 0.05, 0.05)],
    "elem_fire_bullet": [],  # proc 概率走 proc_chance 列；状态 base 走 Sheet4
    "elem_thunder_bullet": [],
    "elem_poison_bullet": [],
    "elem_ice_bullet": [],
    # ===== 主题关：恶魔（6 张，全部 max_hp_pct 惩罚）=====
    "demon_scythe":        [A("max_hp_add", -3.0, 0)],
    "demon_sulfur_laser":  [A("max_hp_add", -3.0, 0), A("cooldown_sec", 6.0, 0), A("duration_sec", 1.0, 0)],
    "demon_baby":          [A("summon_demon_baby_count_add", 1, 0), A("max_hp_add", -3.0, 0)],
    "demon_nine_lives":    [A("max_hp_add", -9.0, 0)],
    "demon_vampire":       [A("max_hp_add", -1.0, 0), A("kill_heal_pct", 0.20, 0)],
    "demon_blood_blade":   [A("max_hp_add", -2.0, 0), A("atk_speed_pct", 1.0, 0), A("atk_pct", -0.80, 0)],
    # ===== 主题关：天使（6 张，无惩罚）=====
    # sv_holy_guard 已是 [] — 仅源表 group 改 → 天使
    "angel_holy_bullet":   [],  # 全在 sr=13 special_values
    "angel_light_ward":    [A("damage_reduction_pct", 0.50, 0)],
    "angel_baby":          [A("summon_angel_baby_count_add", 1, 0)],
    "angel_fate_spear":    [A("sword_spear_count_add", 1, 0)],
    "angel_proximity_slow":[],  # 全在 sr=50 special_values
}


# ========== 4 个 applies_<elem> 布尔 ==========
# 1 = 该卡命中怪后会触发对应元素状态（按 Sheet4 base 值施加）
PER_ID_APPLIES: dict[str, dict[str, int]] = {
    # 火（燃烧）
    "basic_flame_walk":   {"fire": 1},
    "trail_fire_wall":    {"fire": 1},
    "combo_fireball":     {"fire": 1},
    "orb_fire":           {"fire": 1},
    "sword_flame":        {"fire": 1},
    "summon_fire":        {"fire": 1},
    "elem_fire_bullet":   {"fire": 1},
    # 冰（冰伤 + 减速）
    "trail_frost":        {"ice": 1},
    "combo_water_tornado":{"ice": 1},
    "orb_ice":            {"ice": 1},
    "sword_frost":        {"ice": 1},
    "summon_bear":        {"ice": 1},
    "elem_ice_bullet":    {"ice": 1},
    # 雷（雷链 / 麻痹）
    "trail_thunder_field":{"thunder": 1},
    "combo_thunder":      {"thunder": 1},
    "orb_thunder":        {"thunder": 1},
    "sword_thunder":      {"thunder": 1},
    "summon_thunder":     {"thunder": 1},
    "elem_thunder_bullet":{"thunder": 1},
    # 毒（中毒）
    "trail_poison_fog":   {"poison": 1},
    "combo_blade_storm":  {"poison": 1},
    "orb_poison":         {"poison": 1},
    "sword_poison":       {"poison": 1},
    "summon_snake":       {"poison": 1},
    "elem_poison_bullet": {"poison": 1},
    # ===== 主题关：恶魔 / 天使 =====
    "demon_sulfur_laser": {"fire": 1},
    "demon_baby":         {"fire": 1},
    "angel_holy_bullet":  {"thunder": 1},
    "angel_baby":         {"thunder": 1},
}


# ========== 每个 reward 的固定列覆盖 ==========
PER_ID_META: dict[str, dict] = {
    "basic_berserker": {"trigger_value": 0.50},
    "basic_wounded": {"trigger_value": 5.0},
    "sv_desperate_heart": {"trigger_value": 0.50},
    "sv_desperate_regen": {"trigger_value": 0.30},
    "sv_stand_guard": {"trigger_value": 1.5},
    "sv_kill_revive": {"proc_chance": 0.20},
    "sv_demon_recover": {"proc_chance": 0.15},
    "combo_black_hole": {"weapon_mult": 2.0, "trigger_value_per_lv": -1},
    "combo_fireball": {"weapon_mult": 2.5, "trigger_value_per_lv": -1},
    "combo_water_tornado": {"weapon_mult": 2.2, "trigger_value_per_lv": -1},
    "combo_blade_storm": {"weapon_mult": 2.0},
    "combo_thunder": {"weapon_mult": 3.0, "trigger_value_per_lv": -1, "trigger_value": 10},
    "combo_shuriken": {"weapon_mult": 0.6},
    "trail_slash_wave": {"weapon_mult": 2.5},
    "trail_loop_explode": {"weapon_mult": 3.0},
    "orb_burst": {"weapon_mult": 1.5},
    "sword_rage": {"proc_chance": 0.15},  # 触发法术倍率详见 Sheet6 unit_stats
    # 4 张元素子弹卡的子弹附伤是必带效果（不是概率），proc_chance 不再写；详见 CLAUDE.md 三、
    # 7 张召唤单位卡：满级 3（源表是 1，这里覆盖），每级多召 1 只
    # 召唤的 ATK 倍率 / 攻速 / 元素详见 Sheet6 unit_stats
    "summon_king": {"max_level": 3},
    "summon_god": {"max_level": 3},
    "summon_gorilla": {"max_level": 3},
    "summon_thunder": {"max_level": 3},
    "summon_bear": {"max_level": 3},
    "summon_snake": {"max_level": 3},
    "summon_fire": {"max_level": 3},
    # ===== 主题关 =====
    # max_level 已在源表填 1（主题关只刷 1 张），此处仅覆盖额外字段
    "demon_vampire":       {"proc_chance": 0.05},
    "angel_holy_bullet":   {"proc_chance": 0.10, "weapon_mult": 2.0},
    "angel_fate_spear":    {"weapon_mult": 1.5},
}


# ========== 策划手编的 desc 覆盖（以 rewards_v6_compact_new.xlsx 为准）==========
# 源表 ys构思_v6.xlsx 里 desc 含「45% 概率」「雷链 ×3」等过时文案，必须覆盖回策划版
# 详见 CLAUDE.md 四、
PER_ID_DESC_OVERRIDE: dict[str, str] = {
    # bullet_swift_shoot：v7 把"子弹伤害 -10%"改成"攻击 -10%"（更通用，可走属性槽）
    "bullet_swift_shoot":   "攻速 +30%/级，攻击 -10%/级",
    # combo_multi：v7 改语义——不再是"连击数计入伤害的倍率"，而是单次斩击产生的连击数翻倍
    "combo_multi":          "每次斩击产生的连击数 ×2",
    # 「画线末释放」类奖励：仅当本次画线把气力条耗尽时触发（避免短画线反复释放）
    "combo_shuriken":       "气力耗尽时，向斩击末端方向 spawn +2 枚手里剑/级 0.6×ATK",
    "trail_slash_wave":     "气力耗尽时，画线末端范围冲击 2.5×ATK，推开半径 200px (+0.3/级)",
    "trail_loop_explode":   "气力耗尽且画线轨迹首次闭合时，闭合区间内释放爆炸 3.0×ATK (+0.3/级)",
    # 7 张召唤单位卡：全部远程、跟随玩家
    "summon_king":          "召唤精灵王 远程aoe攻击",
    "summon_god":           "召唤天神  远程单体攻击",
    "summon_gorilla":       "召唤大猩猩 远程攻击 每10s向攻击敌人位置扔出香蕉 造成嘲讽效果 持续3s",
    "summon_thunder":       "落雷召唤 每3s对场上随机敌人造成aoe雷伤",
    "summon_bear":          "召唤北极熊跟随玩家 远程单体攻击 冰伤",
    "summon_snake":         "召唤毒蛇跟随玩家 远程单体攻击 毒伤",
    "summon_fire":          "召唤火焰精灵跟随玩家 远程单体攻击 火伤",
    # 4 张元素子弹卡：必带效果，不是概率
    "elem_fire_bullet":     "子弹附火 普攻触发燃烧效果",
    "elem_thunder_bullet":  "子弹附雷 普攻触发雷链效果",
    "elem_poison_bullet":   "子弹附毒 普攻触发中毒效果",
    "elem_ice_bullet":      "子弹附冰 普攻触发冰伤 + 减速效果",
    # ===== 主题关：圣盾（sv_holy_guard 由 神圣守护 → 圣盾，移到天使组）=====
    "sv_holy_guard":        "每关开始获得 1 层圣盾，抵挡 1 次伤害（含致死）",
    # ===== 主题关：恶魔（带惩罚文案）=====
    "demon_scythe":         "气力耗尽时，画线末端释放无限射程贯通镰刀，4×ATK 伤害（最大生命 -3）",
    "demon_sulfur_laser":   "每 6 秒朝最近敌人射出 1 条暗红激光，持续 1 秒，附加燃烧（最大生命 -3）",
    "demon_baby":           "召唤恶魔宝宝跟随玩家 远程激光穿透攻击 火伤（最大生命 -3）",
    "demon_nine_lives":     "九命：初始 1 命 + 8 次复活，复活后 HP=1（最大生命 -9）",
    "demon_vampire":        "击杀时 5% 概率恢复 20% 最大生命（最大生命 -1）",
    "demon_blood_blade":    "普攻改为血飞刀：穿透 + 射程 ×2 + 攻速 +100%，攻击 -80%（最大生命 -2）",
    # ===== 主题关：天使（无惩罚）=====
    "angel_holy_bullet":    "普攻 10% 概率召唤光柱 AOE 雷伤",
    "angel_light_ward":     "受到伤害 -50%",
    "angel_baby":           "召唤天使宝宝跟随玩家 远程单体攻击 雷伤",
    "angel_fate_spear":     "环绕命运之矛 ×1",
    "angel_proximity_slow": "玩家周围 300px 内怪物按距离线性减速，最高 50%",
}


# ========== 强制不入常规升级池（pool_weight 覆写为 0）==========
# 详见 CLAUDE.md 十一、单一开关约定。
# 注意：这里只放"工具级硬规则" — 整组永远不入常规池的卡。
# 个别 basic 卡（神速 / 四叶草 / 运气 / 负伤战士 / 移动加速 / 战士之息）的
# pool_weight=0 由 compact.xlsx 自己控制，不要在这里硬编码 — 一旦 build_rewards 重跑
# 会覆盖 compact 的策划手编值。
FORCE_NOT_IN_POOL_GROUP_CODES: set[int] = {6, 10, 11}  # 6=强化球, 10=恶魔, 11=天使


# ========== Sheet1 schema ==========

SHEET1_HEADERS: list[tuple[str, str]] = [
    # 元信息 (1-8)
    ("ID", "id"),
    ("名称", "name_cn"),
    ("分组", "group"),
    ("品质", "rarity"),
    ("图标", "icon"),
    ("描述", "desc_cn"),
    ("最大等级", "max_level"),
    ("池权重", "pool_weight"),
    # 专属规则 + 数组 (9-11)
    ("专属规则", "special_rule"),
    ("专属数值", "special_values"),
    ("专属数值每级", "special_values_per_lv"),
    # 标签 (12)
    ("卡牌路径", "card_path"),
    # 触发器 (14-17)
    ("触发条件", "trigger_type"),
    ("条件数值", "trigger_value"),
    ("条件数值每级", "trigger_value_per_lv"),
    ("触发概率", "proc_chance"),
    # 法术机制 (18)
    ("基础伤害ATK倍率", "weapon_mult"),
    # 属性槽 1 (19-21)
    ("属性1", "attr_id_1"),
    ("属性数值1", "attr_value_1"),
    ("属性数值1每级", "attr_value_per_lv_1"),
    # 属性槽 2 (22-24)
    ("属性2", "attr_id_2"),
    ("属性数值2", "attr_value_2"),
    ("属性数值2每级", "attr_value_per_lv_2"),
    # 属性槽 3 (25-27)
    ("属性3", "attr_id_3"),
    ("属性数值3", "attr_value_3"),
    ("属性数值3每级", "attr_value_per_lv_3"),
    # 属性槽 4 (28-30)
    ("属性4", "attr_id_4"),
    ("属性数值4", "attr_value_4"),
    ("属性数值4每级", "attr_value_per_lv_4"),
    # 元素状态布尔 (31-34)
    ("附加燃烧", "applies_fire"),
    ("附加冰伤", "applies_ice"),
    ("附加雷链", "applies_thunder"),
    ("附加中毒", "applies_poison"),
    # 备注 (35)
    ("备注", "notes"),
    # 游戏内简化展示文案 (36, 玩家面向；策划手编，generator 留空)
    ("游戏内展示用描述", "desc_cn_game"),
]


# ========== Sheet4 element_effects ==========

ELEMENT_EFFECTS: list[tuple[str, str, str, str, float, str]] = [
    # (元素, 状态, 字段中文, 字段 key, 基础值, 说明)
    ("火", "燃烧 DoT", "燃烧倍率/秒", "burn_atk_per_sec_base", 0.30, "受火伤+ 增伤"),
    ("火", "燃烧 DoT", "燃烧持续秒", "burn_duration_sec_base", 2.0, ""),
    ("火", "燃烧 DoT", "tick 间隔秒", "burn_tick_interval", 0.5, "火伤+ 提高频率"),
    ("冰", "命中冰伤", "冰伤 ATK 倍率", "hit_atk_mult_base", 0.30, "命中即额外 0.30×ATK 一次性伤害；受冰伤+ 增伤"),
    ("冰", "减速", "减速%", "slow_pct_base", 0.30, "冰伤+ 额外叠加"),
    ("冰", "减速", "减速秒", "slow_duration_sec_base", 1.5, ""),
    ("雷", "雷链", "雷链目标", "chain_targets_base", 3, "雷伤+ 每级 +1 目标"),
    ("雷", "雷链", "雷链 ATK 倍率", "chain_atk_mult_base", 0.60, "受雷伤+ 增伤"),
    ("雷", "麻痹（附加）", "麻痹秒", "paralyze_duration_sec_base", 0.5, ""),
    ("毒", "中毒 DoT", "中毒倍率/秒", "poison_atk_per_sec_base", 0.30, "受毒伤+ 增伤"),
    ("毒", "中毒 DoT", "中毒持续秒", "poison_duration_sec_base", 3.0, ""),
    ("毒", "中毒 DoT", "tick 间隔秒", "poison_tick_interval", 1.0, "毒伤+ 提高频率"),
]

ELEMENT_RULES = [
    "1. 卡牌的「附加燃烧/冰伤/雷链/中毒」列 = 1 时，命中怪即按本表基础值施加该元素状态",
    "2. 同元素的「伤害+」卡按层级加成 ELEM 层（影响该元素的所有伤害，含 DoT）",
    "3. 单卡如需偏离本表 base 数值（如 orb_fire 把燃烧倍率拉到 1.0×ATK），走对应元素的「附伤倍率」属性槽",
]


# ========== 读源表 ==========

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
    raw_dmg_layer = str(raw["dmg_layer"]).strip()

    # 拆 (dmg_source, build_tag) 两轴
    if raw_dmg_layer in DMG_LAYER_SPLIT:
        dmg_source, build_tag = DMG_LAYER_SPLIT[raw_dmg_layer]
    else:
        print(f"  WARNING: id={rid} 未识别 dmg_layer={raw_dmg_layer!r}，降级为 dmg_source=该值小写")
        dmg_source, build_tag = raw_dmg_layer.lower(), ""

    # H1-H4/META 默认 physical/meta；按 group 微调到实际来源
    if build_tag and dmg_source in ("physical", "meta"):
        group_code = GROUP_NAME_TO_CODE.get(group, 0)
        override = GROUP_CODE_TO_DMG_SOURCE.get(group_code)
        if override:
            dmg_source = override

    trigger_raw = str(raw.get("trigger", "passive"))
    trigger_type = TRIGGER_NORMALIZE.get(trigger_raw, trigger_raw)

    row: dict = {en: "" for _, en in SHEET1_HEADERS}
    row["id"] = rid
    row["name_cn"] = str(raw["name_cn"])
    row["group"] = GROUP_NAME_TO_CODE.get(group, 0)
    row["rarity"] = COLOUR_TO_RARITY_CODE.get(colour, 0)
    row["icon"] = GROUP_DEFAULT_ICON.get(group, "")
    # 策划手编版优先（CLAUDE.md 四、），再统一去掉 `（最 +X%）` / `（max N）` 这类
    # 等于 per_lv × max_level 的冗余尾巴（CLAUDE.md 八、）
    final_desc = PER_ID_DESC_OVERRIDE.get(rid, desc)
    final_desc = re.sub(r"[（(]\s*(?:最\s*[+\-]?[\d.]+%?|max\s+\d+)\s*[）)]", "", final_desc)
    # 收尾标点：去掉因切除产生的多余前置标点
    final_desc = re.sub(r"[，,]\s*([。.!?！？]|$)", r"\1", final_desc).strip().rstrip(",，")
    row["desc_cn"] = final_desc
    row["max_level"] = int(raw.get("max_level", 1))
    raw_weight = int(raw.get("pool_weight", 100))
    if row["group"] in FORCE_NOT_IN_POOL_GROUP_CODES:
        raw_weight = 0
    row["pool_weight"] = raw_weight
    # 专属规则 type_id（0 = 无）+ 数组 JSON 字符串
    sr_type, sr_arr = SPECIAL_RULES.get(rid, (0, []))
    row["special_rule"] = sr_type
    row["special_values"] = json.dumps(sr_arr, ensure_ascii=False, separators=(",", ":")) if sr_arr else ""
    sr_per_lv = SPECIAL_RULES_PER_LV.get(rid, [])
    row["special_values_per_lv"] = json.dumps(sr_per_lv, ensure_ascii=False, separators=(",", ":")) if sr_per_lv else ""
    row["card_path"] = dmg_source
    row["trigger_type"] = TRIGGER_KEY_TO_CODE.get(trigger_type, 0)
    row["notes"] = str(raw.get("notes", ""))

    if trigger_type == "combo_milestone":
        for n in (5, 6, 8, 10, 12, 14):
            if str(n) in trigger_raw:
                row["trigger_value"] = n
                break

    # PER_ID_META 覆盖（trigger_value / proc_chance / weapon_mult / milestone）
    for k, v in PER_ID_META.get(rid, {}).items():
        row[k] = v

    # 4 个属性槽
    attrs = PER_ID_ATTRS.get(rid, [])
    for i, (en_key, base, per_lv) in enumerate(attrs[:4]):
        code = EN_KEY_TO_CODE.get(en_key)
        if code is None:
            print(f"  WARNING: id={rid} 属性 {en_key} 不在 ATTR_CODES（v4 已砍）")
            continue
        row[f"attr_id_{i+1}"] = code
        # base / per_lv 为 0 时显示空白（v4.5 统一）
        row[f"attr_value_{i+1}"] = "" if base == 0 else base
        row[f"attr_value_per_lv_{i+1}"] = "" if per_lv == 0 else per_lv
    if len(attrs) > 4:
        print(f"  NOTE: id={rid} 有 {len(attrs)} 个属性，仅前 4 个入表")

    # 4 元素状态布尔
    applies = PER_ID_APPLIES.get(rid, {})
    row["applies_fire"] = applies.get("fire", 0)
    row["applies_ice"] = applies.get("ice", 0)
    row["applies_thunder"] = applies.get("thunder", 0)
    row["applies_poison"] = applies.get("poison", 0)
    return row


# ========== 写 4 个 sheet ==========

def write_xlsx(rows: list[dict]) -> None:
    OUT_XLSX.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    fill_cn = PatternFill("solid", fgColor="4472C4")
    fill_en = PatternFill("solid", fgColor="A5C4F2")
    font_cn = Font(color="FFFFFF", bold=True)
    font_en = Font(color="1F3864", italic=True)
    center = Alignment(horizontal="center", vertical="center", wrap_text=True)

    # ----- Sheet1: rewards -----
    ws1 = wb.active
    ws1.title = "rewards"
    cn = [c for c, _ in SHEET1_HEADERS]
    en = [e for _, e in SHEET1_HEADERS]
    ws1.append(cn)
    for c in ws1[1]:
        c.fill = fill_cn
        c.font = font_cn
        c.alignment = center
    ws1.append(en)
    for c in ws1[2]:
        c.fill = fill_en
        c.font = font_en
        c.alignment = center
    for r in rows:
        ws1.append([r.get(k, "") for k in en])
    ws1.freeze_panes = "C3"
    for col_idx, name in enumerate(cn, start=1):
        ws1.column_dimensions[get_column_letter(col_idx)].width = max(8, min(len(name) * 2 + 2, 26))
    ws1.row_dimensions[1].height = 28
    ws1.row_dimensions[2].height = 18

    # 高亮属性槽 12 列 (黄)
    attr_fill = PatternFill("solid", fgColor="FFF2CC")
    attr_cols = [en.index(k) + 1 for k in (
        "attr_id_1", "attr_value_1", "attr_value_per_lv_1",
        "attr_id_2", "attr_value_2", "attr_value_per_lv_2",
        "attr_id_3", "attr_value_3", "attr_value_per_lv_3",
        "attr_id_4", "attr_value_4", "attr_value_per_lv_4",
    )]
    for col_idx in attr_cols:
        for row_idx in range(3, ws1.max_row + 1):
            ws1.cell(row=row_idx, column=col_idx).fill = attr_fill

    # 高亮 4 元素状态布尔列 (浅红)
    elem_fill = PatternFill("solid", fgColor="FCE4D6")
    elem_cols = [en.index(k) + 1 for k in (
        "applies_fire", "applies_ice", "applies_thunder", "applies_poison"
    )]
    for col_idx in elem_cols:
        for row_idx in range(3, ws1.max_row + 1):
            ws1.cell(row=row_idx, column=col_idx).fill = elem_fill

    # ----- Sheet2: attr_codes -----
    ws2 = wb.create_sheet("attr_codes")
    headers2 = ["编码", "类别", "中文名", "英文 key", "说明"]
    ws2.append(headers2)
    for c in ws2[1]:
        c.fill = fill_cn
        c.font = font_cn
        c.alignment = center
    for code, cat, cn_name, en_key, desc in ATTR_CODES:
        ws2.append([code, cat, cn_name, en_key, desc])
    ws2.freeze_panes = "A2"
    for i, w in enumerate([8, 10, 22, 36, 60], start=1):
        ws2.column_dimensions[get_column_letter(i)].width = w
    ws2.row_dimensions[1].height = 24
    # 说明区
    ws2.append([])
    ws2.append(["说明"])
    ws2.cell(row=ws2.max_row, column=1).font = Font(bold=True, color="C00000")
    notes = [
        "1. 每个属性 base（一次性）+ per_lv（每级递增）共用同一 attr_id，分别写在「属性数值」「属性数值每级」列",
        "2. 自然上限 = base + per_lv × (max_level - 1)，无需在编码表 / Sheet1 单独表达",
        "3. 单卡专属机制（穿障碍 / 弹射 / 分裂 / 镜像 / 复活 / Boss 满血 / 嘲讽 / 黑洞 等）不在本表，由 special_rule=1 + GDScript hand-code",
        "4. 元素状态（燃烧 / 减速 / 雷链 / 麻痹 / 中毒）的基础数值在 Sheet4 element_effects；单卡仅用 applies_<elem> 布尔标记是否触发",
        "5. 元素覆盖 elem_<type>_attach_atk_mult（4 个，按元素选）仅当单卡需要偏离 Sheet4 base 时使用（如 orb_fire 想 burn 1.0×ATK）",
    ]
    for n in notes:
        ws2.append([n])

    # ----- Sheet3: damage_formula -----
    ws3 = wb.create_sheet("damage_formula")
    write_damage_formula(ws3, fill_cn, font_cn, center)

    # ----- Sheet4: element_effects -----
    ws4 = wb.create_sheet("element_effects")
    write_element_effects(ws4, fill_cn, font_cn, center)

    # ----- Sheet5: lookups（5 子表 — group/rarity/category/trigger_type/special_rule）-----
    ws5 = wb.create_sheet("lookups")
    write_lookups(ws5, fill_cn, font_cn, center)

    wb.save(OUT_XLSX)
    print(f"Wrote {OUT_XLSX}")


def write_lookups(ws, fill_cn: PatternFill, font_cn: Font, center: Alignment) -> None:
    title_font = Font(bold=True, size=14, color="1F3864")
    subtitle_font = Font(bold=True, size=11, color="C00000")

    ws.append(["元数据编码对照表（主表的 分组 / 品质 / 触发条件 / 卡牌路径 / 专属规则 列对照本表取值）"])
    ws.cell(row=ws.max_row, column=1).font = title_font
    ws.row_dimensions[ws.max_row].height = 26
    ws.append([])

    def write_subtable(title: str, headers: list[str], rows: list[list]) -> None:
        ws.append([title])
        ws.cell(row=ws.max_row, column=1).font = subtitle_font
        ws.append(headers)
        for c in ws[ws.max_row]:
            c.fill = fill_cn
            c.font = font_cn
            c.alignment = center
        for r in rows:
            ws.append(r)
        ws.append([])

    # 1. group
    write_subtable(
        "1. group（分组编码 — 主表「分组」列）",
        ["编码", "中文名"],
        [[c, n] for c, n in GROUP_CODES],
    )
    # 2. rarity
    write_subtable(
        "2. rarity（品质编码 — 主表「品质」列）",
        ["编码", "英文 key", "中文"],
        [[c, k, n] for c, k, n in RARITY_CODES],
    )
    # 3. trigger_type
    write_subtable(
        "3. trigger_type（触发条件编码 — 主表「触发条件」列；条件数值/每级走「条件数值」/「条件数值每级」列）",
        ["编码", "英文 key", "说明"],
        [[c, k, d] for c, k, d in TRIGGER_CODES],
    )
    # 4. card_path（卡牌路径取值）
    write_subtable(
        "4. card_path（卡牌路径 — 主表「卡牌路径」列；前 7 个进伤害结算的「增伤层」按路径独立加和 dmg_<path>_pct，后 3 个不进结算）",
        ["英文 key", "说明"],
        [[k, d] for k, d in CARD_PATH_CODES],
    )
    # 5. special_rule（专属规则编码 + special_values 数组 schema）
    write_subtable(
        "5. special_rule（专属规则编码 — 主表「专属规则」列；专属数值按本表 schema 顺序填，每级增量填「专属数值每级」列）",
        ["编码", "英文 key", "中文名", "数组字段顺序", "数组字段含义"],
        [[c, k, n, s, scn] for c, k, n, s, scn in SPECIAL_RULE_CODES],
    )

    widths = [8, 22, 22, 70, 70]
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.row_dimensions[1].height = 26


def write_element_effects(ws, fill_cn: PatternFill, font_cn: Font, center: Alignment) -> None:
    title_font = Font(bold=True, size=14, color="1F3864")
    rules_font = Font(bold=True, color="C00000")

    ws.append(["四大元素状态效果统一基础值"])
    ws.cell(row=ws.max_row, column=1).font = title_font
    ws.row_dimensions[ws.max_row].height = 26
    ws.append([])

    headers = ["元素", "状态", "基础值", "说明"]
    ws.append(headers)
    for c in ws[ws.max_row]:
        c.fill = fill_cn
        c.font = font_cn
        c.alignment = center

    # 4 元素分组上色
    elem_fills = {
        "火": PatternFill("solid", fgColor="FCE4D6"),
        "冰": PatternFill("solid", fgColor="DDEBF7"),
        "雷": PatternFill("solid", fgColor="FFF2CC"),
        "毒": PatternFill("solid", fgColor="E2EFDA"),
    }
    for elem, state, _cn_name, _en_key, base_val, note in ELEMENT_EFFECTS:
        ws.append([elem, state, base_val, note])
        fill = elem_fills.get(elem)
        if fill:
            for c in ws[ws.max_row]:
                c.fill = fill

    # 规则区
    ws.append([])
    ws.append(["修正规则"])
    ws.cell(row=ws.max_row, column=1).font = rules_font
    for rule in ELEMENT_RULES:
        ws.append([rule])

    widths = [6, 18, 10, 60]
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.row_dimensions[1].height = 26


def write_damage_formula(ws, fill_cn: PatternFill, font_cn: Font, center: Alignment) -> None:
    title_font = Font(bold=True, size=14, color="1F3864")
    section_fill = PatternFill("solid", fgColor="D9E1F2")
    section_font = Font(bold=True, size=11)
    formula_font = Font(name="Consolas", size=11, color="000000")
    en_font = Font(name="Consolas", size=10, color="595959", italic=True)

    def add_title(text: str) -> None:
        ws.append([text])
        ws.cell(row=ws.max_row, column=1).font = title_font
        ws.row_dimensions[ws.max_row].height = 26

    def add_section(text: str) -> None:
        ws.append([text])
        c = ws.cell(row=ws.max_row, column=1)
        c.fill = section_fill
        c.font = section_font
        ws.row_dimensions[ws.max_row].height = 22

    def add_text(text: str) -> None:
        ws.append([text])

    def add_formula(text: str) -> None:
        ws.append([text])
        ws.cell(row=ws.max_row, column=1).font = formula_font

    def add_en_note(text: str) -> None:
        ws.append([text])
        ws.cell(row=ws.max_row, column=1).font = en_font

    def add_table(headers: list[str], rows: list[list]) -> None:
        ws.append(headers)
        for c in ws[ws.max_row]:
            c.fill = fill_cn
            c.font = font_cn
            c.alignment = center
        for r in rows:
            ws.append(r)

    add_title("战斗伤害公式（一页看懂）")
    add_text("")

    # ===== 1. 数学骨架 =====
    add_section("【1】数学骨架 — 一句话")
    add_formula("最终伤害 = 取整( 攻击端 5 层连乘 × 防御端 3 层连乘 )，永远至少 1。")
    add_text("")

    # ===== 2. 总图：同层加 / 跨层乘 =====
    add_section("【2】总图 — 同层内加法、不同层之间乘法")
    add_text("")
    add_formula("攻击端 5 层")
    add_formula("  [1] 攻击层      你的基础攻击 × 攻击%加和")
    add_formula("  [2] 基础伤害层  这一招本身的 ATK 倍率")
    add_formula("  [3] 增伤层      1 + 通用增伤% + 来源增伤%")
    add_formula("  [4] 连击层      1 + 每点连击加成 × 连击数")
    add_formula("  [5] 暴击层      暴击则 ×(1+暴伤%)")
    add_formula("                ↓ 连乘")
    add_formula("防御端 3 层")
    add_formula("  [6] 防御层      怪 def 越高，伤害越低（高关自动软化）")
    add_formula("  [7] 易伤层      1 + 怪的易伤% + 印记")
    add_formula("  [8] 元素层      1 + (玩家元素% - 怪元素抗)")
    add_formula("                ↓ 连乘 + 取整 + 钉底 1")
    add_formula("最终伤害 = max(1, 取整( 攻击端 × 防御端 ))")
    add_text("")
    add_text("关键规则：")
    add_text("  · 同层内多张卡的数值「相加」（10 张攻击%卡加和为一个数）")
    add_text("  · 不同层之间「相乘」")
    add_text("  · 一张神卡刷不到天，但多层叠加也不会被防御吃光")
    add_text("")

    # ===== 3. 8 层各管什么 =====
    add_section("【3】8 个层各管什么 — 一句话一层")
    add_text("")
    add_formula("[1] 攻击层      = 你的基础攻击 × (1 + 攻击%加和)")
    add_text("                 攻击%来源：力量之魂、战士之息、攻击% 等卡；以及临时 buff（如低血狂热）")
    add_text("")
    add_formula("[2] 基础伤害层  = 这一招本身的 ATK 倍率")
    add_text("                 主表「基础伤害ATK倍率」列：普攻 1.0、火球 2.5、雷链 0.6、剑气 2.5、划线斩 1.0")
    add_text("")
    add_formula("[3] 增伤层      = 1 + 通用增伤% + 路径增伤%")
    add_text("                 路径 = 主表「卡牌路径」列；进结算的 7 个：")
    add_text("                   physical / bullet / combo / trail / sword / summon / element")
    add_text("                 每个路径独立加和（子弹增伤+ 不影响剑伤）")
    add_text("                 不进结算的 3 个（survive / meta / debuff）不算伤害卡，不参与本层")
    add_text("")
    add_formula("[4] 连击层      = 1 + 每点连击加成 × 当前连击数")
    add_text("                 只有划线斩吃，子弹/法术不吃；默认每点 +1%，20 连击 = 1.20×")
    add_text("")
    add_formula("[5] 暴击层      = 暴击命中 ? (1 + 暴伤%) : 1.0")
    add_text("                 暴击率 = 角色基础 + 卡牌；默认暴伤 +60%")
    add_text("")
    add_formula("[6] 防御层      = 1 - def / (def + K)，K 随关卡递增")
    add_text("                 高 def 不会让伤害归零；高关卡 K 自动增长保持手感")
    add_text("")
    add_formula("[7] 易伤层      = 1 + 怪的元素易伤% (+ 印记 1.0 命中后消耗)")
    add_text("                 怪物数据 vuln_<元素>；印记 = 易伤 +100%，命中即消耗")
    add_text("")
    add_formula("[8] 元素层      = 1 + (玩家元素%加成 - 怪元素抗性)")
    add_text("                 元素%加成在发射时快照，DoT/燃烧/中毒 tick 用快照值，不读实时")
    add_text("")

    # ===== 4. 玩家受击 =====
    add_section("【4】玩家受击（敌人 → 玩家）")
    add_formula("玩家受伤 = max( 1, 取整( raw × max(0.2, 1 - 总减伤%) ) )")
    add_text("减伤%来源：圣盾 / 不动如山 / 嘲讽召唤兽 / 减伤% 属性 等")
    add_text("下限 0.2 = 最多减 80%，永远至少吃 20% 伤害")

    # 列宽
    ws.column_dimensions["A"].width = 110


def main() -> None:
    raw = read_v6_raw()
    print(f"Loaded {len(raw)} entries from {SRC_XLSX.name}")
    rows = [build_row(r) for r in raw]
    write_xlsx(rows)
    print(f"Sheet1 columns: {len(SHEET1_HEADERS)}")
    print(f"Sheet1 rows: {len(rows)}")
    print(f"Sheet2 attr codes: {len(ATTR_CODES)}")
    print(f"Sheet4 element effects: {len(ELEMENT_EFFECTS)}")
    # 统计 4 元素布尔列分布
    fire = sum(1 for r in rows if r.get("applies_fire") == 1)
    ice = sum(1 for r in rows if r.get("applies_ice") == 1)
    thunder = sum(1 for r in rows if r.get("applies_thunder") == 1)
    poison = sum(1 for r in rows if r.get("applies_poison") == 1)
    print(f"applies_fire={fire} / applies_ice={ice} / applies_thunder={thunder} / applies_poison={poison}")
    print("Done.")


if __name__ == "__main__":
    main()
