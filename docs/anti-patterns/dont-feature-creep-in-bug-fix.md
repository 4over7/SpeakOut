# 不要在修 bug 时顺手 refactor 不相关代码

## 真实事件

**多次发生**，最近一次：2026-05-09 修 AI Plus「前往账户中心配置」跳转 bug。

修复涉及 5 处 `widget.onNavigateToTab(N)` 改成 `SidebarNavigation.of(context)?.goto(...)`。改完后 `mode_tab.dart` / `superpower_tab.dart` 里的 `onNavigateToTab` prop 已经无人调用，理论上可以删除整条 prop drilling 链（含 7 个 sidebar wrapper page 的 prop 声明）。

**第一直觉是顺手清理**——反正都改了，一起删干净。但本次任务目标是「修 bug」，不是「清理 dead code」。如果一起做：
- 改动文件从 5 个变成 12+ 个
- 编译错误链可能扩散
- 出问题 bisect 很难分清"bug 修复挂了"还是"清理挂了"
- review 难度倍增

最终决定**保留 dead prop，只改 5 处调用**。Phase 6 dead code 清理另起 commit 做。

## 为什么会发生

修 bug 过程中扫描到「相关但不直接相关」的代码，是常态。修 navigation bug 自然会看到 navigation 相关的所有代码——其中一部分明显是 dead 的、风格不一致的、可以优化的。

「反正手都伸进来了，顺便扫一下」的诱惑很强。但这种扩张会带来：

1. **Diff 难以审阅**——bug 修复 5 行变成 50 行，reviewer 抓不住重点
2. **回滚困难**——bug 修复挂了想 revert，会把无关清理一起 revert
3. **测试覆盖不全**——bug 修复有明确的复现场景，顺手改的部分没有
4. **承诺超出能力**——你以为 30 分钟修完，实际 2 小时还在调清理引入的副作用

## 如何避免

每次开始 commit 前问自己：

> "我这次 commit 的目标是 X。当前 diff 里有几行不是为 X 服务的？"

非 X 服务的行 → 拆出来下次再做。

具体做法：

- **进入修 bug 状态前明确 scope**——例：「修 navigation 跳转，不动 prop drilling」
- **看到顺手清理的诱惑时，记 TODO**：在 task list 加新 task「清理 onNavigateToTab dead prop chain」放下次做
- **commit 拆分**：如果一次实现里真有两件事（罕见），拆两个 commit
- **diff 自检**：commit 前 `git diff --stat`，超过预期文件数就停下来重新审视 scope

## 修复模式

如果 commit 已经把 bug fix + 顺手清理混在一起：

- **如果还没 push**：`git reset --soft HEAD^` 回到 staged 状态，按 scope 拆两次 commit
- **如果已经 push**：不再 force push（破坏历史）；下个 commit 显式说明"上一个 commit 包含了 X + Y"

## 相关

- 全局 CLAUDE.md「Don't add features, refactor, or introduce abstractions beyond what the task requires」
- 前段 v1.8 sidebar 重构 memory 写了 viewFilter wrapper 路径「Phase 6 要清理 dead code」 —— 那次是显式留 dead code 的决策，不是顺手清理
