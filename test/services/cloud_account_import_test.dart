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

  test('初始化失败后必须允许重试，不能永久卡在失败的 Future', () async {
    // `_initFuture ??= _doInit()` 会把已完成(error)的 Future 永久缓存，
    // 后续调用立刻重抛同一个错误 —— SharedPreferences 首次获取只要瞬时失败
    // 一次，云账户功能就永久不可用。（实测三次调用 attempts 一直是 1。）
    final svc = CloudAccountService();
    svc.debugResetForTest();

    CloudAccountService.debugFailPersistence = true;
    await expectLater(
      svc.addAccount(CloudAccount(
        id: 'retry-1', providerId: 'zhipu', displayName: 'r',
        isEnabled: false, credentials: {},
      )),
      throwsA(isA<StateError>()),
    );

    // 故障排除后应当能成功，而不是继续抛同一个错误
    CloudAccountService.debugFailPersistence = false;
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
