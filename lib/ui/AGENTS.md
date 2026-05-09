# lib/ui/ — UI 层

> macOS 原生风格界面，基于 `macos_ui` 包。v1.8 起重构为 sidebar shell + 独立页面架构。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律 + 跨页 navigation 约定
- Service 协作：通过 `ConfigService()` 读写状态、通过 `LLMService()` 调 LLM

## 这层是干什么的

主窗口（聊天页 + 设置页）+ 引导页 + 词典 + 计费页 + 各种 Dialog。**只**与 Service 层交互，**不**直接调 Engine。

## 顶级文件

| 文件 | 职责 |
|---|---|
| `theme.dart` | 全局颜色/字体/间距（墨竹翡翠绿 #00B074 / #009660），用 `Theme.of(context)` 取值 |
| `settings_page.dart` | 11 行 shell，直接渲染 `SettingsSidebarShell`（v1.8 后旧 5-tab 已不可达）|
| `chat/` | 聊天页：时间线布局 + dictation 气泡（含 ASR 原文折叠展开） |
| `settings/` | 设置页（**重要，看下文**）|
| `cloud_accounts_page.dart` | 云账户管理（多账户 + 凭证分组卡）|
| `vocab_settings_page.dart` | 词典页（行业词典 + 个人词库）+ Beta 徽章 |
| `onboarding_page.dart` | 首次启动引导 |
| `billing_page.dart` | 余额 / 订阅 / Token 历史 |
| `dialogs/` | 弹窗：错误确认、模型下载进度、热键录入器等 |
| `widgets/` | 通用组件：`SettingsCard` / `SettingsCardGrid` / `SettingsPill` / hover 状态等 |
| `linux/`, `windows/` | 跨平台 fallback 实现（macOS 之外） |

## 设置页（v1.8 sidebar 架构）

```
lib/ui/settings/
├── settings_page.dart      ← 11 行 shell
├── settings_shared.dart    ← 共享：HotkeyCapturer / findHotkeyConflict / settingsRow helper
├── tabs/
│   ├── mode_tab.dart       ← 大文件（1700+ 行），承载多个 sidebar 页面（用 viewFilter 过滤）
│   ├── superpower_tab.dart ← 同上，承载超能力相关页面
│   ├── general_tab.dart    ← 通用 + 快捷键 + 权限三合一
│   └── service_tab.dart    ← 旧 5-tab 时代的云账户 wrap（sidebar 改用 sidebar/pages/cloud_accounts_page）
└── sidebar/
    ├── sidebar_shell.dart  ← 左侧导航 shell + SidebarNavigation InheritedWidget
    ├── sidebar_item.dart   ← 单条导航项
    └── pages/              ← 12 个独立页面，每个 wrap mode_tab/superpower_tab 的对应 viewFilter
```

### sidebar 12 个 entry

```
【概览】overview          — 应用信息 + 4 张 feature 卡 + 帮助支持
【基础】general           — 快捷键 + 基础设置 + 权限三合一
【语音】recognition       — 模式选择 + 语言两卡 + 模型卡
        ai_plus           — AI 润色配置 + 打字机效果 + 系统提示词
        vocab             — 词典（Beta）
        cloud_accounts    — 云账户管理（v1.8.6 起，之前漏了）
【超能力】diary / organize / translate / correction / debug — 5 个独立页
【其他】developer         — 详细日志 / 模型目录 / 配置导入导出 / 系统日志导出
```

## 关键设计决策

### 1. SidebarNavigation InheritedWidget 跨页跳转
sidebar 内任意 page 跳到另一页：
```dart
SidebarNavigation.of(context)?.goto('cloud_accounts')
```
**不要**用旧的 `widget.onNavigateToTab(int)` 数字索引——v1.8 sidebar 已无 5-tab 概念，旧代码视为待清理。

### 2. viewFilter wrapper 而非文件级拆分（v1.8 过渡方案）
`mode_tab.dart` / `superpower_tab.dart` 是大文件，里面用 `enum ModeTabView` / `enum SuperpowerTabView` 控制渲染哪部分。Sidebar 的每个 page 只是简单 wrap：
```dart
class AiPlusPage extends StatelessWidget {
  Widget build(_) => ModeTab(viewFilter: ModeTabView.aiPlus);
}
```
**好处**：一套代码两个入口（旧 5-tab 死代码 + 新 sidebar），改动风险小。
**坏处**：Phase 6 要清理 dead code（旧 5-tab 路径已不可达，源码仍在）。

### 3. SettingsCard / SettingsCardGrid 是设计语言
所有设置项必须用 `SettingsCard`（自动 hover 边框 / 圆角 / 间距）。`SettingsCardGrid` 双列布局，奇数时最后一张半宽占位（`forceDualColumn`）。**不要**手写 `Container` 装边框。

### 4. Card title=null 时 trailing 仍渲染
之前 `title=null` 时会丢失 trailing 开关（Flash Note bug 2026-03-23），已修。**新 SettingsCard 无 title 仍然能用**。

### 5. hover 边框区分点击性
- 可点击卡（`onTap != null`）：hover 时 border → accent 0.4 + click cursor
- 不可点击（纯展示）：hover 时 border → accent 0.22（弱视觉反馈）

### 6. Theme.of(context) 而非硬编码颜色
深色/浅色模式自动切换。**绝不**写 `Color(0xFF...)`，永远走 `AppTheme.getAccent(context) / getBackground(context)` 等 helper。

### 7. i18n 全部走 loc.xxx
所有用户可见字符串（含 toast / snackbar / 横幅）从 `AppLocalizations.of(context)` 取。改 ARB 后跑 `flutter gen-l10n`。

### 8. 跨平台 fallback
`linux/` 和 `windows/` 目录提供 macos_ui 不可用平台的实现。**新增 macOS 功能时考虑**对应平台是否需要 fallback（依据：核心录音/输入路径必须三平台都跑通；UI 装饰可只 macOS）。

## 不要做什么

- ❌ **不要 `import 'lib/engine/...'`** — 走 Service 层
- ❌ **不要硬编码颜色** — 用 `AppTheme.getXxx(context)` 或 `Theme.of(context)`
- ❌ **不要直接 `SharedPreferences`** — 用 `ConfigService()`
- ❌ **不要用 `widget.onNavigateToTab(N)` 跨页跳转**（旧 dead 路径）— 用 `SidebarNavigation.of(context)?.goto(id)`
- ❌ **不要在 sidebar page 里写完整内容** — 用 viewFilter wrap mode_tab/superpower_tab
- ❌ **不要硬编码字符串给用户看** — 走 `loc.xxx`
- ❌ **不要 hardcode 圆角/间距** — 用 4px 网格基准（8/12/16/24/32/48）

## 全局规则（来自全局 CLAUDE.md Flutter UI 设计原则）

- 不用 Inter/Roboto 作为唯一字体
- 不用紫色渐变白底卡片（AI 味默认样式）
- 间距走 4px 基准网格（8/12/16/24/32/48）
- 动画克制，只在有意义的交互上加
- 必须支持深色 / 浅色主题切换
- 响应式：考虑 macOS 窗口 / iPad / iPhone 不同尺寸

## 测试

UI 层测试少（macos_ui 风格难自动化）。手工冒烟：[`docs/release_checklist.md`](../../docs/release_checklist.md)。
