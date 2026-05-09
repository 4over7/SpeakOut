# 反模式索引

> 这里记录 SpeakOut 项目里**已经踩过坑、不要再做的事**。每条都源自真实事件，不是空想。新人 / agent 改代码前应扫一眼，避免重复踩雷。

> 维护原则：每条反模式必须包含「真实事件 / 时间」。空想出来的"最佳实践"不进这个目录——那种东西放 `docs/standards/`。

## 当前反模式清单

### 🚧 工程实践

| 文件 | 一句话 |
|---|---|
| [`dont-feature-creep-in-bug-fix.md`](./dont-feature-creep-in-bug-fix.md) | 修 bug 时不要顺手 refactor 不相关代码 |
| [`dont-skip-full-test-on-release.md`](./dont-skip-full-test-on-release.md) | 发版必跑完整 `flutter test`，不要问"是否跳过" |
| [`dont-amend-after-hook-failure.md`](./dont-amend-after-hook-failure.md) | pre-commit hook 失败后用新 commit 修，不要 `--amend` |

### 🏗️ 架构铁律

| 文件 | 一句话 |
|---|---|
| [`dont-bypass-configservice.md`](./dont-bypass-configservice.md) | 不要直接 `SharedPreferences.getInstance()`，必须走 `ConfigService` |
| [`dont-onnavigatetotab-int.md`](./dont-onnavigatetotab-int.md) | sidebar 跨页跳转用 `SidebarNavigation.goto(id)`，不要用旧的 `onNavigateToTab(int)` |

### 🎯 产品决策

| 文件 | 一句话 |
|---|---|
| [`dont-pick-pilot-by-tech-friendliness.md`](./dont-pick-pilot-by-tech-friendliness.md) | 选 dogfood 试点 App 时，用户实际高频 > 技术友好性 |

## 何时新增条目

把你正在写下的"反模式"代入下面 3 个问题：

1. **是否源自真实事件？** 没有 → 不进这里（属于"最佳实践"，不是踩坑教训）
2. **是否对 1-2 句话能讲清楚的下次决策有用？** 没有 → 不进这里（太抽象的话约束不了未来行为）
3. **是否会被"读 CLAUDE.md 就能避免"？** 是 → 不进这里（在 CLAUDE.md / AGENTS.md 加约束就够）

通过 3 个问题的才进 `docs/anti-patterns/`。

## 文件格式

每个反模式文件按以下结构（约 40-80 行）：

```markdown
# 不要 ...

## 真实事件
（时间 + 事件 + 代价）

## 为什么会发生
（根因，1-3 段）

## 如何避免
（具体操作 / 工具 / 规则）

## 修复模式
（如果已经发生了，怎么改回来）
```
