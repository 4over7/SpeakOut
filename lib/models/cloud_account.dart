// 云服务账户数据模型
// CloudProvider: 静态服务商定义（能力、凭证字段、ASR 模型等）
// CloudAccount: 用户的具体账户实例（凭证值、启用状态等）

import '../config/app_constants.dart' show LlmApiFormat;

enum CloudCapability { asrStreaming, asrBatch, llm }

/// 描述一个服务商需要的凭证字段
class CredentialField {
  final String key;
  final String label;
  final bool isSecret;
  final String? placeholder;

  const CredentialField({
    required this.key,
    required this.label,
    this.isSecret = false,
    this.placeholder,
  });
}

/// 服务商支持的 ASR 模型
class CloudASRModel {
  final String id;
  final String name;
  final bool isStreaming;
  final String? description;
  final String? priceHint;

  const CloudASRModel({
    required this.id,
    required this.name,
    required this.isStreaming,
    this.description,
    this.priceHint,
  });
}

/// 静态服务商定义（注册表中的一项）
class CloudProvider {
  final String id;
  final String name;
  final List<CredentialField> credentialFields;
  final Set<CloudCapability> capabilities;
  final List<CloudASRModel> asrModels;
  final String? llmBaseUrl;
  final String? llmDefaultModel;
  final String? llmModelHint;
  final LlmApiFormat llmApiFormat;
  final String helpUrl;

  const CloudProvider({
    required this.id,
    required this.name,
    required this.credentialFields,
    required this.capabilities,
    this.asrModels = const [],
    this.llmBaseUrl,
    this.llmDefaultModel,
    this.llmModelHint,
    this.llmApiFormat = LlmApiFormat.openai,
    this.helpUrl = '',
  });

  bool get hasASR => capabilities.contains(CloudCapability.asrStreaming) ||
                     capabilities.contains(CloudCapability.asrBatch);
  bool get hasLLM => capabilities.contains(CloudCapability.llm);
  bool get hasStreamingASR => capabilities.contains(CloudCapability.asrStreaming);
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
