# 街霸6 特有量表系统 — 研究与集成笔记

> 街霸6 如何存储和应用角色专属资源（杰米的酒、布兰卡人偶、朱莉的风破点数等），
> 以及自定义连招试炼（Custom Combo Trials）如何记录并复现它们。

## 摘要

| 需求 | 答案 |
|---|---|
| 读取当前等级（实时） | `cPlayer.mStyleNo`（0 = 无，N = 当前层数/等级） |
| 上一个等级 | `cPlayer.style_old`（65535 = 本回合从未变过） |
| 用代码应用等级 | 写入 `TrainingManager._tData.ParameterSetting.UniqueData.stock_0_XXX = N`，然后调用 `TrainingManager:call("set_IsReqRefresh", true)` |
| 伤害修正（杰米） | `style_hosei_atk = 90 + 5 × 酒数` |

## 字段（nBattle.cPlayer）

| 字段 | 含义 |
|---|---|
| `mStyleNo` | **当前**风格等级 — 权威数据源。杰米：0–4 杯酒。 |
| `mReqStyle` | 请求的风格等级（由引擎消费）。 |
| `style_old` | **上一个**等级，不是当前等级。`65535` 表示"本回合从未有过风格"。 |
| `style_hosei_atk` | 攻击修正百分比。杰米：`90 + 5 × 酒数`（0 酒 90 → 4 酒 110）。 |
| `comb_id` | 当前指令表 id。随风格等级变化（杰米：2 → 4 → 5），但只在下一次动作/回合初始化时同步 — 不要手动写入。 |
| `style_timer` | 时限型强化的计时器（电刃练气、风水引擎、魔醉之歌等）。 |

## 方法（nBattle.cPlayer）

| 方法 | 语义 |
|---|---|
| `pl_style_change(delta, 1)` | **相对**变化。自然喝酒动作调用 `pl_style_change(1, 1)`。 |
| `pl_style_change(level, 0)` | **绝对**重设。游戏本身周期性调用它刷新修正值。脚本单独调用只更新修正/外观 — 不更新计数器 UI 和指令表。 |
| `pl_style_set(level)` | 只写入等级字段，无副作用。 |
| `pl_style_update()` | 每帧更新，无参数。不是刷新触发器。 |

**重要：** 单独调用以上任何方法都无法完整复现自然喝酒的全部效果
（计数器 UI + 指令表 + 外观 + 修正值）。完整状态只在引擎自己应用风格时组装 —
即**训练模式刷新**时。

## 可靠的应用路径（连招试炼采用的方案）

```lua
-- 1. 设置训练菜单中该角色的特有量表
local tm = sdk.get_managed_singleton("app.training.TrainingManager")
local ud = tm:get_field("_tData"):get_field("ParameterSetting"):get_field("UniqueData")
ud:set_field("stock_0_021", 2)          -- 杰米 = 角色 id 21，字段 = stock_0_%03d
-- 2. 触发原生刷新
tm:call("set_IsReqRefresh", true)
```

刷新会原生应用所有内容：`mStyleNo`、`comb_id`、酒计数 UI、发型、解锁招式。
它同时会重新应用其他所有菜单设置（血量/量表/位置），连招试炼已有的
量表/体力注入逻辑会自动补偿。

各角色的 `UniqueData` 字段名（`stock_0_%03d` / `timer_0_%03d`，使用 ESF 角色 id）：
隆 `timer_0_001`、金伯莉 `stock_0_003`、玛农 `stock_0_005`、莉莉 `stock_0_012`、
布兰卡 `timer/stock_0_015`、朱莉 `timer/stock_0_016`、古烈 `timer_0_018`、
本田 `stock_0_020`、杰米 `timer/stock_0_021`、不知火舞 `stock_0_028`、
维珀 `timer_0_030`、英格丽德 `stock_0_032`。

## 连招试炼集成（TrainingComboTrials_v1.0.lua）

实现采用与 [SF6_TOOLS_CC](https://github.com/cdjay/SF6_TOOLS_CC) 共享的
`unique_resources` 模块，两个项目的连招文件可以互换：

- **注册表** — `unique_resources.by_fighter_id`：每个角色的资源列表
  （`id`、`kind` stock/timer、`min`/`max`、`allow_infinite`/`reject_infinite`、
  可选的 ParamFunc `setter`，如舞的 `SetUnique028_stock_0`）。
- **录制** — `unique_resources.capture_scene_state()` 在录制开始时快照双方的
  特有资源值，存入连招 JSON：
  ```json
  "scene_state": {
    "schema": "xt.combo_trial.scene.v1",
    "capture_mode": "portable",
    "recorded_by": 0,
    "players": { "p1": { "fighter_id": 21, "unique": { "stock_0_021": 2 } } }
  }
  ```
  本地扩展：对 stock 型资源，捕获时还会读取实时的 `cPlayer.mStyleNo` 并取较大值 —
  这样**游戏内**获得的资源（如 22P 喝酒）也能被录制，即使训练菜单仍显示 0。
- **试炼开始** — `unique_resources.apply_recorded()` 从 `scene_state` 收集条目
  （兼容旧的 `meta.environment` 布局和过渡期的 `combo_stats.style_stock` 格式），
  备份当前菜单值（`save_current()`），写入录制值，然后请求训练刷新。
- **试炼结束** — `unique_resources.restore()` 写回备份的菜单值并刷新。

未激活特有资源时录制的连招不含 `scene_state` 键，行为与之前完全一致
（零开销，完全向后兼容）。

## 当前状态与测试情况

| 角色 | 类型 | 状态 |
|---|---|---|
| **杰米**（酒等级） | stock | ✅ **已测试 — 100% 可用**（录制、复现、还原） |
| 金伯莉、玛农、莉莉、本田、不知火舞、英格丽德、布兰卡/朱莉的层数 | stock | ⚠ 未测试 — 与杰米走同一代码路径，理论上可用但需要实机验证 |
| 隆（电刃练气）、古烈、维珀、布兰卡/朱莉/杰米的计时器 | timer | ⚠ 菜单值会被捕获/应用，但**游戏内**激活的强化无法检测，剩余强化时间也不会还原 — 未测试 |

### 如何参与改进

1. **验证层数型角色**：在游戏内实际获取资源（不要用菜单设置），录制一段连招，
   打开 `data/TrainingComboTrials_data/CustomCombos/<角色>/` 里的 JSON，
   确认 `scene_state.players.<side>.unique.stock_0_XXX` 与实际层数一致。
   启动试炼，验证计数器/招式/外观是否正确应用；退出试炼，验证训练菜单的值被还原。
   如果某个角色的 `mStyleNo` 与菜单层数值不是 1:1 对应，请调整
   `unique_resources.capture_for_fighter()` 里的实时覆盖（live overlay）代码块。
2. **集成点**（`TrainingComboTrials_v1.0.lua` 的 `unique_resources` 模块）：
   - `capture_scene_state()` — 录制开始时调用，存为 `scene_state`
   - `apply_recorded()` — 由 `start_trial()` 调用，备份 + 写入菜单值 + 刷新
   - `restore()` — 试炼退出路径调用，还原备份 + 刷新
3. **添加时限型支持**（电刃练气、风水引擎、Sonic 强化等）：
   注册表已声明 `timer_0_XXX` 资源（0 = 标准，1 = 激活/最大，2 = 无限），
   它们作为菜单值被捕获/应用 — 但**游戏内**激活的强化目前无法检测
   （需要一个基于 `style_timer` 的实时覆盖，类似 stock 的 `mStyleNo` 方案），
   且剩余的强化时间不会被还原。刷新路径与层数型完全相同。

## 已验证的注意事项

- 游戏内的酒**计数器 UI** 不跟随脚本的 `pl_style_change` 调用 —
  只有"菜单 + 刷新"路径能更新它。
- `comb_id`（解锁招式）同样需要刷新；静止训练状态下仅写 `mStyleNo` 不会同步。
- 训练刷新会把脚本设置的风格状态**重置**为菜单值 —
  这正是"先写菜单"是唯一稳定方案的原因。
- 时限型强化（电刃练气、风水引擎等）使用 `timer_0_XXX` + `style_timer`，
  目前**尚未**录制 — 只支持层数型（stock）风格。
- 放在 `autorun/` **子文件夹**里的脚本不会被 Reset Scripts 重新加载：
  测试探针必须放在 `autorun/` 顶层。
