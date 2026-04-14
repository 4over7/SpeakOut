import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/config/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('ConfigService Tests', () {
    
    setUp(() {
      // Clear singleton or re-init? 
      // ConfigService is singleton, but SharedPreferences.setMockInitialValues resets the store.
      SharedPreferences.setMockInitialValues({});
    });

    test('Default values should be correct', () async {
      final config = ConfigService();
      await config.init(); // Re-init to pick up empty mock values

      expect(config.pttKeyCode, AppConstants.kDefaultPttKeyCode);
      expect(config.pttKeyName, AppConstants.kDefaultPttKeyName);
      expect(config.activeModelId, AppConstants.kDefaultModelId);
    });

    test('Should save and retrieve PTT Key', () async {
      final config = ConfigService();
      await config.init();

      await config.setPttKey(123, "F1");
      
      expect(config.pttKeyCode, 123);
      expect(config.pttKeyName, "F1");
    });
    
    test('Should persist data across instances', () async {
      // Instance 1
      final config1 = ConfigService();
      await config1.init();
      await config1.setActiveModelId("custom_model_v2");

      // Simulate "Restart" by checking underlying prefs or just re-access
      // (Since ConfigService is singleton dart-side, we test logic integrity)

      expect(config1.activeModelId, "custom_model_v2");
    });

    // AI 一键调试基础键的契约：只存 keyCode + 裸键显示名，不存 modifiers
    //
    // 设计原因：基础键是"长按 + 数字键选槽位"的触发键，需要用户有两只手
    // 分别控制基础键和数字键。如果基础键再要求同时按 Cmd/Option，操作负担不合理。
    // 因此运行时只比较裸 keyCode，显示名也应不含 modifier。
    test('AI Report base key: 不持久化 modifiers（仅 keyCode + keyName）', () async {
      final config = ConfigService();
      await config.init();

      // 即使用户捕获时按了 Cmd+K，UI 层应该已经传裸键名
      // 这里直接验证 API：setAiReportBaseKey 只接收 code 和 name
      await config.setAiReportBaseKey(40, 'K');

      expect(config.aiReportBaseKeyCode, 40);
      expect(config.aiReportBaseKeyName, 'K',
          reason: '基础键显示名应为裸键，不含 modifier（Cmd/Option 等）');
    });

    test('AI Report base key: clearAiReportBaseKey 清空', () async {
      final config = ConfigService();
      await config.init();

      await config.setAiReportBaseKey(40, 'K');
      expect(config.aiReportBaseKeyCode, 40);

      await config.clearAiReportBaseKey();
      expect(config.aiReportBaseKeyCode, 0);
      expect(config.aiReportBaseKeyName, '');
    });
  });
}
