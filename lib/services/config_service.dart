import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_constants.dart';
import 'package:speakout/config/app_log.dart';

/// 管理应用程序配置 (SharedPreferences)
/// Singleton Pattern.
/// 
/// V1.1.3 Fix: Made robust against uninitialized access to prevent White Screen on startup.
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  static const String kDefaultGatewayUrl = 'https://speakout-gateway.4over7.workers.dev';
  static const String kDefaultTopUpUrl = "https://mianbaoduo.com"; 
  // Safe field: Nullable prefs
  SharedPreferences? _prefs;
  bool _initialized = false;
  Completer<void>? _initCompleter;
  // Default doc path (fallback if not init)
  String _defaultDocPath = "";

  // In-memory cache for credential values (loaded from Keychain at startup)
  String? _cachedAliyunAkId;
  String? _cachedAliyunAkSecret;
  String? _cachedAliyunAppKey;
  String? _cachedLlmApiKey;

  // Local Notifier for Language Change
  final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);

  Future<void> init() async {
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    _prefs = await SharedPreferences.getInstance();
    
    // Get Safe Directory
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _defaultDocPath = "${docDir.path}/SpeakOut_Notes";
    } catch (e) {
      AppLog.d("ConfigService: Failed to get doc dir: $e");
    }
    
    // Load Locale
    _updateLocaleNotifier();

    // Preload Keychain values into memory cache
    _preloadSecureKeys();

    _initialized = true;
    _initCompleter!.complete();
  }

  /// 重新加载配置（导入配置后调用，刷新内存缓存）
  Future<void> reload() async {
    _prefs = await SharedPreferences.getInstance();
    _preloadSecureKeys();
    _updateLocaleNotifier();
  }

  // --- Hotkey ---

  int get pttKeyCode => _prefs?.getInt(AppConstants.kKeyPttKeyCode) ?? AppConstants.kDefaultPttKeyCode;
  int get pttModifiers => _prefs?.getInt('ptt_modifiers') ?? 0;

  String get pttKeyName => _prefs?.getString(AppConstants.kKeyPttKeyName) ?? AppConstants.kDefaultPttKeyName;

  Future<void> setPttKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt(AppConstants.kKeyPttKeyCode, code);
    await _prefs?.setString(AppConstants.kKeyPttKeyName, name);
    await _prefs?.setInt('ptt_modifiers', modifiers);
  }
  Future<void> clearPttKey() async {
    await _prefs?.setInt(AppConstants.kKeyPttKeyCode, 0);
    await _prefs?.setString(AppConstants.kKeyPttKeyName, '');
    await _prefs?.remove('ptt_modifiers');
  }

  // --- Diary (Flash Note) ---
  bool get diaryEnabled => _prefs?.getBool('diary_enabled') ?? false;
  int get diaryKeyCode => _prefs?.getInt('diary_key_code') ?? 61; // Default Right Option
  int get diaryModifiers => _prefs?.getInt('diary_modifiers') ?? 0;
  String get diaryKeyName => _prefs?.getString('diary_key_name') ?? "Right Option";
  String get diaryDirectory => _prefs?.getString('diary_directory') ?? _defaultDocPath;

  Future<void> setDiaryEnabled(bool enabled) async => await _prefs?.setBool('diary_enabled', enabled);
  Future<void> setDiaryKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('diary_key_code', code);
    await _prefs?.setString('diary_key_name', name);
    await _prefs?.setInt('diary_modifiers', modifiers);
  }
  Future<void> clearDiaryKey() async {
    await _prefs?.setInt('diary_key_code', 0);
    await _prefs?.setString('diary_key_name', '');
    await _prefs?.remove('diary_modifiers');
  }
  Future<void> setDiaryDirectory(String path) async => await _prefs?.setString('diary_directory', path);

  // --- Toggle Input (Text Injection) ---
  bool get toggleInputEnabled => toggleInputKeyCode != 0;
  int get toggleInputKeyCode => _prefs?.getInt('toggle_input_key_code') ?? AppConstants.kDefaultToggleInputKeyCode;
  int get toggleInputModifiers => _prefs?.getInt('toggle_input_modifiers') ?? 0;
  String get toggleInputKeyName => _prefs?.getString('toggle_input_key_name') ?? AppConstants.kDefaultToggleInputKeyName;
  Future<void> setToggleInputKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('toggle_input_key_code', code);
    await _prefs?.setString('toggle_input_key_name', name);
    await _prefs?.setInt('toggle_input_modifiers', modifiers);
  }
  Future<void> clearToggleInputKey() async {
    await _prefs?.remove('toggle_input_key_code');
    await _prefs?.remove('toggle_input_key_name');
    await _prefs?.remove('toggle_input_modifiers');
  }

  // --- Toggle Diary (Flash Note) ---
  bool get toggleDiaryEnabled => toggleDiaryKeyCode != 0;
  int get toggleDiaryKeyCode => _prefs?.getInt('toggle_diary_key_code') ?? AppConstants.kDefaultToggleDiaryKeyCode;
  int get toggleDiaryModifiers => _prefs?.getInt('toggle_diary_modifiers') ?? 0;
  String get toggleDiaryKeyName => _prefs?.getString('toggle_diary_key_name') ?? AppConstants.kDefaultToggleDiaryKeyName;
  Future<void> setToggleDiaryKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('toggle_diary_key_code', code);
    await _prefs?.setString('toggle_diary_key_name', name);
    await _prefs?.setInt('toggle_diary_modifiers', modifiers);
  }
  Future<void> clearToggleDiaryKey() async {
    await _prefs?.remove('toggle_diary_key_code');
    await _prefs?.remove('toggle_diary_key_name');
  }

  // --- Toggle Shared Config ---
  int get toggleMaxDuration => _prefs?.getInt('toggle_max_duration') ?? AppConstants.kDefaultToggleMaxDuration;
  Future<void> setToggleMaxDuration(int seconds) async => await _prefs?.setInt('toggle_max_duration', seconds);

  // --- AI 梳理 (Organize) ---
  bool get organizeEnabled => _prefs?.getBool('organize_enabled') ?? false;
  int get organizeKeyCode => _prefs?.getInt('organize_key_code') ?? 0; // 0 = 未设置
  int get organizeModifiers => _prefs?.getInt('organize_modifiers') ?? 0;
  String get organizeKeyName => _prefs?.getString('organize_key_name') ?? '';
  String get organizePrompt => _getStringWithDefault('organize_prompt', AppConstants.kDefaultOrganizePrompt);

  Future<void> setOrganizeEnabled(bool v) async => await _prefs?.setBool('organize_enabled', v);
  Future<void> setOrganizeKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('organize_key_code', code);
    await _prefs?.setString('organize_key_name', name);
    await _prefs?.setInt('organize_modifiers', modifiers);
  }
  Future<void> clearOrganizeKey() async {
    await _prefs?.remove('organize_key_code');
    await _prefs?.remove('organize_key_name');
    await _prefs?.remove('organize_modifiers');
  }
  Future<void> setOrganizePrompt(String v) async => await _prefs?.setString('organize_prompt', v);

  // --- 纠错反馈 (Correction Feedback) ---
  bool get correctionEnabled => _prefs?.getBool('correction_enabled') ?? false;
  int get correctionKeyCode => _prefs?.getInt('correction_key_code') ?? 0;
  int get correctionModifiers => _prefs?.getInt('correction_modifiers') ?? 0;
  String get correctionKeyName => _prefs?.getString('correction_key_name') ?? '';

  Future<void> setCorrectionEnabled(bool v) async => await _prefs?.setBool('correction_enabled', v);
  Future<void> setCorrectionKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('correction_key_code', code);
    await _prefs?.setString('correction_key_name', name);
    await _prefs?.setInt('correction_modifiers', modifiers);
  }
  Future<void> clearCorrectionKey() async {
    await _prefs?.remove('correction_key_code');
    await _prefs?.remove('correction_key_name');
    await _prefs?.remove('correction_modifiers');
  }

  // --- AI 一键调试 (AI Debug) — 基础按键 + 数字组合 ---
  static const int kMaxAiReportSlots = 5;
  /// 数字键 keyCode: 1=18, 2=19, 3=20, 4=21, 5=23
  static const List<int> kNumberKeyCodes = [18, 19, 20, 21, 23];

  bool get aiReportEnabled => _prefs?.getBool('ai_report_enabled') ?? false;
  Future<void> setAiReportEnabled(bool v) async => await _prefs?.setBool('ai_report_enabled', v);

  // 基础按键（用户只设这一个，按住它 + 数字选槽位）
  int get aiReportBaseKeyCode => _prefs?.getInt('ai_report_base_key_code') ?? 0;
  String get aiReportBaseKeyName => _prefs?.getString('ai_report_base_key_name') ?? '';
  Future<void> setAiReportBaseKey(int code, String name) async {
    await _prefs?.setInt('ai_report_base_key_code', code);
    await _prefs?.setString('ai_report_base_key_name', name);
  }
  Future<void> clearAiReportBaseKey() async {
    await _prefs?.remove('ai_report_base_key_code');
    await _prefs?.remove('ai_report_base_key_name');
  }

  // 槽位数量和目标
  int get aiReportSlotCount => _prefs?.getInt('ai_report_slot_count') ?? 0;
  Future<void> setAiReportSlotCount(int n) async => await _prefs?.setInt('ai_report_slot_count', n);

  String? aiReportSlotBundleId(int i) => _prefs?.getString('ai_report_s${i}_bundle_id');
  String? aiReportSlotAppName(int i) => _prefs?.getString('ai_report_s${i}_app_name');
  String? aiReportSlotWindowTitle(int i) => _prefs?.getString('ai_report_s${i}_window_title');

  Future<void> setAiReportSlotTarget(int i, String? bundleId, String? appName, {String? windowTitle}) async {
    if (bundleId == null) {
      await _prefs?.remove('ai_report_s${i}_bundle_id');
      await _prefs?.remove('ai_report_s${i}_app_name');
      await _prefs?.remove('ai_report_s${i}_window_title');
    } else {
      await _prefs?.setString('ai_report_s${i}_bundle_id', bundleId);
      if (appName != null) await _prefs?.setString('ai_report_s${i}_app_name', appName);
      if (windowTitle != null) await _prefs?.setString('ai_report_s${i}_window_title', windowTitle);
    }
  }

  Future<void> removeAiReportSlot(int index) async {
    final count = aiReportSlotCount;
    for (int i = index; i < count - 1; i++) {
      final nextBid = aiReportSlotBundleId(i + 1);
      final nextApp = aiReportSlotAppName(i + 1);
      final nextTitle = aiReportSlotWindowTitle(i + 1);
      await setAiReportSlotTarget(i, nextBid, nextApp, windowTitle: nextTitle);
    }
    await setAiReportSlotTarget(count - 1, null, null);
    await setAiReportSlotCount(count - 1);
  }

  /// 迁移旧配置到新的基础按键+槽位模型
  Future<void> migrateAiReportSlots() async {
    // 已有 base key → 已迁移
    if ((_prefs?.getInt('ai_report_base_key_code') ?? 0) != 0) return;
    // 从 slot 0 key 迁移（上一版多槽位格式）
    final s0Code = _prefs?.getInt('ai_report_s0_key_code') ?? 0;
    if (s0Code != 0) {
      await setAiReportBaseKey(s0Code, _prefs?.getString('ai_report_s0_key_name') ?? '');
      // 清理旧的 per-slot key 数据
      for (int i = 0; i < kMaxAiReportSlots; i++) {
        await _prefs?.remove('ai_report_s${i}_key_code');
        await _prefs?.remove('ai_report_s${i}_key_name');
        await _prefs?.remove('ai_report_s${i}_modifiers');
      }
      return;
    }
    // 从最初的单键格式迁移
    final oldCode = _prefs?.getInt('ai_report_key_code') ?? 0;
    if (oldCode == 0) return;
    await setAiReportBaseKey(oldCode, _prefs?.getString('ai_report_key_name') ?? '');
    final oldBid = _prefs?.getString('ai_report_target_bundle_id');
    final oldApp = _prefs?.getString('ai_report_target_app_name');
    if (oldBid != null) {
      await setAiReportSlotTarget(0, oldBid, oldApp);
      await setAiReportSlotCount(1);
    }
    await _prefs?.remove('ai_report_key_code');
    await _prefs?.remove('ai_report_key_name');
    await _prefs?.remove('ai_report_modifiers');
    await _prefs?.remove('ai_report_target_bundle_id');
    await _prefs?.remove('ai_report_target_app_name');
  }

  // --- 即时翻译 (Quick Translate) ---
  bool get translateEnabled => _prefs?.getBool('translate_enabled') ?? false;
  int get translateKeyCode => _prefs?.getInt('translate_key_code') ?? 0;
  int get translateModifiers => _prefs?.getInt('translate_modifiers') ?? 0;
  String get translateKeyName => _prefs?.getString('translate_key_name') ?? '';
  String get translateTargetLanguage => _prefs?.getString('translate_target_language') ?? 'en';

  Future<void> setTranslateEnabled(bool v) async => await _prefs?.setBool('translate_enabled', v);
  Future<void> setTranslateKey(int code, String name, {int modifiers = 0}) async {
    await _prefs?.setInt('translate_key_code', code);
    await _prefs?.setString('translate_key_name', name);
    await _prefs?.setInt('translate_modifiers', modifiers);
  }
  Future<void> clearTranslateKey() async {
    await _prefs?.remove('translate_key_code');
    await _prefs?.remove('translate_key_name');
    await _prefs?.remove('translate_modifiers');
  }
  Future<void> setTranslateTargetLanguage(String lang) async => await _prefs?.setString('translate_target_language', lang);

  // --- Model ---

  String get activeModelId => _prefs?.getString(AppConstants.kKeyActiveModelId) ?? AppConstants.kDefaultModelId;

  Future<void> setActiveModelId(String id) async {
    await _prefs?.setString(AppConstants.kKeyActiveModelId, id);
  }

  // --- Audio Input ---
  
  String? get audioInputDeviceId => _prefs?.getString('audio_device_id');
  String? get audioInputDeviceName => _prefs?.getString('audio_device_name');
  
  Future<void> setAudioInputDeviceId(String? id, {String? name}) async {
    if (id == null) {
      await _prefs?.remove('audio_device_id');
      await _prefs?.remove('audio_device_name');
    } else {
      await _prefs?.setString('audio_device_id', id);
      if (name != null) await _prefs?.setString('audio_device_name', name);
    }
  }
  
  // --- Aliyun Config ---
  String get aliyunAccessKeyId => _cachedAliyunAkId ?? AppConstants.kDefaultAliyunAkId;
  String get aliyunAccessKeySecret => _cachedAliyunAkSecret ?? AppConstants.kDefaultAliyunAkSecret;
  String get aliyunAppKey => _cachedAliyunAppKey ?? AppConstants.kDefaultAliyunAppKey;

  Future<void> setAliyunCredentials(String id, String secret, String appKey) async {
    _cachedAliyunAkId = id.isEmpty ? null : id;
    _cachedAliyunAkSecret = secret.isEmpty ? null : secret;
    _cachedAliyunAppKey = appKey.isEmpty ? null : appKey;
    if (id.isEmpty) { await _prefs?.remove('aliyun_ak_id'); }
    else { await _prefs?.setString('aliyun_ak_id', id); }
    if (secret.isEmpty) { await _prefs?.remove('aliyun_ak_secret'); }
    else { await _prefs?.setString('aliyun_ak_secret', secret); }
    if (appKey.isEmpty) { await _prefs?.remove('aliyun_app_key'); }
    else { await _prefs?.setString('aliyun_app_key', appKey); }
  }
  
  // --- Work Mode ---
  // 'offline' | 'smart' | 'cloud'
  String get workMode => _prefs?.getString('work_mode') ?? _inferWorkMode();

  Future<void> setWorkMode(String mode) async {
    await _prefs?.setString('work_mode', mode);
    switch (mode) {
      case 'offline':
        await setAsrEngineType('sherpa');
        await setAiCorrectionEnabled(false);
      case 'smart':
        await setAsrEngineType('sherpa');
        await setAiCorrectionEnabled(true);
      case 'cloud':
        await setAsrEngineType('aliyun');
        await setAiCorrectionEnabled(false);
    }
  }

  /// Backward compat: infer workMode from legacy config
  String _inferWorkMode() {
    if (asrEngineType == 'aliyun') return 'cloud';
    if (aiCorrectionEnabled) return 'smart';
    return 'offline';
  }

  /// One-time migration: persist inferred workMode
  Future<void> migrateToWorkMode() async {
    if (_prefs?.containsKey('work_mode') ?? false) return;
    await _prefs?.setString('work_mode', _inferWorkMode());
  }

  // --- Engine Type ---
  String get asrEngineType => _prefs?.getString('asr_engine_type') ?? 'sherpa';

  Future<void> setAsrEngineType(String type) async {
    await _prefs?.setString('asr_engine_type', type);
  }

  // --- AI Correction Config ---
  bool get aiCorrectionEnabled => _prefs?.getBool('ai_correct_enabled') ?? AppConstants.kDefaultAiCorrectionEnabled;
  String get aiCorrectionPrompt => _getStringWithDefault('ai_correct_prompt', AppConstants.kDefaultAiCorrectionPrompt);
  String get llmBaseUrl => _getStringWithDefault('llm_base_url', AppConstants.kDefaultLlmBaseUrl);
  String get llmApiKey {
    final cached = _cachedLlmApiKey;
    if (cached != null && cached.trim().isNotEmpty) return cached;
    return AppConstants.kDefaultLlmApiKey;
  }
  String get llmModel => _getStringWithDefault('llm_model', AppConstants.kDefaultLlmModel);

  // Helper: Return default if pref is null OR empty
  String _getStringWithDefault(String key, String defaultValue) {
    if (_prefs == null) return defaultValue;
    final val = _prefs!.getString(key);
    if (val == null || val.trim().isEmpty) {
      return defaultValue;
    }
    return val;
  }

  Future<void> setAiCorrectionEnabled(bool enabled) async => await _prefs?.setBool('ai_correct_enabled', enabled);
  Future<void> setAiCorrectionPrompt(String prompt) async => await _prefs?.setString('ai_correct_prompt', prompt);
  Future<void> setLlmBaseUrl(String url) async => await _prefs?.setString('llm_base_url', url);
  Future<void> setLlmApiKey(String key) async {
    _cachedLlmApiKey = key.isEmpty ? null : key;
    if (key.isEmpty) { await _prefs?.remove('llm_api_key'); }
    else { await _prefs?.setString('llm_api_key', key); }
  }
  Future<void> setLlmModel(String model) async => await _prefs?.setString('llm_model', model);

  // --- Input/Output Language ---
  // inputLanguage: 'auto' | 'zh' | 'en' | 'ja' | 'ko' | 'yue'
  String get inputLanguage => _prefs?.getString('input_language') ?? 'auto';
  Future<void> setInputLanguage(String lang) async => await _prefs?.setString('input_language', lang);

  // outputLanguage: 'auto' | 'zh-Hans' | 'zh-Hant' | 'en' | 'ja' | 'ko'
  String get outputLanguage => _prefs?.getString('output_language') ?? 'auto';
  Future<void> setOutputLanguage(String lang) async => await _prefs?.setString('output_language', lang);

  // Deprecated: outputScript — migrated to outputLanguage
  String get outputScript => _prefs?.getString('output_script') ?? 'auto';
  Future<void> setOutputScript(String script) async => await _prefs?.setString('output_script', script);

  // --- LLM Provider Type ---
  String get llmProviderType => _prefs?.getString('llm_provider_type') ?? AppConstants.kDefaultLlmProviderType;
  Future<void> setLlmProviderType(String type) async => await _prefs?.setString('llm_provider_type', type);

  // --- LLM Preset ---
  String get llmPresetId => _prefs?.getString('llm_preset_id') ?? 'dashscope';
  Future<void> setLlmPresetId(String id) async => await _prefs?.setString('llm_preset_id', id);

  /// Save current LLM config (apiKey, baseUrl, model) under a preset ID
  Future<void> savePresetConfig(String presetId) async {
    final key = llmApiKey;
    final url = _prefs?.getString('llm_base_url') ?? '';
    final model = _prefs?.getString('llm_model') ?? '';
    if (key.isNotEmpty) {
      await _prefs?.setString('llm_preset_${presetId}_api_key', key);
    }
    if (url.isNotEmpty) await _prefs?.setString('llm_preset_${presetId}_base_url', url);
    if (model.isNotEmpty) await _prefs?.setString('llm_preset_${presetId}_model', model);
  }

  /// Load saved config for a preset ID; returns true if config was found
  Future<bool> loadPresetConfig(String presetId) async {
    final savedKey = _prefs?.getString('llm_preset_${presetId}_api_key');
    final savedUrl = _prefs?.getString('llm_preset_${presetId}_base_url');
    final savedModel = _prefs?.getString('llm_preset_${presetId}_model');
    if (savedKey == null && savedUrl == null && savedModel == null) return false;
    if (savedKey != null && savedKey.isNotEmpty) await setLlmApiKey(savedKey);
    if (savedUrl != null && savedUrl.isNotEmpty) await setLlmBaseUrl(savedUrl);
    if (savedModel != null && savedModel.isNotEmpty) await setLlmModel(savedModel);
    return true;
  }

  /// Check if a preset has saved config
  bool hasPresetConfig(String presetId) {
    return _prefs?.getString('llm_preset_${presetId}_base_url') != null ||
           _prefs?.getString('llm_preset_${presetId}_model') != null;
  }

  // --- Ollama Config ---
  String get ollamaBaseUrl => _getStringWithDefault('ollama_base_url', AppConstants.kDefaultOllamaBaseUrl);
  String get ollamaModel => _getStringWithDefault('ollama_model', AppConstants.kDefaultOllamaModel);
  Future<void> setOllamaBaseUrl(String url) async => await _prefs?.setString('ollama_base_url', url);
  Future<void> setOllamaModel(String model) async => await _prefs?.setString('ollama_model', model);

  // Verbose logging (debug mode) — default false, never committed as true
  bool get verboseLogging => _prefs?.getBool('verbose_logging') ?? AppConstants.kVerboseLogging;
  Future<void> setVerboseLogging(bool enabled) async => await _prefs?.setBool('verbose_logging', enabled);

  // Log file directory — defaults to ~/Downloads
  String get logDirectory => _prefs?.getString('log_directory') ?? '';
  Future<void> setLogDirectory(String dir) async => await _prefs?.setString('log_directory', dir);

  String? get llmBaseUrlOverride => _prefs?.getString('llm_base_url');
  String? get llmApiKeyOverride => _cachedLlmApiKey;
  String? get llmModelOverride => _prefs?.getString('llm_model');

  // --- Cloud Account Selection ---
  String? get selectedAsrAccountId => _prefs?.getString('selected_asr_account_id');
  String? get selectedAsrModelId => _prefs?.getString('selected_asr_model_id');
  String? get selectedLlmAccountId => _prefs?.getString('selected_llm_account_id');

  Future<void> setSelectedAsrAccount(String? accountId, {String? modelId}) async {
    if (accountId == null) {
      await _prefs?.remove('selected_asr_account_id');
      await _prefs?.remove('selected_asr_model_id');
    } else {
      await _prefs?.setString('selected_asr_account_id', accountId);
      if (modelId != null) await _prefs?.setString('selected_asr_model_id', modelId);
    }
  }

  Future<void> setSelectedLlmAccountId(String? accountId) async {
    if (accountId == null) {
      await _prefs?.remove('selected_llm_account_id');
    } else {
      await _prefs?.setString('selected_llm_account_id', accountId);
    }
  }

  // --- Agent Router Config ---
  String get agentRouterModel => _getStringWithDefault('agent_router_model', llmModel);
  Future<void> setAgentRouterModel(String model) async => await _prefs?.setString('agent_router_model', model);

  // --- I18n ---
  String get appLanguage => _prefs?.getString('app_language') ?? 'system';

  // --- Device ID (for billing) ---
  String? get deviceId => _prefs?.getString('billing_device_id');
  Future<void> setDeviceId(String id) async => await _prefs?.setString('billing_device_id', id);
  
  Future<void> setAppLanguage(String lang) async {
    await _prefs?.setString('app_language', lang);
    _updateLocaleNotifier();
  }

  /// Load credential values from Keychain into memory cache.
  /// Load credential values from SharedPreferences into memory cache.
  /// TODO: 拿到苹果开发者账号后迁移到 Keychain。
  void _preloadSecureKeys() {
    if (_prefs == null) return;
    _cachedAliyunAkId = _prefs!.getString('aliyun_ak_id');
    _cachedAliyunAkSecret = _prefs!.getString('aliyun_ak_secret');
    _cachedAliyunAppKey = _prefs!.getString('aliyun_app_key');
    _cachedLlmApiKey = _prefs!.getString('llm_api_key');
  }

  void _updateLocaleNotifier() {
    final lang = appLanguage;
    if (lang == 'en') {
      localeNotifier.value = const Locale('en');
    } else if (lang == 'zh') {
      localeNotifier.value = const Locale('zh');
    } else {
      localeNotifier.value = null; // System
    }
  }

  // --- Vocab Enhancement ---
  bool get vocabEnabled => _prefs?.getBool('vocab_enabled') ?? false;
  Future<void> setVocabEnabled(bool v) async => await _prefs?.setBool('vocab_enabled', v);

  bool get vocabTechEnabled => _prefs?.getBool('vocab_tech') ?? false;
  bool get vocabMedicalEnabled => _prefs?.getBool('vocab_medical') ?? false;
  bool get vocabLegalEnabled => _prefs?.getBool('vocab_legal') ?? false;
  bool get vocabFinanceEnabled => _prefs?.getBool('vocab_finance') ?? false;
  bool get vocabEducationEnabled => _prefs?.getBool('vocab_education') ?? false;

  Future<void> setVocabTechEnabled(bool v) async => await _prefs?.setBool('vocab_tech', v);
  Future<void> setVocabMedicalEnabled(bool v) async => await _prefs?.setBool('vocab_medical', v);
  Future<void> setVocabLegalEnabled(bool v) async => await _prefs?.setBool('vocab_legal', v);
  Future<void> setVocabFinanceEnabled(bool v) async => await _prefs?.setBool('vocab_finance', v);
  Future<void> setVocabEducationEnabled(bool v) async => await _prefs?.setBool('vocab_education', v);

  bool get vocabUserEnabled => _prefs?.getBool('vocab_user') ?? true;
  Future<void> setVocabUserEnabled(bool v) async => await _prefs?.setBool('vocab_user', v);

  String get vocabUserEntriesJson => _prefs?.getString('vocab_user_entries') ?? '[]';
  Future<void> setVocabUserEntriesJson(String json) async => await _prefs?.setString('vocab_user_entries', json);

  // --- Typewriter Effect (Alpha) ---
  bool get typewriterEnabled => _prefs?.getBool('typewriter_enabled') ?? false;
  Future<void> setTypewriterEnabled(bool v) async => await _prefs?.setBool('typewriter_enabled', v);

  // --- First Launch / Onboarding ---
  static const String _kOnboardingCompleted = 'onboarding_completed';
  
  /// Returns true if this is the first time the app is launched
  /// (onboarding has not been completed)
  bool get isFirstLaunch => !(_prefs?.getBool(_kOnboardingCompleted) ?? false);
  
  /// Mark onboarding as completed
  Future<void> completeOnboarding() async {
    await _prefs?.setBool(_kOnboardingCompleted, true);
  }
  
  /// Reset onboarding status (for testing)
  Future<void> resetOnboarding() async {
    await _prefs?.remove(_kOnboardingCompleted);
  }
}
