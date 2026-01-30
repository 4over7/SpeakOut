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
      description: "Balanced streaming model (Zh/En). Download: ~490MB",
      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2",
      type: "zipformer",
      lang: "zh-en",
    ),
    ModelInfo(
      id: "paraformer_bi_zh_en",
      name: "Paraformer Bilingual (Streaming)",
      description: "High accuracy Zh/En streaming model with lookahead. Download: ~1GB",
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

    final modelRoot = Directory('${docDir.path}/speakout_models/${_getDirNameFromUrl(model.url)}');
    
    // 1. Direct check
    if (await File('${modelRoot.path}/tokens.txt').exists()) return modelRoot.path;
    
    // 2. Recursive check
    if (await modelRoot.exists()) {
      try {
        final entities = modelRoot.listSync();
        for (var entity in entities) {
          if (entity is Directory) {
             if (await File('${entity.path}/tokens.txt').exists()) return entity.path;
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
    final finalModelDir = Directory('${docDir.path}/speakout_models/$dirName');
    
    if (!await finalModelDir.exists()) return false;
    
    // Simple check (since we normalized the directory structure)
    // We expect tokens.txt to be in the root of the model dir now.
    return await File('${finalModelDir.path}/tokens.txt').exists();
  }
  
  Future<String> downloadAndExtractModel(String id, {Function(String)? onStatus, Function(double)? onProgress}) async {
    final model = availableModels.firstWhere((m) => m.id == id);
    final docDir = await getApplicationDocumentsDirectory();
    final modelsRoot = Directory('${docDir.path}/speakout_models');
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
    
    // Note: We previously had a bzip2 -t integrity check here, but it fails in App Sandbox.
    // Instead, we rely on the tar extraction itself as the integrity check.
    // If extraction fails, it means the file is corrupted.
    
    // Extract to a unique temp directory to handle unknown internal folder names
    final tempExtractDir = Directory('${modelsRoot.path}/temp_extract_${model.id}');
    if (await tempExtractDir.exists()) await tempExtractDir.delete(recursive: true);
    await tempExtractDir.create(recursive: true);

    if (onStatus != null) onStatus("正在解压...");
    if (onProgress != null) onProgress(-1); 
    
    try {
      await compute(_extractModelTask, [tarPath, tempExtractDir.path]);
      
      // Normalize: Find where the content is and move to final 'dirName'
      final dirName = _getDirNameFromUrl(model.url); // Standard name
      final finalModelDir = Directory('${modelsRoot.path}/$dirName');
      if (await finalModelDir.exists()) await finalModelDir.delete(recursive: true);
      
      // Analyze tempExtractDir content
      // 3. Verification using Native Find (Bypass Dart listSync issues)
      // tokens.txt is critical. We search for it natively.
      File? tokenFile;
      if (Platform.isMacOS || Platform.isLinux) {
         try {
           final result = await Process.run('find', [tempExtractDir.path, '-name', 'tokens.txt']);
           if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
              // Found!
              final lines = result.stdout.toString().trim().split('\n');
              if (lines.isNotEmpty) {
                 tokenFile = File(lines.first.trim());
                 print("[Verification] Native find success: ${tokenFile.path}");
              }
           }
         } catch (e) {
           print("[Verification] Native find failed: $e");
         }
      }
      
      // Fallback to Dart search if native failed or on Windows
      if (tokenFile == null) {
          final entities = tempExtractDir.listSync(recursive: true);
          print("[Extraction] Entities: ${entities.length}");
          for (var e in entities) {
            // Check matching filename, loose path check
            if (e.path.contains('tokens.txt')) {
               tokenFile = File(e.path); // Assuming File if contains tokens.txt? Safer to create File obj
               break;
            }
          }
           
          if (tokenFile == null) {
             // Debug info
             final fileList = entities.map((e) => e.path.split(Platform.pathSeparator).last).take(10).join(', ');
             throw Exception("Invalid Model: tokens.txt not found. Found: $fileList...");
          }
      }
      
      final sourceDir = tokenFile.parent;
      print("[Extraction] Found tokens.txt in: ${sourceDir.path}");
      print("[Extraction] Moving/Renaming to: ${finalModelDir.path}");
      
      // Move sourceDir to finalModelDir
      if (sourceDir.absolute.path == tempExtractDir.absolute.path) {
         await tempExtractDir.rename(finalModelDir.path);
      } else {
         await sourceDir.rename(finalModelDir.path);
      }
      
      // Cleanup residue
      if (await tempExtractDir.exists()) await tempExtractDir.delete(recursive: true);
      
      // Delete tarball
      if (await file.exists()) await file.delete();
      
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
       print("[Extraction] Verification Failed!");
       print("[Extraction] Expected path: $finalPath");
       if (await Directory(finalPath).exists()) {
          print("[Extraction] Final Dir Contents: ${Directory(finalPath).listSync()}");
       } else {
          print("[Extraction] Final Dir DOES NOT EXIST!");
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
          print("Warning: Failed to get file length, restarting download: $e");
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
                print("[Download] 416 Received. File verified complete ($localSize bytes). Success.");
                return; // Actually complete
             } else {
                print("[Download] 416 but size mismatch (Local: $localSize, Server: $serverSize). Restarting.");
                if (await destFile.exists()) await destFile.delete();
                throw Exception("文件不完整 ($localSize / $serverSize bytes)，重新下载...");
             }
           } catch (headError) {
              print("[Download] 416 and HEAD request failed: $headError. Restarting.");
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
                print("[Download] Range mismatch! Requested byte $existingBytes, server sending from $serverStartByte. Restarting.");
                if (await destFile.exists()) await destFile.delete();
                throw Exception("服务器响应位置不匹配，重新下载...");
              }
              print("[Download] Range verified: starting from byte $serverStartByte");
            }
          } else {
            totalBytes = existingBytes + (streamedResponse.contentLength ?? 0);
          }
        } else {
          // Full download
          if (existingBytes > 0) {
             print("[Download] Server returned 200 (Full), ignoring Range. Restarting...");
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
        
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          
          if (totalBytes > 0 && onProgress != null) {
            final currentProgress = downloadedBytes / totalBytes;
            // Only update if progress changed by at least 1% to avoid flickering
            if (currentProgress - lastReportedProgress >= 0.01 || currentProgress >= 1.0) {
              onProgress(currentProgress);
              lastReportedProgress = currentProgress;
            }
          }
        }
        
        await sink.close();
        client.close();
        
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
    
    // Generic find model.onnx
    print("[Diagnose] Punctuation Root: ${modelRoot.path} (Exists: ${await modelRoot.exists()})");
    
    if (!await modelRoot.exists()) return null;

    // Robust search: Look for 'model.onnx' in root or 1-level deep
    try {
      if (await File('${modelRoot.path}/model.onnx').exists()) {
        print("[Diagnose] Found model.onnx at root: ${modelRoot.path}/model.onnx");
        return modelRoot.path;
      }
      
      final entities = modelRoot.listSync();
      print("[Diagnose] Root entities: ${entities.map((e) => e.path).toList()}");
      
      for (var entity in entities) {
        if (entity is Directory) {
           if (await File('${entity.path}/model.onnx').exists()) {
             print("[Diagnose] Found model.onnx in subfolder: ${entity.path}");
             return entity.path;
           }
        }
      }
    } catch (e) {
      print("Warning: Error finding punctuation model: $e");
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
  
  // 1. Try Native Tar (MacOS/Linux) - Much faster and memory efficient
  if (Platform.isMacOS || Platform.isLinux) {
     try {
       await Directory(destDir).create(recursive: true);
       // -x: extract, -f: file. bzip2 is usually auto-detected or we can use -j
       // -C: change dir
       final result = await Process.run('tar', ['-xf', tarPath, '-C', destDir]);
       
       if (result.exitCode == 0) {
          print("Native extraction successful.");
          // Fix permissions: Ensure we can read/write everything (some archives have read-only dirs)
          await Process.run('chmod', ['-R', '755', destDir]);
          return;
       }
       print("Native tar failed (Code ${result.exitCode}): ${result.stderr}. Falling back...");
     } catch (e) {
       print("Native tar exception: $e. Falling back...");
     }
  }

  // 2. Fallback: Dart Archive Logic (Memory Intensive!)
  // Note: Loading full file into RAM. For 500MB file this is risky but standard extraction
  // logic usually requires RandomAccess validation or big buffers.
  // We use standard Archive logic.
  final bytes = file.readAsBytesSync();
  
  // Decide based on extension
  Archive archive;
  if (tarPath.endsWith('.tar.bz2') || tarPath.endsWith('.tbz2')) {
    archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
  } else if (tarPath.endsWith('.tar.gz') || tarPath.endsWith('.tgz')) {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } else if (tarPath.endsWith('.zip')) {
    archive = ZipDecoder().decodeBytes(bytes);
  } else {
    // Default fallback
    archive = TarDecoder().decodeBytes(bytes);
  }
  
  // Use extractArchiveToDisk helper which handles paths/symlinks correctly
  extractArchiveToDisk(archive, destDir);
}
