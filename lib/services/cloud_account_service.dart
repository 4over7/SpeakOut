import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_account.dart';
import '../config/cloud_providers.dart';
import '../config/app_log.dart';
import 'config_service.dart';

/// 统一云服务账户管理
///
/// Singleton. 管理所有云服务商的账户 CRUD、持久化、旧数据迁移。
/// 账户元数据存储在 SharedPreferences，敏感凭证存储在系统 Keychain
/// (macOS) / Keystore (Android) via flutter_secure_storage。
class CloudAccountService {
  static final CloudAccountService _instance = CloudAccountService._internal();
  factory CloudAccountService() => _instance;
  CloudAccountService._internal();

  static const String _kAccountsKey = 'cloud_accounts';
  static const String _kMigratedKey = 'cloud_accounts_migrated';
  static const String _kSecureMigratedKey = 'cloud_cred_secure_migrated';

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final List<CloudAccount> _accounts = [];
  bool _initialized = false;

  List<CloudAccount> get accounts => List.unmodifiable(_accounts);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _migrateCredentialsToSecureStorage();
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
        // Load credential values from secure storage
        final keys = (item['credentialKeys'] as List?)?.cast<String>() ?? [];
        for (final key in keys) {
          try {
            final value = await _secureStorage.read(key: 'cloud_cred_${account.id}_$key') ?? '';
            if (value.isNotEmpty) account.credentials[key] = value;
          } catch (e) {
            AppLog.d('CloudAccountService: failed to read credential $key for ${account.id}: $e');
          }
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
      try {
        await _secureStorage.write(key: 'cloud_cred_${account.id}_${entry.key}', value: entry.value);
      } catch (e) {
        AppLog.d('CloudAccountService: failed to save credential ${entry.key} for ${account.id}: $e');
      }
    }
  }

  Future<void> _clearCredentials(String accountId, Iterable<String> keys) async {
    for (final key in keys) {
      try {
        await _secureStorage.delete(key: 'cloud_cred_${accountId}_$key');
      } catch (e) {
        AppLog.d('CloudAccountService: failed to delete credential $key for $accountId: $e');
      }
    }
  }

  // ── SharedPreferences → Keychain 一次性迁移 ──

  Future<void> _migrateCredentialsToSecureStorage() async {
    if (_prefs?.getBool(_kSecureMigratedKey) ?? false) return;

    int migrated = 0;
    // 扫描所有 cloud_cred_ 开头的 SharedPreferences 键
    final allKeys = _prefs?.getKeys() ?? {};
    for (final key in allKeys) {
      if (!key.startsWith('cloud_cred_')) continue;
      final value = _prefs?.getString(key) ?? '';
      if (value.isEmpty) continue;
      try {
        // 写入 Keychain
        await _secureStorage.write(key: key, value: value);
        // 验证写入成功（read back）
        final readBack = await _secureStorage.read(key: key);
        if (readBack == value) {
          // 确认成功后才删除旧数据
          await _prefs?.remove(key);
          migrated++;
        } else {
          AppLog.d('CloudAccountService: Keychain verify failed for $key, keeping SharedPreferences copy');
        }
      } catch (e) {
        AppLog.d('CloudAccountService: secure migration failed for $key: $e');
        // 不删除 SharedPreferences，保留数据安全
      }
    }

    await _prefs?.setBool(_kSecureMigratedKey, true);
    if (migrated > 0) {
      AppLog.d('CloudAccountService: migrated $migrated credentials to secure storage');
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
