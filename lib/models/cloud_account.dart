// 云服务账户数据模型
// CloudProvider: 静态服务商定义（能力、凭证字段、ASR 模型等）
// CloudAccount: 用户的具体账户实例（凭证值、启用状态等）

import '../config/app_constants.dart' show LlmApiFormat;

enum CloudCapability { asrStreaming, asrBatch, llm }

/// 描述一个服务商需要的凭证字段
///
/// [scope] 标记此凭证用于哪些能力:
///   - 空集 {} = 通用（ASR + LLM 都用，如 DashScope 的 api_key）
///   - {CloudCapability.llm} = 仅 LLM（如火山方舟 api_key）
///   - {CloudCapability.asrStreaming} = 仅 ASR（如火山 ASR token）
class CredentialField {
  final String key;
  final String label;
  final bool isSecret;
  final String? placeholder;
  final Set<CloudCapability> scope;

  const CredentialField({
    required this.key,
    required this.label,
    this.isSecret = false,
    this.placeholder,
    this.scope = const {},  // empty = universal (used by all capabilities)
  });

  /// 此凭证是否用于指定能力（scope 为空表示通用，匹配任何能力）
  bool appliesTo(CloudCapability cap) => scope.isEmpty || scope.contains(cap);
}

/// 服务商支持的 LLM 模型
class CloudLLMModel {
  final String id;
  final String name;
  final String? description;
  final String? priceHint;

  const CloudLLMModel({
    required this.id,
    required this.name,
    this.description,
    this.priceHint,
  });
}

/// 服务商支持的 ASR 模型
class CloudASRModel {
  final String id;
  final String name;
  final bool isStreaming;
  final String? description;
  final String? priceHint;

  /// 此模型支持的输入语言列表（如 ['zh', 'en']）。
  /// 为空表示支持所有语言（如 DashScope 的 language_hints 机制）。
  final List<String> supportedLanguages;

  const CloudASRModel({
    required this.id,
    required this.name,
    required this.isStreaming,
    this.description,
    this.priceHint,
    this.supportedLanguages = const [],
  });

  /// 检查此模型是否支持指定语言。空列表表示不限制（支持所有）。
  bool supportsLanguage(String langCode) {
    if (langCode == 'auto') return true;
    if (supportedLanguages.isEmpty) return true;
    return supportedLanguages.contains(langCode);
  }
}

/// 静态服务商定义（注册表中的一项）
class CloudProvider {
  final String id;
  final String name;
  final List<CredentialField> credentialFields;
  final Set<CloudCapability> capabilities;
  final List<CloudASRModel> asrModels;
  final List<CloudLLMModel> llmModels;
  final String? llmBaseUrl;
  final String? llmDefaultModel;
  final String? llmModelHint;
  final LlmApiFormat llmApiFormat;
  final String helpUrl;

  /// 用于 LLM 鉴权的凭证字段 key（默认 'api_key'）。
  /// 当服务商的 LLM 凭证字段名不是 'api_key' 时需要显式指定，
  /// 例如讯飞星火使用 'api_password'。
  final String llmApiKeyField;

  const CloudProvider({
    required this.id,
    required this.name,
    required this.credentialFields,
    required this.capabilities,
    this.asrModels = const [],
    this.llmModels = const [],
    this.llmBaseUrl,
    this.llmDefaultModel,
    this.llmModelHint,
    this.llmApiFormat = LlmApiFormat.openai,
    this.helpUrl = '',
    this.llmApiKeyField = 'api_key',
  });

  bool get hasASR => capabilities.contains(CloudCapability.asrStreaming) ||
                     capabilities.contains(CloudCapability.asrBatch);
  bool get hasLLM => capabilities.contains(CloudCapability.llm);
  bool get hasStreamingASR => capabilities.contains(CloudCapability.asrStreaming);

  /// 检查账户是否至少有一项能力的凭证已填写
  /// [credentials] 是用户填写的凭证 Map
  bool hasAnyValidCredentials(Map<String, String> credentials) {
    // 通用凭证（scope 为空）只要有一个非空就算有效
    final universalFields = credentialFields.where((f) => f.scope.isEmpty);
    final hasUniversal = universalFields.any((f) => (credentials[f.key] ?? '').isNotEmpty);
    if (hasUniversal) return true;

    // 否则检查各能力组是否有完整凭证
    return hasValidCredentialsFor(CloudCapability.llm, credentials) ||
           hasValidCredentialsFor(CloudCapability.asrStreaming, credentials) ||
           hasValidCredentialsFor(CloudCapability.asrBatch, credentials);
  }

  /// 检查指定能力的凭证是否已填写（该能力的所有必填字段都非空）
  bool hasValidCredentialsFor(CloudCapability cap, Map<String, String> credentials) {
    if (!capabilities.contains(cap)) return false;
    final fields = credentialFields.where((f) => f.appliesTo(cap));
    if (fields.isEmpty) return false;
    return fields.every((f) => (credentials[f.key] ?? '').isNotEmpty);
  }
}

/// 用户的云服务账户实例
class CloudAccount {
  final String id;
  final String providerId;
  String displayName;
  Map<String, String> credentials;
  bool isEnabled;
  DateTime createdAt;

  CloudAccount({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.credentials,
    this.isEnabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Serialize (without secret values — those are stored separately)
  Map<String, dynamic> toJson() => {
    'id': id,
    'providerId': providerId,
    'displayName': displayName,
    'isEnabled': isEnabled,
    'createdAt': createdAt.toIso8601String(),
    // credential keys only (values stored separately for security)
    'credentialKeys': credentials.keys.toList(),
  };

  /// Deserialize (credential values loaded separately)
  static CloudAccount fromJson(Map<String, dynamic> json) => CloudAccount(
    id: json['id'] as String,
    providerId: json['providerId'] as String,
    displayName: json['displayName'] as String,
    credentials: {},  // populated later from secure storage
    isEnabled: json['isEnabled'] as bool? ?? true,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
