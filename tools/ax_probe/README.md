# AX Probe — Context-Aware Voice Phase 0 探针

一个独立的 macOS menu bar 小工具，用于 Phase 0 验证 macOS Accessibility API 在不同 App 中能拿到什么，输出 Phase 1 GenericAdapter 能力矩阵的依据。

参见：[`docs/decisions/adr-004-context-aware-pilot-strategy.md`](../../docs/decisions/adr-004-context-aware-pilot-strategy.md) · [`docs/wiki/context_aware_voice_plan_2026_05_07.md`](../../docs/wiki/context_aware_voice_plan_2026_05_07.md)

## 编译

```bash
cd tools/ax_probe
swift build
.build/debug/AXProbe
```

首次运行会弹 AX 权限提示，到 系统设置 → 隐私与安全性 → 辅助功能 把 `AXProbe` 勾上，**完全退出再重新启动**（AX 权限对当前进程不生效）。

## 用法

启动后状态栏出现 👁️ 图标。两种触发方式：

1. **F19** — 全局热键，直接 dump 当前焦点（推荐：切到目标 App 点入输入框，按 F19）
2. **菜单 → Dump now (3s 倒计时)** — 不方便按 F19 时用，倒计时期间切到目标 App

每次 dump 落一个 JSON 到：

```
~/Library/Application Support/AXProbe/dumps/<timestamp>_<bundleID>.json
```

菜单提供：
- `Reveal last dump` — Finder 高亮最新 dump
- `Open dumps folder` — 打开 dumps 目录
- `Re-check AX permission` — 不重启检查权限

## 输出字段

| 字段 | 含义 |
|---|---|
| `app` | NSWorkspace.frontmostApplication：bundleID / name / pid / executablePath |
| `focusedAppFromAX` | 系统级 AX 焦点 App（一般和 `app` 一致） |
| `focusedWindow` | 当前焦点窗口的 AX 描述（role / title / 等） |
| `browserHints` | 窗口上的 AXURL / AXDocument / windowTitle（浏览器特有） |
| `focusedElement` | 焦点 UI 元素：role/subrole/identifier/title/value/placeholder/description/help/childCount/allAttrs/actions |
| `selection` | 选区文本 + 选区 range + 可见 range |
| `surrounding` | 焦点元素 value 中光标前后 200 字符 |
| `parentChain` | 焦点元素往上 6 层父元素（role/subrole/identifier/title） |

`allAttrs` 列出该元素**所有可读 AX 属性名**，`actions` 列出可执行动作——这两个字段是 Spike 的关键，用来发现"还有什么没读但能读"。

## Phase 0 验证步骤

按用户实际高频 App 跑一遍（每个 App 至少 3 种场景）：

### 1. Chrome / Safari
- [ ] 普通输入框（搜索栏 / 表单 input）— 抓 value 和 placeholder
- [ ] 富文本编辑器（Gmail 写邮件 / Notion 编辑 / Slack Web 输入框）
- [ ] 选中一段文字按 F19
- [ ] 飞书 Web 的群聊输入框 — 能否读到"群名"作为 windowTitle？

### 2. 飞书 Mac (Electron)
- [ ] 群聊输入框 — 焦点元素 role / value？
- [ ] 选中一段对话历史按 F19
- [ ] 文档编辑

### 3. 微信 Mac / 企业微信 Mac
- [ ] 聊天输入框 — 焦点是不是真的 textfield？value 能读吗？
- [ ] parentChain 能不能识别"对话名"？
- [ ] allAttrs 看看暴露了什么

### 4. 系统原生 (对照组)
- [ ] Notes 编辑
- [ ] Mail 写邮件
- [ ] TextEdit
- [ ] Xcode 代码编辑

## 整理结果

跑完后把 dumps 整理成一张能力矩阵表，作为 ADR-006（或 Phase 1 设计文档）的依据：

| App | 焦点元素 role | value 可读 | 选区可读 | 周边可读 | 对话/收件人 | URL/title hint |
|---|---|---|---|---|---|---|
| Chrome | AXTextField | ✅ | ✅ | ✅ | windowTitle | ✅ AXURL |
| 微信 | ? | ? | ? | ? | ? | — |
| ... | | | | | | |

## 常见问题

**Q: 按 F19 没反应**
- 检查菜单状态栏图标是不是 ⚠️（热键注册失败）
- 用菜单的 "Dump now (3s 倒计时)" 兜底
- F19 在某些键盘上是音量键之类，被系统抢走 — 可以改 main.swift 里 HotkeyManager.shared.register() 的 keyCode

**Q: dump 出来 axTrusted=false**
- AX 权限没授；授完**完全退出 AXProbe** 再启动（kill 进程或菜单 Quit）

**Q: focusedElement 是 null**
- 焦点不在文本输入控件上（比如焦点在 menu bar、桌面）
- 切到目标 App 点进输入框再按 F19
