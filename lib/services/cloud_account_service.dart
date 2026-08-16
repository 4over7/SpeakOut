import 'dart:async';
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
/// ## 持久化一致性：已做到哪里、剩下什么
///
/// 这个类的写路径经过 31 轮 review 逐层加固，同一条失败链剥出了十几层
/// （静默 no-op → 抛错 → 惰性获取 → 写前加载 → 读前加载 → 抛了没人接 →
///  内存没回滚 → 回滚跨阶段 → 凭证值没还原 → 补偿互相拖累 → 缓存污染 →
///  并发覆盖 → 重入标志打穿串行）。**可用非事务手段能做的已经做完**：
///
/// - 所有写操作经 `_serializedWrite` 串行，复合操作整体入链
/// - 写前 / 读前都确保已加载，避免基于空快照判重或覆盖磁盘
/// - 失败回滚内存 + 凭证值 + 账户列表（缓存污染必须靠重写列表修复）
/// - 回滚按阶段划分：改动未生效才回滚，已生效只记日志
/// - 补偿动作彼此独立 best-effort，单 key 级也不互相拖累
/// - 失败诊断走 `AppLog.e`（不受 verbose 开关控制，且有独立落盘路径）
///
/// **剩余边界只能靠事务型存储解决**，继续叠 try/catch 不会收敛：
///
/// 1. 进程在多个 SharedPreferences key 写入之间退出 → 部分提交
/// 2. 进程在补偿执行期间退出 → 新旧混合值
/// 3. 列表提交后、旧凭证清理前退出 → 孤儿明文 key
/// 4. 平台写持续失败 → best-effort 恢复无法保证缓存与磁盘一致
///
/// 要消除这四条，需要事务日志 / 版本化快照 / 单 key 原子写
/// （把整个账户集合序列化进**一个** key），而不是继续加补偿分支。
/// 迁移到 Keychain 时正好一并处理（见类内 TODO）。
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

  Future<void>? _initFuture;

  Future<void> init() => _ensureLoaded();

  /// 任何**写**操作之前都必须走这里。
  ///
  /// 只惰性拿 prefs 是不够的（我上一版就是那样）：窗口可能在 AppService.init()
  /// 完成前就显示，用户进云账户页触发 _ensureAllProvidersExist → addAccount，
  /// 此时 _accounts 还是空的 —— _saveAccounts() 会把这个近乎空的列表写回磁盘，
  /// **覆盖用户原有的全部账户**。
  /// 讽刺的是改之前的 `_prefs?.setString` 静默 no-op 反而保护了数据。
  ///
  /// 用共享 Future 而不是布尔标志：并发调用（页面 initState 与 AppService.init
  /// 同时进行）必须等同一次加载，不能各加载一遍。
  Future<void> _ensureLoaded() async {
    if (_initialized) return;
    // 失败要复位，否则 `??=` 会把一个已完成(error)的 Future 永久缓存下来 ——
    // 后续每次调用都立刻重抛同一个错误，再也不会重试。
    // （实测：三次调用 attempts 一直是 1。）
    // SharedPreferences 首次获取只要瞬时失败一次，云账户功能就永久不可用。
    final f = _initFuture ??= _doInit();
    try {
      await f;
    } catch (_) {
      if (identical(_initFuture, f)) _initFuture = null;
      rethrow;
    }
  }

  Future<void> _doInit() async {
    // 测试注入点：模拟 SharedPreferences 首次获取瞬时失败。
    // 生产恒为 false，仅一次判断。
    if (debugFailInit) {
      throw StateError('debugFailInit: 强制初始化失败（仅测试）');
    }
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
    _initialized = true;
  }

  /// 重新加载账户数据（导入配置后调用）
  /// 也要进链：它 clear + 重建 _accounts。与进行中的 update 并发时，
  /// 那个 update 的补偿会基于被 reload 换掉的列表写回 —— 新凭证已落盘、
  /// metadata 却被旧数据覆盖，而调用方收到的是「成功」。
  Future<void> reload() => _serializedWrite(() => _reloadUnsafe());

  Future<void> _reloadUnsafe() async {
    _initialized = false;
    _initFuture = null;
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
    _initialized = true;
  }

  /// 仅供测试：模拟「进程重启后尚未 init」—— 清内存与初始化标志，不动磁盘。
  @visibleForTesting
  void debugResetForTest() {
    _accounts.clear();
    _initialized = false;
    _initFuture = null;
    _prefs = null;
  }

  /// 仅供测试：让 _clearCredentials 抛错，用来验证「清理失败不得拖垮列表恢复」。
  @visibleForTesting
  static bool debugFailClearCredentials = false;

  /// 仅供测试：与 debugFailAccountsWrites 配合，模拟「缓存已更新、平台写入失败」
  /// 这个真实故障形态（shared_preferences 先写缓存再 await 平台）。
  @visibleForTesting
  static bool debugFailAccountsWriteAfterCache = false;

  /// 仅供测试：让**前 N 次** _saveAccounts 抛错（凭证写入照常成功），
  /// 用来构造「凭证已就地覆盖、改动尚未提交」这个边界。
  ///
  /// 用计数而不是布尔：布尔会让回滚里那次 _saveAccounts 也抛 ——
  /// 于是「回滚写列表」这一步在测试里**从未真正执行过**，
  /// 它坏了也没人拦（探针实测 PROBE_ROLLBACK_LIST_OK 一次都没出现）。
  /// 设成 1 就只有首次失败，回滚那次照常成功。
  @visibleForTesting
  static int debugFailAccountsWrites = 0;

  /// 仅供测试：让「写账户列表成功之后」的步骤抛错，
  /// 用来验证删除的第二阶段失败时**不得**回滚。
  @visibleForTesting
  static bool debugFailAfterAccountsWrite = false;

  /// 仅供测试：让 _doInit 抛错，模拟 SharedPreferences 首次获取瞬时失败。
  @visibleForTesting
  static bool debugFailInit = false;

  /// 仅供测试：让所有落盘抛错，用来验证内存回滚。生产代码不要碰。
  @visibleForTesting
  static bool debugFailPersistence = false;

  /// 仅供测试：每写一个凭证字段前调用。用来在「已写了一部分」时抛，
  /// 构造孤儿凭证场景 —— 那是唯一能触发它的时序。生产恒为 null。
  @visibleForTesting
  static Future<void> Function()? debugBeforeCredentialWrite;

  Future<void> Function()? get _beforeCredentialWrite =>
      debugBeforeCredentialWrite;

  /// 取 prefs 用于**写入**。
  ///
  /// 惰性获取而不是要求先 init()：窗口可能在 AppService.init() 完成前就显示
  /// （托盘/重开路径各有一处 windowManager.show），用户此时进云账户页会触发
  /// _ensureAllProvidersExist → addAccount。
  /// - 用 `_prefs?.setString` 会静默什么都不写，调用方却拿到"成功" → 数据丢失
  /// - 直接抛 StateError 又会变成未处理异常 + 页面空白（我上一版就是这样）
  /// 惰性获取两者都避开：写入真正发生。
  Future<SharedPreferences> _requirePrefs() async {
    if (debugFailPersistence) {
      throw StateError('debugFailPersistence: 强制落盘失败（仅测试）');
    }
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// 写操作串行化。
  ///
  /// add/update/remove 都是「改内存 → 分几步落盘 → 失败则补偿」。
  /// 并发跑两个 update 时，先发那个失败后的补偿会用它的 previous 快照
  /// 覆盖掉后发那个**已经成功**的凭证与列表 —— 用户看到的是自己刚保存的改动
  /// 被莫名回退。UI 侧的开关没有防重入，这不是纯理论场景。
  ///
  /// 用 Future 链而不是加锁：Dart 单线程，只需保证「上一个写操作完全结束
  /// （含补偿）后才开始下一个」。异常不会打断链条 —— 每一环都自行兜住，
  /// 只把结果转交给各自的调用方。
  Future<void> _writeChain = Future.value();

  /// ⚠️ 不要用「布尔重入标志」来防自死锁 —— 我试过，它会把串行化打穿：
  /// 标志在链内 op 的**整个执行期**（含每个 await 间隙）都为 true，
  /// 此时外部调用会被误判成重入而直接执行，与链内操作并发。
  /// 对照实验：A 进入 await 后调 B，B 走 BYPASS，
  /// 执行顺序变成 A:start → B:start → A:end → B:end。
  ///
  /// 正解是**显式**：需要在链内做多步写的复合方法，自己整体入链，
  /// 并调用下面的 *Unsafe 版本；公开方法只是「入链 + 调 unsafe」的薄包装。
  Future<T> _serializedWrite<T>(Future<T> Function() op) {
    final done = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      try {
        done.complete(await op());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  // ── CRUD ──

  Future<String> addAccount(CloudAccount account) =>
      _serializedWrite(() => _addAccountUnsafe(account));

  Future<String> _addAccountUnsafe(CloudAccount account) async {
    await _ensureLoaded();
    // 先入内存再落盘：任一步抛异常都必须回滚，否则 UI 允许重试时会用新 uuid
    // 再追加一个，第二次成功就把两条一起持久化 —— 重复账户。
    _accounts.add(account);
    try {
      await _saveAccounts();
      await _saveCredentials(account);
    } catch (e) {
      _accounts.removeWhere((a) => a.id == account.id);
      try {
        // 必须先清凭证再回写账户列表：_saveCredentials 是逐字段写的，
        // 前几个 cloud_cred_<uuid>_* 可能已经落盘。账户 metadata 一旦删掉，
        // 这些 key 就再也定位不到（removeAccount 找不到它们），
        // 而用户重试会用新 uuid —— 旧密钥永久残留在 SharedPreferences 里。
        await _clearCredentials(account.id, account.credentials.keys);
      } catch (_) {}
      try {
        await _saveAccounts(); // 尽力把已落盘的账户列表改回去
      } catch (_) {}
      rethrow;
    }
    AppLog.d('CloudAccountService: added account ${account.id} (${account.providerId})');
    return account.id;
  }

  Future<void> updateAccount(CloudAccount account) =>
      _serializedWrite(() => _updateAccountUnsafe(account));

  Future<void> _updateAccountUnsafe(CloudAccount account) async {
    await _ensureLoaded();
    final idx = _accounts.indexWhere((a) => a.id == account.id);
    if (idx < 0) return;
    // 与 removeAccount 同理，按阶段划分 —— 这点第一版写错了两处：
    //   旧版把「清理旧凭证差集」放在最前面且不设防：它失败时凭证已被删掉
    //   一部分、内存却没动，留下残缺；
    //   又把 _saveAccounts 与 _saveCredentials 包在同一个 try 里回滚，
    //   而列表写成功后再回滚会造出「账户是旧的、凭证是新的」混合态。
    //
    //   阶段一 写凭证 + 写账户列表：都失败即「改动尚未生效」，回滚内存。
    //     顺序改成先写凭证再写列表 —— 列表是那份「什么算数」的真源，
    //     它最后落盘，前面失败时磁盘上仍是完整的旧状态。
    //   阶段二 清理旧凭证差集：此时改动已生效，只记日志不回滚，
    //     否则又是「复活出残缺对象」。
    final previous = _accounts[idx];
    final removed = previous.credentials.keys.toSet()
        .difference(account.credentials.keys.toSet());
    _accounts[idx] = account;
    try {
      await _saveCredentials(account);
      await _saveAccounts();
    } catch (e) {
      _accounts[idx] = previous;
      // 只回滚内存和列表是不够的：凭证存在 cloud_cred_<accountId>_<key>，
      // **account id 不变**，所以刚才那几笔写入是就地覆盖了旧值。
      // 必须把旧值写回，并清掉「新增字段」留下的孤儿。
      // 补偿动作各自 best-effort：串在同一个 try 里的话，
      // 「写回旧凭证」失败会让「清理新增字段」**根本不执行** ——
      // 而后者本来可能成功。两件事互相独立，不该互相拖累。
      try {
        await _saveCredentials(previous);
      } catch (e2) {
        AppLog.e('CloudAccountService: 账户 ${account.id} 旧凭证写回失败，'
            '磁盘可能是新旧混合值: $e2');
      }
      try {
        final added = account.credentials.keys.toSet()
            .difference(previous.credentials.keys.toSet());
        if (added.isNotEmpty) {
          await _clearCredentials(account.id, added);
        }
      } catch (e2) {
        AppLog.e('CloudAccountService: 账户 ${account.id} 更新失败后'
            '新增凭证字段清理失败（孤儿明文）: $e2');
      }
      // 第三个独立块：上面任一补偿失败都不该让它不执行。
      // _clearCredentials 现在会在逐 key 尝试完后聚合抛出 ——
      // 与写列表串在同一个 try 里的话，一个 key 删不掉就把缓存修复也一起废了。
      try {
        // 必须再写一次账户列表 —— 我一度以为这是冗余的，错了：
        // shared_preferences 的 _setValue 是**先更新 _preferenceCache、
        // 再 await 平台写入**，平台失败时缓存不回滚
        //（见 shared_preferences_legacy.dart 的 _setValue）。
        // 真实故障下磁盘是旧值、进程内缓存却已是新值 ——
        // 随后 reload() 会从缓存读出未提交的新 metadata。
        // 重写旧列表能把缓存改回去，并再试一次平台写入。
        //
        // 我之前用探针判定「没差别」，是因为注入点在碰 prefs **之前**就抛了，
        // 没有模拟真实故障 —— 探针没错，被验证的场景不对。
        await _saveAccounts();
      } catch (e2) {
        AppLog.e('CloudAccountService: 账户 ${account.id} 更新失败后'
            '账户列表恢复失败，缓存可能仍是未提交的新值: $e2');
      }
      rethrow;
    }

    if (removed.isNotEmpty) {
      try {
        if (debugFailAfterAccountsWrite) {
          throw StateError('debugFailAfterAccountsWrite（仅测试）');
        }
        // 避免删字段/改 schema 后残留明文 secret
        await _clearCredentials(account.id, removed);
      } catch (e) {
        AppLog.e('CloudAccountService: 账户 ${account.id} 已更新，'
            '但旧凭证字段清理失败（可能残留明文）: $e');
      }
    }
  }

  Future<void> removeAccount(String accountId) =>
      _serializedWrite(() => _removeAccountUnsafe(accountId));

  Future<void> _removeAccountUnsafe(String accountId) async {
    await _ensureLoaded();
    final account = getAccountById(accountId);
    if (account == null) return;
    // 删除分两个阶段，回滚只能针对第一阶段 —— 这点我第一版写错了：
    //   阶段一 写账户列表：失败 = 删除**尚未生效**，必须把账户放回内存，
    //     否则界面上消失、磁盘上还在，重启后"复活"，用户以为删除没生效。
    //   阶段二 清凭证：此时删除**已经落盘**。再把账户复活回来，
    //     等于造出一个凭证被部分清掉的残缺账户 —— 比留下孤儿凭证更糟。
    //     所以这里只记日志，不回滚。
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    _accounts.removeWhere((a) => a.id == accountId);
    try {
      await _saveAccounts();
    } catch (e) {
      _accounts.insert(idx.clamp(0, _accounts.length), account);
      // 与 update 同源：shared_preferences 先更新 _preferenceCache 再 await
      // 平台写入，失败时缓存不回滚 —— 只把账户插回内存的话，缓存里仍是
      // 「已删除」的列表，reload() 会读出这个未提交状态。
      try {
        await _saveAccounts();
      } catch (e2) {
        AppLog.e('CloudAccountService: 账户 $accountId 删除失败后'
            '列表恢复也失败，缓存可能仍是「已删除」: $e2');
      }
      rethrow;
    }
    try {
      if (debugFailAfterAccountsWrite) {
        throw StateError('debugFailAfterAccountsWrite（仅测试）');
      }
      await _clearCredentials(accountId, account.credentials.keys);
    } catch (e) {
      // 删除已生效，不回滚。凭证清理失败会留下孤儿明文，必须记下来。
      AppLog.e('CloudAccountService: 账户 $accountId 已删除，'
          '但凭证清理失败（可能残留明文）: $e');
    }

    // 清除指向已删账户的选择。同样属「删除已生效」的收尾阶段，不回滚；
    // 但必须兜住异常并记日志 —— 悬空的 selected ID 会让
    // effectiveAsrAccount() 找不到目标而落到推荐兜底，
    // 表现成「界面显示 A、实际跑 B」那类难查的问题。
    // 两个 setter 各自 best-effort：放在同一个 try 里的话，
    // ASR 清理失败会让 LLM 清理**根本不执行**，留下第二个悬空引用。
    if (ConfigService().selectedAsrAccountId == accountId) {
      try {
        await ConfigService().setSelectedAsrAccount(null);
      } catch (e) {
        AppLog.e('CloudAccountService: 账户 $accountId 已删除，'
            '但 ASR 选中项清理失败（悬空引用）: $e');
      }
    }
    if (ConfigService().selectedLlmAccountId == accountId) {
      try {
        await ConfigService().setSelectedLlmAccountId(null);
      } catch (e) {
        AppLog.d('CloudAccountService: 账户 $accountId 已删除，'
            '但 LLM 选中项清理失败（悬空引用）: $e');
      }
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
  Future<void> migrateDeepSeekModels() =>
      _serializedWrite(() => _migrateDeepSeekModelsUnsafe());

  Future<void> _migrateDeepSeekModelsUnsafe() async {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'deepseek_v4_account_migrated';
    if (prefs.getBool(flag) ?? false) return;
    for (final a in _accounts) {
      if (a.providerId != 'deepseek') continue;
      final m = a.credentials['model'];
      final mapped = ConfigService.mapRetiredDeepSeekModel(m);
      if (m != null && mapped != null && mapped != m) {
        a.credentials['model'] = mapped;
        await _updateAccountUnsafe(a);
        AppLog.d('[Migration] DeepSeek 账户模型 $m → deepseek-v4-flash');
      }
    }
    await prefs.setBool(flag, true);
  }

  Future<void> _loadAccounts() async {
    // 清空再加载：不清的话重入会把同一批账户追加两遍
    _accounts.clear();
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
    if (debugFailAccountsWrites > 0) {
      debugFailAccountsWrites--;
      if (debugFailAccountsWriteAfterCache) {
        // 模拟**真实**故障：先让 SharedPreferences 更新它的内存缓存，
        // 再抛错。shared_preferences 的 _setValue 就是这个顺序，且平台
        // 失败时缓存不回滚 —— 之前的注入在碰 prefs 之前就抛，
        // 根本没有污染缓存，于是「回滚写列表」测起来像是冗余的。
        final prefs = await _requirePrefs();
        await prefs.setString(_kAccountsKey,
            jsonEncode(_accounts.map((a) => a.toJson()).toList()));
      }
      throw StateError('debugFailAccountsWrites（仅测试）');
    }
    // 用 ! 而不是 ?.：_prefs 为空时静默什么都不写，调用方却拿到"成功" ——
    // 那是静默数据丢失。宁可抛出来让上层看见。
    final prefs = await _requirePrefs();
    final json = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_kAccountsKey, json);
  }

  Future<void> _saveCredentials(CloudAccount account) async {
    final prefs = await _requirePrefs();
    // 逐 key best-effort：某个 key 瞬时失败不该让后面的 key **根本不尝试**。
    // 全部试完再把失败聚合抛出，调用方的回滚逻辑不变。
    final failed = <String>[];
    Object? firstError;
    for (final entry in account.credentials.entries) {
      try {
        // 逐字段一个 hook：默认什么都不做，测试用它在「写了一部分」时抛，
        // 才构造得出孤儿凭证场景。不把注入逻辑塞进循环体本身 ——
        // 那样 first 标志之类纯测试用的分支会污染生产代码。
        await _beforeCredentialWrite?.call();
        await prefs.setString(
            'cloud_cred_${account.id}_${entry.key}', entry.value);
      } catch (e) {
        failed.add(entry.key);
        firstError ??= e;
      }
    }
    if (failed.isNotEmpty) {
      throw StateError('凭证写入失败: ${failed.join(", ")} (首个错误: $firstError)');
    }
  }

  Future<void> _clearCredentials(String accountId, Iterable<String> keys) async {
    // 同样惰性获取：静默不删等于明文密钥残留在 SharedPreferences 里
    final prefs = await _requirePrefs();
    // 逐 key best-effort：一个删不掉不该让其余的明文继续留着
    final failed = <String>[];
    Object? firstError;
    for (final key in keys) {
      try {
        // 注入点在**循环内**且只失败首个 key，模拟真实形态：
        // 逐 key 试、部分已删、最后聚合抛。放在方法开头整体抛是失真的 ——
        // 那样一个 key 都不会被删，而真实故障下其余 key 是删掉了的，
        // 两者对「明文是否残留」结论相反。
        //（第二十六轮我就栽在「注入没有模拟真实故障」上。）
        if (debugFailClearCredentials && failed.isEmpty) {
          throw StateError('debugFailClearCredentials（仅测试，只失败首个 key）');
        }
        await prefs.remove('cloud_cred_${accountId}_$key');
      } catch (e) {
        failed.add(key);
        firstError ??= e;
      }
    }
    if (failed.isNotEmpty) {
      throw StateError('凭证清理失败: ${failed.join(", ")} (首个错误: $firstError)');
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

  /// 整体入链：链外读 accounts 判重会看到别人尚未提交、随后可能回滚的
  /// 临时状态 —— 导入谎报成功或建出重复账户。内部必须调 *Unsafe，
  /// 调公开方法会排在自己后面永远等不到（自死锁）。
  Future<int> importFromFile(String filePath) =>
      _serializedWrite(() => _importFromFileUnsafe(filePath));

  Future<int> _importFromFileUnsafe(String filePath) async {
    // 复合操作必须在**任何读取之前**加载：下面用 getAccountByProviderId 判重，
    // 未加载时它恒为 null，于是每个磁盘上已有的 provider 都会被再建一条。
    // 单靠 addAccount 内部的 _ensureLoaded 不够 —— 那时判重已经做完了。
    //
    // 放在 try **之外**：里面的 catch 会把异常吞成 `return 0`，
    // 用户看到的是「文件里没内容」而不是「加载失败」，指向完全错误的方向。
    await _ensureLoaded();
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
          await _updateAccountUnsafe(CloudAccount(
            id: existing.id,
            providerId: existing.providerId,
            displayName: p.displayName ?? existing.displayName,
            credentials: merged,
            isEnabled: _shouldEnable(p.isEnabled ?? existing.isEnabled, merged),
            createdAt: existing.createdAt,
          ));
        } else {
          await _addAccountUnsafe(CloudAccount(
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

  Future<void> migrateFromLegacy() =>
      _serializedWrite(() => _migrateFromLegacyUnsafe());

  Future<void> _migrateFromLegacyUnsafe() async {
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
      await _addAccountUnsafe(account);
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
      await _addAccountUnsafe(account);
      migrated++;
    }

    // 同样不能静默：这个标志没写成功，下次启动会重跑迁移，
    // 而迁移里会 addAccount —— 可能造出重复账户。
    final prefs = await _requirePrefs();
    await prefs.setBool(_kMigratedKey, true);
    if (migrated > 0) {
      AppLog.d('CloudAccountService: migrated $migrated legacy accounts');
    }
  }
}
