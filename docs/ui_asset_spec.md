# UI 素材规范 v1.2

> 给策划 / 美术看的 Photoshop 出图工作流。**每张图的完整放置路径都写在表格里**，照着 PS 出图，按路径丢文件，程序端接入。

**v1.2 改动**（2026-07-07）

- 第 3 批 upgrades 交付：117 张升级卡 icon（`skill_01~117.png`）+ FRAME 边框（`deco_frame_32.png`）已接入 upgrade_popup / themed_reward_popup
- 装备 icon 迁移 PNG：8 张 `equip_01~08.png` 替换旧 SVG，走同一「品质色底层 + icon 顶层」结构
- **主题关专属 12 张放弃出图**：策划决定复用升级卡池 icon（demon_scythe → skill_03 等），themed/ 目录空置
- 新增 `panel_card_9s.png`（升级卡片背景 9-slice）+ `award_text_decoration.png`（奖励标题装饰）
- 第 4 批未启动 — 详见 § 11 现状 + § 12 下一步 ROI

**v1.1 改动**（2026-06-29）

- 每张素材的清单表加 **"放置路径"** 列，写明完整 `assets/ui/...` 路径，不再让你猜目录
- 第一批用户已交付 5 张图，整理后情况见 § 11 现状
- 新增 `assets/ui/icons/system/` 子目录用于系统操作图标（暂停 / 关闭 / 设置 / 返回），与 `status/` 区分（status 后续做 buff/debuff）
- HUD 顶栏 `panel_topbar_9s.png` **取消**（用户决定不要背景条，HUD 顶部用透明 + 文字漂浮）
- 把"bar_ 类前缀放 `panels/`"明确写进规范（之前没说，导致用户合理猜测但需要确认）

---

## § 1. 总览

| 项目 | 取值 |
| --- | --- |
| 基准画布 | **720 × 1280**（竖屏） |
| 倍图体系 | 本期只出 **@1x**（设计稿原尺寸）。@2x、@3x 后续视高分屏需求再补 |
| 视觉风格 | **高清现代 UI** — 圆角 4-8px、柔和阴影、抗锯齿全开 |
| 颜色策略 | **白色 / 灰度模板出图 → 运行时代码 `modulate` 染色**。一张图复用 N 套配色 |
| 文件格式 | PNG-24，透明背景 |
| 色彩模式 | RGB，8 位/通道 |
| DPI | 72 |

---

## § 2. 目录结构

```
assets/ui/
├── panels/              ← 9-slice 面板背景（tooltip / 弹窗 / HUD 底纹 / 血条边框 / 血条填充）
├── buttons/             ← 9-slice 按钮模板
├── icons/               ← UI 图标（注意：根目录是 assets/ui/icons/，不是 assets/icons/）
│   ├── equipment/       ← 装备图标
│   ├── currency/        ← 货币（金币、宝石、矿石）
│   ├── upgrades/        ← 升级卡奖励图标
│   ├── themed/          ← 主题关专属（恶魔 6 + 天使 6）
│   ├── system/          ← 系统操作（暂停、关闭、设置、返回、菜单）
│   └── status/          ← buff / debuff 状态图标（本期预留，先不出图）
├── decorations/         ← 不拉伸的装饰元素（花纹、勋章、星星）
├── backgrounds/         ← 全屏背景图（720×1280 起跳）
└── Fonts/               ← 现有字体，保持原样
```

**目录归属判断**（避免再放错）：

| 文件前缀 | 必须放在 | 例 |
| --- | --- | --- |
| `panel_` | `assets/ui/panels/` | `panel_dialog_9s.png` |
| `btn_` | `assets/ui/buttons/` | `btn_primary_9s.png` |
| `bar_` | `assets/ui/panels/` ⚠️ 不是 `bars/` | `bar_frame_9s.png` |
| `icon_eq_*` | `assets/ui/icons/equipment/` | `icon_eq_sword.png` |
| `icon_cur_*` | `assets/ui/icons/currency/` | `icon_cur_gold.png` |
| `icon_up_*` | `assets/ui/icons/upgrades/` | `icon_up_godspeed.png` |
| `icon_th_*` | `assets/ui/icons/themed/` | `icon_th_demon_baby.png` |
| `icon_nav_*`（底部选项卡） | `assets/ui/icons/nav/` | `icon_nav_gacha.png` |
| 系统图标（无类别前缀，只有 `icon_pause` / `icon_close` / `icon_settings` / `icon_back` / `icon_menu` / `icon_power` / `icon_attack` / `icon_hp` / `icon_detail`） | `assets/ui/icons/system/` | `icon_pause.png` |
| `deco_` | `assets/ui/decorations/` | `deco_star_gold.png` |
| `bg_` | `assets/ui/backgrounds/` | `bg_main_menu.png` |

**现有 `battle/`、`bottom/`、`equipment/`、`equipment_synthesis/` 目录暂时保留**，旧图后续由我做迁移替换。

---

## § 3. 命名规范

### 强制规则

1. **全小写 + snake_case**
2. **禁止**空格、括号、中文、UUID
3. **必须有前缀**（见 § 2 目录归属判断表）
4. **9-slice 标识**：能被拉伸的图，文件名末尾加 `_9s`

### 状态后缀

**优先用 modulate 染色实现状态**。只有图形本身有变化（不是颜色变化）才出多张：

| 后缀 | 何时用 |
| --- | --- |
| `_normal` | 默认态（一般可省略） |
| `_hover` | 鼠标悬停 — 通常用 modulate 实现，不出图 |
| `_pressed` | 按下 — 通常用 modulate 实现，不出图 |
| `_disabled` | 不可点击 — 通常用 modulate 实现，不出图 |

---

## § 4. 五类素材清单（核心交付物）

> ⚠️ 表格里"完整路径"列就是 PNG 应该放的位置 — 复制路径丢文件即可。

### 4.1 提示板（tooltip）

3 档统一风格的 tooltip 背景：

| 档位 | 用途 | 设计尺寸 | 9-slice 切片 | 完整路径 |
| --- | --- | --- | --- | --- |
| **mini** | hover 1-2 行短提示 | 80 × 32 | 8/8/8/8 | `assets/ui/panels/panel_tooltip_mini_9s.png` |
| **标准** | 升级卡 hover / 装备简介 | 200 × 100 | 12/12/12/12 | `assets/ui/panels/panel_tooltip_std_9s.png` ✅ 已交付 |
| **详情** | 装备详情 / 技能完整说明 | 320 × 200 | 16/16/16/16 | `assets/ui/panels/panel_tooltip_detail_9s.png` |

**附**（可选）：

| 文件 | 尺寸 | 完整路径 |
| --- | --- | --- |
| 小尾巴箭头 | 16 × 8 | `assets/ui/panels/panel_tooltip_arrow.png` |

### 4.2 弹窗面板

升级 3 选 1 / 主题关 / 转盘 / 通用对话框**共用 1 张** 9-slice：

| 文件 | 设计尺寸 | 9-slice 切片 | 完整路径 |
| --- | --- | --- | --- |
| 通用弹窗背景 | 240 × 160 | 24/24/24/24 | `assets/ui/panels/panel_dialog_9s.png` ✅ 已交付 |
| 弹窗标题栏（可选） | 240 × 40 | 24/24/0/24 | `assets/ui/panels/panel_dialog_header_9s.png` |

主题色（红 / 金 / 蓝）靠运行时 `modulate` 染色，**不出多张**。

### 4.3 按钮

| 类别 | 形状 | 设计尺寸 | 9-slice 切片 | 完整路径 |
| --- | --- | --- | --- | --- |
| 主按钮 | 圆角矩形 | 160 × 48 | 16/16/16/16 | `assets/ui/buttons/btn_primary_9s.png` ✅ 已交付 |
| 次按钮 | 圆角矩形（细边） | 160 × 48 | 16/16/16/16 | `assets/ui/buttons/btn_secondary_9s.png` |
| 圆按钮 | 圆形 | 48 × 48 | — 固定尺寸 | `assets/ui/buttons/btn_round.png` |
| 标签按钮 | 上半圆角 | 104 × 143 | 24/24/0/24 | `assets/ui/buttons/btn_tab_9s.png` |

**每张图只出白色版本** —— 状态变化（normal/hover/pressed/disabled）+ 颜色主题（金/红/黄/蓝/绿）全靠代码 modulate。详见 § 6。

### 4.4 图标（统一 64 × 64 设计像素）

| 类别 | 数量 | 文件名样例 | 完整路径目录 |
| --- | --- | --- | --- |
| 装备 | 8 张覆盖 8 def_id | `equip_01.png` ~ `equip_08.png`（16×16 手绘像素、xlsx D 列 slug 映射） | `assets/ui/icons/equipment/` ✅ 已交付 |
| 货币 | 2 | `icon_cur_gold.png` / `icon_cur_gem.png` | `assets/ui/icons/currency/` ✅ 已交付（策划确认只有金币 + 宝石，不做矿石）|
| 升级卡 | 117 | `skill_01.png` ~ `skill_117.png`（xlsx E 列 skill_XX 映射） | `assets/ui/icons/upgrades/` ✅ 已交付 |
| 主题关 | — 已放弃 | 复用升级卡池 icon（demon_scythe → skill_03 等） | `assets/ui/icons/themed/`（占位空目录） |
| 系统操作 | 4-6 | `icon_pause.png` / `icon_close.png` / `icon_settings.png` / `icon_back.png` / `icon_menu.png` | `assets/ui/icons/system/` ✅ 已交付 4 张 |
| 属性 stat | 4 | `icon_power.png` / `icon_attack.png` / `icon_hp.png` / `icon_detail.png` | `assets/ui/icons/system/` ✅ 已交付（走 system 目录，不新开 stat 子目录） |
| 导航 nav | 5 | `icon_nav_gacha.png` / `icon_nav_equipment.png` / `icon_nav_battle.png` / `icon_nav_dungeon.png` / `icon_nav_achievement.png` | `assets/ui/icons/nav/` ✅ 已交付 5 张（底部选项卡） |
| 状态 | — 本期不出 | — | `assets/ui/icons/status/`（占位） |

**升级卡 / 装备 icon 数据流**：xlsx 单元格填 slug（`skill_XX` / `equip_XX`）→ export 脚本写 json → `UiStyleHelper.build_reward_icon_with_frame` / `LobbyState.get_item_icon_path` 加载 PNG + 品质色底层 + FRAME 边框。详见 memory `project_ui_standardization` 「数据流」段。

**风格**：全部背景透明、主体居中、四周留 4px 安全边、抗锯齿全开、不写文字。

### 4.5 HUD / 血条 / 系统装饰

⚠️ **顶栏背景条已取消**（用户决定 HUD 顶部用透明 + 文字漂浮，不要 panel_topbar）。

| 类别 | 文件 | 尺寸 | 9-slice 切片 | 完整路径 |
| --- | --- | --- | --- | --- |
| 血条边框 | `bar_frame_9s.png` | 200 × 24 | 8/8/8/8 | `assets/ui/panels/bar_frame_9s.png` ✅ 已交付 |
| 血条填充 | `bar_fill_9s.png` | 200 × 16 | 8/8/8/8 | `assets/ui/panels/bar_fill_9s.png` ✅ 已交付 |
| 暂停 | `icon_pause.png` | 32 × 32 | — | `assets/ui/icons/system/icon_pause.png` ✅ 已交付 |
| 设置 | `icon_settings.png` | 32 × 32 | — | `assets/ui/icons/system/icon_settings.png` ✅ 已交付 |
| 关闭 | `icon_close.png` | 32 × 32 | — | `assets/ui/icons/system/icon_close.png` ✅ 已交付 |
| 返回 | `icon_back.png` | 32 × 32 | — | `assets/ui/icons/system/icon_back.png` ✅ 已交付 |

**血条只出 1 张白色 fill**，hp / mp / exp 全部代码 modulate 上色（红 / 蓝 / 绿）。

---

## § 5. Photoshop 出图技术规范

### 5.1 新建文档

- 文件 → 新建
- 宽度 / 高度：照清单上的"设计尺寸"填（如按钮 160 × 48）
- 分辨率：**72 像素/英寸**
- 颜色模式：**RGB 颜色，8 位**
- 背景内容：**透明**（重要！不要选白色）

### 5.2 导出

- 文件 → 导出 → 导出为 PNG
- **PNG-24**（不要选 PNG-8）
- ✓ 透明度
- 文件大小：100%（不缩放）
- 颜色空间：转换为 sRGB

### 5.3 9-slice 切片线标注

> 9-slice：4 个角不拉伸（保持锐利），上下边水平拉伸，左右边垂直拉伸，中心区域 2 维拉伸。

1. 打开 PSD，`Ctrl+R` 显示标尺
2. 从顶/左标尺拖出 4 条参考线，分别在距离上/右/下/左边缘 [切片值] 像素处
3. 检查所有圆角、描边、装饰图案都在 4 个角的安全区里
4. 导出 PNG（参考线不会烘进图片）
5. 把切片数值告诉我（或我按本文档默认值配），我会写到 `.import` 文件的 `patch_margin_*`

**举例**：`btn_primary_9s.png` 160×48，切片 16/16/16/16

```
+----+----------------+----+
| TL |   T (拉伸)     | TR |    ← 上 16px
+----+----------------+----+
| L  |   C (双向拉伸) | R  |    ← 中间 16px
+----+----------------+----+
| BL |   B (拉伸)     | BR |    ← 下 16px
+----+----------------+----+
 16px        128px      16px
```

### 5.4 6 条硬规则

1. **不要把背景图层锁定**（图层面板里双击解锁），否则导出会带白底
2. **不要用图层样式的"投影 / 内阴影"撑出画布边界** — 9-slice 拉伸会拉花阴影，所有效果必须在切片线内完成
3. **抗锯齿全开** — 文字"平滑"、形状"对齐到像素网格 + 消除锯齿"
4. **不要在 9-slice 图里写中央文字** — 中央会被拉伸糊掉，文字在 Godot 端用 Label 叠
5. **导出文件名严格按 § 2 + § 4** —— 路径错了 / 文件名错了会导致接入失败
6. **白底测试 + 黑底测试** — 导出后分别放白底、黑底上看，确认无白边 / 黑边

### 5.5 给代码染色用的图，怎么画

- 主色画**纯白**（`#FFFFFF`）
- 阴影 / 暗部画**纯黑半透**（`#000000` + alpha）
- 高光画**纯白**或**纯黑**
- **不要带任何颜色** —— 颜色全靠 modulate 加

---

## § 6. 颜色染色 vs 多张贴图判断

**优先用 modulate 染色，不要为颜色变化出多张图。**

| 场景 | 出几张 |
| --- | --- |
| 同一按钮 5 种主题色 | 1 张白色 9-slice |
| 同一血条红/蓝/绿 | 1 张白色 fill |
| 圆按钮 vs 矩形按钮 | 必须 2 张（形状不同） |
| 装备 sword vs shield | 必须 2 张（内容不同） |
| 主题关恶魔 vs 天使配色 | 1 张 `panel_dialog_9s` |
| 按钮 normal/hover/pressed/disabled | 1 张 |

**一句话判断**：「除了颜色和亮度，**还有别的不同**吗？」无 → 1 张 + modulate；有 → 出多张。

按钮状态染色（代码端，参考）：

```gdscript
normal:   Color(1.0, 1.0, 1.0, 1.0)
hover:    Color(1.2, 1.2, 1.2, 1.0)    # 提亮 20%
pressed:  Color(0.7, 0.7, 0.7, 1.0)    # 压暗 30%
disabled: Color(0.5, 0.5, 0.5, 0.6)    # 灰化 + 半透

# 主题色（5 套）
gold:   Color(1.00, 0.78, 0.30, 1.0)   # 金 — 开始按钮
red:    Color(0.92, 0.18, 0.15, 1.0)   # 红 — 恶魔主题
yellow: Color(0.98, 0.85, 0.30, 1.0)   # 黄 — 天使主题
blue:   Color(0.30, 0.60, 1.00, 1.0)   # 蓝 — 默认
green:  Color(0.30, 0.85, 0.40, 1.0)   # 绿 — 确认
```

---

## § 7. Godot 端配置（仅参考，我接入）

| 项目 | 设置 | 原因 |
| --- | --- | --- |
| 新 UI PNG 的 `.import` filter | `true`（LINEAR） | 高清现代风需要平滑缩放 |
| 现有像素 icon（`assets/icons/upgrades/`） | 临时 `false`（NEAREST） | 旧像素图兜底 |
| `process/fix_alpha_border` | `true`（默认） | 防 alpha 边白线 |
| `mipmaps/generate` | **`true`（缩放显示的 icon 必须开）** | 128×128 源 → 40×40 显示 = 30% 缩放，无 mipmap 时 LINEAR 会锯齿。已开的：`icons/system/icon_{power,attack,hp,detail}` + `icons/nav/icon_nav_*` |
| `NinePatchRect.patch_margin_*` | 按 § 4 切片数值 | 9-slice 配置 |

**mipmap 判断准则**：图片显示尺寸 < 源尺寸 50% → 必须开 mipmap。9-slice 面板 / bar 拉伸时不需要（永远接近或大于源尺寸）；固定尺寸的 icon（stat / nav / equipment / themed）都需要开。

---

## § 8. 你的工作流

1. PS 里按 § 5 出图
2. 文件名严格按 § 2 + § 4 起名
3. **复制 § 4 表格里的"完整路径"，把 PNG 丢到对应目录**
4. 跑自查清单：

   - [ ] 文件名全小写 + snake_case + 正确前缀
   - [ ] 9-slice 图带 `_9s` 后缀
   - [ ] 透明背景（不是白底）
   - [ ] 抗锯齿开启
   - [ ] 圆角 / 阴影都在 9-slice 切片内
   - [ ] 染色用的图是纯白 / 灰阶（无杂色）
   - [ ] **放在正确的目录**（对照 § 2 目录归属判断表）

5. 给我 ping：「这批 X 张图做完了，在 `assets/ui/xxx/` 下」
6. 我接入到 `.tscn` / `.gd` + 配 `.import`，启动 Godot 验证

---

## § 9. 分批优先级（每张图都带完整路径）

### 第 1 批 — 验证全链路（3 张）✅ 已交付

1. `assets/ui/panels/panel_dialog_9s.png` 240×160 — 升级 / 主题关弹窗背景
2. `assets/ui/buttons/btn_primary_9s.png` 160×48 — 接受 / 开始按钮
3. `assets/ui/panels/panel_tooltip_std_9s.png` 200×100 — 标准 tooltip

### 第 2 批 — HUD 系统 ✅ 已交付（顶栏取消）

4. `assets/ui/panels/bar_frame_9s.png` 200×24 — 血条 / 经验条边框
5. `assets/ui/panels/bar_fill_9s.png` 200×16 — 通用填充（红 / 蓝 / 绿代码染）
6. `assets/ui/icons/system/icon_pause.png` 32×32
7. `assets/ui/icons/system/icon_settings.png` 32×32
8. `assets/ui/icons/system/icon_close.png` 32×32
9. `assets/ui/icons/system/icon_back.png` 32×32
10. ~~`panel_topbar_9s.png`~~ — **取消**，HUD 顶部用透明 + 文字漂浮

### 第 3 批 — 图标库批量补全 ✅ 已交付主要部分

11. `assets/ui/icons/equipment/equip_01~08.png` — 8 张手绘像素装备 icon（每个 def_id 一张，4 品质共享）✅
12. `assets/ui/icons/upgrades/skill_01~117.png` — 117 张升级卡 icon ✅
13. `assets/ui/decorations/deco_frame_32.png` — 升级卡 / 主题关 icon FRAME 边框 ✅
14. `assets/ui/panels/panel_card_9s.png` — 卡片 9-slice 背景 ✅
15. `assets/ui/decorations/award_text_decoration.png` — 奖励标题装饰 ✅
16. ~~主题关专属 12 张~~ — **策划放弃**，复用升级卡池 icon

### 第 4 批 — 剩余 polish（下一步）

17. ~~货币图标 3 张~~ → **✅ 已交付 2 张**：`icon_cur_gold.png` / `icon_cur_gem.png`（策划确认不做矿石）
18. **次按钮 / 圆按钮 / 标签按钮** — `assets/ui/buttons/btn_secondary_9s.png` / `btn_round.png` / `btn_tab_9s.png`（当前所有次要按钮走"低饱和灰"的主按钮，层级不够）
19. **其余 tooltip 档** — `panel_tooltip_mini_9s.png` + `panel_tooltip_detail_9s.png`（现有 std 档已够用，非急）
20. **全屏背景 —— 只补缺失的场景，主菜单已完成**：详见 § 12 说明；主菜单 `bg_main.png` 用户认可保留，只补 `bg_battle_result.png`（战斗结算） / `bg_pause.png`（暂停覆盖）等未交付场景
21. **装饰元素** — `deco_star_gold.png` / `deco_ribbon.png` 等，配合奖励 / 结算界面

---

## § 10. 常见坑提醒

| 坑 | 后果 | 怎么避 |
| --- | --- | --- |
| PS 文件分辨率 300 | 出图变 4 倍大、内存爆炸 | 新建文档时改 72 |
| 背景图层未解锁 | 导出带白底 | 双击图层 → 确定 |
| 圆角矩形画在画布边缘 | 9-slice 拉伸时圆角被拉花 | 圆角必须在 4 个角切片安全区内 |
| 用"颜色叠加"图层样式 | 导出后改不了颜色 | 直接画纯白，颜色靠代码 |
| 文件名带空格 / 中文 / 大写 | Godot 在某些平台读不到 | 全小写 + snake_case |
| PNG 导出选 PNG-8 | 透明度只有 1bit、边缘锯齿 | 用 PNG-24 |
| **放错目录** | 程序端找不到 → 不会显示 | 对照 § 4 "完整路径"列 |

---

## § 11. 当前进度

**已交付（截至 v1.2）**：

```
assets/ui/
├── panels/
│   ├── panel_dialog_9s.png         ✅
│   ├── panel_tooltip_std_9s.png    ✅
│   ├── panel_card_9s.png           ✅ (卡片背景)
│   ├── bar_frame_9s.png            ✅
│   └── bar_fill_9s.png             ✅
├── buttons/
│   └── btn_primary_9s.png          ✅
├── decorations/
│   ├── deco_frame_32.png           ✅ (升级卡 / 主题关 icon 边框，62.5% opaque)
│   └── award_text_decoration.png   ✅ (奖励标题装饰)
└── icons/
    ├── nav/                        ✅ 底部选项卡（5 张，均带 mipmap 抗锯齿）
    │   ├── icon_nav_gacha.png      ✅
    │   ├── icon_nav_equipment.png  ✅
    │   ├── icon_nav_battle.png     ✅
    │   ├── icon_nav_dungeon.png    ✅
    │   └── icon_nav_achievement.png ✅
    ├── system/                     ✅ 系统操作 + 装备属性
    │   ├── icon_pause.png              ✅
    │   ├── icon_settings.png           ✅
    │   ├── icon_close.png              ✅
    │   ├── icon_back.png               ✅
    │   ├── icon_power.png              ✅ (装备页战力，带 mipmap)
    │   ├── icon_attack.png             ✅ (装备页攻击，带 mipmap)
    │   ├── icon_hp.png                 ✅ (装备页生命，带 mipmap)
    │   └── icon_detail.png             ✅ (装备页详情按钮，带 mipmap)
    ├── upgrades/                   ✅ 117 张手绘升级卡 icon
    │   └── skill_01.png ~ skill_117.png
    └── equipment/                  ✅ 8 张手绘装备 icon（4 品质共享）
        └── equip_01.png ~ equip_08.png
```

**接入层已就绪**：
- `scripts/utils/ui_style_helper.gd` — `make_dialog_stylebox` / `apply_primary_button` / `build_reward_icon_with_frame` / `try_load_upgrade_icon` / `apply_linear_filter_tree`
- 已接入 popup：upgrade_popup、themed_reward_popup、pause_menu、reward_wheel_popup、scout_reward_popup、equipment_panel、synthesis_panel、talent_cards_panel、main_menu（scout btn / bottom nav）、forge_settlement_popup

---

## § 12. 下一步 ROI 排序

**关于"全屏背景"的澄清（v1.2 修订）**：这一项不是"重画主菜单背景"。主菜单 `res://assets/ui/battle/bg_main.png` 用户已认可保留 —— 它只是在 `assets/ui/battle/` 而不是 `assets/ui/backgrounds/`，是**遗留路径**问题，不影响视觉。真正缺背景的是这些界面：

| 场景 | 当前状态 | 建议背景 |
| --- | --- | --- |
| 主菜单 | ✅ 已有 `assets/ui/battle/bg_main.png`（保留） | — |
| 战斗关卡 | ✅ 用 `terrain_background.gd` 程序化生成地形 | — |
| **战斗结算 / 死亡** | ❌ 目前用半透明 ColorRect 遮罩 | `bg_battle_result.png` 720×1280，可带光晕 / 荣耀感 |
| **暂停覆盖** | ❌ 目前用半透明黑色遮罩 | `bg_pause.png` 720×1280，可带模糊质感 |
| **抽卡 / 转盘** | ❌ 目前用九宫格 panel | `bg_gacha.png` 720×1280，可带神秘/星光 |
| **升级 3 选 1 弹窗** | 已有主题氛围（rays + spark），无独立背景 | 可选，非急 |

如果只做 1 张背景 → 建议 `bg_battle_result.png`（玩家每关都看到，冲击频次最高）。

---

| 优先级 | 交付物 | 张数 | 影响面 | 工作量 |
| --- | --- | --- | --- | --- |
| ~~**P0**~~ | ~~货币图标（gold / gem）~~ | ~~2 张 64×64~~ | ~~主菜单顶栏 / 转盘 / 装备强化~~ | ~~✅ 已交付~~ |
| **P1** | 次按钮 + 圆按钮 + tab 按钮 3 张 9-slice | 3 张 | 装备详情"卸下"、pause_menu"debug"、语言切换 tab 层级区分 | 中 |
| **P2** | 战斗结算背景 `bg_battle_result.png` | 1 张 720×1280 | 每关必见 | 中（1 张背景）|
| **P3** | 暂停背景 + 抽卡背景 | 2 张 720×1280 | 玩家经常看到 | 中大 |
| **P4** | tooltip 其他档（mini / detail） | 2 张 9-slice | 装备详情弹窗可以更贴合 | 中 |
| **P5** | status/ buff-debuff icons | ~10 张 32×32 | 战斗内燃烧 / 冰冻 / 中毒等状态图标化 | 中 |

**建议路径**：P2 → P1 → P3 → P4 → P5。
- P2 立刻做（战斗结算是玩家每关必见）
- P1 层级区分做完后 UI 呼吸感强一大截
- P3 / P4 / P5 属于打磨阶段

---

**版本**：v1.2（2026-07-07）
**约定基准**：720×1280 竖屏 / 高清现代风 / 9-slice 单图 / 3 档 tooltip / 系统图标走 `icons/system/`
