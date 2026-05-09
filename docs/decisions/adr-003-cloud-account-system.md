# ADR-003: 云服务账户体系：多账户 + 凭证分组

**日期**: 2026-03-17
**状态**: ✅ Accepted（v1.7+）
**决策者**: 项目所有者

## 背景

v1.7 之前 SpeakOut 的云端配置是**单全局**：一个 LLM API Key、一个 LLM Base URL、一个 LLM Model；ASR 同理。问题：

- **多 provider 并存困难**——用户想 ASR 用阿里云、LLM 用 DeepSeek，但旧 schema 只有一对槽位
- **跨 provider 切换成本高**——需要手动改 baseUrl + model，记不住
- **凭证字段不统一**——讯飞要 4 个字段（app_id/api_key/api_secret/api_password），DeepSeek 只要 1 个，UI 没法泛化
- **新增 provider 改动散落**——加豆包、智谱时要改 5+ 个文件（UI 选择器/校验/调用逻辑等）

## 选项

### A. 保持单全局凭证，加 provider 选择
- ✅ 改动小
- ❌ 不解决"多 provider 并存"——切 provider 要重输凭证
- ❌ 不解决新增 provider 散落

### B. 多账户 + Provider 注册表（SSoT）
- ✅ 一份 `lib/config/cloud_providers.dart` 注册所有 provider 元数据
- ✅ `CloudAccount` 实体支持每用户多账户、每账户启用/禁用
- ✅ ASR / LLM 选择器各自挑账户 × 模型
- ❌ 改动大（数据迁移 + UI 重构 + service 层重写）
- ❌ 需要凭证安全迁移（明文 SharedPreferences → keychain）

### C. 接 1Password / macOS Keychain 直接当后端
- ✅ 安全性最高
- ❌ 强依赖外部服务/系统 API
- ❌ 用户需要单独装 1Password 才能用

## 决策

**选 B：多账户 + Provider 注册表**。

理由：
1. SpeakOut 用户**普遍同时用多个 LLM**（ASR 一家 + LLM 另一家是常态）——单全局是真实痛点
2. Provider 注册表是 SSoT 对未来扩展友好——v1.8 加豆包、智谱、Kimi 等只改一份文件
3. 数据迁移一次性成本，长期受益

## 实现细节

### 数据模型（`lib/models/cloud_account.dart`）

```dart
class CloudProvider {
  String id;                          // 'dashscope' / 'deepseek' / ...
  String name;                        // 用户可见名
  Set<CloudCapability> capabilities;  // {asrStreaming, llm} 多选
  List<CredentialField> credentialFields;  // 凭证字段定义
  List<CloudLLMModel> llmModels;      // LLM 预设模型
  List<CloudASRModel> asrModels;      // ASR 模型
  String? llmBaseUrl;
  String? llmDefaultModel;
  LlmApiFormat llmApiFormat;          // openai / anthropic / ollama
  // ...
}

class CloudAccount {
  String id;                          // UUID
  String providerId;
  String displayName;                 // 用户自定义昵称
  bool isEnabled;
  Map<String, String> credentials;    // 字段名 → 值（凭证）
  // ...
}

class CredentialField {
  String key;
  String label;
  bool isSecret;
  Set<CloudCapability> scope;         // 字段属于哪种能力（asr / llm / 通用）
}
```

### 关键设计点

1. **`scope` 字段决定 UI 分组** — 凭证字段按能力分类，UI 渲染成「通用（灰）/ ASR（蓝）/ LLM（橙）」三色卡，用户一眼看出 ASR-only 和 LLM-only 字段
2. **`effectiveId` 模式** — 当用户保存的 `selectedLlmAccountId` 不在账户列表时（被删了/迁移失效），自动回退到第一个账户。防止旧 ID 失效导致 UI 报错
3. **`credentialKeys` 冗余** — `CloudAccount` 存"已设置的凭证字段名列表"，便于 UI 快速判断"账户配置完整性"，避免每次都遍历 keychain
4. **凭证安全迁移** — `flutter.cloud_cred_secure_migrated` 标记一次性迁移完成，新账户直接进 keychain

### Provider 分组顺序（用户看到的）

1. 流式 ASR + LLM：阿里云百炼、火山、讯飞
2. 非流式 ASR + LLM：Groq、OpenAI
3. 纯 LLM：DeepSeek、智谱、Kimi、MiniMax、Gemini、Anthropic
4. 纯流式 ASR：腾讯云
5. Legacy：阿里云 NLS（旧版）

## 后果

**正面**：
- 新增 provider 成本降到改 `cloud_providers.dart` 一份文件 + 跑测试
- 用户体验显著改善（一次性配置多家，自由组合）
- LLMService / ASRProviderFactory 解耦 provider 具体实现

**负面**：
- 数据迁移代码（v1.7 升级路径）需要保留至少 2 年
- `effectiveId` 这种"友好兜底"逻辑增加了状态空间复杂度（"用户选了什么"和"实际用什么"可能不一致）
- 凭证安全迁移失败时的回退路径需要测试覆盖

## 相关

- 实现：`lib/models/cloud_account.dart` / `lib/config/cloud_providers.dart` / `lib/services/cloud_account_service.dart`
- UI：`lib/ui/cloud_accounts_page.dart`
- memory：`~/.claude/projects/-Users-leon-Apps-speakout/memory/MEMORY.md` 「云服务账户体系」段
