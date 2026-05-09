# 架构决策记录索引（ADR）

> 这里记录 SpeakOut 项目中**经过权衡后做出的关键技术/产品决策**，每条说明背景、所选方案、被否决的方案和原因。

## 这跟 anti-patterns 有什么区别

- **ADR**：「为什么走 X 路而不是 Y 路」——决策结果 + 理由
- **anti-patterns**：「不要做 X」——已经踩过的坑，下次别再来
- **ADR 偏正面**（讲选了什么），**anti-patterns 偏反面**（讲不要做什么）

## 何时新增 ADR

满足以下任一条件就该写 ADR：

1. 选型对**长期架构**有影响（持续 ≥ 1 年）
2. 当时有**明确的备选方案被否决**（要写清为什么否决，否则未来人不知道为啥不走那条）
3. 决策**违反直觉**或**反对常见做法**（如"不引入 Sparkle 框架"反而是合理的）

简单的"这次改用 V4 模型 ID"这种不够格——那是版本升级，不是架构决策。

## 当前 ADR 列表

| 编号 | 标题 | 日期 | 状态 |
|---|---|---|---|
| [ADR-001](./adr-001-no-sparkle.md) | 自动更新不走 Sparkle，用自研 UpdateService | 2026-04-23 | ✅ Accepted |
| [ADR-002](./adr-002-clipboard-injection.md) | 文本注入统一走剪贴板 + Cmd+V | 2025-xx (v1.5.13) | ✅ Accepted |
| [ADR-003](./adr-003-cloud-account-system.md) | 云服务账户体系：多账户 + 凭证分组 | 2026-03-17 | ✅ Accepted |
| [ADR-004](./adr-004-context-aware-pilot-strategy.md) | Context-Aware Voice 试点用 Generic + Browser 双层而非单 App | 2026-05-07 | ✅ Accepted |
| [ADR-005](./adr-005-v4-thinking-off-by-default.md) | DeepSeek V4 默认关 thinking mode | 2026-05-09 | ✅ Accepted |

## ADR 状态语义

- ✅ **Accepted** — 已落地，当前生效
- 🟡 **Proposed** — 草拟中，等评审
- 🔵 **Superseded by ADR-XXX** — 被新 ADR 取代（保留历史）
- 🔴 **Deprecated** — 不再适用但未被 ADR 替代（如功能下线）

## ADR 文件模板

```markdown
# ADR-XXX: <标题>

**日期**: YYYY-MM-DD
**状态**: Accepted / Proposed / Superseded by ADR-YYY
**决策者**: 项目所有者 (+ AI agent 协助)

## 背景

为什么需要这个决策？当时的痛点 / 触发事件是什么？

## 选项

考虑过的方案：
- **选项 A**：xxx
- **选项 B**：xxx
- **选项 C**：xxx

每个选项的优缺点对比。

## 决策

选 X，因为 ...

## 后果

- 正面：...
- 负面：...
- 触发条件 / 何时重新评估
```

## 维护

- ADR 一旦 Accepted **就不应被修改**，只能新建 ADR Supersede 它（保留历史）
- 在 PR / commit 引用时用 `ADR-XXX` 编号，不要直接复制文件内容
