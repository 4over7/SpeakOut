# ADR-002: 文本注入统一走剪贴板 + Cmd+V

**日期**: 2025-xx (v1.5.13)
**状态**: ✅ Accepted（v1.5.13 起所有应用统一）
**决策者**: 项目所有者

## 背景

SpeakOut 的核心功能：录音转文字 → 注入到当前应用的输入框。注入实现有两条主流路径：

1. **CGEvent keyboard injection**：`CGEventCreateKeyboardEvent` 模拟键盘按键，逐字符发送
2. **剪贴板 + Cmd+V**：把文字写剪贴板，发送 `Cmd+V` 触发粘贴，200ms 后恢复原剪贴板内容

早期版本只用 CGEvent keyboard injection。问题：

- **快速多次调用天然不可靠** — HID 队列异步竞争，第二次以后的字符经常丢
- **特殊字符处理复杂** — Unicode 字符、组合键、变音符号都要单独处理
- **某些应用（终端 / 部分电子游戏）拦截 CGEvent** — 完全不响应

## 选项

### A. 继续 CGEvent，加 retry / sleep 缓解
- ✅ 不依赖剪贴板
- ❌ 治标不治本，HID 队列异步本质问题无解
- ❌ retry 让延迟体验更糟

### B. 全部改剪贴板 + Cmd+V
- ✅ 100% 兼容（Cmd+V 是所有 macOS 应用的统一粘贴入口）
- ✅ 速度可预期（一次注入完成）
- ✅ 特殊字符无障碍
- ❌ 必须破坏用户原剪贴板（短时间）—— 200ms 后恢复
- ❌ 在 sandbox app 中粘贴可能被拒（少数情况）

### C. 智能分流（GUI 应用 CGEvent，终端 / 特殊应用剪贴板）
- ✅ GUI 应用保持原剪贴板
- ❌ 检测哪些应用要走哪条路径维护成本极高（白名单永远不全）
- ❌ 用户跨应用切换时行为不一致，反而困惑

## 决策

**选 B：全部走剪贴板**。

**为什么不是 C 的"智能分流"**：用户预期的是「**注入一致**」，不是「最优」。一种行为可预期 > 两种行为大多数时候更优。维护两套路径是技术债无底洞。

## 后果

**正面**：
- v1.5.13 起注入零失败报告
- 终端、设计软件、跨平台应用全部覆盖
- 实现简单（一个函数 `inject_via_clipboard`）

**负面**：
- **用户原剪贴板会被覆盖 200ms** — 已有 bug 报告：极少数情况下目标 App 在 200ms 内读了剪贴板，粘贴的还是 SpeakOut 的内容（已记入 known issues）
- **打字机效果（流式注入）实现复杂** — 用 `inject_clipboard_begin/chunk/end` 分批注入（120ms 批量），avoid 频繁覆盖剪贴板

**残留 CGEvent 路径**：`inject_via_keyboard` 函数仍保留在 `native_lib/native_input.m`，但生产代码不再调用。**保留原因**是某些极端场景（剪贴板被锁定的特殊系统状态）的兜底备用。**未来可考虑彻底删除**。

## 相关

- 实现：`native_lib/native_input.m` `inject_via_clipboard()`
- 已知问题：`docs/anti-patterns/` 未来若加「剪贴板竞态」反模式可链此
- 流式注入：v1.6 起 alpha 实验，`inject_clipboard_begin/chunk/end` API
