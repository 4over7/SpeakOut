import '../models/cloud_account.dart';
import 'app_constants.dart' show LlmApiFormat;

/// 云服务商静态注册表
///
/// 定义所有支持的云服务商及其能力、凭证要求、ASR 模型等。
/// 这是 CloudAccount 体系的 schema —— 告诉 UI 和 Engine
/// 每个服务商需要什么凭证、能提供什么能力。
class CloudProviders {
  static const List<CloudProvider> all = [

    // ══════════════════════════════════════════════════
    // 一、流式 ASR + LLM（全功能，推荐优先）
    // 说话即出字，延迟最低，适合语音输入主力场景
    // ══════════════════════════════════════════════════

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
      llmModels: [
        CloudLLMModel(id: 'qwen-turbo', name: 'Qwen Turbo', description: '快速，性价比高', priceHint: '0.003 元/千 token'),
        CloudLLMModel(id: 'qwen-plus', name: 'Qwen Plus', priceHint: '0.008 元/千 token'),
        CloudLLMModel(id: 'qwen-max', name: 'Qwen Max', description: '最强，慢', priceHint: '0.04 元/千 token'),
        CloudLLMModel(id: 'qwen3-235b-a22b', name: 'Qwen3 235B-A22B', description: 'MoE 旗舰', priceHint: '0.02 元/千 token'),
        CloudLLMModel(id: 'qwen3-30b-a3b', name: 'Qwen3 30B-A3B', priceHint: '0.004 元/千 token'),
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
      llmModels: [
        CloudLLMModel(id: 'doubao-seed-2-0-mini-260215', name: 'Doubao Seed-2.0 Mini', description: '速度最快', priceHint: '0.001 元/千 token'),
        CloudLLMModel(id: 'doubao-1-5-pro-32k-250115', name: 'Doubao 1.5 Pro 32K', priceHint: '0.008 元/千 token'),
        CloudLLMModel(id: 'doubao-1-5-lite-32k-250115', name: 'Doubao 1.5 Lite 32K', priceHint: '0.003 元/千 token'),
      ],
      llmBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      llmDefaultModel: 'doubao-seed-2-0-mini-260215',
      llmModelHint: '推理接入点 ID，如 ep-xxx 或模型名',
      helpUrl: 'https://www.volcengine.com/docs/82379/1399008',
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
      llmModels: [
        CloudLLMModel(id: 'lite', name: '星火 Lite', description: '免费，速度快', priceHint: '免费'),
        CloudLLMModel(id: 'generalv3.5', name: '星火 Pro', priceHint: '按 token 计费'),
        CloudLLMModel(id: '4.0Ultra', name: '星火 4.0 Ultra', description: '旗舰'),
        CloudLLMModel(id: 'max-32k', name: '星火 Max 32K', description: '长文本'),
      ],
      llmBaseUrl: 'https://spark-api-open.xf-yun.com/v1',
      llmDefaultModel: 'lite',
      llmModelHint: '如 lite, generalv3.5, max-32k',
      helpUrl: 'https://www.xfyun.cn/services/voicedictation',
    ),

    // ══════════════════════════════════════════════════
    // 二、非流式 ASR + LLM（说完后整段转写，适合海外用户）
    // ══════════════════════════════════════════════════

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
      llmModels: [
        CloudLLMModel(id: 'llama-3.3-70b-versatile', name: 'Llama 3.3 70B', description: '推荐，极快', priceHint: '免费额度'),
        CloudLLMModel(id: 'llama-3.1-8b-instant', name: 'Llama 3.1 8B Instant', description: '最快', priceHint: '免费额度'),
        CloudLLMModel(id: 'gemma2-9b-it', name: 'Gemma2 9B', priceHint: '免费额度'),
        CloudLLMModel(id: 'moonshotai/kimi-k2-instruct', name: 'Kimi K2 (via Groq)', description: 'MoE 旗舰'),
      ],
      llmBaseUrl: 'https://api.groq.com/openai/v1',
      llmDefaultModel: 'llama-3.3-70b-versatile',
      llmModelHint: '如 llama-3.3-70b-versatile',
      helpUrl: 'https://console.groq.com/docs/quickstart',
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
      llmModels: [
        CloudLLMModel(id: 'gpt-4o-mini', name: 'GPT-4o Mini', description: '推荐，性价比高', priceHint: '0.011 元/千 token'),
        CloudLLMModel(id: 'gpt-4o', name: 'GPT-4o', priceHint: '0.18 元/千 token'),
        CloudLLMModel(id: 'gpt-4.1', name: 'GPT-4.1', priceHint: '0.14 元/千 token'),
        CloudLLMModel(id: 'gpt-4.1-mini', name: 'GPT-4.1 Mini', priceHint: '0.03 元/千 token'),
        CloudLLMModel(id: 'o4-mini', name: 'o4-mini', description: '推理模型'),
      ],
      llmBaseUrl: 'https://api.openai.com/v1',
      llmDefaultModel: 'gpt-4o-mini',
      llmModelHint: '如 gpt-4o-mini, gpt-4o',
      helpUrl: 'https://platform.openai.com/docs/overview',
    ),

    // ══════════════════════════════════════════════════
    // 三、纯 LLM（仅用于 AI 润色，需搭配离线或流式 ASR）
    // ══════════════════════════════════════════════════

    CloudProvider(
      id: 'deepseek',
      name: 'DeepSeek',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmModels: [
        CloudLLMModel(id: 'deepseek-chat', name: 'DeepSeek V3', description: '推荐', priceHint: '0.004 元/千 token'),
        CloudLLMModel(id: 'deepseek-reasoner', name: 'DeepSeek R1', description: '推理模型', priceHint: '0.04 元/千 token'),
      ],
      llmBaseUrl: 'https://api.deepseek.com/v1',
      llmDefaultModel: 'deepseek-chat',
      llmModelHint: '如 deepseek-chat, deepseek-reasoner',
      helpUrl: 'https://platform.deepseek.com/docs',
    ),

    CloudProvider(
      id: 'zhipu',
      name: '智谱 (GLM)',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmModels: [
        CloudLLMModel(id: 'glm-4-flash', name: 'GLM-4 Flash', description: '免费', priceHint: '免费'),
        CloudLLMModel(id: 'glm-4-plus', name: 'GLM-4 Plus', priceHint: '0.05 元/千 token'),
        CloudLLMModel(id: 'glm-z1-flash', name: 'GLM-Z1 Flash', description: '推理，免费', priceHint: '免费'),
        CloudLLMModel(id: 'glm-4-airx', name: 'GLM-4 AirX', description: '超快速'),
      ],
      llmBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      llmDefaultModel: 'glm-4-flash',
      llmModelHint: '如 glm-4-flash, glm-4-plus',
      helpUrl: 'https://open.bigmodel.cn/dev/howuse/introduction',
    ),

    CloudProvider(
      id: 'moonshot',
      name: 'Kimi 国内',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmModels: [
        CloudLLMModel(id: 'kimi-k2.5', name: 'Kimi K2.5', description: '推荐，MoE 旗舰'),
        CloudLLMModel(id: 'moonshot-v1-8k', name: 'Moonshot V1 8K'),
        CloudLLMModel(id: 'moonshot-v1-32k', name: 'Moonshot V1 32K'),
        CloudLLMModel(id: 'moonshot-v1-128k', name: 'Moonshot V1 128K'),
      ],
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
      llmModels: [
        CloudLLMModel(id: 'kimi-k2.5', name: 'Kimi K2.5', description: '推荐，MoE 旗舰'),
        CloudLLMModel(id: 'moonshot-v1-8k', name: 'Moonshot V1 8K'),
        CloudLLMModel(id: 'moonshot-v1-32k', name: 'Moonshot V1 32K'),
        CloudLLMModel(id: 'moonshot-v1-128k', name: 'Moonshot V1 128K'),
      ],
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
      llmModels: [
        CloudLLMModel(id: 'MiniMax-M2.5', name: 'MiniMax M2.5', description: '推荐，MoE 旗舰'),
        CloudLLMModel(id: 'MiniMax-M1', name: 'MiniMax M1', description: '推理增强'),
      ],
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
      llmModels: [
        CloudLLMModel(id: 'MiniMax-M2.5', name: 'MiniMax M2.5', description: '推荐，MoE 旗舰'),
        CloudLLMModel(id: 'MiniMax-M1', name: 'MiniMax M1', description: '推理增强'),
      ],
      llmBaseUrl: 'https://api.minimax.io/v1',
      llmDefaultModel: 'MiniMax-M2.5',
      llmModelHint: '如 MiniMax-M2.5, MiniMax-M1',
      helpUrl: 'https://platform.minimax.io/docs/api-reference/text-openai-api',
    ),

    CloudProvider(
      id: 'gemini',
      name: 'Google Gemini',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmModels: [
        CloudLLMModel(id: 'gemini-2.0-flash', name: 'Gemini 2.0 Flash', description: '推荐，极快'),
        CloudLLMModel(id: 'gemini-2.5-flash', name: 'Gemini 2.5 Flash', description: '思考增强版'),
        CloudLLMModel(id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro', description: '旗舰'),
      ],
      llmBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      llmDefaultModel: 'gemini-2.0-flash',
      llmModelHint: '如 gemini-2.0-flash',
      helpUrl: 'https://ai.google.dev/gemini-api/docs/openai',
    ),

    CloudProvider(
      id: 'anthropic',
      name: 'Anthropic (Claude)',
      credentialFields: [
        CredentialField(key: 'api_key', label: 'API Key', isSecret: true),
      ],
      capabilities: {CloudCapability.llm},
      llmModels: [
        CloudLLMModel(id: 'claude-sonnet-4-6', name: 'Claude Sonnet 4.6', description: '推荐，能力均衡'),
        CloudLLMModel(id: 'claude-haiku-4-5-20251001', name: 'Claude Haiku 4.5', description: '最快，便宜'),
        CloudLLMModel(id: 'claude-opus-4-6', name: 'Claude Opus 4.6', description: '旗舰'),
      ],
      llmBaseUrl: 'https://api.anthropic.com',
      llmDefaultModel: 'claude-sonnet-4-6',
      llmModelHint: '如 claude-sonnet-4-6, claude-haiku-4-5-20251001',
      llmApiFormat: LlmApiFormat.anthropic,
      helpUrl: 'https://docs.anthropic.com/en/docs/initial-setup',
    ),

    // ══════════════════════════════════════════════════
    // 四、纯流式 ASR（无 LLM，可搭配纯 LLM 服务商）
    // ══════════════════════════════════════════════════

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

    // ══════════════════════════════════════════════════
    // 五、Legacy（旧版迁移兼容）
    // ══════════════════════════════════════════════════

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
