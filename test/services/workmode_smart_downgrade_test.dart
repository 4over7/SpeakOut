import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';

/// E1：Smart 模式降级为 AI 润色独立开关
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E1: Smart 模式降级', () {
    test('migrateSmartModeToToggle: smart → offline + AI 润色 on（行为不变）', () async {
      SharedPreferences.setMockInitialValues({'work_mode': 'smart'});
      await ConfigService().reload();
      await ConfigService().migrateSmartModeToToggle();
      expect(ConfigService().workMode, 'offline');
      expect(ConfigService().aiCorrectionEnabled, true);
      expect(ConfigService().asrEngineType, 'sherpa');
    });

    test('migrateSmartModeToToggle: 非 smart 不动', () async {
      SharedPreferences.setMockInitialValues({'work_mode': 'cloud'});
      await ConfigService().reload();
      await ConfigService().migrateSmartModeToToggle();
      expect(ConfigService().workMode, 'cloud');
    });

    test('setWorkMode 只管 ASR 引擎，不再强制开关 AI 润色', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService().reload();
      await ConfigService().setAiCorrectionEnabled(true);
      // 切到 offline 不应关掉 AI 润色（润色已独立）
      await ConfigService().setWorkMode('offline');
      expect(ConfigService().asrEngineType, 'sherpa');
      expect(ConfigService().aiCorrectionEnabled, true);
      // 切到 cloud 也不动 AI 润色
      await ConfigService().setWorkMode('cloud');
      expect(ConfigService().asrEngineType, 'aliyun');
      expect(ConfigService().aiCorrectionEnabled, true);
    });

    test('_inferWorkMode 不再推断 smart（aiCorrection 不决定模式）', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService().reload();
      await ConfigService().setAsrEngineType('sherpa');
      await ConfigService().setAiCorrectionEnabled(true);
      // 无显式 work_mode，aiCorrection on 也只推断为 offline（不再是 smart）
      expect(ConfigService().workMode, 'offline');
    });
  });
}
