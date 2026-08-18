import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:speakout/services/config_service.dart';

class _FailOncePreferencesStore extends InMemorySharedPreferencesStore {
  _FailOncePreferencesStore() : super.empty();

  bool _shouldFail = true;

  @override
  Future<Map<String, Object>> getAll() {
    if (_shouldFail) {
      _shouldFail = false;
      return Future.error(StateError('first load failed'));
    }
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次 SharedPreferences 加载失败后可以重试', () async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _FailOncePreferencesStore();

    await expectLater(ConfigService().init(), throwsStateError);
    await ConfigService().init().timeout(const Duration(seconds: 1));

    await ConfigService().setAppLanguage('en');
    expect(ConfigService().appLanguage, 'en');
  });
}
