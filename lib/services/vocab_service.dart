import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';
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

  // Phase 2：拼音缓存（wrong 汉字 → 拼音字符串）
  final Map<String, String> _pinyinCache = {};
  bool _pinyinCacheReady = false;

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
    invalidatePinyinCache();
  }

  Future<void> deleteUserEntry(int index) async {
    final current = userEntries;
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await _saveUserEntries(current);
    invalidatePinyinCache();
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

  /// Phase 2：音近软匹配替换
  ///
  /// 先做 Phase 1 精确替换，再对文本做滑动窗口拼音距离匹配。
  /// [tokens] — ASR 分词列表（当前仅用于未来置信度门控）
  /// [confidence] — per-token 对数概率，仅离线 Transducer 模型有值
  Future<String> applyWithPhonetic(
    String text, {
    List<String>? tokens,
    List<double>? confidence,
  }) async {
    // Phase 1 已在 CoreEngine 执行，此处直接处理传入文本
    if (text.isEmpty) return text;

    await _ensurePinyinCache();
    if (_pinyinCache.isEmpty) return text;

    final threshold = ConfigService().vocabPhoneticThreshold;
    final entries = getActiveEntries();
    if (entries.isEmpty) return text;

    String result = text;

    // 对每个有 wrong 字段的词条，尝试在文本中找音近子串
    for (final entry in entries) {
      if (entry.wrong.isEmpty || entry.correct.isEmpty) continue;

      final wrongPinyin = _pinyinCache[entry.wrong];
      if (wrongPinyin == null) continue;

      final wrongLen = entry.wrong.length;
      if (wrongLen < 2 || wrongLen > 6) continue; // 只做 2~6 字窗口

      // 在 result 中滑动相同长度窗口，寻找音近子串
      int i = 0;
      while (i <= result.length - wrongLen) {
        final window = result.substring(i, i + wrongLen);
        // 跳过已是正确词的位置
        if (window == entry.correct) {
          i++;
          continue;
        }
        final windowPinyin = PinyinHelper.getPinyin(window, separator: ' ');
        final dist = _phoneticDistance(wrongPinyin, windowPinyin);
        if (dist <= threshold) {
          result = result.substring(0, i) + entry.correct + result.substring(i + wrongLen);
          i += entry.correct.length; // 跳过替换后的正确词
        } else {
          i++;
        }
      }
    }

    return result;
  }

  /// 使词条拼音缓存失效（词条变更或开关切换时调用）
  void invalidatePinyinCache() {
    _pinyinCache.clear();
    _pinyinCacheReady = false;
  }

  Future<void> _ensurePinyinCache() async {
    if (_pinyinCacheReady) return;
    final entries = getActiveEntries();
    for (final e in entries) {
      if (e.wrong.isNotEmpty) {
        _pinyinCache[e.wrong] = PinyinHelper.getPinyin(e.wrong, separator: ' ');
      }
    }
    _pinyinCacheReady = true;
  }

  /// 方言标准化：将平翘舌、前后鼻音等视为等价
  String _normalizeDialect(String pinyin) {
    return pinyin
        .replaceAll('zh', 'z')
        .replaceAll('ch', 'c')
        .replaceAll('sh', 's')
        .replaceAll('l', 'n');
  }

  /// 音近距离：拼音归一化后的 Levenshtein 编辑距离（按音节空格分隔）
  double _phoneticDistance(String pinyinA, String pinyinB) {
    final a = _normalizeDialect(pinyinA);
    final b = _normalizeDialect(pinyinB);
    return _levenshtein(a, b).toDouble();
  }

  /// 标准 Levenshtein 编辑距离
  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final dp = List.generate(s.length + 1, (i) => List.filled(t.length + 1, 0));
    for (int i = 0; i <= s.length; i++) { dp[i][0] = i; }
    for (int j = 0; j <= t.length; j++) { dp[0][j] = j; }

    for (int i = 1; i <= s.length; i++) {
      for (int j = 1; j <= t.length; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[s.length][t.length];
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
