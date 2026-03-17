# 统一云服务账户管理 + 多云 ASR Provider 实施计划

> 日期: 2026-03-17
> 状态: 待确认

## 核心理念

当前凭证管理是"按功能分散"的（ASR 凭证在阿里云区域，LLM 凭证在 Preset 体系）。新架构改为"按服务商集中"：一个服务商注册一次 API Key，即可同时提供 ASR 和 LLM 能力。

## 数据模型

```
CloudProvider (静态注册表)
  ├── id: 'dashscope' / 'volcengine' / 'openai' / ...
  ├── name: '阿里云百炼' / '火山引擎' / 'OpenAI' / ...
  ├── credentialFields: [{key, label, isSecret}]
  ├── capabilities: {asrStreaming, asrBatch, llm}
  ├── asrModels: [{id, name, isStreaming}]
  └── llmDefaults: {baseUrl, defaultModel, apiFormat}

CloudAccount (用户数据)
  ├── id: uuid
  ├── providerId → 关联 CloudProvider
  ├── credentials: {api_key: 'sk-xxx', ...}
  └── isEnabled: bool
```

## 支持的服务商

| 服务商 | ASR 流式 | ASR 非流式 | LLM | 鉴权 | 推荐度 |
|--------|---------|-----------|-----|------|--------|
| 阿里云百炼 | Qwen-ASR, Gummy, Paraformer | - | 通义千问 | API Key | ★★★★★ |
| 火山引擎 | 豆包 Seed-ASR | - | 豆包大模型 | API Key + AppID | ★★★★★ |
| OpenAI | - | Whisper, GPT-4o Transcribe | GPT-4o | API Key | ★★★★ |
| Groq | - | Whisper Turbo | Llama/Mixtral | API Key | ★★★★ |
| 腾讯云 | 实时语音识别 | - | - | SecretId + SecretKey | ★★★ |
| 讯飞 | 语音听写 | - | 星火大模型 | AppID + APIKey + Secret | ★★★ |
| 阿里云 NLS | 实时语音 | - | - | AccessKey + Secret + AppKey | ★★ (legacy) |
| Claude | - | - | Claude | API Key | ★★★★ |
| DeepSeek | - | - | DeepSeek | API Key | ★★★★ |

## 分 Phase 实施

### Phase 1: 数据层 — CloudAccount 模型 + Service

**新建文件:**
- `lib/models/cloud_account.dart` — 数据模型
- `lib/config/cloud_providers.dart` — 服务商注册表
- `lib/services/cloud_account_service.dart` — CRUD + 持久化

**修改:**
- `lib/services/config_service.dart` — 新增 selectedAsrAccountId, selectedAsrModelId, selectedLlmAccountId

**独立可用**: 纯数据层，零破坏性。

### Phase 2: Engine 层 — 新 ASR Provider

**新建:**
- `lib/engine/providers/dashscope_asr_provider.dart` — 阿里云百炼 ASR (WebSocket)
- `lib/engine/providers/volcengine_asr_provider.dart` — 火山引擎 Seed-ASR
- `lib/engine/providers/openai_asr_provider.dart` — Whisper/Transcribe (非流式)
- `lib/engine/providers/asr_provider_factory.dart` — 工厂类

**修改:**
- `lib/engine/core_engine.dart` — initASR() 添加 cloud account 分支

### Phase 3: LLM 统一凭证来源

**修改:**
- `lib/services/llm_service.dart` — _resolveLlmConfig() 支持从 CloudAccount 读

### Phase 4: 自动迁移

- `CloudAccountService.migrateFromLegacy()` — 阿里云 NLS 凭证 + LLM Preset 自动迁移
- AppService.init() 中调用

### Phase 5: UI — 账户中心 + 工作模式重构

**新建:**
- `lib/ui/cloud_accounts_page.dart` — 账户中心

**修改:**
- `lib/ui/settings_page.dart` — Tab 从 5→6，云端模式和智能模式改用账户选择

**设置页 Tab 结构:**
通用 | 云服务账户 | 工作模式 | 触发方式 | 闪念笔记 | 关于

### Phase 6: 额外 Provider（按需）

- 腾讯云、讯飞、Groq 等

## UI 草案

### 云服务账户中心
```
┌─────────────────────────────────────────┐
│  云服务账户                               │
│                                          │
│  🟢 阿里云百炼          [编辑] [删除]     │
│     API Key: sk-****3f2a                │
│     能力: ASR 流式 · LLM                │
│  ─────────────────────────────────────  │
│  🟢 OpenAI              [编辑] [删除]    │
│     API Key: sk-****9e1b                │
│     能力: ASR 非流式 · LLM              │
│  ─────────────────────────────────────  │
│  ⚪ 火山引擎 (未配置)     [配置]          │
│                                          │
│  [+ 添加服务商]                           │
└─────────────────────────────────────────┘
```

### 工作模式 — 云端识别
```
┌─────────────────────────────────────────┐
│  ASR 服务: [阿里云百炼 - Qwen-ASR ▾]    │
│           (来自账户: 我的百炼账户)        │
│                                          │
│  ☑ 启用 LLM 后处理                      │
│  LLM 服务: [同一账户 (百炼) ▾]           │
└─────────────────────────────────────────┘
```

## 关键设计决策

1. **持久化用 SharedPreferences** — 账户数 <10，JSON 足够
2. **ASRProvider 接口不变** — 新 Provider 实现同一接口
3. **保留旧 LlmPreset 系统** — 不做强制迁移，两条路径共存
4. **CloudProvider 注册表在代码中** — 非 JSON 文件，类型安全
5. **工作模式语义不变** — offline / smart / cloud 三模式不变
