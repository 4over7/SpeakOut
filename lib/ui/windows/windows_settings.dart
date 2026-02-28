import 'package:fluent_ui/fluent_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';

/// Windows 设置页面
///
/// 使用 fluent_ui 的 Tab 风格，功能与 macOS settings_page.dart 对应。
class WindowsSettingsPage extends StatefulWidget {
  const WindowsSettingsPage({super.key});

  @override
  State<WindowsSettingsPage> createState() => _WindowsSettingsPageState();
}

class _WindowsSettingsPageState extends State<WindowsSettingsPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return NavigationView(
      pane: NavigationPane(
        selected: _currentIndex,
        onChanged: (i) => setState(() => _currentIndex = i),
        displayMode: PaneDisplayMode.top,
        header: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Text(loc?.settings ?? '设置', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.keyboard_classic),
            title: Text(loc?.change ?? '快捷键'),
            body: const _HotkeySection(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.microphone),
            title: const Text('语音引擎'),
            body: const _ASRSection(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.robot),
            title: Text(loc?.aiCorrection ?? 'AI 纠错'),
            body: const _AISection(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.globe),
            title: Text(loc?.language ?? '语言'),
            body: const _LanguageSection(),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Hotkey Section
// ============================================================
class _HotkeySection extends StatefulWidget {
  const _HotkeySection();

  @override
  State<_HotkeySection> createState() => _HotkeySectionState();
}

class _HotkeySectionState extends State<_HotkeySection> {
  @override
  Widget build(BuildContext context) {
    final config = ConfigService();

    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('快捷键')),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text('按住说话 (PTT)'),
                subtitle: Text(config.pttKeyName),
                trailing: Button(
                  child: const Text('更改'),
                  onPressed: () {
                    // TODO: 键盘监听弹窗
                  },
                ),
              ),
              const Divider(),
              ListTile(
                title: const Text('Toggle 输入'),
                subtitle: Text(config.toggleInputKeyName),
                trailing: Button(
                  child: const Text('更改'),
                  onPressed: () {
                    // TODO: 键盘监听弹窗
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ASR Engine Section
// ============================================================
class _ASRSection extends StatefulWidget {
  const _ASRSection();

  @override
  State<_ASRSection> createState() => _ASRSectionState();
}

class _ASRSectionState extends State<_ASRSection> {
  @override
  Widget build(BuildContext context) {
    final config = ConfigService();

    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('语音引擎')),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text('当前引擎'),
                subtitle: Text(config.asrEngineType == 'aliyun' ? '阿里云' : 'Sherpa (离线)'),
              ),
              const Divider(),
              ListTile(
                title: const Text('当前模型'),
                subtitle: Text(config.activeModelId),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// AI Correction Section
// ============================================================
class _AISection extends StatefulWidget {
  const _AISection();

  @override
  State<_AISection> createState() => _AISectionState();
}

class _AISectionState extends State<_AISection> {
  @override
  Widget build(BuildContext context) {
    final config = ConfigService();
    final loc = AppLocalizations.of(context);

    return ScaffoldPage.scrollable(
      header: PageHeader(title: Text(loc?.aiCorrection ?? 'AI 纠错')),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToggleSwitch(
                checked: config.aiCorrectionEnabled,
                onChanged: (v) async {
                  await config.setAiCorrectionEnabled(v);
                  setState(() {});
                },
                content: const Text('启用 AI 纠错'),
              ),
              const SizedBox(height: 16),
              InfoLabel(
                label: 'LLM API 地址',
                child: TextBox(
                  placeholder: config.llmBaseUrl,
                  onChanged: (v) => config.setLlmBaseUrl(v),
                ),
              ),
              const SizedBox(height: 12),
              InfoLabel(
                label: '模型',
                child: TextBox(
                  placeholder: config.llmModel,
                  onChanged: (v) => config.setLlmModel(v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Language Section
// ============================================================
class _LanguageSection extends StatefulWidget {
  const _LanguageSection();

  @override
  State<_LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends State<_LanguageSection> {
  @override
  Widget build(BuildContext context) {
    final config = ConfigService();
    final loc = AppLocalizations.of(context);

    return ScaffoldPage.scrollable(
      header: PageHeader(title: Text(loc?.language ?? '语言')),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _langOption(loc?.systemDefault ?? '跟随系统', 'system', config),
              const SizedBox(height: 8),
              _langOption('中文', 'zh', config),
              const SizedBox(height: 8),
              _langOption('English', 'en', config),
            ],
          ),
        ),
      ],
    );
  }

  Widget _langOption(String label, String langCode, ConfigService config) {
    return GestureDetector(
      onTap: () async {
        await config.setAppLanguage(langCode);
        setState(() {});
      },
      child: Row(
        children: [
          Icon(
            config.appLanguage == langCode
                ? FluentIcons.radio_btn_on
                : FluentIcons.radio_btn_off,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
