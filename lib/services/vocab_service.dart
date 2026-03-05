import 'dart:convert';
import 'package:flutter/services.dart';
import 'config_service.dart';

/// 词汇表条目：错误形式 → 正确形式
class VocabEntry {
  final String wrong;
  final String correct;

  const VocabEntry({required this.wrong, required this.correct});

  factory VocabEntry.fromJson(Map<String, dynamic> json) => VocabEntry(
        wrong: json['wrong'] as String? ?? '',
        correct: json['correct'] as String,
      );

  Map<String, dynamic> toJson() => {'wrong': wrong, 'correct': correct};
}

/// 行业词汇包
class VocabPack {
  final String id;
  final String nameZh;
  final String nameEn;
  final List<VocabEntry> entries;

  const VocabPack({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.entries,
  });
}

/// 词汇增强服务（Phase 1：简单 replaceAll 替换表）
///
/// Phase 2 扩展点：applyWithPhonetic(text, tokens: List of String)
/// Phase 3 扩展点：applyWithContext(text, industry: String)
class VocabService {
  static final VocabService _instance = VocabService._internal();
  factory VocabService() => _instance;
  VocabService._internal();

  // 行业包定义（id 资源路径 nameZh nameEn）
  static const _packDefs = [
    (id: 'tech', asset: 'assets/vocab/tech.json', nameZh: '软件/IT', nameEn: 'Software/IT'),
    (id: 'medical', asset: 'assets/vocab/medical.json', nameZh: '医疗', nameEn: 'Medical'),
    (id: 'legal', asset: 'assets/vocab/legal.json', nameZh: '法律', nameEn: 'Legal'),
    (id: 'finance', asset: 'assets/vocab/finance.json', nameZh: '金融', nameEn: 'Finance'),
    (id: 'education', asset: 'assets/vocab/education.json', nameZh: '教育', nameEn: 'Education'),
  ];

  final Map<String, VocabPack> _loadedPacks = {};
  bool _packsLoaded = false;

  /// 所有可用行业包（含元信息，不一定已加载词条）
  static List<({String id, String nameZh, String nameEn})> get availablePacks =>
      _packDefs.map((d) => (id: d.id, nameZh: d.nameZh, nameEn: d.nameEn)).toList();

  /// 已加载的行业包
  List<VocabPack> get loadedPacks => _loadedPacks.values.toList();

  /// 当前激活的所有词条（行业包 + 用户自定义）
  List<VocabEntry> getActiveEntries() {
    final config = ConfigService();
    final entries = <VocabEntry>[];

    // 行业包
    for (final def in _packDefs) {
      final enabled = _isPackEnabled(def.id, config);
      if (!enabled) continue;
      final pack = _loadedPacks[def.id];
      if (pack != null) {
        entries.addAll(pack.entries.where((e) => e.wrong.isNotEmpty));
      }
    }

    // 用户自定义词条
    if (config.vocabUserEnabled) {
      entries.addAll(userEntries.where((e) => e.wrong.isNotEmpty));
    }

    return entries;
  }

  /// 用户自定义词条（从 SharedPreferences 读取）
  List<VocabEntry> get userEntries {
    final json = ConfigService().vocabUserEntriesJson;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => VocabEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addUserEntry(VocabEntry entry) async {
    final current = userEntries;
    current.add(entry);
    await _saveUserEntries(current);
  }

  Future<void> deleteUserEntry(int index) async {
    final current = userEntries;
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _saveUserEntries(current);
  }

  Future<void> _saveUserEntries(List<VocabEntry> entries) async {
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await ConfigService().setVocabUserEntriesJson(json);
  }

  /// Phase 1：对 text 执行激活词条的精确替换
  String applyReplacements(String text) {
    if (text.isEmpty) return text;
    final entries = getActiveEntries();
    if (entries.isEmpty) return text;

    String result = text;
    for (final entry in entries) {
      if (entry.wrong.isEmpty || entry.correct.isEmpty) continue;
      result = result.replaceAll(entry.wrong, entry.correct);
    }
    return result;
  }

  /// Phase 2 预留接口（当前透传 Phase 1 结果）
  String applyWithPhonetic(String text, {List<String>? tokens}) {
    return applyReplacements(text);
  }

  /// 初始化：预加载所有启用的行业包（懒加载，首次调用时执行）
  Future<void> ensurePacksLoaded() async {
    if (_packsLoaded) return;
    _packsLoaded = true;
    for (final def in _packDefs) {
      await _loadPack(def.id, def.asset, def.nameZh, def.nameEn);
    }
  }

  Future<void> _loadPack(String id, String assetPath, String nameZh, String nameEn) async {
    if (_loadedPacks.containsKey(id)) return;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (data['entries'] as List<dynamic>)
          .map((e) => VocabEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _loadedPacks[id] = VocabPack(
        id: id,
        nameZh: nameZh,
        nameEn: nameEn,
        entries: entries,
      );
    } catch (_) {
      // 资源不存在时忽略
    }
  }

  bool _isPackEnabled(String id, ConfigService config) {
    switch (id) {
      case 'tech': return config.vocabTechEnabled;
      case 'medical': return config.vocabMedicalEnabled;
      case 'legal': return config.vocabLegalEnabled;
      case 'finance': return config.vocabFinanceEnabled;
      case 'education': return config.vocabEducationEnabled;
      default: return false;
    }
  }
}
