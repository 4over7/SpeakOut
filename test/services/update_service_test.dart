import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/update_service.dart';

void main() {
  group('UpdateService 版本比较', () {
    test('远程更高 patch 版本', () {
      expect(UpdateService.isNewer('1.5.2', '1.5.1'), true);
    });

    test('远程更高 minor 版本', () {
      expect(UpdateService.isNewer('1.6.0', '1.5.9'), true);
    });

    test('远程更高 major 版本', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), true);
    });

    test('相同版本不触发', () {
      expect(UpdateService.isNewer('1.5.1', '1.5.1'), false);
    });

    test('远程更低版本不触发', () {
      expect(UpdateService.isNewer('1.5.0', '1.5.1'), false);
    });

    test('远程更低 major 不触发', () {
      expect(UpdateService.isNewer('1.0.0', '2.0.0'), false);
    });

    test('只有两段版本号', () {
      expect(UpdateService.isNewer('1.6', '1.5.1'), true);
    });

    test('只有一段版本号', () {
      expect(UpdateService.isNewer('2', '1.9.9'), true);
    });

    test('非数字段回退为 0', () {
      expect(UpdateService.isNewer('1.5.abc', '1.5.0'), false);
    });
  });
}
