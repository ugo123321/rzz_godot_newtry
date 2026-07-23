# 左上角货币 HUD + 宝箱飞行拾取效果 — 设计

日期: 2026-07-23
分支: server-version

## 目标

1. 删除局内左上角的金币 widget。
2. 银币 / 钥匙 icon 常驻左上角，**横向**排列，初始计数 0。
3. 银币 icon 用 `assets/ui/icons/currency/icon_cur_silver.png`；钥匙 icon 用 `assets/ui/icons/system/icon_key.png`。icon 尺寸统一缩放到约 18-20px 贴合行高（.png 原始尺寸可能偏大）。
4. 开宝箱时：对应 icon 发着光掉到地上 → 短暂停留 → 变成蓝色粒子特效飞向左上角对应 icon 位置 → 到达后计数改变。复刻现有经验（SoulOrb）效果，粒子颜色为蓝色。
5. 移除居中 `ChestResultPopup`（+N 弹窗）。

## 现状（探索结论）

- HUD 单个 `Control` 全程 `_draw()` 绘制：`scripts/ui/hud.gd`，battle 场景内联节点 `$UI/HUD`（`scripts/battle.gd:59`）。
- 左上角三个 widget 纵向堆叠：金币 y=10（用 `icon_cur_gold.png`）、钥匙 y=34（程序化像素画，仅 keys>0）、银币 y=58（程序化，仅 silver>0）。
- `player.gd`：`keys`/`silver` 字段（line 43-46），`add_key/add_silver/spend_key/has_key/get_keys/get_silver`（686-718），reset 于 1709-1710。变更发 `EventBus.key_changed`/`silver_changed`。
- 宝箱 `chest_normal.gd`/`chest_locked.gd`：proximity 触发（38px），`_open()` 直接调 `player.add_key(1)` 或 `player.add_silver(1+randi()%3)` + `_show_popup(...)`，然后换 `chest_open.png` 贴图 0.2s 后 `queue_free`。无物理掉落物。
- 经验效果 = `scripts/effects/soul_orb.gd` + `soul_orb_manager.gd`：spawn 抛起(0.15s) → idle 浮动(0.25s) → fly tween 飞向 exp bar(0.45s) → impact 爆粒子(0.10s) → 到达才 `add_exp`。绿色调色板。目标位置由 `_calc_target_world_pos`（107-118）用 `get_viewport().get_canvas_transform().affine_inverse()` 反算屏幕中心到世界坐标。

## 架构

### 1. 通用飞行拾取系统（新，数据驱动）

#### `scripts/effects/pickup_orb.gd`（class `PickupOrb`）

复刻 `soul_orb.gd` 四阶段，常量与时长一致：

| 阶段 | 时长 | 行为 |
|---|---|---|
| SPAWN | 0.15s | 抛起 + 落回（sin 曲线，SPAWN_RISE=8px）。本体 = icon 贴图 + 蓝色外发光。 |
| IDLE | 0.25s | 上下 ±2px 浮动 + 脉冲缩放（"短暂停留"）。 |
| FLY | 0.45s | `create_tween` TRANS_CUBIC EASE_IN 飞向目标；留蓝色拖尾。 |
| IMPACT | 0.10s | 蓝色粒子径向爆裂（12 粒，40-110 速，阻尼 0.88）→ `queue_free`，回调 `on_arrive(kind, amount)`。 |

接口：
```
setup(world_pos: Vector2, kind: String, amount: int, on_arrive: Callable)
```
- `kind` 决定 icon 贴图（从 manager 注册表取）。
- `amount` 默认 1（逐个掉模式每次都 1，但保留 amount 字段以备未来单 orb 带 N 的扩展）。
- 目标位置：`_calc_target_world_pos()` 调 `battle.hud.get_pickup_icon_world_pos(kind)`（HUD 公共方法）。
- `z_index = 5`，与 soul_orb 一致。

调色板（蓝色）：
- glow 外圈 `Color(0.30, 0.60, 1.00, 0.22)`
- glow 内圈 `Color(0.50, 0.80, 1.00, 0.42)`
- 拖尾 `Color(0.40, 0.70, 1.00, 0.45)`
- 命中粒子 `#7ab8ff`

本体绘制：icon 贴图缩放到约 18px 绘制（保持像素 sharp，`texture_filter = NEAREST` 若该贴图是像素风），外加两层同心蓝色 glow 圆。拖尾/爆裂与 soul_orb 同结构，换蓝色。

#### `scripts/effects/pickup_orb_manager.gd`（class `PickupOrbManager`）

```
var battle  # 持有 hud / player 引用
var _registry: Dictionary  # kind -> { icon: Texture2D, credit: Callable }

func setup(battle) -> void
func spawn_burst(world_pos: Vector2, kind: String, count: int) -> void
```

- `spawn_burst`：循环 `count` 次，每次 `PickupOrb.new()` → `add_child` → `setup(pos + 小随机偏移, kind, 1, _on_arrive)`，相邻 orb 起飞延迟 ~60-100ms 错开（"逐个掉"）。
- `_on_arrive(kind, amount)`：查注册表 `credit` 回调执行（key → `player.add_key(amount)`，silver → `player.add_silver(amount)`）。
- 注册表（当前两条，未来扩展只加一行）：
  - `key` → icon `res://assets/ui/icons/system/icon_key.png`，credit = `func(): battle.player.add_key(amount)`
  - `silver` → icon `res://assets/ui/icons/currency/icon_cur_silver.png`，credit = `func(): battle.player.add_silver(amount)`

### 2. HUD 改造（`scripts/ui/hud.gd`）

- **删除金币 widget**：移除 `_draw_gold_widget`、`_gold`、`_on_gold_changed`、`_sync_gold_from_lobby`、`_load_coin_icon`、`_coin_icon`、`EventBus.gold_changed` 连接、`_draw` 中的调用。
- **icon 换 .png**：`_ready` 加载 `_key_icon = load("res://assets/ui/icons/system/icon_key.png")`、`_silver_icon = load("res://assets/ui/icons/currency/icon_cur_silver.png")`。`_draw_key_widget`/`_draw_silver_widget` 改用 `draw_texture_rect`（缩放到 ~18px）替代程序化像素画。
- **常驻 + 初始 0**：删除 `if _keys > 0` / `if _silver > 0` 守卫，`_keys=_silver=0` 也绘制。
- **横向布局**：左上角一行。键 widget 在左、银币 widget 在右。具体坐标（scaled）：
  - 钥匙 icon rect `Rect2(_scaled(12), _scaled(10), _scaled(18), _scaled(18))`，数字 `_scaled(34), _scaled(19)`
  - 银币 icon rect `Rect2(_scaled(72), _scaled(10), _scaled(18), _scaled(18))`，数字 `_scaled(94), _scaled(19)`
  - （实现时按实际 icon 比例微调，保证行高一致。）
- **新增公共方法**：
  ```
  func get_pickup_icon_world_pos(kind: String) -> Vector2
  ```
  返回该 icon 屏幕中心（基于上面 rect 中心 + HUD 原点 (0,0)）经 `get_viewport().get_canvas_transform().affine_inverse()` 反算的世界坐标。复刻 `soul_orb.gd:107-118`。未知 kind 回落到银币 icon 位置并 `push_warning`。

### 3. 宝箱改造（`chest_normal.gd` / `chest_locked.gd`）

两文件 `_open()`：
- `player.add_key(1)` + `_show_popup(1, "key")` → `_battle.pickup_orb_manager.spawn_burst(global_position, "key", 1)`
- `player.add_silver(n)` + `_show_popup(n, "silver")` → `_battle.pickup_orb_manager.spawn_burst(global_position, "silver", n)`
- 删除 `_show_popup` 方法与 `ChestResultPopup` preload。
- 货币入账延后到 orb 到达（manager 的 `_on_arrive` 回调里 `player.add_*`）。
- `chest_locked` 缺钥匙时的 `hud.show_message("UI_CHEST_LOCKED_NEED_KEY", 1.2)` 保留不动；`spend_key()` 即时扣（不在本任务范围）。
- `unregister_self(_battle)` + 换 `chest_open.png` + `queue_free` 顺序不变（orb 已先 spawn 到 `global_position`）。

### 4. Battle 接线（`scripts/battle.gd`）

仿 `SoulOrbManager`（line 75、204-207）：
- `@onready var pickup_orb_manager` / preload `PickupOrbManagerScript`
- `_ready` 或 setup 流程：`pickup_orb_manager = PickupOrbManagerScript.new()`，name "PickupOrbManager"，`add_child`，`setup(self)`。
- 给宝箱用（宝箱已有 `_battle` 引用）。

### 5. i18n / 风险

- 无新增可见文字，不触发 CLAUDE.md 第十三条 i18n 规则。`UI_CHEST_LOCKED_NEED_KEY` 已存在。
- 风险：orb 未到达即切关/退场会丢这笔钱（与现有 exp 同行为，可接受）。
- 风险：`chest_locked` 开锁消耗钥匙即时扣 → 计数先减；如果随后 reward 是钥匙又会飞回来加，视觉上"钥匙飞出又飞入"是正常的，不算 bug。

## 验证

1. 进游戏开局：左上角横向显示钥匙 icon=0、银币 icon=0，无金币 widget。
2. 走到普通宝箱触发：银币 icon（1-3 个）从宝箱位置发光掉落 → 停留 ~0.4s → 蓝色拖尾飞向左上角银币 icon → 蓝色粒子爆裂 → 银币计数 +N。
3. 触发钥匙宝箱：钥匙 icon 同样流程飞向钥匙 icon位置 → 计数 +1。
4. 锁定宝箱无钥匙：显示 `UI_CHEST_LOCKED_NEED_KEY`；有钥匙：消耗 1 钥匙（即时减）→ 开出 reward 飞行 +N。
5. 暂停菜单切 English：HUD 数字仍正常（无新文字），无中文残留。
6. 多次开箱确认计数准确、无 orb 残留。
