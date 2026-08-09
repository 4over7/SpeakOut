# ADR-006: 离线 ASR 默认引擎改用 Apple SpeechTranscriber，Sherpa 降为兜底

**日期**: 2026-08-09
**状态**: ❌ **Rejected**（2026-08-09 同日，前置验证未通过 —— 实测中文准确率与速度均劣于现有 SenseVoice）
**决策者**: 项目所有者 + AI agent 调研

> ## ❌ 否决结论（先读这段）
>
> 本 ADR 提出的「Apple SpeechTranscriber 作为离线默认引擎」**未通过里程碑 0 的前置验证，不予实施**。
>
> 实测（macOS 26.5.1，同一批中文语料，详见 `docs/wiki/product_simplification_plan_2026_08_09.md`）：
>
> | 维度 | Apple | SenseVoice（现网在用） |
> |---|---|---|
> | 中文技术词 | 声纹→**升文**、润色→**论色**、嘈杂→**朝朝**、方案→**发案** | 声纹识别 ✅、润色 ✅、嘈杂 ✅、方案 ✅ |
> | 速度 | 0.15~0.31s（~25x 实时） | **0.064~0.110s（~55x，快约 2 倍）** |
> | 英语 | 近乎完美 | — |
>
> **两条被证伪的原始论据**：
> 1. ~~「零模型下载」~~ → 中文非出厂自带，需 21.4 秒下载语言包（虽仍优于 228MB，但不是零）
> 2. ~~「比 Whisper Large V3 Turbo 快 55%」~~ → 该对比对象不是 SenseVoice。**SenseVoice 实测比 Apple 还快 2 倍**，属错误类比
>
> **保留本文的原因**：记录「为什么不走 Apple 原生 ASR」，避免未来重复调研。Apple 若更新中文模型，可新建 ADR 重新评估（复测需用真人语音，TTS 语料对中英混说无效）。
>
> **仍然有效的调研产出**（未来可复用）：
> - macOS 26 采用率 86%、SpeechTranscriber **不依赖 Apple Intelligence**
> - 兼容音频格式 **16kHz mono**，与现有 ring buffer 天然对齐
> - API 陷阱：`supportedLocale(equivalentTo:)` 对不支持的语言也返回非 nil，判断支持性必须查 `supportedLocales`
> - `AssetInventory` 有 `maximumReservedLocales` 配额上限
>
> 以下为否决前的原始提案，原文保留。

## 背景

产品方向调整为「**精简：只做透离线 + 云端两种模式，离线为主、云端为辅，只保留必要设置**」。

现状的离线模式是负资产在增长：

- 维护 **9 个可见模型 + 8 个隐藏模型**的注册表、下载、解压、校验、激活、回滚
- 用户装完 App **还要下载 230MB~1.4GB** 才能说第一句话 —— 转化漏斗上的硬伤
- `ModelManager`（~830 行）+ 模型下载 UI + 引导页选模型 + sherpa-onnx FFI 依赖
- 「9 个模型可选」是**伪差异化**：用户不关心，只增加选择负担

macOS 26 (Tahoe) 带来了新变量。

## 调研事实（2026-08-09 核实）

### Apple SpeechTranscriber / SpeechAnalyzer

| 事实 | 来源 |
|---|---|
| macOS 26 采用率 **86.0%**（Sequoia 12.2%），2026-07-27 TelemetryDeck | aboutchromebooks 统计 |
| **不需要 Apple Intelligence** —— 是 Speech framework 的标准 API，只需 macOS 26 + Apple Silicon | Apple 文档 / 多方开发者实测 |
| 比 MacWhisper Large V3 Turbo **快 55%**（34 分钟音频 45 秒转完） | MacRumors / MacStories 实测 |
| 支持 11 语言含**普通话 + 粤语**，支持流中自动语言切换 | Apple 文档 |
| 驱动系统 Notes / Voice Memos / Journal 的转写 | Apple WWDC25 |
| **零模型下载** | — |

### Apple Foundation Models（离线润色）—— 本次不采用

3B 本地模型、专为 text refinement 优化，正好是润色场景。但**依赖 Apple Intelligence**，而中国大陆 2026-07-15 才刚完成监管备案（接入阿里通义千问 + 百度），**官方未公布上线时间与所需系统版本**。SpeakOut 是中文优先产品，不能把主路径压在未上线的能力上。

**处置**：预留接口，不进本期。待 Apple Intelligence 在中国大陆实际可用后重新评估。

### 「那用户为什么还要装 SpeakOut」

这是本决策必须回答的存在性问题。关键区分：**SpeechTranscriber 是给开发者的 API，用户能用的是系统听写（Fn Fn）**，两者不是一回事，且所有竞品都能调用同一个 API。

macOS 26 系统听写的实测短板（2026 年多方评测）：

- 30 秒静音即结束会话，**无设置可改**
- **完全没有自定义词汇表** —— 教不了品牌名 / 术语 / 专有名词
- **标点不稳定**，逗号句号常错位或缺失
- 语言切换靠 Globe 键，非无缝检测
- 技术术语 / 专有名词 / 带口音英语准确率下降
- 只集成 macOS 自家应用，第三方 App 支持有限
- 无任何 AI 后处理

佐证：macOS 26 发布近一年后，Superwhisper / Wispr Flow / MacWhisper 仍在被持续横向评测，Wispr Flow 仍收 $15/月 —— **系统听写没有杀死第三方**。

## 选项

### A. 维持现状（Sherpa 多模型）
- ✅ 不动代码，兼容 macOS 13+
- ❌ 继续背 17 个模型的注册表 + 下载器 + 首次使用必须下载 230MB~1.4GB
- ❌ 与「精简」方向直接冲突

### B. Apple 全面替代，要求 macOS 26+
- ✅ 最彻底：删掉 ModelManager、下载 UI、引导页选模型、sherpa-onnx 依赖
- ✅ 真正零下载、零配置
- ❌ 放弃约 14% 老系统用户
- ❌ Intel Mac 无 Neural Engine，直接失去支持

### C. Apple 默认 + Sherpa 单模型兜底 ← **选中**
- ✅ macOS 26 + Apple Silicon（约 86%）零下载即用
- ✅ 老系统 / Intel 保留 SenseVoice 单模型，不失去用户
- ✅ 模型从 9 个可见砍到 1 个，注册表与选择 UI 大幅简化
- ❌ `ModelManager` 整套仍需保留（服务兜底路径），代码没有减到最少
- ❌ 两条 ASR 路径需要各自测试

## 决策

**选 C**。

**为什么不是 B**：14% 不是小数目，且 Intel Mac 用户被硬砍掉的体验代价过大。保留一个兜底模型的成本，远低于失去这批用户 —— 与 ADR-001「长期主义不等于选最重方案」同源，这里是「精简不等于砍掉能力」。

**为什么不是 A**：首次使用必须下载几百 MB 才能说第一句话，是转化漏斗上的硬伤，也是「少即是多」最该先解决的地方。

## 前置验证条件（必须先做，未通过则回退决策）

⚠️ **所有公开 benchmark 都是英文速度，Apple 模型的中文准确率没有权威数据。** SpeakOut 是中文优先产品（"子曰"），这是成败点。

**里程碑 0（Spike）**：用真实中文语音样本，同一批音频跑 Apple SpeechTranscriber vs 当前 SenseVoice，对比：

1. 中文字准确率（含专有名词、技术术语）
2. **中文标点质量**（系统听写的已知弱项）
3. 首字延迟与总耗时
4. 中英混说场景
5. 粤语（如需）

**判据**：
- Apple 中文准确率与标点 ≥ SenseVoice → 按本 ADR 执行（Apple 默认）
- Apple 明显更差 → **回退为「中文走 Sherpa、其他语言走 Apple」**，本 ADR 需修订后重新评审
- 介于两者之间 → 带数据回来重新决策

**在里程碑 0 通过前，不删除任何现有模型能力。**

## 后果

**正面**：
- 首次使用零下载，装完即用（转化率质变）
- 离线 ASR 速度提升（对标数据：比 Whisper Large V3 Turbo 快 55%）
- 卸掉 17 个模型的维护负担，模型选择 UI 可大幅精简
- 差异化从「我有更好的模型」（伪，高成本）转移到「更好的工作流 + 中文体验」（真）

**负面**：
- 新增一条 Swift 侧 ASR 路径，与现有 Objective-C / FFI 音频链路需要打通
- 两条 ASR 实现并存，测试面变宽
- **护城河变浅**：ASR 不再是壁垒，竞争全在上层体验。对策是把「零配置 + 中文最好」做到位（Superwhisper 公认弱点正是配置过多）

**重新评估条件**：
- Apple 把系统听写做成「全局热键 + 任意 App 注入 + AI 后处理」→ 需要重新审视整个产品定位
- Apple Intelligence 在中国大陆正式可用 → 评估 Foundation Models 做离线润色
- macOS 26 采用率若停滞在 90% 以下 → 兜底路径需长期保留

## 相关

- 实施计划：`docs/wiki/product_simplification_plan_2026_08_09.md`
- 现有离线实现：`lib/engine/providers/sherpa_provider.dart` / `offline_sherpa_provider.dart` / `model_manager.dart`
- 与 ADR-001 同源的判断原则：不因「业界标准 / 平台原生」就无脑选，也不因「自研已有」就拒绝换
