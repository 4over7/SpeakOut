import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final String type; // 'zipformer', 'whisper'
  final String lang;
  // File naming conventions can vary, so we might need hooks.
  // For simplicity, we assume standard Sherpa layouts or handle in CoreEngine.

  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.type,
    required this.lang,
  });
}

class ModelManager {
  static const List<ModelInfo> availableModels = [
    // Zipformer (Transducer)
    ModelInfo(
      id: "zipformer_bi_2023_02_20",
      name: "Zipformer Bilingual (Recommended)",
      description: "Balanced streaming model (Zh/En). ~85MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2",
      type: "zipformer",
      lang: "zh-en",
    ),
    ModelInfo(
      id: "paraformer_bi_zh_en",
      name: "Paraformer Bilingual (Streaming)",
      description: "High accuracy Zh/En streaming model with lookahead. ~230MB (Int8)",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2",
      type: "paraformer",
      lang: "zh-en",
    ),
  ];
  
  // Punctuation model for adding punctuation to ASR output
  static const punctuationModelUrl = 
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2";
  static const punctuationModelId = "punct_ct_transformer_zh_en";
  
  ModelInfo? getModelById(String id) {
    try {
      return availableModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<ModelInfo?> getActiveModelInfo() async {
    final prefs = await SharedPreferences.getInstance();
    String activeId = prefs.getString('active_model_id') ?? availableModels[0].id;
    try {
      return availableModels.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getActiveModelPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    
    // Default to bilingual if not set
    String activeId = prefs.getString('active_model_id') ?? availableModels[0].id;
    
    // Check if valid
    ModelInfo? model;
    try {
      model = availableModels.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return null;
    }

    final modelDir = Directory('${docDir.path}/speakout_models/${_getDirNameFromUrl(model.url)}');
    if (await isModelDownloaded(model.id)) {
      return modelDir.path;
    }
    return null;
  }

  Future<void> setActiveModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_model_id', id);
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
    final model = availableModels.firstWhere((m) => m.id == id);
    final docDir = await getApplicationDocumentsDirectory();
    final dirName = _getDirNameFromUrl(model.url);
    final modelDir = Directory('${docDir.path}/speakout_models/$dirName');
    
    if (!await modelDir.exists()) return false;
    // Simple check
    return await File('${modelDir.path}/tokens.txt').exists();
  }
  
  Future<String> downloadAndExtractModel(String id, {Function(String)? onStatus, Function(double)? onProgress}) async {
    final model = availableModels.firstWhere((m) => m.id == id);
    final docDir = await getApplicationDocumentsDirectory();
    final modelsRoot = Directory('${docDir.path}/speakout_models');
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }

    final tarPath = '${modelsRoot.path}/temp_${model.id}.tar.bz2';
    
    // Download with progress
    if (onStatus != null) onStatus("Downloading ${model.name}...");
    
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(model.url));
    final streamedResponse = await client.send(request);
    
    if (streamedResponse.statusCode == 200) {
      final contentLength = streamedResponse.contentLength ?? 0;
      final file = File(tarPath);
      final sink = file.openWrite();
      
      int received = 0;
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        
        if (contentLength > 0 && onProgress != null) {
          final progress = received / contentLength;
          onProgress(progress);
        }
        
        // Also update status with percentage if no progress callback
        if (contentLength > 0 && onStatus != null && onProgress == null) {
          final pct = (received / contentLength * 100).toStringAsFixed(0);
          onStatus("Downloading ${model.name}... $pct%");
        }
      }
      
      await sink.close();
      client.close();
      
      if (onStatus != null) onStatus("Extracting (background)...");
      if (onProgress != null) onProgress(-1); // Indicate extraction phase
      
      try {
        // Run extraction in isolate to avoid UI freeze
        await compute(_extractModelTask, [tarPath, modelsRoot.path]);
      } catch (e) {
        throw Exception("Extraction failed: $e");
      } finally {
        if (await file.exists()) await file.delete();
      }

      // Set as active
      await setActiveModel(id);
      
      // Return path
      final dirName = _getDirNameFromUrl(model.url);
      return '${modelsRoot.path}/$dirName';
    } else {
      client.close();
      throw Exception("Failed to download model status: ${streamedResponse.statusCode}");
    }
  }

  Future<void> deleteModel(String id) async {
     final model = availableModels.firstWhere((m) => m.id == id);
     final docDir = await getApplicationDocumentsDirectory();
     final dirName = _getDirNameFromUrl(model.url);
     final modelDir = Directory('${docDir.path}/speakout_models/$dirName');
     if (await modelDir.exists()) {
       await modelDir.delete(recursive: true);
     }
  }
  
  // ============ Punctuation Model Methods ============
  
  Future<bool> isPunctuationModelDownloaded() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelDir = Directory('${docDir.path}/speakout_models/$dirName');
    
    if (!await modelDir.exists()) return false;
    // Check for model.onnx file
    return await File('${modelDir.path}/$dirName/model.onnx').exists();
  }
  
  Future<String?> getPunctuationModelPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelRoot = Directory('${docDir.path}/speakout_models/$dirName');
    
    if (!await modelRoot.exists()) return null;

    // Robust search: Look for 'model.onnx' in root or 1-level deep
    try {
      if (await File('${modelRoot.path}/model.onnx').exists()) {
        return modelRoot.path;
      }
      
      final entities = modelRoot.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
           if (await File('${entity.path}/model.onnx').exists()) {
             return entity.path;
           }
        }
      }
    } catch (e) {
      print("Error finding punctuation model: $e");
    }
    
    return null;
  }
  
  Future<String> downloadPunctuationModel({Function(String)? onStatus, Function(double)? onProgress}) async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelsRoot = Directory('${docDir.path}/speakout_models');
    if (!await modelsRoot.exists()) {
      await modelsRoot.create(recursive: true);
    }
    
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final destDir = '${modelsRoot.path}/$dirName';
    final tarPath = '${modelsRoot.path}/$dirName.tar.bz2';
    
    // Download
    onStatus?.call("下载标点模型中...");
    final response = await http.Client().send(http.Request('GET', Uri.parse(punctuationModelUrl)));
    final totalBytes = response.contentLength ?? 0;
    final sink = File(tarPath).openWrite();
    int downloadedBytes = 0;
    
    await for (var chunk in response.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(downloadedBytes / totalBytes);
      }
    }
    await sink.close();
    
    // Extract
    onStatus?.call("解压中...");
    await compute(_extractModelTask, [tarPath, destDir]);
    
    // Cleanup
    await File(tarPath).delete();
    onStatus?.call("完成");
    
    return destDir;
  }
  
  Future<void> deletePunctuationModel() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dirName = _getDirNameFromUrl(punctuationModelUrl);
    final modelDir = Directory('${docDir.path}/speakout_models/$dirName');
    
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }
}

// Top-level function for isolate
Future<void> _extractModelTask(List<String> args) async {
  final tarPath = args[0];
  final destDir = args[1];
  final file = File(tarPath);
  
  // BZip2 + Tar
  final bytes = file.readAsBytesSync();
  final archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
  
  for (final item in archive) {
    if (item.isFile) {
      final filename = item.name;
      final p = '$destDir/$filename';
      File(p)
        ..createSync(recursive: true)
        ..writeAsBytesSync(item.content as List<int>);
    }
  }
}
