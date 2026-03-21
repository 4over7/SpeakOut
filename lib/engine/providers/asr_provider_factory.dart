import '../../models/cloud_account.dart';
import '../asr_provider.dart';
import 'aliyun_provider.dart';
import 'dashscope_asr_provider.dart';
import 'openai_asr_provider.dart';
import 'tencent_asr_provider.dart';
import 'volcengine_asr_provider.dart';
import 'xfyun_asr_provider.dart';

/// ASR Provider 工厂
///
/// 根据 CloudAccount + CloudASRModel 创建对应的 ASRProvider 实例，
/// 并构建 initialize() 所需的 config Map。
class ASRProviderFactory {
  /// 创建 ASR Provider 实例
  static ASRProvider create(String providerId) {
    switch (providerId) {
      case 'dashscope':
        return DashScopeASRProvider();
      case 'openai':
      case 'groq':
        return OpenAIASRProvider();
      case 'aliyun_nls':
        return AliyunProvider();
      case 'volcengine':
        return VolcengineASRProvider();
      case 'xfyun':
        return XfyunASRProvider();
      case 'tencent':
        return TencentASRProvider();
      default:
        throw Exception('Unsupported ASR provider: $providerId');
    }
  }

  /// 构建 initialize() 的 config Map
  static Map<String, dynamic> buildConfig(CloudAccount account, CloudASRModel model) {
    switch (account.providerId) {
      case 'dashscope':
        return {
          'apiKey': account.credentials['api_key'] ?? '',
          'model': model.id,
        };
      case 'openai':
        return {
          'apiKey': account.credentials['api_key'] ?? '',
          'baseUrl': 'https://api.openai.com/v1',
          'model': model.id,
        };
      case 'groq':
        return {
          'apiKey': account.credentials['api_key'] ?? '',
          'baseUrl': 'https://api.groq.com/openai/v1',
          'model': model.id,
        };
      case 'aliyun_nls':
        return {
          'accessKeyId': account.credentials['access_key_id'] ?? '',
          'accessKeySecret': account.credentials['access_key_secret'] ?? '',
          'appKey': account.credentials['app_key'] ?? '',
        };
      case 'volcengine':
        return {
          'apiKey': account.credentials['asr_api_key'] ?? '',
        };
      case 'xfyun':
        return {
          'appId': account.credentials['app_id'] ?? '',
          'apiKey': account.credentials['api_key'] ?? '',
          'apiSecret': account.credentials['api_secret'] ?? '',
        };
      case 'tencent':
        return {
          'secretId': account.credentials['secret_id'] ?? '',
          'secretKey': account.credentials['secret_key'] ?? '',
          'appId': account.credentials['app_id'] ?? '',
          'model': model.id,
        };
      default:
        return {'apiKey': account.credentials['api_key'] ?? ''};
    }
  }

  /// 判断该 ASR 模型是否为非流式（离线批量识别）
  static bool isOfflineModel(CloudASRModel model) => !model.isStreaming;
}
