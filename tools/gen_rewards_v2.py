# -*- coding: utf-8 -*-
"""
Generate D:/workspace/godot1/rzz_godot/奖励设计_v2.xlsx
Reorganized per latest feedback:
  - 飞剑系列 -> 炸弹系列 (掷弹/爆破)
  - 精灵保留
  - 流星 -> 激光 (光束/扫射)
  - 元素四件套保留
  - 新增 画线轨迹 流派 (与元素串联)
  - 新增 强化球 流派 (每 X 秒生成、共鸣、引爆、印记)
  - 原 "旋转球" 并入 强化球
"""
import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUT = r"D:\workspace\godot1\rzz_godot\奖励设计_v2.xlsx"

RARITY_FILL = {"white":"EAEAEA","blue":"CFE4FF","purple":"E4D2FF","orange":"FFE0B0"}
RARITY_CN = {"white":"普通","blue":"稀有","purple":"史诗","orange":"传奇"}

# columns: id, name_cn, rarity, group, dmg_layer, value_type, apply_value,
#          apply_type, trigger, max_level, once_per_run, once_per_chapter,
#          desc_cn, build_tag, notes

# ===================== 基础属性 =====================
basics = [
    ("warrior_soul",      "战士之魂",       "orange", "基础属性", "H1",  "mult",     1.30, "atk_mult",         "passive",         1, 1, 0, "攻击力 ×1.30（本局一次）", "generic", "弓2核心橙"),
    ("power_trio",        "力量三重奏",     "orange", "基础属性", "H1",  "add_pct",  0.15, "power_trio",       "passive",         1, 1, 0, "攻击 +15%、攻速 +20%、最大生命 +20%", "generic", "三合一橙"),
    ("multi_combo",       "多重连击",       "orange", "基础属性", "H3",  "add_pct",  0.20, "combo_mult",       "passive",         9, 0, 0, "连击权重 +0.2/级", "combo_build", "原版保留 id"),

    ("atk_boost",         "攻击力提升",     "purple", "基础属性", "H1",  "add_pct",  0.25, "atk_mult",         "passive",         9, 0, 0, "攻击 +25%/级（H1 加法求和后乘）", "generic", ""),
    ("giant_force",       "巨人之力",       "purple", "基础属性", "H1",  "mult",     1.20, "giant_force",      "passive",         1, 1, 0, "攻击 ×1.20、最大生命 +25%、体型变大、移速降低", "generic", ""),
    ("swift_soul",        "迅捷之魂",       "purple", "基础属性", "H1",  "add_pct",  0.25, "atk_speed_mult",   "passive",         1, 1, 0, "攻速 +25%、移速大幅提升", "bullet_build", ""),

    ("godspeed",          "神速",           "blue",   "基础属性", "H1",  "mult",     1.30, "godspeed",         "passive",         9, 0, 0, "攻速 ×1.3/级，气力回复 ×0.85/级", "bullet_build", "原版保留 id"),
    ("melee_strike",      "近战打击",       "blue",   "基础属性", "H1",  "add_pct",  0.20, "melee_strike",     "passive",         1, 1, 0, "攻击 +20%、攻速 +100%、攻击范围缩短至 7m", "bullet_build", ""),
    ("desperate_rage",    "绝境狂热",       "blue",   "基础属性", "H3",  "add_pct",  0.30, "desperate_rage",   "hp_below_50",     1, 0, 0, "HP<50% 时攻击 +30%、攻速 +30%", "survive_build", ""),
    ("wind_spirit",       "风之精灵",       "blue",   "基础属性", "H1",  "add_pct",  0.10, "wind_spirit",      "passive",         1, 1, 0, "攻速 +10%、移速 +10%", "generic", ""),
    ("demon_hunter",      "恶魔猎手",       "blue",   "基础属性", "H3",  "add_pct",  0.10, "demon_hunter",     "on_kill",         1, 1, 0, "击杀后攻击 +10%/层，最多 5 层（+50%），持续 3s", "generic", ""),
    ("warrior_heart",     "战士之心",       "blue",   "基础属性", "H1",  "add_pct",  0.05, "warrior_heart",    "on_heart_pickup", 1, 1, 0, "拾红心几率攻击 +5%/层，最多 10 层（+50%）", "generic", ""),

    ("warrior_breath",    "战士之息",       "white",  "基础属性", "H1",  "add_pct",  0.10, "atk_mult",         "passive",         9, 0, 0, "攻击 +10%/级", "generic", ""),
    ("spirit_breath",     "精灵之息",       "white",  "基础属性", "H1",  "add_pct",  0.10, "atk_speed_mult",   "passive",         9, 0, 0, "攻速 +10%/级", "generic", ""),
    ("wind_breath",       "风之息",         "white",  "基础属性", "H1",  "add_pct",  0.10, "move_speed_mult",  "passive",         9, 0, 0, "移速 +10%/级", "generic", ""),
    ("wounded_warrior",   "负伤战士",       "white",  "基础属性", "H3",  "add_pct",  0.50, "wounded_buff",     "on_hit",          1, 1, 0, "受伤后 5s 内攻击 +50%", "survive_build", ""),
    ("boss_killer",       "Boss 杀手",      "white",  "基础属性", "H3",  "add_pct",  0.25, "boss_dmg",         "vs_boss",         1, 1, 0, "对 Boss 伤害 +25%；Boss 战前完全恢复生命", "generic", ""),
]

# ===================== 生存防御 =====================
survive = [
    ("holy_guard",        "神圣守护",       "orange", "生存防御", "SURVIVE","count",  1,    "wave_shield",      "every_wave",      1, 1, 0, "获得护盾，每波可抵挡 1 次伤害", "survive_build", ""),
    ("power_soul",        "力量之魂",       "orange", "生存防御", "SURVIVE","add_pct",0.40, "max_hp_mult",      "passive",         1, 1, 0, "最大生命 +40%", "survive_build", ""),
    ("super_mushroom",    "超级蘑菇",       "orange", "生存防御", "H2",  "mult",     1.30, "super_mushroom",    "passive",         1, 1, 0, "斩击伤害 ×1.30、回满血、最大生命 ×1.2、体型 ×1.5", "survive_build", "原版保留 id"),
    ("stillness_heart",   "静止之心",       "orange", "生存防御", "H4",  "add_pct",  0.03, "stillness_heart",   "stand_0_5s",      1, 0, 1, "原地每 0.5s 暴击 +3% 与暴伤 +3%，最多 15 层", "combo_build", "原版保留 id"),

    ("adversity_heart",   "逆境之心",       "purple", "生存防御", "H3",  "add_pct",  0.15, "adversity_heart",   "hp_below_50",     9, 0, 0, "HP<50% 时攻击 +15%（每级 +5%）", "survive_build", "原版保留 id"),
    ("slow_field",        "减速领域",       "purple", "生存防御", "SURVIVE","count", 1,    "slow_field",        "passive",         1, 1, 0, "创造领域，减缓附近投射物和怪物速度", "survive_build", ""),
    ("resurrect",         "复活",           "purple", "生存防御", "SURVIVE","count", 1,    "resurrect",         "on_death",        1, 1, 0, "死亡后以满生命复活一次", "survive_build", ""),

    ("holy_shield",       "圣盾",           "blue",   "生存防御", "SURVIVE","flat",  15.0, "holy_shield_interval","passive",       9, 0, 0, "每 15s 获得 1 层护盾（每级 -1s，最多 5 层）", "survive_build", "原版保留 id"),
    ("steadfast_guard",   "不动如山",       "blue",   "生存防御", "SURVIVE","add_pct",0.30,"steadfast_guard",   "stand_1_5s",      9, 0, 0, "站立 1.5s 后生成减伤环：减伤 30%（每级 +5%，上限 60%）", "survive_build", "原版保留 id"),
    ("desperate_counter", "绝境反击",       "blue",   "生存防御", "H3",  "add_pct",  0.20, "desperate_counter", "on_hit",          9, 0, 0, "受击后 4s 内攻速 +20%、暴击 +20%（每级 +5%）", "survive_build", "原版保留 id"),
    ("lucky_bandaid",     "幸运创可贴",     "blue",   "生存防御", "META","mult",     2.00, "lucky_bandaid",     "on_hit",          1, 1, 0, "受击时对屏幕大部分敌人造成 2.0×ATK 并清除敌方投射物", "survive_build", ""),
    ("lucky_cookie",      "幸运饼干",       "blue",   "生存防御", "META","add_pct",  0.20, "evasion_pct",       "passive",         1, 1, 0, "幸运值大幅提升，闪避 +20%", "survive_build", ""),
    ("lucky_heart",       "幸运之心",       "blue",   "生存防御", "SURVIVE","add_pct",0.03,"max_hp_per_heart",  "on_heart_pickup", 1, 1, 0, "拾红心几率最大生命 +3%/层，最多 10 层（+30%）", "survive_build", ""),
    ("life_spring",       "生命之泉",       "blue",   "生存防御", "SURVIVE","add_pct",0.15,"max_hp_mult",       "passive",         1, 1, 0, "最大生命 +15%，拾取时完全恢复生命", "survive_build", ""),
    ("vitality_heart",    "活力之心",       "blue",   "生存防御", "SURVIVE","add_pct",0.15,"max_hp_mult",       "passive",         1, 1, 0, "最大生命 +15%，红心恢复效果增强至 32.5%", "survive_build", ""),
    ("angel_shelter",     "天使庇护",       "blue",   "生存防御", "SURVIVE","add_pct",0.15,"max_hp_mult",       "on_hit",          1, 1, 0, "最大生命 +15%，受伤后 2s 无敌", "survive_build", ""),

    ("power_blood",       "力量之血",       "white",  "生存防御", "SURVIVE","add_pct",0.10,"max_hp_mult",       "passive",         9, 0, 0, "最大生命 +10%/级", "survive_build", ""),
    ("heal_hp",           "恢复生命",       "white",  "生存防御", "SURVIVE","flat",  0.20,"heal_hp",            "on_pickup",       1, 0, 0, "恢复 20% 最大生命", "survive_build", ""),
    ("desperate_heal",    "绝境恢复",       "white",  "生存防御", "SURVIVE","add_pct",0.30,"desperate_heal",    "hp_below_30",     1, 1, 0, "HP<30% 时缓慢恢复至 30%", "survive_build", ""),
    ("demon_heal",        "恶魔恢复",       "white",  "生存防御", "SURVIVE","proc_pct",0.15,"demon_heal",       "on_kill",         1, 1, 0, "击杀几率回 5% 最大生命", "survive_build", ""),
]

# ===================== 普攻子弹 =====================
bullet = [
    ("energy_beam",       "能量光束",       "orange", "普攻子弹", "H2",  "mult",     0.70, "energy_beam",       "charge",          1, 1, 0, "蓄力释放强力穿透激光，每道光束 4 次 0.7×ATK 伤害", "bullet_build", ""),
    ("multi_shot",        "多重射击",       "orange", "普攻子弹", "H2",  "count",    1,    "multi_shot",        "passive",         1, 1, 0, "额外发射一轮主武器箭矢，攻击周期 +8 帧", "bullet_build", ""),
    ("barrage_king",      "弹幕之王",       "orange", "普攻子弹", "H2",  "count",    3,    "barrage_king",      "passive",         1, 0, 1, "普攻子弹 +3、攻速 ×0.8（本章一次）", "bullet_build", "原版保留 id"),
    ("spirit_bomb",       "元气弹",         "orange", "普攻子弹", "H2",  "mult",     1.30, "spirit_bomb",       "passive",         1, 1, 0, "普攻变元气弹，伤害 +30%（本局一次）", "bullet_build", "原版保留 id"),
    ("pierce",            "穿透",           "orange", "普攻子弹", "H2",  "count",    1,    "pierce_bullet",     "passive",         1, 1, 0, "普攻子弹穿透敌人（本局一次）", "bullet_build", "原版保留 id"),

    ("homing_eye",        "追踪之眼",       "purple", "普攻子弹", "H2",  "mult",     0.90, "homing_eye",        "passive",         1, 1, 0, "投射物追踪敌人，伤害 ×0.90、速度 ×0.50", "bullet_build", ""),
    ("diagonal_arrow",    "斜向箭",         "purple", "普攻子弹", "H2",  "count",    2,    "diagonal_arrow",    "passive",         1, 1, 0, "增加 2 支斜向发射的箭矢（无衰减）", "bullet_build", ""),
    ("energy_ring",       "能量环",         "purple", "普攻子弹", "H2",  "mult",     0.70, "energy_ring",       "charge",          1, 1, 0, "蓄力释放能量环，最多造成 11 次 0.7×ATK", "bullet_build", ""),
    ("mirror_bullet",     "镜像子弹",       "purple", "普攻子弹", "H2",  "count",    1,    "mirror_bullet",     "passive",         1, 1, 0, "普攻子弹命中后返回主角，回程可伤害敌人", "bullet_build", "原版保留 id"),
    ("close_range_shot",  "近距离射击",     "purple", "普攻子弹", "H2",  "add_pct",  0.35, "close_range_shot",  "passive",         9, 0, 0, "普攻子弹飞行距离越短伤害越高", "bullet_build", "原版保留 id"),

    ("standstill_power",  "屹立不倒",       "blue",   "普攻子弹", "H2",  "add_pct",  0.45, "standstill_power",  "standstill",      1, 1, 0, "站立攻击：攻速 +150%、攻击 +45%（渐增）", "bullet_build", ""),
    ("wing_arrow",        "光翼箭",         "blue",   "普攻子弹", "H2",  "proc_pct", 0.20, "wing_arrow",        "passive",         1, 1, 0, "投射物 20% 几率长翅，造成 +100% 额外伤害", "bullet_build", ""),
    ("swift_arrow",       "迅捷箭",         "blue",   "普攻子弹", "H2",  "mult",     0.80, "swift_arrow",       "passive",         1, 1, 0, "攻速 +100%、伤害 ×0.80、散射", "bullet_build", ""),
    ("front_arrow",       "前方箭",         "blue",   "普攻子弹", "H2",  "count",    1,    "front_arrow",       "passive",         1, 1, 0, "增加 1 支前方箭矢，主武器伤害 ×0.85", "bullet_build", ""),
    ("charge_arrow",      "蓄力箭",         "blue",   "普攻子弹", "H2",  "mult",     2.00, "charge_arrow",      "charge",          1, 1, 0, "蓄力发射巨型箭，造成 2.0×ATK，穿透敌人和障碍", "bullet_build", ""),
    ("pierce_arrow",      "穿透箭",         "blue",   "普攻子弹", "H2",  "count",    1,    "pierce_arrow",      "passive",         1, 1, 0, "投射物可穿透敌人", "bullet_build", ""),
    ("split_arrow",       "分裂箭",         "blue",   "普攻子弹", "H2",  "mult",     0.33, "split_arrow",       "on_hit",          1, 1, 0, "命中后分裂为 3 个小投射物，每个 0.33×初始伤害", "bullet_build", ""),
    ("bounce_bullet",     "弹射子弹",       "blue",   "普攻子弹", "H2",  "count",    1,    "bounce_bullet",     "passive",         9, 0, 0, "普攻子弹在敌人间弹射（每级 +1 次）", "bullet_build", "原版保留 id"),
    ("laser_blast",       "激光冲击",       "blue",   "普攻子弹", "H2",  "proc_pct", 0.06, "laser_blast",       "on_attack",       9, 0, 0, "普攻 6% 几率释放激光（每级 +6%）", "bullet_build", "原版保留 id"),

    ("multi_bullet",      "多重子弹",       "white",  "普攻子弹", "H2",  "count",    1,    "bullet_count",      "passive",         9, 0, 0, "普攻子弹数量 +1/级（无衰减）", "bullet_build", "原版保留 id"),
    ("range_power",       "远程威力",       "white",  "普攻子弹", "H2",  "add_pct",  0.40, "range_power",       "passive",         1, 1, 0, "投射物飞行距离越远伤害越高，最多 +40%", "bullet_build", ""),
    ("rebound_arrow",     "反弹箭",         "white",  "普攻子弹", "H2",  "count",    1,    "rebound_arrow",     "passive",         1, 1, 0, "投射物可在墙壁上反弹", "bullet_build", ""),
    ("back_arrow",        "后方箭",         "white",  "普攻子弹", "H2",  "count",    1,    "back_arrow",        "passive",         1, 1, 0, "增加 1 支向后发射的箭矢", "bullet_build", ""),
]

# ===================== 连击画线 (连击触发) =====================
combo = [
    ("great_fireball",    "豪火球术",       "orange", "连击画线", "H3",  "count",    1,    "fireball",          "combo_milestone_12", 9, 0, 0, "连击每 +12 释放豪火球", "combo_build", "原版保留 id"),
    ("storm_combo",       "暴风连击",       "orange", "连击画线", "H3",  "mult",     0.50, "storm_combo",       "combo_ge_30",     1, 1, 0, "连击 ≥30 时全场敌人造成 0.5×ATK 伤害", "combo_build", ""),

    ("water_tornado",     "水龙卷术",       "purple", "连击画线", "H4",  "add_pct",  0.05, "crit_rate",         "combo_milestone_5", 9, 0, 0, "暴击 +5%，连击每 +5 释放水龙卷", "combo_build", "原版保留 id"),
    ("black_hole",        "黑洞",           "purple", "连击画线", "H3",  "count",    1,    "black_hole",        "combo_eq_8",      9, 0, 0, "连击 =8 时生成黑洞", "combo_build", "原版保留 id"),
    ("blade_whirl",       "刀阵旋风",       "purple", "连击画线", "H3",  "count",    1,    "whirl",             "combo_milestone_8", 9, 0, 0, "连击每 +8 释放刀阵旋风", "combo_build", "原版保留 id"),
    ("charge_strike",     "蓄力击",         "purple", "连击画线", "H2",  "mult",     1.45, "charge_strike",     "stand_then_slash",9, 0, 0, "原地越久，普攻攻速与斩击伤害越高（斩击后重置）", "combo_build", "原版保留 id"),
    ("abyss_explosion",   "深渊爆炸",       "purple", "连击画线", "H3",  "mult",     1.20, "abyss_explosion",   "line_closed_circle", 9, 0, 0, "画线闭合圆时在范围内爆炸（每级 ×1.2）", "combo_build", "原版保留 id"),
    ("combo_frenzy",      "连击狂热",       "purple", "连击画线", "H3",  "add_pct",  0.005,"combo_dmg_bonus",   "passive",         9, 0, 0, "每点连击伤害加成 +0.5%（基础 1% → 1.5%）", "combo_build", ""),

    ("shuriken",          "手里剑",         "blue",   "连击画线", "H3",  "count",    2,    "shuriken_count",    "combo_hit",       9, 0, 0, "每次连击释放 2 枚手里剑", "combo_build", "原版保留 id"),
    ("lightning_chain",   "闪电链",         "blue",   "连击画线", "H3",  "count",    1,    "chain",             "combo_milestone_8", 9, 0, 0, "连击每 +8 释放闪电链", "combo_build", "原版保留 id"),
    ("combo_armor",       "连击护甲",       "blue",   "连击画线", "SURVIVE","add_pct",0.10,"combo_armor",       "combo_ge_10",     1, 1, 0, "连击 ≥10 时减伤 +10%", "combo_build", ""),
    ("combo_zoom",        "连击加成",       "blue",   "连击画线", "H3",  "add_pct",  0.10, "combo_bonus_dmg",   "combo_milestone_10", 9, 0, 0, "连击每 +10 段，当段斩击伤害 +10%", "combo_build", ""),

    ("combo_heal",        "连击回复",       "white",  "连击画线", "SURVIVE","proc_pct",0.01,"combo_heal",       "combo_ge_20",     1, 1, 0, "连击 ≥20 时每段连击回 1% HP", "combo_build", ""),
    ("closed_extra",      "闭合追加",       "white",  "连击画线", "H2",  "count",    1,    "closed_extra",      "line_closed",     1, 1, 0, "画线闭合时额外 +1 次斩击", "combo_build", ""),
]

# ===================== 画线轨迹 (新流派 / 与元素串联) =====================
trail = [
    # carry orange
    ("trail_carnival",    "轨迹狂欢",       "orange", "画线轨迹", "E_A", "mult",     1.20, "trail_carnival",    "line_drawn",      1, 1, 0, "画线轨迹同时附带火/雷/毒/冰四种元素，触发频率 ×1.5", "trail_build", "新增 carry"),
    ("scorching_path",    "灼热轨迹",       "orange", "画线轨迹", "E_A", "mult",     0.80, "scorching_path",    "stand_on_trail",  1, 1, 0, "画线后留下持续 4s 的火焰带，每 0.3s 造成 0.8×ATK 并附加燃烧", "trail_build", ""),

    # purple
    ("thunder_field",     "雷电力场",       "purple", "画线轨迹", "E_A", "mult",     0.50, "thunder_field",     "line_drawn",      1, 1, 0, "画线轨迹形成雷电力场 3s，每 0.4s 对触地敌人造成 0.5×ATK 雷电", "trail_build", ""),
    ("toxic_mist",        "腐蚀雾径",       "purple", "画线轨迹", "E_A", "mult",     0.35, "toxic_mist",        "line_drawn",      1, 1, 0, "画线轨迹生成毒雾 5s，每 0.5s 对敌造成 0.35×ATK 并附加剧毒", "trail_build", ""),
    ("frost_path",        "霜径",           "purple", "画线轨迹", "E_A", "mult",     0.40, "frost_path",        "line_drawn",      1, 1, 0, "画线轨迹冻结 4s，敌人接触减速 60%，造成 0.4×ATK", "trail_build", ""),
    ("trail_resonance",   "轨迹共鸣",       "purple", "画线轨迹", "E_A", "add_pct",  0.50, "trail_resonance",   "passive",         9, 0, 0, "画线轨迹所有持续伤害 +50%（每级 +15%）", "trail_build", ""),

    # blue
    ("trail_lengthen",    "轨迹延展",       "blue",   "画线轨迹", "META","add_pct",  0.25, "trail_lengthen",    "passive",         9, 0, 0, "画线轨迹宽度 +25%、持续时间 +25%", "trail_build", ""),
    ("trail_ignite",      "余烬轨迹",       "blue",   "画线轨迹", "E_B", "mult",     0.25, "trail_ignite",      "line_drawn",      1, 1, 0, "画线轨迹尾段引燃，触地敌人燃烧 3s，每 0.5s 造成 0.25×单次直伤", "trail_build", ""),
    ("trail_static",      "静电轨迹",       "blue",   "画线轨迹", "E_B", "proc_pct", 0.30, "trail_static",      "stand_on_trail",  1, 1, 0, "敌人触地时 30% 几率触发雷击，造成 1.0×单次直伤", "trail_build", ""),
    ("trail_slowzone",    "黏滞轨迹",       "blue",   "画线轨迹", "META","add_pct",  0.40, "trail_slowzone",    "stand_on_trail",  1, 1, 0, "敌人触地时减速 40%", "trail_build", ""),

    # white
    ("trail_spark",       "轨迹火星",       "white",  "画线轨迹", "E_A", "mult",     0.15, "trail_spark",       "line_drawn",      9, 0, 0, "画线轨迹随机散落火星，每点 0.15×ATK，每级 +0.05", "trail_build", ""),
    ("trail_shock",       "轨迹冲击",       "white",  "画线轨迹", "E_A", "mult",     0.30, "trail_shock",       "line_closed",     1, 1, 0, "画线闭合后轨迹对内部敌人一次性造成 0.30×ATK", "trail_build", ""),
    ("trail_breath",      "轨迹之息",       "white",  "画线轨迹", "META","add_pct",  0.10, "trail_lengthen",    "passive",         9, 0, 0, "画线轨迹持续时间 +10%/级", "trail_build", ""),
]

# ===================== 召唤宠物 (含 炸弹 + 精灵 + 激光) =====================
pet = [
    # ----- 橙 -----
    ("heavenly_thunder",  "天雷",           "orange", "召唤宠物", "P",   "mult",     1.00, "thunder",           "passive_1s",      9, 0, 0, "每秒落雷范围攻击 1.0×ATK", "pet_build", "原版保留 id"),
    ("nurturing_heart",   "养育之心",       "orange", "召唤宠物", "P",   "mult",     2.00, "pet_mult",          "passive",         1, 0, 1, "宠物数量翻倍（本章一次）", "pet_build", "原版保留 id"),
    ("spirit_king",       "精灵王",         "orange", "召唤宠物", "P",   "mult",     0.60, "spirit_king",       "passive",         1, 1, 0, "精灵王伙伴：发射追踪光束，每道 4 次 0.6×ATK", "pet_build", ""),
    ("photon_lance",      "光子长矛",       "orange", "召唤宠物", "P",   "flat",     2.5,  "photon_lance",      "every_2_5s",      1, 1, 0, "每 2.5s 释放一道穿透激光，定期触发已有激光齐射", "pet_build", "替代飞剑橙"),
    ("nova_bomb",         "新星核弹",       "orange", "召唤宠物", "P",   "flat",     5.0,  "nova_bomb",         "every_5s",        1, 1, 0, "每 5s 投掷一颗大型炸弹，落地 2.5×ATK + 范围燃烧 3s", "pet_build", "替代飞剑橙·炸弹版"),

    # ----- 紫 -----
    ("divine_god",        "天神",           "purple", "召唤宠物", "P",   "count",    1,    "pet_god",           "passive",         9, 0, 0, "宠物：召唤天神", "pet_build", "原版保留 id"),
    ("wild_call",         "野性号召",       "purple", "召唤宠物", "H1",  "add_pct",  0.06, "wild_call",         "per_pet",         9, 0, 0, "每有 1 个召唤物，主角攻速 +6%（每级 +2%）", "pet_build", "原版保留 id"),
    ("bloodthirst",       "嗜血",           "purple", "召唤宠物", "SURVIVE","proc_pct",0.08,"bloodthirst",      "pet_hit",         1, 1, 0, "召唤物命中有 8% 几率为主角回复 1% 生命", "pet_build", "原版保留 id"),
    ("spirit_frenzy",     "精灵狂潮",       "purple", "召唤宠物", "P",   "mult",     1.50, "spirit_frenzy",     "passive",         1, 1, 0, "所有精灵伤害和攻速大幅提升，基础 ×1.5", "pet_build", ""),
    ("laser_spirit",      "激光精灵",       "purple", "召唤宠物", "P",   "mult",     0.50, "laser_spirit",      "passive",         1, 1, 0, "激光精灵伙伴：每道光束 4 次 0.5×ATK", "pet_build", ""),
    ("bomb_master",       "爆破大师",       "purple", "召唤宠物", "P",   "mult",     1.50, "bomb_master",       "passive",         1, 1, 0, "所有炸弹基础伤害 +50%", "pet_build", "替代飞剑强化"),
    ("dual_bomb",         "双联炸弹",       "purple", "召唤宠物", "P",   "mult",     2.00, "dual_bomb",         "passive",         1, 1, 0, "投掷的炸弹数量翻倍", "pet_build", "替代双飞剑"),
    ("elemental_bomb",    "元素炸弹",       "purple", "召唤宠物", "P",   "count",    1,    "elemental_bomb",    "passive",         1, 1, 0, "炸弹可继承主武器的元素效果", "pet_build", "替代魔法飞剑"),
    ("beam_sweep",        "光束扫射",       "purple", "召唤宠物", "P",   "mult",     0.80, "beam_sweep",        "every_3s",        1, 1, 0, "每 3s 召唤一束扫射激光，沿屏幕水平扫过造成 0.8×ATK", "pet_build", "替代流星紫"),

    # ----- 蓝 -----
    ("wild_bull",         "野熊",           "blue",   "召唤宠物", "P",   "count",    1,    "pet_bull",          "passive",         9, 0, 0, "宠物：召唤一只野熊", "pet_build", "原版保留 id"),
    ("bomb_spirit",       "炸弹精灵",       "blue",   "召唤宠物", "P",   "mult",     0.40, "bomb_spirit",       "passive",         1, 1, 0, "炸弹精灵：每次最多 5 发，每发 0.4×ATK", "pet_build", ""),
    ("spirit_boost",      "精灵强化",       "blue",   "召唤宠物", "P",   "mult",     1.40, "spirit_boost",      "passive",         1, 1, 0, "精灵基础伤害 +40%", "pet_build", ""),
    ("salvo_bomb",        "齐射炸弹",       "blue",   "召唤宠物", "P",   "mult",     0.75, "salvo_bomb",        "every_wave",      1, 1, 0, "每波投掷 5 颗炸弹，每颗 0.75×ATK 范围伤害", "pet_build", "替代闪电飞剑"),
    ("quick_bomb",        "速投炸弹",       "blue",   "召唤宠物", "P",   "mult",     0.75, "quick_bomb",        "every_1_5s",      1, 1, 0, "每 1.5s 投掷 1 颗小炸弹，0.75×ATK 范围伤害", "pet_build", "替代瞬发飞剑"),
    ("laser_satellite",   "激光卫星",       "blue",   "召唤宠物", "P",   "mult",     0.60, "laser_satellite",   "every_2s",        1, 1, 0, "围绕主角的激光卫星每 2s 向最近敌人发射 0.6×ATK 光束", "pet_build", "替代连锁流星"),

    # ----- 白 -----
    ("wild_wolf",         "狼战士",         "white",  "召唤宠物", "P",   "count",    2,    "pet_wolf",          "passive",         9, 0, 0, "宠物：召唤两名狼战士", "pet_build", "原版保留 id"),
    ("fire_spirit",       "火焰精灵",       "white",  "召唤宠物", "P",   "count",    1,    "fire_spirit",       "passive",         1, 1, 0, "火焰精灵伙伴：造成伤害并附加燃烧", "pet_build", ""),
    ("lightning_spirit",  "雷电精灵",       "white",  "召唤宠物", "P",   "count",    1,    "lightning_spirit",  "passive",         1, 1, 0, "雷电精灵伙伴：造成伤害并附加雷电", "pet_build", ""),
    ("poison_spirit",     "剧毒精灵",       "white",  "召唤宠物", "P",   "count",    1,    "poison_spirit",     "passive",         1, 1, 0, "剧毒精灵伙伴：造成伤害并附加毒素", "pet_build", ""),
    ("ice_spirit",        "冰刺精灵",       "white",  "召唤宠物", "P",   "count",    1,    "ice_spirit",        "passive",         1, 1, 0, "冰刺精灵伙伴：造成伤害并附加冰冻", "pet_build", ""),
    ("ambush_bomb",       "突袭炸弹",       "white",  "召唤宠物", "P",   "proc_pct", 0.15, "ambush_bomb",       "on_attack",       1, 1, 0, "攻击时几率投掷一颗小炸弹", "pet_build", "替代突击飞剑"),
    ("pursuit_bomb",      "追击炸弹",       "white",  "召唤宠物", "P",   "count",    1,    "pursuit_bomb",      "on_kill",         1, 1, 0, "击杀怪物时投掷一颗追击炸弹", "pet_build", "替代追击飞剑"),
    ("retaliate_bomb",    "反击炸弹",       "white",  "召唤宠物", "P",   "count",    5,    "retaliate_bomb",    "on_hit",          1, 1, 0, "受伤时向四周抛出 5 颗小炸弹", "pet_build", "替代反击飞剑"),
]

# ===================== 强化球 (NEW - 围绕场上 orb 生成 / 共鸣 / 印记) =====================
orb_charge = [
    # carry orange
    ("orb_overflow",      "球潮溢涌",       "orange", "强化球",   "META","flat",     6.0,  "orb_overflow",      "every_6s",        1, 1, 0, "每 6s 在场上随机生成 1 颗强化球（类型按当前局内权重随机）", "orb_build", "强化球流派 carry"),
    ("orb_resonance_x",   "印记共鸣",       "orange", "强化球",   "H1",  "mult",     1.50, "orb_resonance_x",   "orb_collected",   1, 1, 0, "拾取强化球时，该球的局内增益效果 ×1.5", "orb_build", ""),

    # purple
    ("attack_orb_master", "攻击球·精通",   "purple", "强化球",   "H1",  "add_pct",  0.20, "attack_orb_bonus",  "orb_attack_eaten",1, 1, 0, "攻击球加成 1.3→1.5（H1 同区加 0.20）；持续时间延长 50%", "orb_build", ""),
    ("ki_orb_master",     "气力球·精通",   "purple", "强化球",   "META","add_pct",  0.30, "ki_orb_bonus",      "orb_ki_eaten",    1, 1, 0, "气力球回复 +30%；拾取时额外回 10% HP", "orb_build", ""),
    ("combo_orb_master",  "连击球·精通",   "purple", "强化球",   "H3",  "mult",     1.50, "combo_orb_bonus",   "orb_combo_eaten", 1, 1, 0, "连击球加成 ×2 → ×3；持续时间延长 50%", "orb_build", ""),
    ("ice_orb_master",    "冰球·精通",     "purple", "强化球",   "E_A", "mult",     1.80, "ice_orb_bonus",     "orb_ice_eaten",   1, 1, 0, "冰球触发的冰冻伤害 ×1.8、范围 +30%", "orb_build", ""),
    ("orb_imprint",       "球之印记",       "purple", "强化球",   "META","count",    1,    "orb_imprint",       "orb_collected",   1, 1, 0, "拾取强化球时，30% 几率保留 1 个同类印记到下一波", "orb_build", ""),

    # blue
    ("orb_rich_field",    "丰沃球场",       "blue",   "强化球",   "META","add_pct",  0.50, "orb_rich_field",    "stage_start",     1, 1, 0, "每关开局生成的强化球数量 +50%", "orb_build", ""),
    ("orb_magnet",        "球磁场",         "blue",   "强化球",   "META","add_pct",  0.80, "orb_magnet",        "passive",         1, 1, 0, "拾取范围 +80%，划线时自动吸附 80% 半径内的球", "orb_build", ""),
    ("orb_detonate",      "球爆引",         "blue",   "强化球",   "E_A", "mult",     1.00, "orb_detonate",      "orb_collected",   1, 1, 0, "拾取强化球时，在球的位置爆炸造成 1.0×ATK 范围伤害（附该球元素）", "orb_build", ""),
    ("orb_extend",        "球延寿",         "blue",   "强化球",   "META","add_pct",  0.40, "orb_extend",        "passive",         9, 0, 0, "强化球局内 buff 持续时间 +40%（每级 +10%）", "orb_build", ""),
    ("orb_ricochet",      "球之回响",       "blue",   "强化球",   "H3",  "add_pct",  0.30, "orb_ricochet",      "orb_collected",   1, 1, 0, "拾取一颗球后 3s 内，下次斩击伤害 +30%", "orb_build", ""),

    # white
    ("orb_starter",       "球之入门",       "white",  "强化球",   "META","add_pct",  0.10, "orb_starter",       "passive",         9, 0, 0, "每关开局生成的强化球数量 +10%/级", "orb_build", ""),
    ("orb_glow",          "球之微光",       "white",  "强化球",   "H1",  "add_pct",  0.05, "orb_glow",          "orb_collected",   9, 0, 0, "拾取强化球时，本波攻击 +5%/级", "orb_build", ""),
    ("orb_lucky",         "球之幸运",       "white",  "强化球",   "META","proc_pct", 0.10, "orb_lucky",         "orb_collected",   1, 1, 0, "拾取强化球时，10% 几率额外生成 1 颗同类球", "orb_build", ""),
    # 保留少量原"旋转球"概念作为环绕球（与 holy_shield 同位）
    ("guardian_orb",      "守护环绕球",     "white",  "强化球",   "H1",  "mult",     0.30, "guardian_orb",      "passive",         1, 1, 0, "环绕主角的 2 颗守护球，撞击敌人造成 0.3×ATK", "orb_build", "原旋转球概念压缩到 1 条"),
]

# ===================== 元素附加 (保留) =====================
element = [
    ("super_flame",       "焚天烈焰",       "purple", "元素附加", "E_B", "add_pct",  1.50, "super_flame",       "passive",         1, 1, 0, "火焰伤害 +150%，燃烧频率翻倍至 10 次/秒", "element_build", "原超级烈焰改名"),
    ("super_lightning",   "惊雷裁决",       "purple", "元素附加", "E_B", "add_pct",  0.50, "super_lightning",   "passive",         1, 1, 0, "雷电伤害 +50%，可同时击中 8 个目标", "element_build", "原超级雷电改名"),
    ("super_poison",      "腐骨之噬",       "purple", "元素附加", "E_B", "add_pct",  2.00, "super_poison",      "passive",         1, 1, 0, "毒素伤害 +200%，几率触发额外 400% 伤害", "element_build", "原超级剧毒改名"),
    ("super_ice",         "绝寒之裁",       "purple", "元素附加", "E_A", "mult",     3.00, "super_ice",         "passive",         1, 1, 0, "冰冻伤害提升至 3×ATK，冰碎追加 1×ATK，冰冻 2.1s", "element_build", "原超级冰冻改名"),

    ("flame",             "烈焰",           "blue",   "元素附加", "E_B", "mult",     0.30, "flame",             "on_hit",          1, 1, 0, "投射物点燃敌人，造成火焰伤害并附加燃烧", "element_build", "B 类基于单次直伤 30%"),
    ("lightning",         "雷电",           "blue",   "元素附加", "E_B", "mult",     0.40, "lightning",         "on_hit",          1, 1, 0, "投射物电击敌人，可连锁攻击 4 个目标", "element_build", ""),
    ("poison",            "剧毒",           "blue",   "元素附加", "E_B", "mult",     0.25, "poison",            "on_hit",          1, 1, 0, "投射物使敌人中毒，造成毒素伤害并持续掉血", "element_build", ""),
    ("ice",               "冰冻",           "blue",   "元素附加", "E_A", "mult",     1.00, "ice",               "on_hit",          1, 1, 0, "投射物冻结敌人 1.5s，造成 1×ATK", "element_build", "E_A 基于ATK"),
    ("bullet_burn",       "子弹灼烧",       "blue",   "元素附加", "E_B", "mult",     0.14, "bullet_burn",       "on_hit",          9, 0, 0, "普攻命中附加 1.5s 灼烧 DOT（每级 +14% 灼烧伤害）", "element_build", "原版保留 id"),
]

# ===================== 气力 / 抽卡 / 工具 =====================
ki_meta = [
    # purple
    ("luck_meta",         "幸运学",         "purple", "气力运势", "META","add_pct",  0.20, "luck_meta",         "passive",         1, 1, 0, "本局所有 proc_pct 类升级触发概率 +20%", "ki_build", ""),
    # blue
    ("four_leaf_clover",  "四叶草",         "blue",   "气力运势", "META","add_pct",  0.03, "luck_roll",         "passive",         9, 0, 0, "幸运提升：蓝 -4%/级、紫 +3%/级、橙 +1%/级", "ki_build", "原版保留 id"),
    ("invincibility",     "无敌药水",       "blue",   "气力运势", "SURVIVE","flat", 2.0,  "invincibility",     "on_pickup",       1, 0, 0, "拾取后获得 2s 无敌", "ki_build", ""),
    ("potion_rich",       "药水充沛",       "blue",   "气力运势", "META","add_pct",  0.50, "potion_rich",       "passive",         1, 1, 0, "地图上出现的药水数量 +50%", "ki_build", ""),
    ("ki_overflow",       "气力涌泉",       "blue",   "气力运势", "META","add_pct",  0.30, "ki_overflow",       "passive",         1, 1, 0, "气力回复 +30%、气力上限 +15%", "ki_build", ""),
    # white
    ("luck",              "运气",           "white",  "气力运势", "META","mult",     1.20, "ki_mult",           "passive",         9, 0, 0, "气力上限 +20%/级", "ki_build", "原版保留 id"),
    ("berserk_potion",    "狂暴药水",       "white",  "气力运势", "H3",  "add_pct",  0.50, "berserk_potion",    "on_pickup",       1, 0, 0, "拾取后攻速 +50%、暴击大幅提升、持续 5s", "ki_build", ""),
    ("ki_breath",         "气之息",         "white",  "气力运势", "META","add_pct",  0.10, "ki_regen_mult",     "passive",         9, 0, 0, "气力回复 +10%/级", "ki_build", ""),
]

ALL = basics + survive + bullet + combo + trail + pet + orb_charge + element + ki_meta

# ===================== Build the workbook =====================
wb = openpyxl.Workbook()
thin = Side(border_style="thin", color="C0C0C0")
border = Border(left=thin, right=thin, top=thin, bottom=thin)
header_fill = PatternFill(start_color="2E2E2E", end_color="2E2E2E", fill_type="solid")
header_font = Font(color="FFFFFF", bold=True, name="Microsoft YaHei")
body_font = Font(name="Microsoft YaHei", size=10)
center = Alignment(horizontal="center", vertical="center", wrap_text=True)
left_wrap = Alignment(horizontal="left", vertical="center", wrap_text=True)

# Sheet 1: Upgrades
ws1 = wb.active
ws1.title = "Upgrades"
headers = ["id","name_cn","rarity","group","dmg_layer","value_type","apply_value",
           "apply_type","trigger","max_level","once_per_run","once_per_chapter",
           "desc_cn","build_tag","notes"]
ws1.append(headers)
for col_idx, h in enumerate(headers, 1):
    c = ws1.cell(row=1, column=col_idx); c.fill = header_fill; c.font = header_font; c.alignment = center; c.border = border
for row in ALL:
    ws1.append(list(row))
for r in range(2, ws1.max_row + 1):
    rarity = ws1.cell(row=r, column=3).value
    fill = PatternFill(start_color=RARITY_FILL[rarity], end_color=RARITY_FILL[rarity], fill_type="solid")
    for col in range(1, len(headers) + 1):
        cell = ws1.cell(row=r, column=col)
        cell.fill = fill; cell.font = body_font; cell.border = border
        cell.alignment = left_wrap if col in (13, 15) else center
for i, w in enumerate([18, 14, 8, 12, 11, 11, 12, 22, 18, 10, 13, 16, 50, 14, 36], 1):
    ws1.column_dimensions[get_column_letter(i)].width = w
ws1.row_dimensions[1].height = 24
ws1.freeze_panes = "A2"
ws1.auto_filter.ref = ws1.dimensions

# Sheet 2: RarityWeights
ws2 = wb.create_sheet("RarityWeights")
rw_headers = ["rarity","name_cn","chance","color_hex","overlay","edge_glow","card_glow","shimmer","pulse","spark_count","rays","luck_roll_modifier"]
ws2.append(rw_headers)
rw_rows = [
    ("white",  "普通", 0.00, "#d8d8d8", 0.76, 0.00, 0.12, 0, 0, 0,  0, "无（保底/凑数）"),
    ("blue",   "稀有", 0.40, "#58a8ff", 0.80, 0.28, 0.32, 1, 0, 6,  0, "四叶草每级 -4%"),
    ("purple", "史诗", 0.40, "#b070ff", 0.84, 0.48, 0.50, 1, 1, 12, 0, "四叶草每级 +3%"),
    ("orange", "传奇", 0.20, "#ff9830", 0.88, 0.78, 0.85, 1, 1, 22, 1, "四叶草每级 +1%"),
]
for r in rw_rows: ws2.append(list(r))
for col in range(1, len(rw_headers)+1):
    c = ws2.cell(row=1, column=col); c.fill = header_fill; c.font = header_font; c.alignment = center; c.border = border
for r in range(2, 6):
    rar = ws2.cell(row=r, column=1).value
    fill = PatternFill(start_color=RARITY_FILL[rar], end_color=RARITY_FILL[rar], fill_type="solid")
    for col in range(1, len(rw_headers)+1):
        cc = ws2.cell(row=r, column=col); cc.fill = fill; cc.font = body_font; cc.alignment = center; cc.border = border
for i, w in enumerate([10, 8, 8, 12, 9, 11, 11, 9, 8, 13, 7, 24], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w
ws2.row_dimensions[1].height = 22

# Sheet 3: BaseAttributes
ws3 = wb.create_sheet("BaseAttributes")
ba_headers = ["key","value","description","dmg_layer","upgrades_that_modify"]
ws3.append(ba_headers)
ba_rows = [
    ("base_attack",           40,    "基础攻击力 (player.json)",       "H1 起点", "warrior_soul, atk_boost, giant_force, warrior_breath, demon_hunter, warrior_heart, wounded_warrior, desperate_rage, melee_strike, power_trio, adversity_heart, boss_killer, super_mushroom, orb_glow, orb_resonance_x"),
    ("base_hp",               100,   "基础生命",                       "SURVIVE 起点", "power_soul, life_spring, vitality_heart, angel_shelter, lucky_heart, power_blood, giant_force, super_mushroom"),
    ("base_ki",               234,   "基础气力上限",                   "META",       "luck, ki_overflow"),
    ("base_crit_rate",        0.08,  "暴击率",                         "H4",         "water_tornado, desperate_counter, stillness_heart, berserk_potion"),
    ("base_crit_damage",      1.60,  "暴击伤害倍率",                   "H4",         "stillness_heart"),
    ("attack_speed",          2850,  "路径冲刺速度 px/s",              "H1 攻速",    "godspeed, swift_soul, spirit_breath, swift_arrow, melee_strike, standstill_power"),
    ("basic_attack_speed",    2,     "普攻频率（次/秒）",              "H1 攻速",    "godspeed, swift_soul, swift_arrow, melee_strike, standstill_power"),
    ("move_speed",            120,   "摇杆移速 px/s",                  "META",       "wind_breath, swift_soul, wind_spirit, giant_force(-)"),
    ("hitbox_radius",         22,    "碰撞半径",                       "META",       "super_mushroom(+), giant_force(+)"),
    ("ki_regen_speed",        60,    "气力回复（点/秒）",              "META",       "godspeed(-), ki_overflow, ki_breath"),
    ("ki_per_pixel",          0.18,  "划线每像素消耗气力",             "META",       "（无）"),
    ("combo_damage_bonus",    0.01,  "每点连击伤害加成 (H3 主轴)",     "H3",         "combo_frenzy, multi_combo, combo_zoom"),
    ("auto_bullet_damage_mult", 0.5, "普攻子弹伤害倍率 (H2 基线)",     "H2",         "spirit_bomb, charge_arrow, energy_beam, energy_ring, swift_arrow(-)"),
    ("auto_bullet_speed",     420,   "普攻子弹速度",                   "H2",         "homing_eye(-)"),
    ("auto_bullet_life",      0.9,   "普攻子弹存活时间",               "H2",         "range_power, close_range_shot"),
    ("auto_bullet_pierce_range_mul", 0.85, "穿透子弹距离倍率",         "H2",         "pierce, pierce_arrow"),
    ("invincible_time",       0.45,  "受击无敌时间（s）",              "SURVIVE",    "angel_shelter, invincibility"),
    ("orb_spawn_chance_attack",0.55, "攻击球生成概率 (buff_orbs.json)","META",       "orb_rich_field, orb_starter, orb_overflow, orb_lucky"),
    ("orb_spawn_chance_ki",   0.45,  "气力球生成概率",                 "META",       "orb_rich_field, orb_starter, orb_overflow, orb_lucky, ki_orb_master"),
    ("orb_spawn_chance_combo",0.42,  "连击球生成概率",                 "META",       "orb_rich_field, orb_starter, orb_overflow, orb_lucky, combo_orb_master"),
    ("orb_spawn_chance_ice",  0.28,  "冰球生成概率",                   "META",       "orb_rich_field, orb_starter, orb_overflow, orb_lucky, ice_orb_master"),
    ("orb_attack_mult",       1.30,  "攻击球加成倍率 (turn_buff)",     "H1",         "attack_orb_master, orb_resonance_x"),
    ("orb_combo_mult",        2.00,  "连击球加成倍率 (turn_buff)",     "H3",         "combo_orb_master, orb_resonance_x"),
]
for r in ba_rows: ws3.append(list(r))
for col in range(1, len(ba_headers)+1):
    c = ws3.cell(row=1, column=col); c.fill = header_fill; c.font = header_font; c.alignment = center; c.border = border
for r in range(2, ws3.max_row + 1):
    for col in range(1, len(ba_headers)+1):
        cc = ws3.cell(row=r, column=col); cc.font = body_font; cc.alignment = left_wrap if col == 5 else center; cc.border = border
for i, w in enumerate([28, 10, 28, 14, 75], 1):
    ws3.column_dimensions[get_column_letter(i)].width = w
ws3.row_dimensions[1].height = 22
ws3.freeze_panes = "A2"

# Sheet 4: DamageFormula
ws4 = wb.create_sheet("DamageFormula")
df_headers = ["layer_code","layer_name","formula_segment","aggregation","project_fields","实现位置 (gd)","说明"]
ws4.append(df_headers)
df_rows = [
    ("(sum)", "最终单次输出",
        "总伤 = 英雄直伤 + A类元素 + B类元素 + 召唤/激光 + 强化球印记",
        "求和",
        "—",
        "combat_director.gd: resolve_damage()",
        "四个独立体系直接相加，不互相缩放"),
    ("H1",    "攻击乘区 (Π attack)",
        "面板ATK × Π(攻击倍率)",
        "独立乘算",
        "base_attack × attack_power_scale × turn_buff_attack_mult × bonus_attack_mult",
        "player.gd: _compute_attack_power()",
        "战士之魂/攻击力提升/巨人之力/野性号召 落在这里；攻击球 turn_buff 也走 H1"),
    ("H2",    "武器/弹道乘区",
        "× 武器倍率 × Π(弹道系数)",
        "独立乘算",
        "auto_bullet_damage_mult × slash_damage_mult × bullet_count_modifier × charge_strike",
        "player.gd: _compute_bullet_damage(), perform_slash()",
        "多弹道惩罚集中此区：多重子弹无衰减；前方箭 ×0.85；追踪 ×0.9；迅捷 ×0.8"),
    ("H3",    "条件加成 (Σ %)",
        "× (1 + Σ%)",
        "加法求和后乘",
        "combo_damage_bonus × combo + 对Boss/低血/连击/受伤/击杀 各 % 之和",
        "player.gd: _compute_conditional_bonus()",
        "Boss杀手/逆境/绝境/恶魔猎手/连击狂热/球之回响 落这里；连击球 turn_buff_combo_mult 也走 H3"),
    ("H4",    "暴击",
        "× 暴击倍率",
        "二选一",
        "base_crit_rate + bonus_crit_rate, base_crit_damage + bonus_crit_damage",
        "player.gd: roll_crit(), apply_crit()",
        "水龙卷/静止之心/狂暴药水 进入该区"),
    ("E_A",   "A类元素（基于ATK）",
        "(面板ATK × Π攻击乘区) × 元素系数 × (1 + Σ元素增伤%)",
        "独立乘算",
        "元素技能系数（轨迹/激光/陨光/绝寒）",
        "ability_manager.gd: spawn_trail_dot(), spawn_ice()",
        "免疫多弹道衰减 —— 画线轨迹全系、绝寒之裁、ice、orb_detonate 落这里"),
    ("E_B",   "B类元素（基于单次直伤）",
        "英雄单次直伤 × 元素系数",
        "随直伤线性",
        "bullet_burn 0.14×单次直伤；闪电/中毒类似",
        "monster.gd: apply_dot()",
        "受 H2 衰减影响 —— 烈焰/雷电/剧毒/子弹灼烧/焚天/惊雷/腐骨 落这里"),
    ("P",     "召唤 / 炸弹 / 激光 独立乘区",
        "(面板ATK × 召唤转化率) × Π召唤专属倍率 × 召唤暴击",
        "完全独立",
        "pet_atk_coef × spirit_frenzy(×1.5) × spirit_boost(×1.4) × bomb_master(×1.5)",
        "ability_manager.gd: pet_attack(), bomb_throw(), beam_fire()",
        "不吃 H2 弹道衰减；wild_call 反向影响 H1（堆攻速）"),
    ("SURVIVE","生存/护盾/回血",
        "—",
        "—",
        "bonus_damage_reduction, max_hp_mult, holy_shield_layers",
        "player.gd: take_damage(), regen()",
        "圣盾/不动如山/复活/生命之泉/逆境恢复 都在这里"),
    ("META",  "强化球 / 抽卡 / 工具",
        "—（改变其它乘区或抽卡权重）",
        "—",
        "buff_orbs.json: spawn_chance, ki_max, luck_roll",
        "upgrade_manager.gd, buff_orb_manager.gd",
        "影响奖励池权重、强化球生成、地图掉落，不直接打伤害"),
]
for r in df_rows: ws4.append(list(r))
for col in range(1, len(df_headers)+1):
    c = ws4.cell(row=1, column=col); c.fill = header_fill; c.font = header_font; c.alignment = center; c.border = border
for r in range(2, ws4.max_row + 1):
    for col in range(1, len(df_headers)+1):
        cc = ws4.cell(row=r, column=col); cc.font = body_font; cc.alignment = left_wrap; cc.border = border
for i, w in enumerate([9, 24, 42, 14, 50, 40, 50], 1):
    ws4.column_dimensions[get_column_letter(i)].width = w
ws4.row_dimensions[1].height = 22
ws4.freeze_panes = "A2"
for r in range(2, ws4.max_row + 1):
    ws4.row_dimensions[r].height = 62

# Sheet 5: Builds
ws5 = wb.create_sheet("Builds")
b_headers = ["build_tag", "中文名", "核心 (Carry, 橙)", "强化件 (紫)", "基础件 (蓝)", "白色入门", "与之协同", "与之冲突", "数值瓶颈"]
ws5.append(b_headers)
b_rows = [
    ("bullet_build",  "普攻流",
        "弹幕之王 / 元气弹 / 多重射击 / 能量光束 / 穿透",
        "斜向箭 / 镜像子弹 / 近距离射击 / 能量环 / 追踪之眼(-)",
        "蓄力箭 / 屹立不倒 / 光翼箭 / 弹射子弹 / 激光冲击 / 分裂箭 / 穿透箭 / 前方箭 / 迅捷箭",
        "多重子弹 / 后方箭 / 反弹箭 / 远程威力",
        "基础属性流（H1 共乘）、暴击流",
        "追踪之眼(H2 衰减)；迅捷箭(H2 衰减)；前方箭(H2 衰减)；近战打击(范围短)",
        "多弹道衰减叠乘后伤害掉档；需 E_A 或 P 兜底"),
    ("combo_build",   "连击/画线流",
        "豪火球术 / 多重连击 / 暴风连击",
        "水龙卷术 / 黑洞 / 刀阵旋风 / 蓄力击 / 深渊爆炸 / 连击狂热",
        "手里剑 / 闪电链 / 连击加成 / 连击护甲",
        "闭合追加 / 连击回复",
        "气力流（撑画线长度）、强化球流（连击球加成）、画线轨迹流",
        "近战打击(范围短)",
        "boss 单怪输出偏弱，需要稳定怪堆"),
    ("trail_build",   "画线轨迹流",
        "轨迹狂欢 / 灼热轨迹",
        "雷电力场 / 腐蚀雾径 / 霜径 / 轨迹共鸣",
        "轨迹延展 / 余烬轨迹 / 静电轨迹 / 黏滞轨迹",
        "轨迹火星 / 轨迹冲击 / 轨迹之息",
        "元素流（E_A 同区强化）、连击流（画线本身）",
        "高速移动型 build（轨迹覆盖不到）",
        "敌人远程不踩轨迹时收益骤降；与 super_ice/super_flame 共享 E_A 乘区"),
    ("pet_build",     "宠物/炸弹/激光流 (P 乘区)",
        "天雷 / 养育之心 / 精灵王 / 光子长矛 / 新星核弹",
        "天神 / 野性号召 / 嗜血 / 精灵狂潮 / 激光精灵 / 爆破大师 / 双联炸弹 / 元素炸弹 / 光束扫射",
        "野熊 / 炸弹精灵 / 精灵强化 / 齐射炸弹 / 速投炸弹 / 激光卫星",
        "狼战士 / 四色精灵 / 突袭炸弹 / 追击炸弹 / 反击炸弹",
        "基础属性（面板 ATK 撑高）、元素（炸弹继承元素）",
        "弹幕/迅捷箭等高频普攻流抢资源",
        "宠物 AI 命中率；面板 ATK 不撑高时 P 区收益线性下滑"),
    ("orb_build",     "强化球流 (META + H1 + H3)",
        "球潮溢涌 / 印记共鸣",
        "攻击球·精通 / 气力球·精通 / 连击球·精通 / 冰球·精通 / 球之印记",
        "丰沃球场 / 球磁场 / 球爆引 / 球延寿 / 球之回响",
        "球之入门 / 球之微光 / 球之幸运 / 守护环绕球",
        "连击流 (连击球加成)、画线流 (沿途吃球)、元素流 (球爆引带元素)",
        "高速移动型 build （来不及吃球）",
        "依赖场上球生成；冷场关卡（boss 房）收益差"),
    ("element_build", "元素流 (E_A / E_B)",
        "—（橙位由轨迹狂欢 / 绝寒之裁客串）",
        "焚天烈焰 / 惊雷裁决 / 腐骨之噬 / 绝寒之裁",
        "烈焰 / 雷电 / 剧毒 / 冰冻 / 子弹灼烧",
        "—（白色由 trail_spark 等客串）",
        "画线轨迹流 (E_A 共区)、宠物流 (元素炸弹继承)、强化球流 (球爆引)",
        "普攻流单一武器无元素时收益骤降",
        "B 类吃 H2 衰减；A 类不受影响但触发频率受限"),
    ("survive_build", "生存流",
        "神圣守护 / 力量之魂 / 超级蘑菇 / 静止之心",
        "复活 / 减速领域 / 逆境之心",
        "圣盾 / 不动如山 / 绝境反击 / 幸运创可贴 / 幸运饼干 / 幸运之心 / 生命之泉 / 活力之心 / 天使庇护",
        "力量之血 / 恢复生命 / 绝境恢复 / 恶魔恢复",
        "连击流(滚雪球需活)、宠物流(分担伤害)",
        "—",
        "无主动输出；必须搭一条进攻 build"),
    ("ki_build",      "气力 / 运势",
        "—（无碰运气 carry）",
        "幸运学",
        "四叶草 / 无敌药水 / 药水充沛 / 气力涌泉",
        "运气 / 狂暴药水 / 气之息",
        "强化球流（药水即球）、画线流（气力撑长度）",
        "—",
        "纯辅助；放大其它流派而非独立 carry"),
    ("generic",       "基础属性流",
        "战士之魂 / 力量三重奏 / 多重连击",
        "攻击力提升 / 巨人之力 / 迅捷之魂",
        "神速 / 近战打击 / 绝境狂热 / 风之精灵 / 恶魔猎手 / 战士之心",
        "战士之息 / 精灵之息 / 风之息 / 力量之血 / 负伤战士 / Boss 杀手",
        "通吃所有流派（H1 全局乘）",
        "—",
        "纯堆 H1 易遇稀释；后期需找 H2/H3/E/P 任一作为乘区主轴"),
]
for r in b_rows: ws5.append(list(r))
for col in range(1, len(b_headers)+1):
    c = ws5.cell(row=1, column=col); c.fill = header_fill; c.font = header_font; c.alignment = center; c.border = border
for r in range(2, ws5.max_row + 1):
    for col in range(1, len(b_headers)+1):
        cc = ws5.cell(row=r, column=col); cc.font = body_font; cc.alignment = left_wrap; cc.border = border
for i, w in enumerate([14, 22, 38, 50, 60, 40, 36, 32, 38], 1):
    ws5.column_dimensions[get_column_letter(i)].width = w
ws5.row_dimensions[1].height = 22
for r in range(2, ws5.max_row + 1):
    ws5.row_dimensions[r].height = 110
ws5.freeze_panes = "A2"

wb.save(OUT)
print(f"OK -> {OUT}")
print(f"Total upgrades = {len(ALL)}")
from collections import Counter
print("by rarity:", dict(Counter(r[2] for r in ALL)))
print("by group :", dict(Counter(r[3] for r in ALL)))
