import 'dart:io';
import '../engine/core_engine.dart';
import 'notification_service.dart';
import 'config_service.dart';
import 'chat_service.dart';
import '../engine/model_manager.dart';

/// 管理应用程序生命周期与核心业务逻辑
/// Central Hub for initialization and logic.
class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  AppService._internal();

  final CoreEngine engine = CoreEngine();
  final ModelManager modelManager = ModelManager();
  
  bool _isPunctuationInitialized = false;

  /// 初始化应用核心服务
  Future<void> init() async {
    engine.updateStatus("正在配置服务...");
    await Future.delayed(const Duration(milliseconds: 50));
    // 1. Config
    await ConfigService().init();
    
    // 1.5 Other Services
    await ChatService().init();
    
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
  }
  
  Future<void> _initASR() async {
    try {
      // Check active model
      String? path = await modelManager.getActiveModelPath();
      
      // If no model, download default
      if (path == null) {
        print("AppService: Downloading default model...");
        try {
          final defaultId = ModelManager.availableModels.first.id;
          // We can't easily show progress in UI here unless we expose stream.
          // For now, blocking wait or rely on engine status updates if hooked.
          path = await modelManager.downloadAndExtractModel(defaultId);
          // Update Config
           await ConfigService().setActiveModelId(defaultId);
        } catch (e) {
          print("AppService: Default download failed: $e");
        }
      }
      
      if (path != null) {
         final info = await modelManager.getActiveModelInfo();
         final type = info?.type ?? 'zipformer'; 
         final name = info?.name ?? 'Local Model';
         await engine.initASR(path, modelType: type, modelName: name);
      }
    } catch (e) {
       print("AppService: ASR Init Error: $e");
    }
  }

  /// ASR Init Wrapper
  Future<void> initASR({required String modelPath, String? type, String? modelName}) async {
    await engine.initASR(modelPath, modelType: type ?? 'zipformer', modelName: modelName ?? 'Local Model');
  }

  Future<void> _initPunctuation() async {
    if (_isPunctuationInitialized) return;
    
    try {
      // 检查标点模型 - 不再自动下载，由 Onboarding 或 Settings 页面处理
      bool hasModel = await modelManager.isPunctuationModelDownloaded();
      if (!hasModel) {
        print("Punctuation model not found. User can download from Settings.");
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
      print("AppService: Punctuation init failed: $e. Attempting self-heal.");
      // If init failed, the model file is likely corrupted or incompatible.
      // Delete it so it re-downloads on next launch.
      await modelManager.deletePunctuationModel();
    }
  }
}
