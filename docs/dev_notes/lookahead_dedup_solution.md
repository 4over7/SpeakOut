# Lookahead 流式 ASR：重复文字问题与去重/合并方案（给工程同学）

> 目标：在 **流式 + lookahead/right-context** 的语音输入中，避免 UI 上出现“重复字/重复词”，并保持输入法体验（按住说话实时出字、松开后快速定稿）。

---

## 1. 为什么 lookahead 会导致“重复文字”

很多流式 ASR（尤其加 lookahead）在每次回调里给的不是“纯增量”，而是：

- **A. 当前整句最优假设（full hypothesis so far）**：每次都可能重写前面一部分；
- **B. 近一段窗口的假设（window hypothesis）**：包含与上一窗的 **重叠** 区间；
- **C. partial + final**：结束时 `final` 可能等同于最后一次 `partial`。

如果引擎把 `partial` 当增量直接 append（`text += partial`），就会出现重复。

---

## 2. 方案总览（从推荐到备用）

### ✅ 方案 1（强烈推荐）：把 partial 当“替换”，不是“追加”
**适用：** 回调给的是 *整句假设* 或 *近段假设*（大多数情况）

- 每次 partial 到来：只更新 UI 的 **composition text（组合文本）**，用 **replace** 覆盖显示
- 当 `final/is_final=true` 或 PTT 松开：把 composition **commit** 到最终文本
- **不要**在 final 再做 append（否则会重复一次）

**优点：** 实现最简单、最稳；重复问题基本消失  
**缺点：** 如果你必须分段保留历史（例如很长句），需要配合“稳定前缀提交”（见方案 3）

---

### ✅ 方案 2：重叠对齐去重（Overlap Alignment / LCS）
**适用：** 回调给的是“窗口片段”，每次包含重叠区域（window hypothesis）

思路：只在 **尾部** 做对齐，找到“最大重叠”，把重复部分切掉再拼接。

#### 2.1 简化版：最长前后缀重叠（Longest Overlap）
- `prev = committed + tail`
- `hyp = new_hypothesis`
- 在 `prev` 的最后 N 个字符（或 token）与 `hyp` 的开头做匹配  
- 找到最大重叠长度 `k`
- 合并：`merged = prev + hyp[k:]`

> 推荐参数  
> - 中文：N=30~80 个字  
> - 中英混说：用 token（按空格/标点切）更稳，N=10~30 tokens

#### 2.2 稳健版：LCS（最长公共子序列）
在中英混说、标点抖动时，LCS 比“最长前后缀”更稳，但计算稍重。  
可只对 **尾部窗口**（N 限制）做 LCS，性能可控。

---

### ✅ 方案 3：稳定前缀提交（Stable Prefix Commit）
**适用：** lookahead 导致尾巴抖动/回滚明显，且你想把“确定不再变化”的部分锁定

规则：若某段前缀连续 K 次更新都不变，就把这段前缀从 `tail` 挪到 `committed`。

- 状态：`committed`（稳定前缀）、`tail`（可变尾巴）、`last_hyp`
- 每次新 `hyp` 到来：
  - 计算 `common_prefix = LCP(last_hyp, hyp)`（最长公共前缀）
  - 若 `common_prefix` 连续满足阈值 K（例如 2~4 次），就 commit 一部分（例如 commit 到 `common_prefix` 末尾）
- UI 展示：`committed + tail_current`

**优点：** 既减少重复，也显著减少“回滚抖动”，输入法体验更像系统  
**缺点：** 需要维护更多状态（但非常值得）

---

### 🟡 方案 4：基于时间戳/对齐信息合并（如果模型支持）
**适用：** 模型能返回 token/word 的时间戳（start/end）或对齐信息

- 按时间排序合并
- 重叠时间段只保留置信度更高或更晚更新的 token
- 天然去重、鲁棒性最好

**备注：** 部分 streaming Paraformer 的常见导出不提供 timestamps，此时用方案 2/3 即可。

---

## 3. 推荐落地组合（最少改动、效果最好）

### 3.1 默认组合（建议先实现）
1. **方案 1：partial replace + final commit**（修正 UI 更新语义）
2. 若仍有重复（window hypothesis）：加 **方案 2：尾部重叠对齐**
3. 若尾巴抖动明显：加 **方案 3：稳定前缀提交**

> 经验：90% 的“重复字/重复词”问题，用 **方案 1** 就能解决。

---

## 4. 伪代码（可直接翻成你们的 CoreEngine 逻辑）

### 4.1 Partial replace + final commit（方案 1）
```pseudo
state:
  committed_text = ""   // 已提交、不会变
  composing_text = ""   // UI 上的组合文本（可变）

on_partial(hyp_text):
  composing_text = hyp_text
  UI.show(committed_text + composing_text)   // replace, 不 append

on_final(hyp_text):
  composing_text = hyp_text   // 或直接使用当前 composing_text
  committed_text += composing_text
  composing_text = ""
  UI.show(committed_text)
```

### 4.2 尾部重叠对齐（方案 2：最长重叠）
```pseudo
function merge_with_overlap(prev, hyp, N):
  prev_tail = last_N(prev, N)                   // 只取尾部窗口
  k = max_overlap_suffix_prefix(prev_tail, hyp) // 找最大匹配
  return prev + hyp[k:]

on_partial_window(hyp_text):
  merged = merge_with_overlap(committed_text, hyp_text, N)
  UI.show(merged)     // replace, 不 append
```

### 4.3 稳定前缀提交（方案 3）
```pseudo
state:
  committed = ""
  last_hyp = ""
  stable_hits = 0

on_partial(hyp):
  common = longest_common_prefix(last_hyp, hyp)

  if len(common) >= MIN_STABLE_LEN:
     stable_hits += 1
  else:
     stable_hits = 0

  if stable_hits >= K:
     committed = common        // 或 commit 到词边界
     stable_hits = 0

  tail = hyp[len(committed):]
  UI.show(committed + tail)
  last_hyp = hyp
```

---

## 5. 参数建议（中英混说 + PTT 输入法）

- **重叠对齐窗口 N**
  - 中文：30~80 字
  - 中英混说：10~30 tokens（推荐）
- **稳定前缀**
  - K（连续不变次数）：2~4
  - MIN_STABLE_LEN：10~20 字（或 3~6 个 token）
- **规范化（强烈建议）**
  - 对齐前先做轻量 normalize：空格合并、全角半角、大小写策略、常见标点归一  
  - 中英混说对齐更稳

---

## 6. 常见坑位清单（快速排查）

- **final 事件又 append 一次**：final 应该是 commit/replace，不要 append
- **partial 既输出全量又输出增量**：要确认 SDK 的语义，优先按“全量假设”处理
- **窗口输出没有 overlap**：如果 SDK 输出是纯增量，那就不需要方案 2，只做方案 1/3
- **英文 token 边界被切坏**：对齐用 token/LCS + overlap 0.3~0.8s 的音频窗口更稳

---

## 7. 建议的验证方式（30 分钟）

准备 30~50 条中英混说样本（含英文实体名、噪声、短/长句），对比：
- 是否还有“重复字/重复词”
- partial 回滚是否明显
- 松开到最终稿 p95 是否 < 1s

---

如需我把上述伪代码落到你们具体语言（Swift/Kotlin/C++/Rust）或接入你们现有回调结构（is_final、segment、timestamps 等），把当前回调示例贴出来即可。
