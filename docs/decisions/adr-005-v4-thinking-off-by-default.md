# ADR-005: DeepSeek V4 默认关闭 thinking mode

**日期**: 2026-05-09
**状态**: ✅ Accepted（commit `dbcf730`）
**决策者**: 项目所有者 + AI agent 测速验证

## 背景

2026-05 DeepSeek 发布 V4，模型清单替换：
- 旧 `deepseek-chat` (V3) → 新 `deepseek-v4-flash`（推荐 / 1M 上下文）
- 旧 `deepseek-reasoner` (R1) → 新 `deepseek-v4-pro`（高级 / 1M 上下文）

V4 文档明确写：「Both models support thinking mode (default)」——**V4 默认开启 thinking**。这与 V3 行为不同（V3 `deepseek-chat` 是纯生成）。

实测对比（同次测试，统一中文 ASR 纠错任务）：

| 配置 | TTFT | 总耗时 | vs thinking ON |
|---|---:|---:|---|
| V3 `deepseek-chat`（历史 wiki 数据）| 129ms | ~ | 基线 |
| **V4 Flash · thinking ON（默认）** | 918ms | **2386ms** | — |
| V4 Flash · thinking OFF | 720ms | **1050ms** | ↓ 56% |
| V4 Pro · thinking ON（默认）| 722ms | **6111ms** | — |
| V4 Pro · thinking OFF | 1363ms | 1981ms | ↓ 68% |

V4 默认行为让 SpeakOut 短句纠错总耗时翻 2x 以上，**严重影响用户体验**。

## 选项

### A. 让用户在设置里自己关 thinking
- ✅ 灵活
- ❌ 大多数用户不会点进去改默认
- ❌ 与 SpeakOut「零配置开箱即用」原则冲突

### B. SpeakOut 默认强制关 V4 thinking
- ✅ 用户体验回归到 1 秒级响应
- ✅ 短句纠错任务不需要 CoT，关 thinking 不损失质量
- ❌ 高级用户如果想要 thinking 推理质量，没办法在 SpeakOut 里开启

### C. 短句关、长输入开
- ✅ 平衡
- ❌ "短/长" 边界难定义，状态空间复杂
- ❌ 实际上 SpeakOut 几乎全是短输入（语音输入 1-3 句话），分支用不到

## 决策

**选 B：默认强制关闭 V4 thinking**。

**为什么不是 A**：SpeakOut 是「按下快捷键就工作」的工具，配置项越多越违背产品定位。
**为什么不是 C**：边界定义麻烦，且 SpeakOut 实际使用场景几乎都是短输入，"开 thinking 的分支"是无用代码。

## 实现

`lib/services/llm_service.dart` 加 helper：

```dart
void _applyModelSpecificParams(Map<String, dynamic> body, String model) {
  if (model.startsWith('deepseek-v4')) {
    body['thinking'] = {'type': 'disabled'};
  }
}
```

4 处 OpenAI 兼容 body 构造点都接通：
- `streamCorrectText` 流式调用
- `correctText` 同步调用
- `_callLlmGeneric` (organize / 翻译)
- `routeIntent` 工具路由

不影响 Anthropic / Ollama 路径。

## 后果

**正面**：
- V4 用户即开即用，无需手动关 thinking
- 总耗时回到 1 秒级（V4 Flash thinking OFF 总耗时 1050ms）
- 跨场景统一（不存在"有的功能开 thinking 有的不开"的不一致）

**负面**：
- 高级用户如想用 V4 的 CoT 推理能力，无法通过 SpeakOut 启用——但这不是 SpeakOut 的产品场景，**这是个 feature gap 不是 bug**
- 如果未来 DeepSeek 改了 V5 的字段名（如改为 `enable_thinking: false` 之类），需要更新 helper

**重新评估条件**：
- 用户反馈"想要思考链推理"→ 考虑加可选开关
- DeepSeek 推出 V5 / 其他模型也有 thinking 概念 → 抽象 helper 的判断逻辑

## 性能上下文（横向）

V4 Flash thinking OFF 之后，国内中文 LLM 短句润色性能排名：

| 排名 | 模型 | TTFT | 总耗时 |
|:---:|---|---:|---:|
| 1 | 阿里云 qwen-turbo | 329ms | 518ms |
| 2 | Groq llama-3.3-70b | 426ms | 526ms |
| **3** | **DeepSeek V4 Flash · OFF** | **720ms** | **1050ms** |
| 4 | 智谱 GLM-4-Flash | 1088ms | 1484ms |

DeepSeek V3 时代是国内最快（129ms TTFT 横扫），V4 thinking OFF 退到第 3，但仍可用。

## 相关

- 实现：`lib/services/llm_service.dart` `_applyModelSpecificParams` + 4 处接通
- 测速脚本：`scripts/test_llm_latency.dart`（含 thinking on/off 对照组）
- DeepSeek 文档：`thinking: {"type": "disabled"}` 字段，默认 enabled
- commit：`377068b` (cloud_providers 升级 V4 ID) + `dbcf730` (LLM Service 接通 thinking off)
