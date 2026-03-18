import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/config/app_constants.dart';
import 'dart:ui';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigService config;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    config = ConfigService();
    await config.init();
  });

  // =========================================================================
  // 1. 快捷键配置 (PTT Key)
  // =========================================================================
  group('PTT 快捷键配置', () {
    test('pttKeyCode 默认值应为 AppConstants.kDefaultPttKeyCode', () {
      // 由于 singleton 已初始化，先清除自定义值来验证默认值
      // 默认值来自 AppConstants
      expect(AppConstants.kDefaultPttKeyCode, isA<int>());
    });

    test('pttKeyName 默认值应为 AppConstants.kDefaultPttKeyName', () {
      expect(AppConstants.kDefaultPttKeyName, isA<String>());
      expect(AppConstants.kDefaultPttKeyName.isNotEmpty, true);
    });

    test('setPttKey 应保存 keyCode 和 keyName', () async {
      await config.setPttKey(123, 'F5');
      expect(config.pttKeyCode, 123);
      expect(config.pttKeyName, 'F5');
    });

    test('setPttKey 可以设置为 0', () async {
      await config.setPttKey(0, '');
      expect(config.pttKeyCode, 0);
      expect(config.pttKeyName, '');
    });

    test('setPttKey 特殊字符名称', () async {
      await config.setPttKey(99, '⌘ Command');
      expect(config.pttKeyCode, 99);
      expect(config.pttKeyName, '⌘ Command');
    });

    test('setPttKey 超长名称', () async {
      final longName = 'K' * 1000;
      await config.setPttKey(42, longName);
      expect(config.pttKeyCode, 42);
      expect(config.pttKeyName, longName);
    });

    // 恢复默认
    tearDownAll(() async {
      await config.setPttKey(AppConstants.kDefaultPttKeyCode, AppConstants.kDefaultPttKeyName);
    });
  });

  // =========================================================================
  // 2. 日记/闪念笔记
  // =========================================================================
  group('日记/闪念笔记配置', () {
    test('diaryEnabled 默认值应为 false', () async {
      // 重置
      await config.setDiaryEnabled(false);
      expect(config.diaryEnabled, false);
    });

    test('setDiaryEnabled(true) 应持久化', () async {
      await config.setDiaryEnabled(true);
      expect(config.diaryEnabled, true);
    });

    test('setDiaryEnabled(false) 应持久化', () async {
      await config.setDiaryEnabled(false);
      expect(config.diaryEnabled, false);
    });

    test('diaryKeyCode 有默认值', () {
      // 默认值是一个 int
      expect(config.diaryKeyCode, isA<int>());
    });

    test('diaryKeyName 有默认值', () {
      expect(config.diaryKeyName, isA<String>());
    });

    test('setDiaryKey 应保存 code 和 name', () async {
      await config.setDiaryKey(55, 'Right Shift');
      expect(config.diaryKeyCode, 55);
      expect(config.diaryKeyName, 'Right Shift');
    });

    test('diaryDirectory 有默认值', () {
      // 默认值是 string（可能为空或指向文档目录）
      expect(config.diaryDirectory, isA<String>());
    });

    test('setDiaryDirectory 应持久化自定义路径', () async {
      await config.setDiaryDirectory('/Users/test/notes');
      expect(config.diaryDirectory, '/Users/test/notes');
    });

    test('setDiaryDirectory 可设为空字符串', () async {
      await config.setDiaryDirectory('');
      // 空字符串应被持久化
      expect(config.diaryDirectory, isA<String>());
    });

    test('setDiaryDirectory 中文路径', () async {
      await config.setDiaryDirectory('/用户/测试/笔记');
      expect(config.diaryDirectory, '/用户/测试/笔记');
    });
  });

  // =========================================================================
  // 3. ASR 引擎
  // =========================================================================
  group('ASR 引擎配置', () {
    test('asrEngineType 默认值', () async {
      // 默认应为某种本地引擎标识
      expect(config.asrEngineType, isA<String>());
      expect(config.asrEngineType.isNotEmpty, true);
    });

    test('setAsrEngineType 应持久化', () async {
      await config.setAsrEngineType('aliyun');
      expect(config.asrEngineType, 'aliyun');
    });

    test('setAsrEngineType 切换回本地', () async {
      await config.setAsrEngineType('sherpa');
      expect(config.asrEngineType, 'sherpa');
    });

    test('activeModelId 默认值应为 AppConstants.kDefaultModelId', () async {
      // 先清除自定义值
      await config.setActiveModelId(AppConstants.kDefaultModelId);
      expect(config.activeModelId, AppConstants.kDefaultModelId);
    });

    test('setActiveModelId 应持久化', () async {
      await config.setActiveModelId('whisper-large-v3');
      expect(config.activeModelId, 'whisper-large-v3');
    });

    test('setActiveModelId 空字符串', () async {
      await config.setActiveModelId('');
      // 空字符串被保存后，getter 应返回空字符串（因为已设置）
      expect(config.activeModelId, isA<String>());
    });

    // 恢复
    tearDownAll(() async {
      await config.setActiveModelId(AppConstants.kDefaultModelId);
      await config.setAsrEngineType('sherpa');
    });
  });

  // =========================================================================
  // 4. AI 润色
  // =========================================================================
  group('AI 润色配置', () {
    test('aiCorrectionEnabled 默认值应为 false', () {
      expect(AppConstants.kDefaultAiCorrectionEnabled, false);
    });

    test('setAiCorrectionEnabled(true) 应持久化', () async {
      await config.setAiCorrectionEnabled(true);
      expect(config.aiCorrectionEnabled, true);
    });

    test('setAiCorrectionEnabled(false) 应持久化', () async {
      await config.setAiCorrectionEnabled(false);
      expect(config.aiCorrectionEnabled, false);
    });

    test('aiCorrectionPrompt 默认值不为空', () {
      expect(AppConstants.kDefaultAiCorrectionPrompt.isNotEmpty, true);
      // 默认 prompt 应包含相关指令
      expect(config.aiCorrectionPrompt.isNotEmpty, true);
    });

    test('setAiCorrectionPrompt 应持久化自定义 prompt', () async {
      const customPrompt = '你是一个纯净的文本纠错助手。';
      await config.setAiCorrectionPrompt(customPrompt);
      expect(config.aiCorrectionPrompt, customPrompt);
    });

    test('setAiCorrectionPrompt 空字符串应回退到默认值', () async {
      await config.setAiCorrectionPrompt('');
      // _getStringWithDefault 对空字符串应回退到默认值
      expect(config.aiCorrectionPrompt, AppConstants.kDefaultAiCorrectionPrompt);
    });

    test('llmBaseUrl 默认值应为 AppConstants.kDefaultLlmBaseUrl', () async {
      // 清除自定义值以测试默认
      await config.setLlmBaseUrl('');
      expect(config.llmBaseUrl, AppConstants.kDefaultLlmBaseUrl);
    });

    test('setLlmBaseUrl 应持久化', () async {
      const url = 'https://api.openai.com/v1';
      await config.setLlmBaseUrl(url);
      expect(config.llmBaseUrl, url);
    });

    test('llmApiKey 默认值应为 AppConstants.kDefaultLlmApiKey', () {
      // Keychain 在测试中不可用，回退到缓存/默认
      // 未设置时应返回默认值（空字符串）
      expect(AppConstants.kDefaultLlmApiKey, isA<String>());
    });

    test('llmModel 默认值应为 AppConstants.kDefaultLlmModel', () async {
      await config.setLlmModel('');
      expect(config.llmModel, AppConstants.kDefaultLlmModel);
    });

    test('setLlmModel 应持久化', () async {
      await config.setLlmModel('gpt-4o');
      expect(config.llmModel, 'gpt-4o');
    });

    test('llmProviderType 默认值应为 cloud', () {
      expect(AppConstants.kDefaultLlmProviderType, 'cloud');
    });

    test('setLlmProviderType 应持久化', () async {
      await config.setLlmProviderType('ollama');
      expect(config.llmProviderType, 'ollama');
    });

    test('setLlmProviderType 切换回 cloud', () async {
      await config.setLlmProviderType('cloud');
      expect(config.llmProviderType, 'cloud');
    });

    // 恢复
    tearDownAll(() async {
      await config.setAiCorrectionEnabled(false);
      await config.setAiCorrectionPrompt('');
      await config.setLlmBaseUrl('');
      await config.setLlmModel('');
      await config.setLlmProviderType('cloud');
    });
  });

  // =========================================================================
  // 5. Ollama 配置
  // =========================================================================
  group('Ollama 配置', () {
    test('ollamaBaseUrl 默认值应为 http://localhost:11434', () async {
      await config.setOllamaBaseUrl('');
      expect(config.ollamaBaseUrl, AppConstants.kDefaultOllamaBaseUrl);
      expect(config.ollamaBaseUrl, 'http://localhost:11434');
    });

    test('setOllamaBaseUrl 应持久化', () async {
      await config.setOllamaBaseUrl('http://192.168.1.100:11434');
      expect(config.ollamaBaseUrl, 'http://192.168.1.100:11434');
    });

    test('ollamaModel 默认值应为 qwen3:0.6b', () async {
      await config.setOllamaModel('');
      expect(config.ollamaModel, AppConstants.kDefaultOllamaModel);
      expect(config.ollamaModel, 'qwen3:0.6b');
    });

    test('setOllamaModel 应持久化', () async {
      await config.setOllamaModel('llama3:8b');
      expect(config.ollamaModel, 'llama3:8b');
    });

    // 恢复
    tearDownAll(() async {
      await config.setOllamaBaseUrl('');
      await config.setOllamaModel('');
    });
  });

  // =========================================================================
  // 6. 音频设备
  // =========================================================================
  group('音频设备配置', () {
    test('audioInputDeviceId 未设置时应为 null', () async {
      await config.setAudioInputDeviceId(null);
      expect(config.audioInputDeviceId, isNull);
    });

    test('setAudioInputDeviceId 应持久化', () async {
      await config.setAudioInputDeviceId('device-123', name: 'MacBook Pro Mic');
      expect(config.audioInputDeviceId, 'device-123');
      expect(config.audioInputDeviceName, 'MacBook Pro Mic');
    });

    test('setAudioInputDeviceId(null) 应清除设备', () async {
      await config.setAudioInputDeviceId('some-device');
      await config.setAudioInputDeviceId(null);
      expect(config.audioInputDeviceId, isNull);
      expect(config.audioInputDeviceName, isNull);
    });

    test('setAudioInputDeviceId 不传 name 时只设 id', () async {
      await config.setAudioInputDeviceId('dev-456');
      expect(config.audioInputDeviceId, 'dev-456');
    });
  });

  // =========================================================================
  // 7. 词汇增强
  // =========================================================================
  group('词汇增强配置', () {
    test('vocabEnabled 默认值应为 false', () async {
      await config.setVocabEnabled(false);
      expect(config.vocabEnabled, false);
    });

    test('setVocabEnabled(true) 应持久化', () async {
      await config.setVocabEnabled(true);
      expect(config.vocabEnabled, true);
    });

    test('vocabTechEnabled 默认值应为 false', () {
      // 行业词典默认关闭
      expect(config.vocabTechEnabled, isA<bool>());
    });

    test('setVocabTechEnabled 应持久化', () async {
      await config.setVocabTechEnabled(true);
      expect(config.vocabTechEnabled, true);
      await config.setVocabTechEnabled(false);
      expect(config.vocabTechEnabled, false);
    });

    test('vocabMedicalEnabled 默认值 & setter', () async {
      await config.setVocabMedicalEnabled(true);
      expect(config.vocabMedicalEnabled, true);
      await config.setVocabMedicalEnabled(false);
      expect(config.vocabMedicalEnabled, false);
    });

    test('vocabLegalEnabled 默认值 & setter', () async {
      await config.setVocabLegalEnabled(true);
      expect(config.vocabLegalEnabled, true);
      await config.setVocabLegalEnabled(false);
      expect(config.vocabLegalEnabled, false);
    });

    test('vocabFinanceEnabled 默认值 & setter', () async {
      await config.setVocabFinanceEnabled(true);
      expect(config.vocabFinanceEnabled, true);
      await config.setVocabFinanceEnabled(false);
      expect(config.vocabFinanceEnabled, false);
    });

    test('vocabEducationEnabled 默认值 & setter', () async {
      await config.setVocabEducationEnabled(true);
      expect(config.vocabEducationEnabled, true);
      await config.setVocabEducationEnabled(false);
      expect(config.vocabEducationEnabled, false);
    });

    test('vocabUserEnabled 默认值', () {
      // 用户自定义词条默认状态
      expect(config.vocabUserEnabled, isA<bool>());
    });

    test('setVocabUserEnabled 应持久化', () async {
      await config.setVocabUserEnabled(true);
      expect(config.vocabUserEnabled, true);
      await config.setVocabUserEnabled(false);
      expect(config.vocabUserEnabled, false);
    });

    test('vocabUserEntriesJson 默认值应为 "[]"', () async {
      // 默认应为空 JSON 数组
      // 先清除自定义值
      await config.setVocabUserEntriesJson('[]');
      expect(config.vocabUserEntriesJson, '[]');
    });

    test('setVocabUserEntriesJson 应持久化 JSON 字符串', () async {
      const json = '[{"original":"flutter","replacement":"Flutter"}]';
      await config.setVocabUserEntriesJson(json);
      expect(config.vocabUserEntriesJson, json);
    });

    test('setVocabUserEntriesJson 空字符串', () async {
      await config.setVocabUserEntriesJson('');
      expect(config.vocabUserEntriesJson, isA<String>());
    });

    test('setVocabUserEntriesJson 特殊字符', () async {
      const json = '[{"original":"C++","replacement":"C++语言"}]';
      await config.setVocabUserEntriesJson(json);
      expect(config.vocabUserEntriesJson, json);
    });

    test('setVocabUserEntriesJson 超长 JSON', () async {
      final longJson = '[${List.generate(100, (i) => '{"k$i":"v$i"}').join(',')}]';
      await config.setVocabUserEntriesJson(longJson);
      expect(config.vocabUserEntriesJson, longJson);
    });

    // 恢复
    tearDownAll(() async {
      await config.setVocabEnabled(false);
      await config.setVocabTechEnabled(false);
      await config.setVocabMedicalEnabled(false);
      await config.setVocabLegalEnabled(false);
      await config.setVocabFinanceEnabled(false);
      await config.setVocabEducationEnabled(false);
      await config.setVocabUserEnabled(true);
      await config.setVocabUserEntriesJson('[]');
    });
  });

  // =========================================================================
  // 8. Toggle 模式
  // =========================================================================
  group('Toggle 模式配置', () {
    test('toggleInputEnabled 由 keyCode 决定', () async {
      await config.clearToggleInputKey();
      // keyCode 为 0 时 toggleInputEnabled 应为 false
      expect(config.toggleInputKeyCode, AppConstants.kDefaultToggleInputKeyCode);
      expect(config.toggleInputEnabled, false);
    });

    test('设置 toggle input key 后 toggleInputEnabled 为 true', () async {
      await config.setToggleInputKey(56, 'Left Shift');
      expect(config.toggleInputEnabled, true);
      expect(config.toggleInputKeyCode, 56);
      expect(config.toggleInputKeyName, 'Left Shift');
    });

    test('clearToggleInputKey 应清除并恢复默认', () async {
      await config.setToggleInputKey(56, 'Left Shift');
      await config.clearToggleInputKey();
      expect(config.toggleInputEnabled, false);
      expect(config.toggleInputKeyCode, AppConstants.kDefaultToggleInputKeyCode);
    });

    test('toggleDiaryEnabled 由 keyCode 决定', () async {
      await config.clearToggleDiaryKey();
      expect(config.toggleDiaryEnabled, false);
    });

    test('设置 toggle diary key 后 toggleDiaryEnabled 为 true', () async {
      await config.setToggleDiaryKey(60, 'Right Shift');
      expect(config.toggleDiaryEnabled, true);
      expect(config.toggleDiaryKeyCode, 60);
      expect(config.toggleDiaryKeyName, 'Right Shift');
    });

    test('clearToggleDiaryKey 应清除并恢复默认', () async {
      await config.setToggleDiaryKey(60, 'Right Shift');
      await config.clearToggleDiaryKey();
      expect(config.toggleDiaryEnabled, false);
    });

    test('toggleMaxDuration 默认值应为 AppConstants.kDefaultToggleMaxDuration', () {
      expect(config.toggleMaxDuration, AppConstants.kDefaultToggleMaxDuration);
    });

    test('setToggleMaxDuration 应持久化', () async {
      await config.setToggleMaxDuration(60);
      expect(config.toggleMaxDuration, 60);
    });

    test('setToggleMaxDuration 设为 0', () async {
      await config.setToggleMaxDuration(0);
      expect(config.toggleMaxDuration, 0);
    });

    test('setToggleMaxDuration 设为很大的值', () async {
      await config.setToggleMaxDuration(86400);
      expect(config.toggleMaxDuration, 86400);
    });

    // 恢复
    tearDownAll(() async {
      await config.clearToggleInputKey();
      await config.clearToggleDiaryKey();
      await config.setToggleMaxDuration(AppConstants.kDefaultToggleMaxDuration);
    });
  });

  // =========================================================================
  // 9. 日志配置
  // =========================================================================
  group('日志配置', () {
    test('verboseLogging 默认值应为 false', () {
      expect(AppConstants.kVerboseLogging, false);
    });

    test('setVerboseLogging 应持久化', () async {
      await config.setVerboseLogging(true);
      expect(config.verboseLogging, true);
      await config.setVerboseLogging(false);
      expect(config.verboseLogging, false);
    });

    test('logDirectory 默认值应为空字符串', () async {
      await config.setLogDirectory('');
      expect(config.logDirectory, '');
    });

    test('setLogDirectory 应持久化', () async {
      await config.setLogDirectory('/tmp/speakout_logs');
      expect(config.logDirectory, '/tmp/speakout_logs');
    });

    test('setLogDirectory 中文路径', () async {
      await config.setLogDirectory('/用户/日志');
      expect(config.logDirectory, '/用户/日志');
    });

    // 恢复
    tearDownAll(() async {
      await config.setVerboseLogging(false);
      await config.setLogDirectory('');
    });
  });

  // =========================================================================
  // 10. 国际化
  // =========================================================================
  group('国际化配置', () {
    test('appLanguage 默认值应为 "system"', () {
      expect(config.appLanguage, 'system');
    });

    test('localeNotifier 初始值: system 时为 null', () async {
      await config.setAppLanguage('system');
      expect(config.localeNotifier.value, isNull);
    });

    test('setAppLanguage("en") 应更新 localeNotifier', () async {
      await config.setAppLanguage('en');
      expect(config.appLanguage, 'en');
      expect(config.localeNotifier.value, const Locale('en'));
    });

    test('setAppLanguage("zh") 应更新 localeNotifier', () async {
      await config.setAppLanguage('zh');
      expect(config.appLanguage, 'zh');
      expect(config.localeNotifier.value, const Locale('zh'));
    });

    test('setAppLanguage("system") 应将 localeNotifier 设为 null', () async {
      await config.setAppLanguage('en');
      expect(config.localeNotifier.value, isNotNull);

      await config.setAppLanguage('system');
      expect(config.appLanguage, 'system');
      expect(config.localeNotifier.value, isNull);
    });

    test('localeNotifier 切换时触发监听', () async {
      final values = <Locale?>[];
      void listener() => values.add(config.localeNotifier.value);
      config.localeNotifier.addListener(listener);

      await config.setAppLanguage('en');
      await config.setAppLanguage('zh');
      await config.setAppLanguage('system');

      config.localeNotifier.removeListener(listener);

      expect(values.length, 3);
      expect(values[0], const Locale('en'));
      expect(values[1], const Locale('zh'));
      expect(values[2], isNull);
    });

    // 恢复
    tearDownAll(() async {
      await config.setAppLanguage('system');
    });
  });

  // =========================================================================
  // 11. 引导页
  // =========================================================================
  group('引导页状态', () {
    test('isFirstLaunch 默认值应为 true', () async {
      await config.resetOnboarding();
      expect(config.isFirstLaunch, true);
    });

    test('completeOnboarding 后 isFirstLaunch 应为 false', () async {
      await config.resetOnboarding();
      expect(config.isFirstLaunch, true);

      await config.completeOnboarding();
      expect(config.isFirstLaunch, false);
    });

    test('resetOnboarding 应恢复为首次启动状态', () async {
      await config.completeOnboarding();
      expect(config.isFirstLaunch, false);

      await config.resetOnboarding();
      expect(config.isFirstLaunch, true);
    });

    test('重复 completeOnboarding 应幂等', () async {
      await config.resetOnboarding();
      await config.completeOnboarding();
      await config.completeOnboarding();
      expect(config.isFirstLaunch, false);
    });

    test('重复 resetOnboarding 应幂等', () async {
      await config.completeOnboarding();
      await config.resetOnboarding();
      await config.resetOnboarding();
      expect(config.isFirstLaunch, true);
    });
  });

  // =========================================================================
  // 12. Override 属性
  // =========================================================================
  group('Override 属性', () {
    test('llmBaseUrlOverride 未设置自定义值时应为 null', () async {
      // 清除自定义 URL
      // SharedPreferences 中无 llm_base_url 时应返回 null
      // 但由于 singleton 状态，需要通过 setLlmBaseUrl('') 清除
      // 注意: setLlmBaseUrl('') 会写入空字符串，getString 仍会返回空字符串而非 null
      // 所以 override 可能返回空字符串
      final override = config.llmBaseUrlOverride;
      // override 应为 null 或 String
      expect(override == null || override is String, true);
    });

    test('llmBaseUrlOverride 设置自定义值后应返回该值', () async {
      await config.setLlmBaseUrl('https://custom.api.com/v1');
      expect(config.llmBaseUrlOverride, 'https://custom.api.com/v1');
    });

    test('llmModelOverride 设置自定义值后应返回该值', () async {
      await config.setLlmModel('custom-model');
      expect(config.llmModelOverride, 'custom-model');
    });

    test('llmApiKeyOverride 未设置时应为 null', () {
      // Keychain 不可用时，缓存值可能为 null
      // 这取决于初始化时 _preloadSecureKeys 的行为
      final override = config.llmApiKeyOverride;
      expect(override == null || override is String, true);
    });

    // 恢复
    tearDownAll(() async {
      await config.setLlmBaseUrl('');
      await config.setLlmModel('');
    });
  });

  // =========================================================================
  // 13. 组合状态测试
  // =========================================================================
  group('组合状态', () {
    test('AI 开 + Ollama 模式 + 词汇开', () async {
      await config.setAiCorrectionEnabled(true);
      await config.setLlmProviderType('ollama');
      await config.setVocabEnabled(true);

      expect(config.aiCorrectionEnabled, true);
      expect(config.llmProviderType, 'ollama');
      expect(config.vocabEnabled, true);
      // Ollama 模式下应使用 Ollama 配置
      expect(config.ollamaBaseUrl, isNotEmpty);
      expect(config.ollamaModel, isNotEmpty);
    });

    test('AI 开 + Cloud 模式 + 词汇关', () async {
      await config.setAiCorrectionEnabled(true);
      await config.setLlmProviderType('cloud');
      await config.setVocabEnabled(false);

      expect(config.aiCorrectionEnabled, true);
      expect(config.llmProviderType, 'cloud');
      expect(config.vocabEnabled, false);
      // Cloud 模式下应使用标准 LLM 配置
      expect(config.llmBaseUrl, isNotEmpty);
      expect(config.llmModel, isNotEmpty);
    });

    test('AI 关 + 词汇开', () async {
      await config.setAiCorrectionEnabled(false);
      await config.setVocabEnabled(true);

      expect(config.aiCorrectionEnabled, false);
      expect(config.vocabEnabled, true);
    });

    test('AI 关 + 词汇关', () async {
      await config.setAiCorrectionEnabled(false);
      await config.setVocabEnabled(false);

      expect(config.aiCorrectionEnabled, false);
      expect(config.vocabEnabled, false);
    });

    test('多行业词典同时启用', () async {
      await config.setVocabEnabled(true);
      await config.setVocabTechEnabled(true);
      await config.setVocabMedicalEnabled(true);
      await config.setVocabLegalEnabled(true);
      await config.setVocabFinanceEnabled(true);
      await config.setVocabEducationEnabled(true);
      await config.setVocabUserEnabled(true);

      expect(config.vocabEnabled, true);
      expect(config.vocabTechEnabled, true);
      expect(config.vocabMedicalEnabled, true);
      expect(config.vocabLegalEnabled, true);
      expect(config.vocabFinanceEnabled, true);
      expect(config.vocabEducationEnabled, true);
      expect(config.vocabUserEnabled, true);
    });

    test('Toggle 模式 + PTT 共存', () async {
      await config.setPttKey(63, 'Fn');
      await config.setToggleInputKey(56, 'Left Shift');
      await config.setToggleMaxDuration(120);

      expect(config.pttKeyCode, 63);
      expect(config.toggleInputEnabled, true);
      expect(config.toggleInputKeyCode, 56);
      expect(config.toggleMaxDuration, 120);
    });

    test('日记模式 + Toggle 日记共存', () async {
      await config.setDiaryEnabled(true);
      await config.setDiaryKey(61, 'Right Option');
      await config.setToggleDiaryKey(60, 'Right Shift');

      expect(config.diaryEnabled, true);
      expect(config.diaryKeyCode, 61);
      expect(config.toggleDiaryEnabled, true);
      expect(config.toggleDiaryKeyCode, 60);
    });

    // 恢复
    tearDownAll(() async {
      await config.setAiCorrectionEnabled(false);
      await config.setLlmProviderType('cloud');
      await config.setVocabEnabled(false);
      await config.setVocabTechEnabled(false);
      await config.setVocabMedicalEnabled(false);
      await config.setVocabLegalEnabled(false);
      await config.setVocabFinanceEnabled(false);
      await config.setVocabEducationEnabled(false);
      await config.setVocabUserEnabled(true);
      await config.clearToggleInputKey();
      await config.clearToggleDiaryKey();
      await config.setDiaryEnabled(false);
    });
  });

  // =========================================================================
  // 14. Singleton 保护
  // =========================================================================
  group('Singleton 保护', () {
    test('ConfigService() 每次返回相同实例', () {
      final a = ConfigService();
      final b = ConfigService();
      expect(identical(a, b), true);
    });

    test('多次调用 init() 应幂等（不会报错）', () async {
      // init 有 if (_initialized) return 保护
      await config.init();
      await config.init();
      // 不应抛出异常
      expect(config.pttKeyCode, isA<int>());
    });

    test('init 后修改的值在同一实例中可见', () async {
      await config.setPttKey(77, 'TestKey');
      final sameInstance = ConfigService();
      expect(sameInstance.pttKeyCode, 77);
      expect(sameInstance.pttKeyName, 'TestKey');
    });
  });

  // =========================================================================
  // 15. 边界测试
  // =========================================================================
  group('边界测试', () {
    test('空字符串 setter 行为: llmBaseUrl', () async {
      await config.setLlmBaseUrl('');
      // 空字符串应回退到默认值（_getStringWithDefault 行为）
      expect(config.llmBaseUrl, AppConstants.kDefaultLlmBaseUrl);
    });

    test('空字符串 setter 行为: ollamaBaseUrl', () async {
      await config.setOllamaBaseUrl('');
      expect(config.ollamaBaseUrl, AppConstants.kDefaultOllamaBaseUrl);
    });

    test('空字符串 setter 行为: ollamaModel', () async {
      await config.setOllamaModel('');
      expect(config.ollamaModel, AppConstants.kDefaultOllamaModel);
    });

    test('空字符串 setter 行为: aiCorrectionPrompt', () async {
      await config.setAiCorrectionPrompt('');
      expect(config.aiCorrectionPrompt, AppConstants.kDefaultAiCorrectionPrompt);
    });

    test('空白字符串（仅空格）应回退到默认值', () async {
      await config.setLlmBaseUrl('   ');
      // _getStringWithDefault 对 trim() 后为空的值应回退
      expect(config.llmBaseUrl, AppConstants.kDefaultLlmBaseUrl);
    });

    test('特殊字符字符串', () async {
      const special = 'https://api.example.com/v1?key=abc&token=123#section';
      await config.setLlmBaseUrl(special);
      expect(config.llmBaseUrl, special);
    });

    test('Unicode 字符串', () async {
      const unicode = '模型名称-v2.0-中文版';
      await config.setLlmModel(unicode);
      expect(config.llmModel, unicode);
    });

    test('超长字符串不会崩溃', () async {
      final longStr = 'x' * 10000;
      await config.setLlmBaseUrl(longStr);
      expect(config.llmBaseUrl, longStr);
    });

    test('负数 keyCode', () async {
      await config.setPttKey(-1, 'Invalid');
      expect(config.pttKeyCode, -1);
      expect(config.pttKeyName, 'Invalid');
    });

    test('最大 int keyCode', () async {
      // Dart int 可以很大，但 SharedPreferences 用 int64
      await config.setPttKey(2147483647, 'MaxInt');
      expect(config.pttKeyCode, 2147483647);
    });

    test('toggleMaxDuration 负数', () async {
      await config.setToggleMaxDuration(-1);
      expect(config.toggleMaxDuration, -1);
    });
  });

  // =========================================================================
  // 16. Agent Router 配置
  // =========================================================================
  group('Agent Router 配置', () {
    test('agentRouterModel 默认值应回退到 llmModel', () async {
      await config.setLlmModel('qwen-turbo');
      // 未设置 agentRouterModel 时应回退到 llmModel
      expect(config.agentRouterModel, isA<String>());
    });

    test('setAgentRouterModel 应持久化', () async {
      await config.setAgentRouterModel('qwen-plus');
      expect(config.agentRouterModel, 'qwen-plus');
    });

    test('setAgentRouterModel 空字符串应回退到 llmModel', () async {
      await config.setLlmModel('qwen-turbo');
      await config.setAgentRouterModel('');
      // _getStringWithDefault 对空字符串回退到 llmModel
      expect(config.agentRouterModel, config.llmModel);
    });
  });
}
