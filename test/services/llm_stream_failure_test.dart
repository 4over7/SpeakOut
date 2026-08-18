import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/llm_service.dart';

/// 流式润色中途出错时**不能**再把原文吐一遍。
///
/// 打字机模式是边收 delta 边往用户文档里粘的（`core_engine` 的
/// `injectClipboardChunk`）。已经粘出去半段润色文本，异常分支再 yield 整段原文，
/// 用户文档里就是「半段润色 + 完整原文」—— 文本翻倍，而且撤不回来。
///
/// 「一个字都没吐过」才允许回退原文 —— 那时回退是唯一能救的路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LLMService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai_correct_enabled': true,
      'llm_base_url': 'https://api.openai.com/v1',
      'llm_provider_type': 'cloud',
    });
    await ConfigService().init();
    await ConfigService().setLlmApiKey('test_key');
    service = LLMService();
  });

  /// 构造一个「先吐几段 SSE，再决定是否报错」的流式 client
  void mockStream(List<String> sseLines, {bool thenError = false}) {
    service.setClient(MockClient.streaming((request, bodyStream) async {
      final controller = StreamController<List<int>>();
      scheduleMicrotask(() async {
        for (final l in sseLines) {
          controller.add(utf8.encode(l));
          await Future<void>.delayed(Duration.zero);
        }
        if (thenError) {
          controller.addError(const SocketExceptionStub());
        }
        await controller.close();
      });
      return http.StreamedResponse(controller.stream, 200);
    }));
  }

  String sse(String content) =>
      'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': content}
              }
            ]
          })}\n';

  test('已经吐过内容后中断 —— 不得再补一份原文（否则文本翻倍）', () async {
    mockStream([sse('润色了'), sse('一半')], thenError: true);

    final out = await service.correctTextStream('原始语音文本').toList();
    final joined = out.join();

    expect(joined, '润色了一半');
    expect(joined.contains('原始语音文本'), isFalse,
        reason: '中断后又吐了一遍原文 —— 打字机模式下用户文档会出现「半段润色+完整原文」');
  });

  test('一个字都没吐过就中断 —— 必须回退原文，否则用户口述内容凭空消失', () async {
    mockStream([], thenError: true);

    final out = await service.correctTextStream('原始语音文本').toList();

    expect(out.join(), '原始语音文本');
  });

  test('最后一条 data 没有换行结尾也不能丢', () async {
    // 服务端不以 \n 收尾时，末尾那条 SSE 会留在行缓冲里
    service.setClient(MockClient.streaming((request, bodyStream) async {
      final body = '${sse('前半')}data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '末尾'}
              }
            ]
          })}';
      return http.StreamedResponse(
          Stream.value(utf8.encode(body)), 200);
    }));

    final out = await service.correctTextStream('x').toList();
    expect(out.join(), '前半末尾');
  });

  test('伪流式路径（Ollama 一次性 yield）同样不得漏 think 标签', () async {
    // Ollama / Anthropic 走的是「整段结果一次性 yield」，不经过 SSE 的
    // ThinkTagFilter。漏清的话打字机会把 <think>…</think> 原样粘进用户文档。
    // ConfigService 是 singleton 且 init() 幂等 —— setMockInitialValues + 再 init()
    // 在 setUp 已经初始化过之后是**无效**的（我第一次就这么写，结果走了云端分支）。
    // 要改运行期配置只能用 setter。
    await ConfigService().setLlmProviderType('ollama');
    addTearDown(() => ConfigService().setLlmProviderType('cloud'));
    service.setClient(MockClient((request) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'message': {'content': '<think>先想想</think>润色结果'}
        })),
        200)));

    final out = await service.correctTextStream('原文').toList();
    expect(out.join(), '润色结果');
  });

  test('think 段不得流进用户文档', () async {
    mockStream([sse('<think>让我'), sse('想想</think>'), sse('正文')]);

    final out = await service.correctTextStream('x').toList();
    expect(out.join(), '正文');
  });
}

/// 只是为了给 addError 一个具体异常类型，不依赖 dart:io
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: connection reset';
}
