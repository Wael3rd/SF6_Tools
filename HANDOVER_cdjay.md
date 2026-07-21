# Convergence Handover — Wael → cdjay
# 融合交接说明 — Wael 致 cdjay

*(English first, 中文在后)*

---

## 🇬🇧 English

### Dear cdjay,

First, thank you. The work you have shared — the BCM/AC toolchain, the modern-notation
data, DynamicRecords, the online-safety hooks, the Validator architecture — has been a
real gift to this project. Building on your foundation made everything below possible,
and I want to be clear that this is a shared result, not mine alone.

This document is a complete, honest account of everything I have integrated on my branch,
the decisions I made, and — where I kept a different approach — an explanation of *why*, so
you can judge for yourself. **My goal was to make my branch a 100% superset of
`SF6_TOOLS_CC`**, so that we truly share one core with two language front-ends. I believe I
have now integrated everything I reasonably can. **I am handing the initiative back to you**:
please review whether anything is missing, and take it from here to finish integrating
whatever you wish (including any SF6CC-specific links or systems on your side).

---

### 1. What was integrated from your fork

Everything below was ported from your `HEAD 9b851c5`, verified (syntax + declaration order
+ a strict quote scan), and — except where noted — **tested in-game**.

| Subsystem | Status | Notes |
|---|---|---|
| **CTTimelineSequenceNormalizer** | ✅ Ported, tested | Compacts repeated / multi-hit normals into single steps via the recorded press timeline. Wired fail-open into `assign_groups`. |
| **Trial defense-settings restore** | ✅ Ported, tested | Disables the dummy's auto Drive-Parry / Drive-Rush during a trial, restores the user's Defense-tab settings afterwards. |
| **Dummy crouch + guard inference** | ✅ Ported, tested | Infers crouch/guard from environment / scene status / combo text, keeping our jump handling. |
| **Modern-notation unresolved audit** | ✅ Ported, tested | Logs the act_ids the modern_display map cannot resolve, so coverage gaps can be found. Adapted to our `ModernDisplay.lua` flow. |
| **Forward-compat schema guard** | ✅ Ported, tested | `warn_newer_schema`: a combo file written with a newer `_xt_meta.schema` warns once and still loads best-effort, instead of breaking silently. Important for our shared JSON format. |
| **BCM action catalogs (30 chars)** | ✅ Generated with your toolchain | Node toolchain, v2 compiler, 0 fails. Catalog and manual exceptions coexist as two independent toggles. |
| **Modern notation (v9 data, 30 chars)** | ✅ Integrated | 3 display modes (Shortcut / Motion / Both), auto-detection from the player's control type, button icons. |
| **DynamicRecords** | ✅ Ported + made bilingual | Your training-config import/export. Now EN/中文; **your "小吞MOD" attribution is preserved in both languages** — credit stays with you. |
| **11 upstream fixes** | ✅ Ported | SharedHooks online guard + generation, HitConfirm, UTF-8 D2D centering, hide-REF-menu-on-boot, SheldonsBoxes online guard, and more. |

---

### 2. Subsystems that were already covered — and one technical arbitration

In a few cases I found that my branch already solved the same problem, sometimes through a
different mechanism. I want to explain these carefully and respectfully, because in two of
them I concluded a different approach was preferable **for a specific technical reason**, not
as a judgement of your work. Please challenge me if you see it differently.

#### 2.1 HP restore — already exact to the point

Both our systems restore HP to the exact point (`vital_new = exact value`, damage =
`start_hp − min_hp`), never by percentage. The HP-restore core was already present on my
side, identical in effect. Nothing to port here.

#### 2.2 DEMO replay under stun/DI — *arbitration in favour of raw input replay*

This is the one place I want to explain most carefully, because both approaches are valid.

- **Your `CTStunDemoRuntime`** replays the combo as **timeline steps** (each step has a frame
  duration) and, because the script tick can drift from the engine clock during hitstop,
  uses `catch_up_missed_engine_frames` to resynchronise. This is a sound design.
- **My raw DEMO** records the literal per-frame input bitmask (`pl_input_new`, one `uint16`
  per engine input tick) and replays it on the **same engine hook** used for recording.

The reason I kept raw replay as the primary path is architectural: because record and replay
are both gated on the same engine input hook, **drift is impossible** — during stun / DI /
DRC hitstop the hook simply does not fire, so recording and replay pause and resume in
lockstep. It reproduces the exact input stream, including DRC-cancel timing. Your `catch_up`
solves a drift problem that this architecture does not have.

**Important:** I did not discard your work. Your `CTStunDemoRuntime` is fully present on my
branch and serves as the **fallback for legacy combos that have no `raw_inputs`**. New combos
use raw replay; older ones use your timeline system. It is the best of both.

#### 2.3 Same-action continuation — covered by a lighter mechanism

Your `is_same_action_continuation_step` / `ct_try_skip_unreported_same_action_pressure_step`
handle a repeated same move (e.g. cr.LK × 3) where the engine reports the same
`action_instance`. My branch solves the same case differently: via the **combo count**
(`Validator.check_combo`, `current_combo >= expected_combo` distinguishes each repetition)
plus the `CTTimelineSequenceNormalizer` you authored. Same result, and it avoids threading
`action_instance` through the ~62 call sites it touches in your matcher. So I did not port
this one — not because it is wrong, but because the outcome is already achieved and the port
would be invasive to a validator that is working.

#### 2.4 Modern-notation rendering — kept the lighter resolver

Your `ComboTrials_D2D` modern-resolution engine (~1300 lines) is powerful. On my side, a
small `ModernDisplay.lua` (act_id → modern-notation string) produces the same rendered
result in icon mode, so I kept it — **but I did port your unresolved-audit layer on top of
it** (see §1), because that diagnostic is genuinely useful for finding gaps in the v9 data.

---

### 3. UI philosophy — one core, two language front-ends

We agreed on this together, and it is now real. The logic is shared; the presentation is
per-language, because the UX conventions differ between our audiences:

- **In English**, the interface keeps my original layout.
- **In 中文**, the top bar is a **faithful reproduction of yours** — your positions, your
  widths, your three modes (关闭训练 / 确认训练 / 连段训练) plus 距离显示 / 碰撞显示, and no
  purple backdrop, exactly as in `SF6_TOOLS_CC`.
- A runtime **EN ↔ 中文 toggle** switches everything at once via an `i18n` registry.
- For CJK glyphs I used the **same font approach as you** (swapping the file to
  `msyh.ttc` / `msyhbd.ttc` — REFramework already bakes the CJK ranges), so both forks render
  Chinese identically.

Because the two top bars differ (your fork has three training modes, mine has six), the
Chinese bar deliberately shows your three; EXECUTION / REACTION DRILLS / POST GUARD remain
reachable through the REFramework menu and the hotkey framework. This was a conscious choice
to respect the Chinese layout you designed.

---

### 4. Findings and feedback for you

While integrating, I found a few things that may be useful on your side. I offer these as
observations, for your judgement:

1. **Install act_ids are not derivable from BCM.** E.g. E.Honda's Sumo Spirit changes the
   act_ids of empowered normals (act_id 971 is absent even from the full AC+BCM source). So
   character exceptions remain necessary as a fallback for install-type moves.
2. **DRC / RAW DR inconsistency in the catalogs.** Across the 30 generated catalogs, only
   ~10–11 contain 500/501, and the raw data reads **500 = RAW DR / 501 = DRC**, whereas the
   mod convention (`exceptions/Common.json`) treats **500 = DRC**. Rather than guess, I kept
   the exceptions as the fallback and left the catalogs strict. This may be worth aligning on
   your side.
3. **The `catalog` parameter in `CharacterRules` absorb functions was left dormant** in your
   HEAD (the call sites do not pass it). I wired it through so that, in BCM-strict mode, the
   catalog drives absorb confirmation.
4. **DynamicRecords vs RSM.** Your DynamicRecords overlaps with my `SF6_RecordingSlotManager`.
   I kept both and made DynamicRecords bilingual; if we want to unify later, that is a good
   candidate for a joint decision.

---

### 5. Where to look

- **Bilingual port tracker** (every subsystem, status, commit): `roadmap/port.html`
  (password `cdjayANDwael`) → `wael3rd.github.io/SF6_Tools/roadmap/port.html`.
- All the ports are in the commit history with `port(cdjay #N): …` messages, each explaining
  the wiring and the decision.

---

### 6. Handover

From my side, I have integrated everything I reasonably can — I believe my branch is now a
functional superset of `SF6_TOOLS_CC`. **The initiative is yours now.** Please:

- review whether anything is missing or was misunderstood on my part;
- integrate whatever you wish to add (SF6CC-specific links, systems, or data on your side);
- correct me on any of the arbitrations above if you see them differently — I would genuinely
  welcome that.

Thank you again for the collaboration. It has been a pleasure building on your work, and I
hope this shared core serves both our communities well.

— Wael

---
---

## 🇨🇳 中文

### cdjay 你好，

首先，衷心感谢你。你所分享的成果——BCM/AC 工具链、现代记法数据、DynamicRecords、在线安全
hook、Validator 架构——对这个项目而言是一份真正的馈赠。正是在你的基础之上，下面这一切才得以
实现。我想明确一点：这是**共同的成果**，绝非我一人之功。

本文档是对我在自己分支上所整合的一切、所做的决定，以及——在我保留了不同做法之处——*为何如此*
的一份完整而坦诚的说明，供你自行判断。**我的目标是让我的分支成为 `SF6_TOOLS_CC` 的 100% 超集**，
使我们真正共享一个核心、拥有两套按语言划分的前端。我相信目前能合理整合的都已整合完毕。
**现在我把主动权交还给你**：请检视是否有遗漏之处，并由你接手，继续整合你希望加入的一切
（包括你那边任何 SF6CC 专属的链接或系统）。

---

### 1. 从你的分支整合的内容

以下全部移植自你的 `HEAD 9b851c5`，均已校验（语法 + 声明顺序 + 严格的引号扫描），
除特别注明外，**均已实机测试**。

| 子系统 | 状态 | 说明 |
|---|---|---|
| **CTTimelineSequenceNormalizer** | ✅ 已移植并测试 | 依据录制的按键时间轴，将重复 / 多段命中的普通技压缩为单个 step。以失败即放行方式接入 `assign_groups`。 |
| **Trial 防御设置还原** | ✅ 已移植并测试 | 在 trial 期间关闭假人的自动 Drive Parry / Drive Rush，结束后还原用户的 Defense 选项卡设置。 |
| **假人蹲姿 + 防御类型推断** | ✅ 已移植并测试 | 从环境 / 场景状态 / 连段文本推断蹲姿与防御，同时保留我们的跳跃处理。 |
| **现代记法未解析审计** | ✅ 已移植并测试 | 记录 modern_display 无法解析的 act_id，以便发现覆盖缺口。已适配到我们的 `ModernDisplay.lua` 流程。 |
| **向前兼容 schema 守护** | ✅ 已移植并测试 | `warn_newer_schema`：当连段文件的 `_xt_meta.schema` 高于当前支持时提示一次并尽力加载，而非静默失败。对我们共享的 JSON 格式很重要。 |
| **BCM 动作目录（30 角色）** | ✅ 用你的工具链生成 | Node 工具链、v2 编译器、0 失败。目录与手动例外作为两个独立开关共存。 |
| **现代记法（v9 数据，30 角色）** | ✅ 已整合 | 3 种显示模式（快捷 / 指令 / 两者）、根据玩家操作类型自动检测、按钮图标。 |
| **DynamicRecords** | ✅ 已移植并双语化 | 你的训练配置导入/导出。现已支持 EN/中文；**你的「小吞MOD」署名在两种语言下均保留**——功劳归于你。 |
| **11 项上游修复** | ✅ 已移植 | SharedHooks 在线屏蔽 + 代次防重、HitConfirm、UTF-8 D2D 居中、启动隐藏 REF 菜单、SheldonsBoxes 在线屏蔽等。 |

---

### 2. 已被覆盖的子系统——以及一处技术取舍

有几处我发现我的分支已经解决了同样的问题，有时是通过不同的机制。我想谨慎而诚恳地说明这些，
因为其中两处，我基于**具体的技术原因**认为另一种做法更可取，这并非对你工作的评判。若你有不同
看法，非常欢迎指正。

#### 2.1 血量还原——已精确到点

我们两套系统都将血量精确还原到点（`vital_new = 精确值`，伤害 = `起始血量 − 最低血量`），
绝非按百分比。血量还原的核心在我这边早已具备，效果一致。此处无需移植。

#### 2.2 晕眩 / DI 下的 DEMO 回放——*取舍：采用原始输入回放*

这一处我最想仔细说明，因为两种方案都是成立的。

- **你的 `CTStunDemoRuntime`** 以**时间轴 step**（每个 step 含帧时长）回放连段，并因脚本节拍在
  硬直期间可能偏离引擎时钟，使用 `catch_up_missed_engine_frames` 重新同步。这是一个稳妥的设计。
- **我的 raw DEMO** 逐帧录制原始输入位掩码（`pl_input_new`，每个引擎输入 tick 一个 `uint16`），
  并在与录制**相同的引擎 hook** 上回放。

我保留原始回放作为主路径，原因在于架构：由于录制与回放都挂在同一个引擎输入 hook 上，
**漂移不可能发生**——在晕眩 / DI / DRC 硬直期间该 hook 根本不触发，因此录制与回放会锁步暂停、
锁步恢复。它复现的是精确的输入流，包括 DRC 取消的时机。你的 `catch_up` 解决的是这套架构本身
并不存在的漂移问题。

**重要：** 我并未丢弃你的工作。你的 `CTStunDemoRuntime` 在我的分支中完整保留，作为**没有
`raw_inputs` 的旧连段的回退方案**。新连段用原始回放，旧连段用你的时间轴系统。这是两者兼得。

#### 2.3 同一动作连续——由更轻量的机制覆盖

你的 `is_same_action_continuation_step` / `ct_try_skip_unreported_same_action_pressure_step`
处理重复的同一 move（如 cr.LK × 3），此时引擎报告相同的 `action_instance`。我的分支以不同方式
解决同一情形：借助**连段计数**（`Validator.check_combo`，`current_combo >= expected_combo`
区分每一次重复）加上你所编写的 `CTTimelineSequenceNormalizer`。结果相同，且避免了将
`action_instance` 贯穿到它在你匹配器中触及的约 62 处调用点。因此这一项我未移植——并非它有误，
而是结果已经达成，且移植会对一个正常工作的 validator 造成侵入。

#### 2.4 现代记法渲染——保留更轻量的解析器

你的 `ComboTrials_D2D` 现代解析引擎（约 1300 行）非常强大。在我这边，一个小巧的
`ModernDisplay.lua`（act_id → 现代记法字符串）在图标模式下产生相同的渲染结果，故予以保留——
**但我在其之上移植了你的未解析审计层**（见 §1），因为该诊断对发现 v9 数据的缺口确有实用价值。

---

### 3. UI 理念——一个核心，两套语言前端

这是我们共同商定并已落实的：逻辑共享；表现按语言划分，因为我们各自受众的 UX 习惯不同：

- **英文下**，界面保持我原本的布局。
- **中文下**，顶栏是**对你的忠实复刻**——你的位置、你的宽度、你的三个模式（关闭训练 / 确认训练 /
  连段训练）加上 距离显示 / 碰撞显示，且没有紫色背景条，与 `SF6_TOOLS_CC` 完全一致。
- 运行时 **EN ↔ 中文 切换**通过 `i18n` 注册表一次性切换全部。
- 对于 CJK 字形，我采用了**与你相同的字体做法**（将文件切换为 `msyh.ttc` / `msyhbd.ttc`——
  REFramework 已预烘焙 CJK 范围），因此两个分支渲染中文完全一致。

由于两套顶栏不同（你的分支有三个训练模式，我的有六个），中文栏有意只显示你的三个；
EXECUTION / REACTION DRILLS / POST GUARD 仍可通过 REFramework 菜单与快捷键框架访问。
这是为尊重你所设计的中文布局而做的有意选择。

---

### 4. 给你的发现与反馈

在整合过程中，我发现了几处或许对你那边有用的东西。谨作为观察提出，供你判断：

1. **install 型 act_id 无法从 BCM 推导。** 例如本田的相扑之魂会改变强化普通技的 act_id
   （act_id 971 即便在完整的 AC+BCM 源中也不存在）。因此对于 install 型招式，角色例外仍作为
   回退所必需。
2. **目录中 DRC / 原始 DR 的不一致。** 在生成的 30 个目录中，仅约 10–11 个含有 500/501，且原始
   数据读作 **500 = 原始 DR / 501 = DRC**，而 mod 约定（`exceptions/Common.json`）视
   **500 = DRC**。为避免臆测，我保留例外作为回退，并让目录保持严格。你那边或值得统一。
3. **`CharacterRules` 吸收函数中的 `catalog` 参数在你的 HEAD 中处于休眠状态**（调用点并未传入）。
   我已将其接通，使得在 BCM 严格模式下由目录驱动吸收确认。
4. **DynamicRecords 与 RSM。** 你的 DynamicRecords 与我的 `SF6_RecordingSlotManager` 有重叠。
   我保留了两者并将 DynamicRecords 双语化；若日后想统一，这是一个适合共同决定的候选。

---

### 5. 参考位置

- **双语移植进度看板**（每个子系统、状态、提交）：`roadmap/port.html`
  （密码 `cdjayANDwael`）→ `wael3rd.github.io/SF6_Tools/roadmap/port.html`。
- 所有移植都在提交历史中以 `port(cdjay #N): …` 的信息记录，每条都说明了接线方式与决策。

---

### 6. 交接

在我这边，能合理整合的都已整合——我相信我的分支现已是 `SF6_TOOLS_CC` 的功能超集。
**现在主动权在你手中。** 恳请你：

- 检视是否有遗漏，或我理解有误之处；
- 整合你希望加入的任何内容（你那边 SF6CC 专属的链接、系统或数据）；
- 对上述任何取舍，若你有不同看法，请指正我——我由衷欢迎。

再次感谢这次合作。能在你的成果之上继续构建，是我的荣幸。愿这个共享的核心能很好地服务于我们
两边的社区。

—— Wael
