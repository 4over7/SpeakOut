# 云服务商 ASR & LLM 鉴权机制全面调研

> 调研日期：2026-03-17
> 覆盖范围：14 家主流云服务商的语音识别 (ASR) 和大语言模型 (LLM) 鉴权体系
> 核心问题：同一服务商的 ASR 和 LLM 是否共用凭证？各自需要什么参数？
> 适用场景：任何需要集成多家云 AI 服务的应用开发

---

## 总览表

| # | 服务商 | ASR 服务 | LLM 服务 | 凭证共用？ | ASR 凭证 | LLM 凭证 | 同一控制台？ |
|---|--------|----------|----------|-----------|----------|----------|-------------|
| 1 | 阿里云百炼 (DashScope) | Paraformer V2, SenseVoice | 通义千问 | **Yes** | DashScope API Key | DashScope API Key | 同一（百炼控制台） |
| 2 | 火山引擎 | Seed-ASR (豆包语音) | 豆包大模型 (方舟) | **No** | AppID + Token + Cluster | 方舟 API Key + Endpoint ID | 不同控制台 |
| 3 | OpenAI | Whisper, GPT-4o Transcribe | GPT-4o, GPT-4o-mini | **Yes** | OpenAI API Key | OpenAI API Key | 同一 (platform.openai.com) |
| 4 | Groq | Whisper Large V3 Turbo | Llama, Mixtral 等 | **Yes** | Groq API Key | Groq API Key | 同一 (console.groq.com) |
| 5 | 腾讯云 | 实时语音识别 | 混元大模型 | **No** | SecretId + SecretKey + AppID (签名鉴权) | 混元 API Key (Bearer Token) | 不同产品控制台 |
| 6 | 讯飞 | 语音听写 (IAT) | 星火大模型 | **部分共用** | AppID + APIKey + APISecret (HMAC-SHA256) | APIPassword (Bearer Token) 或 AppID + APIKey + APISecret (WebSocket) | 同一平台不同应用 |
| 7 | 百度智能云 | 短语音/实时语音识别 | 文心一言 (ERNIE) | **No** | API Key + Secret Key → OAuth Token | 千帆 API Key (Bearer Token) | 不同产品控制台 |
| 8 | Google | Cloud Speech-to-Text | Gemini API | **No** | Service Account (GCP) | API Key (Google AI Studio) | 完全不同平台 |
| 9 | Azure/Microsoft | Azure Speech Service | Azure OpenAI Service | **No** | Speech Resource Key + Region | Azure OpenAI Key + Endpoint + Deployment ID | 不同 Azure 资源 |
| 10 | Anthropic | 无 ASR | Claude 系列 | N/A（纯 LLM） | — | x-api-key | — |
| 11 | DeepSeek | 无 ASR | deepseek-chat/reasoner | N/A（纯 LLM） | — | API Key (Bearer Token) | — |
| 12 | 智谱 (GLM) | 无独立 ASR（可能有多模态语音能力） | GLM-4 系列 | N/A（纯 LLM） | — | API Key (JWT) | — |
| 13 | MiniMax | 无 ASR（仅有 TTS） | MiniMax-M2.5 | N/A（纯 LLM） | — | API Key (Bearer Token) | — |
| 14 | Moonshot (Kimi) | 无 ASR | kimi-k2.5 | N/A（纯 LLM） | — | API Key (Bearer Token) | — |

---

## 各服务商详细分析

### 1. 阿里云百炼 (DashScope)

**结论：ASR 和 LLM 共用同一个 DashScope API Key** ✅

- **凭证类型**：DashScope API Key（Bearer Token 格式）
- **鉴权方式**：`Authorization: Bearer $DASHSCOPE_API_KEY`
- **共用情况**：百炼平台统一 API Key，一个 key 可同时调用 LLM（通义千问系列）和 ASR（Paraformer V2、SenseVoice 等）
- **控制台**：[百炼控制台](https://bailian.console.aliyun.com/) → 密钥管理
- **额外参数**：调用时指定 model 即可（如 `paraformer-v2`、`qwen-turbo`）
- **注意**：旧版阿里云 NLS（智能语音交互）使用不同的 AccessKey ID + AccessKey Secret + AppKey 体系，与百炼 DashScope 完全独立

**当前代码状态**：`cloud_providers.dart` 中 `dashscope` 只定义了一个 `api_key` 字段 → **已正确**

---

### 2. 火山引擎 (Volcengine)

**结论：ASR 和 LLM 使用完全不同的凭证体系** ❌ 不共用

#### LLM（方舟平台 / Ark）
- **凭证类型**：方舟 API Key
- **鉴权方式**：`Authorization: Bearer $ARK_API_KEY`
- **额外参数**：Endpoint ID（推理接入点，每个模型部署后生成）
- **控制台**：[方舟控制台](https://console.volcengine.com/ark/)

#### ASR（豆包语音 / 语音技术）
- **凭证类型**：AppID + Access Token + Cluster ID
- **鉴权方式**：WebSocket 连接时在请求体中携带 `{"app": {"appid": "", "token": "", "cluster": ""}}`
- **额外参数**：Cluster（业务集群 ID，开通服务后在控制台显示）
- **控制台**：[语音技术控制台](https://console.volcengine.com/speech/app)（与方舟是不同的产品线）

**当前代码状态**：`cloud_providers.dart` 中 `volcengine` 定义了 `api_key` + `app_id` → **不完整**，缺少 ASR 所需的 `token` 和 `cluster` 字段。且 `api_key` 只能用于 LLM，ASR 需要单独的 `token`

**建议**：需要为火山引擎拆分 ASR 和 LLM 的凭证，或增加 `token`、`cluster` 字段

---

### 3. OpenAI

**结论：ASR 和 LLM 共用同一个 API Key** ✅

- **凭证类型**：OpenAI API Key（`sk-` 前缀）
- **鉴权方式**：`Authorization: Bearer $OPENAI_API_KEY`
- **共用情况**：同一个 API Key 可调用所有 OpenAI 服务（Chat Completions、Audio Transcription、Image Generation 等）
- **控制台**：[OpenAI Platform](https://platform.openai.com/api-keys)
- **额外参数**：调用 ASR 时指定 model（`whisper-1`、`gpt-4o-transcribe` 等）+ 音频文件
- **权限控制**：可通过 Project Keys 限制特定项目的 API 访问范围

**当前代码状态**：`cloud_providers.dart` 中 `openai` 只定义了 `api_key` → **已正确**

---

### 4. Groq

**结论：ASR 和 LLM 共用同一个 API Key** ✅

- **凭证类型**：Groq API Key（`gsk_` 前缀）
- **鉴权方式**：`Authorization: Bearer $GROQ_API_KEY`
- **共用情况**：同一个 key 调用 LLM 和 Audio Transcription（Whisper）
- **控制台**：[Groq Console](https://console.groq.com/keys)
- **额外参数**：指定 model（`whisper-large-v3-turbo` 等）+ 音频文件
- **API 格式**：与 OpenAI 兼容（`/openai/v1/audio/transcriptions`）

**当前代码状态**：`cloud_providers.dart` 中 `groq` 只定义了 `api_key` → **已正确**

---

### 5. 腾讯云

**结论：ASR 和 LLM 使用不同的鉴权体系** ❌ 不共用

#### ASR（实时语音识别）
- **凭证类型**：SecretId + SecretKey + AppID
- **鉴权方式**：HMAC-SHA1 签名，签名拼接到 WebSocket URL 参数中
- **连接 URL**：`wss://asr.cloud.tencent.com/asr/v2/<appid>?...&signature=xxx`
- **控制台**：[语音识别控制台](https://console.cloud.tencent.com/asr)

#### LLM（混元大模型）
- **凭证类型**：混元 API Key（OpenAI 兼容模式）或 SecretId/SecretKey（云 API 签名 v3）
- **鉴权方式**：
  - OpenAI 兼容接口：`Authorization: Bearer $HUNYUAN_API_KEY`（推荐，更简单）
  - 原生接口：云 API 签名方法 v3（使用 SecretId + SecretKey）
- **控制台**：[混元控制台](https://console.cloud.tencent.com/hunyuan/api-key)

**分析**：虽然原生接口的 SecretId/SecretKey 理论上通用于腾讯云所有服务，但 ASR 需要额外的 AppID 参数。混元的 OpenAI 兼容接口使用独立的 API Key，与 ASR 的签名鉴权完全不同。

**当前代码状态**：`cloud_providers.dart` 中 `tencent` 定义了 `secret_id` + `secret_key`，仅标记 ASR 能力 → **如果要添加 LLM 能力，需要增加 API Key 字段或让用户选择鉴权模式**

---

### 6. 讯飞

**结论：ASR 和 LLM 部分共用凭证，但鉴权方式不同** ⚠️ 部分共用

#### ASR（语音听写 IAT）
- **凭证类型**：AppID + APIKey + APISecret
- **鉴权方式**：HMAC-SHA256 签名，拼接到 WebSocket URL 的 `authorization` 参数
- **控制台**：[讯飞开放平台控制台](https://console.xfyun.cn/) → 我的应用

#### LLM（星火大模型）
- **HTTP 调用**：APIPassword（Bearer Token 格式，`Authorization: Bearer $API_PASSWORD`）
  - APIPassword 在星火控制台单独获取，**与 ASR 的 APIKey/APISecret 不同**
- **WebSocket 调用**：AppID + APIKey + APISecret（与 ASR 相同的凭证格式）
  - 但 **注意**：即使凭证字段名相同，ASR 和 LLM 的 AppID/APIKey/APISecret 可能是不同应用下的不同值

**分析**：讯飞同一个应用下的 AppID/APIKey/APISecret 可以同时用于 ASR 和 LLM WebSocket 接口，但如果使用星火 HTTP 接口则需要单独的 APIPassword。当前项目使用 OpenAI 兼容格式调用星火（通过 `spark-api-open.xf-yun.com/v1`），这需要 APIPassword，与 ASR 凭证不同。

**当前代码状态**：`cloud_providers.dart` 中 `xfyun` 定义了 `app_id` + `api_key` + `api_secret`，同时标记 ASR 和 LLM 能力 → **对 ASR 正确，但 LLM HTTP 接口实际需要的是 APIPassword 而非 APIKey/APISecret。需要确认项目的 LLM 调用使用哪套凭证**

---

### 7. 百度智能云

**结论：ASR 和 LLM 使用不同的凭证体系** ❌ 不共用

#### ASR（语音识别）
- **凭证类型**：API Key + Secret Key → 换取 OAuth Access Token
- **鉴权方式**：先用 API Key + Secret Key 调用 `https://aip.baidubce.com/oauth/2.0/token` 获取 access_token，再在请求中携带 token
- **控制台**：[百度 AI 开放平台](https://ai.baidu.com/) → 应用管理
- **有效期**：Access Token 有效期 30 天

#### LLM（文心一言 / ERNIE — 千帆平台）
- **凭证类型**：千帆 API Key（Bearer Token）
- **鉴权方式**：`Authorization: Bearer $QIANFAN_API_KEY`
- **控制台**：[千帆大模型平台](https://console.bce.baidu.com/qianfan/ais/console/applicationConsole/application)
- **注意**：千帆平台也曾支持 AK/SK 鉴权（类似 ASR），但已推荐迁移到 API Key 方式

**分析**：百度语音识别属于"百度 AI 开放平台"，文心一言属于"千帆大模型平台"，虽然都在百度智能云生态下，但是不同的产品线，凭证不互通。

**当前代码未包含百度** → 如需添加，ASR 和 LLM 需要不同的凭证字段

---

### 8. Google

**结论：ASR 和 LLM 使用完全不同的鉴权体系** ❌ 不共用

#### ASR（Cloud Speech-to-Text）
- **凭证类型**：GCP Service Account（JSON 密钥文件）或 API Key + OAuth 2.0
- **鉴权方式**：Service Account 认证（推荐），通过 `GOOGLE_APPLICATION_CREDENTIALS` 环境变量指定 JSON 密钥文件
- **控制台**：[Google Cloud Console](https://console.cloud.google.com/) → APIs & Services
- **额外参数**：Project ID、Region（可选）
- **计费**：GCP 计费账户

#### LLM（Gemini API）
- **凭证类型**：简单 API Key
- **鉴权方式**：URL 参数 `?key=API_KEY` 或 `Authorization: Bearer $GEMINI_API_KEY`
- **控制台**：[Google AI Studio](https://aistudio.google.com/app/apikey)（与 GCP Console 不同）
- **注意**：Gemini 也可以通过 Vertex AI（GCP）调用，此时使用 Service Account，与 Cloud STT 相同体系

**分析**：Google AI Studio 的 Gemini API Key 和 GCP 的 Service Account 是完全不同的鉴权体系。如果统一使用 GCP（Vertex AI + Cloud STT），则可以共用 Service Account，但目前 Gemini API 更常用 AI Studio 的简单 API Key。

**当前代码状态**：`cloud_providers.dart` 中 `gemini` 只定义了 `api_key`，仅标记 LLM 能力 → **已正确（不含 ASR）**

---

### 9. Azure / Microsoft

**结论：ASR 和 LLM 使用完全不同的资源和密钥** ❌ 不共用

#### ASR（Azure Speech Service）
- **凭证类型**：Speech Resource Key（`Ocp-Apim-Subscription-Key`）
- **鉴权方式**：直接使用 Resource Key，或先换取 Bearer Token（有效期 10 分钟）
- **额外参数**：Region（如 `eastus`、`southeastasia`）
- **Endpoint 格式**：`https://<region>.stt.speech.microsoft.com/speech/recognition/...`
- **控制台**：[Azure Portal](https://portal.azure.com/) → Speech Resource

#### LLM（Azure OpenAI Service）
- **凭证类型**：Azure OpenAI API Key（`api-key` header）
- **鉴权方式**：`api-key: YOUR_API_KEY` 或 Microsoft Entra ID Token
- **额外参数**：Endpoint（`https://<resource-name>.openai.azure.com`）、Deployment ID、API Version
- **控制台**：[Azure Portal](https://portal.azure.com/) → Azure OpenAI Resource

**分析**：Azure Speech 和 Azure OpenAI 是完全独立的 Azure 资源，各自有独立的 Resource Key。即使在同一个 Azure 订阅下，两者的密钥也不可互换。

**当前代码未包含 Azure** → 如需添加，需要为 ASR 和 LLM 分别定义不同的凭证字段

---

### 10. Anthropic (Claude)

**结论：纯 LLM 服务商，无 ASR** — 不涉及凭证共用问题

- **凭证类型**：API Key
- **鉴权方式**：`x-api-key: $ANTHROPIC_API_KEY`（注意：不是 Bearer Token 格式）
- **额外 header**：`anthropic-version: 2023-06-01`
- **控制台**：[Anthropic Console](https://platform.claude.com/settings/keys)
- **ASR**：无。Anthropic 不提供任何语音识别服务

**当前代码状态** → **已正确**

---

### 11. DeepSeek

**结论：纯 LLM 服务商，无 ASR** — 不涉及凭证共用问题

- **凭证类型**：API Key
- **鉴权方式**：`Authorization: Bearer $DEEPSEEK_API_KEY`
- **控制台**：[DeepSeek Platform](https://platform.deepseek.com/api_keys)
- **ASR**：无。DeepSeek 不提供语音识别服务

**当前代码状态** → **已正确**

---

### 12. 智谱 (GLM)

**结论：纯 LLM 服务商，ASR 能力有限** — 不涉及凭证共用问题

- **凭证类型**：API Key（用于生成 JWT Token）
- **鉴权方式**：API Key 格式为 `{id}.{secret}`，调用时生成 JWT Token 作为 `Authorization: Bearer $TOKEN`
- **ASR**：智谱平台文档中未见独立的 ASR 服务。GLM-4V 等多模态模型可能支持音频理解，但不是传统意义上的 ASR 转写服务
- **注意**：智谱也提供 OpenAI 兼容接口，直接用 API Key 作为 Bearer Token

#### 国内/国际版

| 版本 | 控制台 | API Endpoint | API Key |
|------|--------|-------------|---------|
| **国内版** | [open.bigmodel.cn](https://open.bigmodel.cn/usercenter/apikeys) | `https://open.bigmodel.cn/api/paas/v4` | 国内版 API Key |
| **国际版** | [bigmodel.cn (global)](https://bigmodel.cn/) | `https://open.bigmodel.cn/api/paas/v4`（待确认是否有独立海外 endpoint） | 可能共用 |

**注意**：智谱目前国际化程度有限，主要面向国内市场。海外用户也使用同一个平台。

**当前代码状态** → **已正确**

---

### 13. MiniMax

**结论：纯 LLM + TTS 服务商，无 ASR** — 不涉及凭证共用问题

- **凭证类型**：API Key
- **鉴权方式**：`Authorization: Bearer $MINIMAX_API_KEY`
- **ASR**：无。MiniMax 提供 TTS（语音合成 Speech 2.6）但**不提供** ASR（语音识别）服务
- **其他能力**：LLM、TTS、视频生成、音乐生成

#### 国内/国际版

| 版本 | 控制台 | API Endpoint | API Key | 备注 |
|------|--------|-------------|---------|------|
| **国内版** | [platform.minimaxi.com](https://platform.minimaxi.com/) | `https://api.minimax.chat/v1/openai` | 国内版 API Key | 面向国内用户 |
| **国际版** | [platform.minimax.io](https://platform.minimax.io/) | `https://api.minimax.io/v1` | 国际版 API Key | 面向海外用户 |

**重要**：国内版和国际版是**独立的账户体系**，API Key 不互通。需要分别注册。API 格式兼容但 endpoint 不同。

**当前代码状态** → 已在 `cloud_providers.dart` 中分为 `minimax`（国内）和应增加 `minimax_global`（国际）

---

### 14. Moonshot (Kimi)

**结论：纯 LLM 服务商，无 ASR** — 不涉及凭证共用问题

- **凭证类型**：API Key
- **鉴权方式**：`Authorization: Bearer $MOONSHOT_API_KEY`
- **ASR**：无。Moonshot/Kimi 不提供语音识别服务
- **API 格式**：OpenAI 兼容

#### 国内/国际版

| 版本 | 控制台 | API Endpoint | API Key | 备注 |
|------|--------|-------------|---------|------|
| **国内版** | [platform.moonshot.cn](https://platform.moonshot.cn/console/api-keys) | `https://api.moonshot.cn/v1` | 国内版 API Key | 面向国内用户 |
| **国际版** | [platform.moonshot.ai](https://platform.moonshot.ai/) | `https://api.moonshot.ai/v1` | 国际版 API Key | 面向海外用户 |

**重要**：国内版和国际版是**独立的账户体系**，API Key 不互通。需要分别注册。

**当前代码状态** → 已在 `cloud_providers.dart` 中分为 `moonshot`（国内），应增加 `moonshot_global`（国际）

---

## 凭证共用分类总结

### 共用凭证的服务商（一个 key 同时调 ASR + LLM）

| 服务商 | 共用的凭证 | 备注 |
|--------|-----------|------|
| 阿里云百炼 | DashScope API Key | 最简单，一个 key 搞定 |
| OpenAI | OpenAI API Key | 同一 key 调所有 API |
| Groq | Groq API Key | OpenAI 兼容格式 |

### 不共用凭证的服务商（ASR 和 LLM 需要不同 key）

| 服务商 | ASR 凭证 | LLM 凭证 | 差异程度 |
|--------|----------|----------|---------|
| 火山引擎 | AppID + Token + Cluster | 方舟 API Key + Endpoint ID | **完全不同的产品线和控制台** |
| 腾讯云 | SecretId + SecretKey + AppID (签名) | 混元 API Key (Bearer) | **鉴权方式完全不同** |
| 讯飞 | AppID + APIKey + APISecret | APIPassword (Bearer) | **同一平台但不同凭证** |
| 百度 | API Key + Secret Key → OAuth Token | 千帆 API Key (Bearer) | **不同产品平台** |
| Google | Service Account (GCP) | API Key (AI Studio) | **完全不同的平台和体系** |
| Azure | Speech Resource Key + Region | Azure OpenAI Key + Endpoint + Deployment | **不同 Azure 资源** |

### 纯 LLM 服务商（无 ASR）

Anthropic、DeepSeek、智谱、MiniMax、Moonshot — 不涉及此问题

### 有国内/国际双版本的服务商

以下服务商的国内版和国际版是**独立账户体系**，API Key 不互通，endpoint 不同：

| 服务商 | 国内 Endpoint | 国际 Endpoint | Key 互通？ |
|--------|-------------|-------------|-----------|
| **MiniMax** | `api.minimax.chat` | `api.minimax.io` | ❌ 不互通 |
| **Moonshot (Kimi)** | `api.moonshot.cn` | `api.moonshot.ai` | ❌ 不互通 |
| **智谱 (GLM)** | `open.bigmodel.cn` | 同（暂无独立海外版） | ✅ 同一平台 |

如需同时支持国内外用户，MiniMax 和 Moonshot 应在服务商注册表中各注册两个条目（国内版 + 国际版）。

---

## 对 CloudProvider 数据模型的影响

### 当前模型

```dart
class CloudProvider {
  final List<CredentialField> credentialFields;  // 单一凭证列表
  final Set<CloudCapability> capabilities;        // ASR/LLM 能力标记
}
```

### 问题分析

当前的 `credentialFields` 是一个扁平列表，**不区分凭证用于 ASR 还是 LLM**。这对于以下场景是够用的：

1. **凭证完全共用**（DashScope、OpenAI、Groq）→ 一个 `api_key` 搞定 ✅
2. **纯 LLM 服务商**（DeepSeek、Anthropic 等）→ 只有 LLM 凭证 ✅
3. **纯 ASR 服务商**（旧版阿里云 NLS）→ 只有 ASR 凭证 ✅

但对于以下场景**不够用**：

4. **火山引擎**：LLM 需要 `api_key`，ASR 需要 `app_id` + `token` + `cluster` → 当前只有 `api_key` + `app_id`，**缺少 ASR 的 token 和 cluster**
5. **讯飞**：ASR 需要 `app_id` + `api_key` + `api_secret`，LLM HTTP 接口需要 `api_password` → 当前定义的凭证对 ASR 足够，但 **LLM 缺少 api_password 字段**
6. **腾讯云**（如果未来加 LLM）：ASR 用签名鉴权，LLM 用 API Key → 需要两套凭证

### 建议方案

#### 方案 A：扩展 CredentialField，添加 scope 标记（推荐）

```dart
class CredentialField {
  final String key;
  final String label;
  final bool isSecret;
  final String? placeholder;
  final Set<CloudCapability> scope;  // 新增：标记此凭证用于哪些能力
  //   {} 空集 = 通用（ASR + LLM 都用）
  //   {CloudCapability.llm} = 仅 LLM
  //   {CloudCapability.asrStreaming} = 仅 ASR
}
```

**优点**：最小改动，向后兼容（`scope` 为空表示通用）
**示例**：

```dart
// 火山引擎
credentialFields: [
  CredentialField(key: 'api_key', label: '方舟 API Key', scope: {CloudCapability.llm}),
  CredentialField(key: 'app_id', label: 'ASR App ID', scope: {CloudCapability.asrStreaming}),
  CredentialField(key: 'token', label: 'ASR Token', scope: {CloudCapability.asrStreaming}),
  CredentialField(key: 'cluster', label: 'ASR Cluster', scope: {CloudCapability.asrStreaming}),
  CredentialField(key: 'endpoint_id', label: '推理接入点 ID', scope: {CloudCapability.llm}),
]

// 讯飞
credentialFields: [
  CredentialField(key: 'app_id', label: 'App ID', scope: {}),  // 通用
  CredentialField(key: 'api_key', label: 'API Key', scope: {CloudCapability.asrStreaming}),
  CredentialField(key: 'api_secret', label: 'API Secret', scope: {CloudCapability.asrStreaming}),
  CredentialField(key: 'api_password', label: 'API Password', scope: {CloudCapability.llm}),
]
```

#### 方案 B：按服务类型分组凭证

```dart
class CloudProvider {
  final Map<CloudCapability, List<CredentialField>> credentialFieldsByCapability;
}
```

**优点**：最清晰的分组
**缺点**：改动较大，对共用凭证的服务商（DashScope 等）需要重复定义

#### 方案 C：维持现状，在 Factory 层处理

保持 `credentialFields` 扁平列表，但为火山引擎等添加缺失的字段，在 `ASRProviderFactory.buildConfig()` 和 LLM 调用层分别取各自需要的字段。

**优点**：零模型改动
**缺点**：UI 层无法知道哪些字段是 ASR 用的、哪些是 LLM 用的，不利于分组展示

### 最终建议

**推荐方案 A**。理由：
1. 改动最小（只加一个可选字段）
2. 向后兼容（`scope` 默认空集 = 通用，现有定义无需修改）
3. UI 层可以根据 scope 分组展示凭证字段（如"ASR 凭证"和"LLM 凭证"分区）
4. 覆盖所有场景：共用、仅 ASR、仅 LLM

### 当前需要修正的服务商

| 服务商 | 当前问题 | 修正内容 |
|--------|---------|---------|
| 火山引擎 | 缺少 ASR 的 `token`、`cluster` 字段；`api_key` 未标明仅用于 LLM | 添加字段 + scope 标记 |
| 讯飞 | LLM HTTP 调用实际需要 `api_password`，当前用 `api_key`/`api_secret` 可能不对 | 确认 LLM 调用方式，可能需要添加 `api_password` |
| 腾讯云 | 仅有 ASR 能力，如果未来加 LLM 需要额外的 API Key | 暂不改动，未来扩展时处理 |

---

## 附录：各服务商 API Endpoint 汇总

| 服务商 | ASR Endpoint | LLM Endpoint |
|--------|-------------|--------------|
| 阿里云百炼 | `wss://dashscope.aliyuncs.com/api-ws/v1/inference` | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| 火山引擎 | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel` | `https://ark.cn-beijing.volces.com/api/v3` |
| OpenAI | `https://api.openai.com/v1/audio/transcriptions` | `https://api.openai.com/v1/chat/completions` |
| Groq | `https://api.groq.com/openai/v1/audio/transcriptions` | `https://api.groq.com/openai/v1/chat/completions` |
| 腾讯云 | `wss://asr.cloud.tencent.com/asr/v2/<appid>` | `https://hunyuan.tencentcloudapi.com` |
| 讯飞 | `wss://iat-api.xfyun.cn/v2/iat` | `https://spark-api-open.xf-yun.com/v1/chat/completions` |
| 百度 | `https://vop.baidu.com/server_api` | `https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop/chat/` |
| Google | `https://speech.googleapis.com/v1/speech:recognize` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Azure | `https://<region>.stt.speech.microsoft.com/...` | `https://<resource>.openai.azure.com/openai/deployments/<id>/...` |

---

## 参考文档

- [阿里云百炼 API Key](https://help.aliyun.com/zh/model-studio/getting-started/first-api-call-to-qwen)
- [火山引擎方舟 API](https://www.volcengine.com/docs/82379/1399008)
- [火山引擎语音识别接入](https://www.volcengine.com/docs/6561/80818)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [Groq API](https://console.groq.com/docs)
- [腾讯云 ASR 鉴权](https://cloud.tencent.com/document/product/1093/48982)
- [腾讯混元 OpenAI 兼容接口](https://cloud.tencent.com/document/product/1729/111007)
- [讯飞语音听写 API](https://www.xfyun.cn/doc/asr/voicedictation/API.html)
- [讯飞星火 HTTP API](https://www.xfyun.cn/doc/spark/HTTP%E8%B0%83%E7%94%A8%E6%96%87%E6%A1%A3.html)
- [Azure Speech REST API](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
- [Azure OpenAI API Reference](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference)
- [Anthropic API](https://platform.claude.com/docs/en/api/getting-started)
- [DeepSeek API](https://api-docs.deepseek.com/)
- [Google Gemini API Key](https://ai.google.dev/gemini-api/docs/api-key)
- [Google Cloud STT](https://cloud.google.com/speech-to-text/docs/before-you-begin)
