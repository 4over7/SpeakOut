import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../theme.dart';
import '../widgets/settings_widgets.dart';
import 'tabs/mode_tab.dart';
import 'tabs/trigger_tab.dart';
import 'tabs/service_tab.dart';
import 'tabs/general_tab.dart';
import 'tabs/about_tab.dart';

/// Settings page — 5 horizontal tabs: Mode | Trigger | Service | General | About
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;
  final GlobalKey<ModeTabState> _modeTabKey = GlobalKey<ModeTabState>();

  Future<void> _onTabChanged(int newIndex) async {
    // Guard: warn if leaving Mode tab with unsaved LLM changes
    if (_selectedIndex == 0 && newIndex != 0) {
      final modeState = _modeTabKey.currentState;
      if (modeState != null && modeState.hasUnsavedChanges) {
        final action = await _showUnsavedChangesDialog();
        if (action == null) return; // cancelled
        if (action) {
          await modeState.saveChanges();
        } else {
          modeState.discardChanges();
        }
      }
    }
    setState(() => _selectedIndex = newIndex);
  }

  /// Returns true=save, false=discard, null=cancel
  Future<bool?> _showUnsavedChangesDialog() {
    return showMacosAlertDialog<bool>(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 48, color: MacosColors.systemOrangeColor),
        title: const Text("有未保存的修改"),
        message: const Text("AI 润色配置尚未保存，是否保存后再切换？"),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("保存"),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("放弃"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return MacosWindow(
      backgroundColor: AppTheme.getBackground(context),
      disableWallpaperTinting: true,
      child: MacosScaffold(
        backgroundColor: AppTheme.getBackground(context),
        toolBar: ToolBar(
          title: Text(loc.settings),
          titleWidth: 150.0,
        ),
        children: [
          ContentArea(
            builder: (context, _) {
              return Container(
                color: AppTheme.getBackground(context),
                child: Column(
                  children: [
                    // Horizontal tab bar
                    SettingsHorizontalTabs(
                      selectedIndex: _selectedIndex,
                      onTabChanged: (i) => _onTabChanged(i),
                      tabs: [
                        SettingsTabItem(icon: CupertinoIcons.waveform_circle_fill, label: loc.tabWorkMode),
                        SettingsTabItem(icon: CupertinoIcons.hand_draw, label: loc.tabTrigger),
                        SettingsTabItem(icon: CupertinoIcons.cloud, label: loc.tabCloudAccounts),
                        SettingsTabItem(icon: CupertinoIcons.settings, label: loc.tabGeneral),
                        SettingsTabItem(icon: CupertinoIcons.info_circle, label: loc.tabAbout),
                      ],
                    ),
                    // Tab content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildTabContent(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedIndex) {
      case 0:
        return ModeTab(
          key: _modeTabKey,
          onNavigateToTab: (i) => _onTabChanged(i),
        );
      case 1:
        return TriggerTab(
          onNavigateToTab: (i) => _onTabChanged(i),
        );
      case 2:
        return const ServiceTab();
      case 3:
        return GeneralTab(
          onNavigateToTab: (i) => _onTabChanged(i),
        );
      case 4:
        return const AboutTab();
      default:
        return const SizedBox.shrink();
    }
  }
}
