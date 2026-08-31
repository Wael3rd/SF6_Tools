# 在 Street Fighter 6 中用 REFramework 构建原生游戏内菜单与 HUD

> **TL;DR** -- 你可以仅使用 REFramework Lua,在 SF6 训练模式中注入完全原生的设置窗口、暂停菜单行与标签页、HUD 面板
> 文字,以及屏幕弹窗 -- 不需要 DLL 补丁,不需要自定义渲染,也不需要 ImGui。游戏自己负责构建这些行、处理焦点/导航,
> 并用它自己的字体、精灵图和九宫格边框来绘制一切。本指南记录了我们实现过的每一项技巧、每一次教会我们一条规则的
> 崩溃,以及找到这些入口点所用的探测工作流。

| | |
|---|---|
| **阅读时间** | 约 45 分钟(完整阅读);约 15 分钟(仅技巧 1-2) |
| **技能水平** | 中级 REFramework Lua(你需要了解 `sdk.hook`、`sdk.find_type_definition`、`sdk.get_managed_singleton`) |
| **游戏版本** | Street Fighter 6,RE Engine(在 REFramework-Websockets 版本 LL5271 上测试;所有菜单技巧在普通 REFramework 下同样可用) |
| **最后更新** | 2026-08-31 |

[![Native window over the fight](../img/native_window_hitconfirm.png)](../img/native_window_hitconfirm.png)
*“Hit Confirm”设置窗口,完全基于游戏自身的 Options 对话框 UI 构建,显示在暂停中的对战画面之上。*

---

## 1. 本指南适合谁

你是一名 REFramework Lua 模组作者,想要在 SF6 训练模式中添加设置、覆盖层或控制项,**但不使用** ImGui 窗口或 D2D
覆盖层。也许你希望模组的设置看起来就像游戏原生的一部分;也许 ImGui 在你用户的环境下不够稳定;也许你想要支持
手柄导航的菜单。

本指南涵盖五种互补的技巧,从最实用的(Options 对话框行)到最实验性的(劫持游戏的两栏式 Control Settings 对话
框)。每一节都是自成一体的:只读你需要的部分即可。

**你将获得:**
- 一个显示在对战画面之上的设置窗口,会暂停动作,外观与游戏自身的 Options 面板完全一致(滑条、开关、
  spin-text、按钮)。
- 训练暂停菜单内的行以及完整的标签页(spin、按钮、动作回调)。
- 由你的脚本驱动的游戏自带 Damage / Combo Damage / Attack Type 面板以及回合计时器数字。
- 由借用的 GUI 元素拼装出的弹窗边框与文字(比如“Match Found”霓虹边框等)。
- 一套用于发现新菜单与新可 hook 控件的工作流。

---

## 2. 前置条件

### REFramework

任意近期的 SF6 版 REFramework 都能用于本指南的菜单技巧(1-5)。
[REFramework-Websockets 版本(LL5271)](https://github.com/praydog/REFramework) 在 8080 端口增加了一个 Lua
websocket 服务器,可以通过脚本进行远程探测(第 10 节),但 UI 注入本身并不需要它。

### Lua 基础

你应当熟悉以下内容:
- `sdk.find_type_definition`、`sdk.get_managed_singleton`、`sdk.create_instance`
- `sdk.hook(method, pre_fn, post_fn)` 以及 `PreHookResult.SKIP_ORIGINAL` 这种写法
- `re.on_pre_application_entry("LateUpdateBehavior", fn)`(游戏线程回调)
- `re.on_frame`(渲染线程)与游戏线程的区别 -- 这个区分至关重要(规则 1)
- 用于持久化的 `json.load_file` / `json.dump_file`

### 崩溃日志阅读流程

当 SF6 在加载 REFramework 的情况下崩溃时,在重新启动前先检查**两个文件**(日志会在重启时被覆盖):
1. `reframework/re2_framework_log.txt` -- 滚动到“Exception occurred”部分查看调用栈和出错地址。
2. `reframework/reframework_crash.dmp` -- 时间戳可以告诉你这是哪一次崩溃。

---

## 3. 游戏 UI 的运作原理

以下是与模组开发相关的游戏 UI 架构简要地图。这些内容全部是通过探测(第 10 节)发现的,并非来自任何官方文档。

### 控件与 Agent

SF6 的 UI 构建在 RE Engine 的 `via.gui` 控件树之上。控件(`via.gui.Control` 及其子类型 -- `Rect`、`Text`、
`Scale9Grid`、`Panel`)构成一个父子层级结构。每个菜单画面都有一个 **UIAgent**(`app.UIAgent`),它拥有一棵
控件树(可通过 `agent.get_ControlMain()` 访问)。所有存活的 agent 都列在 `app.UIAgentManager._Entries` 中。

训练模式中的关键 agent 名称:
| Agent 名称 | 说明 |
|---|---|
| `ui11200` | 训练暂停菜单(标签页、行、焦点管理) |
| `OptionDialog` | Options / Settings 对话框(显示在对战画面之上,或从暂停菜单打开) |
| `KeyConfigBattleMenuFG` | “Control Settings”两栏式对话框 |
| `BattleHud_Timer` | 回合计时器(承载着我们借用元素时所挂靠的 `c_main` 控件) |
| `Resident_Cmn_MatchingStandby` | 匹配弹窗(霓虹边框与文字的来源) |

### UIFlow 与 Param

菜单画面由 **UIFlow**(`app.UIFlowManager`)管理。一个 flow 通过静态的 `Start(...)` 调用启动,返回一个
`IUIFlowHandle`。该 flow 会创建一个 `Param` 对象(它的运行状态),并驱动画面依次经过 `Init` -> `ShowedObject`
-> 用户交互 -> `OnEnd`。通过 handle 的 `get_IsEnd()` 可以知道该 flow 何时结束。

重要的 flow:
| Flow 类 | Param 类 | 驱动的内容 |
|---|---|---|
| `app.UIFlowOptionBGDialog` | `app.UIFlowOptionBGDialog.Param` | 深色的“BattleHud”选项窗口(我们的主要载体) |
| `app.UIFlowKeyConfig.Menu` | `app.UIFlowKeyConfig.Menu.Param` | 两栏式 Control Settings 对话框 |
| `app.UIFlowShortcutSetting` | (由 `app.ShortcutSetting` 管理) | Shortcut Settings 菜单 |

### UIParts

菜单内的行是 `UIParts` 对象(`UIPartsSpin`、`UIPartsButton`、`UIPartsScrollList`、`UIPartsGroupScroll`)。
游戏会从一个对象池中实例化它们,并将其绑定到数据对象上。你几乎不会直接创建 UIParts;取而代之的是创建数据对象
(`OptionSettingUnit`、`TrainingMenuData`),然后让游戏自己去构建这些 parts。

### 消息 GUID(hMsg)

SF6 菜单中显示的每一段文字都来自一次 GUID 查找:`app.helper.hMsg.GetMessage(Guid)`。游戏把文字保存在以 GUID
为索引的消息表中。我们无法向这些表中添加条目,所以我们 hook `GetMessage`,拦截我们自己伪造的 GUID,并返回我们
想要的任意字符串。这是本指南中每一项技巧的基础。

```lua
-- Create a GUID and register its text
local guid_text = {}   -- GUID string -> our text
local function message_guid(str)
    local g = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    guid_text[g:call("ToString()")] = str
    return g
end

-- Hook the message resolver
sdk.hook(
    sdk.find_type_definition("app.helper.hMsg"):get_method("GetMessage(System.Guid)"),
    function(args)
        local s = guid_text[sdk.to_valuetype(args[2], "System.Guid"):call("ToString()")]
        if s then
            thread.get_hook_storage()[1] = s
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function(retval)
        local s = thread.get_hook_storage()[1]
        if s then return sdk.to_ptr(sdk.create_managed_string(s)) end
        return retval
    end
)
```

### 向对象写入 GUID

这个 REFramework 版本拒绝直接赋值嵌套的 `ValueType` 字段(例如 `obj.GuidField = guid`)。你必须手动写入这 16
个原始字节:

```lua
local function set_guid(obj, field_name, guid)
    local off = obj:get_type_definition():get_field(field_name):get_offset_from_base()
    obj:write_qword(off, guid:read_qword(0))
    obj:write_qword(off + 8, guid:read_qword(8))
end
```

---

## 4. 黄金法则(崩溃验证过的经验)

下面的每一条规则都是从一次崩溃中学到的 -- 其中大多数来自把游戏直接打挂、且无法恢复的访问违规(access
violation)。规则按严重程度排列。

### 规则 1:禁止在主线程之外运行 Lua

**症状:** 加载后 1-3 分钟内,在引擎的随机函数中出现间歇性 AV(访问违规)。打开 REFramework 菜单会掩盖这个
问题(因为它把 Lua 的执行串行化了)。

**原因:** 对运行在游戏输入线程、UI job 线程或渲染线程上的方法使用 `sdk.hook` 回调。具体来说,对 `InputState`
的 setter、`UIWidget_TMAttackInfo.SetXText` 以及 `UIBattleHud_Timer.UpdateBattleHud` 的 hook 都会让 Lua
在主线程之外执行,并造成不确定性的崩溃(用 `soak.py` 做二分定位:去掉这些 hook 时 0/3 次崩溃,加上时 3/3
次崩溃)。

**规则:** 每一次 GUI 写入、每一个非平凡的 Lua 回调都必须发生在游戏的主线程上:
`re.on_pre_application_entry("LateUpdateBehavior", fn)`。渲染线程(`re.on_frame`)上的只读 hook 可以用来
采集数据,但**绝不能**从那里写入游戏对象。

### 规则 2:写入缓存对象前先确认其存活

**症状:** 在 `via.gui.Text` 或 `via.gui.Control` 上调用 `set_Message`、`set_Color` 或 `set_Visible` 时出现
AV,而这个对象在几帧之前还是有效的。

**原因:** 游戏会在每次 `PauseManager._CurrentPauseTypeBit` 变化时重建战斗 HUD(我们窗口用的暂停类型 8、真正
的暂停菜单、Options 对话框……)。任何缓存的控件都可能被释放,而 `sdk.is_managed_object` 在一块**被重新分配**
的内存上仍可能返回 `true`(31/08 实测:即使加了防护仍会崩溃)。在暂停/HUD 切换期间,缓存的控件不仅仅是失效
-- 那块内存可能已经被复用给了另一个对象。

**规则:**
1. 每次写入前调用 `sdk.is_managed_object(control:get_address())` -- 但要清楚它并不完美。
2. 一旦 `TrainingGamePaused` 或 `NativeOptionsWindowOpen` 变为 true,**立刻丢弃所有缓存**(面板、计时器、
   文字)。不要尝试任何“最后一次写入” -- 那些控件可能已经被释放了。
3. 监控 `_CurrentPauseTypeBit`:一旦发生变化,丢弃所有缓存,并等待 20 tick 之后再重新解析控件。
4. 把每一次 GUI 写入都包在 `pcall` 里。一次没有防护的 AV 就是致命的。

### 规则 3:绝不重新填充一个已经打开的对话框页面

**症状:** 在你修改了某个当前正显示其对话框页面的 unit 的 `ChildUnitList` 之后几帧,UI parts 池中出现 RIP 0
(空函数指针解引用)。

**原因:** `SetupDispUnits` 会把池中的 UIParts 绑定到你的数据上。如果你在页面存活期间改变了数据类型(例如把
一个滑条换成一个按钮),池会把错误类型的 part 重新绑定上去,下一次布局调用就会跳到一个空的 vtable 条目上。

**规则:** 绝不要在对话框页面打开期间调用 `SetupDispUnits` 或修改 `ChildUnitList`。正确做法是:先 `End()`
该对话框,等待其 agent 消失,`rebuild()` 数据树,然后再 `Start()` 一个新对话框。配合 `ImmediateFade = true`
(见第 5 节),即使在持续暂停的状态下,这个过渡在视觉上也是瞬间完成的。

### 规则 4:绝不伪造引擎期望完整构建的游戏数据对象

**症状:** 在 `SetSettingParams` 或 `MakeListIndexToParamIndex` 内部出现 `NullReferenceException`,随后在
`UpdateListSetting` 中出现 `IndexOutOfRangeException`,游戏在几帧之后崩溃。

**原因:** 通过 `sdk.create_instance` 创建 `app.UIKeyConfig.SettingParam`,却只填充了整数字段。引擎的方法
期望 `Name`、`Icon`、`Comment` 这些字符串属性以及 `GamePadButton` 枚举都被完整初始化。半成品的 param 会导致
列表构建崩溃。

**规则:** 当某个游戏类型的初始化很复杂时,应当**克隆**一个已有实例(`CloneSettingParams`、
`MemberwiseClone`),而不是凭空构造一个。只通过 hook 覆盖文本的 getter。`NativeDialog` 正是这样工作的(见第
9 节)。

### 规则 5:用 pcall(func, args),不要用 pcall(function() ... end)

**症状:** 内存占用逐渐增长(每分钟 1-3 MB),最终导致卡顿。

**原因:** `pcall(function() ... end)` 每次调用都会分配一个新的闭包。在热路径上(每秒 60 次调用),这些闭包
积累的速度比 GC 回收的速度还快。

**规则:** 使用预先定义好的函数,写成 `pcall(func, arg1, arg2)`。在一次排查中,SF6 Tools 代码库里有 89 处
热路径闭包调用被修复。

### 规则 6:io.open 相对于 reframework/data/,绝不使用 ".."

**症状:** `io.open` 静默失败,或者写入到了意料之外的位置。

**原因:** REFramework 把 `io.open` 沙箱限制在了 `reframework/data/` 目录下。带有 `..` 的路径会被拒绝。
`io.popen` 和 `os.execute` 则被完全禁用。

**规则:** JSON 一律使用 `json.dump_file`(它能处理 Windows 的文件锁)。`io.open` 只用于文本文件,路径始终
相对于 `reframework/data/`(路径中不要带 `data/` 前缀)。

### 规则 7:fs.glob 开销很大 -- 绝不能放在定时器里

**症状:** 每隔 N 秒出现一次约 260 ms 的帧时间尖峰。

**原因:** `fs.glob` 会遍历整个 `reframework/data/` 目录树(约 2200 个文件)。周期性地调用它(比如为了刷新
文件列表)会造成规律性的卡顿。

**规则:** 只在菜单即将打开时调用 `fs.glob`(此时用户本就预期会有短暂停顿)。把结果缓存起来。在
`NativeOptions` 中,`lists_changed()` 检查和 `rebuild()` 都发生在 `open_request` 路径中,而不是定时器里。

### 规则 8:GUI 写入只能在 LateUpdateBehavior 中进行

**症状:** 从 `re.on_frame` 中调用 `set_Message` 时出现 AV。

**原因:** `re.on_frame` 运行在**渲染线程**上。从那里写入 `via.gui.Text.set_Message` 会与主线程上游戏自身的
布局(layout)过程产生竞争。

**规则:** `set_Message`、`set_Color`、`set_Visible`、`set_Position`、`set_Size` -- 这些全部都必须从
`re.on_pre_application_entry("LateUpdateBehavior", ...)` 中调用,或者从一个已知运行在主线程上的方法(例如
`TrainingManager.OpenMenu`)的 `sdk.hook` 回调中调用。

### 规则 9:绝不在源头修改游戏文本

**症状:** 训练重置后崩溃,或文本被永久性损坏。

**原因:** 覆盖一个由游戏拥有的控件的 `Message` 字段,意味着游戏自身的更新逻辑会把你写入的文本读回去,并把它
当作原始文本对待。

**规则:** 只写入你**已经取得所有权**的控件,并在释放它们时恢复原始内容。把原始内容存到磁盘上(这样它们能在
脚本重载后依然存在)。对于 HUD 面板,“两侧”的文字(`LeftText`、`RightText`)每一帧都会被对应的 widget 重写
-- 把它们隐藏起来,只使用中间的文字。

---

## 5. 技巧 1 -- 选项对话框行(NativeOptions)

这是最主要的技巧:把设置行注入到游戏自身的 Options 系统中,并将其作为一个独立窗口显示在实时对战画面之上。
游戏负责构建开关、滑条、spin-text 和按钮;处理十字键/摇杆导航;并用它自己的风格渲染这一切。

[![SF6 Tools in the Options menu](../img/options_sf6tools_submenu.png)](../img/options_sf6tools_submenu.png)
*“SF6 Tools”出现在 Options > General 的底部。展开它可以看到子分组(Hit Confirm、Script Manager),每一个子
分组都会在对战画面之上打开一个 BattleHud 风格的窗口。*

[![Options window over the fight](../img/native_window_hitconfirm.png)](../img/native_window_hitconfirm.png)
*“Hit Confirm”窗口,包含一个滑条、一个开关和一个按钮,显示在已暂停的对战画面之上。*

### 工作原理

1. **创建 `OptionSettingUnit` 条目**,并将其挂到 `app.OptionManager.UnitLists[General]` 上。游戏的 Options
   界面会读取这个列表来构建“General”标签页。带有 `EventType.OpenSubMenu` 的 unit 会变成一个可点击的分组;
   带有 `EventType.OpenBattleHudSetting` 的 unit 会打开一个“BattleHud”风格的深色窗口。
2. **通过伪造的 GUID 来解析文本**:每一个 `TitleMessage` 和 `DescriptionMessage` 都是一个 GUID。我们生成
   随机 GUID,并 hook `hMsg.GetMessage` 来返回我们自己的字符串。
3. **跳过游戏自身的 Load/Reset**:hook `OptionValueUnit.LoadValueEvent` 和 `ResetEvent`,跳过我们自己的
   TypeId(游戏不应该去加载或重置它并不拥有的值)。
4. **在对战画面之上打开窗口**:从 `LateUpdateBehavior` 中调用 `UIFlowOptionBGDialog.Start(SettingData,
   false)`。`SettingData.TopUnit` 指向我们其中一个分组 unit。
5. **暂停对战**:`PauseManager.requestPause(true, 8)`(类型 8 = `BATTLE_MENU_PAUSE`,与真正的暂停菜单使用
   的类型相同)。窗口关闭时释放暂停。

### 分步指南:添加一个设置分组

#### 第 1 步:分配 TypeId

每个 `OptionSettingUnit` 都需要一个唯一的 `TypeId`。游戏会按 TypeId 跨脚本重载缓存 widget 种类,所以你的
脚本每次加载时都必须使用全新的 ID:

```lua
local next_id = nil
local function new_id()
    if not next_id then
        -- Find the highest existing TypeId in the game's ValueType enum
        local max = 0
        for _, f in ipairs(sdk.find_type_definition("app.Option.ValueType"):get_fields()) do
            if f:is_static() then
                local ok, v = pcall(f.get_data, f, nil)
                if ok and type(v) == "number" and v > max and v < 2100000000 then max = v end
            end
        end
        next_id = math.ceil((max + 1) / 10) * 10 + 100000
        next_id = next_id + (os.time() % 5000) * 100   -- fresh per load
    end
    next_id = next_id + 1
    return next_id
end
```

#### 第 2 步:构建 Unit 树

```lua
local InputType = enum("app.Option.UnitInputType")     -- SpinText, Slider, Button_Type1, Button_Type2
local EventType = enum("app.Option.DecideEventType")   -- OpenSubMenu, OpenBattleHudSetting, SettingReset, ...
local DataType  = enum("app.Option.SettingDataType")   -- Value
local TabType   = enum("app.Option.TabType")           -- General

local mgr = sdk.get_managed_singleton("app.OptionManager")
local parent_list = mgr.UnitLists:call("get_Item", TabType.General)

-- Get empty typed lists from an existing unit (for MemberwiseClone)
local first_setting = parent_list:call("get_Item", 0):call("get_Setting")
local empty_guids    = first_setting.ValueMessageList:call("GetRange", 0, 0)
local empty_settings = first_setting.ChildUnitList:call("GetRange", 0, 0)
```

#### 第 3 步:创建根分组

```lua
local function new_setting()
    local d = sdk.create_instance("app.Option.OptionSettingUnit")
    d.TypeId = new_id()
    return d
end

local function make_unit(desc, description, value_messages)
    local unit = desc:call("MakeUnitData")
    local s = unit:call("get_Setting")
    set_guid(s, "DescriptionMessage", message_guid(description or ""))
    s.ValueMessageList = empty_guids:call("MemberwiseClone")
    s.ChildUnitList    = empty_settings:call("MemberwiseClone")
    for _, msg in ipairs(value_messages or {}) do
        s.ValueMessageList:call("Add", message_guid(msg))
    end
    return unit
end

-- Root: "My Mod" -> opens a sub-menu
local root_desc = new_setting()
set_guid(root_desc, "TitleMessage", message_guid("My Mod"))
root_desc.InputType = InputType.Button_Type1
root_desc.EventType = EventType.OpenSubMenu
local root_unit = make_unit(root_desc, "Settings for My Mod.")
parent_list:call("Add", root_unit)
```

#### 第 4 步:添加一个设置子分组(打开一个窗口)

```lua
local group_desc = new_setting()
set_guid(group_desc, "TitleMessage", message_guid("My Settings"))
group_desc.InputType = InputType.Button_Type1
group_desc.EventType = EventType.OpenBattleHudSetting   -- opens a window over the fight
local group_unit = make_unit(group_desc, "Adjust my mod's parameters.")

-- Attach to root
local function attach(parent, child)
    parent:call("get_ChildUnits"):call("Add", child)
    parent:call("get_Setting").ChildUnitList:call("Add", child:call("get_Setting"))
end
attach(root_unit, group_unit)
```

#### 第 5 步:添加一个开关(带 Off/On 的 SpinText)

```lua
local toggle_desc = new_setting()
set_guid(toggle_desc, "TitleMessage", message_guid("Enable Feature"))
toggle_desc._DataType   = DataType.Value
toggle_desc.InputType   = InputType.SpinText
local toggle_type_id = toggle_desc.TypeId

local toggle_unit = make_unit(toggle_desc, "Turn the feature on or off.", {"Off", "On"})
attach(group_unit, toggle_unit)

-- Value setting (min/max/initial)
local vs = sdk.create_instance("app.Option.OptionValueSetting")
vs.TypeId = toggle_type_id
vs.MinValue = 0; vs.MaxValue = 1; vs.InitValue = 1   -- default "On"
toggle_unit:call("set_PrevValue", 1)
toggle_unit:call("set_ValueSetting", vs)
toggle_unit.ValueData = vs:call("MakeValueData")
```

#### 第 6 步:添加一个滑条

```lua
local slider_desc = new_setting()
set_guid(slider_desc, "TitleMessage", message_guid("Block Rate"))
slider_desc._DataType = DataType.Value
slider_desc.InputType = InputType.Slider

local slider_unit = make_unit(slider_desc, "Chance (%) that the dummy blocks.")
attach(group_unit, slider_unit)

local svs = sdk.create_instance("app.Option.OptionValueSetting")
svs.TypeId = slider_desc.TypeId
svs.MinValue = 0; svs.MaxValue = 100; svs.InitValue = 50
slider_unit:call("set_PrevValue", 50)
slider_unit:call("set_ValueSetting", svs)
slider_unit.ValueData = svs:call("MakeValueData")
```

#### 第 7 步:添加一个按钮(Restore-Row 模式)

按钮使用 `InputType.Button_Type2` 和 `EventType.SettingReset` -- 与游戏“Restore Default Settings”那一行
完全相同的模式。渲染出来是一个全宽、居中的按钮。

```lua
local btn_desc = new_setting()
set_guid(btn_desc, "TitleMessage", message_guid("START SESSION"))
btn_desc.InputType = InputType.Button_Type2
btn_desc.EventType = EventType.SettingReset
local btn_unit = make_unit(btn_desc, "Start the training session.")
attach(group_unit, btn_unit)
```

> **注意:** `Button_Type1` 在获得焦点时标题左对齐(用于子菜单导航)。`Button_Type2` 则始终保持标题居中
> (用于动作按钮)。在你的设置窗口中,按钮请始终使用 `Type2`。

要处理按钮按下事件,需要 hook `Param.GetFocusDecideEventType` 和 `Param.FlowEvent_ResetCurrentUnits`:

```lua
local bg_param_td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")

-- Intercept the decide: return Invalid (0) for our buttons so no "Revert?" popup appears
sdk.hook(bg_param_td:get_method("GetFocusDecideEventType"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    if (sdk.to_int64(rv) & 0xFF) == 1 then   -- SettingReset
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local u = param:call("GetFocusUnit")
        local tid = u and u:call("get_Setting").TypeId
        if tid == btn_desc.TypeId then
            -- Queue your callback here
            my_button_callback()
            return sdk.to_ptr(0)   -- DecideEventType.Invalid: no popup
        end
    end
    return rv
end)
```

#### 第 8 步:为我们自己的 ID 跳过 Load/Reset

```lua
local known_ids = { [toggle_type_id] = true, [slider_desc.TypeId] = true, [btn_desc.TypeId] = true }

local function skip_ours(args)
    local ok, id = pcall(function()
        return sdk.to_managed_object(args[2]):call("get_Setting").TypeId
    end)
    if ok and known_ids[id] then return sdk.PreHookResult.SKIP_ORIGINAL end
end

local vu = sdk.find_type_definition("app.Option.OptionValueUnit")
sdk.hook(vu:get_method("LoadValueEvent"), skip_ours)
sdk.hook(vu:get_method("ResetEvent"), skip_ours)
```

#### 第 9 步:在对战画面之上打开窗口

```lua
local dialog_handle = nil

local function open_window()
    -- Close any existing dialog first (they stack)
    if dialog_handle then
        pcall(function()
            if not dialog_handle:call("get_IsEnd") then dialog_handle:call("End") end
        end)
    end

    local sd = sdk.create_instance("app.UIFlowOptionBGDialog.SettingData")
    sd.TopUnit = group_unit
    sd.SupportMode = 32
    sd.UseBattleHudBG = false
    sd.PlayerIndex = 0

    local m = sdk.find_type_definition("app.UIFlowOptionBGDialog")
        :get_method("Start(app.UIFlowOptionBGDialog.SettingData, System.Boolean)")
    dialog_handle = m:call(nil, sd, false)
end
```

在你的热键被按下,或暂停菜单按钮被激活时,从 `LateUpdateBehavior` 中调用 `open_window()`。**绝不要从
`re.on_frame` 中调用**(规则 8)。

#### 第 10 步:暂停对战

```lua
local PAUSE_TYPE = 8   -- BATTLE_MENU_PAUSE
local pause_held = false

local function hold_pause(on)
    if on == pause_held then return end
    local mgr = sdk.get_managed_singleton("app.PauseManager")
    if mgr and pcall(function() mgr:call("requestPause", on, PAUSE_TYPE) end) then
        pause_held = on
    end
end
```

在 `open_window()` 之后立即调用 `hold_pause(true)`。当对话框关闭时(通过 `dialog_handle:call("get_IsEnd")`
或 `OptionDialog` agent 消失来检测)调用 `hold_pause(false)`。

#### 第 11 步:检测关闭

从 `LateUpdateBehavior` 中每隔约 10 tick 轮询一次:

```lua
if dialog_handle then
    local ended = pcall(function() return dialog_handle:call("get_IsEnd") end)
        and dialog_handle:call("get_IsEnd")
    if ended then
        dialog_handle = nil
        hold_pause(false)
    end
end
```

#### 第 12 步:轮询数值变化

```lua
-- In LateUpdateBehavior, every ~10 ticks:
local ok, n = pcall(function() return toggle_unit:call("get_Value") end)
if ok and n ~= last_toggle_value then
    last_toggle_value = n
    local is_on = (n ~= 0)
    -- Act on the change
end
```

### 与暂停菜单的互斥

用于关闭你窗口的 Esc/Start 按键,同样会经由 `TrainingManager.OpenMenu` 到达训练暂停菜单。在你窗口打开期间
(以及关闭后约 20 帧内)hook 它并跳过:

```lua
local tm_td = sdk.find_type_definition("app.training.TrainingManager")
local open_menu = tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
sdk.hook(open_menu, function(args)
    if my_window_open or (tick - closed_tick) < 20 then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end, function(rv) return rv end)
```

### 跳过屏幕淡入淡出(ImmediateFade)

当你关闭并重新打开对话框时(例如在模式切换后刷新内容),默认的过渡效果包含一个屏幕淡入淡出。在持续暂停的
状态下,这个淡入淡出会被卡住(淡入淡出动画需要未暂停的帧)。要跳过它:

```lua
sdk.hook(bg_param_td:get_method("CreatedObject"), function(args)
    if my_window_open then
        pcall(function()
            local param = sdk.to_managed_object(args[2])
            param:set_field("<ImmediateFade>k__BackingField", true)
        end)
    end
end, function(rv) return rv end)
```

### 隐藏游戏自带的“Restore Default Settings”行

你的窗口打开时,游戏会自动添加一行“Restore Default Settings”。在我们的页面上(它并不会重置任何东西),
需要把它隐藏起来:

```lua
sdk.hook(bg_param_td:get_method("SetupDispUnits"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    pcall(function()
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local parts = param:get_field("OptionUnits")
        if not parts then return end
        local ours = false
        local reset_parts = {}
        for i = 0, parts:call("get_Length") - 1 do
            local part = parts:call("GetValue", i)
            local ud = part and part:get_field("UnitData")
            if ud then
                local s = ud:call("get_Setting")
                if known_ids[s.TypeId] then
                    ours = true
                elseif s.EventType == 1 then   -- SettingReset (the game's own)
                    reset_parts[#reset_parts + 1] = part
                end
            end
        end
        if ours then
            for _, part in ipairs(reset_parts) do
                local c = part:call("get_Control")
                if c then c:call("set_ForceInvisible", true) end
                pcall(function() part:call("SetDisable", true) end)
            end
        end
    end)
    return rv
end)
```

### 动态列表与刷新

如果你的选项里包含一个文件列表(比如录制槽位),只应该在窗口即将打开时重新读取它 -- 绝不能放在定时器里
(规则 7)。模式如下:

1. 打开之前,检查是否有任何 `options_fn`(一个返回列表的函数)发生了变化。
2. 如果发生了变化,拆除 unit 树(`parent_list:Remove(root_unit)`)并重建它。
3. 打开新窗口。

### 脚本重置时的清理

```lua
re.on_script_reset(function()
    if root_unit and parent_list then
        pcall(function() parent_list:call("Remove", root_unit) end)
    end
end)
```

### NativeOptions API 参考

`NativeOptions.lua` 模块把以上所有内容封装成了一套简洁的 API:

| 函数 | 说明 |
|---|---|
| `Opt.group(title, desc, {mode=id, key=key})` | 创建一个具名的设置分组。`mode` 把它关联到某个训练模式 ID。 |
| `g:toggle(key, title, desc, default, cb, opts)` | 布尔开关(Off/On spin)。数值变化时触发 `cb(value)`。 |
| `g:choice(key, title, desc, options, default, cb, opts)` | 带命名选项的 spin。`default` 和 `cb` 的值都是从 1 开始计数的。`options` 可以是一个函数。 |
| `g:slider(key, title, desc, min, max, default, cb, opts)` | 整数滑条。 |
| `g:button(key, title, desc, cb, refresh)` | 动作按钮。`cb()` 可以返回 `"close"` 来关闭窗口。`refresh=true` 会在按下后重建窗口(用于动态标题)。 |
| `g:get(key)` / `g:set(key, v)` | 以编程方式读取/写入某个条目的值。 |
| `Opt.open(title)` | 在对战画面之上打开该具名分组的窗口(如果尚未处于暂停状态)。 |
| `Opt.open_after_unpause(title)` | 排队一次打开操作,等待对战恢复并稳定 5 个 tick 后再执行。 |
| `Opt.close()` | 关闭当前窗口。 |
| `Opt.set_mode_selector(names, ids, get, set)` | 在组合窗口“SF6 Tools”顶部安装一个“Training mode”spin。 |
| `Opt.rebuild()` | 拆除并重建 unit 树(用于动态内容)。 |
| `Opt.message_guid(str)` | 创建一个解析为 `str` 的伪造 GUID(可供其他模块复用)。 |

条目选项(`opts` 表):
- `deferred = true` -- 回调只会在窗口关闭、对战恢复之后才触发(用于录制导入这类重量级操作)。
- `getter = function()` -- 在窗口打开时调用,用于从外部状态刷新条目的值。

---

## 6. 技巧 2 -- 暂停菜单行与标签页(NativePauseMenu)

把行注入到训练暂停菜单的“Basic Settings”标签页中,并添加全新的标签页。

[![Pause menu with injected row](../img/pause_menu_injected_row.png)](../img/pause_menu_injected_row.png)
*Basic Settings 底部的“SF6 Tools Shortcut Settings”行,带有滚动指示器。顶部可以看到多出来的一个标签页圆点
(我们的“SF6 Tools”标签页)。*

### 工作原理

训练暂停菜单由 `TrainingManager._UIData._MenuData` 驱动,这是一个 `TrainingMenuData[8]` 数组(每个标签页
一个元素)。每个标签页的行分别位于 `_ChildData`(静态)和 `DynamicChildData`(动态,在运行时添加)中。
游戏提供了 `AddDynamicMenu(funcType, data, action)` 用于追加行。

我们的行使用 `FuncType = 345`(这是我们自己选定的 `DYNAMIC` 值;游戏自身的标签页使用 1..8)。游戏会调用
`TrainingMenuFunc` 的方法来渲染这些行并与之交互:

| 方法 | 时机 | 我们要做的事 |
|---|---|---|
| `ViewUpdate(param, data, i)` | 每帧、每一行 | 记录当前正在处理的是我们的哪一行(`current = item`) |
| `GetIsActive(ftype)` | 每一行 | 返回 `1`(激活状态) |
| `GetOptionText(ftype)` | 每一个 spin 行 | 返回当前选项的文本 |
| `GetOptionIndex(ftype, wanted, ftype)` | spin 变化时 | 调用 `item.set(wanted)`,返回 `wanted` |
| `Function(ftype, param, viewData, value)` | 确认/decide 时 | 对于按钮:调用 `item.on_decide()`,返回 0(停留)或 1(关闭菜单) |

行是通过其 `TrainingMenuData` 的 `_MessageID` GUID 来识别其地址的(因为 `AddDynamicMenu` 会克隆数据 --
原始地址会丢失)。

### 添加一个 Spin 行

```lua
local PM = require("func/NativePauseMenu")

PM.spin(
    "Training mode",                           -- title
    "Which training script drives the dummy.", -- guide text (bottom of screen)
    { "DISABLED", "HIT CONFIRM", "REACTION DRILLS" },  -- options
    function() return current_mode_index end,  -- getter (0-based)
    function(i) set_mode(i) end                -- setter (0-based)
)
```

### 添加一个按钮行

```lua
PM.button(
    "SF6 Tools Shortcut Settings",
    "Open the shortcut configuration menu.",
    function() NativeShortcuts.open() end,   -- on_decide
    true,   -- keep_open: the pause menu stays up
    true    -- in_tab: also appears in our "SF6 Tools" tab
)
```

### 添加一个完整的标签页(Page)

```lua
local pg = PM.page("Distance Viewer", "Distance Viewer settings.")

pg:toggle("Display P1", "Show P1 distance overlay.",
    function() return config.p1_enabled end,
    function(v) config.p1_enabled = v; save() end)

pg:spin("Red Zone", "Attack used for the red zone.",
    function() return get_move_names() end,   -- options (function = dynamic list)
    function() return selected_move_index end,
    function(i) select_move(i) end,
    20)  -- capacity: max option count (row built once, options filled live)

pg:button("TELEPORT", "Move both players to this distance.",
    function() teleport() end,
    false)  -- keep_open = false: closes the pause menu after the action

pg:value("Distance", "Current distance between players.",
    function() return string.format("%.1f", current_distance) end)

pg:label("Press L1+R1 to toggle overlay.", "Keyboard: F5.")
```

### 标签页的安装

标签页是通过把 `_MenuData` 替换成一个更长的数组(游戏原本的 8 个 + 我们自己的标签页)来安装的。我们的每一个
标签页都是一个 `_FuncType = 345`、`_ChildData` 为我们自己的行对象的 `TrainingMenuData`。游戏会在标签条中
渲染该标签页、显示它的页面圆点,并处理焦点/导航。

安装动作是在菜单**关闭**的状态下进行的(规则 3)。`NativePauseMenu` 每 60 tick 检查一次 `tabs_present`,
如果游戏重建了菜单数据(角色切换等情况),就会重新安装。

### 14 行滚动 Bug

Basic Settings 标签页原本有 13 个自带行。再添加一行就变成 14 行,而这**正好**落在滚动视图的底部
(`_ViewTop 37.5 + _ViewSize.h 805 = 842.5 = 第 13 行的底部`)。但视觉遮罩要高出 20 px,所以游戏永远不会
滚动,最后一行就会被裁剪掉。

**修复方法:** 在暂停期间把 `_ViewSize.h = 745` 写入 `UIPartsGroupScroll`(`ui11200` agent 的根 item)。
视图中少显示一行,游戏自身的 `ScrollFocusItem` 就会滚动到它。13 行的标签页依然能完整容纳(相等 = 可见)。

```lua
-- In LateUpdateBehavior, while paused:
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    if go and tostring(go:call("get_Name")) == "ui11200" then
        local root = agent:get_field("_RootItem")
        if root then
            local off = root:get_type_definition():get_field("_ViewSize"):get_offset_from_base()
            if root:read_float(off + 4) > 745 then
                root:write_float(off + 4, 745)
            end
        end
        break
    end
end
```

### 动态标题

以**函数**形式给出的标题和引导文字,会在 `TrainingManager.OpenMenu`(暂停菜单的唯一入口点,运行在游戏线程
上)的 pre-hook 中被重新求值。随后 hMsg hook 会把这些 GUID 解析为最新的文本。

### NativePauseMenu API 参考

| 函数 | 说明 |
|---|---|
| `PM.spin(title, guide, options, get, set)` | 向 Basic Settings 添加一个 spin 行。`get`/`set` 从 0 开始计数。 |
| `PM.button(title, guide, on_decide, keep_open, in_tab)` | 添加一个按钮行。`in_tab=true` 会在“SF6 Tools”标签页中复制一份。 |
| `PM.page(title, guide, opts)` | 创建一个新的标签页。返回一个 `Page` 对象。`opts.tab=false` 表示只作为容器,不安装标签页。 |
| `pg:spin(title, guide, options, get, set, capacity)` | 页面上的 spin 行。`options` 可以是一个函数。 |
| `pg:toggle(title, guide, get, set)` | 页面上的 Off/On 开关。 |
| `pg:number(title, guide, min, max, step, get, set, fmt)` | 带离散步长的数值行。 |
| `pg:button(title, guide, on_decide, keep_open)` | 页面上的按钮行。 |
| `pg:value(title, guide, fn)` | 只读行,文本来自 `fn()`。 |
| `pg:label(title, guide)` | 静态文本行。 |
| `PM.tab_button(title, guide, on_decide, keep_open)` | 只出现在“SF6 Tools”标签页中的按钮。 |

### 限制

- **行池:** 游戏每个标签页大约创建 20 个 UIParts。超出池所能承受的行数将不会被渲染。请把每个页面控制在
  **13 行以内**(游戏自身的标签页从不超过 13 行)。
- **标签条:** 游戏的标签条在视觉设计上是给 8 个标签页用的。多加 1-2 个可以正常工作(圆点、焦点、导航都没
  问题);多加约 3 个以上标签条可能会显得拥挤。

---

## 7. 技巧 3 -- 驱动游戏 HUD(NativeHud)

用你自己的内容替换训练 HUD 中“Damage / Combo Damage / Attack Type”面板的文字以及回合计时器的数字,同时
沿用游戏自身的字体、精灵图和布局。

[![Native HUD panel](../img/native_hud_panel.png)](../img/native_hud_panel.png)
*训练 HUD,中央顶部为原生的伤害面板,显示着“Damage”、“Combo Damage”和“Attack Type”标签。回合计时器用
原生数字精灵显示“99”。*

### 伤害面板

widget `app.training.UIWidget_TMAttackInfo`(可通过 `TrainingManager._ViewUIWigetDict` 找到)拥有一个包含
3 行的 `AttackInfos` 数组。每一行都有 `LeftText`、`CenterText` 和 `RightText`(都是 `via.gui.Text` 控件)。

**关键点:** 游戏每一帧都会重写**两侧**的文字(`LeftText`、`RightText`)。你无法与之对抗。正确做法是:
**隐藏**两侧的文字(`set_Visible(false)`),只写**中间**的文字 -- 游戏只在命中/防御事件时才会碰它(而你可以
在下一个 tick 重新写回你的文字)。

```lua
local NativeHud = require("func/NativeHud")

-- Take ownership
NativeHud.claim("my_mod")

-- Write three rows (l/c/r parts are joined into the centre text with spacing)
NativeHud.set(0, "l", "SCORE: 3")
NativeHud.set(0, "c", "HIT CONFIRM")
NativeHud.set(0, "r", "TOTAL: 10")
NativeHud.set(0, "c", nil, 0xFF00FF00)   -- green colour (ABGR)

NativeHud.set(1, "l", "HIT: 80%")
NativeHud.set(1, "r", "BLOCK: 20%")

NativeHud.set(2, "c", "WAITING")

-- Give it back when done
NativeHud.release("my_mod")
```

### 回合计时器

`app.UIBattleHud_Timer` 拥有由 `set_UVPatternNo(digit)` 驱动的数字精灵控件(`e_texture_number_001`、
`010`、`100`)。无穷符号是 `c_infinite`(在我们驱动数字期间通过 `set_ForceInvisible` 把它隐藏起来)。

```lua
NativeHud.set_timer(29, 0xFF0000FF)   -- show "29" in red
NativeHud.set_timer(nil)               -- give the timer back
```

对于大于等于 100 的数字,该模块会调整精灵的位置和缩放(游戏通常只用两位数字)。

### 关键安全事项(四条 AV 规则)

这四条规则各自对应着 2026 年 8 月 30-31 日通过二分定位到的一次崩溃:

1. **暂停时不进行 GUI 写入** -- 当 `TrainingGamePaused` 或 `NativeOptionsWindowOpen` 变为 true 时,静默地
   丢弃所有缓存。不要尝试进行“告别性写入”。
2. **只在 `OpenMenu` 的 pre-hook 处恢复文字** -- 这是唯一能保证 HUD 控件仍然存活的时机(在随后的拆除动作
   之前)。
3. **监控 `_CurrentPauseTypeBit`** -- 任何变化都会触发 HUD 重建。丢弃所有缓存并等待 20 个 tick。
4. **`sdk.is_managed_object` 是不够的** -- 它在被重新分配的内存块上仍会通过检测。始终把 GUI 写入包在
   `pcall` 里。

### NativeHud API 参考

| 函数 | 说明 |
|---|---|
| `NativeHud.claim(name)` | 取得 HUD 的所有权。同一时间只能有一个所有者。 |
| `NativeHud.release(name)` | 归还一切(恢复原始文字)。 |
| `NativeHud.set(row, col, text, color)` | 设置文字/颜色。`row` = 0-2,`col` = "l"/"c"/"r",`color` = ABGR。 |
| `NativeHud.clear()` | 清除所有待显示的文字。 |
| `NativeHud.set_timer(n, color)` | 驱动计时器数字(0-999)。传 `nil` 会恢复游戏自身的计时器。 |
| `NativeHud.request_text_visible(bool)` | 显示/隐藏面板文字(用于不使用 HUD 的模式)。 |
| `NativeHud.available()` | 当面板控件已解析完成时为 true。 |

---

## 8. 技巧 4 -- 借用 GUI 元素(NativePopup)

用游戏自身的 `via.gui` 元素来构建屏幕弹窗、条状 UI 和边框 -- 而不创建任何新元素。这项技巧被用在了
NativeTopBar(顶部的模式按钮)、NativeBottomBar(底部的动作按钮,目前已禁用)以及 NativePopup(通知边框)
上。

[![Borrowed popup](../img/borrowed_popup.png)](../img/borrowed_popup.png)
*一个由借用的 GUI 元素拼装而成的弹窗:“Match Found”霓虹边框(Scale9Grid)、一个深色的 Rect 主体,以及来自
休眠 agent 的文字元素。*

### 为什么不直接创建元素?

- `sdk.create_instance("via.gui.Text")` 在正确的父级和根节点下能够渲染,但**无法在脚本重置后存活**
  (REFramework 会释放它托管的实例,留下一个悬空的子节点,一调用 `set_Message` 就会崩溃)。
- `Panel:call("create_instance", ...)` 和 `control:call("duplicate")` 从 Lua 调用时都不会渲染(引擎需要一个
  我们无法触发的注册步骤)。
- 只有**引擎自己构建**的元素(在 agent 初始化期间由预制体生成)才具备渲染所需的完整内部状态。

### 具体做法

1. **找到引擎构建过、但在你当前游戏模式下从不显示的多余元素**。常驻的匹配 agent
   (`Resident_Cmn_MatchingStandby`、`Resident_Cmn_MatchingSelect` 等)有一些隐藏的子节点(Battle Hub 皮肤、
   在线待机皮肤),它们已被加载,但在 Fighting Ground 中不可见。
2. **从一个可见的来源复制外观**:`source:call("copyProperties", spare)`。这会复制九宫格图集、字体槽位、
   发光参数和颜色设置。
   > **警告:** 方向是 `来源 -> 目标`(来源的属性会被复制**到**这个多余元素上)。如果方向反了,会在无声无息
   > 中破坏掉来源元素。
3. **重新挂载到一个存活的 host 之下**:`host:call("addChild", spare)`。这个 host 必须是可见的,并且处于
   渲染树中。`BattleHud_Timer` 的 `c_main` 是个不错的选择(它在训练模式中始终存在,并且有可用的字体槽位 8)。
4. **在 `LateUpdateBehavior` 中驱动位置、尺寸、颜色和优先级**。

### 哪些方法可行,哪些不可行

| 操作 | 结果 |
|---|---|
| 把一个 Rect 从一个 agent `addChild` 到另一个 | 可行(前提是它不是其他地方的子节点;如有需要,先 `remove()` 再 `addChild`) |
| `addChild` 一个 Text | 只能成功**一次**。对 Text 调用 `remove()` 会永久剥离它的字体注册 -- 它会变成一个空白矩形。Text 只能移动一次。 |
| `addChild` 一个 Scale9Grid | 可行。`remove()` 会剥离图集。只能移动一次。 |
| `copyProperties` Scale9Grid -> Scale9Grid | 可行。会复制九宫格图集、边框矩形和渲染模式。 |
| `copyProperties` Text -> Text | 可行。会复制字体槽位、描边、发光设置。 |
| 设置 `MaskType = 0` | 必须的。被借用的控件可能带着来自其原始父级的遮罩,会把整个 host 裁剪掉。 |
| 设置 `ControlPoint = 5` | 居中锚点(定位更简单)。 |

### 底部栏的失败与教训

NativeBottomBar(屏幕底部的动作按钮)已经构建完成并且能正常工作,但目前处于**禁用**状态(设置
`NativeBottomBar_Experimental = true` 可启用)。存在的问题:

1. **文字池太小。** 在所有常驻 agent 中,只有大约 4 个 Text 元素在被“收养”后不会在 `set_Message` 时崩溃。
   而底部栏每个按钮都需要一个文字元素。
2. **文字会被它们原本所属的 widget 重写。** `BattleHud_HitCount/e_txt_score` 在被收养后能正常渲染,但
   `set_Message` 会抛出 AV。`BattleHud_MatchWonNumber` 的文字会在连段过程中被覆盖(变通方案:每 60 tick
   重新写回标签)。
3. **脚本重置会释放 sdk.create_instance 创建的文字。** 即使调用了 `add_ref()`,引擎的 GC 或 REFramework 的
   清理逻辑仍会释放创建出的文字实例,在 host 下留下悬空的子节点。

**教训:** 借用元素的 UI 对于小规模的部分是可行的(1-3 行的弹窗、带固定标签的顶部栏),但无法扩展到动态的
多按钮栏。对于设置类 UI,请改用技巧 1 和技巧 2。

---

## 9. 技巧 5 -- 复用整个游戏菜单(NativeShortcuts, NativeDialog)

### A. Shortcut Settings 菜单替换(NativeShortcuts)

游戏的 Shortcut Settings 菜单(`app.ShortcutSetting`)会从两个数据列表中显示手柄/键盘绑定:
`_SettingUserData.Data`(定义)和 `SettingSaveData.ItemDataList`(状态)。在菜单打开期间,把这两个列表
**替换**成我们自己的,就能得到一个完全可用、显示我们自己那些行的按键绑定菜单。

**工作原理:**
1. 为我们自己的动作构建 `ShortcutSettingData` 和 `ShortcutSettingItemSaveData` 数组。
2. 在 `ShortcutSetting.Start(0)` 之前,把引擎的列表替换成我们自己的。
3. 在替换期间屏蔽 `ShortcutSaveData.Save` 和 `ShortcutSetting.Save`(游戏不能把我们的行当作真正的快捷键
   持久化保存)。
4. 菜单关闭时(`get_IsOpening() == false`),恢复原始列表,并把绑定推送到我们自己的热键框架中。

### B. 两栏式对话框劫持(NativeDialog)

> **状态:** 已经实现并且能正常工作,但**在项目中被否决**,转而采用 NativeOptions 窗口(技巧 1)。这里记录
> 下来是作为该技巧及其坑点的参考。`NativeDialog.lua` 仍留在仓库中,但未被使用。

“P1 Control Settings”对话框(`app.UIFlowKeyConfig.Menu`)左侧是一个分类 spin,右侧是一个可滚动的行列表。
在我们的对话框处于激活状态时 hook 它的 `Param` 方法,就可以让它显示我们自己的分类和行。

**关键教训 -- 规则 4 的实战体现:** 第一版通过 `sdk.create_instance` 创建 `SettingParam` 实例,却只填充了
整数字段。引擎的 `MakeListIndexToParamIndex` 尝试读取 `Name`(一个字符串属性)时得到 null,抛出了
`NullReferenceException`。修复方法:用 `Param.CloneSettingParams(sourceArray)` **克隆**游戏自己的数组,
只通过 hook 覆盖文本相关的 getter(`GetName`、`GetIcon`、`GetInputIcon`、`GetComment`)。

**关键 hook:**
- `GetBattleSettingParams`(post-hook):捕获游戏的数组作为克隆源,针对当前分类返回我们的克隆。
- `SpinPresetChanged`(pre-hook,SKIP):设置我们的分类,`SetSettingParams(clone)`、`UpdateListSetting()`、
  `UpdateTextSpinPreset()`。
- `SettingParam.GetName/GetIcon/GetInputIcon/GetComment`:对已映射的行返回我们的文本,对未映射的克隆槽位
  返回 `""`。
- `UIAgent.InputDecide`:拦截右侧列表上的确认操作。对于 spin 条目:切换到下一个选项。对于按钮:执行对应
  动作。
- 在激活期间屏蔽所有持久化操作(`SaveSettingParams`、`SaveOther`、`RevertSettings` 等)以及变更检测
  (`CheckChanges` -> 0、`EqualSettings` -> true)。

**什么时候该用这个而不是技巧 1:** 只有当你真正需要两栏式布局时(左侧分类,右侧条目)。对于大多数设置需求,
技巧 1 更简单也更可靠。

---

## 10. 亲自拆解一个游戏菜单

本指南中的这些技巧,都是通过用一次性 Lua 脚本探测游戏运行中的 UI 而发现的。下面就是这个工作流。

### 工具

- **`sf6.py`**(位于 `agent/sf6.py`):一个与 REFramework 的 websocket 服务器通信的 Python 脚本。主要命令:
  - `sf6.py run agent/tmp/my_probe.lua --wait my_probe` -- 部署一个探测脚本,并等待它写出
    `data/my_probe.json`。
  - `sf6.py shot` -- 截图(保存到 `agent/shots/`)。
  - `sf6.py reset` -- 重置所有脚本(清除探测用的 hook)。
  - `sf6.py logs` -- 读取 `re2_framework_log.txt` 中的错误信息。
  - `sf6.py state` -- 导出当前游戏状态(flow、模式、角色、位置、HP)。
  - `sf6.py tap ESC` / `sf6.py tap E` / `sf6.py tap A` -- 发送按键点击以导航菜单。
- **探测脚本**(位于 `agent/tmp/`):把数据导出为 JSON 后就退出的简短 Lua 文件。

### 探测工作流

1. **导航到你想要检查的菜单**:`sf6.py nav training`,然后用 `sf6.py tap ESC` 打开暂停菜单,用
   `sf6.py tap E`/`sf6.py tap A` 切换标签页。

2. **枚举 UIAgent**,找出是谁拥有这个菜单:

```lua
-- agent/tmp/probe_agents.lua
local out = {}
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    out[#out + 1] = {
        name = go and tostring(go:call("get_Name")) or "?",
        type = agent and agent:get_type_definition():get_full_name() or "?"
    }
end
json.dump_file("__OUT__.json", out)
```

3. **一旦知道了 agent,就导出它的控件树:**

```lua
-- agent/tmp/probe_ctrl_tree.lua
local function dump(ctrl, depth)
    if not ctrl or depth > 20 then return nil end
    local r = {
        name = tostring(ctrl:call("get_Name")),
        type = ctrl:get_type_definition():get_name(),
        visible = ctrl:call("get_Visible"),
        size = { w = ctrl:call("get_Size").w, h = ctrl:call("get_Size").h }
    }
    local children = {}
    local c = ctrl:call("get_Child")
    while c do
        children[#children + 1] = dump(c, depth + 1)
        c = c:call("get_Next")
    end
    if #children > 0 then r.children = children end
    return r
end
-- ... find the agent, get_ControlMain(), dump(main, 0) ...
json.dump_file("__OUT__.json", tree)
```

4. **导出感兴趣对象的类型定义**(字段与方法):

```lua
local function dump_type(td)
    local fields, methods = {}, {}
    for _, f in ipairs(td:get_fields()) do
        fields[#fields + 1] = { name = f:get_name(), type = f:get_type():get_full_name() }
    end
    for _, m in ipairs(td:get_methods()) do
        local params = {}
        for _, p in ipairs(m:get_param_types()) do params[#params + 1] = p:get_full_name() end
        methods[#methods + 1] = { name = m:get_name(), params = params, ret = m:get_return_type():get_full_name() }
    end
    return { name = td:get_full_name(), fields = fields, methods = methods }
end
```

5. **对某个协议进行 hook 追踪**,查看游戏在其 flow 上都调用了些什么:

```lua
-- Hook every method of a Param type, log which ones fire
local td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")
for _, m in ipairs(td:get_methods()) do
    pcall(function()
        sdk.hook(m, function(args)
            log.info("PARAM CALL: " .. m:get_name())
        end, function(rv) return rv end)
    end)
end
```

> **警告:** 在不同的 hook 探测之间要重置脚本(`sf6.py reset`)。上一次探测遗留下来、不再有响应的 hook 可能
> 会导致行显示空白、回调失效,甚至崩溃。

### 常见坑点

- 在某些 REFramework 版本上(比如 LL5271 websocket 版),`System.Int32[].GetValue(i)` 会返回 `nil`。可以
  尝试 `get_element(i)`、原始内存读取(`read_dword(0x20 + 4*i)`),或者索引运算符 `array[i]`。
- 由上一次脚本加载所注册的 `hMsg` GUID 文本,会在 Reset Scripts 时失效。如果你正在用伪造的 GUID 进行探测,
  重置之后它们会显示为空白,直到探测脚本重新注册它们。
- 探测脚本要放在 `agent/tmp/` 中,绝不能放进 `autorun/`。`autorun/` 中的脚本会在启动时自动加载,并且不会
  被 `sf6.py reset` 重置;而 `autorun/` 子目录中的脚本,Reset Scripts 根本不会重新加载它们。

---

## 11. 故障排查

| 症状 | 原因 | 解决方法 |
|---|---|---|
| 打开/关闭窗口后出现**黑屏** | 持续暂停状态下淡入淡出动画被卡住 | 在 `CreatedObject` 上设置 `<ImmediateFade>k__BackingField = true`(见第 5 节)。如果对话框在 30 个 tick 后仍未消失,就释放暂停。 |
| 更改窗口内容后出现 **RIP 0**(空指针崩溃) | 重新填充了一个已打开的对话框页面(规则 3) | 先 `End()` 对话框,等待 `OptionDialog` agent 消失,再 `Start()` 一个新的。 |
| **set_Message 中出现 AV** | 写入了一个已被释放的 `via.gui.Text` 控件 | 暂停/窗口打开时丢弃所有缓存(规则 2)。绝不要在暂停切换期间写入。 |
| 行显示为空白,带有**圆圈斜杠图标** | `GetIsActive` 没有针对我们的 `FuncType` 给出响应 | hook `TrainingMenuFunc.GetIsActive`:针对你的 FuncType 返回 `1`。 |
| 暂停菜单中的行**无法获得焦点** | `_FuncType` 不在游戏预期的枚举范围内 | 始终统一使用 `345`(DYNAMIC)。确保 `TrainingMenuData` 上的 `IsEnabled = true`。 |
| 菜单行中出现**空白文本** | GUID 未注册(首次加载)或在 Reset Scripts 后丢失 | 在 `re.on_script_reset` 中或在构建时重新注册 GUID。检查 `message_guid()` 是否在 unit 创建之前就被调用了。 |
| 按下按钮时出现 **“Restore Default Settings?”弹窗** | 按钮使用了 `EventType.SettingReset`,但没有拦截 decide | hook `GetFocusDecideEventType`:针对你按钮的 TypeId 返回 `Invalid (0)`。 |
| Basic Settings 中**第 14 行被裁剪** | 滚动视图的 `_ViewSize.h` 太大 | 在菜单打开期间把 `_ViewSize.h = 745` 写入 `UIPartsGroupScroll`。 |
| 窗口打开时**数值被重置为默认值** | 游戏针对你的 TypeId 触发了 `LoadValueEvent` | hook `OptionValueUnit.LoadValueEvent`:对你的 TypeId 跳过处理。 |
| 窗口打开了,但**对战没有暂停** | `PauseType` 错误,或暂停请求被拒绝 | 使用类型 `8`(`BATTLE_MENU_PAUSE`)。检查你是否已经处于另一种暂停状态。 |
| **离开暂停菜单时 Options 窗口又打开了** | 没有在缓冲帧内屏蔽 `OpenMenu` | hook `TrainingManager.OpenMenu`:在你窗口关闭后的约 20 帧内跳过处理。 |
| **内存泄漏**(Lua 内存持续增长) | 热路径中使用了 `pcall(function() ... end)` | 替换成 `pcall(named_func, args)`(规则 5)。 |
| 每隔 N 秒出现**帧时间尖峰** | `fs.glob` 被放在了定时器里 | 把 `fs.glob` 调用只保留在窗口打开路径中(规则 7)。 |
| 模式切换后,暂停菜单的 spin 显示**错误的值** | getter 返回了过期的索引 | 当模式在外部发生变化时,重建并重新安装标签页。 |
| NativeHud 文字**颜色不对** | 使用了 RGB 而不是 ABGR | 所有 `via.gui` 颜色都是 **ABGR**(alpha 在最高字节,然后是 blue)。`0xFF0000FF` = 不透明的红色。 |

---

## 12. 附录 -- 类型与枚举参考

### app.Option 枚举

| 枚举 | 使用到的值 |
|---|---|
| `app.Option.UnitInputType` | `SpinText`(带箭头的 spin)、`Slider`(横向滑条)、`Button_Type1`(子菜单 / 左对齐)、`Button_Type2`(动作 / 居中)、`Button_Type0`(单选弹窗,对自定义 ID 不生效) |
| `app.Option.DecideEventType` | `OpenSubMenu`(进入子菜单)、`OpenBattleHudSetting`(打开 HUD 窗口)、`SettingReset`(按钮 / 恢复)、`OpenRadioButton`(弹出列表,对自定义 ID 不生效)、`Invalid`(0,不做任何事) |
| `app.Option.SettingDataType` | `Value`(带有 min/max 的数值) |
| `app.Option.TabType` | `General`(“SF6 Tools”所在的标签页) |

### app.training 类型

| 类型 | 关键字段 |
|---|---|
| `TrainingMenuData` | `_Type`(0=TEXT_ONLY,1=SPIN)、`_FuncType`(1..8 为游戏自带,345 为我们自己的)、`_MessageID`(GUID)、`_GuideMessage`(GUID)、`_ChildData`(TrainingMenuData[])、`DynamicChildData`(List)、`IsEnabled`、`_Interval`、`_GuidIcon`、`VisibleCase` |
| `TrainingMenuFunc` | 方法:`ViewUpdate`、`GetIsActive`、`GetOptionText`、`GetOptionText2`、`GetOptionIndex`、`IsValueType`、`GetVisibleCase`、`IsChangedValue`、`Function` |
| `TrainingPauseMenuUserData` | `_MenuData`:`TrainingMenuData[]`(每个标签页一个) |

### app.UIFlowOptionBGDialog

| 类型 | 关键成员 |
|---|---|
| `SettingData` | `TopUnit`、`SupportMode`(32)、`UseBattleHudBG`(我们的窗口设为 false)、`PlayerIndex` |
| `Param` | `GetFocusUnit()`、`GetFocusDecideEventType()`、`SetupDispUnits()`、`FlowEvent_ResetCurrentUnits()`、`CreatedObject()`、`OptionUnits`(parts 数组) |
| 静态 | `Start(SettingData, bool)` -> `IUIFlowHandle` |

### PauseManager

| 暂停类型 | 值 | 作用 |
|---|---|---|
| `DIALOG_PAUSE` | 1 | 只暂停对话框作用域内的对象(不暂停对战) |
| `BATTLE_MENU_PAUSE` | 8 | 暂停对战(与真正的暂停菜单相同)。在 `_CurrentPauseTypeBit` 中对应的位 = 64。 |
| `BATTLE_TRAINING_PAUSE` | 11 | 在训练菜单上下文之外会被拒绝 |

### EConfigInitLayout(起始位置)

| 名称 | 值 |
|---|---|
| `CENTER` | 0 |
| `RIGHT` | 1 |
| `LEFT` | 2 |
| `MANUAL` | 3 |

### 源文件

| 模块 | 路径 | 作用 |
|---|---|---|
| NativeOptions | `autorun/func/NativeOptions.lua` | Options 对话框窗口(技巧 1) |
| NativePauseMenu | `autorun/func/NativePauseMenu.lua` | 暂停菜单行与标签页(技巧 2) |
| NativeHud | `autorun/func/NativeHud.lua` | 伤害面板与计时器(技巧 3) |
| NativePopup | `autorun/func/NativePopup.lua` | 借用元素的弹窗(技巧 4) |
| NativeShortcuts | `autorun/func/NativeShortcuts.lua` | Shortcut Settings 替换(技巧 5A) |
| NativeDialog | `autorun/func/NativeDialog.lua` | KeyConfig 对话框劫持(技巧 5B) |
| NativeTopBar | `autorun/func/NativeTopBar.lua` | 模式选择条(借用元素,已禁用) |
| NativeBottomBar | `autorun/func/NativeBottomBar.lua` | 动作按钮条(实验性,已禁用) |
| GameState | `autorun/func/GameState.lua` | 暂停检测(`GS.in_pause_menu`) |
| Training_ScriptManager | `autorun/Training_ScriptManager.lua` | 总控脚本(模式切换、注册) |

---

## 13. 致谢

- **Wael3rd** -- 所有原生 UI 模块(NativeOptions、NativePauseMenu、NativeHud、NativePopup、
  NativeShortcuts、NativeDialog、NativeTopBar、NativeBottomBar)、探测工作流、崩溃调查,以及本指南。
- **mfyk** -- OptionManager 注入技巧(把 OptionSettingUnit 注入 UnitLists、伪造 GUID 文本 hook、
  OpenBattleHudSetting 窗口)。2026 年公开分享,允许公开使用。是技巧 1 的基础。
- **alphaZomega** -- 开发过程中所使用的 REFramework 工具与知识库。
- **cdjay** -- 对 SF6 Tools 代码库的贡献(BCM catalog、现代式指令记法、指令显示格式),在
  Training_ScriptManager 中被引用。
- **praydog** -- REFramework 本身。
- **LL5271** -- REFramework-Websockets 分支(本文使用的 `dinput8.dll` 构建):其 websocket 服务器使远程探测工作流(`sf6.py run / state / shot`)以及本指南中的所有剖析成为可能。

---

*更新日志:2026-08-31 -- 初始版本。*
