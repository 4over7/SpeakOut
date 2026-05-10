# SpeakOut — Agent 导航

> 这个文件给 AI agent 看，是一份**入口索引**。项目级的 build / test / 业务概述见 [CLAUDE.md](./CLAUDE.md)。

## 必读（按顺序）

1. [CLAUDE.md](./CLAUDE.md) — 项目概况、Flutter 命令、原生库编译命令、核心数据流
2. 本文件 — 模块定位 + 跨模块约束 + 反模式索引
3. 当前任务相关的模块 AGENTS.md（见下表）
4. 涉及到决策权衡时 → [docs/decisions/INDEX.md](./docs/decisions/INDEX.md)（含 5 个 ADR）
5. 实施前先看反例 → [docs/anti-patterns/INDEX.md](./docs/anti-patterns/INDEX.md)（6 条踩过的坑）

> **提示**：`docs/wiki/` 目录（gitignored，本地文档库）含 50 个历史设计/调研文档。本地有 `docs/wiki/README.md` 状态索引，按 🚀 Planning / 🟢 Active / 📜 Historical / 🔴 Archived 分类。改相关代码时先查 README 找对应 active 文档作为设计依据。

## 模块导航

| 模块 | 路径 | 职责 | 详细文档 |
|---|---|---|---|
| **Engine** | `lib/engine/` | 核心编排器、ASR Provider 抽象、模型管理 | [lib/engine/AGENTS.md](./lib/engine/AGENTS.md) |
| **Services** | `lib/services/` | 业务服务（配置/LLM/笔记/聊天/音频/账户/计费/更新） | [lib/services/AGENTS.md](./lib/services/AGENTS.md) |
| **UI** | `lib/ui/` | 界面（macos_ui，sidebar shell + 各页面） | [lib/ui/AGENTS.md](./lib/ui/AGENTS.md) |
| FFI | `lib/ffi/` | Dart ↔ 原生 dylib 绑定 | (待补) |
| Config | `lib/config/` | 静态常量、云服务商注册表、日志 | (待补) |
| Models | `lib/models/` | 数据模型（cloud_account / chat / billing） | (待补) |
| Native | `native_lib/` | Objective-C：CGEventTap + AudioQueue + 文本注入 | (待补) |
| Gateway | `gateway/` | Cloudflare Workers 后端：许可证 + 计费 + 版本 | (待补) |
| macOS 集成 | `macos/Runner/` | AppDelegate + 录音浮窗 + Method Channel | (待补) |

## 三层架构铁律

```
UI 层  ──depends on──▶ Service 层  ──depends on──▶ Engine 层
   │                       │                          │
   └─ 不要直接调 Engine     └─ 不要直接读 SharedPrefs   └─ 不要 import flutter/material
```

- **UI 层不能直接 `import 'lib/engine/...'`** — 必须通过 Service 层
- **Service 层不能 `import 'package:flutter/material.dart'`** — UI 无关
- **Engine 层不能 `import 'package:flutter/material.dart'`** — 无 UI 依赖，可单独测试

## 全局约定

### 单例模式
全局服务用 singleton：`ConfigService()`, `CoreEngine()`, `ChatService()`, `LLMService()`, `CloudAccountService()`。**不要 new 第二个实例**。

### 生命周期
所有引擎/服务遵循 `init() → start() → stop() → dispose()`。新加 service 必须实现 `dispose()` 关闭流/取消计时器（防内存泄漏）。

### 流式状态分发
ASR 实时结果、UpdateService 进度、AudioDeviceService 设备变化等都用 `StreamController`。订阅者在 `dispose()` 时取消订阅。

### 配置读写
**唯一入口** `ConfigService()`。不要直接 `SharedPreferences.getInstance()`。

### LLM 调用
**唯一入口** `LLMService()`。不要在 UI / Engine 直接发 HTTP。新增模型特定参数（如 thinking off）走 `_applyModelSpecificParams()`。

### i18n
所有用户可见字符串走 `loc.xxx`（`AppLocalizations.of(context)`）。改 ARB 后跑 `flutter gen-l10n` 同步 generated。

### 跨页 navigation（v1.8 sidebar 后）
sidebar 内部跳转用 `SidebarNavigation.of(context)?.goto('page_id')`，**不要**用旧的 `onNavigateToTab(int)` 数字索引（已 deprecated，残留代码视为待清理）。

## 反模式（不要做什么）

待 `docs/anti-patterns/` 完善后链接。当前已知（详见 memory 中 `feedback_*.md`）：
- ❌ 选 dogfood 试点 App 时按"技术友好性"而非"用户实际频率"
- ❌ 发版默认跳过 `flutter test`
- ❌ pre-commit hook 失败后用 `git commit --amend` 修（应新建 commit）
- ❌ feature creep — 修 bug 时顺手 refactor 不相关代码
- ❌ 测试 mock 真实网络/数据库（model_full_flow_test 是有意走真网，但其他不该）

## 跨平台状态（Phase）

| 平台 | 状态 | 来源 |
|---|---|---|
| macOS | ✅ 主战场 | v1.0+ |
| Windows | ✅ Phase 2 完成 | 编译过测试可绿 |
| Linux | ✅ Phase 2 完成 | 同上 |
| 鸿蒙 | ❌ Phase 3 待做 | 独立仓库（ArkTS） |

写跨平台代码时：FFI 通过 `NativeInputBase` 抽象，按 `Platform.isMacOS / isWindows / isLinux` 分发。

## 发版

走 `.claude/skills/release/SKILL.md`（4 阶段渐进披露），不要手工拼步骤。命令是 `/release`。

## 当前长期方向

- **Context-Aware Voice**（v1.9 试点 Mail.app）— 见 `docs/wiki/context_aware_voice_plan_2026_05_07.md`
- **个性化 ASR**（待启动）— 词汇增强 → LoRA → speaker-conditioned
- **iOS 兄弟项目 FlashNote**（独立仓库 `~/Apps/FlashNote/`）

## 代码风格快速一览

- 文件名：`snake_case.dart`
- 类名：`PascalCase`
- 注释：默认不写。只在「为什么这么做」非显然时写一行；不解释「做什么」（让代码自解释）
- 注释语言：中文 / 英文均可，禁止其他语言
- 不写多段 docstring；不写过期的 "TODO（具体人名）" 注释（项目无负责人映射）
