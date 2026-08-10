# 合成 Cmd+V 在 Flutter 应用中完全失效

**日期**：2026-08-10
**触发场景**：引导页完成步骤新增「现在试一次」输入框，语音识别成功但文字注入不进去
**最终根因**：`inject_via_clipboard` 合成的按键序列与真实键盘事件不一致，缺三样东西
**影响面**：所有 Flutter 桌面应用（含 SpeakOut 自己）；原生控件与 Chromium/Electron 不受影响

---

## 轮次 1：完成页按快捷键完全无反应

**现象**：完成页显示「按住说话」，按 Right Option 毫无反应，日志无任何记录。

**假设·判断原因**：引导页从未初始化引擎。`AppService.init()`（内含 `engine.init()` 装 CGEventTap）
只在 `_HomePageState.initState` 调用，引导页走的是另一个分支，只调了 `initASR`。
`app_service.dart` 里那句 `// Skip if already initialized (e.g., by onboarding)` 就是这种双写留下的补丁气味。

**措施**：把键盘监听收敛为 `AppService.startKeyboardListener()`，完成页在 postFrame 里调用。
顺带发现 `engine.init()` 在全项目散落三处（`app_service.init` / `main._recheckPermissions` / 本次新增），全部收敛到一处。

**验证结果**：按键有反应了，录音、识别（「测试一下。」）、`inject/save done` 全链路日志齐全。

**复盘**：假设准确。但暴露出更根本的问题——引导阶段 `applyVerboseLogging()` 也没调，
**全程无文件日志**，这正是本轮之前排查困难的原因。已一并前移到引导页 initState。

---

## 轮次 2：识别成功但文字没进输入框

**现象**：日志显示 `Result (5字): '测试一下。'` + `inject/save done`，但输入框空的。

**假设·判断原因**（依次提出并**全部被推翻**）：

| # | 假设 | 推翻依据 |
|---|---|---|
| 1 | 输入框不可编辑 | `macos_ui` 的 `readOnly` 默认 false；用户实测打字正常 |
| 2 | 我们自己的 CGEventTap 吞掉了事件 | tap 是 `kCGEventTapOptionListenOnly`，所有分支 `return event` |
| 3 | 录音浮窗抢走焦点 | 浮窗是 `.nonactivatingPanel` + `orderFront`（非 `makeKeyAndOrderFront`） |
| 4 | Option 修饰键残留干扰 | 日志显示 keyUp 在注入前 95ms 已发生 |
| 5 | 主线程忙，事件延迟到 200ms 剪贴板恢复之后 | tap 挂在主线程 runloop，注入后 **6ms** 就收到了事件，主线程没阻塞 |
| 6 | 200ms 恢复剪贴板抢跑 | 手动复现完整时序（写入→10ms→Cmd+V→200ms→恢复）**能成功** |
| 7 | `setState` 抖掉了 autofocus 焦点 | 用户手动点击输入框后再试，仍然失败 |
| 8 | 「自己发给自己」不成立 | 外部进程用同样代码发，一样失败 |
| 9 | 缺 Command 键的 down/up | 补上完整序列后**仍然失败**（当时如此判断，见下方复盘） |
| 10 | 是 Electron/自绘控件的通病 | 用户实测 Obsidian、Cursor（均 Electron）**都正常** |

**措施**：改用「我们自己的 CGEventTap 当探针」——它记录每个经过 HID 层的按键事件，
把真实按键与合成事件的字段逐项对比。

**验证结果**：找到硬差异——

```
真实按键：  code=55 mods=0x108   code=9 mods=0x108   code=9 mods=0x108   code=55 mods=0x100
产品合成：  (无 code=55)         code=9 mods=0x0
```

**复盘**：前 10 个假设全错，教训是**过早推理、太晚测量**。
真正有效的一步是把已有的 tap 当探针用——现成的观测点一直在那儿，却绕了十轮才想到。

另一个严重的方法论错误：**实验条件没控制住**。执行 bash 命令时前台窗口是谁、
焦点在不在输入框，一直是自由变量，导致同一个变体一次「成功」一次「失败」，
还据此错误排除了 `postToPid`。后来给每次实验都加上 `activate` + 对照组才稳定下来。
（用户两次指出这点：「我当时都不在那个窗口焦点呢」「刚才焦点不在」。）

---

## 轮次 3：逐位复刻真实事件

**现象**：合成事件 `mods=0x0`，真实按键 `mods=0x108`。

**假设·判断原因**：`CGEventSetFlags(…, kCGEventFlagMaskCommand)` 设的是**高位** `0x100000`，
而真实键盘事件还带着**低位设备相关位**：`0x8`（左 Command）与 `0x100`（非合并标志）。
Cocoa 把 CGEvent 转 NSEvent 时会参考这些位还原修饰键状态。

**措施**：外部脚本发送「完整序列 + 设备位 + 8ms 间隔」，与产品做法对照。

**验证结果**：tap 记录与真实按键**逐字段一致**，文字成功粘贴。
对照组（`postToPid`、session tap、combined source、nil source）在同等前台条件下**全部失败**。

**复盘**：假设成立。附带发现——四个事件连发会被系统合并（tap 只收到前两个），
必须留间隔，这一点单看代码完全想不到，只有量出来才知道。

---

## 最终修复

`native_lib/native_input.m` 新增 `post_command_key(key, tap)`，逐位复刻真实按键：

1. 发送 **Command 键本身**的 down/up，不能只打 flags 标记
2. flags 补上 `NX_DEVICELCMDKEYMASK`（左 Command）| `NX_NONCOALSESCEDMASK`（非合并）
3. 事件之间 `INJECT_KEY_GAP_US`（8ms）间隔，否则被系统合并

**同源清零**：全文另有两处相同缺陷，一并收敛到该函数——

- 打字机流式注入的 Cmd+V（原本还用了 `kCGEventSourceStatePrivate`，一并统一为 `HIDSystemState`）
- AI 梳理的 Cmd+C（`copy_selection`）

`press_key` 两处调用的 `modifierFlags` 均为 0（→ 键、Return），不涉及组合键，未改动。

---

## 轮次 4：修复引发回归 —— Obsidian 粘出旧剪贴板内容

**现象**：Flutter 侧修好后做回归，在 Obsidian（Electron）里语音输入，
粘进去的是**用户原本的剪贴板内容**，而不是识别出的文字。原本 Obsidian 是正常的。

**假设·判断原因**：目标 App 读剪贴板的时刻晚于「200ms 后还原」的定时器。
但按时序账算，改动后窗口反而**变宽了 16ms**：

```
改动前：t=0 写入 → t=10ms 触发粘贴 → t=210ms 还原    目标 App 有 200ms
改动后：t=0 写入 → t=18ms 触发粘贴 → t=234ms 还原    目标 App 有 216ms
```

推理与现象矛盾，说明账不能这么算 —— 完整按键序列在 Chromium 里走的处理分支
与「裸 V + flags」不同，粘贴落地更慢。放弃推理，改用二分实测。

**措施**：把还原延迟从 200ms 提到 800ms（同时提取为常量 `CLIPBOARD_RESTORE_DELAY_MS`，
普通注入与打字机流式两处一并替换）。

**验证结果**：Obsidian 恢复正常。确认根因就是还原窗口太窄。

**复盘**：假设方向对，但**定量推理完全不可信** —— 算出来窗口变宽了，实际却击穿。
教训与轮次 2 一致：涉及跨进程时序，只能测，不能算。

另一个重要发现：[ADR-002](../decisions/adr-002-clipboard-injection.md) 早就把这一条列为已知缺陷 ——
「必须破坏用户原剪贴板（短时间）—— 200ms 后恢复」并记了 bug 报告。
**根因不是本次引入的，是本次把一个一直在临界点上的脆弱设计推过了线。**

**连带加固**：窗口拉长到 800ms 后，「用户在等待期内自己复制了东西、还原时被覆盖」的风险显著变大。
因此还原前比对 `NSPasteboard.changeCount`：与我们写入时记录的值不一致，说明剪贴板已易主，直接放弃还原。
打字机路径同理（用 `_lastChunkChangeCount` 记录最后一个 chunk 的写入）。

## 为什么一直没被发现

原生控件（NSTextField/NSTextView）和 Chromium 只读高位 `modifierFlags`，Command 标记就在事件里，
所以备忘录、Xcode、终端、Obsidian、Cursor 全都正常。
只有 Flutter 在框架层用 `HardwareKeyboard` 的按键状态判断组合键，而那个状态**只由 Command 键自身的
down/up 事件维护**——于是唯独它认不出来。日常使用覆盖不到 Flutter 桌面应用，缺陷就一直潜伏着。
