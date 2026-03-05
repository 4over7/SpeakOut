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

  const ASRResult({
    required this.text,
    this.tokens = const [],
    this.timestamps = const [],
    this.tokenConfidence,
  });

  /// 便捷工厂：从纯文本创建（用于 Aliyun 等无 token 信息的情况）
  factory ASRResult.textOnly(String text) => ASRResult(text: text);
}
