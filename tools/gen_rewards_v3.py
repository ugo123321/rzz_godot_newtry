# -*- coding: utf-8 -*-
"""
Generate D:/workspace/godot1/rzz_godot/奖励设计_v3.xlsx

v3.1 设计向修订（不考虑落地）：
  - 卡池：白 18% / 蓝 35% / 紫 32% / 橙 15%，新增 GachaRules、GlobalCaps 表
  - Upgrades 增列：pool_weight、excl_group、design_role
  - 本作主轴：连击画线 + 画线轨迹权重上调；弹幕/宠物流橙装互斥组
  - 数值：H2 多弹衰减公式入表；暴击/暴伤软上限；削弱爆表组合（深渊爆炸、水龙卷拆层等）
  - 触发语义：神圣守护=每关开始；不动如山=划线前静止（非跑图站桩）
  - 元素流补专属橙「元素融贯」；移除「反弹射」、新增「连击锐眼」

v3.2：
  - 分组「召唤激光」→「召唤」；条目去掉激光/光束用语
  - desc_cn 删除（2→2.3 次/秒）类前后对比描述

v3.3：
  - 删圣盾/闭合追加/深渊爆炸；补战地复苏、精灵盟约、斩击余波
  - 黑洞改 combo_milestone_8；召唤橙拆天雷/精灵；精灵 desc 四段模板
"""
import re
import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from collections import Counter

OUT = r"D:\workspace\godot1\rzz_godot\奖励设计_v3.xlsx"
OUT_FALLBACK = r"D:\workspace\godot1\rzz_godot\奖励设计_v3_1.xlsx"

RARITY_FILL = {"white": "EAEAEA", "blue": "CFE4FF", "purple": "E4D2FF", "orange": "FFE0B0"}

# 基础 15 列 + 设计 3 列
# id, name_cn, rarity, group, dmg_layer, value_type, apply_value,
# apply_type, trigger, max_level, once_per_run, once_per_chapter,
# desc_cn, build_tag, notes, pool_weight, excl_group, design_role


def clean_desc_cn(text: str) -> str:
    """去掉 desc 里「前后数值对比」类写法，保留效果本身。"""
    if not text:
        return text
    text = re.sub(r"（[^）]*→[^）]*）", "", text)
    text = re.sub(r"×[\d.]+→×([\d.]+)", r"×\1", text)
    text = re.sub(r"\+[\d.]+%→\+([\d.]+)%", r"+\1%", text)
    text = re.sub(r"\+[\d.]+%→\+([\d.]+)", r"+\1", text)
    text = re.sub(r"([\d.]+)%→([\d.]+)%", r"\2%", text)
    text = re.sub(r"([\d.]+)\s*次/秒\s*→\s*([\d.]+)\s*次/秒", r"\2次/秒", text)
    text = re.sub(r"([\d.]+)s→([\d.]+)s", r"\2s", text)
    text = re.sub(r"([\d.]+)→([\d.]+)(?=[次\s%/秒])", r"\2", text)
    text = re.sub(r"([\d.]+)→([\d.]+)", r"\2", text)
    text = re.sub(r"，{2,}", "，", text)
    text = re.sub(r"，\s*$", "", text)
    text = re.sub(r"^\s*，", "", text)
    return text.strip()


def U(row, pool_weight=100, excl_group="", design_role=""):
    row = list(row)
    row[12] = clean_desc_cn(str(row[12]))
    return tuple(row) + (pool_weight, excl_group, design_role)


# ===================== 基础属性 (10) =====================
basics = [
    U(["warrior_soul", "战士之魂", "orange", "基础属性", "H1", "mult", 1.25, "atk_mult", "passive", 1, 1, 0,
       "攻击 ×1.25（本局一次）", "generic", "v3.1: 1.30→1.25 避免与其它橙 H1 叠爆"], 75, "", "core"),
    U(["power_trio", "力量三重奏", "orange", "基础属性", "H1", "add_pct", 0.12, "power_trio", "passive", 1, 1, 0,
       "攻击 +12%、攻速 +15%、最大生命 +15%", "generic", "v3.1 三合一略削"], 75, "", "core"),

    U(["atk_boost", "攻击力提升", "purple", "基础属性", "H1", "add_pct", 0.12, "atk_mult", "passive", 5, 0, 0,
       "攻击 +12%/级，max 5（最多 +60%，H1 加法后乘）", "generic", "v3.1: 15%→12%"], 100, "", "support"),
    U(["giant_force", "巨人之力", "purple", "基础属性", "H1", "mult", 1.15, "giant_force", "passive", 1, 1, 0,
       "攻击 ×1.15、最大生命 +25%、体型 ×1.35、移速 -15%", "generic", "v3.1 体型/移速惩罚略减"], 95, "", "support"),
    U(["swift_soul", "迅捷之魂", "purple", "基础属性", "H1", "add_pct", 0.20, "atk_speed_mult", "passive", 1, 1, 0,
       "攻速 +20%、移速 +25%", "combo_build", "偏划线节奏；标签改 combo"], 95, "", "support"),

    U(["godspeed", "神速", "blue", "基础属性", "H1", "mult", 1.12, "godspeed", "passive", 4, 0, 0,
       "攻速 ×1.12/级，max 4（叠至 ×1.57）；气力回复 ×0.94/级", "bullet_build", "v3.1: max5→4，减轻气力惩罚"], 100, "", "support"),
    U(["desperate_rage", "绝境狂热", "blue", "基础属性", "H3", "add_pct", 0.25, "desperate_rage", "hp_below_50", 1, 0, 0,
       "HP<50% 时攻击 +25%（H3）；同时攻速 +20%（META 区，不计入 H3% 加和）", "survive_build", "分层写清；避免双算"], 100, "", "support"),
    U(["demon_hunter", "恶魔猎手", "blue", "基础属性", "H3", "add_pct", 0.08, "demon_hunter", "on_kill", 1, 1, 0,
       "击杀后攻击 +8%/层，最多 5 层（+40%），持续 3s", "generic", "v3.1: 10%→8%"], 100, "", "support"),

    U(["warrior_breath", "战士之息", "white", "基础属性", "H1", "add_pct", 0.05, "atk_mult", "passive", 5, 0, 0,
       "攻击 +5%/级，max 5（叠至 +25%）", "generic", ""], 130, "", "filler"),
    U(["wounded_warrior", "负伤战士", "white", "基础属性", "H3", "add_pct", 0.35, "wounded_buff", "on_hit", 1, 1, 0,
       "受伤后 5s 内攻击 +35%", "survive_build", "v3.1: 50%→35%"], 125, "", "filler"),
]

# ===================== 生存防御 (10) =====================
survive = [
    U(["holy_guard", "神圣守护", "orange", "生存防御", "SURVIVE", "count", 1, "wave_shield", "stage_start", 1, 1, 0,
       "每关战斗开始时获得 1 层护盾，抵挡 1 次伤害（含致命）", "survive_build", "v3.1: every_wave→stage_start"], 80, "", "core"),
    U(["power_soul", "力量之魂", "orange", "生存防御", "SURVIVE", "add_pct", 0.35, "max_hp_mult", "passive", 1, 1, 0,
       "最大生命 +35%", "survive_build", "v3.1: 40%→35%"], 80, "", "core"),

    U(["adversity_heart", "逆境之心", "purple", "生存防御", "H3", "add_pct", 0.08, "adversity_heart", "hp_below_50", 5, 0, 0,
       "HP<50% 时攻击 +8%/级，max 5（最多 +40%）", "survive_build", ""], 100, "", "support"),
    U(["resurrect", "复活", "purple", "生存防御", "SURVIVE", "count", 1, "resurrect", "on_death", 1, 1, 0,
       "死亡后以 50% 生命复活一次（本局一次）", "survive_build", "v3.1 满复活→半血，降强度"], 90, "", "support"),

    U(["vital_spring", "战地复苏", "blue", "生存防御", "SURVIVE", "proc_pct", 0.25, "vital_spring", "on_kill", 1, 1, 0,
       "击杀敌人时 25% 几率回复 6% 最大生命；脱离战斗 3s 后每秒回复 2% 最大生命", "survive_build", "v3.3 替代圣盾"], 100, "", "support"),
    U(["steadfast_guard", "不动如山", "blue", "生存防御", "SURVIVE", "add_pct", 0.25, "steadfast_guard", "idle_before_draw_1.5s", 4, 0, 0,
       "进入划线前静止 1.5s：获得减伤 25%（每级 +3%，上限 40%），持续至本次攻击结束", "combo_build",
       "v3.1 改触发：划线前静止，避免跑图站桩；标签改 combo"], 95, "stand_dr", "support"),
    U(["life_spring", "生命之泉", "blue", "生存防御", "SURVIVE", "add_pct", 0.12, "max_hp_mult", "passive", 1, 1, 0,
       "最大生命 +12%，获得时回复 20% 当前生命", "survive_build", "v3.1 不再一键满血"], 100, "", "support"),
    U(["angel_shelter", "天使庇护", "blue", "生存防御", "SURVIVE", "add_pct", 0.10, "max_hp_mult", "on_hit", 1, 1, 0,
       "最大生命 +10%；受伤后 1.2s 无敌（内置 CD 8s）", "survive_build", "v3.1 加 CD，与减伤球区分"], 95, "", "support"),

    U(["power_blood", "力量之血", "white", "生存防御", "SURVIVE", "add_pct", 0.05, "max_hp_mult", "passive", 5, 0, 0,
       "最大生命 +5%/级，max 5（叠至 +25%）", "survive_build", ""], 130, "", "filler"),
    U(["demon_heal", "恶魔恢复", "white", "生存防御", "SURVIVE", "proc_pct", 0.12, "demon_heal", "on_kill", 1, 1, 0,
       "击杀时 12% 几率恢复 4% 最大生命", "survive_build", ""], 125, "", "filler"),
]

# ===================== 普攻子弹 (11) =====================
bullet = [
    U(["barrage_king", "弹幕之王", "orange", "普攻子弹", "H2", "count", 3, "barrage_king", "passive", 1, 0, 1,
       "普攻子弹 +3；攻速 ×0.85；额外子弹受 H2 衰减", "bullet_build", "本章一次；与元气弹/光束互斥"], 70, "orange_bullet", "core"),
    U(["spirit_bomb", "元气弹", "orange", "普攻子弹", "H2", "mult", 1.25, "spirit_bomb", "passive", 1, 1, 0,
       "普攻变元气弹，单发伤害 ×1.25（本局一次，不受多弹衰减）", "bullet_build", ""], 70, "orange_bullet", "core"),
    U(["energy_beam", "能量光束", "orange", "普攻子弹", "H2", "mult", 0.65, "energy_beam", "charge", 1, 1, 0,
       "蓄力释放穿透能量束，共 4 段，每段 0.65×ATK", "bullet_build", ""], 70, "orange_bullet", "core"),

    U(["diagonal_arrow", "斜向射", "purple", "普攻子弹", "H2", "count", 2, "diagonal_arrow", "passive", 1, 1, 0,
       "+2 颗斜向子弹（列入 H2 衰减豁免清单）", "bullet_build", ""], 95, "", "support"),
    U(["mirror_bullet", "镜像子弹", "purple", "普攻子弹", "H2", "count", 1, "mirror_bullet", "passive", 1, 1, 0,
       "命中后回程，回程伤害 = 命中时 H2 结算伤害（仍吃衰减）", "bullet_build", ""], 90, "", "support"),
    U(["homing_eye", "追踪之眼", "purple", "普攻子弹", "H2", "mult", 0.85, "homing_eye", "passive", 1, 1, 0,
       "子弹追踪；伤害 ×0.85、速度 ×0.55", "bullet_build", "v3.1 追踪惩罚略增"], 85, "", "support"),

    U(["charge_arrow", "蓄力射", "blue", "普攻子弹", "H2", "mult", 1.80, "charge_arrow", "charge", 1, 1, 0,
       "蓄力巨型子弹 1.8×ATK，穿透", "bullet_build", "v3.1: 2.0→1.8"], 100, "", "support"),
    U(["split_arrow", "分裂射", "blue", "普攻子弹", "H2", "mult", 0.35, "split_arrow", "on_hit", 1, 1, 0,
       "命中分裂 3 颗，每颗 0.35×当次 H2 伤害", "bullet_build", ""], 100, "", "support"),
    U(["bounce_bullet", "弹射子弹", "blue", "普攻子弹", "H2", "count", 1, "bounce_bullet", "passive", 3, 0, 0,
       "弹射 +1 次/级，max 3", "bullet_build", "v3.1: max4→3"], 100, "", "support"),
    U(["swift_arrow", "迅捷射", "blue", "普攻子弹", "H2", "mult", 0.82, "swift_arrow", "passive", 1, 1, 0,
       "攻速 +80%；子弹伤害 ×0.82；散射 ±6°", "bullet_build", "副玩法；略削"], 90, "bullet_fast", "support"),

    U(["multi_bullet", "多重子弹", "white", "普攻子弹", "H2", "count", 1, "bullet_count", "passive", 3, 0, 0,
       "普攻子弹 +1/级，max 3（吃 H2 衰减）", "bullet_build", "v3.1 明确吃衰减"], 130, "", "filler"),
]

# ===================== 连击画线 (10) =====================
combo = [
    U(["multi_combo", "多重连击", "orange", "连击画线", "H3", "add_pct", 0.15, "combo_mult", "passive", 5, 0, 0,
       "连击权重 +0.15/级，max 5（每段连击伤害加成提升）", "combo_build", "本作主轴橙"], 85, "", "core"),
    U(["great_fireball", "豪火球术", "orange", "连击画线", "H3", "mult", 2.20, "fireball", "combo_milestone_14", 1, 1, 0,
       "连击每 +14 段释放豪火球，2.2×ATK 范围伤害", "combo_build", "v3.1: 12段→14段，2.5→2.2"], 85, "", "core"),

    U(["water_tornado", "水龙卷术", "purple", "连击画线", "H3", "mult", 1.00, "water_tornado", "combo_milestone_6", 5, 0, 0,
       "连击每 +6 段（每级 -0.5 段，min 4）释放水龙卷 1.0×ATK；不再附带暴击", "combo_build", "v3.1 拆层：纯 H3 技能"], 105, "", "support"),
    U(["keen_combo_eye", "连击锐眼", "purple", "连击画线", "H4", "add_pct", 0.03, "crit_rate", "passive", 5, 0, 0,
       "暴击率 +3%/级，max 5（受全局 50% 上限）", "combo_build", "替代原水龙卷上的 H4"], 100, "", "support"),
    U(["black_hole", "黑洞", "purple", "连击画线", "H3", "mult", 1.40, "black_hole", "combo_milestone_8", 1, 1, 0,
       "连击每 +8 段生成 1 个黑洞，1.4×ATK 吸入伤害", "combo_build", "v3.3: combo_eq_8→milestone_8"], 95, "", "support"),
    U(["blade_whirl", "刀阵旋风", "purple", "连击画线", "H3", "mult", 1.15, "whirl", "combo_milestone_8", 1, 1, 0,
       "连击每 +8 段：6 把刀旋风，每把 1.15×ATK", "combo_build", ""], 100, "", "support"),
    U(["charge_strike", "蓄力击", "purple", "连击画线", "H2", "mult", 1.35, "charge_strike", "idle_before_draw_0.4s", 1, 1, 0,
       "划线前每静止 0.4s：下次斩击 +12% 伤害与 +8% 攻速，上限 ×1.35，出手后重置", "combo_build", "与不动如山同语义域"], 100, "stand_dr", "support"),
    U(["slash_aftershock", "斩击余波", "purple", "连击画线", "H3", "mult", 0.85, "slash_aftershock", "slash_end", 1, 1, 0,
       "每次划线攻击结束时，在路径末端造成 0.85×ATK 范围冲击", "combo_build", "v3.3 替代深渊爆炸"], 105, "", "support"),

    U(["shuriken", "手里剑", "blue", "连击画线", "H3", "count", 2, "shuriken_count", "combo_hit", 5, 0, 0,
       "每次连击 +2 枚手里剑（每级 +1，max 6 枚），每枚 0.38×ATK", "combo_build", ""], 110, "", "support"),
    U(["lightning_chain", "闪电链", "blue", "连击画线", "H3", "mult", 0.55, "chain", "combo_milestone_8", 4, 0, 0,
       "连击每 +8 段：闪电链跳 3 目标（每级 +1 跳，max 7 跳），每跳 0.55×直伤", "combo_build", "v3.1 max5→4"], 105, "", "support"),
]

# ===================== 画线轨迹 (10) =====================
trail = [
    U(["trail_carnival", "轨迹狂欢", "orange", "画线轨迹", "E_A", "mult", 1.15, "trail_carnival", "line_drawn", 1, 1, 0,
       "轨迹附带火/雷/毒/冰；触发频率 ×1.4、持续 ×1.25（子弹时间内 tick 减半）", "trail_build", ""], 82, "orange_trail", "core"),
    U(["scorching_path", "灼热轨迹", "orange", "画线轨迹", "E_A", "mult", 0.45, "scorching_path", "line_on_trail", 1, 1, 0,
       "画线留 3s 火径：每 0.5s 0.45×ATK + 燃烧（期望总伤 ≈2.7×ATK，按覆盖 2 怪计）", "trail_build", ""], 82, "orange_trail", "core"),

    U(["thunder_field", "雷电力场", "purple", "画线轨迹", "E_A", "mult", 0.38, "thunder_field", "line_drawn", 1, 1, 0,
       "雷场 3s，每 0.5s 0.38×ATK（总伤 2.28×ATK/单怪满踩）", "trail_build", ""], 105, "", "support"),
    U(["toxic_mist", "腐蚀雾径", "purple", "画线轨迹", "E_A", "mult", 0.28, "toxic_mist", "line_drawn", 1, 1, 0,
       "毒雾 4s，每 0.5s 0.28×ATK + 剧毒", "trail_build", ""], 105, "", "support"),
    U(["frost_path", "霜径", "purple", "画线轨迹", "E_A", "mult", 0.45, "frost_path", "line_drawn", 1, 1, 0,
       "霜径 3s：接触减速 45%、单次 0.45×ATK，同怪 0.8s 内不重复", "trail_build", ""], 100, "", "support"),
    U(["trail_resonance", "轨迹共鸣", "purple", "画线轨迹", "E_A", "add_pct", 0.08, "trail_resonance", "passive", 5, 0, 0,
       "轨迹持续伤害 +8%/级，max 5（+40%）", "trail_build", ""], 100, "", "support"),

    U(["trail_lengthen", "轨迹延展", "blue", "画线轨迹", "META", "add_pct", 0.20, "trail_lengthen", "passive", 1, 1, 0,
       "轨迹宽度 +20%、持续 +20%", "trail_build", ""], 110, "", "support"),
    U(["trail_ignite", "余烬轨迹", "blue", "画线轨迹", "E_B", "mult", 0.22, "trail_ignite", "line_drawn", 1, 1, 0,
       "线尾引燃：3s 内每 0.5s 0.22×最近一次斩击直伤", "trail_build", ""], 105, "", "support"),
    U(["trail_static", "静电轨迹", "blue", "画线轨迹", "E_B", "proc_pct", 0.25, "trail_static", "line_on_trail", 1, 1, 0,
       "踩线敌人 25% 几率雷击 0.9×最近一次斩击直伤", "trail_build", ""], 100, "", "support"),

    U(["trail_spark", "轨迹火星", "white", "画线轨迹", "E_A", "mult", 0.08, "trail_spark", "line_drawn", 5, 0, 0,
       "轨迹散火星，每点 0.08×ATK/级，max 5", "trail_build", ""], 135, "", "filler"),
]

# ===================== 强化球 (15) =====================
orb = [
    U(["orb_overflow", "球潮溢涌", "orange", "强化球", "META", "flat", 9.0, "orb_overflow", "every_9s", 3, 1, 0,
       "每 9s 场上生成 1 颗随机强化球（每级 -1s，min 6s）；Boss 房不触发", "orb_build", ""], 78, "", "core"),
    U(["orb_resonance_x", "印记共鸣", "orange", "强化球", "H1", "mult", 1.35, "orb_resonance_x", "orb_collected", 1, 1, 0,
       "拾取强化球：该球增益 ×1.35（本局一次）", "orb_build", "v3.1: 1.5→1.35"], 78, "", "core"),

    U(["attack_orb_master", "攻击球·精通", "purple", "强化球", "H1", "add_pct", 0.15, "attack_orb_bonus", "orb_attack_eaten", 1, 1, 0,
       "攻击球：×1.45，持续 ×1.4", "orb_build", ""], 100, "", "support"),
    U(["ki_orb_master", "气力球·精通", "purple", "强化球", "META", "add_pct", 0.25, "ki_orb_bonus", "orb_ki_eaten", 1, 1, 0,
       "气力球：回复 +25%，拾取回 8% 最大生命", "orb_build", ""], 100, "", "support"),
    U(["combo_orb_master", "连击球·精通", "purple", "强化球", "H3", "mult", 1.35, "combo_orb_bonus", "orb_combo_eaten", 1, 1, 0,
       "连击球：×2.7，持续 ×1.4", "orb_build", ""], 105, "", "support"),
    U(["ice_orb_master", "冰球·精通", "purple", "强化球", "E_A", "mult", 1.50, "ice_orb_bonus", "orb_ice_eaten", 1, 1, 0,
       "冰球伤害 ×1.5、范围 +25%", "orb_build", ""], 95, "", "support"),
    U(["crit_orb_master", "暴击球·精通", "purple", "强化球", "H4", "add_pct", 0.10, "crit_orb_bonus", "orb_crit_eaten", 1, 1, 0,
       "暴击球：率 +40%、暴伤 +28%、持续 ×1.4", "orb_build", ""], 95, "", "support"),
    U(["orb_imprint", "球之印记", "purple", "强化球", "META", "proc_pct", 0.25, "orb_imprint", "orb_collected", 1, 1, 0,
       "拾取球：25% 保留同类印记至下一小波", "orb_build", ""], 90, "", "support"),

    U(["orb_rich_field", "丰沃球场", "blue", "强化球", "META", "add_pct", 0.40, "orb_rich_field", "stage_start", 1, 1, 0,
       "每关开局场上球数量 +40%", "orb_build", ""], 105, "", "support"),
    U(["orb_magnet", "球磁场", "blue", "强化球", "META", "add_pct", 0.65, "orb_magnet", "passive", 1, 1, 0,
       "拾取范围 +65%；划线时吸附半径内 70% 的球", "orb_build", ""], 110, "", "support"),
    U(["orb_detonate", "球爆引", "blue", "强化球", "E_A", "mult", 0.85, "orb_detonate", "orb_collected", 1, 1, 0,
       "拾取时在球位置爆炸 0.85×ATK（继承元素）", "orb_build", ""], 100, "", "support"),
    U(["orb_extend", "球延寿", "blue", "强化球", "META", "add_pct", 0.08, "orb_extend", "passive", 4, 0, 0,
       "球 buff 持续 +8%/级，max 4（+32%）", "orb_build", ""], 100, "", "support"),

    U(["orb_glow", "球之微光", "white", "强化球", "H1", "add_pct", 0.02, "orb_glow", "orb_collected", 5, 0, 0,
       "拾取球：本波攻击 +2%/级，max 5（+10%）", "orb_build", ""], 130, "", "filler"),
    U(["crit_orb", "暴击球", "white", "强化球", "H4", "add_pct", 0.20, "crit_orb", "orb_crit_eaten", 1, 1, 0,
       "入池；拾取 6s：暴击率 +20%（受上限）、暴伤 +12%", "orb_build", "球池基础类型"], 125, "orb_type_crit", "filler"),
    U(["shield_orb", "减伤球", "white", "强化球", "SURVIVE", "add_pct", 0.20, "shield_orb", "orb_shield_eaten", 1, 1, 0,
       "入池；拾取 5s：受到伤害 -20%", "orb_build", ""], 125, "orb_type_shield", "filler"),
]

# ===================== 单手剑 (10) =====================
sword = [
    U(["whirlwind_slash", "狂暴旋风", "orange", "单手剑", "H1", "mult", 0.28, "whirlwind_slash", "passive", 1, 1, 0,
       "4 把环绕剑：每秒 4 次，每次 0.28×ATK；连击每 +12 段触发大旋风 0.9×ATK", "sword_build", "副主轴；贴脸"], 72, "orange_sword", "core"),

    U(["mirror_blade", "镜影双剑", "purple", "单手剑", "H1", "mult", 1.15, "mirror_blade", "passive", 1, 1, 0,
       "2 把剑影：撞击 1.15×ATK；每 1.6s 剑气 0.85×ATK", "sword_build", ""], 90, "sword_stack", "support"),
    U(["quad_blade", "四剑环绕", "purple", "单手剑", "H1", "mult", 1.10, "quad_blade", "passive", 1, 1, 0,
       "4 把剑：各 1.10×ATK，转速 80°/s", "sword_build", ""], 90, "sword_stack", "support"),

    U(["blade_sharpen", "利刃磨砺", "blue", "单手剑", "H1", "add_pct", 0.22, "blade_sharpen", "passive", 5, 0, 0,
       "环绕剑伤害 +22%/级，max 5（+110%）", "sword_build", ""], 95, "", "support"),

    U(["flame_blade", "火焰剑", "white", "单手剑", "E_B", "mult", 0.45, "flame_blade", "passive", 1, 1, 0,
       "2 把火剑：0.45×ATK + 燃烧", "sword_build", ""], 120, "sword_element", "filler"),
    U(["lightning_blade", "雷霆剑", "white", "单手剑", "E_B", "mult", 0.45, "lightning_blade", "passive", 1, 1, 0,
       "2 把雷剑：0.45×ATK，链 3 跳", "sword_build", ""], 120, "sword_element", "filler"),
    U(["venom_blade", "毒刺剑", "white", "单手剑", "E_B", "mult", 0.45, "venom_blade", "passive", 1, 1, 0,
       "2 把毒剑：0.45×ATK + 毒", "sword_build", ""], 120, "sword_element", "filler"),
    U(["frost_blade", "寒霜剑", "white", "单手剑", "E_A", "mult", 0.45, "frost_blade", "passive", 1, 1, 0,
       "2 把冰剑：0.45×ATK，冻结 0.8s", "sword_build", ""], 120, "sword_element", "filler"),
    U(["vampire_blade", "嗜血剑", "white", "单手剑", "H1", "mult", 0.42, "vampire_blade", "passive", 1, 1, 0,
       "2 把嗜血剑：0.42×ATK，命中回 1.5% 最大生命（CD 0.6s）", "sword_build", ""], 115, "", "filler"),

    U(["guardian_blade", "守护剑", "white", "单手剑", "H1", "mult", 0.28, "guardian_blade", "passive", 1, 1, 0,
       "2 把守护剑：0.28×ATK；存在时受到的伤害 -5%", "sword_build", "入门"], 125, "", "filler"),
]

# ===================== 召唤 (11) =====================
pet_summon = [
    U(["heavenly_thunder", "天雷", "orange", "召唤", "P", "mult", 0.34, "thunder", "passive_1s", 5, 0, 0,
       "【召唤物】落雷 · 【频率】每秒 1 次 · 【单次】0.34×ATK · 【范围】当前屏随机落点", "pet_build", "天雷流橙"], 75, "orange_thunder", "core"),
    U(["spirit_covenant", "精灵盟约", "orange", "召唤", "P", "mult", 1.00, "spirit_covenant", "passive", 1, 1, 0,
       "立刻获得精灵王与奥术精灵；精灵类召唤物伤害 +15%、攻击间隔 -10%", "pet_build", "v3.3 精灵流核心橙"], 78, "orange_spirit", "core"),

    U(["divine_god", "天神", "purple", "召唤", "P", "mult", 1.10, "pet_god", "passive", 5, 0, 0,
       "【召唤物】天神飞剑 · 【频率】每 0.30s 1 柄 · 【单次】1.10×ATK · 【范围】锁定最近敌人", "pet_build", ""], 95, "", "support"),
    U(["spirit_frenzy", "精灵狂潮", "purple", "召唤", "P", "mult", 1.35, "spirit_frenzy", "passive", 1, 1, 0,
       "所有召唤物 P 区伤害 ×1.35、攻击间隔缩短 25%", "pet_build", ""], 90, "", "support"),
    U(["arc_spirit", "奥术精灵", "purple", "召唤", "P", "mult", 0.48, "arc_spirit", "passive", 1, 1, 0,
       "【召唤物】奥术精灵 · 【频率】每 1.2s 一轮 · 【单次】4 段×0.48 ATK · 【范围】锁定最近敌人", "pet_build", "盟约已赠则叠等级"], 95, "", "support"),
    U(["spirit_sweep", "精灵横扫", "purple", "召唤", "P", "mult", 0.70, "spirit_sweep", "every_3s", 1, 1, 0,
       "【召唤物】横扫精灵 · 【频率】每 3s · 【单次】1.2s 内每 0.2s 0.70×ATK · 【范围】环绕主角一圈", "pet_build", ""], 90, "", "support"),

    U(["wild_bull", "野熊", "blue", "召唤", "P", "mult", 0.75, "pet_bull", "passive", 5, 0, 0,
       "【召唤物】野熊 · 【频率】每 2s 冲撞 1 次 · 【单次】0.75×ATK · 【范围】直线突进最近敌人", "pet_build", ""], 100, "", "support"),
    U(["spirit_satellite", "精灵卫星", "blue", "召唤", "P", "mult", 0.55, "spirit_satellite", "every_1_5s", 4, 0, 0,
       "【召唤物】精灵卫星 · 【频率】每 1.5s · 【单次】0.55×ATK · 【范围】锁定最近敌人，每级 +1 颗，max 6 颗", "pet_build", ""], 95, "", "support"),
    U(["spirit_boost", "精灵强化", "blue", "召唤", "P", "mult", 1.30, "spirit_boost", "passive", 1, 1, 0,
       "召唤物 P 区伤害 ×1.30", "pet_build", ""], 100, "", "support"),

    U(["wild_wolf", "狼战士", "white", "召唤", "P", "mult", 0.72, "pet_wolf", "passive", 5, 0, 0,
       "【召唤物】2 名狼战士 · 【频率】每 1.8s 各扑击 1 次 · 【单次】0.72×ATK · 【范围】最近敌人", "pet_build", ""], 125, "", "filler"),
    U(["fire_spirit", "火焰精灵", "white", "召唤", "P", "mult", 0.48, "fire_spirit", "passive", 1, 1, 0,
       "【召唤物】火焰精灵 · 【频率】每 1.5s · 【单次】0.48×ATK+燃烧 · 【范围】最近敌人", "pet_build", ""], 120, "", "filler"),
    U(["spirit_king", "精灵王", "purple", "召唤", "P", "mult", 0.55, "spirit_king", "passive", 1, 1, 0,
       "【召唤物】精灵王 · 【频率】每 1.0s 一轮 · 【单次】4 段×0.55 ATK · 【范围】最近敌人周围", "pet_build", "盟约已赠则叠等级；橙位改盟约"], 100, "", "support"),
]

# ===================== 元素附加 (9) =====================
element = [
    U(["element_fusion", "元素融贯", "orange", "元素附加", "E_A", "mult", 1.20, "element_fusion", "passive", 1, 1, 0,
       "选定火/雷/毒/冰之一：该系 E_A/E_B 伤害 +20%、触发率 +15%", "element_build", "元素流专属橙"], 78, "orange_element", "core"),
    U(["super_flame", "焚天烈焰", "purple", "元素附加", "E_B", "mult", 1.30, "super_flame", "passive", 1, 1, 0,
       "火焰 +130%；燃烧 6 次/秒", "element_build", ""], 95, "element_super", "support"),
    U(["super_lightning", "惊雷裁决", "purple", "元素附加", "E_B", "mult", 0.40, "super_lightning", "passive", 1, 1, 0,
       "雷电 +40%；链 6 个目标", "element_build", ""], 95, "element_super", "support"),
    U(["super_poison", "腐骨之噬", "purple", "元素附加", "E_B", "mult", 1.60, "super_poison", "passive", 1, 1, 0,
       "毒 +160%；15% 触发额外 2.5×直伤暴毒", "element_build", "v3.1 400%→2.5×"], 95, "element_super", "support"),
    U(["super_ice", "绝寒之裁", "purple", "元素附加", "E_A", "mult", 2.40, "super_ice", "passive", 1, 1, 0,
       "冰冻 2.4×ATK，冰碎 +0.8×ATK，冻结时长 2.0s", "element_build", ""], 95, "element_super", "support"),

    U(["flame", "烈焰", "blue", "元素附加", "E_B", "mult", 0.28, "flame", "on_hit", 1, 1, 0,
       "子弹附火：0.28×直伤 + 燃烧", "element_build", ""], 100, "", "support"),
    U(["lightning", "雷电", "blue", "元素附加", "E_B", "mult", 0.36, "lightning", "on_hit", 1, 1, 0,
       "子弹附雷：0.36×直伤，链 4 目标", "element_build", ""], 100, "", "support"),
    U(["poison", "剧毒", "blue", "元素附加", "E_B", "mult", 0.22, "poison", "on_hit", 1, 1, 0,
       "子弹附毒：5s 每秒 0.22×直伤", "element_build", ""], 100, "", "support"),
    U(["ice", "冰冻", "blue", "元素附加", "E_A", "mult", 0.90, "ice", "on_hit", 1, 1, 0,
       "子弹附冰：1.2s 冻结，0.90×ATK", "element_build", ""], 100, "", "support"),
]

# ===================== 气力运势 (3) =====================
ki_meta = [
    U(["four_leaf_clover", "四叶草", "blue", "气力运势", "META", "add_pct", 0.03, "luck_roll", "passive", 5, 0, 0,
       "幸运：蓝 -4%/级、紫 +3%/级、橙 +1%/级", "ki_build", ""], 105, "", "support"),
    U(["ki_overflow", "气力涌泉", "blue", "气力运势", "META", "add_pct", 0.25, "ki_overflow", "passive", 1, 1, 0,
       "气力回复 +25%、气力上限 +12%", "ki_build", ""], 110, "", "support"),

    U(["luck", "运气", "white", "气力运势", "META", "mult", 1.08, "ki_mult", "passive", 3, 0, 0,
       "气力上限 ×1.08/级，max 3", "ki_build", "v3.1: max5→3"], 130, "", "filler"),
]

ALL = basics + survive + bullet + combo + trail + orb + sword + pet_summon + element + ki_meta

assert len(ALL) == 100, f"Expected 100 rows, got {len(ALL)}"

# ===================== Build workbook =====================
wb = openpyxl.Workbook()
thin = Side(border_style="thin", color="C0C0C0")
border = Border(left=thin, right=thin, top=thin, bottom=thin)
header_fill = PatternFill(start_color="2E2E2E", end_color="2E2E2E", fill_type="solid")
header_font = Font(color="FFFFFF", bold=True, name="Microsoft YaHei")
body_font = Font(name="Microsoft YaHei", size=10)
center = Alignment(horizontal="center", vertical="center", wrap_text=True)
left_wrap = Alignment(horizontal="left", vertical="center", wrap_text=True)

ws1 = wb.active
ws1.title = "Upgrades"
headers = [
    "id", "name_cn", "rarity", "group", "dmg_layer", "value_type", "apply_value",
    "apply_type", "trigger", "max_level", "once_per_run", "once_per_chapter",
    "desc_cn", "build_tag", "notes", "pool_weight", "excl_group", "design_role",
]
ws1.append(headers)
for col_idx, _ in enumerate(headers, 1):
    c = ws1.cell(row=1, column=col_idx)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for row in ALL:
    ws1.append(list(row))
for r in range(2, ws1.max_row + 1):
    rarity = ws1.cell(row=r, column=3).value
    fill = PatternFill(start_color=RARITY_FILL[rarity], end_color=RARITY_FILL[rarity], fill_type="solid")
    for col in range(1, len(headers) + 1):
        cell = ws1.cell(row=r, column=col)
        cell.fill = fill
        cell.font = body_font
        cell.border = border
        cell.alignment = left_wrap if col in (13, 15, 18) else center
widths = [18, 14, 8, 12, 11, 11, 12, 22, 20, 10, 13, 16, 52, 14, 28, 10, 14, 10]
for i, w in enumerate(widths, 1):
    ws1.column_dimensions[get_column_letter(i)].width = w
ws1.row_dimensions[1].height = 24
ws1.freeze_panes = "A2"
ws1.auto_filter.ref = ws1.dimensions

# --- RarityWeights ---
ws2 = wb.create_sheet("RarityWeights")
rw_headers = [
    "rarity", "name_cn", "chance", "color_hex", "overlay", "edge_glow", "card_glow",
    "shimmer", "pulse", "spark_count", "rays", "luck_roll_modifier", "design_note",
]
ws2.append(rw_headers)
rw_rows = [
    ("white", "普通", 0.18, "#d8d8d8", 0.76, 0.00, 0.12, 0, 0, 0, 0,
     "三选一主池；偏 filler/入门", "白装占 18%；design_role=filler 权重更高"),
    ("blue", "稀有", 0.35, "#58a8ff", 0.80, 0.28, 0.32, 1, 0, 6, 0,
     "四叶草每级 -4%", ""),
    ("purple", "史诗", 0.32, "#b070ff", 0.84, 0.48, 0.50, 1, 1, 12, 0,
     "四叶草每级 +3%", ""),
    ("orange", "传奇", 0.15, "#ff9830", 0.88, 0.78, 0.85, 1, 1, 22, 1,
     "四叶草每级 +1%", "橙 15%；同 excl_group 橙装已拥有则不出同组"),
]
for r in rw_rows:
    ws2.append(list(r))
for col in range(1, len(rw_headers) + 1):
    c = ws2.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, 6):
    rar = ws2.cell(row=r, column=1).value
    fill = PatternFill(start_color=RARITY_FILL[rar], end_color=RARITY_FILL[rar], fill_type="solid")
    for col in range(1, len(rw_headers) + 1):
        cc = ws2.cell(row=r, column=col)
        cc.fill = fill
        cc.font = body_font
        cc.alignment = left_wrap if col >= 12 else center
        cc.border = border
for i, w in enumerate([10, 8, 8, 12, 9, 11, 11, 9, 8, 13, 7, 22, 36], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w

# --- GlobalCaps ---
ws_cap = wb.create_sheet("GlobalCaps")
cap_headers = ["key", "value", "unit", "说明", "关联升级/系统"]
ws_cap.append(cap_headers)
cap_rows = [
    ("crit_rate_cap", 0.50, "比率", "暴击率硬上限", "连击锐眼、暴击球、暴击精通"),
    ("crit_damage_cap", 2.50, "倍率", "暴击伤害倍率上限（相对基础 1.6）", "暴击球系"),
    ("h2_bullet_decay", 0.88, "每额外弹", "H2：第 2 发起每多 1 颗子弹 ×0.88", "多重子弹、弹幕之王；豁免见 h2_decay_exempt"),
    ("h2_decay_exempt", "diagonal_arrow", "id 列表", "不计入衰减的子弹来源", "斜向射"),
    ("h2_slash_decay", 0.92, "每额外段", "额外斩击段 ×0.92（预留）", "—"),
    ("combo_hit_display_cap", 99, "次", "HUD 连击显示封顶", "—"),
    ("orb_types_max_on_field", 6, "个", "同屏强化球类型上限", "丰沃球场"),
    ("orb_crit_spawn_cap", 0.22, "概率", "暴击球生成上限（含精通后）", "crit_orb"),
    ("orb_shield_spawn_cap", 0.18, "概率", "减伤球生成上限", "shield_orb"),
    ("trail_tick_bullet_time", 0.50, "比率", "子弹时间内轨迹 DOT 频率", "轨迹狂欢、灼热轨迹"),
    ("upgrades_per_run_avg", 8, "次", "期望升级次数（8 关）", "GachaRules 平衡用"),
    ("primary_build_bias", "combo+trail", "标签", "本作默认高权重 build_tag", "见 GachaRules"),
]
for r in cap_rows:
    ws_cap.append(list(r))
for col in range(1, len(cap_headers) + 1):
    c = ws_cap.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws_cap.max_row + 1):
    for col in range(1, len(cap_headers) + 1):
        cc = ws_cap.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap
        cc.border = border
for i, w in enumerate([22, 10, 10, 40, 36], 1):
    ws_cap.column_dimensions[get_column_letter(i)].width = w
ws_cap.freeze_panes = "A2"

# --- GachaRules ---
ws_gacha = wb.create_sheet("GachaRules")
g_headers = ["规则 id", "说明", "参数", "备注"]
ws_gacha.append(g_headers)
g_rows = [
    ("rarity_roll", "先 roll 稀有度，再在对应稀有度池抽 3 张", "见 RarityWeights", "总和=100%"),
    ("white_in_pool", "白装进入三选一主池", "chance=18%", "v3.0 白 chance=0 已废弃"),
    ("pool_weight", "同稀有度内按 pool_weight 加权", "filler 130 / core 75", "design_role 可批量改"),
    ("build_bias", "每 3 次升级：至少 1 张来自已选 build_tag", "若已有 2 个不同 tag", "防止纯随机废局"),
    ("excl_group", "同组橙装核心互斥", "orange_bullet/orange_trail/orange_thunder/orange_spirit…", "见 Upgrades.excl_group"),
    ("max_same_card", "同 id 达 max_level 后不再出现", "—", ""),
    ("orange_pity", "连续 4 次升级无橙：第 5 次必含 1 橙", "可叠加四叶草", "可选规则"),
    ("boss_room_orb", "Boss 房：球潮溢涌暂停；丰沃球场不生效", "—", "orb_build 瓶颈对策"),
    ("duplicate_penalty", "三选一出现 2 张同 build_tag 时，第 3 张倾向其它 tag", "权重 ×1.4", "提高构筑辨识度"),
]
for r in g_rows:
    ws_gacha.append(list(r))
for col in range(1, len(g_headers) + 1):
    c = ws_gacha.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws_gacha.max_row + 1):
    for col in range(1, len(g_headers) + 1):
        cc = ws_gacha.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap
        cc.border = border
for i, w in enumerate([14, 48, 28, 32], 1):
    ws_gacha.column_dimensions[get_column_letter(i)].width = w

# --- BaseAttributes ---
ws3 = wb.create_sheet("BaseAttributes")
ba_headers = ["key", "value", "description", "dmg_layer", "upgrades_that_modify"]
ws3.append(ba_headers)
ba_rows = [
    ("base_attack", 40, "基础攻击力", "H1", "warrior_soul, atk_boost, power_trio, …"),
    ("base_hp", 100, "基础生命", "SURVIVE", "power_soul, life_spring, power_blood, giant_force, vital_spring"),
    ("base_ki", 234, "基础气力上限", "META", "luck, ki_overflow"),
    ("ki_regen_speed", 60, "气力回复/秒", "META", "godspeed, ki_overflow"),
    ("base_crit_rate", 0.08, "暴击率", "H4", "keen_combo_eye, crit_orb, crit_orb_master"),
    ("base_crit_damage", 1.60, "暴击伤害倍率", "H4", "crit_orb, crit_orb_master"),
    ("crit_rate_cap", 0.50, "暴击率上限", "H4", "GlobalCaps"),
    ("crit_damage_cap", 2.50, "暴伤倍率上限", "H4", "GlobalCaps"),
    ("move_speed", 120, "摇杆移速 px/s", "META", "swift_soul, giant_force"),
    ("basic_attack_speed", 2, "普攻频率 次/秒", "H1", "godspeed, swift_soul, swift_arrow, desperate_rage(META)"),
    ("combo_damage_bonus", 0.01, "每连击伤害加成", "H3", "multi_combo"),
    ("auto_bullet_damage_mult", 0.5, "普攻子弹 H2 基线", "H2", "spirit_bomb, charge_arrow, energy_beam"),
    ("h2_bullet_decay_per_extra", 0.88, "每额外子弹 H2 乘数", "H2", "GlobalCaps；multi_bullet 吃衰减"),
    ("h2_decay_exempt_ids", "diagonal_arrow", "豁免子弹", "H2", ""),
    ("orb_spawn_chance_attack", 0.55, "攻击球", "META", "orb_rich_field, orb_overflow"),
    ("orb_spawn_chance_ki", 0.45, "气力球", "META", ""),
    ("orb_spawn_chance_combo", 0.42, "连击球", "META", ""),
    ("orb_spawn_chance_ice", 0.28, "冰球", "META", ""),
    ("orb_spawn_chance_crit", 0.18, "暴击球（v3.1 下调）", "META", "crit_orb"),
    ("orb_spawn_chance_shield", 0.15, "减伤球", "META", "shield_orb"),
    ("orb_attack_mult", 1.30, "攻击球 turn_buff", "H1", "attack_orb_master 提升至 1.45"),
    ("orb_combo_mult", 2.00, "连击球 turn_buff", "H3", "combo_orb_master 提升至 2.7"),
    ("orb_crit_rate_bonus", 0.20, "暴击球（率）", "H4", "crit_orb_master 提升至 +0.40"),
    ("orb_crit_damage_bonus", 0.12, "暴击球（暴伤）", "H4", ""),
    ("orb_shield_dr", 0.20, "减伤球", "SURVIVE", "shield_orb"),
    ("trail_dot_base", 0.45, "轨迹基础 tick×ATK", "E_A", "见灼热/雷场等"),
    ("trail_duration", 3.0, "轨迹基础秒", "E_A", "trail_lengthen, trail_carnival"),
    ("sword_orbit_count", 0, "默认无环绕剑", "H1", "quad_blade, whirlwind_slash, 元素剑"),
    ("pet_atk_coef", 1.0, "召唤 ATK 转化", "P", "spirit_covenant, spirit_frenzy, spirit_boost"),
]
for r in ba_rows:
    ws3.append(list(r))
for col in range(1, len(ba_headers) + 1):
    c = ws3.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws3.max_row + 1):
    for col in range(1, len(ba_headers) + 1):
        cc = ws3.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap if col >= 3 else center
        cc.border = border
for i, w in enumerate([28, 12, 36, 14, 48], 1):
    ws3.column_dimensions[get_column_letter(i)].width = w
ws3.freeze_panes = "A2"

# --- DamageFormula ---
ws4 = wb.create_sheet("DamageFormula")
df_headers = ["layer_code", "layer_name", "formula_segment", "aggregation", "project_fields", "设计约定", "说明"]
ws4.append(df_headers)
df_rows = [
    ("(sum)", "最终输出", "直伤 + E_A + E_B + P + 剑撞击", "求和", "—", "五系相加", "不互相缩放"),
    ("H1", "攻击乘区", "ATK × Π倍率", "乘算", "attack_power_scale, turn_buff_attack", "加法% 后乘", "战士之魂/攻提/球攻"),
    ("H2", "武器/弹道", "×武器 ×Π弹道 ×衰减", "乘算",
     "auto_bullet_damage_mult, slash, 0.88^(n-1)", "见 GlobalCaps", "斜向射豁免；斩击段用 slash_decay"),
    ("H3", "条件%", "×(1+Σ%)", "加和后乘", "combo, 低血, 击杀层", "", "连击球走 turn_buff_combo"),
    ("H4", "暴击", "×暴伤；率≤50%", "概率", "crit_rate_cap", "见 GlobalCaps", "连击锐眼/暴击球"),
    ("E_A", "元素·ATK", "ATK×H1×系数", "独立", "轨迹、冰、球爆", "子弹时间 tick×0.5", ""),
    ("E_B", "元素·直伤", "直伤×系数", "随直伤", "火焰/毒/雷", "吃 H2", ""),
    ("P", "召唤", "ATK×转化×Π召唤物", "独立", "pet_atk_coef", "不吃 H2", "伙伴/精灵/野兽/auto 召唤"),
    ("SURVIVE", "生存", "减伤/盾/HP", "—", "bonus_dr", "", ""),
    ("META", "系统", "掉率/气力/抽卡", "—", "luck_roll, ki", "", ""),
    ("slash", "斩击直伤", "沿路径命中", "H2+H3+H4", "perform_slash", "本作主轴", "斩击余波走 slash_end"),
]
for r in df_rows:
    ws4.append(list(r))
for col in range(1, len(df_headers) + 1):
    c = ws4.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws4.max_row + 1):
    for col in range(1, len(df_headers) + 1):
        cc = ws4.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap
        cc.border = border
for i, w in enumerate([10, 18, 40, 12, 36, 28, 44], 1):
    ws4.column_dimensions[get_column_letter(i)].width = w
ws4.freeze_panes = "A2"
for r in range(2, ws4.max_row + 1):
    ws4.row_dimensions[r].height = 56

# --- Builds ---
ws5 = wb.create_sheet("Builds")
b_headers = [
    "build_tag", "中文名", "定位", "核心橙", "紫装支柱", "蓝白铺量",
    "协同", "冲突", "瓶颈", "池权重建议",
]
ws5.append(b_headers)
b_rows = [
    ("combo_build", "连击画线", "主轴★", "多重连击 / 豪火球", "水龙卷 / 锐眼 / 斩击余波 / 蓄力击 / 刀阵 / 黑洞",
     "手里剑 / 闪电链", "轨迹流、球连击、generic H1", "纯弹幕橙（抢升级节奏）",
     "Boss 单体；依赖连击里程碑", "升级池权重 ×1.25"),
    ("trail_build", "画线轨迹", "主轴★", "轨迹狂欢 / 灼热轨迹", "雷场 / 毒径 / 霜径 / 共鸣",
     "延展 / 余烬 / 静电 / 火星", "元素融贯、combo、球爆引", "迅捷射跑打（线短）",
     "远程怪不踩线；子弹时间减半 tick", "×1.20"),
    ("generic", "基础属性", "辅轴", "战士之魂 / 力量三重奏", "攻提 / 巨人 / 迅捷之魂",
     "战士之息 / 负伤", "所有流", "—", "纯 H1 后期稀释", "×1.0"),
    ("orb_build", "强化球", "辅轴", "球潮 / 印记共鸣", "三精通 + 印记", "磁场 / 丰沃 / 爆引",
     "combo、trail", "手残不吃球", "Boss 房停球", "×1.05"),
    ("bullet_build", "普攻子弹", "副玩法", "弹幕 / 元气弹 / 光束（三选一）", "斜向 / 镜像 / 追踪",
     "蓄力 / 弹射 / 多重", "generic、元素 B", "迅捷+弹幕衰减", "H2 衰减；需豁免或单发", "×0.85"),
    ("element_build", "元素", "辅轴", "元素融贯", "四超级", "烈焰/雷/毒/冰", "trail、pet、bullet",
     "无元素触发源", "B 吃 H2 衰减", "×1.0"),
    ("pet_build", "召唤", "副玩法", "精灵盟约 / 天雷（二选一）", "精灵王 / 狂潮 / 奥术精灵 / 横扫 / 天神", "狼 / 熊 / 卫星 / 火精灵",
     "generic、元素", "天雷流与精灵流互斥橙", "召唤物数量与命中", "×0.95"),
    ("sword_build", "单手剑", "副玩法", "狂暴旋风", "镜影 / 四剑", "磨砺 + 元素剑", "generic H1",
     "贴脸；与轨迹抢 H1", "Boss 贴身", "×0.88"),
    ("survive_build", "生存", "粘合剂", "神圣守护 / 力量之魂", "复活 / 逆境", "战地复苏 / 不动 / 泉",
     "combo 滚雪球", "—", "缺输出需搭主轴", "×0.95"),
    ("ki_build", "气力运势", "放大器", "—", "—", "四叶草 / 涌泉 / 运气",
     "trail、orb", "—", "非独立 carry", "×1.0"),
]
for r in b_rows:
    ws5.append(list(r))
for col in range(1, len(b_headers) + 1):
    c = ws5.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws5.max_row + 1):
    for col in range(1, len(b_headers) + 1):
        cc = ws5.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap
        cc.border = border
for i, w in enumerate([14, 12, 10, 32, 36, 28, 28, 28, 32, 14], 1):
    ws5.column_dimensions[get_column_letter(i)].width = w
for r in range(2, ws5.max_row + 1):
    ws5.row_dimensions[r].height = 88
ws5.freeze_panes = "A2"

# --- ExclGroups 互斥组说明 ---
ws_excl = wb.create_sheet("ExclGroups")
ex_headers = ["excl_group", "说明", "包含 id（橙/核心）", "规则"]
ws_excl.append(ex_headers)
ex_rows = [
    ("orange_bullet", "普攻橙核心三选一", "barrage_king, spirit_bomb, energy_beam", "已持其一则其余权重×0"),
    ("orange_trail", "轨迹橙二选一", "trail_carnival, scorching_path", "同上"),
    ("orange_sword", "剑橙", "whirlwind_slash", "仅 1 个"),
    ("orange_thunder", "天雷流橙", "heavenly_thunder", "与 orange_spirit 互斥"),
    ("orange_spirit", "精灵流橙", "spirit_covenant", "与 orange_thunder 互斥；入队即获精灵王+奥术精灵"),
    ("orange_element", "元素橙", "element_fusion", "与元素融贯绑定"),
    ("bullet_fast", "极速弹幕", "swift_arrow", "与 barrage_king 同局互斥"),
    ("stand_dr", "划线前站桩", "steadfast_guard, charge_strike", "可共存但共享静止计时"),
    ("sword_stack", "剑影数量", "mirror_blade, quad_blade", "二选一"),
    ("sword_element", "入门元素剑", "flame/lightning/venom/frost_blade", "最多 2 种白剑"),
    ("element_super", "超级元素", "super_flame/lightning/poison/ice", "最多 2 个紫超元素"),
    ("orb_type_crit", "暴击球类型", "crit_orb", "与 orb_type_shield 独立"),
]
for r in ex_rows:
    ws_excl.append(list(r))
for col in range(1, len(ex_headers) + 1):
    c = ws_excl.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
    c.alignment = center
    c.border = border
for r in range(2, ws_excl.max_row + 1):
    for col in range(1, len(ex_headers) + 1):
        cc = ws_excl.cell(row=r, column=col)
        cc.font = body_font
        cc.alignment = left_wrap
        cc.border = border
for i, w in enumerate([16, 36, 40, 32], 1):
    ws_excl.column_dimensions[get_column_letter(i)].width = w

# --- Changelog ---
ws_log = wb.create_sheet("Changelog")
ws_log.append(["版本", "日期", "摘要"])
ws_log.append(["v3.0", "—", "100 条、分层、删药水、轨迹/球/剑"])
ws_log.append([
    "v3.1", "2026-06-04",
    "白装进池18%；橙15%；加 GlobalCaps/GachaRules/ExclGroups；削爆表；主轴 combo+trail；"
    "拆水龙卷与锐眼；元素橙；互斥组；H2衰减公式",
])
ws_log.append([
    "v3.2", "2026-06-04",
    "召唤激光→召唤；laser_spirit/satellite、beam_sweep 改名；desc_cn 去掉→前后对比",
])
ws_log.append([
    "v3.3", "2026-06-04",
    "删圣盾/闭合追加/深渊；补战地复苏/精灵盟约/斩击余波；黑洞改每8连击；橙拆天雷/精灵；元素融贯归元素组",
])
for col in range(1, 4):
    c = ws_log.cell(row=1, column=col)
    c.fill = header_fill
    c.font = header_font
ws_log.column_dimensions["A"].width = 10
ws_log.column_dimensions["B"].width = 14
ws_log.column_dimensions["C"].width = 80

import os
target = OUT
try:
    if os.path.exists(OUT):
        with open(OUT, "a"):
            pass
except PermissionError:
    target = OUT_FALLBACK
wb.save(target)
print(f"OK -> {target}")
print(f"wrote {len(ALL)} rows")
print("by rarity:", dict(Counter(r[2] for r in ALL)))
print("by group :", dict(Counter(r[3] for r in ALL)))
