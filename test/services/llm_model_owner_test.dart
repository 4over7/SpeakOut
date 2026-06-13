import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';

/// C2：LLM model 与账户绑定（owner-tagging），防止切 provider 后旧 model 名污染新 provider
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('C2: LLM model owner 标记', () {
    test('setLlmModel 记录当前 selectedLlmAccountId 为 owner', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService().reload();
      await ConfigService().setSelectedLlmAccountId('acc-openai');
      await ConfigService().setLlmModel('gpt-4o-mini');
      expect(ConfigService().llmModelOverride, 'gpt-4o-mini');
      expect(ConfigService().llmModelOwnerAccountId, 'acc-openai');
    });

    test('切 account 未重选 model 时 owner 仍指向旧 account（resolve 会用 provider 默认）', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService().reload();
      await ConfigService().setSelectedLlmAccountId('acc-openai');
      await ConfigService().setLlmModel('gpt-4o-mini');
      // 切到另一个账户但没重选 model
      await ConfigService().setSelectedLlmAccountId('acc-deepseek');
      expect(ConfigService().llmModelOverride, 'gpt-4o-mini');
      expect(ConfigService().llmModelOwnerAccountId, 'acc-openai');
      // owner ≠ 当前 account → _resolveLlmConfig 不会把旧 model 打到新 provider
      expect(ConfigService().llmModelOwnerAccountId == ConfigService().selectedLlmAccountId, false);
    });

    test('migrateLlmModelOwner 给历史全局 model 打当前 account 标记', () async {
      SharedPreferences.setMockInitialValues({
        'llm_model': 'legacy-model',
        'selected_llm_account_id': 'acc-x',
      });
      await ConfigService().reload();
      await ConfigService().migrateLlmModelOwner();
      expect(ConfigService().llmModelOwnerAccountId, 'acc-x');
    });
  });
}
