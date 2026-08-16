# 批次 5：native 层存量 finding 清理

全量 review 第 5 批（`native_lib/` + `macos/Runner/`）报告了 7 条确定问题 + 1 条待验证。
本文按轮次记录核实与修复过程。批次 1–4（services / 云账户持久化链）已收敛，见 git log。

## 核实结论（2026-08-16，逐条对当前代码复核）

| # | 级别 | 问题 | 现状 |
|---|---|---|---|
| N1 | P1 | `kCGEventTapDisabledByUserInput` 不重新启用 tap | **仍在**（`native_input.m:141`） |
| N2 | P1 | verbose 日志在 CGEventTap 回调里做同步文件 I/O + NSString 分配 | **仍在**（`log_to_file` 同步 fopen/fclose/NSLog） |
| N3 | P1 | 800ms 内连续两次普通注入永久丢失用户原剪贴板 | **仍在**（`inject_via_clipboard`，每次都重新快照） |
| N4 | P1 | App Store 版只存目录路径，重启后失去闪念目录沙盒权限 | **仍在**（无 security-scoped bookmark） |
| N5 | P1 | DebugProfile 沙盒缺 audio-input / user-selected 权限 | **仍在** |
| N6 | P2 | `_lastChunkChangeCount` 跨会话残留导致漏还原 | **仍在**（`begin` 不重置） |
| N7 | P2 | 麦克风首次授权超 5 秒被当成拒绝 + `result` 无原子同步 | **仍在** |
| N8 | P2 待验证 | `smoothedLevel` 可能被 Swift 与 Dart 并发读写 | 待验证 |

前一批加的 `_clipboardSessionActive` 只解决了「原剪贴板为空时 end 误早退」，N3/N6 是另外两个独立缺陷。

## 修复顺序

先做契约清晰、爆炸半径小的：N1 → N3 + N6（同源，一起改）→ N5 → N7 → N2 → N8 核实 → N4（最大，最后评估）。

---

## 第一轮

### 现象

见上表核实结论。N1、N3、N6 三条都能在当前代码里逐字对上。

### 假设 · 判断原因

- **N1**：`CGEventTapEnable(eventTap, false)` 在全仓只出现在 137、310 两处且都传 `true` —— 没有任何「有意禁用」的路径会跟自动重启打架，所以对 `DisabledByUserInput` 无条件重启是安全的。
- **N3**：快照时机错了。每次注入都重新读当前剪贴板当「原始内容」，第二次读到的其实是第一次注入的文本。要改成**事务级快照**：只有在没有待还原任务时才拍快照，之后的注入只刷新代次。
- **N6**：`_lastChunkChangeCount` 是会话间共享的静态量，`begin` 不重置 → 上一次会话的 changeCount 会被这一次的 `end` 当成判据。
- **N7**：`__block int result` 在超时路径上被主线程读、completion block 在任意线程写，是数据竞争；且超时后返回的是初值 0（= 拒绝）。根因是「用同步 FFI 等一个要人点的 UI」，只能改成状态查询 + 异步请求。
- **N2**：`log_to_file` 在 tap 回调里 `fopen`/`fclose`/`NSLog`，磁盘忙时回调超时 → 系统禁用 tap。要把 I/O 挪出回调线程，且回调侧不能有堆分配。

### 措施

| # | 改法 |
|---|---|
| N1 | 两类禁用合并处理，`eventTap` 非空即 `CGEventTapEnable(tap, true)` |
| N2 | 新增 tap 线程专用环形缓冲 `log_from_tap`：回调侧只做栈上 `vsnprintf` + 一次 release store，后台队列 200ms 排空做真正 I/O。回调内 7 处 `log_to_file` 全部换掉 |
| N3 | `inject_via_clipboard` 改成事务级快照：只有当前无待还原任务时才拍快照，之后的注入只推进代次，唯有最后一代负责写回最初那份 |
| N6 | `begin` 复位 `_lastChunkChangeCount = -1`；`copy_selection` 在会话进行中时把自己造成的 changeCount 记进判据 |
| N5 | `DebugProfile.entitlements` 补 `device.audio-input` + `files.user-selected.read-write` |
| N7 | 拆成 `microphone_permission_status()`（只查询、不弹框、不阻塞）+ `request_microphone_permission()`（只在未决定时弹框，立即返回）。`check_microphone_permission()` 退化成 `status == 3`。Dart 侧 onboarding 未决定走系统授权框并轮询，已拒绝才去系统设置；core_engine 权限门补一次异步请求 |
| N8 | `smoothedLevel` 改成原子位模式 + **按时间**算衰减 |
| N4 | `AppDelegate` 增加 security-scoped bookmark：`pickDirectory` 落 bookmark 并立即按 bookmark 方式持有，`applicationDidFinishLaunching` 解析恢复，`stale` 时重建 |

### 验证结果

- **编译**：`clang -dynamiclib … -fobjc-arc` 退出码 0、零警告；`nm -gU` 确认新符号
  `_microphone_permission_status` / `_request_microphone_permission` 已导出。
  `swiftc -parse macos/Runner/AppDelegate.swift` 通过。
- **N8 用离线探针取得确定性证据**（`scratchpad/decay_probe.c`，复刻新旧两种衰减）：

  | 轮询器个数 | 旧实现 480ms 后 | 新实现 |
  |---|---|---|
  | 1 | 0.4644 | 0.4644 |
  | 3 | **0.1002** | 0.4643 |

  即旧实现在三个轮询器同时跑时衰减到设计值的 **1/4.6**。这条原本报的是
  「可能存在数据竞争（待验证）」，探针把它升级成**确定的行为缺陷**：
  衰减速度跟着调用次数走，与设计意图（80ms 一拍、半衰期 ~460ms）不符。
- **N8 影响范围要说准**：`rms < 0.002` 时 `get_audio_level` 直接 `return 0.0f`，
  **不经过平滑器**。所以「死寂环境」下静音检测拿到的是原始 0，不受此缺陷影响；
  受影响的是「有底噪但低于说话音量」那一段 —— 波形掉得过快，
  静音检测的 `level < 0.01` 判据也会更早成立。
- **N4 只做到「能编译 + 逻辑自洽」**：security-scoped bookmark 的真实行为
  必须在 **App Store 沙盒构建**里验证（选目录 → 退出 → 重开 → 写闪念），
  本地 Release 构建 `app-sandbox = false`，跑通了也不能证明沙盒版能跑通。
  **这条标记为「已实现、未在沙盒环境验证」，发版前必须手测。**
- **N2 的取舍**：环形缓冲溢出（200ms 内超过 256 条）会丢最旧的若干条并留一行标记；
  写者覆盖正在被读的槽位时最坏是那一行内容撕裂 —— 读侧整块 `memcpy` 后强制补 NUL，
  不会越界。调试日志可以容忍撕裂，不能容忍拖慢回调。

### 复盘

- 假设基本准：8 条里 7 条在当前代码逐字对得上，没有一条是「早已修过」。
- **N8 是这轮最有价值的一条**：原报告只敢写「待验证的数据竞争」，
  而真正咬人的是那个不需要任何并发就成立的行为缺陷 —— 三个轮询器各自推进
  同一个滤波器。这印证了一件事：**「待验证」的 finding 不该直接放过，
  去验证的过程往往会撞见比原 finding 更硬的问题。**
- 新问题（老问题的延伸）：一次性注入与流式注入用的是两套快照静态量，
  真交错的话两边的还原会互相打架。目前靠 Dart 侧的录音状态机与
  `_clipboardSessions` 计数隔开，**没有 native 层的互斥**。
  暂不动手（改动面大于收益），记在这里。
