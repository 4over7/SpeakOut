/// LLM 延迟测试脚本
///
/// 对所有已配置的 LLM 服务商发送相同的短文本纠错请求，
/// 测量首 token 延迟 (TTFT) 和总完成时间。
///
/// 运行: dart run scripts/test_llm_latency.dart

import 'dart:convert';
import 'dart:io';

const testInput = '今天天气不措，我想去公远散步，顺便买点东西回家做反。';
const systemPrompt = '修复语音识别的同音字错误，去除口语冗余，输出修正后的文本。';

class ProviderConfig {
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final bool isAnthropic;

  ProviderConfig({required this.name, required this.baseUrl, required this.model, required this.apiKey, this.isAnthropic = false});
}

Future<void> main() async {
  // Read credentials from SharedPreferences plist
  final plistResult = await Process.run('plutil', ['-p', '${Platform.environment['HOME']}/Library/Preferences/com.speakout.speakout.plist']);
  final plist = plistResult.stdout as String;

  String? getCredValue(String accountId, String key) {
    final pattern = RegExp('flutter\\.cloud_cred_${accountId}_$key.*?=>\\s*"(.*?)"');
    final match = pattern.firstMatch(plist);
    return match?.group(1);
  }

  // Parse cloud accounts
  final accountsMatch = RegExp(r'flutter\.cloud_accounts.*?=>\s*"(.*?)"', dotAll: true).firstMatch(plist);
  if (accountsMatch == null) {
    print('No cloud accounts found');
    return;
  }

  final accountsJson = accountsMatch.group(1)!.replaceAll(r'\"', '"');
  final accounts = jsonDecode(accountsJson) as List;

  // Build provider configs
  final providers = <ProviderConfig>[];

  for (final account in accounts) {
    final providerId = account['providerId'] as String;
    final accountId = account['id'] as String;
    final enabled = account['isEnabled'] as bool;
    if (!enabled) continue;

    String? apiKey;
    String baseUrl = '';
    String model = '';

    switch (providerId) {
      case 'volcengine':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
        model = 'doubao-seed-2-0-mini-260215';
      case 'dashscope':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
        model = 'qwen-turbo';
      case 'groq':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://api.groq.com/openai/v1';
        model = 'llama-3.3-70b-versatile';
      case 'deepseek':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://api.deepseek.com/v1';
        model = 'deepseek-chat';
      case 'zhipu':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://open.bigmodel.cn/api/paas/v4';
        model = 'glm-4-flash';
      case 'moonshot':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://api.moonshot.cn/v1';
        model = 'kimi-k2.5';
      case 'minimax':
        apiKey = getCredValue(accountId, 'api_key');
        baseUrl = 'https://api.minimax.chat/v1/openai';
        model = 'MiniMax-M2.5';
      case 'xfyun':
        apiKey = getCredValue(accountId, 'api_password');
        baseUrl = 'https://spark-api-open.xf-yun.com/v1';
        model = 'lite';
      default:
        continue;
    }

    if (apiKey == null || apiKey.isEmpty) continue;
    providers.add(ProviderConfig(name: '${account['displayName']} ($model)', baseUrl: baseUrl, model: model, apiKey: apiKey));
  }

  print('═══════════════════════════════════════════════════════════');
  print('LLM 延迟测试 — ${DateTime.now().toIso8601String()}');
  print('测试输入: "$testInput"');
  print('═══════════════════════════════════════════════════════════\n');

  final results = <Map<String, dynamic>>[];

  for (final p in providers) {
    stdout.write('测试 ${p.name}...');
    try {
      final result = await testProvider(p);
      results.add({'name': p.name, ...result});
      final ttft = result['ttft_ms'];
      final total = result['total_ms'];
      final output = result['output'] as String;
      print(' TTFT=${ttft}ms, 总耗时=${total}ms');
      print('  输出: ${output.length > 60 ? '${output.substring(0, 60)}...' : output}');
    } catch (e) {
      results.add({'name': p.name, 'error': e.toString()});
      print(' ❌ $e');
    }
    print('');
  }

  // Summary table
  print('\n═══════════════════════════════════════════════════════════');
  print('结果汇总');
  print('═══════════════════════════════════════════════════════════');
  print('${'服务商'.padRight(35)} | ${'TTFT'.padLeft(8)} | ${'总耗时'.padLeft(8)} | 状态');
  print('${'─' * 35}─┼${'─' * 10}┼${'─' * 10}┼${'─' * 10}');

  // Sort by total time
  results.sort((a, b) {
    final aTime = a['total_ms'] as int? ?? 999999;
    final bTime = b['total_ms'] as int? ?? 999999;
    return aTime.compareTo(bTime);
  });

  for (final r in results) {
    final name = (r['name'] as String).padRight(35);
    if (r.containsKey('error')) {
      print('$name | ${'—'.padLeft(8)} | ${'—'.padLeft(8)} | ❌ ${r['error'].toString().substring(0, 30)}');
    } else {
      final ttft = '${r['ttft_ms']}ms'.padLeft(8);
      final total = '${r['total_ms']}ms'.padLeft(8);
      print('$name | $ttft | $total | ✅');
    }
  }
}

Future<Map<String, dynamic>> testProvider(ProviderConfig p) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);

  final body = jsonEncode({
    'model': p.model,
    'messages': [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': testInput},
    ],
    'stream': true,
    'temperature': 0.3,
  });

  final sw = Stopwatch()..start();

  final uri = Uri.parse('${p.baseUrl}/chat/completions');
  final request = await client.postUrl(uri);
  request.headers.set('Content-Type', 'application/json');
  request.headers.set('Authorization', 'Bearer ${p.apiKey}');
  request.write(body);

  final response = await request.close();

  if (response.statusCode != 200) {
    final errBody = await response.transform(utf8.decoder).join();
    client.close();
    throw Exception('HTTP ${response.statusCode}: ${errBody.substring(0, 100)}');
  }

  int? ttftMs;
  final outputBuffer = StringBuffer();

  await for (final chunk in response.transform(utf8.decoder)) {
    if (ttftMs == null) {
      ttftMs = sw.elapsedMilliseconds;
    }
    // Parse SSE lines
    for (final line in chunk.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null) outputBuffer.write(content);
        }
      } catch (_) {}
    }
  }

  final totalMs = sw.elapsedMilliseconds;
  client.close();

  return {
    'ttft_ms': ttftMs ?? totalMs,
    'total_ms': totalMs,
    'output': outputBuffer.toString().trim(),
  };
}
