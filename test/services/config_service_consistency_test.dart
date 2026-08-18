import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigService().reload();
  });

  test('设置音频 UID 但不提供名称时清掉旧名称', () async {
    await ConfigService().setAudioInputDeviceId(
      'old-mic',
      name: 'Old Microphone',
    );

    await ConfigService().setAudioInputDeviceId('new-mic');

    expect(ConfigService().audioInputDeviceId, 'new-mic');
    expect(ConfigService().audioInputDeviceName, isNull);
  });

  test('切换 ASR 账户但不指定模型时清掉旧账户模型', () async {
    await ConfigService().setSelectedAsrAccount(
      'account-a',
      modelId: 'model-a',
    );

    await ConfigService().setSelectedAsrAccount('account-b');

    expect(ConfigService().selectedAsrAccountId, 'account-b');
    expect(ConfigService().selectedAsrModelId, isNull);
  });

  test('无选中账户时设置 LLM 模型会清掉旧 owner', () async {
    await ConfigService().setSelectedLlmAccountId('account-a');
    await ConfigService().setLlmModel('model-a');
    await ConfigService().setSelectedLlmAccountId(null);

    await ConfigService().setLlmModel('global-model');

    expect(ConfigService().llmModelOverride, 'global-model');
    expect(ConfigService().llmModelOwnerAccountId, isNull);
  });

  test('清除 Toggle Diary 快捷键同时清掉修饰键', () async {
    await ConfigService().setToggleDiaryKey(60, 'Right Shift', modifiers: 123);

    await ConfigService().clearToggleDiaryKey();

    expect(ConfigService().toggleDiaryModifiers, 0);
  });
}
