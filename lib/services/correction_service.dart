import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/app_log.dart';
import '../engine/core_engine.dart';
import 'llm_service.dart';
import 'vocab_service.dart';

/// 词级纠错对
class CorrectionPair {
  final String wrong;
  final String correct;
  final String source; // 'asr' | 'llm'

  CorrectionPair({required this.wrong, required this.correct, required this.source});

  factory CorrectionPair.fromJson(Map<String, dynamic> json) => CorrectionPair(
    wrong: json['wrong'] as String,
    correct: json['correct'] as String,
    source: json['source'] as String? ?? 'asr',
  );

  Map<String, dynamic> toJson() => {'wrong': wrong, 'correct': correct, 'source': source};
}

/// 纠错反馈结果
class CorrectionResult {
  final List<CorrectionPair> corrections;
  final int vocabAdded;

  CorrectionResult({required this.corrections, required this.vocabAdded});
}

/// 纠错反馈服务：对比用户校正与 ASR 输出，提取差异，追加词汇表
class CorrectionService {
  static final CorrectionService _instance = CorrectionService._internal();
  factory CorrectionService() => _instance;
  CorrectionService._internal();

  void _log(String msg) => AppLog.d('[Correction] $msg');

  /// 提交纠错：用户校正文本 + pipeline trace
  Future<CorrectionResult> submitCorrection(String userText, LastRecordingTrace trace) async {
    _log('Submitting correction: user="${userText.length}字", asr="${trace.asrRawText.length}字"');

    // 选择对比目标：如果有 LLM 润色，对比 LLM 输出；否则对比 ASR 原文
    final wrongText = trace.finalText;

    // LLM 提取词级差异
    final corrections = await _extractCorrections(wrongText, userText);
    _log('Extracted ${corrections.length} corrections');

    // 追加到词汇表
    int added = 0;
    for (final c in corrections) {
      if (c.wrong.isNotEmpty && c.correct.isNotEmpty && c.wrong != c.correct) {
        await VocabService().addUserEntry(VocabEntry(wrong: c.wrong, correct: c.correct));
        added++;
      }
    }
    _log('Added $added entries to vocab');

    // 保存完整纠错记录
    await _saveRecord(trace, userText, corrections);

    return CorrectionResult(corrections: corrections, vocabAdded: added);
  }

  /// 调用 LLM 对比差异，提取词级纠错对
  Future<List<CorrectionPair>> _extractCorrections(String wrongText, String correctText) async {
    if (wrongText == correctText) return [];

    final prompt = '''你是一个文本对比专家。以下是语音识别的输出和用户修正后的正确文本。
请提取所有词级别的差异，返回 JSON 数组。

注意：
- 用户可能多选或少选了几个字，忽略首尾的无关文字
- 只提取真正的识别错误，不包括标点、格式差异
- 判断错误来源：如果是音近错误（同音/近音字），标记为 "asr"；如果是语义/语法错误，标记为 "llm"
- 如果没有实质差异，返回空数组 []

识别输出: $wrongText
用户修正: $correctText

仅返回 JSON 数组，不要其他文字:
[{"wrong": "错误词", "correct": "正确词", "source": "asr"}]''';

    try {
      final response = await LLMService().organizeText(prompt);
      final cleaned = response.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '').trim();

      final list = jsonDecode(cleaned) as List;
      return list
          .map((e) => CorrectionPair.fromJson(e as Map<String, dynamic>))
          .where((c) => c.wrong.isNotEmpty && c.correct.isNotEmpty)
          .toList();
    } catch (e) {
      _log('LLM extraction failed: $e');
      return [];
    }
  }

  /// 保存纠错记录到 JSONL 文件
  Future<void> _saveRecord(LastRecordingTrace trace, String userText, List<CorrectionPair> corrections) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final corrDir = Directory('${dir.path}/corrections');
      if (!corrDir.existsSync()) corrDir.createSync(recursive: true);

      final file = File('${corrDir.path}/corrections.jsonl');
      final record = {
        ...trace.toJson(),
        'userCorrectedText': userText,
        'corrections': corrections.map((c) => c.toJson()).toList(),
      };
      await file.writeAsString('${jsonEncode(record)}\n', mode: FileMode.append);
      _log('Record saved to ${file.path}');
    } catch (e) {
      _log('Save record failed: $e');
    }
  }

  /// 纠错数据文件路径
  Future<String> get _dataFilePath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/corrections/corrections.jsonl';
  }

  /// 获取纠错记录数量
  Future<int> getRecordCount() async {
    try {
      final file = File(await _dataFilePath);
      if (!file.existsSync()) return 0;
      return file.readAsLinesSync().where((l) => l.trim().isNotEmpty).length;
    } catch (_) {
      return 0;
    }
  }

  /// 导出纠错数据到指定路径
  Future<bool> exportData(String destPath) async {
    try {
      final srcPath = await _dataFilePath;
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) {
        _log('Export: no data file');
        return false;
      }
      await srcFile.copy(destPath);
      _log('Exported to $destPath');
      return true;
    } catch (e) {
      _log('Export failed: $e');
      return false;
    }
  }

  /// 导入纠错数据（追加到现有数据，跳过已存在的记录）
  Future<int> importData(String srcPath) async {
    try {
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) return 0;

      final lines = srcFile.readAsLinesSync().where((l) => l.trim().isNotEmpty);
      int imported = 0;

      final destFile = File(await _dataFilePath);
      final destDir = destFile.parent;
      if (!destDir.existsSync()) destDir.createSync(recursive: true);

      // Load existing timestamps to dedup
      final existingTimestamps = <String>{};
      if (destFile.existsSync()) {
        for (final existingLine in destFile.readAsLinesSync()) {
          try {
            final ej = jsonDecode(existingLine) as Map<String, dynamic>;
            final ts = ej['timestamp'] as String?;
            if (ts != null) existingTimestamps.add(ts);
          } catch (_) {}
        }
      }

      final sink = destFile.openWrite(mode: FileMode.append);
      for (final line in lines) {
        try {
          // 验证 JSON 合法性
          final json = jsonDecode(line) as Map<String, dynamic>;
          // Skip if record with same timestamp already exists
          final ts = json['timestamp'] as String?;
          if (ts != null && existingTimestamps.contains(ts)) continue;
          sink.writeln(jsonEncode(json));
          if (ts != null) existingTimestamps.add(ts);
          imported++;

          // 同时导入词汇对到 VocabService
          final corrections = json['corrections'] as List<dynamic>? ?? [];
          for (final c in corrections) {
            final pair = CorrectionPair.fromJson(c as Map<String, dynamic>);
            if (pair.wrong.isNotEmpty && pair.correct.isNotEmpty && pair.wrong != pair.correct) {
              await VocabService().addUserEntry(VocabEntry(wrong: pair.wrong, correct: pair.correct));
            }
          }
        } catch (_) {
          // 跳过无效行
        }
      }
      await sink.flush();
      await sink.close();

      _log('Imported $imported records from $srcPath');
      return imported;
    } catch (e) {
      _log('Import failed: $e');
      return 0;
    }
  }
}
