# 不要按"技术友好性"选 dogfood 试点 App

## 真实事件

**2026-05-07 / Context-Aware Voice 规划阶段**

最初规划文档（`docs/wiki/context_aware_voice_plan_2026_05_07.md`）选 **Mail.app 作为试点**——理由是 AppleScript 完整支持、上下文结构化、formal 语气差异大。

被用户立刻纠正：「我几乎不用 Mail。我最常用的是微信、企业微信、Chrome/Safari、飞书。」

**代价**：如果按原方案做下去，会做出一个用户自己都不会用的功能。dogfood 不可能持续，prompt 永远迭代不出。

修订路径：
- 弃用 Mail 试点
- 改 Generic Adapter（覆盖所有 App）+ Browser Adapter（Chrome/Safari，技术友好且通杀 Web 飞书 / Gmail / Slack Web 等）
- 微信 / 企业微信留到最后做（私有 Cocoa 控件 + 无 AppleScript，技术上最难，但用户高频）

## 为什么会发生

「**用什么标准选试点**」时，agent 容易掉进**技术评估优先**的陷阱：

- AppleScript 支持完整 → 工程上爽 → 选这个
- AX 树清晰 → 调试简单 → 选这个
- Provider 有现成 SDK → 复用率高 → 选这个

但产品角度看，**技术友好的 App 如果用户不用，就等于没做**。dogfood 链路断了：
- 用户不用 → 不会发现 prompt 缺陷
- 用户不用 → 不会反馈体验问题
- 用户不用 → 不会主动测各种边缘情况

最后做出"技术正确但产品死掉"的功能。

## 如何避免

选试点时**两道关**，顺序不能颠倒：

1. **先问用户实际高频用什么**（必要条件）
2. **在用户高频列表里挑技术上最容易做的**（在第 1 满足下的优化）

不能反过来：先列技术友好的 App，再问"你用不用"。

具体做法：

- 对话开头收集"你日常用什么 App"
- 评估清单的**第一列必须是用户实际使用频率**，技术维度放后面
- 如果用户高频列表里全是技术地狱（如本案：微信/企微 都没 AppleScript），可以**双层策略**：
  - Generic Adapter 兜底覆盖全 App
  - 在用户高频列表里挑相对最容易的（本案 Chrome/Safari）做第一个深度 adapter
  - 不要跳出用户高频列表

## 修复模式

如果方案已经基于"技术友好"出炉，意识到错误时：

1. **承认错误**——不要硬把"技术友好"包装成"用户也会用"
2. 把原 Mail 方案标记为"已弃用"（保留在文档里作历史参考），开新方案
3. 用 Generic + 高频里相对最容易的双层策略
4. 把这次踩坑作为反模式落库，避免下次再犯（即本文）

## 相关

- `~/.claude/projects/-Users-leon-Apps-speakout/memory/feedback_pilot_app_selection.md` — 同主题的 agent 个人 feedback
- `docs/wiki/context_aware_voice_plan_2026_05_07.md` — 修订后的方案
