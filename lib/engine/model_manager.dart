import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:speakout/config/app_constants.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/config/distribution.dart';

/// 模型架构分类，用于确定 Phase 2 置信度支持能力
enum ModelArch {
  transducerStreaming, // 流式 Transducer（Zipformer 双语）
  transducerOffline,  // 离线 Transducer（未来新增）— C API 可读 ys_log_probs
  ctcStreaming,        // 流式 CTC（Paraformer 双语）
  ctcOffline,         // 离线 CTC（Paraformer/SenseVoice/FireRedASR）
  whisperLike,        // Encoder-Decoder（Whisper）
}

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final String type; // 'zipformer', 'paraformer', 'sense_voice', 'offline_paraformer', 'whisper', 'fire_red_asr', 'funasr_nano', 'fire_red_asr_ctc', 'moonshine', 'telespeech_ctc', 'dolphin'
  final String lang;
  final bool isOffline; // true = non-streaming (batch recognition after recording)
  final bool hasPunctuation; // true = model outputs punctuation, no need for punctuation model
  final ModelArch arch; // 模型架构分类

  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.type,
    required this.lang,
    this.isOffline = false,
    this.hasPunctuation = false,
    this.arch = ModelArch.ctcOffline,
  });

  /// 是否支持 per-token 置信度（当前仅未来离线 Transducer 模型支持）
  bool get supportsConfidence => arch == ModelArch.transducerOffline;

  /// 检查模型是否支持指定输入语言
  bool supportsLanguage(String langCode) {
    if (langCode == 'auto') return true;
    if (lang == 'multilingual') return true;
    // lang format: "zh-en", "zh-en-ja-ko-yue", "zh-en-dialect"
    final supported = lang.split('-').toSet();
    return supported.contains(langCode);
  }

  /// 返回模型支持的语言列表（用于 UI 展示）
  List<String> get supportedLanguages {
    if (lang == 'multilingual') return ['zh', 'en', 'ja', 'ko', 'yue'];
    return lang.split('-').where((l) => l != 'dialect').toList();
  }
}

class ModelManager {
  static const List<ModelInfo> availableModels = [
    // Paraformer streaming (good quality, no repetition issues)
    ModelInfo(
      id: "paraformer_bi_zh_en",
      name: "Paraformer Bilingual (Streaming)",
      description: "High accuracy Zh/En streaming model with lookahead. Download: ~1GB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2",
      type: "paraformer",
      lang: "zh-en",
      arch: ModelArch.ctcStreaming,
    ),
    // Zipformer hidden: severe repetition issues (Transducer architecture)
    // Kept in code for existing users who already downloaded it
  ];

  /// 已隐藏但需保留定义的模型（已下载的用户仍可使用）
  static const List<ModelInfo> _hiddenModels = [
    ModelInfo(
      id: "zipformer_bi_2023_02_20",
      name: "Zipformer Bilingual (Not Recommended)",
      description: "Zh/En streaming, severe repetition issues. ~490MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2",
      type: "zipformer",
      lang: "zh-en",
      arch: ModelArch.transducerStreaming,
    ),
    ModelInfo(
      id: "telespeech_ctc_int8",
      name: "TeleSpeech CTC (Not Recommended)",
      description: "China Telecom, extremely poor Chinese quality. ~175MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-telespeech-ctc-int8-zh-2024-06-04.tar.bz2",
      type: "telespeech_ctc",
      lang: "zh-dialect",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "funasr_nano_int8",
      name: "FunASR Nano (SDK Incompatible)",
      description: "Requires newer sherpa-onnx native library. ~716MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2",
      type: "funasr_nano",
      lang: "zh-en-ja-dialect",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "moonshine_base_zh",
      name: "Moonshine Base 中文 (SDK Incompatible)",
      description: "Decodes but returns empty. ~95MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-base-zh-quantized-2026-02-27.tar.bz2",
      type: "moonshine",
      lang: "zh",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "whisper_large_v3",
      name: "Whisper Large-v3 (Not Recommended)",
      description: "Very slow, poor Chinese. ~1.0GB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-large-v3.tar.bz2",
      type: "whisper",
      lang: "multilingual",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.whisperLike,
    ),
    ModelInfo(
      id: "whisper_distil_large_v3_5",
      name: "Whisper Distil (Not Recommended)",
      description: "Translates Chinese to English instead of transcribing. ~504MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-distil-large-v3.5.tar.bz2",
      type: "whisper",
      lang: "multilingual",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.whisperLike,
    ),
    ModelInfo(
      id: "whisper_medium_aishell",
      name: "Whisper Medium AISHELL (Not Recommended)",
      description: "Poor Chinese quality despite fine-tuning. ~655MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium-aishell.tar.bz2",
      type: "whisper",
      lang: "zh",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.whisperLike,
    ),
    ModelInfo(
      id: "fire_red_asr_large",
      name: "FireRedASR v1 (Superseded by v2)",
      description: "Use v2 CTC instead. ~1.4GB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr-large-zh_en-2025-02-16.tar.bz2",
      type: "fire_red_asr",
      lang: "zh-en-dialect",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
  ];

  static const List<ModelInfo> offlineModels = [
    // ⭐⭐⭐ 推荐
    ModelInfo(
      id: "sensevoice_zh_en_int8",
      name: "SenseVoice 2024 (Recommended)",
      description: "Alibaba DAMO, Zh/En/Ja/Ko/Yue, built-in punctuation. ~228MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
      type: "sense_voice",
      lang: "zh-en-ja-ko-yue",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "offline_paraformer_zh",
      name: "Paraformer Offline",
      description: "Zh/En, fastest decoding (70x realtime). ~217MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2",
      type: "offline_paraformer",
      lang: "zh-en",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "fire_red_asr2_ctc_int8",
      name: "FireRedASR v2 CTC",
      description: "XiaoHongShu, Zh/En + dialects, CTC architecture. ~496MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2",
      type: "fire_red_asr_ctc",
      lang: "zh-en-dialect",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "sensevoice_funasr_nano_int8",
      name: "SenseVoice + FunASR Nano",
      description: "SenseVoice encoder + Nano decoder, compact. ~179MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17.tar.bz2",
      type: "sense_voice",
      lang: "zh-en-ja",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    // ⭐⭐ 可用
    ModelInfo(
      id: "sensevoice_zh_en_int8_2025",
      name: "SenseVoice 2025",
      description: "Cantonese enhanced (21.8k hrs), no built-in punctuation. ~158MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2",
      type: "sense_voice",
      lang: "zh-en-ja-ko-yue",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "offline_paraformer_dialect_2025",
      name: "Paraformer Dialect 2025",
      description: "Zh/En + Sichuan/Chongqing dialects. ~218MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2",
      type: "offline_paraformer",
      lang: "zh-en-dialect",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
    ModelInfo(
      id: "whisper_turbo",
      name: "Whisper Turbo",
      description: "OpenAI, 99 languages, built-in punctuation. ~538MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-turbo.tar.bz2",
      type: "whisper",
      lang: "multilingual",
      isOffline: true,
      hasPunctuation: true,
      arch: ModelArch.whisperLike,
    ),
    ModelInfo(
      id: "dolphin_base_int8",
      name: "Dolphin Base",
      description: "DataOcean AI, ultra-light multilingual CTC. ~77MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-dolphin-base-ctc-multi-lang-int8-2025-04-02.tar.bz2",
      type: "dolphin",
      lang: "multilingual",
      isOffline: true,
      arch: ModelArch.ctcOffline,
    ),
  ];

  static List<ModelInfo> get allModels => [...availableModels, ...offlineModels, ..._hiddenModels];

  // Punctuation model for adding punctuation to ASR output
  static const punctuationModelUrl = 
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2";
  static const punctuationModelId = "punct_ct_transformer_zh_en";
  
  ModelInfo? getModelById(String id) {
    try {
      return allModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<ModelInfo?> getActiveModelInfo() async {
    final prefs = await SharedPreferences.getInstance();
    String activeId = prefs.getString('active_model_id') ?? AppConstants.kDefaultModelId;
    try {
      return allModels.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return null;
    }
  }

  /// 返回模型根目录: ~/Library/Application Support/com.speakout.speakout/Models/
  Future<Directory> _getModelsRoot() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return Directory('${appSupportDir.path}/Models');
  }

  Future<String?> getActiveModelPath() async {
    final modelsRoot = await _getModelsRoot();
    final prefs = await SharedPreferences.getInstance();

    // Default to bilingual if not set
    String activeId = prefs.getString('active_model_id') ?? AppConstants.kDefaultModelId;

    // Check if valid
    ModelInfo? model;
    try {
      model = allModels.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return null;
    }

    final modelRoot = Directory('${modelsRoot.path}/${_getDirNameFromUrl(model.url)}');

    // 1. Direct check
    if (await _hasTokensFile(modelRoot.path)) return modelRoot.path;

    // 2. Recursive check (one level deep)
    if (await modelRoot.exists()) {
      try {
        final entities = modelRoot.listSync();
        for (var entity in entities) {
          if (entity is Directory) {
             if (await _hasTokensFile(entity.path)) return entity.path;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> setActiveModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_model_id', id);
  }

  /// 检查目录下是否有 tokens 文件 (tokens.txt / *-tokens.txt / tokenizer.json)
  Future<bool> _hasTokensFile(String dirPath) async {
    if (await File('$dirPath/tokens.txt').exists()) return true;
    if (await File('$dirPath/tokenizer.json').exists()) return true;
    try {
      final entries = Directory(dirPath).listSync(recursive: true);
      return entries.any((e) => e is File &&
          (e.path.endsWith('tokens.txt') || e.path.endsWith('tokenizer.json')));
    } catch (_) {
      return false;
    }
  }

  String _getDirNameFromUrl(String url) {
    // extract filename without extensions. 
    // e.g. .../foo.tar.bz2 -> foo
    final filename = url.split('/').last;
    if (filename.endsWith('.tar.bz2')) {
      return filename.substring(0, filename.length - 8);
    }
    return filename;
  }

  Future<bool> isModelDownloaded(String id) async {
    final model = allModels.where((m) => m.id == id).firstOrNull;
    if (model == null) return false;
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(model.url);
    final finalModelDir = Directory('${modelsRoot.path}/$dirName');

    if (!await finalModelDir.exists()) return false;
    return _hasTokensFile(finalModelDir.path);
  }
  
  Future<String> downloadAndExtractModel(String id, {Function(String)? onStatus, Function(double)? onProgress}) async {
    final model = allModels.firstWhere((m) => m.id == id);
    final modelsRoot = await _getModelsRoot();
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }

    final tarPath = '${modelsRoot.path}/temp_${model.id}.tar.bz2';
    final file = File(tarPath);

    // Download with resume and retry
    if (onStatus != null) onStatus("正在下载 ${model.name}...");

    await _downloadWithResume(
      url: model.url,
      destFile: file,
      onProgress: onProgress,
      onStatus: onStatus,
      modelName: model.name,
    );

    return _extractAndInstallModel(id, file, onStatus: onStatus, onProgress: onProgress);
  }

  /// 手动导入模型：从用户选择的 .tar.bz2 文件导入
  Future<String> importModel(String id, String sourcePath, {Function(String)? onStatus, Function(double)? onProgress}) async {
    final modelsRoot = await _getModelsRoot();
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception("文件不存在: $sourcePath");
    }

    // Copy to Models directory to avoid sandbox permission issues
    onStatus?.call("复制文件...");
    final model = allModels.firstWhere((m) => m.id == id);
    final tarPath = '${modelsRoot.path}/temp_${model.id}.tar.bz2';
    final destFile = File(tarPath);
    await sourceFile.copy(destFile.path);

    return _extractAndInstallModel(id, destFile, onStatus: onStatus, onProgress: onProgress);
  }

  /// 共用解压+验证+激活逻辑
  Future<String> _extractAndInstallModel(String id, File tarFile, {Function(String)? onStatus, Function(double)? onProgress}) async {
    final model = allModels.firstWhere((m) => m.id == id);
    final modelsRoot = await _getModelsRoot();
    final tarPath = tarFile.path;

    // Extract to a unique temp directory to handle unknown internal folder names
    final tempExtractDir = Directory('${modelsRoot.path}/temp_extract_${model.id}');
    if (await tempExtractDir.exists()) await tempExtractDir.delete(recursive: true);
    await tempExtractDir.create(recursive: true);

    onStatus?.call("正在解压...");
    if (onProgress != null) onProgress(-1);

    try {
      await compute(_extractModelTask, [tarPath, tempExtractDir.path]);

      // Normalize: Find where the content is and move to final 'dirName'
      final dirName = _getDirNameFromUrl(model.url); // Standard name
      final finalModelDir = Directory('${modelsRoot.path}/$dirName');
      if (await finalModelDir.exists()) await finalModelDir.delete(recursive: true);

      // Analyze tempExtractDir content
      // Find anchor file: tokens.txt / *-tokens.txt / tokenizer.json (FunASR Nano)
      File? anchorFile;
      final anchorPatterns = ['*tokens.txt', 'tokenizer.json'];

      if (Platform.isMacOS || Platform.isLinux) {
         for (final pattern in anchorPatterns) {
           if (anchorFile != null) break;
           try {
             final result = await Process.run('find', [tempExtractDir.path, '-name', pattern]);
             if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
                final lines = result.stdout.toString().trim().split('\n');
                if (lines.isNotEmpty) {
                   anchorFile = File(lines.first.trim());
                   AppLog.d("[Verification] Native find success: ${anchorFile.path}");
                }
             }
           } catch (e) {
             AppLog.d("[Verification] Native find failed: $e");
           }
         }
      }

      // Fallback to Dart search
      if (anchorFile == null) {
          final entities = tempExtractDir.listSync(recursive: true);
          AppLog.d("[Extraction] Entities: ${entities.length}");
          for (var e in entities) {
            if (e.path.endsWith('tokens.txt') || e.path.endsWith('tokenizer.json')) {
               anchorFile = File(e.path);
               break;
            }
          }

          if (anchorFile == null) {
             final fileList = entities.map((e) => e.path.split(Platform.pathSeparator).last).take(10).join(', ');
             throw Exception("Invalid Model: tokens.txt/tokenizer.json not found. Found: $fileList...");
          }
      }

      // Determine model root: anchor file's parent, but if that dir has no .onnx files,
      // go up one level (e.g. FunASR Nano: tokenizer.json is in Qwen3-0.6B/ subdirectory)
      var sourceDir = anchorFile.parent;
      final hasOnnx = sourceDir.listSync().any((e) => e is File && e.path.endsWith('.onnx'));
      if (!hasOnnx && sourceDir.parent.path != tempExtractDir.path) {
        // Check parent for onnx files
        final parentHasOnnx = sourceDir.parent.listSync().any((e) => e is File && e.path.endsWith('.onnx'));
        if (parentHasOnnx) {
          AppLog.d("[Extraction] Anchor was in subdirectory, using parent as model root");
          sourceDir = sourceDir.parent;
        }
      }
      AppLog.d("[Extraction] Found tokens in: ${sourceDir.path}");
      AppLog.d("[Extraction] Moving/Renaming to: ${finalModelDir.path}");

      // Move sourceDir to finalModelDir
      if (sourceDir.absolute.path == tempExtractDir.absolute.path) {
         await tempExtractDir.rename(finalModelDir.path);
      } else {
         await sourceDir.rename(finalModelDir.path);
      }

      // Cleanup residue
      if (await tempExtractDir.exists()) await tempExtractDir.delete(recursive: true);

      // Delete tarball
      if (await tarFile.exists()) await tarFile.delete();

    } catch (e) {
      // Cleanup temp
      if (await tempExtractDir.exists()) await tempExtractDir.delete(recursive: true);
      throw Exception("解压/整理失败: $e");
    }

    // Set as active
    await setActiveModel(id);

    // Return path
    final dirName = _getDirNameFromUrl(model.url);

    // Verify
    if (!await isModelDownloaded(id)) {
       // Debug verification failure
       final finalPath = '${modelsRoot.path}/$dirName';
       AppLog.d("[Extraction] Verification Failed!");
       AppLog.d("[Extraction] Expected path: $finalPath");
       if (await Directory(finalPath).exists()) {
          AppLog.d("[Extraction] Final Dir Contents: ${Directory(finalPath).listSync()}");
       } else {
          AppLog.d("[Extraction] Final Dir DOES NOT EXIST!");
       }
       throw Exception("校验失败: 最终路径无有效模型文件");
    }

    return '${modelsRoot.path}/$dirName';
  }
  
  /// 支持断点续传和重试的下载方法
  Future<void> _downloadWithResume({
    required String url,
    required File destFile,
    Function(double)? onProgress,
    Function(String)? onStatus,
    String? modelName,
    int maxRetries = 5,
  }) async {
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        // Check existing file size for resume
        int existingBytes = 0;
        try {
          if (await destFile.exists()) {
            existingBytes = await destFile.length();
          }
        } catch (e) {
          AppLog.d("Warning: Failed to get file length, restarting download: $e");
          existingBytes = 0;
          try { if (await destFile.exists()) await destFile.delete(); } catch (_) {}
        }
        
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(url));
        
        // Add headers
        request.headers['User-Agent'] = 'SpeakOut/1.0 (Dart/Flutter)';
        
        // Add Range header for resume
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
          onStatus?.call("续传中... (已下载 ${(existingBytes / 1024 / 1024).toStringAsFixed(1)}MB)");
        }
        
        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            client.close();
            throw Exception("连接超时");
          },
        );
        
        // Check response
        if (streamedResponse.statusCode == 416) {
           // Range not satisfiable. Could mean fully downloaded OR corrupted.
           client.close();
           
           // Get actual server file size via fresh request
           try {
             final headResponse = await http.head(Uri.parse(url));
             final serverSize = int.tryParse(headResponse.headers['content-length'] ?? '');
             final localSize = await destFile.exists() ? await destFile.length() : 0;
             
             if (serverSize != null && localSize == serverSize) {
                AppLog.d("[Download] 416 Received. File verified complete ($localSize bytes). Success.");
                return; // Actually complete
             } else {
                AppLog.d("[Download] 416 but size mismatch (Local: $localSize, Server: $serverSize). Restarting.");
                if (await destFile.exists()) await destFile.delete();
                throw Exception("文件不完整 ($localSize / $serverSize bytes)，重新下载...");
             }
           } catch (headError) {
              AppLog.d("[Download] 416 and HEAD request failed: $headError. Restarting.");
              if (await destFile.exists()) await destFile.delete();
              throw Exception("文件状态异常，重新下载...");
           }
        }
        
        if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
          client.close();
          throw Exception("服务器错误: ${streamedResponse.statusCode}");
        }
        
        // Get total content length
        int totalBytes;
        if (streamedResponse.statusCode == 206) {
          // Partial content - parse Content-Range header
          // Format: bytes START-END/TOTAL
          final contentRange = streamedResponse.headers['content-range'];
          if (contentRange != null && contentRange.contains('/')) {
            totalBytes = int.parse(contentRange.split('/').last);
            
            // CRITICAL: Verify server is starting from the byte we requested
            final rangeMatch = RegExp(r'bytes\s+(\d+)-').firstMatch(contentRange);
            if (rangeMatch != null) {
              final serverStartByte = int.parse(rangeMatch.group(1)!);
              if (serverStartByte != existingBytes) {
                // Server is sending from a different position! Data would be corrupted.
                client.close();
                AppLog.d("[Download] Range mismatch! Requested byte $existingBytes, server sending from $serverStartByte. Restarting.");
                if (await destFile.exists()) await destFile.delete();
                throw Exception("服务器响应位置不匹配，重新下载...");
              }
              AppLog.d("[Download] Range verified: starting from byte $serverStartByte");
            }
          } else {
            totalBytes = existingBytes + (streamedResponse.contentLength ?? 0);
          }
        } else {
          // Full download
          if (existingBytes > 0) {
             AppLog.d("[Download] Server returned 200 (Full), ignoring Range. Restarting...");
             onStatus?.call("服务器不支持续传，重新下载...");
          }
          totalBytes = streamedResponse.contentLength ?? 0;
          existingBytes = 0; // Reset
          if (await destFile.exists()) await destFile.delete();
        }
        
        // Open file for append or write
        final sink = destFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);
        int downloadedBytes = existingBytes;
        double lastReportedProgress = existingBytes / (totalBytes > 0 ? totalBytes : 1);

        try {
          // Add inactivity timeout: if no data received for 30s, treat as stalled
          await for (final chunk in streamedResponse.stream.timeout(
            const Duration(seconds: 30),
            onTimeout: (sink) {
              sink.addError(Exception("数据传输超时 (30s 无数据)"));
              sink.close();
            },
          )) {
            sink.add(chunk);
            downloadedBytes += chunk.length;

            if (totalBytes > 0 && onProgress != null) {
              final currentProgress = downloadedBytes / totalBytes;
              if (currentProgress - lastReportedProgress >= 0.01 || currentProgress >= 1.0) {
                onProgress(currentProgress);
                lastReportedProgress = currentProgress;
              }
            }
          }
        } finally {
          await sink.close();
          client.close();
        }
        
        // Verify download completed
        final finalSize = await destFile.length();
        if (totalBytes > 0 && finalSize < totalBytes) {
          throw Exception("下载不完整: $finalSize / $totalBytes bytes");
        }
        
        return; // Success!
        
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          throw Exception("下载失败 (已重试 $maxRetries 次): $e");
        }
        
        onStatus?.call("下载中断，正在重试 ($retryCount/$maxRetries)...");
        await Future.delayed(Duration(seconds: retryCount * 2)); // Exponential backoff
      }
    }
  }

  Future<void> deleteModel(String id) async {
     final model = allModels.where((m) => m.id == id).firstOrNull;
     if (model == null) return;
     final modelsRoot = await _getModelsRoot();
     final dirName = _getDirNameFromUrl(model.url);
     final modelDir = Directory('${modelsRoot.path}/$dirName');
     if (await modelDir.exists()) {
       await modelDir.delete(recursive: true);
     }
  }
  
  // ============ Punctuation Model Methods ============
  
  Future<bool> isPunctuationModelDownloaded() async {
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelDir = Directory('${modelsRoot.path}/$dirName');
    
    if (!await modelDir.exists()) return false;
    // Check for model.onnx file
    return await File('${modelDir.path}/$dirName/model.onnx').exists();
  }
  
  Future<String?> getPunctuationModelPath() async {
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelRoot = Directory('${modelsRoot.path}/$dirName');
    
    // Generic find model.onnx
    AppLog.d("[Diagnose] Punctuation Root: ${modelRoot.path} (Exists: ${await modelRoot.exists()})");
    
    if (!await modelRoot.exists()) return null;

    // Robust search: Look for 'model.onnx' in root or 1-level deep
    try {
      if (await File('${modelRoot.path}/model.onnx').exists()) {
        AppLog.d("[Diagnose] Found model.onnx at root: ${modelRoot.path}/model.onnx");
        return modelRoot.path;
      }
      
      final entities = modelRoot.listSync();
      AppLog.d("[Diagnose] Root entities: ${entities.map((e) => e.path).toList()}");
      
      for (var entity in entities) {
        if (entity is Directory) {
           if (await File('${entity.path}/model.onnx').exists()) {
             AppLog.d("[Diagnose] Found model.onnx in subfolder: ${entity.path}");
             return entity.path;
           }
        }
      }
    } catch (e) {
      AppLog.d("Warning: Error finding punctuation model: $e");
    }
    
    return null;
  }
  
  Future<String> downloadPunctuationModel({Function(String)? onStatus, Function(double)? onProgress}) async {
    final modelsRoot = await _getModelsRoot();
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }
    
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final destDir = '${modelsRoot.path}/$dirName';
    final tarPath = '${modelsRoot.path}/$dirName.tar.bz2';
    final tarFile = File(tarPath);
    
    // Download with resume and retry
    onStatus?.call("正在下载标点模型...");
    
    await _downloadWithResume(
      url: punctuationModelUrl,
      destFile: tarFile,
      onProgress: onProgress,
      onStatus: onStatus,
      modelName: "标点模型",
    );
    
    // Extract
    onStatus?.call("正在解压...");
    await compute(_extractModelTask, [tarPath, destDir]);
    
    // Cleanup
    if (await tarFile.exists()) await tarFile.delete();
    onStatus?.call("完成");
    
    return destDir;
  }
  
  Future<void> deletePunctuationModel() async {
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelDir = Directory('${modelsRoot.path}/$dirName');
    
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }
}

// Top-level function for isolate
Future<void> _extractModelTask(List<String> args) async {
  final tarPath = args[0];
  final destDir = args[1];
  
  // 1. Try Native Tar (MacOS/Linux) - Much faster and memory efficient
  // 1. Try Native Tar (MacOS/Linux) - Much faster and memory efficient
  // App Store 沙盒下 Process.run 会抛异常，自动走 Dart 回退
  if (Platform.isMacOS || Platform.isLinux) {
     try {
       await Directory(destDir).create(recursive: true);
       // -x: extract, -f: file. bzip2 is usually auto-detected or we can use -j
       // -C: change dir
       final result = await Process.run('tar', ['-xf', tarPath, '-C', destDir]);
       
       if (result.exitCode == 0) {
          AppLog.d("Native extraction successful.");
          // Fix permissions: Ensure we can read/write everything (some archives have read-only dirs)
          await Process.run('chmod', ['-R', '755', destDir]);
          return;
       }
       AppLog.d("Native tar failed (Code ${result.exitCode}): ${result.stderr}. Falling back...");
     } catch (e) {
       AppLog.d("Native tar exception: $e. Falling back...");
     }
  }

  // 2. Fallback: Dart Streaming Archive (memory efficient)
  // extractFileToDisk uses InputFileStream internally — no full file load into RAM
  await Directory(destDir).create(recursive: true);
  extractFileToDisk(tarPath, destDir);
}
