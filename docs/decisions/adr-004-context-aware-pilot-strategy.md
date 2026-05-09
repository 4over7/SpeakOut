# ADR-004: Context-Aware Voice 试点用 Generic + Browser 双层而非单 App

**日期**: 2026-05-07
**状态**: ✅ Accepted（v1.9 规划）
**决策者**: 项目所有者 + AI agent 协助

## 背景

v1.9 规划「Context-Aware Voice」——升级 SpeakOut 从「语音 → 文字」到「语音 + App 上下文 → 合适的文字」。规划过程中需要选 dogfood 试点 App。

第一次提案：**Mail.app 优先做试点**，理由：
- AppleScript 完整支持（To/Subject/Body 都能稳定读）
- 上下文结构化清晰（回复邮件时原邮件可解析）
- formal vs casual 语气差异大，能体现"懂语境"价值

被用户立刻纠正：「我几乎不用 Mail。我最常用的是微信、企业微信、Chrome/Safari、飞书。」

## 选项重新评估

### 用户高频 4 个 App 的技术可行性

| App | 技术栈 | AX 友好度 | 难度 |
|---|---|---|---|
| 微信 Mac | 老 Cocoa（私有控件） | 差 | 🔴 极高 |
| 企业微信 Mac | 类微信 | 差 | 🔴 高 |
| 飞书 Mac | Electron | 中 | 🟡 中 |
| Chrome / Safari | 浏览器 | **高**（标准 AXTextField） | 🟢 中-低 |

### A. 单 App 试点（如 Mail.app）
- ✅ 工程复杂度低，AppleScript 友好
- ❌ **用户不用**——dogfood 链路死掉
- ❌ Mail 路径成熟后，迁移到微信仍需重新摸 AX 路径
- ❌ 违反「[试点选型以用户实际频率为先](../anti-patterns/dont-pick-pilot-by-tech-friendliness.md)」

### B. 单 App 试点（如 Chrome）
- ✅ 用户高频
- ✅ AX 友好
- ❌ 第一周 SpeakOut 在其他 App 都不能用（微信/飞书 等），用户感受到"功能缺失"

### C. Generic + Browser 双层
- ✅ Phase 1 GenericAdapter（仅 AX 焦点元素 + 选区 + 周边）覆盖**所有 App**
- ✅ Phase 2 BrowserAdapter（Chrome/Safari）作为首个深度 adapter
- ✅ 用户第一周就能在任意 App 用上 Smart Voice（即使粗糙版）
- ✅ Browser 通杀网页 Web App（飞书 Web / Gmail / Slack Web / Notion）
- ❌ 实现工作量比单 App 多（要同时完成 Generic 抽象 + Browser 实现）

## 决策

**选 C：Generic + Browser 双层**。

**为什么不是 A 单 App**：违反 dogfood 第一原则。
**为什么不是 B 单 App（Chrome）**：第一周 user 在微信/飞书不能用 → 体感"半成品"。
**为什么 C 是对的**：双层覆盖让 SpeakOut Smart Voice **从 day 1 就在用户所有 App 工作**（虽然粗糙），Browser Adapter 提供深度体验，Phase 3+ 渐进添加飞书 / 企业微信 / 微信。

## 实现路径

```
Phase 1 (3-5 天)
├── GenericAdapter
│   - 仅 macOS Accessibility API
│   - AXFocusedUIElement 焦点元素文本
│   - AXSelectedText 选区
│   - 周边 N 行
│   - 不读历史消息、不读对话
│
└── 全局基础设施
    - workMode.smartVoice 工作模式
    - 独立快捷键（用户主动按下即同意）
    - PromptBuilder + IntentClassifier
    - 隐私 Pipeline 一二层

Phase 2 (3-5 天)
└── BrowserAdapter (Chrome/Safari)
    - AX 标准抓取（textfield / textarea / contenteditable）
    - URL/title 作为语境 hint
    - 网页输入框分类（搜索框 / 表单 / 富文本）

Phase 3 (持续)
└── dogfood + Prompt 调优

Phase 4-6 (v1.x)
└── FeishuAdapter (Electron)
    └── WeComAdapter
        └── WeChatAdapter (最难最后)
```

## 后果

**正面**：
- Day 1 全 App 可用（Generic 基础体验）
- ROI 最高的 App（Browser）优先深耕
- 不被技术地狱（微信私有控件）阻塞主流程

**负面**：
- Phase 1 工作量比单 App 多约 30%（要完成 Adapter 抽象层）
- GenericAdapter 体验天花板低（只读 AX，不读历史/对话）—— 必须在 Browser/Feishu 等深度 adapter 出来后才显出 Smart Voice 真正价值

**重新评估的触发条件**：
- 如果 dogfood 一周后用户主观评分 < 5/10 → 反思是不是 GenericAdapter 太弱（无 context 历史），调整路径
- 如果 BrowserAdapter 实现复杂度远超预期 → 退化到「Generic + 单一深度 adapter」的稳健版本

## 相关

- 设计文档：[`docs/wiki/context_aware_voice_plan_2026_05_07.md`](../wiki/context_aware_voice_plan_2026_05_07.md)
- 反模式归档：[`docs/anti-patterns/dont-pick-pilot-by-tech-friendliness.md`](../anti-patterns/dont-pick-pilot-by-tech-friendliness.md)
- memory：`~/.claude/projects/-Users-leon-Apps-speakout/memory/project_context_aware_voice.md`
