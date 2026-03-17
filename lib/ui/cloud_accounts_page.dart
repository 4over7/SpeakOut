import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../services/cloud_account_service.dart';
import '../config/cloud_providers.dart';
import '../models/cloud_account.dart';
import 'theme.dart';
import 'widgets/settings_widgets.dart';

/// 云服务账户管理页面
///
/// 嵌入 SettingsPage 中，提供账户 CRUD 操作。
class CloudAccountsPage extends StatefulWidget {
  const CloudAccountsPage({super.key});

  @override
  State<CloudAccountsPage> createState() => _CloudAccountsPageState();
}

class _CloudAccountsPageState extends State<CloudAccountsPage> {
  List<CloudAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    _refreshAccounts();
  }

  void _refreshAccounts() {
    setState(() {
      _accounts = CloudAccountService().accounts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          SettingsGroup(
            title: loc.cloudAccountsTitle,
            children: [
              if (_accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        MacosIcon(
                          CupertinoIcons.cloud,
                          size: 48,
                          color: MacosColors.systemGrayColor.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          loc.cloudAccountNone,
                          style: AppTheme.caption(context),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._buildAccountList(loc),
            ],
          ),

          const SizedBox(height: 16),

          // 添加按钮
          Center(
            child: PushButton(
              controlSize: ControlSize.regular,
              onPressed: () => _showAddEditDialog(context, loc),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MacosIcon(CupertinoIcons.plus_circle, size: 16),
                  const SizedBox(width: 6),
                  Text(loc.cloudAccountAdd),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAccountList(AppLocalizations loc) {
    final widgets = <Widget>[];
    for (int i = 0; i < _accounts.length; i++) {
      if (i > 0) widgets.add(const SettingsDivider());
      widgets.add(_buildAccountCard(_accounts[i], loc));
    }
    return widgets;
  }

  Widget _buildAccountCard(CloudAccount account, AppLocalizations loc) {
    final provider = CloudProviders.getById(account.providerId);
    final providerName = provider?.name ?? account.providerId;

    // 能力标签
    final capabilities = <String>[];
    if (provider != null) {
      if (provider.hasASR) capabilities.add(loc.cloudAccountCapabilityAsr);
      if (provider.hasLLM) capabilities.add(loc.cloudAccountCapabilityLlm);
    }

    // 遮掩凭证
    final maskedCred = account.credentials.entries.map((e) {
      final v = e.value;
      if (v.length <= 8) return '${e.key}: ****';
      return '${e.key}: ${v.substring(0, 4)}...${v.substring(v.length - 4)}';
    }).join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: MacosIcon(CupertinoIcons.cloud_fill, size: 20, color: AppTheme.accentColor),
            ),
          ),
          const SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.displayName,
                        style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!account.isEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: MacosColors.systemGrayColor.withValues(alpha: 0.15),
                        ),
                        child: Text(
                          loc.disabled,
                          style: const TextStyle(fontSize: 10, color: MacosColors.systemGrayColor),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(providerName, style: AppTheme.caption(context)),
                if (maskedCred.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    maskedCred,
                    style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (capabilities.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: capabilities.map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: AppTheme.accentColor.withValues(alpha: 0.1),
                      ),
                      child: Text(c, style: const TextStyle(fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.w500)),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          // 操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.pencil, size: 16),
                onPressed: () => _showAddEditDialog(context, AppLocalizations.of(context)!, existingAccount: account),
              ),
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.trash, size: 16, color: MacosColors.systemRedColor),
                onPressed: () => _confirmDelete(context, account, AppLocalizations.of(context)!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, CloudAccount account, AppLocalizations loc) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.trash, size: 48, color: MacosColors.systemRedColor),
        title: Text(loc.cloudAccountDeleteConfirm),
        message: Text(account.displayName),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          onPressed: () async {
            Navigator.of(context).pop();
            await CloudAccountService().removeAccount(account.id);
            _refreshAccounts();
          },
          child: Text(loc.cloudAccountDelete),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
      ),
    );
  }

  void _showAddEditDialog(BuildContext context, AppLocalizations loc, {CloudAccount? existingAccount}) {
    final isEdit = existingAccount != null;

    // 选中的服务商 ID
    String selectedProviderId = existingAccount?.providerId ?? CloudProviders.all.first.id;
    String displayName = existingAccount?.displayName ?? '';
    bool isEnabled = existingAccount?.isEnabled ?? true;
    final credControllers = <String, TextEditingController>{};

    // 初始化凭证控制器
    void initCredControllers(String providerId) {
      credControllers.clear();
      final provider = CloudProviders.getById(providerId);
      if (provider == null) return;
      for (final field in provider.credentialFields) {
        credControllers[field.key] = TextEditingController(
          text: existingAccount?.providerId == providerId
              ? existingAccount?.credentials[field.key] ?? ''
              : '',
        );
      }
    }

    initCredControllers(selectedProviderId);

    showMacosSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            final provider = CloudProviders.getById(selectedProviderId);
            return MacosSheet(
              insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      isEdit ? loc.cloudAccountEdit : loc.cloudAccountAdd,
                      style: AppTheme.heading(builderContext),
                    ),
                    const SizedBox(height: 20),

                    // 服务商选择（仅新建时可选）
                    Row(
                      children: [
                        Text('${loc.cloudAccountProvider}:', style: AppTheme.body(builderContext)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MacosPopupButton<String>(
                            value: selectedProviderId,
                            items: CloudProviders.all.map((p) =>
                              MacosPopupMenuItem(value: p.id, child: Text(p.name)),
                            ).toList(),
                            onChanged: isEdit ? null : (v) {
                              if (v == null) return;
                              setDialogState(() {
                                selectedProviderId = v;
                                final p = CloudProviders.getById(v);
                                displayName = p?.name ?? v;
                                initCredControllers(v);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 显示名称
                    Row(
                      children: [
                        Text('${loc.cloudAccountName}:', style: AppTheme.body(builderContext)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MacosTextField(
                            placeholder: provider?.name ?? '',
                            controller: TextEditingController(text: displayName),
                            onChanged: (v) => displayName = v,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 凭证字段
                    if (provider != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _buildCredentialFieldsGrouped(provider, credControllers),
                      ),
                      // 帮助链接
                      if (provider.helpUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(provider.helpUrl);
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          child: Row(
                            children: [
                              MacosIcon(CupertinoIcons.question_circle, size: 14, color: AppTheme.accentColor),
                              const SizedBox(width: 4),
                              Text(
                                provider.helpUrl,
                                style: TextStyle(fontSize: 11, color: AppTheme.accentColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // 启用开关
                    Row(
                      children: [
                        Text('${loc.cloudAccountEnabled}:', style: AppTheme.body(builderContext)),
                        const SizedBox(width: 12),
                        MacosSwitch(
                          value: isEnabled,
                          onChanged: (v) => setDialogState(() => isEnabled = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () {
                            for (final c in credControllers.values) { c.dispose(); }
                            Navigator.of(builderContext).pop();
                          },
                          child: Text(loc.cancel),
                        ),
                        const SizedBox(width: 8),
                        PushButton(
                          controlSize: ControlSize.regular,
                          onPressed: () async {
                            final creds = <String, String>{};
                            for (final entry in credControllers.entries) {
                              creds[entry.key] = entry.value.text;
                            }

                            if (isEdit) {
                              final updated = CloudAccount(
                                id: existingAccount.id,
                                providerId: existingAccount.providerId,
                                displayName: displayName.isNotEmpty ? displayName : (provider?.name ?? selectedProviderId),
                                credentials: creds,
                                isEnabled: isEnabled,
                                createdAt: existingAccount.createdAt,
                              );
                              await CloudAccountService().updateAccount(updated);
                            } else {
                              final account = CloudAccount(
                                id: const Uuid().v4(),
                                providerId: selectedProviderId,
                                displayName: displayName.isNotEmpty ? displayName : (provider?.name ?? selectedProviderId),
                                credentials: creds,
                                isEnabled: isEnabled,
                              );
                              await CloudAccountService().addAccount(account);
                            }

                            for (final c in credControllers.values) { c.dispose(); }
                            if (builderContext.mounted) Navigator.of(builderContext).pop();
                            _refreshAccounts();
                          },
                          child: Text(loc.saveApply),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Build credential fields grouped by scope (通用 / ASR / LLM)
  Widget _buildCredentialFieldsGrouped(CloudProvider provider, Map<String, TextEditingController> controllers) {
    final universal = provider.credentialFields.where((f) => f.scope.isEmpty).toList();
    final asrOnly = provider.credentialFields.where((f) => f.scope.contains(CloudCapability.asrStreaming) || f.scope.contains(CloudCapability.asrBatch)).toList();
    final llmOnly = provider.credentialFields.where((f) => f.scope.contains(CloudCapability.llm)).toList();

    // If all fields are universal (no scope), show flat list
    final hasGroups = asrOnly.isNotEmpty || llmOnly.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (universal.isNotEmpty) ...[
          if (hasGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('通用凭证', style: AppTheme.caption(context).copyWith(fontWeight: FontWeight.w600)),
            ),
          ..._buildFieldList(universal, controllers),
        ],
        if (asrOnly.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              MacosIcon(CupertinoIcons.waveform, size: 12, color: MacosColors.systemBlueColor),
              const SizedBox(width: 4),
              Text('语音识别 (ASR)', style: AppTheme.caption(context).copyWith(fontWeight: FontWeight.w600, color: MacosColors.systemBlueColor)),
            ]),
          ),
          ..._buildFieldList(asrOnly, controllers),
        ],
        if (llmOnly.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              MacosIcon(CupertinoIcons.sparkles, size: 12, color: MacosColors.systemOrangeColor),
              const SizedBox(width: 4),
              Text('大语言模型 (LLM)', style: AppTheme.caption(context).copyWith(fontWeight: FontWeight.w600, color: MacosColors.systemOrangeColor)),
            ]),
          ),
          ..._buildFieldList(llmOnly, controllers),
        ],
      ],
    );
  }

  List<Widget> _buildFieldList(List<CredentialField> fields, Map<String, TextEditingController> controllers) {
    return fields.map((field) {
      final ctrl = controllers[field.key] ??= TextEditingController();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            MacosTextField(
              placeholder: field.placeholder ?? field.label,
              obscureText: field.isSecret,
              controller: ctrl,
            ),
          ],
        ),
      );
    }).toList();
  }
}
