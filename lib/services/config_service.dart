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

  // In-memory cache for credential values (avoid repeated pref reads on hot path)
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
    await _preloadSecureKeys();

    _initialized = true;
    _initCompleter!.complete();
  }

  // --- Hotkey ---

  int get pttKeyCode => _prefs?.getInt(AppConstants.kKeyPttKeyCode) ?? AppConstants.kDefaultPttKeyCode;
  
  String get pttKeyName => _prefs?.getString(AppConstants.kKeyPttKeyName) ?? AppConstants.kDefaultPttKeyName;

  Future<void> setPttKey(int code, String name) async {
    await _prefs?.setInt(AppConstants.kKeyPttKeyCode, code);
    await _prefs?.setString(AppConstants.kKeyPttKeyName, name);
  }

  // --- Diary (Flash Note) ---
  bool get diaryEnabled => _prefs?.getBool('diary_enabled') ?? false;
  int get diaryKeyCode => _prefs?.getInt('diary_key_code') ?? 61; // Default Right Option
  String get diaryKeyName => _prefs?.getString('diary_key_name') ?? "Right Option";
  String get diaryDirectory => _prefs?.getString('diary_directory') ?? _defaultDocPath;

  Future<void> setDiaryEnabled(bool enabled) async => await _prefs?.setBool('diary_enabled', enabled);
  Future<void> setDiaryKey(int code, String name) async {
    await _prefs?.setInt('diary_key_code', code);
    await _prefs?.setString('diary_key_name', name);
  }
  Future<void> setDiaryDirectory(String path) async => await _prefs?.setString('diary_directory', path);

  // --- Toggle Input (Text Injection) ---
  bool get toggleInputEnabled => toggleInputKeyCode != 0;
  int get toggleInputKeyCode => _prefs?.getInt('toggle_input_key_code') ?? AppConstants.kDefaultToggleInputKeyCode;
  String get toggleInputKeyName => _prefs?.getString('toggle_input_key_name') ?? AppConstants.kDefaultToggleInputKeyName;
  Future<void> setToggleInputKey(int code, String name) async {
    await _prefs?.setInt('toggle_input_key_code', code);
    await _prefs?.setString('toggle_input_key_name', name);
  }
  Future<void> clearToggleInputKey() async {
    await _prefs?.remove('toggle_input_key_code');
    await _prefs?.remove('toggle_input_key_name');
  }

  // --- Toggle Diary (Flash Note) ---
  bool get toggleDiaryEnabled => toggleDiaryKeyCode != 0;
  int get toggleDiaryKeyCode => _prefs?.getInt('toggle_diary_key_code') ?? AppConstants.kDefaultToggleDiaryKeyCode;
  String get toggleDiaryKeyName => _prefs?.getString('toggle_diary_key_name') ?? AppConstants.kDefaultToggleDiaryKeyName;
  Future<void> setToggleDiaryKey(int code, String name) async {
    await _prefs?.setInt('toggle_diary_key_code', code);
    await _prefs?.setString('toggle_diary_key_name', name);
  }
  Future<void> clearToggleDiaryKey() async {
    await _prefs?.remove('toggle_diary_key_code');
    await _prefs?.remove('toggle_diary_key_name');
  }

  // --- Toggle Shared Config ---
  int get toggleMaxDuration => _prefs?.getInt('toggle_max_duration') ?? AppConstants.kDefaultToggleMaxDuration;
  Future<void> setToggleMaxDuration(int seconds) async => await _prefs?.setInt('toggle_max_duration', seconds);

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
  
  // --- Aliyun Config (Keychain-backed) ---
  String get aliyunAccessKeyId => _cachedAliyunAkId ?? AppConstants.kDefaultAliyunAkId;
  String get aliyunAccessKeySecret => _cachedAliyunAkSecret ?? AppConstants.kDefaultAliyunAkSecret;
  String get aliyunAppKey => _cachedAliyunAppKey ?? AppConstants.kDefaultAliyunAppKey;

  Future<void> setAliyunCredentials(String id, String secret, String appKey) async {
    if (id.isEmpty) {
      await _prefs?.remove('aliyun_ak_id');
      _cachedAliyunAkId = null;
    } else {
      await _prefs?.setString('aliyun_ak_id', id);
      _cachedAliyunAkId = id;
    }
    if (secret.isEmpty) {
      await _prefs?.remove('aliyun_ak_secret');
      _cachedAliyunAkSecret = null;
    } else {
      await _prefs?.setString('aliyun_ak_secret', secret);
      _cachedAliyunAkSecret = secret;
    }
    if (appKey.isEmpty) {
      await _prefs?.remove('aliyun_app_key');
      _cachedAliyunAppKey = null;
    } else {
      await _prefs?.setString('aliyun_app_key', appKey);
      _cachedAliyunAppKey = appKey;
    }
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
    if (key.isEmpty) {
      await _prefs?.remove('llm_api_key');
      _cachedLlmApiKey = null;
    } else {
      await _prefs?.setString('llm_api_key', key);
      _cachedLlmApiKey = key;
    }
  }
  Future<void> setLlmModel(String model) async => await _prefs?.setString('llm_model', model);

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

  // --- ASR De-duplication Config ---
  bool get deduplicationEnabled => _prefs?.getBool('dedup_enabled') ?? AppConstants.kDefaultDeduplicationEnabled;
  Future<void> setDeduplicationEnabled(bool enabled) async => await _prefs?.setBool('dedup_enabled', enabled);

  // Verbose logging (debug mode) — default false, never committed as true
  bool get verboseLogging => _prefs?.getBool('verbose_logging') ?? AppConstants.kVerboseLogging;
  Future<void> setVerboseLogging(bool enabled) async => await _prefs?.setBool('verbose_logging', enabled);

  // Log file directory — defaults to ~/Downloads
  String get logDirectory => _prefs?.getString('log_directory') ?? '';
  Future<void> setLogDirectory(String dir) async => await _prefs?.setString('log_directory', dir);

  String? get llmBaseUrlOverride => _prefs?.getString('llm_base_url');
  String? get llmApiKeyOverride => _cachedLlmApiKey;
  String? get llmModelOverride => _prefs?.getString('llm_model');

  // --- Agent Router Config ---
  String get agentRouterModel => _getStringWithDefault('agent_router_model', llmModel);
  Future<void> setAgentRouterModel(String model) async => await _prefs?.setString('agent_router_model', model);

  // --- I18n ---
  String get appLanguage => _prefs?.getString('app_language') ?? 'system'; 
  
  Future<void> setAppLanguage(String lang) async {
    await _prefs?.setString('app_language', lang);
    _updateLocaleNotifier();
  }

  /// Load credential values from SharedPreferences into memory cache
  Future<void> _preloadSecureKeys() async {
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
