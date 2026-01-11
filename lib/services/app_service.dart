import 'dart:io';
import '../engine/core_engine.dart';
import 'notification_service.dart';
import 'metering_service.dart';
import 'config_service.dart';
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
    // 1. Config
    await ConfigService().init();
    
    // 2. Engine (Set KeyCode)
    engine.pttKeyCode = ConfigService().pttKeyCode;
    await engine.init(); // START LISTENER (Crucial Fix)
    
    // 3. Initialize ASR (Essential for Sherpa bindings)
    await _initASR();
    
    // 4. Punctuation (Auto) - After ASR
    await _initPunctuation();
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
      // 检查标点模型
      bool hasModel = await modelManager.isPunctuationModelDownloaded();
      if (!hasModel) {
        print("Auto-downloading Punctuation Model...");
        await modelManager.downloadPunctuationModel(
          onProgress: (progress) {
             if (progress >= 1.0) print("Punctuation Downloaded.");
          }
        );
      }
      
      String? modelPath = await modelManager.getPunctuationModelPath();
      if (modelPath != null) {
        // Use core engine to init
        final activeInfo = await modelManager.getActiveModelInfo();
        final activeName = activeInfo?.name ?? '';
        await engine.initPunctuation(modelPath, activeModelName: activeName);
        _isPunctuationInitialized = true;
        // 5. Init Metering (Usage Reporting)
        MeteringService().init();
      }
    } catch (e) {
      print("AppService: Punctuation init failed: $e. Attempting self-heal.");
      // If init failed, the model file is likely corrupted or incompatible.
      // Delete it so it re-downloads on next launch.
      await modelManager.deletePunctuationModel();
    }
  }
}
