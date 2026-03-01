import 'package:flutter/material.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';

/// Linux 设置页面
///
/// Material Design 3 风格，功能与 macOS/Windows 设置页对应。
class LinuxSettingsPage extends StatefulWidget {
  const LinuxSettingsPage({super.key});

  @override
  State<LinuxSettingsPage> createState() => _LinuxSettingsPageState();
}

class _LinuxSettingsPageState extends State<LinuxSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final config = ConfigService();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loc?.settings ?? '设置'),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.keyboard), text: loc?.change ?? '快捷键'),
              Tab(icon: const Icon(Icons.mic), text: '语音引擎'),
              Tab(icon: const Icon(Icons.smart_toy), text: loc?.aiCorrection ?? 'AI 纠错'),
              Tab(icon: const Icon(Icons.language), text: loc?.language ?? '语言'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HotkeyTab(config: config),
            _ASRTab(config: config),
            _AITab(config: config, loc: loc),
            _LanguageTab(config: config, loc: loc),
          ],
        ),
      ),
    );
  }
}

class _HotkeyTab extends StatelessWidget {
  final ConfigService config;
  const _HotkeyTab({required this.config});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('按住说话 (PTT)'),
                subtitle: Text(config.pttKeyName),
                trailing: FilledButton.tonal(
                  child: const Text('更改'),
                  onPressed: () {
                    // TODO: 键盘监听弹窗
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Toggle 输入'),
                subtitle: Text(config.toggleInputKeyName),
                trailing: FilledButton.tonal(
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

class _ASRTab extends StatelessWidget {
  final ConfigService config;
  const _ASRTab({required this.config});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('当前引擎'),
                subtitle: Text(config.asrEngineType == 'aliyun' ? '阿里云' : 'Sherpa (离线)'),
              ),
              const Divider(height: 1),
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

class _AITab extends StatefulWidget {
  final ConfigService config;
  final AppLocalizations? loc;
  const _AITab({required this.config, required this.loc});

  @override
  State<_AITab> createState() => _AITabState();
}

class _AITabState extends State<_AITab> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('启用 AI 纠错'),
                  value: widget.config.aiCorrectionEnabled,
                  onChanged: (v) async {
                    await widget.config.setAiCorrectionEnabled(v);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'LLM API 地址',
                    hintText: widget.config.llmBaseUrl,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => widget.config.setLlmBaseUrl(v),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: '模型',
                    hintText: widget.config.llmModel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => widget.config.setLlmModel(v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageTab extends StatefulWidget {
  final ConfigService config;
  final AppLocalizations? loc;
  const _LanguageTab({required this.config, required this.loc});

  @override
  State<_LanguageTab> createState() => _LanguageTabState();
}

class _LanguageTabState extends State<_LanguageTab> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: RadioGroup<String>(
            groupValue: widget.config.appLanguage,
            onChanged: (String? v) async {
              if (v == null) return;
              await widget.config.setAppLanguage(v);
              setState(() {});
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  title: Text(widget.loc?.systemDefault ?? '跟随系统'),
                  value: 'system',
                ),
                RadioListTile<String>(
                  title: const Text('中文'),
                  value: 'zh',
                ),
                RadioListTile<String>(
                  title: const Text('English'),
                  value: 'en',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
