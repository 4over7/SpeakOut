import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/app_constants.dart';
import 'package:speakout/engine/providers/asr_provider_factory.dart';

/// Core 等待 provider.stop() 的上限必须 ≥ provider 自身的网络超时。
///
/// 事故形态：Core 固定等 6 秒，而 OpenAI/Groq 批量识别自身 HTTP 超时 30 秒 ——
/// Whisper 转写稍长的录音必然超 6 秒，Core 先超时丢弃，provider 还在干活，
/// 用户看到「说了一段话什么都没出来」，日志里也没有报错。
///
/// 本文件只管**对外契约**（声明的 stopTimeout 够不够）。provider 内部实际等多久、
/// 有没有给外层留余量，由 `asr_stop_budget_test.dart` 管。两者不重复。
void main() {
  group('ASR stopTimeout 契约', () {
    test('批量识别 provider 的等待上限必须大于其自身 HTTP 超时（30s）', () {
      for (final id in ['openai', 'groq']) {
        final p = ASRProviderFactory.create(id);
        expect(p.stopTimeout.inSeconds, greaterThan(30),
            reason: '$id 是批量识别，Core 等得比它自己的 30s HTTP 超时短就会丢结果');
      }
    });

    test('流式 provider 用全局默认', () {
      for (final id in ['dashscope', 'volcengine', 'xfyun', 'tencent', 'aliyun_nls']) {
        final p = ASRProviderFactory.create(id);
        expect(p.stopTimeout, AppConstants.kAsrStopTimeout, reason: id);
      }
    });

    test('每个注册的 provider 都必须给出 stopTimeout 且为正', () {
      // ASRProvider 用 implements 而非 extends，编译器会强制新 provider
      // 显式声明这个值 —— 正是靠这一点防止新增批量 provider 时静默沿用 6 秒。
      for (final id in [
        'dashscope', 'volcengine', 'xfyun', 'tencent',
        'openai', 'groq', 'aliyun_nls',
      ]) {
        final p = ASRProviderFactory.create(id);
        expect(p.stopTimeout.inMilliseconds, greaterThan(0), reason: id);
      }
    });
  });
}
