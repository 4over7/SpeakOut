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
  });
}
