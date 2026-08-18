import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:speakout/config/app_constants.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/config/app_log.dart';

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
    String activeId = ConfigService().activeModelId;
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

  /// 随包内置模型的目录（打包脚本在 codesign 前注入到 app bundle 的 Resources 下）。
  ///
  /// 路径推算：`.../SpeakOut.app/Contents/MacOS/SpeakOut` → `.../Contents/Resources/models/<dir>`
  /// 开发期 `flutter run` 下不存在，一切自动回退到原有的下载流程。
  /// 仅 macOS 有此机制。
  /// 缓存探测结果 —— bundle 内容在进程生命周期内不会变，
  /// 而模型列表 UI 会对每个模型反复调用（每次都 existsSync 是浪费）。
  static final Map<String, String?> _bundledDirCache = {};

  String? bundledModelDir(String modelId) {
    if (!Platform.isMacOS) return null;
    if (_bundledDirCache.containsKey(modelId)) return _bundledDirCache[modelId];
    final model = allModels.where((m) => m.id == modelId).firstOrNull;
    if (model == null) return null;
    String? result;
    try {
      final contents = File(Platform.resolvedExecutable).parent.parent.path;
      final dir = Directory('$contents/Resources/models/${_getDirNameFromUrl(model.url)}');
      result = _findValidModelDir(model, dir.path);
    } catch (_) {
      result = null;
    }
    _bundledDirCache[modelId] = result;
    return result;
  }

  /// 该模型是否随包内置（内置即视为已就绪，无需下载）
  bool isModelBundled(String modelId) => bundledModelDir(modelId) != null;

  /// 用户目录里是否存在该模型的本地副本（下载或导入而来）。
  /// 与 isModelBundled 区分：内置＋有副本时删除按钮应当保留（删副本、回落内置），
  /// 只有「纯内置」才该隐藏删除，否则等于剥夺了用户删除自己下载内容的能力。
  Future<bool> hasLocalCopy(String modelId) async {
    final model = allModels.where((m) => m.id == modelId).firstOrNull;
    if (model == null) return false;
    final modelsRoot = await _getModelsRoot();
    final dir = Directory('${modelsRoot.path}/${_getDirNameFromUrl(model.url)}');
    await _recoverInterruptedInstall(
      dir,
      (path) => _findValidModelDir(model, path) != null,
    );
    return _findValidModelDir(model, dir.path) != null;
  }

  /// 找出「随包内置、同时又在用户目录留了一份下载副本」的冗余占用。
  ///
  /// 老用户升级到内置版本后，之前下载的那份就纯属冗余（同一 URL、同一目录、同一内容），
  /// 但不会自动删 —— 删用户数据目录得由用户自己点。返回总字节数与目录列表。
  Future<(int, List<Directory>)> findRedundantBundledCopies() async {
    final dirs = <Directory>[];
    int total = 0;
    final modelsRoot = await _getModelsRoot();
    if (!await modelsRoot.exists()) return (0, dirs);
    for (final m in allModels) {
      if (bundledModelDir(m.id) == null) continue; // 没内置就谈不上冗余
      final dup = Directory('${modelsRoot.path}/${_getDirNameFromUrl(m.url)}');
      if (!await dup.exists()) continue;
      int size = 0;
      try {
        await for (final e in dup.list(recursive: true, followLinks: false)) {
          if (e is File) size += await e.length();
        }
      } catch (_) {}
      dirs.add(dup);
      total += size;
    }
    return (total, dirs);
  }

  /// 删除上面找出的冗余副本。内置那份在 app bundle 内，不受影响。
  /// 返回**实际释放**的字节数（不是检测到的总量）——
  /// 删除可能因权限/占用失败，返回 total 会让 UI 谎报「已释放 229MB」。
  Future<int> cleanupRedundantBundledCopies() async {
    final (_, dirs) = await findRedundantBundledCopies();
    int freed = 0;
    for (final d in dirs) {
      int size = 0;
      try {
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File) size += await e.length();
        }
        await d.delete(recursive: true);
        freed += size; // 只在删除确实成功后计入
        AppLog.d('[Model] 已清理冗余副本: ${d.path}');
      } catch (e) {
        AppLog.d('[Model] 清理失败 ${d.path}: $e');
      }
    }
    return freed;
  }

  Future<String?> getActiveModelPath() async {
    final modelsRoot = await _getModelsRoot();

    // Default to bilingual if not set
    String activeId = ConfigService().activeModelId;

    // Check if valid
    ModelInfo? model;
    try {
      model = allModels.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return null;
    }

    final modelRoot = Directory('${modelsRoot.path}/${_getDirNameFromUrl(model.url)}');

    await _recoverInterruptedInstall(
      modelRoot,
      (path) => _findValidModelDir(model!, path) != null,
    );

    final local = _findValidModelDir(model, modelRoot.path);
    if (local != null) return local;

    // 3. 兜底：随包内置的模型。
    //    放最后而非最前 —— 用户主动下载/导入的副本必须优先，
    //    否则「导入」按钮对内置模型完全失效（导入了却仍在用 bundle 里那份）。
    final bundled = bundledModelDir(activeId);
    if (bundled != null) return bundled;

    return null;
  }

  Future<void> setActiveModel(String id) async {
    await ConfigService().setActiveModelId(id);
  }

  bool _isNonEmptyFile(File file) {
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  bool _isModelFile(File file) {
    final name = file.path.toLowerCase();
    return _isNonEmptyFile(file) &&
        (name.endsWith('.onnx') || name.endsWith('.ort'));
  }

  bool _hasFile(List<File> files, String pattern) =>
      files.any((file) =>
          _isModelFile(file) &&
          file.path.split(Platform.pathSeparator).last.contains(pattern));

  bool _hasExactFile(List<File> files, String name) =>
      files.any((file) =>
          _isNonEmptyFile(file) &&
          file.path.split(Platform.pathSeparator).last == name);

  bool _hasTokenFile(List<File> files) => files.any((file) {
        final name = file.path.split(Platform.pathSeparator).last;
        return name.endsWith('tokens.txt') && _isNonEmptyFile(file);
      });

  /// 按 Provider 真正加载的文件组合判断模型是否可用。
  /// 只看 tokens 会让「可解压但缺权重」的包覆盖掉现有模型。
  bool _isValidModelDir(ModelInfo model, String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return false;
      final files = dir.listSync(followLinks: false).whereType<File>().toList();

      if (model.type == 'funasr_nano') {
        final hasTokenizer = dir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .any((file) =>
                file.path.split(Platform.pathSeparator).last ==
                    'tokenizer.json' &&
                _isNonEmptyFile(file));
        return hasTokenizer &&
            _hasFile(files, 'encoder_adaptor') &&
            _hasFile(files, 'llm') &&
            _hasFile(files, 'embedding');
      }

      final hasTokens = model.type == 'whisper' || model.type == 'moonshine'
          ? _hasTokenFile(files)
          : _isNonEmptyFile(File('$dirPath/tokens.txt'));
      if (!hasTokens) return false;

      switch (model.type) {
        case 'paraformer':
          return _hasExactFile(files, 'encoder.int8.onnx') &&
              _hasExactFile(files, 'decoder.int8.onnx');
        case 'zipformer':
          return _hasFile(files, 'encoder') &&
              _hasFile(files, 'decoder') &&
              _hasFile(files, 'joiner');
        case 'sense_voice':
        case 'offline_paraformer':
          return _hasExactFile(files, 'model.int8.onnx');
        case 'whisper':
        case 'fire_red_asr':
          return _hasFile(files, 'encoder') && _hasFile(files, 'decoder');
        case 'fire_red_asr_ctc':
        case 'telespeech_ctc':
        case 'dolphin':
          return _hasFile(files, 'model');
        case 'moonshine':
          final hasMerged = _hasFile(files, 'encoder_model') &&
              _hasFile(files, 'decoder_model_merged');
          final hasSplit = _hasFile(files, 'preprocess') &&
              _hasFile(files, 'encoder') &&
              _hasFile(files, 'uncached') &&
              files.any((file) {
                final name = file.path.split(Platform.pathSeparator).last;
                return _isModelFile(file) &&
                    name.contains('cached') &&
                    !name.contains('uncached');
              });
          return hasMerged || hasSplit;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// 正常安装会把模型文件收敛在根目录；兼容旧版本遗留的一层 wrapper。
  String? _findValidModelDir(ModelInfo model, String rootPath) {
    if (_isValidModelDir(model, rootPath)) return rootPath;
    try {
      final root = Directory(rootPath);
      if (!root.existsSync()) return null;
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory && _isValidModelDir(model, entity.path)) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

  Directory? _findExtractedModelDir(ModelInfo model, Directory extractedRoot) {
    try {
      final candidates = <Directory>[extractedRoot];
      candidates.addAll(extractedRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>());
      candidates.sort((a, b) => b.path.length.compareTo(a.path.length));
      return candidates
          .where((dir) => _isValidModelDir(model, dir.path))
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverInterruptedInstall(
    Directory finalDir,
    bool Function(String path) isValid,
  ) async {
    final backupDir = Directory('${finalDir.path}.old');
    if (!await backupDir.exists()) return;

    if (await finalDir.exists() && isValid(finalDir.path)) {
      try {
        await backupDir.delete(recursive: true);
      } catch (e) {
        AppLog.d('[Model] 无法清理安装备份 ${backupDir.path}: $e');
      }
      return;
    }

    if (!isValid(backupDir.path)) {
      AppLog.d('[Model] 安装备份无效，保留现场: ${backupDir.path}');
      return;
    }

    if (await finalDir.exists()) await finalDir.delete(recursive: true);
    await backupDir.rename(finalDir.path);
    AppLog.d('[Model] 已恢复中断安装留下的备份: ${finalDir.path}');
  }

  Future<void> _replaceDirectoryAtomically({
    required Directory sourceDir,
    required Directory finalDir,
    required bool Function(String path) isValid,
  }) async {
    if (!isValid(sourceDir.path)) throw Exception('模型文件不完整');

    await _recoverInterruptedInstall(finalDir, isValid);
    final backupDir = Directory('${finalDir.path}.old');
    if (await backupDir.exists()) {
      throw Exception('发现无法自动恢复的安装备份: ${backupDir.path}');
    }

    if (await finalDir.exists()) await finalDir.rename(backupDir.path);

    try {
      await sourceDir.rename(finalDir.path);
      if (!isValid(finalDir.path)) throw Exception('安装后模型校验失败');
    } catch (_) {
      if (await finalDir.exists()) await finalDir.delete(recursive: true);
      if (await backupDir.exists()) await backupDir.rename(finalDir.path);
      rethrow;
    }

    if (await backupDir.exists()) {
      try {
        await backupDir.delete(recursive: true);
      } catch (e) {
        AppLog.d('[Model] 新模型已安装，但旧备份清理失败: $e');
      }
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

    await _recoverInterruptedInstall(
      finalModelDir,
      (path) => _findValidModelDir(model, path) != null,
    );
    if (_findValidModelDir(model, finalModelDir.path) != null) return true;
    return isModelBundled(id);
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

    // Staging 与正式目录隔离；校验通过前绝不触碰现有模型。
    final tempExtractDir = Directory('${modelsRoot.path}/temp_extract_${model.id}');
    if (await tempExtractDir.exists()) {
      await tempExtractDir.delete(recursive: true);
    }
    await tempExtractDir.create(recursive: true);

    onStatus?.call("正在解压...");
    if (onProgress != null) onProgress(-1);

    try {
      await compute(_extractModelTask, [tarPath, tempExtractDir.path]);

      final dirName = _getDirNameFromUrl(model.url); // Standard name
      final finalModelDir = Directory('${modelsRoot.path}/$dirName');
      final sourceDir = _findExtractedModelDir(model, tempExtractDir);
      if (sourceDir == null) {
        throw Exception('Invalid Model: 缺少 ${model.type} 所需的完整模型文件');
      }

      await _replaceDirectoryAtomically(
        sourceDir: sourceDir,
        finalDir: finalModelDir,
        isValid: (path) => _isValidModelDir(model, path),
      );
    } catch (e) {
      throw Exception("解压/整理失败: $e");
    } finally {
      try {
        if (await tempExtractDir.exists()) {
          await tempExtractDir.delete(recursive: true);
        }
      } catch (e) {
        AppLog.d('[Model] 临时解压目录清理失败: $e');
      }
      try {
        if (await tarFile.exists()) await tarFile.delete();
      } catch (e) {
        AppLog.d('[Model] 临时压缩包清理失败: $e');
      }
    }

    // Set as active
    await setActiveModel(id);

    // Return path
    final dirName = _getDirNameFromUrl(model.url);

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
        // 父目录可能在下载途中消失（测试超时后 tearDown 会删临时目录，而下载 Future
        // 无法被取消，仍会继续写）。这里补建一次，避免 PathNotFoundException 冒泡
        // 击穿 stream sink，把整个测试框架拖崩、造成后续用例级联失败。
        await destFile.parent.create(recursive: true);
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
     final backupDir = Directory('${modelDir.path}.old');
     if (await backupDir.exists()) {
       await backupDir.delete(recursive: true);
     }
     // 若删除的是当前 active 模型，切到另一个已下载模型，避免 active_model_id 悬空
     // （否则下次启动 getActiveModelPath 返回 null，会静默重下默认模型，造成"为什么又下载"困惑）
     final activeId = ConfigService().activeModelId;
     if (activeId == id) {
       String? next;
       for (final m in allModels) {
         if (m.id == id) continue;
         if (await isModelDownloaded(m.id)) { next = m.id; break; }
       }
       // 有其他已下载模型则切过去；否则回退默认 id（启动逻辑再决定是否下载）
       await ConfigService().setActiveModelId(next ?? AppConstants.kDefaultModelId);
     }
  }
  
  // ============ Punctuation Model Methods ============
  
  Future<bool> isPunctuationModelDownloaded() async {
    return await getPunctuationModelPath() != null;
  }

  String? _findPunctuationModelPath(String rootPath) {
    try {
      final root = Directory(rootPath);
      if (!root.existsSync()) return null;
      final direct = File('${root.path}/model.onnx');
      if (_isNonEmptyFile(direct)) return root.path;
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory &&
            _isNonEmptyFile(File('${entity.path}/model.onnx'))) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }
  
  Future<String?> getPunctuationModelPath() async {
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelRoot = Directory('${modelsRoot.path}/$dirName');
    
    // Generic find model.onnx
    AppLog.d("[Diagnose] Punctuation Root: ${modelRoot.path} (Exists: ${await modelRoot.exists()})");
    
    await _recoverInterruptedInstall(
      modelRoot,
      (path) => _findPunctuationModelPath(path) != null,
    );
    return _findPunctuationModelPath(modelRoot.path);
  }
  
  Future<String> downloadPunctuationModel({Function(String)? onStatus, Function(double)? onProgress}) async {
    final modelsRoot = await _getModelsRoot();
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }
    
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final finalDir = Directory('${modelsRoot.path}/$dirName');
    final tempExtractDir = Directory('${modelsRoot.path}/temp_extract_punctuation');
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
    
    if (await tempExtractDir.exists()) {
      await tempExtractDir.delete(recursive: true);
    }
    await tempExtractDir.create(recursive: true);

    try {
      onStatus?.call("正在解压...");
      await compute(_extractModelTask, [tarPath, tempExtractDir.path]);
      final sourcePath = _findPunctuationModelPath(tempExtractDir.path);
      if (sourcePath == null) throw Exception('标点模型缺少 model.onnx');
      await _replaceDirectoryAtomically(
        sourceDir: Directory(sourcePath),
        finalDir: finalDir,
        isValid: (path) => _findPunctuationModelPath(path) != null,
      );
      onStatus?.call("完成");
      return finalDir.path;
    } finally {
      try {
        if (await tempExtractDir.exists()) {
          await tempExtractDir.delete(recursive: true);
        }
      } catch (e) {
        AppLog.d('[Model] 标点临时目录清理失败: $e');
      }
      try {
        if (await tarFile.exists()) await tarFile.delete();
      } catch (e) {
        AppLog.d('[Model] 标点临时压缩包清理失败: $e');
      }
    }
  }
  
  Future<void> deletePunctuationModel() async {
    final modelsRoot = await _getModelsRoot();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelDir = Directory('${modelsRoot.path}/$dirName');
    
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    final backupDir = Directory('${modelDir.path}.old');
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
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

  // 2. Fallback: Dart Archive — 全流式，不将整个文件加载到内存
  // extractFileToDisk 内部: InputFileStream → BZip2/GZip decodeStream → temp.tar
  //   → TarDecoder.decodeStream → OutputFileStream 逐文件写入 → 清理 temp
  await Directory(destDir).create(recursive: true);
  await extractFileToDisk(tarPath, destDir);
}
