import '../models/cloud_account.dart';
import 'app_constants.dart' show LlmApiFormat;

/// 云服务商静态注册表
///
/// 定义所有支持的云服务商及其能力、凭证要求、ASR 模型等。
/// 这是 CloudAccount 体系的 schema —— 告诉 UI 和 Engine
/// 每个服务商需要什么凭证、能提供什么能力。
class CloudProviders {
  static const List<CloudProvider> all = [
    // ── 第一梯队：推荐 ──

    CloudProvider(
      id: 'dashscope',
      name: '阿里云百炼',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true, placeholder: 'sk-...'),
      ],
      capabilities: {CloudCapability.asrStreaming, CloudCapability.llm},
      asrModels: [
        CloudASRModel(id: 'paraformer-v2', name: 'Paraformer V2', isStreaming: true, priceHint: '0.86 元/h'),
        CloudASRModel(id: 'paraformer-realtime-v2', name: 'Paraformer 实时 V2', isStreaming: true, priceHint: '0.86 元/h'),
      ],
      llmBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      llmDefaultModel: 'qwen-turbo',
      llmModelHint: '如 qwen-turbo, qwen-plus',
      helpUrl: 'https://help.aliyun.com/zh/model-studio/getting-started/first-api-call-to-qwen',
    ),

    CloudProvider(
      id: 'volcengine',
      name: '火山引擎 (豆包)',
      credentialFields: [
        CredentialField(key: 'api_key', label: '方舟 API Key', isSecret: true, scope: {CloudCapability.llm}),
        CredentialField(key: 'asr_app_id', label: 'ASR App ID', scope: {CloudCapability.asrStreaming}),
        CredentialField(key: 'asr_token', label: 'ASR Access Token', isSecret: true, scope: {CloudCapability.asrStreaming}),
        CredentialField(key: 'asr_cluster', label: 'ASR Cluster', placeholder: 'volcengine_streaming_common', scope: {CloudCapability.asrStreaming}),
      ],
      capabilities: {CloudCapability.asrStreaming, CloudCapability.llm},
      asrModels: [
        CloudASRModel(id: 'seed-asr', name: '豆包 Seed-ASR', isStreaming: true, description: '中文精度最高', priceHint: '1.00 元/h'),
      ],
      llmBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      llmDefaultModel: 'doubao-seed-2-0-mini-260215',
      llmModelHint: '推理接入点 ID，如 ep-xxx',
      helpUrl: 'https://www.volcengine.com/docs/82379/1399008',
    ),

    CloudProvider(
      id: 'openai',
      name: 'OpenAI',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true, placeholder: 'sk-...'),
      ],
      capabilities: {CloudCapability.asrBatch, CloudCapability.llm},
      asrModels: [
        CloudASRModel(id: 'whisper-1', name: 'Whisper', isStreaming: false, priceHint: '2.63 元/h'),
        CloudASRModel(id: 'gpt-4o-transcribe', name: 'GPT-4o Transcribe', isStreaming: false, priceHint: '2.63 元/h'),
        CloudASRModel(id: 'gpt-4o-mini-transcribe', name: 'GPT-4o Mini Transcribe', isStreaming: false, priceHint: '1.31 元/h'),
      ],
      llmBaseUrl: 'https://api.openai.com/v1',
      llmDefaultModel: 'gpt-4o-mini',
      llmModelHint: '如 gpt-4o-mini, gpt-4o',
      helpUrl: 'https://platform.openai.com/docs/overview',
    ),

    CloudProvider(
      id: 'groq',
      name: 'Groq',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true, placeholder: 'gsk_...'),
      ],
      capabilities: {CloudCapability.asrBatch, CloudCapability.llm},
      asrModels: [
        CloudASRModel(id: 'whisper-large-v3-turbo', name: 'Whisper V3 Turbo', isStreaming: false, description: '299x 实时速度', priceHint: '0.29 元/h'),
        CloudASRModel(id: 'whisper-large-v3', name: 'Whisper Large V3', isStreaming: false, priceHint: '0.81 元/h'),
      ],
      llmBaseUrl: 'https://api.groq.com/openai/v1',
      llmDefaultModel: 'llama-3.3-70b-versatile',
      llmModelHint: '如 llama-3.3-70b-versatile',
      helpUrl: 'https://console.groq.com/docs/quickstart',
    ),

    // ── 第二梯队：特定场景 ──

    CloudProvider(
      id: 'tencent',
      name: '腾讯云',
      credentialFields: [
        CredentialField(key: 'secret_id', label: 'SecretId'),
        CredentialField(key: 'secret_key', label: 'SecretKey', isSecret: true),
      ],
      capabilities: {CloudCapability.asrStreaming},
      asrModels: [
        CloudASRModel(id: 'asr-streaming', name: '实时语音识别', isStreaming: true, description: '每月 5h 免费', priceHint: '3.20 元/h'),
      ],
      helpUrl: 'https://cloud.tencent.com/document/product/1093',
    ),

    CloudProvider(
      id: 'xfyun',
      name: '讯飞',
      credentialFields: [
        CredentialField(key: 'app_id', label: 'App ID'),
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true, scope: {CloudCapability.asrStreaming}),
        CredentialField(key: 'api_secret', label: 'API Secret', isSecret: true, scope: {CloudCapability.asrStreaming}),
        CredentialField(key: 'api_password', label: 'API Password (星火)', isSecret: true, scope: {CloudCapability.llm}, placeholder: 'Bearer Token for HTTP API'),
      ],
      capabilities: {CloudCapability.asrStreaming, CloudCapability.llm},
      asrModels: [
        CloudASRModel(id: 'iat', name: '语音听写', isStreaming: true, description: '202 种方言', priceHint: '按次计费'),
      ],
      llmBaseUrl: 'https://spark-api-open.xf-yun.com/v1',
      llmDefaultModel: 'lite',
      llmModelHint: '如 lite, generalv3.5, max-32k',
      helpUrl: 'https://www.xfyun.cn/services/voicedictation',
    ),

    // ── 纯 LLM 服务商（无 ASR）──

    CloudProvider(
      id: 'deepseek',
      name: 'DeepSeek',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.deepseek.com/v1',
      llmDefaultModel: 'deepseek-chat',
      llmModelHint: '如 deepseek-chat, deepseek-reasoner',
      helpUrl: 'https://platform.deepseek.com/docs',
    ),

    CloudProvider(
      id: 'anthropic',
      name: 'Anthropic (Claude)',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.anthropic.com',
      llmDefaultModel: 'claude-sonnet-4-6',
      llmModelHint: '如 claude-sonnet-4-6, claude-haiku-4-5-20251001',
      llmApiFormat: LlmApiFormat.anthropic,
      helpUrl: 'https://docs.anthropic.com/en/docs/initial-setup',
    ),

    CloudProvider(
      id: 'zhipu',
      name: '智谱 (GLM)',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      llmDefaultModel: 'glm-4-flash',
      llmModelHint: '如 glm-4-flash, glm-4-plus',
      helpUrl: 'https://open.bigmodel.cn/dev/howuse/introduction',
    ),

    CloudProvider(
      id: 'gemini',
      name: 'Google Gemini',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      llmDefaultModel: 'gemini-2.0-flash',
      llmModelHint: '如 gemini-2.0-flash',
      helpUrl: 'https://ai.google.dev/gemini-api/docs/openai',
    ),

    CloudProvider(
      id: 'moonshot',
      name: 'Kimi 国内',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.moonshot.cn/v1',
      llmDefaultModel: 'kimi-k2.5',
      llmModelHint: '如 kimi-k2.5, kimi-k2-0711',
      helpUrl: 'https://platform.moonshot.cn/docs',
    ),

    CloudProvider(
      id: 'moonshot_global',
      name: 'Kimi 海外',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.moonshot.ai/v1',
      llmDefaultModel: 'kimi-k2.5',
      llmModelHint: '如 kimi-k2.5, kimi-k2-0711',
      helpUrl: 'https://platform.moonshot.ai/',
    ),

    CloudProvider(
      id: 'minimax',
      name: 'MiniMax 国内',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.minimax.chat/v1/openai',
      llmDefaultModel: 'MiniMax-M2.5',
      llmModelHint: '如 MiniMax-M2.5, MiniMax-M1',
      helpUrl: 'https://platform.minimaxi.com/document/introduction',
    ),

    CloudProvider(
      id: 'minimax_global',
      name: 'MiniMax 海外',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmBaseUrl: 'https://api.minimax.io/v1',
      llmDefaultModel: 'MiniMax-M2.5',
      llmModelHint: '如 MiniMax-M2.5, MiniMax-M1',
      helpUrl: 'https://platform.minimax.io/docs/api-reference/text-openai-api',
    ),

    // ── Legacy ──

    CloudProvider(
      id: 'aliyun_nls',
      name: '阿里云 NLS (旧版)',
      credentialFields: [
        CredentialField(key: 'access_key_id', label: 'AccessKey ID'),
        CredentialField(key: 'access_key_secret', label: 'AccessKey Secret', isSecret: true),
        CredentialField(key: 'app_key', label: 'AppKey'),
      ],
      capabilities: {CloudCapability.asrStreaming},
      asrModels: [
        CloudASRModel(id: 'nls-streaming', name: 'NLS 实时语音', isStreaming: true, priceHint: '3.50 元/h'),
      ],
      helpUrl: 'https://help.aliyun.com/zh/isi/',
    ),
  ];

  /// 按 ID 查找
  static CloudProvider? getById(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 获取有 ASR 能力的服务商
  static List<CloudProvider> withASR() => all.where((p) => p.hasASR).toList();

  /// 获取有 LLM 能力的服务商
  static List<CloudProvider> withLLM() => all.where((p) => p.hasLLM).toList();
}
