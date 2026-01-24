import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
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
  static const String _kGatewayUrlKey = 'gateway_url';
  static const String _kTopUpUrlKey = 'top_up_url';
  
  // Safe field: Nullable prefs
  SharedPreferences? _prefs;
  bool _initialized = false;
  // Default doc path (fallback if not init)
  String _defaultDocPath = ""; 
  
  // Local Notifier for Language Change
  final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    
    // Get Safe Directory
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _defaultDocPath = "${docDir.path}/SpeakOut_Notes";
    } catch (e) {
      print("ConfigService: Failed to get doc dir: $e");
    }
    
    // Load Locale
    _updateLocaleNotifier();
    
    // Load Secrets
    try {
      final jsonStr = await rootBundle.loadString('assets/aliyun_config.json');
      final Map<String, dynamic> json = jsonDecode(jsonStr);
      
      AppConstants.kDefaultAliyunAppKey = json['aliyun_app_key'] ?? '';
      AppConstants.kDefaultAliyunAkId = json['aliyun_ak_id'] ?? '';
      AppConstants.kDefaultAliyunAkSecret = json['aliyun_ak_secret'] ?? '';
    } catch (e) {
      // _log("ConfigService: No aliyun_config.json found.");
    }
    
    // Load LLM Config
    try {
      final jsonStr = await rootBundle.loadString('assets/llm_config.json');
      final Map<String, dynamic> json = jsonDecode(jsonStr);
      
      // Update Defaults if present in file
      if (json['llm_base_url'] != null) AppConstants.kDefaultLlmBaseUrl = json['llm_base_url'];
      if (json['llm_api_key'] != null) AppConstants.kDefaultLlmApiKey = json['llm_api_key'];
      if (json['llm_model'] != null) AppConstants.kDefaultLlmModel = json['llm_model'];
      if (json['ai_correction_prompt'] != null) AppConstants.kDefaultAiCorrectionPrompt = json['ai_correction_prompt'];
    } catch (e) {
      // _log("ConfigService: No llm_config.json found.");
    }
    
    _initialized = true;
  }

  // --- License ---
  String get licenseKey => _prefs?.getString('license_key') ?? '';
  bool get isProUser => _prefs?.getBool('is_pro_user') ?? false;
  String get gatewayUrl => _prefs?.getString(_kGatewayUrlKey) ?? kDefaultGatewayUrl;
  set gatewayUrl(String val) => _prefs?.setString(_kGatewayUrlKey, val);

  String get topUpUrl => _prefs?.getString(_kTopUpUrlKey) ?? kDefaultTopUpUrl;
  set topUpUrl(String val) => _prefs?.setString(_kTopUpUrlKey, val);

  Future<void> setLicenseKey(String key) async => await _prefs?.setString('license_key', key);
  Future<void> setProStatus(bool isPro) async => await _prefs?.setBool('is_pro_user', isPro);

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
  
  // --- Aliyun Config ---
  String get aliyunAccessKeyId => _prefs?.getString('aliyun_ak_id') ?? AppConstants.kDefaultAliyunAkId;
  String get aliyunAccessKeySecret => _prefs?.getString('aliyun_ak_secret') ?? AppConstants.kDefaultAliyunAkSecret;
  String get aliyunAppKey => _prefs?.getString('aliyun_app_key') ?? AppConstants.kDefaultAliyunAppKey;
  
  Future<void> setAliyunCredentials(String id, String secret, String appKey) async {
    if (id.isEmpty) await _prefs?.remove('aliyun_ak_id'); 
    else await _prefs?.setString('aliyun_ak_id', id);
    
    if (secret.isEmpty) await _prefs?.remove('aliyun_ak_secret');
    else await _prefs?.setString('aliyun_ak_secret', secret);
    
    if (appKey.isEmpty) await _prefs?.remove('aliyun_app_key');
    else await _prefs?.setString('aliyun_app_key', appKey);
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
  String get llmApiKey => _getStringWithDefault('llm_api_key', AppConstants.kDefaultLlmApiKey);
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
  Future<void> setLlmApiKey(String key) async => await _prefs?.setString('llm_api_key', key);
  Future<void> setLlmModel(String model) async => await _prefs?.setString('llm_model', model);

  String? get llmBaseUrlOverride => _prefs?.getString('llm_base_url');
  String? get llmApiKeyOverride => _prefs?.getString('llm_api_key');
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

  void _updateLocaleNotifier() {
    final lang = appLanguage;
    if (lang == 'en') localeNotifier.value = const Locale('en');
    else if (lang == 'zh') localeNotifier.value = const Locale('zh');
    else localeNotifier.value = null; // System
  }
}
