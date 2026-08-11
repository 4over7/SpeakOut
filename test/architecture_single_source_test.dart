import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 架构约束测试：某些「唯一真源」必须真的唯一。
///
/// 起因是一次真实事故 —— UI 直读 selectedAsrAccountId 自己做回退（取池中第一个），
/// Engine 走推荐顺序，于是界面显示火山、实际连阿里云；而且那个「已选中」从不落盘。
/// 后来收敛到 CloudAccountService.effectiveAsrAccount()，
/// 但 codex 审查指出：**光有收敛挡不住下一个人再写一遍直读** ——
/// 事实上当时语言过滤那两处就漏掉了，测试全绿也发现不了。
///
/// 所以这里用源码级断言把入口钉死：只有真源本身可以碰原始 key。
void main() {
  /// 允许直接读取该 key 的文件（真源与其存取层）
  const asrAllowed = {
    'lib/services/config_service.dart',      // getter/setter 定义处
    'lib/services/cloud_account_service.dart', // effectiveAsrAccount 内部
  };

  /// 只看真实代码行 —— 注释里提到这个名字（比如解释「不要直读」的注释本身）不算违规
  bool hasRealUsage(String src, String needle) {
    for (var line in src.split('\n')) {
      final t = line.trim();
      if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;
      // 去掉行尾注释再判断
      final code = t.contains('//') ? t.substring(0, t.indexOf('//')) : t;
      if (code.contains(needle)) return true;
    }
    return false;
  }

  List<String> filesWithRealUsage(String needle, Set<String> allowed) {
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('l10n/generated')) continue;
      if (allowed.any((a) => e.path.endsWith(a))) continue;
      if (hasRealUsage(e.readAsStringSync(), needle)) hits.add(e.path);
    }
    return hits;
  }

  test('除真源外，任何地方不得直读 selectedAsrAccountId', () {
    final hits = filesWithRealUsage('selectedAsrAccountId', asrAllowed);
    expect(
      hits,
      isEmpty,
      reason: '这些文件绕过了 CloudAccountService.effectiveAsrAccount()，'
          '会再次出现「界面显示 A、实际用 B」：\n  ${hits.join("\n  ")}',
    );
  });

  test('UI 不得自己拼 ASR 账户池（应调 asrAccountPool）', () {
    // 判据要精确到「取账户」这个动作；按能力筛 CredentialField 是另一回事，不算
    final hits = filesWithRealUsage(
        'getAccountsWithCapability(CloudCapability.asrStreaming)', const {});
    expect(hits.where((p) => p.contains('/ui/')), isEmpty,
        reason: 'UI 自行拼装账户池会与 Engine 的口径漂移：\n  ${hits.join("\n  ")}');
  });
}
