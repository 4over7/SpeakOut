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

  test('任一落盘方法都不得静默 no-op（_prefs 为空必须抛）', () async {
    // `_prefs?.setString(...)` 在 _prefs 为空时什么都不写，调用方却拿到"成功" ——
    // 静默数据丢失。上面那条回滚测试只要有**任意一个**方法抛就会通过，
    // 挡不住「只有一个改回 ?. 」的退化，所以这里逐个方法单独验。
    final svc = CloudAccountService();
    await svc.reload();
    svc.debugSetPrefsForTest(null);

    // _saveAccounts 路径（removeAccount 只调它，不调 _saveCredentials）
    await svc.reload();
    await svc.addAccount(CloudAccount(
      id: 'probe', providerId: 'zhipu', displayName: 'p',
      isEnabled: false, credentials: {},
    ));
    svc.debugSetPrefsForTest(null);
    await expectLater(svc.removeAccount('probe'), throwsA(isA<StateError>()),
        reason: '_saveAccounts 在 _prefs 为空时静默 no-op 了');

    // _saveCredentials 没法用行为测试隔离：仓库里没有「只调它、不调
    // _saveAccounts」的路径，后者必先抛。改用一条精确的源码断言补上 ——
    // 判据很窄（写入不得用 `_prefs?.`），不是那种能被等价改写绕过的宽泛规则。
    final src =
        File('lib/services/cloud_account_service.dart').readAsStringSync();
    final silentWrites = RegExp(r'_prefs\?\.\s*set\w+\(')
        .allMatches(src)
        .map((m) => m.group(0)!)
        .toList();
    expect(silentWrites, isEmpty,
        reason: '写入用了 `_prefs?.` —— _prefs 为空时静默什么都不写，'
            '调用方却拿到"成功"，等于静默数据丢失：$silentWrites');
  });

  test('落盘失败必须回滚内存，否则重试会造出重复账户', () async {
    // addAccount 先把账户加进 _accounts 再落盘。若落盘抛异常而不回滚，
    // UI 的重试会用新 uuid 再追加一个，第二次成功时两条一起持久化。
    // 这里用「未初始化的 _prefs」构造落盘失败 —— 它现在会抛 StateError
    // 而不是像以前那样 `_prefs?.setString` 静默 no-op（静默 = 数据丢失）。
    final svc = CloudAccountService();
    await svc.reload();
    final before = svc.accounts.length;

    // 把 prefs 置空：模拟未初始化 / 平台通道不可用
    svc.debugSetPrefsForTest(null);
    await expectLater(
      svc.addAccount(CloudAccount(
        id: 'fail-1', providerId: 'deepseek', displayName: 'x',
        isEnabled: true, credentials: {'api_key': 'k'},
      )),
      throwsA(isA<StateError>()),
      reason: '落盘失败必须抛出来，不能静默成功',
    );
    expect(svc.accounts.length, before,
        reason: '失败后账户仍留在内存里 —— 重试会造出第二个重复账户');
    expect(svc.getAccountById('fail-1'), isNull);
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
