# SpeakOut — Agent 指南

> **本文是唯一真源**。`CLAUDE.md` 是指向本文的软链接（symlink）——两个文件名、同一份内容，改这里就够。
> （Windows 上若 git 未启用 symlink，`CLAUDE.md` 会 checkout 成一个内容为 `AGENTS.md` 的文本文件，直接读本文即可。）
> 本文是 **L1 入口**：只放全局刚需 + 导航。模块内部知识不写在这里，按下表下钻。

## 文档体系（渐进披露 4 层）

| 层 | 位置 | 什么时候读 |
|---|---|---|
| **L1** | 本文 | 每次任务开始。项目概况 + 命令 + 架构铁律 + 导航 |
| **L2** | `<module>/AGENTS.md` | 动某个模块的代码前，只读那一个（见[模块导航](#模块导航l2)） |
| **L3** | [`docs/decisions/INDEX.md`](./docs/decisions/INDEX.md)（ADR）<br>[`docs/anti-patterns/INDEX.md`](./docs/anti-patterns/INDEX.md)（踩过的坑） | 做技术选型时查 ADR；动手实施前扫一眼反模式 |
| **L4** | `docs/wiki/README.md` | 需要历史设计依据时。按 🚀 Planning / 🟢 Active / 📜 Historical / 🔴 Archived 分类。**gitignored 的本地文档库 —— 全新 clone 后没有这个目录，属正常** |

> **铁律：一个事实只写在一个层。** L1 可以有指向下层的**指针和一句话索引**，但不复制下层的**可执行细节**（命令、参数、实现机制）——曾经因为两处都抄，原生库编译命令在 L1 漂移成了缺 framework 的过期版本。
> 同理：文档里少写会漂移的精确数字（文件行数、条目个数），改为指向真源。

## 项目速览

**子曰 SpeakOut** — macOS 离线优先 AI 语音输入系统。**按住快捷键说话 → 松开 → 文字直接注入当前 App 的输入框。**

Flutter/Dart 构建，通过 FFI 调用原生 Objective-C 实现低延迟键盘监听和音频采集。ASR 双引擎：Sherpa-ONNX（离线，默认）/ 云端（阿里云百炼等）。LLM 润色纠错为独立可选开关。

三种录音模式（`RecordingMode`，定义在 `lib/engine/core_engine.dart`）：

| 模式 | 行为 |
|---|---|
| `ptt` | 默认。识别结果注入当前 App 输入框 |
| `diary` | 闪念笔记。写入本地目录，不注入 |
| `aiReport` | AI 一键调试 |

### 目录结构

| 目录 | 内容 |
|---|---|
| `lib/` | Flutter/Dart 主体，三层架构（见[模块导航](#模块导航l2)） |
| `native_lib/` | Objective-C 原生库：CGEventTap 键盘 + AudioQueue 音频 + 文本注入；含 `linux/` `windows/` 同名实现 |
| `macos/` `windows/` `linux/` | 各平台壳工程（AppDelegate / entitlements / CMake） |
| `gateway/` | Cloudflare Workers 后端：许可证 + Token + 计费 |
| `test/` | 测试（见[测试](#测试)） |
| `scripts/` | 构建 / 安装 / 打包 / DMG 脚本 |
| `tools/` | 开发辅助工具（如 `ax_probe` 无障碍探针） |
| `assets/` | 静态资源 + 凭证模板（`*.json.example`） |
| `docs/` | 文档：`decisions/` `anti-patterns/` `wiki/` `debug-log/` |
| `log/` `wiki/` `real-test/` | **本地目录，不入库** — 运行日志 / GitHub Wiki 本地 clone / 真机测试产物 |

### 代码入口（新人从这里读）

```
lib/main.dart
  ├─ main() 平台分发 → runApp(SpeakOutApp | WindowsAppWrapper | LinuxAppWrapper)
  ├─ ConfigService().init()              配置先行，所有偏好/凭证从这里出
  ├─ 首启 → OnboardingPage               权限引导 + 离线模型下载
  └─ AppService.init() → engine.init()   拉起全部服务与 CoreEngine
```

两个必读文件：`lib/main.dart`（启动）和 `lib/engine/core_engine.dart`（主编排器，键盘/音频/ASR/分发都在这）。

### 首次运行前提

macOS 会拦两道权限，不给全程序跑不起来（`macos/Runner/Info.plist`）：

- **麦克风**（`NSMicrophoneUsageDescription`）— 录音
- **辅助功能 / 输入监控**（`NSAccessibilityUsageDescription`）— CGEventTap 监听快捷键 + 注入文本

离线 ASR 首次使用需先下载 Sherpa 模型（应用内引导页完成）。

## 命令速查

```bash
# 依赖
flutter pub get

# 静态分析
flutter analyze

# 测试
flutter test                                       # 全部
flutter test test/services/llm_service_test.dart   # 单文件

# 构建
flutter build macos --release

# 编译并安装到 /Applications
./scripts/install.sh

# 生成 DMG 安装程序
./scripts/create_styled_dmg.sh

# Gateway 后端 (Cloudflare Workers)
cd gateway && npm run dev      # 本地开发
cd gateway && npm run deploy   # 部署
```

**原生库编译**（改 `native_input.m` 后必做）：命令见 [`native_lib/AGENTS.md`](./native_lib/AGENTS.md) §编译。不在这里复制——漏 framework 或漏 `-fobjc-arc` 会导致内存管理崩。

## 三层架构铁律

```
UI 层  ──depends on──▶ Service 层  ──depends on──▶ Engine 层
   │                       │                          │
   └─ 不要直接调 Engine     └─ 不要直接读 SharedPrefs   └─ 不要 import flutter/material
```

- **UI 层不能直接 `import 'lib/engine/...'`** — 必须通过 Service 层
- **Service 层不能 `import 'package:flutter/material.dart'`** — UI 无关
- **Engine 层不能 `import 'package:flutter/material.dart'`** — 无 UI 依赖，可单独测试

## 核心数据流

```
快捷键触发 → native_input.m (CGEventTap)
  → C Ring Buffer 采集 16kHz PCM 音频
  → CoreEngine FFI 轮询 → VAD/AGC 处理
  → ASR (Sherpa 离线 / Aliyun 云端)
  → LLM 润色纠错 (可选)
  → 模式分发: ptt 文本注入 | diary 闪念笔记 | aiReport AI 调试
```

## 模块导航（L2）

| 模块 | 路径 | 职责 | 文档 |
|---|---|---|---|
| **Engine** | `lib/engine/` | 核心编排器 `CoreEngine`、ASR Provider 抽象、模型下载管理 | [AGENTS.md](./lib/engine/AGENTS.md) |
| **Services** | `lib/services/` | 业务服务（配置/LLM/笔记/聊天/音频/账户/计费/更新） | [AGENTS.md](./lib/services/AGENTS.md) |
| **UI** | `lib/ui/` | 界面（macos_ui，sidebar shell + 各页面） | [AGENTS.md](./lib/ui/AGENTS.md) |
| **FFI** | `lib/ffi/` | Dart ↔ 原生 dylib 绑定（`NativeInputBase` 抽象 + 平台分发） | [AGENTS.md](./lib/ffi/AGENTS.md) |
| **Config** | `lib/config/` | 静态常量、云服务商注册表、日志 | [AGENTS.md](./lib/config/AGENTS.md) |
| **Models** | `lib/models/` | 数据模型（cloud_account / chat / billing） | [AGENTS.md](./lib/models/AGENTS.md) |
| **Native** | `native_lib/` | Objective-C：CGEventTap + AudioQueue Ring Buffer + 文本注入 | [AGENTS.md](./native_lib/AGENTS.md) |
| **Gateway** | `gateway/` | Cloudflare Workers 后端：许可证 + Token + 计费 + 版本 | [AGENTS.md](./gateway/AGENTS.md) |
| **macOS 集成** | `macos/Runner/` | AppDelegate + 录音浮窗 + Method Channel | [AGENTS.md](./macos/Runner/AGENTS.md) |
| i18n | `lib/l10n/` | `app_zh.arb` / `app_en.arb` + `generated/`，改后跑 `flutter gen-l10n` | 无独立文档 |

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

### 敏感配置
`aliyun_config.json` 和 `llm_config.json` 已 gitignore，凭证存储于 SharedPreferences。**不要把密钥写进任何入库文件**，配置导出功能须排除密钥字段。

### i18n
所有用户可见字符串走 `loc.xxx`（`AppLocalizations.of(context)`）。改 ARB 后跑 `flutter gen-l10n` 同步 generated。

### 跨页 navigation（v1.8 sidebar 后）
sidebar 内部跳转用 `SidebarNavigation.of(context)?.goto('page_id')`，**不要**用旧的 `onNavigateToTab(int)` 数字索引（已 deprecated，残留代码视为待清理）。

## 反模式（L3）

实施前扫一眼 [`docs/anti-patterns/INDEX.md`](./docs/anti-patterns/INDEX.md)，每条都源自真实事件：

| 反模式 | 一句话 |
|---|---|
| [`dont-feature-creep-in-bug-fix`](./docs/anti-patterns/dont-feature-creep-in-bug-fix.md) | 修 bug 时不要顺手 refactor 不相关代码 |
| [`dont-skip-full-test-on-release`](./docs/anti-patterns/dont-skip-full-test-on-release.md) | 发版必跑完整 `flutter test`，不要问"是否跳过" |
| [`dont-amend-after-hook-failure`](./docs/anti-patterns/dont-amend-after-hook-failure.md) | pre-commit hook 失败后用新 commit 修，不要 `--amend` |
| [`dont-bypass-configservice`](./docs/anti-patterns/dont-bypass-configservice.md) | 不要直接 `SharedPreferences.getInstance()` |
| [`dont-onnavigatetotab-int`](./docs/anti-patterns/dont-onnavigatetotab-int.md) | 跨页跳转不要用 `onNavigateToTab(int)` |
| [`dont-pick-pilot-by-tech-friendliness`](./docs/anti-patterns/dont-pick-pilot-by-tech-friendliness.md) | 选试点 App：用户实际高频 > 技术友好性 |

## 架构决策（L3）

涉及选型权衡时先查 [`docs/decisions/INDEX.md`](./docs/decisions/INDEX.md)：ADR-001 不走 Sparkle / ADR-002 剪贴板注入 / ADR-003 云账户体系 / ADR-004 Context-Aware 试点策略 / ADR-005 V4 默认关 thinking。

新决策满足「影响长期架构 / 有明确备选被否决 / 违反直觉」任一条时，按 INDEX 里的模板新增 ADR。**已 Accepted 的 ADR 不修改**，只能新建 ADR Supersede。

## 测试

测试位于 `test/`，用 `flutter_test` + `mockito`：

- `test/services/` — 服务层单元测试
- `test/engine/` — 引擎层单元测试
- `test/integration_test.dart` — 集成测试
- `test/goldens/llm_correction_prompt.txt` — Golden 测试锁定 LLM prompt
- `test/helpers/` — 共享基础设施（`test_helpers.dart`, `mock_services.dart`）

`ConfigService` 是 singleton，测试中需用 setter 注入。手动冒烟清单见 `docs/release_checklist.md`。

## 跨平台状态（Phase）

| 平台 | 状态 | CI |
|---|---|---|
| macOS | ✅ 主战场 | ✅ 绿 |
| Linux | ✅ Phase 2 完成（编译通过） | ✅ 绿 |
| Windows | ⚠️ Phase 2 完成（编译通过），但**测试未全绿** | ❌ 红 |
| 鸿蒙 | ❌ Phase 3 待做 | — |

> **CI 现状（2026-08-09 核实）**：`main` 上 CI 长期红，`windows` job 挂 6 个测试（macOS / Linux 全绿）。
> **这是已知遗留，不是你搞坏的** —— 看到红先确认是不是这 6 个。项目所有者要求专门开会话修，**不要在其他任务里顺手碰**。

写跨平台代码时：FFI 通过 `NativeInputBase` 抽象，按 `Platform.isMacOS / isWindows / isLinux` 分发。

## 发版

用 `/release` 命令（4 阶段渐进披露的发版 SOP），不要手工拼步骤。

> skill 装在**全局** `~/.claude/skills/release/`，**不在本仓库内** —— clone 下来看不到它，这是预期的。

## 当前长期方向

- **Context-Aware Voice**（规划中，`lib/` 内**尚无实现**）— 语音 + App 上下文 → 更合适的文字。试点方案走 **Generic + Browser 双层**，单 App（Mail.app）方案已被否决，理由见 [ADR-004](./docs/decisions/adr-004-context-aware-pilot-strategy.md)。设计稿 `docs/wiki/context_aware_voice_plan_2026_05_07.md`
- **个性化 ASR**（待启动）— 词汇增强 → LoRA → speaker-conditioned
- **iOS 兄弟项目 FlashNote**（独立仓库 `~/Apps/FlashNote/`）

## 代码风格

- 文件名：`snake_case.dart`
- 类名：`PascalCase`
- 注释：默认不写。只在「为什么这么做」非显然时写一行；不解释「做什么」（让代码自解释）
- 注释语言：中文 / 英文均可，禁止其他语言
- 不写多段 docstring；不写过期的 "TODO（具体人名）" 注释（项目无负责人映射）
