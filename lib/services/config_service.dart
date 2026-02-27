import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_constants.dart';

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

  // Keychain storage for sensitive credentials
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions.defaultOptions,
    iOptions: IOSOptions.defaultOptions,
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked,
    ),
  );
  // In-memory cache for Keychain values (avoid async reads on hot path)
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
      debugPrint("ConfigService: Failed to get doc dir: $e");
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
      await _secureStorage.delete(key: 'aliyun_ak_id');
      _cachedAliyunAkId = null;
    } else {
      await _secureStorage.write(key: 'aliyun_ak_id', value: id);
      _cachedAliyunAkId = id;
    }
    if (secret.isEmpty) {
      await _secureStorage.delete(key: 'aliyun_ak_secret');
      _cachedAliyunAkSecret = null;
    } else {
      await _secureStorage.write(key: 'aliyun_ak_secret', value: secret);
      _cachedAliyunAkSecret = secret;
    }
    if (appKey.isEmpty) {
      await _secureStorage.delete(key: 'aliyun_app_key');
      _cachedAliyunAppKey = null;
    } else {
      await _secureStorage.write(key: 'aliyun_app_key', value: appKey);
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
      await _secureStorage.delete(key: 'llm_api_key');
      _cachedLlmApiKey = null;
    } else {
      await _secureStorage.write(key: 'llm_api_key', value: key);
      _cachedLlmApiKey = key;
    }
  }
  Future<void> setLlmModel(String model) async => await _prefs?.setString('llm_model', model);

  // --- LLM Provider Type ---
  String get llmProviderType => _prefs?.getString('llm_provider_type') ?? AppConstants.kDefaultLlmProviderType;
  Future<void> setLlmProviderType(String type) async => await _prefs?.setString('llm_provider_type', type);

  // --- Ollama Config ---
  String get ollamaBaseUrl => _getStringWithDefault('ollama_base_url', AppConstants.kDefaultOllamaBaseUrl);
  String get ollamaModel => _getStringWithDefault('ollama_model', AppConstants.kDefaultOllamaModel);
  Future<void> setOllamaBaseUrl(String url) async => await _prefs?.setString('ollama_base_url', url);
  Future<void> setOllamaModel(String model) async => await _prefs?.setString('ollama_model', model);

  // --- ASR De-duplication Config ---
  bool get deduplicationEnabled => _prefs?.getBool('dedup_enabled') ?? AppConstants.kDefaultDeduplicationEnabled;
  Future<void> setDeduplicationEnabled(bool enabled) async => await _prefs?.setBool('dedup_enabled', enabled);

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

  /// Keychain 键名与旧 SharedPreferences 键名的映射
  static const _secureKeys = ['aliyun_ak_id', 'aliyun_ak_secret', 'aliyun_app_key', 'llm_api_key'];

  Future<void> _preloadSecureKeys() async {
    // 尝试从 Keychain 读取，失败则回退 SharedPreferences（兼容旧版迁移 + 测试环境）
    bool keychainAvailable = true;
    try {
      _cachedAliyunAkId = await _secureStorage.read(key: 'aliyun_ak_id');
      _cachedAliyunAkSecret = await _secureStorage.read(key: 'aliyun_ak_secret');
      _cachedAliyunAppKey = await _secureStorage.read(key: 'aliyun_app_key');
      _cachedLlmApiKey = await _secureStorage.read(key: 'llm_api_key');
    } catch (e) {
      debugPrint("ConfigService: Keychain unavailable, falling back to SharedPreferences: $e");
      keychainAvailable = false;
    }

    // 从 SharedPreferences 迁移：如果 Keychain 中没有值但 prefs 有，写入 Keychain
    if (_prefs != null) {
      for (final key in _secureKeys) {
        final cached = _getCachedByKey(key);
        if (cached == null || cached.isEmpty) {
          final prefsVal = _prefs!.getString(key);
          if (prefsVal != null && prefsVal.isNotEmpty) {
            _setCachedByKey(key, prefsVal);
            if (keychainAvailable) {
              try {
                await _secureStorage.write(key: key, value: prefsVal);
                await _prefs!.remove(key); // 迁移后从 plist 删除明文
              } catch (_) {}
            }
          }
        }
      }
    }
  }

  String? _getCachedByKey(String key) {
    switch (key) {
      case 'aliyun_ak_id': return _cachedAliyunAkId;
      case 'aliyun_ak_secret': return _cachedAliyunAkSecret;
      case 'aliyun_app_key': return _cachedAliyunAppKey;
      case 'llm_api_key': return _cachedLlmApiKey;
      default: return null;
    }
  }

  void _setCachedByKey(String key, String value) {
    switch (key) {
      case 'aliyun_ak_id': _cachedAliyunAkId = value;
      case 'aliyun_ak_secret': _cachedAliyunAkSecret = value;
      case 'aliyun_app_key': _cachedAliyunAppKey = value;
      case 'llm_api_key': _cachedLlmApiKey = value;
    }
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
