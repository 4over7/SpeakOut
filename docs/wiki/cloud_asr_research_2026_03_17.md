# 云端 ASR 语音识别服务全面调研

> 调研日期：2026-03-17
> 目标场景：macOS 桌面端语音输入应用（SpeakOut），中文普通话为主，兼顾英文和中英混合

---

## 一、总览对比表

| 服务商 | 流式支持 | 中文精度 | 英文精度 | 首字延迟 | 流式价格(元/h) | 非流式价格(元/h) | 免费额度 | 接入复杂度 |
|--------|---------|---------|---------|---------|---------------|----------------|---------|-----------|
| **火山引擎(豆包)** | WebSocket 双向流式 | ★★★★★ | ★★★★ | ~200ms | 1.00 | 0.80 | 试用额度(需申请) | 中 |
| **火山引擎(传统)** | WebSocket | ★★★★ | ★★★★ | ~300ms | 3.50(后付) | 1.80 | 同上 | 中 |
| **阿里云 NLS** | WebSocket | ★★★★☆ | ★★★★ | ~300ms | 3.50(后付) | 2.50 | 新用户3个月试用 | 中 |
| **阿里云百炼 Qwen-ASR** | WebSocket | ★★★★★ | ★★★★★ | ~200ms | 1.19 | - | 未明确 | 低 |
| **阿里云百炼 Gummy** | WebSocket | ★★★★☆ | ★★★★ | ~150ms | 0.54 | - | 未明确 | 低 |
| **阿里云百炼 Paraformer** | WebSocket | ★★★★ | ★★★★ | ~200ms | 0.86 | - | 未明确 | 低 |
| **OpenAI Whisper** | 不支持 | ★★★★ | ★★★★★ | N/A | N/A | ~2.6(≈$0.36) | $5 credits | 极低 |
| **OpenAI GPT-4o Transcribe** | 不支持 | ★★★★☆ | ★★★★★ | N/A | N/A | ~2.6(≈$0.36) | $5 credits | 极低 |
| **OpenAI Realtime API** | WebSocket | ★★★★ | ★★★★★ | ~300ms | ~30+(极贵) | N/A | $5 credits | 中 |
| **腾讯云 ASR** | WebSocket | ★★★★ | ★★★★ | ~300ms | 3.20(后付) | 1.75 | 流式5h/月,文件10h/月 | 中 |
| **百度智能云** | WebSocket | ★★★★ | ★★★☆ | ~400ms | 3.00(后付) | 1.80 | 个人15万次,企业200万次 | 中 |
| **Google Cloud STT** | gRPC 流式 | ★★★☆ | ★★★★★ | ~300ms | ~8.3(≈$0.96/h+) | 同价 | 60分钟/月 | 高 |
| **Azure Speech** | WebSocket/SDK | ★★★★ | ★★★★★ | ~200ms | ~7.3(≈$1/h) | ~2.6(≈$0.36/h) | 5h/月 | 中 |
| **讯飞(语音听写)** | WebSocket | ★★★★★ | ★★★★ | ~200ms | 按次:2.3元/万次 | 同 | 个人1万次,企业10万次 | 低 |
| **讯飞(星火大模型)** | WebSocket | ★★★★★ | ★★★★ | ~200ms | 按次:23元/万次 | 同 | 个人2万次,企业20万次 | 低 |
| **Groq Whisper** | 不支持 | ★★★★ | ★★★★★ | ~50ms(推理) | N/A | ~0.8(≈$0.111/h) | 有免费额度 | 极低 |
| **Deepgram Nova-3** | WebSocket | ★★☆(中文弱) | ★★★★★ | <200ms | ~3.4(≈$0.46/h) | 同价 | $200 credits | 低 |
| **AssemblyAI** | WebSocket | 不支持中文 | ★★★★★ | ~200ms | ~2.7(≈$0.37/h) | 同价 | 免费试用 | 低 |
| **ElevenLabs Scribe v2** | WebSocket | ★★★★ | ★★★★★ | <150ms | ~2.9(≈$0.40/h) | 同价 | 有免费额度 | 低 |
| **Soniox** | WebSocket | ★★★★ | ★★★★★ | <200ms | ~0.87(≈$0.12/h) | ~0.73(≈$0.10/h) | 免费试用 | 低 |

> 注：价格按 1 USD ≈ 7.3 CNY 折算；★ 评级基于公开评测和用户反馈的综合判断

---

## 二、各服务商详细分析

### 1. 火山引擎（字节跳动）

#### 产品线
- **传统流式语音识别**：经典 ASR 引擎
- **豆包语音识别大模型 (Seed-ASR)**：基于 MoE 大语言模型架构，2025年12月发布2.0版
- **一句话识别**：60秒以内短音频

#### 技术特点
- Seed-ASR 在 SpeechIO 公开基准上 CER 达到业界领先（约 2.49%）
- 豆包2.0支持多模态（视觉+语音），可通过图片辅助识别
- 支持13种外语，中文方言覆盖广
- WebSocket 双向流式，16kHz PCM

#### 价格（豆包系列，最具性价比）
| 产品 | 后付费 | 资源包(1000h) |
|------|--------|--------------|
| 豆包流式识别 | 1.00元/h | 0.90元/h |
| 豆包录音文件 | 0.80元/h | 0.75元/h |
| 传统流式识别 | 3.50元/h | 1.80元/h(1000h包) |
| 大模型流式识别 | 4.50元/h | 4.00元/h |

#### 免费额度
- 注册后可在控制台开启试用，具体额度需登录查看
- 创业者加速计划：30人以下初创企业可获3个月免费（价值4.7万元）

#### 接入方式
- WebSocket API + SDK（Java/Python/Android/iOS）
- 鉴权：AppID + Token

#### 适合场景
**中文精度要求极高 + 预算敏感的场景。豆包系列性价比极高（1元/小时），是国内方案中的最优选择之一。**

---

### 2. 阿里云智能语音（NLS）+ 百炼平台

#### 产品线
- **传统 NLS**：实时语音识别、一句话识别、录音文件识别（当前 SpeakOut 使用方案）
- **百炼平台 Qwen-ASR**：千问语音大模型，2026年2月发布 qwen3-asr-flash
- **百炼平台 Gummy**：轻量级流式模型，超低价
- **百炼平台 Paraformer**：开源架构商用版

#### 技术特点
- Qwen3-ASR-Flash 支持30+语言，含普通话方言（四川话、闽南语、吴语、粤语）
- 内置情绪识别（惊讶、平静、喜悦、悲伤、厌恶、愤怒、恐惧）
- Paraformer 支持热词配置，已开源
- 全线支持 WebSocket 流式

#### 价格

**传统 NLS：**
| 产品 | 后付费(0-299h) | 资源包(1000h) |
|------|---------------|--------------|
| 实时语音识别 | 3.50元/h | 1.80元/h |
| 一句话识别 | 3.50元/千次 | 1.80元/千次 |
| 录音文件识别 | 2.50元/h(40h包) | - |

**百炼平台（按秒计费，折算为每小时）：**
| 模型 | 每秒价格 | 折算每小时 |
|------|---------|-----------|
| Qwen3-ASR-Flash | 0.00033元/秒 | **1.19元/h** |
| Gummy | 0.00015元/秒 | **0.54元/h** |
| Paraformer-v2 | 0.00024元/秒 | **0.86元/h** |

#### 免费额度
- 传统 NLS：新用户3个月免费试用
- 百炼平台：未明确公开免费额度

#### 接入方式
- 传统 NLS：WebSocket + SDK（Java/Python/C++等），鉴权 AppKey + AccessKey
- 百炼平台：WebSocket + SDK（Java/Python/Node.js），鉴权 API Key（与百炼大模型同一个 key）

#### 适合场景
**百炼 Gummy 是价格最低的国内流式方案（0.54元/h）。Qwen-ASR 适合需要最高精度的场景。传统 NLS 稳定成熟但价格偏高。作为 SpeakOut 当前方案的升级路径，迁移到百炼平台是最自然的选择。**

---

### 3. OpenAI Whisper / GPT-4o Transcribe / Realtime API

#### 产品线
- **Whisper**：经典非流式转写，$0.006/min
- **GPT-4o Transcribe**：更高精度非流式，$0.006/min，含说话人分离
- **GPT-4o Mini Transcribe**：轻量版，$0.003/min
- **Realtime API**：双向流式对话，支持音频输入输出

#### 技术特点
- Whisper 支持 99+ 语言，中英混合能力强
- GPT-4o Transcribe 基于大模型架构，上下文理解能力强
- Realtime API 基于 WebSocket，但设计目标是语音对话而非纯 ASR
- 文件大小限制 25MB（~30分钟音频）

#### 价格
| 产品 | 价格 | 折算 |
|------|------|------|
| Whisper | $0.006/min | $0.36/h ≈ 2.63元/h |
| GPT-4o Transcribe | $0.006/min | $0.36/h ≈ 2.63元/h |
| GPT-4o Mini Transcribe | $0.003/min | $0.18/h ≈ 1.31元/h |
| Realtime API (音频输入) | ~$0.06/min | ~$3.6/h ≈ 26.3元/h |
| Realtime API (音频输出) | ~$0.24/min | ~$14.4/h ≈ 105元/h |

#### 免费额度
- 新账户 $5 credits（约 833 分钟 Whisper）

#### 接入方式
- Whisper/Transcribe：REST API，极简调用（一个 HTTP 请求 + API Key）
- Realtime API：WebSocket，复杂度较高
- 鉴权：统一 OpenAI API Key（与 GPT/DALL-E 等共用）

#### 关键限制
- **Whisper/Transcribe 不支持流式**，必须录完再识别
- Realtime API 支持流式但**价格极高**（约 26 元/h），且设计目标是语音对话
- 需要海外网络访问

#### 适合场景
**非流式场景的最佳英文方案。GPT-4o Mini Transcribe 性价比优秀。Realtime API 因价格过高不适合纯 ASR 场景。如果 SpeakOut 增加"录完后识别"模式，Whisper 是很好的选择。**

---

### 4. 腾讯云 ASR

#### 产品线
- 实时语音识别、一句话识别、录音文件识别、录音文件极速版、语音流异步识别

#### 技术特点
- 支持普通话、英语、粤语、日语、韩语等 + 闽南话、潮汕话等方言
- WebSocket 流式接口
- 2025年12月更新优化了多语种识别

#### 价格
| 产品 | 后付费(0-299h) | 资源包(1000h) |
|------|---------------|--------------|
| 实时语音识别 | 3.20元/h | 1.80元/h |
| 一句话识别 | 3.20元/千次 | 1.80元/千次 |
| 录音文件识别 | 1.75元/h(月结) | 1.20元/h |

#### 免费额度（每月持续）
- 实时语音识别：**5小时/月**
- 录音文件识别：**10小时/月**
- 一句话识别：**5000次/月**
- 录音文件极速版：**5小时/月**

#### 接入方式
- WebSocket API + SDK（多语言）
- 鉴权：SecretId + SecretKey（腾讯云标准鉴权）

#### 适合场景
**免费额度是国内最慷慨的持续性方案（每月5小时流式免费）。对于低用量用户，可能完全免费使用。精度和价格与阿里云 NLS 相当。**

---

### 5. 百度智能云语音识别

#### 产品线
- 短语音识别标准版/极速版（≤60秒）
- 实时语音识别（流式）
- 录音文件识别

#### 技术特点
- 支持普通话、英语、粤语、四川话等
- 2025年4月发布跨模态端到端语音交互模型
- 短语音识别按次数计费，适合短句场景

#### 价格
| 产品 | 后付费 | 资源包(1000h/千次) |
|------|--------|-------------------|
| 短语音标准版 | 3.40元/千次 | 2.40元/千次 |
| 短语音极速版 | 4.20元/千次 | 3.00元/千次 |
| 实时语音识别 | 3.00元/h | 1.80元/h |

#### 免费额度
- 个人认证：5并发 + **15万次**免费
- 企业认证：10并发 + **200万次**免费

#### 接入方式
- REST API + WebSocket
- 鉴权：API Key + Secret Key（百度云标准鉴权）

#### 适合场景
**免费额度最多（企业200万次），适合初期开发测试。但中文精度和延迟略逊于火山/阿里/讯飞。**

---

### 6. Google Cloud Speech-to-Text

#### 技术特点
- V2 API 含 Chirp 高精度模型（包含在标准价格内）
- 支持 125+ 语言
- gRPC 流式 + REST 批量
- 中文普通话支持，但中文精度一般（非强项）

#### 价格
| 类型 | 价格 |
|------|------|
| 标准模型 | $0.016/min ≈ $0.96/h ≈ 7.0元/h |
| 增强模型 | $0.024/min ≈ $1.44/h ≈ 10.5元/h |
| 动态批量 | ~$0.004/min ≈ $0.24/h ≈ 1.75元/h |

#### 免费额度
- 新用户 $300 GCP credits
- 持续 60 分钟/月免费

#### 接入方式
- gRPC + REST API
- 鉴权：GCP Service Account JSON（复杂）

#### 适合场景
**英文精度一流，但中文非优势。价格偏高，接入复杂。不推荐作为中文优先方案。**

---

### 7. Azure Speech Service（微软）

#### 技术特点
- 支持 100+ 语言，含中文普通话
- WebSocket + SDK 流式
- 完善的说话人分离、自定义语音模型功能
- 与 Azure 生态深度集成

#### 价格
| 类型 | 价格 |
|------|------|
| 实时转写 | $0.017/min ≈ $1.02/h ≈ 7.4元/h |
| 批量转写 | $0.006/min ≈ $0.36/h ≈ 2.6元/h |
| 自定义模型 | $0.048/min + $0.068/h(托管) |

#### 免费额度
- **5小时/月**实时转写免费

#### 接入方式
- SDK（C#/Java/Python/JavaScript/C++/Go/Objective-C/Swift）—— **原生 macOS SDK 支持好**
- WebSocket API
- 鉴权：Azure 订阅 Key

#### 适合场景
**有 macOS 原生 SDK（Objective-C/Swift），接入便利。英文精度极高。但价格在实时场景偏高（7.4元/h）。如果未来需要自定义语音模型或说话人分离，Azure 是好选择。**

---

### 8. 讯飞开放平台

#### 产品线
- **语音听写**（≤60秒短音频，按次计费）
- **实时语音转写**（长音频流式）
- **星火语音识别大模型**（大模型架构，精度更高）
- **语音转写**（离线长音频，5小时以内）

#### 技术特点
- 号称识别率 98%，中文领域传统强者
- 支持 65 语种 + 23 方言 + 普通话方言混合识别
- 星火大模型支持 37 外语 + 202 方言
- 流式接口默认 50 路并发
- 智能标点、动态修正

#### 价格
**语音听写（短音频≤60秒，按次计费）：**
| 套餐 | 次数 | 价格 | 单价 |
|------|------|------|------|
| 套餐一 | 50万次 | 1,300元/年 | 2.6元/千次 |
| 套餐二 | 100万次 | 2,500元/年 | 2.5元/千次 |
| 套餐三 | 1000万次 | 16,000元/年 | 1.6元/千次 |

**星火语音大模型（按次计费）：**
| 套餐 | 次数 | 价格 | 单价 |
|------|------|------|------|
| 套餐一 | 100万次 | 2,300元/年 | 23元/万次 |
| 套餐二 | 250万次 | 5,050元/年 | 20.2元/万次 |
| 套餐三 | 1000万次 | 16,500元/年 | 16.5元/万次 |

#### 免费额度
- 语音听写：个人 1万次/3个月，企业 10万次/3个月
- 星火大模型：个人 2万次/3个月，企业 20万次/3个月

#### 接入方式
- WebSocket API（WebAPI默认50路并发）
- SDK（Android/iOS/PC）
- 鉴权：AppID + APIKey + APISecret

#### 适合场景
**中文方言识别的绝对王者（202种方言）。传统语音听写按次计费对短句语音输入场景非常友好。但星火大模型价格偏高。**

---

### 9. DeepSeek

#### 当前状态
- **没有独立的 ASR API 产品**
- DeepSeek 专注于 LLM（R1, V3 等），未推出语音识别服务
- 研究层面：发表了 eMoE 语音识别架构论文（TouchASP），在 SpeechIO 基准达到 CER 2.49
- 实际使用：需要搭配其他 ASR（如 Whisper）使用

#### 结论
**目前不可用作 ASR 方案。关注其未来是否会推出多模态语音 API。**

---

### 10. Groq Whisper

#### 技术特点
- 基于 LPU 硬件加速，Whisper Large V3 达到 **299x 实时速度**
- 30秒音频约 0.1 秒完成转写
- WER 10.3%（与原版 Whisper 一致）
- **不支持流式**，仅支持文件上传

#### 价格
| 模型 | 价格 | 折算 |
|------|------|------|
| Whisper Large V3 | $0.111/h | ~0.81元/h |
| Whisper Large V3 Turbo | $0.04/h | ~0.29元/h |

#### 免费额度
- 有免费 tier（速率限制较低）

#### 接入方式
- REST API（与 OpenAI 兼容格式）
- 鉴权：Groq API Key
- 文件大小限制：100MB（付费用户）

#### 适合场景
**非流式场景的性价比之王。Whisper V3 Turbo 仅 0.29 元/h，且推理速度极快。如果 SpeakOut 实现"录完后快速识别"模式，Groq 是最佳选择——录 5 秒音频，<50ms 返回结果。**

---

### 11. 其他新兴方案

#### Deepgram
- Nova-3 英文精度领先（WER 5.26%）
- **中文支持弱**：Nova-3 尚未正式支持中文，社区强烈呼求中
- Nova-2 有中文支持但精度一般
- 流式 WebSocket，延迟 <200ms
- 价格：$0.0077/min（Nova-3）
- $200 免费 credits
- **不推荐用于中文场景**

#### AssemblyAI
- Universal-3 Pro Streaming 英文极强
- **不支持中文**（仅英/西/法/德/意/葡）
- $0.37/h，低延迟流式
- **不可用于本项目**

#### ElevenLabs Scribe v2
- 2026年1月发布 Scribe v2 Realtime
- 支持 90+ 语言含中文
- 超低延迟 <150ms
- $0.40/h（标准），$0.28/h（Realtime）
- 英文精度 96.7%（VentureBeat 评测）
- **中文表现待验证，新兴有潜力**

#### Soniox
- 2026年新兴选手，宣称中文 WER 6.6%
- 流式 WebSocket，延迟 <200ms
- **极低价格**：$0.12/h（流式），$0.10/h（批量）
- 支持 60+ 语言
- **价格极具竞争力，但规模和稳定性待验证**

---

## 三、关键维度深度对比

### 1. 中文识别精度排名

1. **讯飞星火大模型** / **火山引擎豆包 Seed-ASR 2.0** — 中文 ASR 的技术天花板，CER ~2.5-3%
2. **阿里云百炼 Qwen3-ASR-Flash** — 千问大模型架构，30+ 语言，精度接近第一梯队
3. **阿里云 NLS** / **腾讯云 ASR** / **讯飞语音听写** — 成熟方案，CER ~4-5%
4. **火山引擎传统 ASR** / **百度智能云** — 中上水平
5. **OpenAI Whisper** / **Azure** — 中文能力可用但非强项
6. **Google Cloud STT** — 中文表现中等
7. **Deepgram / AssemblyAI** — 中文弱或不支持

### 2. 流式/实时能力

**一类：原生流式 WebSocket（推荐）**
- 火山引擎、阿里云（NLS + 百炼）、腾讯云、百度云、讯飞、Azure、Deepgram、Soniox、ElevenLabs

**二类：不支持流式（录完后识别）**
- OpenAI Whisper / GPT-4o Transcribe、Groq Whisper

**三类：流式但不适合纯 ASR**
- OpenAI Realtime API（为语音对话设计，价格极高）

### 3. 价格排名（流式每小时，从低到高）

1. **Groq Whisper V3 Turbo** — 0.29 元/h（非流式）
2. **阿里云百炼 Gummy** — 0.54 元/h
3. **Groq Whisper V3** — 0.81 元/h（非流式）
4. **阿里云百炼 Paraformer** — 0.86 元/h
5. **Soniox** — 0.87 元/h
6. **火山引擎豆包流式** — 1.00 元/h
7. **阿里云百炼 Qwen-ASR** — 1.19 元/h
8. **OpenAI GPT-4o Mini Transcribe** — 1.31 元/h（非流式）
9. **OpenAI Whisper** — 2.63 元/h（非流式）
10. **ElevenLabs Scribe v2** — 2.92 元/h
11. **腾讯云** — 3.20 元/h（后付费）
12. **阿里云 NLS** — 3.50 元/h（后付费）
13. **火山引擎传统** — 3.50 元/h（后付费）
14. **百度云** — 3.00 元/h
15. **Google Cloud STT** — 7.0 元/h
16. **Azure Speech** — 7.4 元/h
17. **OpenAI Realtime API** — ~26 元/h（不推荐纯 ASR）

### 4. 免费额度排名

1. **百度智能云** — 企业 200万次（最多）
2. **Deepgram** — $200 credits（约 43,000 分钟）
3. **讯飞** — 企业 10-20万次
4. **腾讯云** — 每月持续 5h 流式 + 10h 文件（**唯一持续免费**）
5. **阿里云 NLS** — 3个月试用
6. **Azure** — 5h/月（持续）
7. **Google Cloud** — $300 credits + 60min/月
8. **OpenAI** — $5 credits
9. **火山引擎** — 需申请试用

### 5. 接入复杂度（从简到繁）

1. **OpenAI Whisper / Groq** — 一个 REST 请求 + API Key
2. **阿里云百炼** — WebSocket + API Key
3. **讯飞** — WebSocket + 3个Key（AppID/APIKey/APISecret）
4. **火山引擎** — WebSocket + AppID + Token
5. **腾讯云** — WebSocket + SecretId + SecretKey + HMAC签名
6. **阿里云 NLS** — WebSocket + AppKey + AccessKey/Secret + Token
7. **Azure** — SDK + 订阅 Key（SDK 质量高但依赖重）
8. **百度云** — REST/WebSocket + API Key + Secret Key + Access Token
9. **Google Cloud** — gRPC + Service Account JSON + IAM（最复杂）

### 6. 与 LLM 服务共用 Key

| 服务商 | 共用 Key? | 说明 |
|--------|----------|------|
| OpenAI | **是** | Whisper/GPT/DALL-E 全部共用一个 API Key |
| 阿里云百炼 | **是** | Qwen LLM + Qwen-ASR + Paraformer 共用百炼 API Key |
| 火山引擎 | **部分** | 豆包语音和豆包大模型在同一平台，但可能需要不同的 AppID |
| Groq | **是** | Whisper 和 LLM 推理共用同一个 Key |
| 讯飞 | **是** | 星火大模型和语音服务共用 AppID 体系 |
| Google | **是** | 同一 GCP 项目下 Service Account 通用 |
| Azure | **部分** | Speech 和 OpenAI 是不同服务，需要不同 Key |
| 腾讯云/百度 | **是** | 同一云账户体系下 Key 通用 |

### 7. 特殊能力对比

| 能力 | 火山 | 阿里 | OpenAI | 腾讯 | 百度 | Google | Azure | 讯飞 | Groq |
|------|------|------|--------|------|------|--------|-------|------|------|
| 自动标点 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 说话人分离 | ✓ | ✓ | ✓(4o) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| 热词定制 | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| 噪声抑制 | ✓ | ✓ | 内置 | ✓ | ✓ | ✓ | ✓ | ✓ | 内置 |
| 情绪识别 | ✓ | ✓(百炼) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| 方言识别 | ✓ | ✓ | 部分 | ✓ | ✓ | 部分 | 部分 | ✓✓✓ | 部分 |
| 中英混合 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## 四、SpeakOut 场景推荐排名

### 第一梯队：强烈推荐

#### 推荐 1：阿里云百炼 Gummy（流式主力）
- **理由**：价格最低的流式方案（0.54元/h），中文精度好，WebSocket 接口，与现有阿里云体系无缝衔接
- **适合**：日常语音输入，对延迟不极端敏感的场景
- **迁移成本**：低（同为阿里云体系）

#### 推荐 2：火山引擎豆包 Seed-ASR（流式高精度）
- **理由**：中文精度最高之一（CER ~2.5%），价格合理（1元/h），大模型架构理解能力强
- **适合**：对中文精度要求极高的场景
- **迁移成本**：中（需要新建火山引擎账户）

#### 推荐 3：阿里云百炼 Qwen3-ASR-Flash（流式全能）
- **理由**：精度极高，30+ 语言支持强，情绪识别等高级功能，1.19 元/h
- **适合**：需要多语种 + 高精度的全能场景
- **迁移成本**：低

### 第二梯队：特定场景推荐

#### 推荐 4：Groq Whisper V3 Turbo（非流式极速）
- **理由**：0.29 元/h 极致性价比，299x 实时速度意味着几乎无延迟
- **适合**：SpeakOut "录完后识别"模式，松开按键后 <100ms 出结果
- **限制**：不支持流式，需要录完后发送

#### 推荐 5：腾讯云 ASR（免费额度充裕）
- **理由**：每月 5 小时免费流式识别，低用量用户免费
- **适合**：轻度使用、成本敏感用户

#### 推荐 6：讯飞语音听写（方言场景）
- **理由**：202种方言识别无人能及，按次计费对短句友好
- **适合**：需要方言识别的用户群体

### 第三梯队：备选方案

#### 推荐 7：OpenAI Whisper / GPT-4o Mini Transcribe
- **理由**：接入最简单（一个 REST 调用），与现有 LLM Key 共用
- **限制**：无流式，需海外网络

#### 推荐 8：Soniox
- **理由**：超低价（0.87 元/h 流式），中文 WER 6.6%
- **限制**：新兴公司，稳定性和长期可靠性待验证

#### 推荐 9：ElevenLabs Scribe v2
- **理由**：<150ms 超低延迟，90+ 语言
- **限制**：中文精度待验证，价格中等（2.9 元/h）

### 不推荐

- **OpenAI Realtime API**：纯 ASR 场景价格不合理（26 元/h）
- **Google Cloud STT**：中文非强项，价格高，接入复杂
- **Azure Speech**：价格偏高（7.4 元/h），除非需要自定义语音模型
- **Deepgram**：中文支持不足
- **AssemblyAI**：不支持中文
- **DeepSeek**：无 ASR API

---

## 五、SpeakOut 架构建议

### 推荐方案：双引擎 + 可切换

```
用户设置可选：
├── 流式识别引擎（默认）
│   ├── 阿里云百炼 Gummy    — 性价比优先（默认）
│   ├── 阿里云百炼 Qwen-ASR — 精度优先
│   ├── 火山引擎豆包        — 中文最强
│   └── 阿里云 NLS          — 兼容现有（保留）
│
├── 快速识别引擎（录完后识别）
│   ├── Groq Whisper Turbo  — 极速 + 极便宜
│   └── OpenAI Whisper      — 简单可靠
│
└── 离线引擎（现有）
    └── Sherpa-ONNX         — 无网络时使用
```

### 迁移优先级

1. **Phase 1**：接入阿里云百炼 Gummy/Qwen-ASR（与现有阿里云账户体系兼容，API Key 可能共用）
2. **Phase 2**：增加 Groq Whisper 作为"非流式快速识别"选项
3. **Phase 3**：评估火山引擎豆包（需要新开账户，但精度可能更好）
4. **Phase 4**：根据用户反馈和用量数据，优化默认方案

---

## 六、参考资源

### 官方文档
- [火山引擎豆包语音](https://www.volcengine.com/docs/6561)
- [火山引擎计费说明](https://www.volcengine.com/docs/6561/1359370)
- [阿里云百炼实时语音识别](https://help.aliyun.com/zh/model-studio/qwen-real-time-speech-recognition)
- [阿里云百炼 Paraformer/Gummy](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition)
- [阿里云 NLS 价格](https://help.aliyun.com/zh/isi/product-overview/billing-10)
- [OpenAI Pricing](https://developers.openai.com/api/docs/pricing/)
- [腾讯云 ASR 计费](https://cloud.tencent.com/document/product/1093/35686)
- [百度语音识别](https://ai.baidu.com/ai-doc/SPEECH/Tldjm0i4c)
- [Google Cloud STT Pricing](https://cloud.google.com/speech-to-text/pricing)
- [Azure Speech Pricing](https://azure.microsoft.com/en-us/pricing/details/speech/)
- [讯飞语音听写](https://www.xfyun.cn/services/voicedictation)
- [讯飞星火语音大模型](https://www.xfyun.cn/services/speech_big_model)
- [Groq Pricing](https://groq.com/pricing)
- [Deepgram Pricing](https://deepgram.com/pricing)
- [Soniox Pricing](https://soniox.com/pricing/)
- [ElevenLabs Scribe v2](https://elevenlabs.io/realtime-speech-to-text)

### 第三方评测
- [Speech-to-Text APIs in 2026: Benchmarks & Pricing](https://futureagi.substack.com/p/speech-to-text-apis-in-2026-benchmarks)
- [Best Speech-to-Text APIs 2026 (Deepgram)](https://deepgram.com/learn/best-speech-to-text-apis-2026)
- [OpenAI Whisper API Pricing 2026](https://costgoat.com/pricing/openai-transcription)
- [FireRedASR Mandarin Benchmark](https://github.com/FireRedTeam/FireRedASR)
