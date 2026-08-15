import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/cloud_account_service.dart';
import 'package:speakout/models/cloud_account.dart';

/// 导出/导入的三条语义，每条都对应一次真实事故：
/// 1. 导出不得带密钥值（v1.9.0 只修了 ConfigBackupService，这条同源路径漏了）
/// 2. 导入不得「已存在就跳过」（云账户页预建 15 家 → 导入永远 0 条，死功能）
/// 3. 空凭证账户不得被恢复成 enabled（会进 asrAccountPool 然后初始化失败）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('speakout_import_test');
    await CloudAccountService().reload();
  });
  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<String> writeBackup(List<Map<String, dynamic>> accounts) async {
    final f = File('${tmp.path}/b.json');
    await f.writeAsString(jsonEncode({
      'app': 'SpeakOut',
      'type': 'cloud_accounts',
      'version': 1,
      'accounts': accounts,
    }));
    return f.path;
  }

  test('update 落盘失败必须回滚内存 —— 否则显示的状态磁盘上并不存在', () async {
    // 先改内存再落盘、失败不回滚的话：内存是新值、磁盘是旧值。
    // 界面刷新会显示一个磁盘上并不存在的状态（开关显示"已启用"，重启又变回去）。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'upd-1', providerId: 'zhipu', displayName: '原名',
      isEnabled: false, credentials: {'api_key': 'k'},
    ));

    CloudAccountService.debugFailPersistence = true;
    addTearDown(() => CloudAccountService.debugFailPersistence = false);
    await expectLater(
      svc.updateAccount(CloudAccount(
        id: 'upd-1', providerId: 'zhipu', displayName: '改后',
        isEnabled: true, credentials: {'api_key': 'k'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugFailPersistence = false;

    expect(svc.getAccountById('upd-1')!.displayName, '原名',
        reason: '内存没回滚 —— 界面会显示一个磁盘上并不存在的值');
    expect(svc.getAccountById('upd-1')!.isEnabled, isFalse);
  });

  test('清理新增凭证失败，不得连带让账户列表恢复也不执行', () async {
    // 三个补偿动作必须各自独立。_clearCredentials 逐 key 尝试完后会聚合抛出 ——
    // 若它与「重写旧列表」串在同一个 try 里，一个 key 删不掉就把缓存修复也废了，
    // reload() 仍会读出未提交的新 metadata。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'iso-1', providerId: 'minimax', displayName: '旧名',
      isEnabled: false, credentials: {'api_key': 'k'},
    ));

    CloudAccountService.debugFailAccountsWriteAfterCache = true;
    CloudAccountService.debugFailAccountsWrites = 1;
    CloudAccountService.debugFailClearCredentials = true; // 补偿里的清理也失败
    addTearDown(() {
      CloudAccountService.debugFailAccountsWriteAfterCache = false;
      CloudAccountService.debugFailAccountsWrites = 0;
      CloudAccountService.debugFailClearCredentials = false;
    });
    await expectLater(
      svc.updateAccount(CloudAccount(
        id: 'iso-1', providerId: 'minimax', displayName: '新名',
        isEnabled: true, credentials: {'api_key': 'k', 'extra': 'X'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugFailAccountsWriteAfterCache = false;
    CloudAccountService.debugFailAccountsWrites = 0;
    CloudAccountService.debugFailClearCredentials = false;

    await svc.reload();
    expect(svc.getAccountById('iso-1')!.displayName, '旧名',
        reason: '清理失败把「重写旧列表」一起废掉了 —— '
            '缓存里仍是未提交的新 metadata');
  });

  test('update 失败时必须把账户列表写回 —— 缓存已被污染', () async {
    // shared_preferences 的 _setValue 先更新 _preferenceCache 再 await 平台写入，
    // 平台失败时**缓存不回滚**。所以真实故障下磁盘是旧值、缓存已是新值 ——
    // 不重写旧列表的话，reload() 会从缓存读出未提交的新 metadata。
    // 我之前用探针判定这行"冗余"，是因为注入点在碰 prefs 之前就抛了。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'cache-1', providerId: 'moonshot', displayName: '旧名',
      isEnabled: false, credentials: {'api_key': 'k'},
    ));

    CloudAccountService.debugFailAccountsWriteAfterCache = true;
    CloudAccountService.debugFailAccountsWrites = 1;
    addTearDown(() {
      CloudAccountService.debugFailAccountsWriteAfterCache = false;
      CloudAccountService.debugFailAccountsWrites = 0;
    });
    await expectLater(
      svc.updateAccount(CloudAccount(
        id: 'cache-1', providerId: 'moonshot', displayName: '新名',
        isEnabled: true, credentials: {'api_key': 'k'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugFailAccountsWriteAfterCache = false;
    CloudAccountService.debugFailAccountsWrites = 0;

    await svc.reload();
    expect(svc.getAccountById('cache-1')!.displayName, '旧名',
        reason: '缓存里残留着未提交的新 metadata —— 回滚没把旧列表写回去');
  });

  test('update 失败时凭证**值**也要还原 —— 它们是就地覆盖的', () async {
    // 凭证存在 cloud_cred_<accountId>_<key>，account id 不变，
    // 所以写新值等于就地覆盖旧值。只回滚内存和账户列表不够 ——
    // 重启后会读到「旧 metadata + 新凭证」的混合状态。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'cred-rb', providerId: 'gemini', displayName: 'n',
      isEnabled: false, credentials: {'api_key': 'OLD'},
    ));

    // 让写凭证成功、写账户列表失败 —— 正是「凭证已覆盖但改动未提交」的边界
    var writes = 0;
    CloudAccountService.debugBeforeCredentialWrite = () async { writes++; };
    addTearDown(() => CloudAccountService.debugBeforeCredentialWrite = null);
    CloudAccountService.debugFailAccountsWrites = 1; // 只失败首次，回滚那次要成功
    addTearDown(() => CloudAccountService.debugFailAccountsWrites = 0);
    await expectLater(
      svc.updateAccount(CloudAccount(
        id: 'cred-rb', providerId: 'gemini', displayName: 'n',
        isEnabled: false, credentials: {'api_key': 'NEW', 'extra': 'X'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugFailAccountsWrites = 0;
    expect(writes, greaterThan(0), reason: '前置条件：凭证确实写过');

    await svc.reload();
    final rb = svc.getAccountById('cred-rb');
    expect(rb, isNotNull, reason: '回滚后账户本身应该还在磁盘上');
    expect(rb!.displayName, 'n', reason: '账户列表没还原到磁盘');
    expect(rb.credentials['api_key'], 'OLD',
        reason: '凭证值没还原 —— 重启后是「旧 metadata + 新凭证」的混合状态');
    expect(rb.credentials.containsKey('extra'), isFalse,
        reason: '新增字段没清掉，留下孤儿明文');
  });

  test('update 第一阶段失败回滚、第二阶段失败不回滚', () async {
    // 与 remove 同构。第一版把「清理旧凭证差集」放最前面且不设防，
    // 又把写凭证与写列表包在同一个 try 里回滚 ——
    // 列表写成功后再回滚会造出「账户是旧的、凭证是新的」混合态。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'upd-2', providerId: 'gemini', displayName: '原名',
      isEnabled: false, credentials: {'api_key': 'k', 'legacy': 'old'},
    ));

    // 第一阶段失败 → 必须回滚
    CloudAccountService.debugFailPersistence = true;
    addTearDown(() => CloudAccountService.debugFailPersistence = false);
    await expectLater(
      svc.updateAccount(CloudAccount(
        id: 'upd-2', providerId: 'gemini', displayName: '改后',
        isEnabled: true, credentials: {'api_key': 'k'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugFailPersistence = false;
    expect(svc.getAccountById('upd-2')!.displayName, '原名',
        reason: '第一阶段失败必须回滚内存');

    // 第二阶段（清理旧凭证差集）失败 → 改动已生效，不得回滚
    CloudAccountService.debugFailAfterAccountsWrite = true;
    addTearDown(
        () => CloudAccountService.debugFailAfterAccountsWrite = false);
    await svc.updateAccount(CloudAccount(
      id: 'upd-2', providerId: 'gemini', displayName: '改后',
      isEnabled: true, credentials: {'api_key': 'k'},
    ));
    CloudAccountService.debugFailAfterAccountsWrite = false;
    expect(svc.getAccountById('upd-2')!.displayName, '改后',
        reason: '第二阶段失败不该回滚 —— 改动已经落盘了');
  });

  test('remove 第二阶段（清凭证）失败不得把账户复活 —— 删除已经落盘了', () async {
    // 删除分两阶段：写账户列表 → 清凭证。
    // 第二阶段失败时删除**已经生效**，把账户复活回来等于造出一个
    // 凭证被部分清掉的残缺账户，比留下孤儿凭证更糟。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'del-2', providerId: 'gemini', displayName: '两阶段',
      isEnabled: false, credentials: {'api_key': 'k'},
    ));

    // 只让清凭证那步失败：_clearCredentials 内部同样走 _requirePrefs，
    // 但账户列表已经先写成功了
    CloudAccountService.debugFailAfterAccountsWrite = true;
    addTearDown(
        () => CloudAccountService.debugFailAfterAccountsWrite = false);
    await svc.removeAccount('del-2');
    CloudAccountService.debugFailAfterAccountsWrite = false;

    expect(svc.getAccountById('del-2'), isNull,
        reason: '删除已经落盘，不该把账户复活成一个凭证残缺的对象');
    await svc.reload();
    expect(svc.getAccountById('del-2'), isNull,
        reason: '磁盘上也应该已删除');
  });

  test('remove 落盘失败必须把账户放回内存 —— 否则重启后它会「复活」', () async {
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'del-1', providerId: 'moonshot', displayName: '待删',
      isEnabled: false, credentials: {},
    ));

    CloudAccountService.debugFailPersistence = true;
    addTearDown(() => CloudAccountService.debugFailPersistence = false);
    await expectLater(
        svc.removeAccount('del-1'), throwsA(isA<StateError>()));
    CloudAccountService.debugFailPersistence = false;

    expect(svc.getAccountById('del-1'), isNotNull,
        reason: '删除失败却把内存里的账户抹掉了 —— 界面上消失、磁盘上还在，'
            '重启后又"复活"，用户以为删除没生效');
  });

  test('导入时加载失败必须抛出，不能被吞成「导入 0 条」', () async {
    // importFromFile 的 catch 会 `return 0`。若 _ensureLoaded() 写在 try 里，
    // 加载失败就变成「文件里没内容」—— 指向完全错误的方向。
    final svc = CloudAccountService();
    await svc.reload();
    final path = await writeBackup([
      {'providerId': 'deepseek', 'isEnabled': true,
       'credentials': {'api_key': 'k'}},
    ]);

    svc.debugResetForTest();
    CloudAccountService.debugFailInit = true;
    addTearDown(() => CloudAccountService.debugFailInit = false);
    await expectLater(svc.importFromFile(path), throwsA(isA<StateError>()),
        reason: '加载失败被吞成 return 0 了 —— 用户会以为文件是空的');
  });

  test('未初始化时导入，不得给磁盘上已有的 provider 重复建账户', () async {
    // 复合操作在**读取**时就要求已加载：importFromFile 用
    // getAccountByProviderId 判重，未加载时它恒为 null ——
    // 每个磁盘上已有的 provider 都会被再建一条。
    // 单靠 addAccount 内部的 _ensureLoaded 挡不住：那时判重已经做完了。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'disk-deepseek', providerId: 'deepseek', displayName: '磁盘上的',
      isEnabled: true, credentials: {'api_key': 'DISK-KEY'},
    ));

    // 模拟「重启后尚未 init」
    svc.debugResetForTest();

    final path = await writeBackup([
      {'providerId': 'deepseek', 'displayName': '导入的',
       'isEnabled': true, 'credentials': {'model': 'm'}},
    ]);
    await svc.importFromFile(path);

    await svc.reload();
    final deepseeks =
        svc.accounts.where((a) => a.providerId == 'deepseek').toList();
    expect(deepseeks.length, 1,
        reason: '给已有 provider 重复建了账户：${deepseeks.map((a) => a.id).toList()}');
    expect(deepseeks.first.credentials['api_key'], 'DISK-KEY',
        reason: '原有凭证应保留');
    expect(deepseeks.first.credentials['model'], 'm',
        reason: '导入的空缺字段应补上');
  });

  test('初始化失败后必须允许重试，不能永久卡在失败的 Future', () async {
    // `_initFuture ??= _doInit()` 会把已完成(error)的 Future 永久缓存，
    // 后续调用立刻重抛同一个错误 —— SharedPreferences 首次获取只要瞬时失败
    // 一次，云账户功能就永久不可用。（实测三次调用 attempts 一直是 1。）
    final svc = CloudAccountService();
    svc.debugResetForTest();

    // 注入的是**初始化**失败，不是落盘失败 —— 后者走 _requirePrefs，
    // 根本不经过 _doInit，构造不出「失败 Future 被缓存」的场景。
    //（我第一版就用错了注入点，导致这条测试验证不通过。）
    CloudAccountService.debugFailInit = true;
    addTearDown(() => CloudAccountService.debugFailInit = false);
    await expectLater(
      svc.addAccount(CloudAccount(
        id: 'retry-1', providerId: 'zhipu', displayName: 'r',
        isEnabled: false, credentials: {},
      )),
      throwsA(isA<StateError>()),
    );

    // 故障排除后应当能成功，而不是继续抛同一个错误
    CloudAccountService.debugFailInit = false;
    await svc.addAccount(CloudAccount(
      id: 'retry-2', providerId: 'zhipu', displayName: 'r2',
      isEnabled: false, credentials: {},
    ));
    expect(svc.getAccountById('retry-2'), isNotNull,
        reason: '初始化失败后被永久缓存，故障排除也恢复不了');
  });

  test('未初始化时写入不得覆盖磁盘上已有的账户', () async {
    // 真实时序：窗口可能在 AppService.init() 完成前就显示（托盘/重开路径），
    // 用户进云账户页 → _ensureAllProvidersExist → addAccount，
    // 此时 _accounts 还是空的。若直接 _saveAccounts()，那个近乎空的列表
    // 会把用户原有的全部账户**覆盖掉**。
    //
    // 讽刺的是：改成惰性获取之前的 `_prefs?.setString` 静默 no-op
    // 反而保护了数据 —— 所以「能写了」还不够，必须先加载。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'pre-existing', providerId: 'moonshot', displayName: '用户原有',
      isEnabled: true, credentials: {'api_key': 'USER-KEY'},
    ));

    // 模拟「进程重启后尚未 init」：清掉内存与初始化标志，磁盘保持不变
    svc.debugResetForTest();
    expect(svc.accounts, isEmpty, reason: '前置条件：内存应为空');

    // 未 init 直接写 —— 这正是页面 initState 抢跑的情形
    await svc.addAccount(CloudAccount(
      id: 'new-blank', providerId: 'zhipu', displayName: '新建',
      isEnabled: false, credentials: {},
    ));

    await svc.reload();
    expect(svc.getAccountById('pre-existing'), isNotNull,
        reason: '用户原有账户被这次写入覆盖了 —— 数据丢失');
    expect(svc.getAccountById('pre-existing')!.credentials['api_key'],
        'USER-KEY');
    expect(svc.getAccountById('new-blank'), isNotNull);
  });

  test('_prefs 未初始化时写入必须真正发生，而不是静默跳过', () async {
    // 窗口可能在 AppService.init() 完成前就显示（托盘/重开路径），
    // 用户此时进云账户页会触发 addAccount。
    // 旧实现 `_prefs?.setString` 静默什么都不写却返回成功 → 数据丢失；
    // 我上一版改成抛 StateError 又变成未处理异常 + 页面空白。
    // 正解是惰性获取：写入真正发生。
    final svc = CloudAccountService();
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'lazy-1', providerId: 'zhipu', displayName: 'z',
      isEnabled: false, credentials: {'api_key': 'k1'},
    ));
    // 重新加载一遍，证明是真落盘了而不是只在内存里
    await svc.reload();
    expect(svc.getAccountById('lazy-1'), isNotNull,
        reason: '写入没有真正落盘 —— 静默丢失');
    expect(svc.getAccountById('lazy-1')!.credentials['api_key'], 'k1');
  });

  test('落盘失败必须回滚内存，且不留孤儿凭证', () async {
    // addAccount 先入内存再落盘。失败不回滚的话，UI 重试会用新 uuid
    // 再追加一个，第二次成功就把两条一起持久化 —— 重复账户。
    // 而 _saveCredentials 是逐字段写的，回滚时若不清凭证，
    // 账户 metadata 一删这些 cloud_cred_<uuid>_* 就再也定位不到，明文永久残留。
    final svc = CloudAccountService();
    await svc.reload();
    final before = svc.accounts.length;

    CloudAccountService.debugFailPersistence = true;
    addTearDown(() => CloudAccountService.debugFailPersistence = false);
    await expectLater(
      svc.addAccount(CloudAccount(
        id: 'fail-1', providerId: 'deepseek', displayName: 'x',
        isEnabled: true, credentials: {'api_key': 'k', 'model': 'm'},
      )),
      throwsA(isA<StateError>()),
      reason: '落盘失败必须抛出来，不能静默成功',
    );
    expect(svc.accounts.length, before,
        reason: '失败后账户仍留在内存里 —— 重试会造出第二个重复账户');
    expect(svc.getAccountById('fail-1'), isNull);

  });

  test('凭证写到一半失败，回滚必须清掉已落盘的孤儿凭证', () async {
    // 这个场景只有「账户列表写成功、凭证写到第二个字段才失败」才构造得出 ——
    // 用 all 模式的话 _saveAccounts 第一步就抛，根本走不到写凭证。
    // （我第一版就是这么写的，导致「回滚不清凭证」的退化漏报。）
    final svc = CloudAccountService();
    await svc.reload();

    // 第一个字段放行、第二个字段抛 —— 这样才有「已落盘的孤儿」。
    // 用 all 模式的话 _saveAccounts 第一步就抛，根本走不到写凭证
    //（我第一版就是这么写的，导致「回滚不清凭证」的退化漏报）。
    var n = 0;
    CloudAccountService.debugBeforeCredentialWrite = () async {
      if (++n > 1) throw StateError('注入：凭证写到一半失败');
    };
    addTearDown(() => CloudAccountService.debugBeforeCredentialWrite = null);
    await expectLater(
      svc.addAccount(CloudAccount(
        id: 'orphan-1', providerId: 'deepseek', displayName: 'x',
        isEnabled: true, credentials: {'api_key': 'SECRET', 'model': 'm'},
      )),
      throwsA(isA<StateError>()),
    );
    CloudAccountService.debugBeforeCredentialWrite = null;

    final prefs = await SharedPreferences.getInstance();
    final orphans = prefs
        .getKeys()
        .where((k) => k.startsWith('cloud_cred_orphan-1_'))
        .toList();
    expect(orphans, isEmpty,
        reason: '账户 metadata 已删但凭证还在 —— 这些 key 再也定位不到，'
            '明文密钥永久残留：$orphans');

    // 还要验**磁盘上的账户列表**：addAccount 是「先写列表、后写凭证」，
    // 凭证失败时列表已经落盘 —— 回滚必须把它改回去，否则重启后会读出
    // 一个凭证为空的幽灵账户。
    // （原来这条测试只查凭证 key，去掉回滚里的写列表也不会红。）
    await svc.reload();
    expect(svc.getAccountById('orphan-1'), isNull,
        reason: '磁盘上的账户列表没回滚 —— 重启后会出现凭证为空的幽灵账户');
  });

  test('写入路径不得使用 `_prefs?.` —— 静默 no-op 等于数据丢失', () {
    // _saveCredentials / _clearCredentials 没法用行为测试隔离
    // （仓库里没有只调它们、不先调 _saveAccounts 的路径）。
    // 判据很窄：**写入**不得走可空调用；读取（getString/getBool）不在此列，
    // 读不到走默认值是正常语义。
    final src =
        File('lib/services/cloud_account_service.dart').readAsStringSync();
    final silent = <String>[];
    for (final line in src.split('\n')) {
      final t = line.trim();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      final m = RegExp(r'_prefs\?\.\s*(set\w+|remove)\(').firstMatch(t);
      if (m != null) silent.add(t);
    }
    expect(silent, isEmpty,
        reason: '这些写入用了 `_prefs?.`，_prefs 为空时什么都不写却返回成功：'
            '\n  ${silent.join("\n  ")}');
  });

  test('导出不含 credentials 值，只含字段名清单', () async {
    final svc = CloudAccountService();
    await svc.addAccount(CloudAccount(
      id: 'a1',
      providerId: 'deepseek',
      displayName: 'DS',
      isEnabled: true,
      credentials: {'api_key': 'sk-SUPER-SECRET-VALUE'},
    ));
    final path = '${tmp.path}/export.json';
    expect(await svc.exportToFile(path), isTrue);
    final raw = await File(path).readAsString();
    expect(raw.contains('sk-SUPER-SECRET-VALUE'), isFalse,
        reason: '导出文件里出现了明文密钥');
    expect(raw.contains('credentialKeys'), isTrue);
    expect(raw.contains('api_key'), isTrue, reason: '字段名清单应保留，供用户知道要重填哪些');
  });

  test('provider 已存在时合并而非跳过', () async {
    final svc = CloudAccountService();
    await svc.addAccount(CloudAccount(
      id: 'pre', providerId: 'deepseek', displayName: '预建',
      isEnabled: false, credentials: {},
    ));
    final path = await writeBackup([
      {'providerId': 'deepseek', 'displayName': '我的 DeepSeek',
       'isEnabled': true, 'credentials': {'api_key': 'sk-old-backup'}},
    ]);
    expect(await svc.importFromFile(path), 1, reason: '已存在就跳过会让导入恒为 0');
    final a = svc.getAccountByProviderId('deepseek')!;
    expect(a.displayName, '我的 DeepSeek');
    expect(a.credentials['api_key'], 'sk-old-backup');
  });

  test('不覆盖用户已填好的密钥，只补空缺', () async {
    final svc = CloudAccountService();
    await svc.addAccount(CloudAccount(
      id: 'pre', providerId: 'deepseek', displayName: 'x',
      isEnabled: true, credentials: {'api_key': 'sk-USER-CURRENT'},
    ));
    final path = await writeBackup([
      {'providerId': 'deepseek', 'isEnabled': true,
       'credentials': {'api_key': 'sk-STALE', 'model': 'deepseek-v4-flash'}},
    ]);
    await svc.importFromFile(path);
    final a = svc.getAccountByProviderId('deepseek')!;
    expect(a.credentials['api_key'], 'sk-USER-CURRENT', reason: '不该被备份里的旧值覆盖');
    expect(a.credentials['model'], 'deepseek-v4-flash', reason: '空缺应补上');
  });

  test('新格式（无密钥）导入后账户必须保持禁用', () async {
    final svc = CloudAccountService();
    await svc.addAccount(CloudAccount(
      id: 'pre', providerId: 'deepseek', displayName: 'x',
      isEnabled: false, credentials: {},
    ));
    final path = await writeBackup([
      {'providerId': 'deepseek', 'displayName': 'DS', 'isEnabled': true,
       'credentialKeys': ['api_key']},
    ]);
    await svc.importFromFile(path);
    final a = svc.getAccountByProviderId('deepseek')!;
    expect(a.isEnabled, isFalse,
        reason: '空凭证账户被启用会进 asrAccountPool()，选中后云端识别初始化失败');
  });

  test('单项坏数据只跳过该项，不影响其余项', () async {
    final svc = CloudAccountService();
    final path = await writeBackup([
      {'providerId': 'deepseek', 'isEnabled': true,
       'credentials': {'api_key': 'sk-good'}},
      {'providerId': 'openai', 'isEnabled': 'true'},   // 类型错：String 而非 bool
      {'providerId': 'zhipu', 'isEnabled': true,
       'credentials': {'api_key': 'sk-also-good'}},
    ]);
    expect(await svc.importFromFile(path), 2, reason: '坏项应被跳过，好项照常导入');
    expect(svc.getAccountByProviderId('deepseek')?.credentials['api_key'], 'sk-good');
    expect(svc.getAccountByProviderId('zhipu')?.credentials['api_key'], 'sk-also-good');
  });

  test('合并走副本，不就地改 _accounts 里的原对象', () async {
    // updateAccount 用「旧 keys - 新 keys」差集去清 SharedPreferences 里的残留密钥。
    // 若导入就地改 existing.credentials，差集恒为空，那道安全网静默失效。
    final svc = CloudAccountService();
    final original = CloudAccount(
      id: 'pre', providerId: 'deepseek', displayName: '原名',
      isEnabled: true, credentials: {'api_key': 'sk-user'},
    );
    await svc.addAccount(original);
    final path = await writeBackup([
      {'providerId': 'deepseek', 'displayName': '新名', 'isEnabled': true,
       'credentials': {'model': 'deepseek-v4-flash'}},
    ]);
    await svc.importFromFile(path);
    // 传给 updateAccount 的必须是新对象：原对象不该被就地改名
    expect(original.displayName, '原名',
        reason: '导入就地改了 _accounts 里的原对象，updateAccount 的差集清理会失效');
    expect(svc.getAccountByProviderId('deepseek')!.displayName, '新名');
  });

  test('坏项不得在抛异常前留下半改状态', () async {
    final svc = CloudAccountService();
    await svc.addAccount(CloudAccount(
      id: 'pre', providerId: 'openai', displayName: '原名',
      isEnabled: false, credentials: {},
    ));
    final path = await writeBackup([
      {'providerId': 'openai', 'displayName': '新名', 'isEnabled': 'true'}, // cast 会抛
    ]);
    await svc.importFromFile(path);
    expect(svc.getAccountByProviderId('openai')!.displayName, '原名',
        reason: '解析失败的项不该已经改掉实时对象的 displayName');
  });
}
