import 'dart:io';
import '../engine/core_engine.dart';
import '../ffi/native_input_base.dart';
// import 'billing_service.dart'; // 暂时隐藏
import 'config_service.dart';
import 'chat_service.dart';
import 'llm_service.dart';
import 'cloud_account_service.dart';
import 'notification_service.dart';
import 'update_service.dart';
import 'audio_device_service.dart';
import '../engine/model_manager.dart';
import '../config/app_constants.dart';
import 'package:speakout/config/app_log.dart';

/// 管理应用程序生命周期与核心业务逻辑
/// Central Hub for initialization and logic.
class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  AppService._internal();

  final CoreEngine engine = CoreEngine();
  final ModelManager modelManager = ModelManager();

  bool _isPunctuationInitialized = false;

  // ════════════════════════════════════════════════════════════
  // Engine facade — UI 层经此访问 engine 能力，避免直接 import lib/engine/
  // （三层架构：UI → Service → Engine。详见 lib/ui/AGENTS.md）
  // ════════════════════════════════════════════════════════════

  // ── Streams ──
  Stream<String> get statusStream => engine.statusStream;
  Stream<(int keyCode, int modifierFlags)> get rawKeyEventStream => engine.rawKeyEventStream;

  // ── Getters / setter ──
  NativeInputBase? get nativeInput => engine.nativeInput;
  AudioDeviceService? get audioDeviceService => engine.audioDeviceService;
  bool get isPunctuationEnabled => engine.isPunctuationEnabled;
  int get pttKeyCode => engine.pttKeyCode;
  set pttKeyCode(int v) => engine.pttKeyCode = v;
  void updateStatus(String msg) => engine.updateStatus(msg);
  static int ownModifierMask(int keyCode) => CoreEngine.ownModifierMask(keyCode);

  // ── 权限检查 ──
  bool checkInputMonitoringPermission() => engine.nativeInput?.checkInputMonitoringPermission() ?? false;
  bool checkAccessibilityPermission() => engine.nativeInput?.checkAccessibilityPermission() ?? false;
  bool checkMicrophonePermission() => engine.nativeInput?.checkMicrophonePermission() ?? false;

  // ── 标点初始化 ──
  Future<void> initPunctuation(String modelPath, {String activeModelName = ''}) =>
      engine.initPunctuation(modelPath, activeModelName: activeModelName);

  // ── 模型管理（转发 ModelManager）──
  static List<ModelInfo> get offlineModels => ModelManager.offlineModels;
  static List<ModelInfo> get availableModels => ModelManager.availableModels;
  static List<ModelInfo> get allModels => ModelManager.allModels;
  static String get punctuationModelId => ModelManager.punctuationModelId;
  ModelInfo? getModelById(String id) => modelManager.getModelById(id);
  Future<ModelInfo?> getActiveModelInfo() => modelManager.getActiveModelInfo();
  Future<String?> getActiveModelPath() => modelManager.getActiveModelPath();
  Future<void> setActiveModel(String id) => modelManager.setActiveModel(id);
  Future<bool> isModelDownloaded(String id) => modelManager.isModelDownloaded(id);
  /// 该模型是否随包内置（内置则无需下载，首启即可用）
  bool isModelBundled(String id) => modelManager.isModelBundled(id);
  Future<bool> hasLocalCopy(String id) => modelManager.hasLocalCopy(id);
  Future<(int, List<Directory>)> findRedundantBundledCopies() =>
      modelManager.findRedundantBundledCopies();
  Future<int> cleanupRedundantBundledCopies() =>
      modelManager.cleanupRedundantBundledCopies();
  Future<bool> isPunctuationModelDownloaded() => modelManager.isPunctuationModelDownloaded();
  Future<String?> getPunctuationModelPath() => modelManager.getPunctuationModelPath();
  Future<void> deleteModel(String id) => modelManager.deleteModel(id);
  Future<void> deletePunctuationModel() => modelManager.deletePunctuationModel();
  Future<String> downloadAndExtractModel(String id, {Function(String)? onStatus, Function(double)? onProgress}) =>
      modelManager.downloadAndExtractModel(id, onStatus: onStatus, onProgress: onProgress);
  Future<String> importModel(String id, String sourcePath, {Function(String)? onStatus, Function(double)? onProgress}) =>
      modelManager.importModel(id, sourcePath, onStatus: onStatus, onProgress: onProgress);
  Future<void> downloadPunctuationModel({Function(String)? onStatus, Function(double)? onProgress}) =>
      modelManager.downloadPunctuationModel(onStatus: onStatus, onProgress: onProgress);

  /// 释放所有资源，应用退出时调用
  Future<void> dispose() async {
    engine.dispose();
    await ChatService().dispose(); // 等待待写队列 flush，避免退出丢最后一条
    NotificationService().dispose();
    UpdateService().dispose();
    LLMService().dispose();
    await AppLog.dispose();
  }

  /// Apply verbose logging + log directory to AppLog and native C layer.
  /// Call this after ConfigService.init() and whenever settings change.
  Future<void> applyVerboseLogging() async {
    final enabled = ConfigService().verboseLogging;
    AppLog.enabled = enabled;
    AppLog.logSensitive = ConfigService().logSensitiveContent;
    final dir = ConfigService().logDirectory;
    if (dir.isNotEmpty) {
      AppLog.customLogDirectory = dir;
      engine.nativeInput?.setLogDirectory(dir);
    }
    if (enabled) {
      await AppLog.init();
    } else {
      // 关闭 verbose：释放文件 sink + flush timer，避免句柄/定时器泄漏到应用退出
      await AppLog.dispose();
    }
    engine.nativeInput?.setDebugLogging(enabled);
  }

  /// 初始化应用核心服务
  Future<void> init() async {
    engine.updateStatus("正在配置服务...");
    await Future.delayed(const Duration(milliseconds: 50));
    // 1. Config
    await ConfigService().init();
    await ConfigService().migrateToWorkMode();
    await ConfigService().migrateLlmModelOwner();
    await ConfigService().migrateSmartModeToToggle();
    await applyVerboseLogging(); // Apply debug logging as early as possible

    // 1.5 Other Services
    await ChatService().init();
    await CloudAccountService().init();
    await CloudAccountService().migrateFromLegacy();
    
    engine.updateStatus("正在启动键盘监听...");
    await Future.delayed(const Duration(milliseconds: 100));

    // 2. Engine (Set KeyCode)
    engine.pttKeyCode = ConfigService().pttKeyCode;
    try {
       await engine.init(); 
    } catch (e) {
       engine.updateStatus("❌ 键盘监听失败: $e");
       await Future.delayed(const Duration(seconds: 2));
    }
    
    // 3. Initialize ASR (HEAVY TASK - Delay significantly)
    // Skip if already initialized (e.g., by onboarding)
    if (engine.isASRReady) {
      engine.updateStatus("语音模型已就绪");
      await Future.delayed(const Duration(milliseconds: 200));
    } else {
      // Give the UI time to fully settle (1 second) before hitting the CPU hard
      engine.updateStatus("准备加载语音模型...");
      await Future.delayed(const Duration(milliseconds: 800));
      
      engine.updateStatus("正在加载语音模型...");
      await Future.delayed(const Duration(milliseconds: 50)); 
      try {
        await _initASR();
      } catch (e) {
        engine.updateStatus("❌ 语音模型失败: $e");
      }
    }
    
    // 4. Punctuation (also skip if already initialized)
    if (!_isPunctuationInitialized) {
      await _initPunctuation();
    }
    
    // Final Health Check
    if (engine.isListenerRunning) {
        engine.updateStatus("✅就绪");
        await Future.delayed(const Duration(milliseconds: 500));
        engine.updateStatus(""); // Clear
    } else {
        // Persistent Error - Do NOT Clear
        engine.updateStatus("❌ 监听启动失败 (请检查权限)");
    }

    // 5. Check for updates (non-blocking)
    UpdateService().checkForUpdate();

    // 6. Billing (暂时禁用，等支付宝/Stripe 开通后恢复)
    // BillingService().init();
  }
  
  Future<void> _initASR() async {
    try {
      // Check active model
      String? path = await modelManager.getActiveModelPath();
      
      // If no model, fall back to default
      if (path == null) {
        final defaultId = AppConstants.kDefaultModelId;
        // 默认模型随包内置时直接用 —— 否则 activeModelId 指向一个已被删除/失效的模型时，
        // 这里会去下载一份 bundle 里已经有的 229MB
        final bundledDefault = modelManager.bundledModelDir(defaultId);
        if (bundledDefault != null) {
          AppLog.d("AppService: 回退到随包内置的默认模型");
          path = bundledDefault;
          await ConfigService().setActiveModelId(defaultId);
        } else {
          AppLog.d("AppService: Downloading default model...");
          try {
            // We can't easily show progress in UI here unless we expose stream.
            // For now, blocking wait or rely on engine status updates if hooked.
            path = await modelManager.downloadAndExtractModel(defaultId);
            // Update Config
            await ConfigService().setActiveModelId(defaultId);
          } catch (e) {
            AppLog.d("AppService: Default download failed: $e");
          }
        }
      }
      
      if (path != null) {
         final info = await modelManager.getActiveModelInfo();
         final type = info?.type ?? 'zipformer'; 
         final name = info?.name ?? 'Local Model';
         final hasPunct = info?.hasPunctuation ?? false;
         await engine.initASR(path, modelType: type, modelName: name, hasPunctuation: hasPunct);
      }
    } catch (e) {
       AppLog.d("AppService: ASR Init Error: $e");
    }
  }

  /// ASR Init Wrapper
  Future<void> initASR({required String modelPath, String? type, String? modelName, bool hasPunctuation = false}) async {
    await engine.initASR(modelPath, modelType: type ?? 'zipformer', modelName: modelName ?? 'Local Model', hasPunctuation: hasPunctuation);
  }

  Future<void> _initPunctuation() async {
    if (_isPunctuationInitialized) return;
    
    try {
      // 检查标点模型 - 不再自动下载，由 Onboarding 或 Settings 页面处理
      bool hasModel = await modelManager.isPunctuationModelDownloaded();
      if (!hasModel) {
        AppLog.d("Punctuation model not found. User can download from Settings.");
        return; // Skip init if not downloaded
      }
      
      String? modelPath = await modelManager.getPunctuationModelPath();
      if (modelPath != null) {
        // Use core engine to init
        final activeInfo = await modelManager.getActiveModelInfo();
        final activeName = activeInfo?.name ?? '';
        await engine.initPunctuation(modelPath, activeModelName: activeName);
        _isPunctuationInitialized = true;
      }
    } catch (e) {
      AppLog.d("AppService: Punctuation init failed: $e. Attempting self-heal.");
      // If init failed, the model file is likely corrupted or incompatible.
      // Delete it so it re-downloads on next launch.
      await modelManager.deletePunctuationModel();
    }
  }
}
