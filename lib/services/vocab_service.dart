import 'dart:convert';
import 'package:flutter/services.dart';
import 'config_service.dart';

/// Vocab entry: wrong form -> correct form
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

/// Industry vocab pack
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

/// Vocab service: manages industry packs and user custom entries.
///
/// Primary mode: provide vocab hints to LLM for context-aware correction.
/// Fallback mode: direct string replacement when AI is disabled.
class VocabService {
  static final VocabService _instance = VocabService._internal();
  factory VocabService() => _instance;
  VocabService._internal();

  static const _packDefs = [
    (id: 'tech', asset: 'assets/vocab/tech.json', nameZh: '软件/IT', nameEn: 'Software/IT'),
    (id: 'medical', asset: 'assets/vocab/medical.json', nameZh: '医疗', nameEn: 'Medical'),
    (id: 'legal', asset: 'assets/vocab/legal.json', nameZh: '法律', nameEn: 'Legal'),
    (id: 'finance', asset: 'assets/vocab/finance.json', nameZh: '金融', nameEn: 'Finance'),
    (id: 'education', asset: 'assets/vocab/education.json', nameZh: '教育', nameEn: 'Education'),
  ];

  final Map<String, VocabPack> _loadedPacks = {};
  bool _packsLoaded = false;

  static List<({String id, String nameZh, String nameEn})> get availablePacks =>
      _packDefs.map((d) => (id: d.id, nameZh: d.nameZh, nameEn: d.nameEn)).toList();

  List<VocabPack> get loadedPacks => _loadedPacks.values.toList();

  /// All active entries (industry packs + user custom)
  List<VocabEntry> getActiveEntries() {
    final config = ConfigService();
    final entries = <VocabEntry>[];

    for (final def in _packDefs) {
      if (!_isPackEnabled(def.id, config)) continue;
      final pack = _loadedPacks[def.id];
      if (pack != null) {
        entries.addAll(pack.entries.where((e) => e.wrong.isNotEmpty));
      }
    }

    if (config.vocabUserEnabled) {
      entries.addAll(userEntries.where((e) => e.wrong.isNotEmpty));
    }

    return entries;
  }

  /// Get vocab hints for LLM prompt injection.
  /// Returns unique correct-form terms, user entries prioritized.
  List<String> getVocabHints({int maxItems = 200}) {
    final entries = getActiveEntries();
    final userSet = userEntries.map((e) => e.correct).toSet();
    final allHints = entries.map((e) => e.correct).toSet().toList();

    if (allHints.length <= maxItems) return allHints;

    // Prioritize user entries, then truncate industry entries
    final sorted = allHints.where(userSet.contains).toList()
      ..addAll(allHints.where((h) => !userSet.contains(h)));
    return sorted.take(maxItems).toList();
  }

  /// User custom entries (from SharedPreferences)
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
    // Dedup: if an entry with the same 'wrong' text exists, update it
    final existingIdx = current.indexWhere((e) => e.wrong == entry.wrong);
    if (existingIdx >= 0) {
      current[existingIdx] = entry;
    } else {
      current.add(entry);
    }
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

  /// Fallback: direct string replacement (used when AI is disabled)
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

  /// Load all industry packs (lazy, called once)
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
      // Asset not found — ignore
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
