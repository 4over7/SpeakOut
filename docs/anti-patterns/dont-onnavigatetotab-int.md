# 不要用 `onNavigateToTab(int)` 跨页跳转（v1.8 sidebar 后）

## 真实事件

**2026-05-09 / AI Plus「前往账户中心配置」按钮失效**

用户报：AI Plus 设置页里「暂无配置，请添加云服务账户」横幅旁边的「前往账户中心配置」按钮点了**没反应**。

根因连环三层：

1. **AI Plus 页根本没拿到 callback** — `sidebar_shell.dart` 实例化 `AiPlusPage()` 没传 onNavigateToTab，`?? (_) {}` 兜底成空函数
2. **跳转 API 是旧 5-tab 时代的 int 索引** — `mode_tab.dart` 4 处 `widget.onNavigateToTab(2)` / `(3)`，旧 index：
   - `(0)通用 (1)语音输入 (2)超能力 (3)云账户 (4)关于`
   - sidebar 改用字符串 ID（`'overview'` / `'cloud_accounts'` / ...），int 索引根本无法寻址
3. **sidebar 里压根没有云账户入口** — v1.8 重构时漏了

修复后改用 `SidebarNavigation.of(context)?.goto('cloud_accounts')`，并在 sidebar 加云账户 entry。

## 为什么会发生

v1.8 sidebar 重构时为了**降低改动风险**采用 viewFilter wrapper 策略——`mode_tab.dart` / `superpower_tab.dart` 大文件保持原状，sidebar 各 page 只是 `MyTab(viewFilter: xxx)` 简单包装。

代价是：旧代码（含 `onNavigateToTab(int)` prop drilling 链）**仍在 mode_tab 内部**，**仍能编译**，但跑起来全是空函数兜底。新人/agent 看到 `widget.onNavigateToTab(3)` 容易以为它能用。

## 如何避免

跨 sidebar 页跳转**只用一种方式**：

```dart
// ✅ 唯一正确方式
SidebarNavigation.of(context)?.goto('cloud_accounts')
```

`SidebarNavigation` 是 `sidebar_shell.dart` 里定义的 `InheritedWidget`，sidebar 内部任意 widget 都能拿到。

绝对不要：

```dart
// ❌ v1.8 后所有 onNavigateToTab(N) 调用都是 dead 路径
widget.onNavigateToTab(3)
```

新增 sidebar page 时**不要传 onNavigateToTab prop**（旧的 `MyTab` 还接受这个 prop 是兼容性残留，Phase 6 会清理）。

如果你需要的 page 还不存在 → 在 `sidebar_shell.dart` 的 `_buildSections()` 加 `SidebarEntry`，参考 `cloud_accounts` 入口（2026-05-09 新增）。

## 修复模式

如果你看到代码里有 `widget.onNavigateToTab(N)`：

1. 判断 `N` 对应的 sidebar 页（旧 5-tab → 新 sidebar 映射）：
   - 0 (通用) → `'general'`
   - 1 (语音输入) → 看具体场景，可能是 `'recognition'` / `'ai_plus'` / `'vocab'`
   - 2 (超能力) → 看具体功能 `'diary'` / `'organize'` / `'translate'` / `'correction'` / `'debug'`
   - 3 (云账户) → `'cloud_accounts'`
   - 4 (关于) → `'developer'`
2. 改为 `SidebarNavigation.of(context)?.goto('xxx')`
3. 同时 `sidebar_shell.dart` 实例化对应 page 时**不要再传 onNavigateToTab prop**

完整清理（Phase 6）需要删 `mode_tab.dart` / `superpower_tab.dart` / 7 个 sidebar wrapper 的 `onNavigateToTab` 声明 + prop drilling 链。**清理工作单独 commit，不要混进 bug 修复**（见 `dont-feature-creep-in-bug-fix.md`）。

## 相关

- `lib/ui/AGENTS.md` 设计决策 #1「SidebarNavigation InheritedWidget 跨页跳转」
- 修复 commit `f481fca`
