import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/cloud_account_service.dart';
import 'package:speakout/services/config_service.dart';

/// effectiveAsrAccount() 是 UI 与 Engine 共用的**唯一真源**。
///
/// 它存在的原因是一次真实事故：两边各写各的回退 —— UI 取池中第一个
/// （界面画出「火山引擎已选中」），Engine 按推荐顺序（实际连 dashscope），
/// 于是显示的和真正在跑的不是一个。更早之前 ASR 干脆没有兜底，
/// 用户切云端会掉进 legacy Aliyun NLS 分支报 "Aliyun Config Missing"。
///
/// 这两个回归都不会让编译或 analyze 失败，只能靠测试守住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 账户顺序刻意让 volcengine 排在 dashscope 前面 ——
  // 「池中第一个」与「推荐顺序第一个」必须能区分开，否则测不出那个 bug
  Map<String, Object> prefsWith({
    bool dashscopeKey = true,
    bool volcengineKey = true,
  }) {
    final accounts = [
      {
        'id': 'acc-volc', 'providerId': 'volcengine', 'displayName': '火山引擎 (豆包)',
        'isEnabled': true, 'createdAt': '2026-01-01T00:00:00.000',
        'credentialKeys': ['api_key', 'asr_api_key'],
      },
      {
        'id': 'acc-dash', 'providerId': 'dashscope', 'displayName': '阿里云百炼',
        'isEnabled': true, 'createdAt': '2026-01-02T00:00:00.000',
        'credentialKeys': ['api_key'],
      },
    ];
    final map = <String, Object>{'cloud_accounts': jsonEncode(accounts)};
    if (volcengineKey) {
      map['cloud_cred_acc-volc_api_key'] = 'vk';
      map['cloud_cred_acc-volc_asr_api_key'] = 'vk-asr';
    }
    if (dashscopeKey) map['cloud_cred_acc-dash_api_key'] = 'dk';
    return map;
  }

  /// ConfigService 是 singleton 且 init() 幂等，setMockInitialValues 换掉 store 后
  /// 它仍持有旧实例 —— 所以账户数据走 mock prefs，而「已选账户」必须用 setter 注入。
  Future<void> load(Map<String, Object> prefs, {String? selectedAsrId}) async {
    SharedPreferences.setMockInitialValues(prefs);
    await ConfigService().init();
    await CloudAccountService().reload();
    await ConfigService().setSelectedAsrAccount(selectedAsrId);
  }

  test('没显式选过时按推荐顺序，而不是池中第一个', () async {
    await load(prefsWith());
    final pool = CloudAccountService().asrAccountPool();
    expect(pool.first.providerId, 'volcengine', reason: '池顺序应为账户列表顺序');

    final eff = CloudAccountService().effectiveAsrAccount();
    expect(eff?.providerId, 'dashscope',
        reason: 'dashscope 在推荐顺序里靠前，不能退化成 pool.first');
  });

  test('显式选择优先于推荐顺序', () async {
    await load(prefsWith(), selectedAsrId: 'acc-volc');
    expect(CloudAccountService().effectiveAsrAccount()?.id, 'acc-volc',
        reason: '用户主动选过就必须尊重');
  });

  test('保存的 id 已失效时回退，而不是返回 null', () async {
    await load(prefsWith(), selectedAsrId: 'acc-gone');
    final eff = CloudAccountService().effectiveAsrAccount();
    expect(eff, isNotNull, reason: '失效 id 不该让云端 ASR 整个不可用');
    expect(eff?.providerId, 'dashscope');
  });

  test('凭证不完整的账户不被推荐', () async {
    // 只有 volcengine 有凭证；dashscope 虽在推荐序更前，但 key 为空
    await load(prefsWith(dashscopeKey: false));
    expect(CloudAccountService().pickRecommendedAsrAccount()?.providerId,
        'volcengine',
        reason: '推荐必须要求凭证完整，否则选出来也连不上');
  });

  test('火山的 ASR 凭证按能力判断，不是只看 api_key', () async {
    // 缺 asr_api_key（火山 ASR 专用），只有通用 api_key
    final prefs = prefsWith(dashscopeKey: false);
    prefs.remove('cloud_cred_acc-volc_asr_api_key');
    await load(prefs);
    expect(CloudAccountService().pickRecommendedAsrAccount(), isNull,
        reason: '火山 ASR 需要独立的 asr_api_key，缺了就不该被推荐');
  });

  test('无可用账户时返回 null', () async {
    await load({});
    expect(CloudAccountService().effectiveAsrAccount(), isNull);
    expect(CloudAccountService().asrAccountPool(), isEmpty);
  });
}
