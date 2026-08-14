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
