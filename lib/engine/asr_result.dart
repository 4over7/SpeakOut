/// ASR 识别结果数据类
///
/// 封装文本、分词列表、时间戳和可选的置信度信息。
/// 所有模型均提供 text 和 tokens；tokenConfidence 仅离线 Transducer 模型未来可用。
class ASRResult {
  final String text;
  final List<String> tokens;
  final List<double> timestamps;

  /// Per-token 对数概率；仅 transducerOffline 模型有值，其余为 null
  final List<double>? tokenConfidence;

  /// ASR 服务返回的错误信息（如云端鉴权失败）；非空时 text 为空
  final String? error;

  const ASRResult({
    required this.text,
    this.tokens = const [],
    this.timestamps = const [],
    this.tokenConfidence,
    this.error,
  });

  /// 便捷工厂：从纯文本创建（用于 Aliyun 等无 token 信息的情况）
  factory ASRResult.textOnly(String text) => ASRResult(text: text);

  /// 便捷工厂：创建错误结果
  factory ASRResult.withError(String error) => ASRResult(text: '', error: error);
}
