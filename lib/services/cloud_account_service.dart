import 'dart:convert';
import 'dart:io';
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

  // ── CRUD ──

  Future<String> addAccount(CloudAccount account) async {
    _accounts.add(account);
    await _saveAccounts();
    await _saveCredentials(account);
    AppLog.d('CloudAccountService: added account ${account.id} (${account.providerId})');
    return account.id;
  }

  Future<void> updateAccount(CloudAccount account) async {
    final idx = _accounts.indexWhere((a) => a.id == account.id);
    if (idx < 0) return;
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

  // ── 持久化 ──

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
    final json = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await _prefs?.setString(_kAccountsKey, json);
  }

  Future<void> _saveCredentials(CloudAccount account) async {
    for (final entry in account.credentials.entries) {
      await _prefs?.setString('cloud_cred_${account.id}_${entry.key}', entry.value);
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
      final data = _accounts.map((a) => {
        'providerId': a.providerId,
        'displayName': a.displayName,
        'isEnabled': a.isEnabled,
        'credentials': Map<String, String>.from(a.credentials),
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
      for (final item in list) {
        final providerId = item['providerId'] as String? ?? '';
        if (providerId.isEmpty) continue;
        // 跳过已存在的服务商
        if (getAccountByProviderId(providerId) != null) continue;
        final creds = (item['credentials'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString())) ?? {};
        final account = CloudAccount(
          id: const Uuid().v4(),
          providerId: providerId,
          displayName: item['displayName'] as String? ?? providerId,
          isEnabled: item['isEnabled'] as bool? ?? true,
          credentials: creds,
        );
        await addAccount(account);
        imported++;
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

    await _prefs?.setBool(_kMigratedKey, true);
    if (migrated > 0) {
      AppLog.d('CloudAccountService: migrated $migrated legacy accounts');
    }
  }
}
