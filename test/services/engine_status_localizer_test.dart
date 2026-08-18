import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/engine_status.dart';
import 'package:speakout/services/engine_status_localizer.dart';

void main() {
  test('启用路径中的所有字面量状态码都有中英文映射', () {
    final sources = [
      File('lib/engine/core_engine.dart').readAsStringSync(),
      File('lib/services/app_service.dart').readAsStringSync(),
      File('lib/main.dart').readAsStringSync(),
    ].join('\n');
    final codes = RegExp(
      r"code:\s*'([^']+)'",
    ).allMatches(sources).map((m) => m.group(1)!).toSet();

    expect(codes, isNotEmpty);
    for (final code in codes) {
      final status = EngineStatus.info(
        '__UNMAPPED__',
        code: code,
        params: const {
          'provider': 'Provider X',
          'model': 'Model X',
          'error': 'detail',
        },
      );
      expect(
        localizedEngineStatusForLocale(status, const Locale('zh')),
        isNot('__UNMAPPED__'),
        reason: '缺少中文映射: $code',
      );
      expect(
        localizedEngineStatusForLocale(status, const Locale('en')),
        isNot('__UNMAPPED__'),
        reason: '缺少英文映射: $code',
      );
    }
  });

  test('动态 provider/model/error 参数不会在翻译时丢失', () {
    const status = EngineStatus.error(
      'fallback',
      code: 'provider_connect_failed',
      params: {'provider': 'Acme', 'error': '401'},
    );

    expect(
      localizedEngineStatusForLocale(status, const Locale('zh')),
      allOf(contains('Acme'), contains('401')),
    );
    expect(
      localizedEngineStatusForLocale(status, const Locale('en')),
      allOf(contains('Acme'), contains('401')),
    );
  });

  test('无 code 的 UI 临时消息保留 fallback', () {
    const status = EngineStatus.info('temporary message');
    expect(
      localizedEngineStatusForLocale(status, const Locale('zh')),
      'temporary message',
    );
  });
}
