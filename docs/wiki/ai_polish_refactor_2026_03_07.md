# AI 润色重构 — 词典从硬替换到 LLM 上下文注入

> 2026-03-07 | 已完成

## 背景

原词汇增强方案是在 LLM 纠错之前做无语境的字符串替换（Phase 1 精确替换 + Phase 2 音近匹配），存在误替换高、覆盖率低、与 LLM 功能重叠等问题。

## 改动总结

### 架构变化

```
旧: ASR → VocabService.applyReplacements → applyWithPhonetic → LLMService.correctText → 输出
新: ASR → LLMService.correctText(vocabHints: [...]) → 输出
        ↘ AI 关闭回退: VocabService.applyReplacements → 输出
```

### 核心改动

| 文件 | 改动 |
|------|------|
| `LLMService` | `correctText` 新增 `vocabHints` 参数，`_buildUserMessage` 构建含 `<vocab_hints>` 的用户消息 |
| `VocabService` | 新增 `getVocabHints()`，移除 `applyWithPhonetic` 及全部拼音相关代码 |
| `CoreEngine` | AI 开 + 词典开 → hints 注入 LLM；AI 关 + 词典开 → 精确替换回退 |
| `ConfigService` | 移除 `vocabPhoneticEnabled` / `vocabPhoneticThreshold` |
| `app_constants.dart` | 默认 prompt 新增 vocab_hints 处理指令 |

### UI 变化

| 变化 | 说明 |
|------|------|
| 侧边栏 | 通用 / 语音模型 / 触发方式 / **AI 润色** / 关于（5 个 tab） |
| AI 润色 tab | 合并 LLM 配置 + 专业词汇，顶部有橙色风险提示横幅 |
| 移除 | 音近匹配开关、阈值滑块 |
| 新增 | 自定义词条 TSV/CSV 导入导出、Beta 标签 |

### 移除的依赖

- `lpinyin: ^2.0.3` — 包体积减少 ~2MB

## 默认 Prompt（新版）

```
你是一个智能助手，负责润色语音转文字的结果。
...（含 vocab_hints 指令，见 app_constants.dart:32）
```

## 相关文件

- 计划文档: `docs/wiki/vocab_llm_integration_plan.md`
- 发版日志: `CHANGELOG.md` v1.5.0
- Golden: `test/goldens/llm_correction_prompt.txt`
