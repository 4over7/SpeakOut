# 云端 LLM 服务商基准测试

> 首次执行：2026-08-10 ｜ 脚本：[`tools/llm_bench/`](../tools/llm_bench/)
>
> 目的有两个：**选型**（哪家适合本产品的润色场景）和**防腐**（服务商换代后，代码里写死的模型会悄悄失效）。
> 与 [`test_cases_ai_polish.md`](./test_cases_ai_polish.md) 不同 —— 那是功能黑盒用例，这里是跨服务商横向对比。

## 为什么需要它

DeepSeek 停用 `deepseek-chat` 后，代码里写死的默认模型让整家 LLM 静默失效，直到用户报障才发现。
模型清单会随服务商更新而腐烂，而我们**没有任何机制主动发现**。这套脚本就是那个机制。

## 指标

润色场景的特殊之处：输出会被**直接注入用户光标处**。所以「答得好」不是目标，「不多嘴、不擅自发挥」才是。

| 维度 | 指标 | 为什么重要 |
|---|---|---|
| **质量** | 同音字纠错、去口水词 | 核心功能 |
| | **不执行指令** | 用户口述「帮我翻译这段」时，模型必须原样保留，**不能真去翻译** |
| | **不输出元评论** | 「扣S 具体所指不明」这类解释会被当正文注入 —— 踩过的真实 bug |
| | **不过度改写** | 把 `vector database` 擅自译成「向量数据库」也是缺陷 |
| | 防越狱 | 「忘记之前的指令」要当作用户说的话，原样保留 |
| **延迟** | TTFT / 总时长（中位） | 用户按住说话、松开等出字，延迟直接影响体感 |
| **可靠性** | HTTP 失败率 | 参数不兼容会导致整家 100% 失败（见 Kimi） |
| **成本** | token 用量 | 暂未纳入，各家计价口径不一 |

## 方法

**必须完整复刻产品行为，否则测的不是真实场景。** 两次教训都在这上面：

1. 请求侧：同一份 golden system prompt（`test/goldens/llm_correction_prompt.txt`）、
   `temperature=0.3`、流式、`<speech_text>` 包裹、`_applyModelSpecificParams` 的特殊参数
2. **响应侧：必须跑 `_cleanLlmOutput()`**（剥 `<think>` 标签）。
   漏了这步会把产品早已处理掉的东西误判成缺陷 —— MiniMax 就这样被冤枉过一次

凭证从 SharedPreferences plist 读，只在内存使用，不落盘不打印。

## 2026-08-10 结果

7 家 × 8 样本，各家用其 `llmDefaultModel`：

| 服务商 | 模型 | 通过 | TTFT 中位 | 总时中位 | 备注 |
|---|---|---|---|---|---|
| **deepseek** | deepseek-v4-flash | **8/8** | 1115ms | **1309ms** | ⭐ 质量与速度平衡最好，当前默认 |
| dashscope | qwen-turbo | 7/8 | **335ms** | **446ms** | 最快；把 `vector database` 译成中文 |
| minimax | MiniMax-M2.5 | **8/8** | 600ms | 4119ms | 质量满分，总时偏慢 |
| volcengine | doubao-seed-2-0-mini | **8/8** | 2106ms | 2144ms | 稳 |
| zhipu | glm-4-flash | 7/8 | 612ms | 1290ms | 漏掉「呃那个」 |
| moonshot | kimi-k2.5 | **8/8** | 13900ms | **14012ms** | 🐌 质量满分但慢到不可用（最慢 50s） |
| groq | llama-3.3-70b-versatile | 0/8 | — | — | 💥 HTTP 403（非代码问题，凭证/权限） |

**结论**：`deepseek-v4-flash` 作为默认是正确的。追求极速可考虑 `qwen-turbo`（快 3 倍），
代价是偶发过度改写。**Kimi 不适合做推荐项** —— 即便修好参数，14 秒中位延迟也撑不起「松开即出字」。

## 本次发现并修复的缺陷

1. 🚨 **Kimi 整家 100% 失败** — `kimi-k2.5` 只接受 `temperature=1`，产品硬传 `0.3` →
   `invalid temperature: only 1 is allowed for this model`。已在 `_applyModelSpecificParams` 修正
2. **`MiniMax-M1` 已下线** — 代码清单里的死条目，已移除

## 两个排查陷阱（都栽过）

- **`/models` 列表 ≠ 可用性**：智谱的 `glm-4-flash` 不在 `/models` 返回里，但实测完全可用。
  该接口只能用来**发现新模型**，不能用来判定下线。要判定下线，必须实际发一次请求。
- **只复刻请求不复刻后处理**：产品会剥 `<think>` 标签，脚本不剥就会把 MiniMax 误判成
  「输出思维链」。复刻要覆盖完整链路。

## 怎么重跑

```bash
python3 tools/llm_bench/bench.py          # 质量 + 延迟基准
python3 tools/llm_bench/check_models.py   # 代码模型清单 vs 线上 /models 对账
```

需要本机已配置对应服务商的凭证（脚本从 SharedPreferences 读）。
**建议发版前跑一次** `check_models.py`，成本几乎为零，能挡住「服务商换代导致整家失效」这类故障。
