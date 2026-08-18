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
| `settings_page.dart` | shell，直接渲染 `SettingsSidebarShell`（v1.8 后旧 5-tab 已不可达）|
| `chat/` | 聊天页：时间线布局 + dictation 气泡（含 ASR 原文折叠展开） |
| `settings/` | 设置页（**重要，看下文**）|
| `cloud_accounts_page.dart` | 云账户管理（多账户 + 凭证分组卡）。**v1.10 起分层展示**：已启用/已填凭证/`_kRecommendedProviderIds` 内的进主区，其余折叠进「更多服务商」——15 家 provider 一个没删，只是默认不铺开 |
| `vocab_settings_page.dart` | 词典页（行业词典 + 个人词库）+ Beta 徽章 |
| `onboarding_page.dart` | 首次启动引导 |
| `billing_page.dart` | 余额 / 订阅 / Token 历史 |
| `dialogs/` | 弹窗：错误确认、模型下载进度、热键录入器等 |
| `widgets/` | 通用组件：`SettingsCard` / `SettingsCardGrid` / `SettingsPill` / hover 状态等 |
| `linux/`, `windows/` | 跨平台 fallback 实现（macOS 之外） |

## 设置页（v1.8 sidebar 架构）

```
lib/ui/settings/
├── settings_page.dart      ← shell
├── settings_shared.dart    ← 共享：HotkeyCapturer / findHotkeyConflict / settingsRow helper
├── tabs/
│   ├── mode_tab.dart       ← 大文件，承载多个 sidebar 页面（用 viewFilter 过滤）
│   ├── superpower_tab.dart ← 同上，承载超能力相关页面
│   ├── general_tab.dart    ← 通用 + 快捷键 + 权限三合一
│   └── service_tab.dart    ← 旧 5-tab 时代的云账户 wrap（sidebar 改用 sidebar/pages/cloud_accounts_page）
└── sidebar/
    ├── sidebar_shell.dart  ← 左侧导航 shell + SidebarNavigation InheritedWidget
    ├── sidebar_item.dart   ← 单条导航项
    └── pages/              ← 各 sidebar 页面实现，多数 wrap mode_tab/superpower_tab 的对应 viewFilter
```

### sidebar 导航结构

```
【概览】overview          — 应用信息 + feature 卡 + 帮助支持
【基础】general           — 快捷键 + 基础设置 + 权限三合一
【语音】recognition       — 模式选择 + 语言两卡 + 模型卡
        ai_plus           — AI 润色配置 + 打字机效果 + 系统提示词
        vocab             — 词典（Beta）
        cloud_accounts    — 云账户管理（v1.8.6 起，之前漏了）
【超能力】superpower      — 单个 hub 页（`SuperpowerHubPage`），内部聚合
                            diary / organize / translate（v1.10 砍掉纠错反馈与 AI 一键调试）
【其他】developer         — 详细日志 / 模型目录 / 配置导入导出 / 系统日志导出
```

entry 定义在 `sidebar_shell.dart`，改导航只动这一处。

> **v1.9.0**：超能力从 5 个独立 sidebar entry **合并为 1 个 hub 页**。
> **v1.10**：功能本身砍到 3 个 —— **纠错反馈（correction）与 AI 一键调试（aiReport）已整体移除**。
> 若在旧文档/旧代码里看到 `correction` / `debug` / `aiReport`，那是移除前的残留，不要照着复原。

## 关键设计决策

### 1. SidebarNavigation InheritedWidget 跨页跳转
sidebar 内任意 page 跳到另一页：
```dart
SidebarNavigation.of(context)?.goto('cloud_accounts')
```
**不要**用旧的 `widget.onNavigateToTab(int)` 数字索引——v1.8 sidebar 已无 5-tab 概念，旧代码视为待清理。

### 2. viewFilter wrapper 而非文件级拆分（v1.8 过渡方案）
`mode_tab.dart` / `superpower_tab.dart` 是大文件，里面用 `enum ModeTabView { all, recognition, aiPlus }` / `enum SuperpowerView { all, diary, organize, translate }`（注意后者叫 `SuperpowerView`，不是 `SuperpowerTabView`）控制渲染哪部分。Sidebar 的每个 page 只是简单 wrap：
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

## 异步纪律（这层最容易踩的一类）

UI 层几乎每个 handler 都是 `async`，而**页面随时可能在 await 期间消失** ——
sidebar 一换页当前 page 就 dispose，引导页的模型下载更是要跑好几分钟。
三条硬规矩：

### 1. `await` 之后的 `setState` 必须先判 `mounted`

```dart
await ConfigService().setXxx(v);
if (!mounted) return;      // ← 少了这句 → setState() called after dispose()
setState(() {});
```

一次清过 **77 处**。`test/ui/setstate_mounted_guard_test.dart` 会挡住回潮；
它是 AST 判定，`AppLog.d('mounted')` 这种字符串骗不过去。
用 `context` 的地方另外判 `context.mounted`（两者不是一回事）。

**反过来的错更严重：`mounted` 只挡 `setState`，不挡落盘，也不挡全局通知。**

```dart
final dir = await picker();
// ❌ 守卫放这儿 → 页面在选目录期间被关掉，用户选的目录被静默丢弃
if (dir != null) {
  await ConfigService().setLogDirectory(dir);   // 这一步必须发生
  if (!mounted) return;                          // ✅ 守卫放这儿
  setState(() {});
}
```

那次批量补守卫里这个错犯了 **5 次**：日志目录、闪念目录（Swift 侧已经提交了
security-scoped bookmark，Dart 侧不落盘两边就对不上，`DiaryService` 的对账
fail-closed → 闪念根本写不了）、刚录好的快捷键、LLM 模型（preset 存了 model 没存）。
`NotificationService()` 是全局横幅、不依赖本页 context，同样不判 `mounted` ——
判了就变成「操作失败了但用户什么都没看到」。
同一个测试文件的第二条断言守这条反向规则。

### 2. 已经落盘的操作，后续步骤失败必须让用户看见并回滚

典型形态：`await config.setXxx()` 成功 → `await engine.reinit()` 抛异常。
若不接住，异常跑进全局 zone，UI 停在旧值而配置已是新值 ——
**「显示 A 跑 B」**，v1.10.0 为这类问题修过一整批。
接住之后要么回滚配置，要么把错误显示出来，两者都不做等于没修。

### 3. 按钮不许有空回调

`onPressed: () {}` / 空函数体的 helper 看着可点、点了没反应，用户只会以为程序坏了。
暂不支持就传 `onPressed: null`（置灰）并说明原因。
真实事件：模型下载链接按钮的 `_launchUrl` 是个空函数；
Windows/Linux 的快捷键「更改」按钮挂着 `// TODO`。
另外 `launchUrl` **失败时返回 false 而不抛异常**，只 await 不看返回值同样是静默失败。

## 不要做什么

- ❌ **不要 `import 'lib/engine/...'`** — 走 Service 层：engine 能力（ASR/模型/权限/热键流等）经 `AppService()` 的 facade 调用；需要 `ModelInfo`/`ModelArch` 等数据类型时 `import '../services/engine_types.dart'`（已落实，UI 层零 engine import）
- ❌ **不要硬编码颜色** — 用 `AppTheme.getXxx(context)` 或 `Theme.of(context)`
- ❌ **不要直接 `SharedPreferences`** — 用 `ConfigService()`
- ❌ **不要用 `widget.onNavigateToTab(N)` 跨页跳转**（旧 dead 路径）— 用 `SidebarNavigation.of(context)?.goto(id)`
- ❌ **不要在 sidebar page 里写完整内容** — 用 viewFilter wrap mode_tab/superpower_tab
- ❌ **不要硬编码字符串给用户看** — 走 `loc.xxx`
- ❌ **不要 hardcode 圆角/间距** — 用 4px 网格基准（8/12/16/24/32/48）
- ❌ **不要给按钮空回调** — 见上「异步纪律 3」
- ❌ **不要在 await 后裸调 setState** — 见上「异步纪律 1」

## 全局规则（来自全局 CLAUDE.md Flutter UI 设计原则）

- 不用 Inter/Roboto 作为唯一字体
- 不用紫色渐变白底卡片（AI 味默认样式）
- 间距走 4px 基准网格（8/12/16/24/32/48）
- 动画克制，只在有意义的交互上加
- 必须支持深色 / 浅色主题切换
- 响应式：考虑 macOS 窗口 / iPad / iPhone 不同尺寸

## 测试

渲染层难自动化，`test/ui/` 里两类混着放 —— **看清楚哪条是哪类**：

| 测试 | 类型 | 守什么 |
|---|---|---|
| `setstate_mounted_guard_test.dart` | 纪律（AST 扫全 `lib/`） | await 后的 setState 必须判 mounted |
| `service_error_handling_test.dart` | 纪律（AST 扫全 `lib/`） | Service 抛出的错误 UI 必须接住 |
| `notification_queue_test.dart` | 行为 | 通知队列：error 不被后来的 info 顶掉 |
| `notification_mounted_test.dart` | 行为 | 横幅真的挂在 widget 树上 |
| `scaffold_messenger_unavailable_test.dart` | 行为 | MacosApp 下没有 ScaffoldMessenger 祖先，别去 `of(context)` |
| `diagnostics_bundle_test.dart` | 行为 | 报障包含 `speakout_errors.log` |

纪律类断言只能证明「代码还长这样」，证明不了「跑起来是对的」——
边界与教训见 [`docs/anti-patterns/dont-let-source-text-assertions-prove-behavior.md`](../../docs/anti-patterns/dont-let-source-text-assertions-prove-behavior.md)。

其余靠手工冒烟：[`docs/release_checklist.md`](../../docs/release_checklist.md)。
