import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_account.dart';
import '../config/cloud_providers.dart';
import '../config/app_log.dart';
import 'config_service.dart';

/// 统一云服务账户管理
///
/// Singleton. 管理所有云服务商的账户 CRUD、持久化、旧数据迁移。
/// 凭证存储在 SharedPreferences。
/// TODO: 拿到苹果开发者账号后迁移到 Keychain (flutter_secure_storage)。
class CloudAccountService {
  static final CloudAccountService _instance = CloudAccountService._internal();
  factory CloudAccountService() => _instance;
  CloudAccountService._internal();

  static const String _kAccountsKey = 'cloud_accounts';
  static const String _kMigratedKey = 'cloud_accounts_migrated';

  SharedPreferences? _prefs;
  final List<CloudAccount> _accounts = [];
  bool _initialized = false;

  List<CloudAccount> get accounts => List.unmodifiable(_accounts);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
    _initialized = true;
  }

  /// 重新加载账户数据（导入配置后调用）
  Future<void> reload() async {
    _accounts.clear();
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
  }

  /// 仅供测试：构造「落盘失败」场景。
  /// 生产代码不要调用 —— 置空后所有写入都会抛 StateError。
  @visibleForTesting
  void debugSetPrefsForTest(SharedPreferences? prefs) => _prefs = prefs;

  // ── CRUD ──

  Future<String> addAccount(CloudAccount account) async {
    // 先入内存再落盘：任一步抛异常都必须回滚，否则 UI 允许重试时会用新 uuid
    // 再追加一个，第二次成功就把两条一起持久化 —— 重复账户。
    _accounts.add(account);
    try {
      await _saveAccounts();
      await _saveCredentials(account);
    } catch (e) {
      _accounts.removeWhere((a) => a.id == account.id);
      try {
        await _saveAccounts(); // 尽力把已落盘的部分改回去
      } catch (_) {}
      rethrow;
    }
    AppLog.d('CloudAccountService: added account ${account.id} (${account.providerId})');
    return account.id;
  }

  Future<void> updateAccount(CloudAccount account) async {
    final idx = _accounts.indexWhere((a) => a.id == account.id);
    if (idx < 0) return;
    // 清理被移除的旧凭证 key（旧 - 新 差集），避免删字段/改 schema 后残留明文 secret
    final removed = _accounts[idx].credentials.keys.toSet()
        .difference(account.credentials.keys.toSet());
    if (removed.isNotEmpty) {
      await _clearCredentials(account.id, removed);
    }
    _accounts[idx] = account;
    await _saveAccounts();
    await _saveCredentials(account);
  }

  Future<void> removeAccount(String accountId) async {
    final account = getAccountById(accountId);
    if (account == null) return;
    _accounts.removeWhere((a) => a.id == accountId);
    await _saveAccounts();
    await _clearCredentials(accountId, account.credentials.keys);

    // 如果被删除的账户正被选用，清除选择
    if (ConfigService().selectedAsrAccountId == accountId) {
      await ConfigService().setSelectedAsrAccount(null);
    }
    if (ConfigService().selectedLlmAccountId == accountId) {
      await ConfigService().setSelectedLlmAccountId(null);
    }

    AppLog.d('CloudAccountService: removed account $accountId');
  }

  CloudAccount? getAccountById(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 获取指定能力的所有已启用账户
  List<CloudAccount> getAccountsWithCapability(CloudCapability cap) {
    return _accounts.where((a) {
      if (!a.isEnabled) return false;
      final provider = CloudProviders.getById(a.providerId);
      return provider != null && provider.capabilities.contains(cap);
    }).toList();
  }

  /// 获取指定服务商的账户
  CloudAccount? getAccountByProviderId(String providerId) {
    for (final a in _accounts) {
      if (a.providerId == providerId) return a;
    }
    return null;
  }

  /// LLM 推荐优先级：质量/价格/对 prompt 约束的服从性综合排序。
  /// 注：volcengine 豆包 lite 默认模型对元评论禁令服从性差，故排在中后段。
  static const List<String> _kLlmRecommendationOrder = [
    'deepseek',
    'anthropic',
    'openai',
    'zhipu',
    'dashscope',
    'moonshot',
    'gemini',
    'minimax',
    'volcengine',
    'groq',
    'xfyun',
  ];

  /// 具备 ASR 能力的账户池（去重，保持列表顺序）。
  List<CloudAccount> asrAccountPool() {
    final all = getAccountsWithCapability(CloudCapability.asrStreaming) +
        getAccountsWithCapability(CloudCapability.asrBatch);
    final seen = <String>{};
    return all.where((a) => seen.add(a.id)).toList();
  }

  /// 当前实际生效的 ASR 账户 —— **UI 与 Engine 必须共用这一个入口**。
  /// 曾经两边各写各的回退：UI 回退到池中第一个（画出「火山引擎」已选中的假象），
  /// Engine 回退到推荐顺序（实际连的是阿里云百炼），于是界面显示的和真正在跑的不是一个。
  /// 注意 selectedAsrAccountId 为空时这里只是「临时生效」，并未落盘，
  /// 直到用户在下拉里主动选一次才会持久化。
  CloudAccount? effectiveAsrAccount() {
    final pool = asrAccountPool();
    if (pool.isEmpty) return null;
    final saved = ConfigService().selectedAsrAccountId;
    if (saved != null) {
      for (final a in pool) {
        if (a.id == saved) return a;
      }
    }
    return pickRecommendedAsrAccount() ?? pool.first;
  }

  /// ASR 推荐优先级。与 LLM 分开排：ASR 看重流式稳定与低延迟，
  /// 且凭证形态各异（讯飞要 app_id+api_key+api_secret，火山有独立 asr_api_key）。
  /// aliyun_nls 是 legacy 通道，排最后。
  static const List<String> _kAsrRecommendationOrder = [
    'dashscope',
    'volcengine',
    'xfyun',
    'tencent',
    'openai',
    'groq',
    'aliyun_nls',
  ];

  /// 按优先级挑一个 ASR 账户，对应 LLM 的 pickRecommendedLlmAccount()。
  /// 少了这个兜底，用户切到云端识别但没显式选过 ASR 账户时，
  /// initASR 会一路掉进 legacy Aliyun NLS 分支，报一句指向错误方向的
  /// "Aliyun Config Missing" —— 而他的 DashScope 凭证其实是全的。
  /// 凭证完整性按能力判断，不能只看 api_key。
  CloudAccount? pickRecommendedAsrAccount() {
    final pool = _accounts.where((a) {
      if (!a.isEnabled) return false;
      final p = CloudProviders.getById(a.providerId);
      if (p == null) return false;
      return p.hasValidCredentialsFor(CloudCapability.asrStreaming, a.credentials) ||
          p.hasValidCredentialsFor(CloudCapability.asrBatch, a.credentials);
    }).toList();
    if (pool.isEmpty) return null;
    for (final pid in _kAsrRecommendationOrder) {
      for (final a in pool) {
        if (a.providerId == pid) return a;
      }
    }
    return pool.first;
  }

  /// 按优先级挑一个 LLM 账户（已 enabled 且 api_key 已配）。
  /// 用于 selectedLlmAccountId 为空 / 失效时的兜底——避免落到豆包 lite 这种
  /// 对 prompt 约束服从性差的小模型上。
  CloudAccount? pickRecommendedLlmAccount() {
    // 凭证完整性按**能力**判断，不能硬编码 api_key ——
    // 讯飞的 LLM 用 api_password（llmApiKeyField），它同时还有个给 ASR 用的 api_key。
    // 只看 api_key 会把「只配了 ASR」的讯飞账户推荐去做 LLM，然后调用失败。
    final pool = getAccountsWithCapability(CloudCapability.llm).where((a) {
      final p = CloudProviders.getById(a.providerId);
      return p != null &&
          p.hasValidCredentialsFor(CloudCapability.llm, a.credentials);
    }).toList();
    if (pool.isEmpty) return null;
    for (final pid in _kLlmRecommendationOrder) {
      for (final a in pool) {
        if (a.providerId == pid) return a;
      }
    }
    return pool.first;
  }

  // ── 持久化 ──

  /// 云账户凭证里存的 model 字段同样可能是已停用的 DeepSeek 旧别名。
  /// 与 ConfigService.migrateDeepSeekV4 配套，只动 deepseek 账户。
  Future<void> migrateDeepSeekModels() async {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'deepseek_v4_account_migrated';
    if (prefs.getBool(flag) ?? false) return;
    for (final a in _accounts) {
      if (a.providerId != 'deepseek') continue;
      final m = a.credentials['model'];
      final mapped = ConfigService.mapRetiredDeepSeekModel(m);
      if (m != null && mapped != null && mapped != m) {
        a.credentials['model'] = mapped;
        await updateAccount(a);
        AppLog.d('[Migration] DeepSeek 账户模型 $m → deepseek-v4-flash');
      }
    }
    await prefs.setBool(flag, true);
  }

  Future<void> _loadAccounts() async {
    final json = _prefs?.getString(_kAccountsKey);
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List;
      for (final item in list) {
        final account = CloudAccount.fromJson(item as Map<String, dynamic>);
        final keys = (item['credentialKeys'] as List?)?.cast<String>() ?? [];
        for (final key in keys) {
          final value = _prefs?.getString('cloud_cred_${account.id}_$key') ?? '';
          if (value.isNotEmpty) account.credentials[key] = value;
        }
        _accounts.add(account);
      }
      AppLog.d('CloudAccountService: loaded ${_accounts.length} accounts');
    } catch (e) {
      AppLog.d('CloudAccountService: load failed: $e');
    }
  }

  Future<void> _saveAccounts() async {
    // 用 ! 而不是 ?.：_prefs 为空时静默什么都不写，调用方却拿到"成功" ——
    // 那是静默数据丢失。宁可抛出来让上层看见。
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('CloudAccountService 未初始化，无法保存账户');
    }
    final json = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_kAccountsKey, json);
  }

  Future<void> _saveCredentials(CloudAccount account) async {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('CloudAccountService 未初始化，无法保存凭证');
    }
    for (final entry in account.credentials.entries) {
      await prefs.setString('cloud_cred_${account.id}_${entry.key}', entry.value);
    }
  }

  Future<void> _clearCredentials(String accountId, Iterable<String> keys) async {
    for (final key in keys) {
      await _prefs?.remove('cloud_cred_${accountId}_$key');
    }
  }

  // ── 导出/导入 ──

  /// 导出所有云账户（含凭证）到 JSON 文件
  Future<bool> exportToFile(String filePath) async {
    try {
      // 导出**不含凭证**。导出文件会被同步、转发、误提交，API Key 一旦落进
      // 明文 JSON 就收不回来。v1.9.0 只给 ConfigBackupService 加了这道闸，
      // 这条同源路径漏了 —— 它还挂在普通用户按钮上，无任何提示。
      // 只带出「有哪些账户、填过哪些字段」，导入后由用户重填密钥。
      final data = _accounts.map((a) => {
        'providerId': a.providerId,
        'displayName': a.displayName,
        'isEnabled': a.isEnabled,
        'credentialKeys': a.credentials.keys.toList()..sort(),
      }).toList();
      final json = const JsonEncoder.withIndent('  ').convert({
        'app': 'SpeakOut',
        'type': 'cloud_accounts',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'accounts': data,
      });
      await File(filePath).writeAsString(json);
      AppLog.d('CloudAccountService: exported ${data.length} accounts to $filePath');
      return true;
    } catch (e) {
      AppLog.d('CloudAccountService: export failed: $e');
      return false;
    }
  }

  /// 从 JSON 文件导入云账户（跳过已存在的服务商）
  /// 新格式导出不带密钥值，无脑恢复 isEnabled 会让**空凭证账户被启用**：
  /// asrAccountPool() 只看 isEnabled + capability，会把它选中，
  /// 然后云端识别初始化失败。所以只有真拿到凭证才允许启用。
  static bool _shouldEnable(bool wanted, Map<String, String> creds) =>
      wanted && creds.values.any((v) => v.isNotEmpty);

  Future<int> importFromFile(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      if (map['type'] != 'cloud_accounts') {
        AppLog.d('CloudAccountService: invalid file type');
        return 0;
      }
      final list = (map['accounts'] as List?) ?? [];
      int imported = 0;
      int skipped = 0;
      for (final item in list) {
        // 先把整项解析校验完，再动 _accounts 里的对象。
        // getAccountByProviderId 返回的是**原对象引用**，边解析边改的话，
        // 后一个字段 cast 抛异常会留下「已改名但没落盘」的脏内存状态。
        final ({
          String providerId,
          String? displayName,
          bool? isEnabled,
          Map<String, String> creds
        })? p;
        try {
          p = (
            providerId: (item['providerId'] as String?) ?? '',
            displayName: item['displayName'] as String?,
            isEnabled: item['isEnabled'] as bool?,
            // 老格式（v1.10.0 前）带明文 credentials，仍要读出来让用户能恢复自己的旧备份；
            // 新格式只有 credentialKeys（字段名清单，供人看），没有值可填。
            creds: (item['credentials'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, v.toString())) ??
                <String, String>{},
          );
        } catch (e) {
          // 单项坏数据只跳过这一项，不能让整个导入 return 0 —— 那会在前面若干项
          // 已逐项落盘之后谎报「一条都没导入」。
          AppLog.d('CloudAccountService: skip malformed entry: $e');
          skipped++;
          continue;
        }
        if (p.providerId.isEmpty) {
          skipped++;
          continue;
        }

        // 不能「已存在就跳过」：云账户页一进入就会 _ensureAllProvidersExist()
        // 预建全部 15 家，那样导入永远是 0 条。改为合并到既有账户。
        final existing = getAccountByProviderId(p.providerId);
        if (existing != null) {
          // 只补空缺，不用导入值覆盖用户已填好的密钥
          final merged = Map<String, String>.from(existing.credentials);
          p.creds.forEach((k, v) {
            if (v.isNotEmpty && (merged[k] ?? '').isEmpty) merged[k] = v;
          });
          // 构造副本而不是就地改 existing：getAccountByProviderId 返回的是
          // _accounts 里的原对象，就地改会让 updateAccount 里
          // 「旧 keys - 新 keys」的差集恒为空 —— 那道用来清除 SharedPreferences
          // 残留明文密钥的安全网会静默失效（本路径只增不减，暂时无泄漏，
          // 但这个写法一旦被照抄到会删字段的场景就是真漏）。
          await updateAccount(CloudAccount(
            id: existing.id,
            providerId: existing.providerId,
            displayName: p.displayName ?? existing.displayName,
            credentials: merged,
            isEnabled: _shouldEnable(p.isEnabled ?? existing.isEnabled, merged),
            createdAt: existing.createdAt,
          ));
        } else {
          await addAccount(CloudAccount(
            id: const Uuid().v4(),
            providerId: p.providerId,
            displayName: p.displayName ?? p.providerId,
            isEnabled: _shouldEnable(p.isEnabled ?? true, p.creds),
            credentials: p.creds,
          ));
        }
        imported++;
      }
      if (skipped > 0) {
        AppLog.d('CloudAccountService: skipped $skipped malformed entries');
      }
      AppLog.d('CloudAccountService: imported $imported accounts from $filePath');
      return imported;
    } catch (e) {
      AppLog.d('CloudAccountService: import failed: $e');
      return 0;
    }
  }

  // ── 旧数据迁移（Legacy → CloudAccount） ──

  Future<void> migrateFromLegacy() async {
    if (_prefs?.getBool(_kMigratedKey) ?? false) return;

    final config = ConfigService();
    int migrated = 0;

    // 1. 迁移阿里云 NLS 凭证
    final akId = config.aliyunAccessKeyId;
    final akSecret = config.aliyunAccessKeySecret;
    final appKey = config.aliyunAppKey;
    if (akId.isNotEmpty && akSecret.isNotEmpty && appKey.isNotEmpty) {
      final account = CloudAccount(
        id: const Uuid().v4(),
        providerId: 'aliyun_nls',
        displayName: '阿里云 NLS (迁移)',
        credentials: {
          'access_key_id': akId,
          'access_key_secret': akSecret,
          'app_key': appKey,
        },
      );
      await addAccount(account);
      migrated++;
    }

    // 2. 迁移 LLM Preset 凭证
    for (final presetId in ['dashscope', 'volcengine', 'openai', 'deepseek', 'anthropic', 'zhipu', 'gemini', 'moonshot', 'minimax', 'groq']) {
      final savedKey = _prefs?.getString('llm_preset_${presetId}_api_key') ?? '';
      if (savedKey.isEmpty) continue;
      if (getAccountByProviderId(presetId) != null) continue;
      final provider = CloudProviders.getById(presetId);
      if (provider == null) continue;

      final account = CloudAccount(
        id: const Uuid().v4(),
        providerId: presetId,
        displayName: '${provider.name} (迁移)',
        credentials: {'api_key': savedKey},
      );
      await addAccount(account);
      migrated++;
    }

    // 同样不能静默：这个标志没写成功，下次启动会重跑迁移，
    // 而迁移里会 addAccount —— 可能造出重复账户。
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('CloudAccountService 未初始化，无法写入迁移标志');
    }
    await prefs.setBool(_kMigratedKey, true);
    if (migrated > 0) {
      AppLog.d('CloudAccountService: migrated $migrated legacy accounts');
    }
  }
}
