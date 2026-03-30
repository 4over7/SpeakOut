import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../services/cloud_account_service.dart';
import '../services/llm_service.dart';
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
    _ensureAllProvidersExist();
    setState(() {
      _accounts = List.of(CloudAccountService().accounts);
      // 启用的排前面，禁用的排后面
      _accounts.sort((a, b) {
        if (a.isEnabled && !b.isEnabled) return -1;
        if (!a.isEnabled && b.isEnabled) return 1;
        return 0;
      });
    });
  }

  /// 确保所有服务商都有对应的账户条目（新用户首次打开时自动创建）
  void _ensureAllProvidersExist() {
    final service = CloudAccountService();
    final existingProviderIds = service.accounts.map((a) => a.providerId).toSet();
    for (final provider in CloudProviders.all) {
      if (!existingProviderIds.contains(provider.id)) {
        service.addAccount(CloudAccount(
          id: const Uuid().v4(),
          providerId: provider.id,
          displayName: provider.name,
          credentials: {},
          isEnabled: false,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部操作栏
          Row(
            children: [
              Text(loc.cloudAccountsTitle, style: AppTheme.heading(context)),
              const Spacer(),
              GestureDetector(
                onTap: () => _importAccounts(context),
                child: Text('导入', style: TextStyle(fontSize: 12, color: AppTheme.getAccent(context))),
              ),
              if (_accounts.isNotEmpty) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _exportAccounts(context),
                  child: Text('导出', style: TextStyle(fontSize: 12, color: AppTheme.getAccent(context))),
                ),
              ],
              const SizedBox(width: 12),
              PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => _showAddEditDialog(context, loc),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MacosIcon(CupertinoIcons.plus, size: 14),
                    const SizedBox(width: 4),
                    Text(loc.cloudAccountAdd),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 账户列表（所有服务商预置，填 key 才能启用）
          SettingsCardGrid(
            spacing: 8,
            runSpacing: 8,
            children: _accounts.map((a) => _buildAccountCard(a, loc)).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _importAccounts(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    final count = await CloudAccountService().importFromFile(result.files.single.path!);
    if (!mounted) return;
    _refreshAccounts();
    await showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.cloud_download, size: 48),
        title: const Text('导入完成'),
        message: Text(count > 0 ? '成功导入 $count 个云服务账户' : '没有新账户需要导入（已存在的服务商会跳过）'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ),
    );
  }

  Future<void> _exportAccounts(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出云服务账户',
      fileName: 'speakout_cloud_accounts.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    if (path == null) return;
    final ok = await CloudAccountService().exportToFile(path);
    if (!mounted) return;
    await showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: MacosIcon(ok ? CupertinoIcons.checkmark_circle : CupertinoIcons.xmark_circle, size: 48),
        title: Text(ok ? '导出成功' : '导出失败'),
        message: Text(ok ? '已导出 ${_accounts.length} 个云服务账户\n注意：文件含明文凭证，请妥善保管' : '写入文件失败'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ),
    );
  }

  Widget _buildAccountCard(CloudAccount account, AppLocalizations loc) {
    final provider = CloudProviders.getById(account.providerId);

    // 能力标签
    final capabilities = <String>[];
    if (provider != null) {
      if (provider.hasASR) capabilities.add(loc.cloudAccountCapabilityAsr);
      if (provider.hasLLM) capabilities.add(loc.cloudAccountCapabilityLlm);
    }

    final canEnable = provider != null && provider.hasAnyValidCredentials(account.credentials);
    final hasKeys = canEnable; // 是否已填写凭证

    return SettingsCard(
      padding: const EdgeInsets.all(12),
      children: [
        // Row 1: name + toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                account.displayName,
                style: AppTheme.body(context).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: account.isEnabled ? null : AppTheme.getTextSecondary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasKeys)
              MacosSwitch(
                value: account.isEnabled,
                onChanged: (v) async {
                  final updated = CloudAccount(
                    id: account.id, providerId: account.providerId,
                    displayName: account.displayName, credentials: account.credentials,
                    isEnabled: v, createdAt: account.createdAt,
                  );
                  await CloudAccountService().updateAccount(updated);
                  _refreshAccounts();
                },
              )
            else
              // 未配置凭证 → 显示"配置"按钮
              GestureDetector(
                onTap: () => _showAddEditDialog(context, loc, existingAccount: account),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.getAccent(context).withValues(alpha: 0.4)),
                  ),
                  child: Text('配置', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context), fontWeight: FontWeight.w500)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Row 2: tags + actions
        Row(
          children: [
            ...capabilities.map((c) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: (account.isEnabled ? AppTheme.getAccent(context) : MacosColors.systemGrayColor).withValues(alpha: 0.1),
                ),
                child: Text(c, style: TextStyle(
                  fontSize: 9,
                  color: account.isEnabled ? AppTheme.getAccent(context) : MacosColors.systemGrayColor,
                  fontWeight: FontWeight.w500,
                )),
              ),
            )),
            if (provider?.warning != null)
              const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 11, color: MacosColors.systemOrangeColor),
            const Spacer(),
            if (hasKeys) ...[
              GestureDetector(
                onTap: () => _showAddEditDialog(context, loc, existingAccount: account),
                child: Text('编辑', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
              ),
            ],
          ],
        ),
      ],
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
    final credControllers = <String, TextEditingController>{};
    List<(bool, String)> testResults = [];  // (success, message) per service
    bool testLoading = false;

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

    final visibleSecrets = <String>{};  // 当前可见的密钥字段

    showMacosSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            final provider = CloudProviders.getById(selectedProviderId);
            return MacosSheet(
              insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 40),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      isEdit ? loc.cloudAccountEdit : loc.cloudAccountAdd,
                      style: AppTheme.heading(builderContext),
                    ),
                    const SizedBox(height: 16),

                    // 可滚动内容区
                    Expanded(child: SingleChildScrollView(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 服务商选择（仅新建时可选，编辑时显示为只读文本）
                        Row(
                          children: [
                            Text('${loc.cloudAccountProvider}:', style: AppTheme.body(builderContext)),
                            const SizedBox(width: 12),
                            if (isEdit)
                              Expanded(
                                child: Text(
                                  CloudProviders.getById(selectedProviderId)?.name ?? selectedProviderId,
                                  style: AppTheme.body(builderContext).copyWith(color: MacosColors.systemGrayColor),
                                ),
                              )
                            else
                              Expanded(
                                child: MacosPopupButton<String>(
                                  value: selectedProviderId,
                                  items: CloudProviders.all.map((p) =>
                                    MacosPopupMenuItem(value: p.id, child: Text(p.name)),
                                  ).toList(),
                                  onChanged: (v) {
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

                        // 服务商警告
                        if (provider?.warning != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 14, color: MacosColors.systemOrangeColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(provider!.warning!, style: TextStyle(fontSize: 11, color: MacosColors.systemOrangeColor, height: 1.4))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // 凭证字段
                        if (provider != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _buildCredentialFieldsGrouped(provider, credControllers, visibleSecrets: visibleSecrets, setDialogState: setDialogState),
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
                                  MacosIcon(CupertinoIcons.question_circle, size: 14, color: AppTheme.getAccent(context)),
                                  const SizedBox(width: 4),
                                  Text(
                                    provider.helpUrl,
                                    style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ))),
                    const SizedBox(height: 16),

                    // 测试结果（每行一个服务）
                    if (testResults.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: testResults.map((r) {
                            final (ok, msg) = r;
                            final color = ok ? MacosColors.systemGreenColor : MacosColors.systemRedColor;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  MacosIcon(
                                    ok ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                                    size: 14, color: color,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: color), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    // 固定底部按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (provider != null && (provider.hasLLM || provider.hasASR)) ...[
                          PushButton(
                            controlSize: ControlSize.regular,
                            secondary: true,
                            onPressed: testLoading ? null : () async {
                              setDialogState(() { testLoading = true; testResults = []; });
                              final results = <(bool, String)>[];

                              // Test LLM
                              if (provider.hasLLM) {
                                final apiKey = credControllers[provider.llmApiKeyField]?.text ?? '';
                                if (apiKey.isNotEmpty) {
                                  final (ok, msg) = await LLMService().testConnectionWith(
                                    apiKey: apiKey,
                                    baseUrl: provider.llmBaseUrl ?? '',
                                    model: provider.llmDefaultModel ?? '',
                                    apiFormat: provider.llmApiFormat,
                                  );
                                  results.add((ok, 'LLM: $msg'));
                                } else {
                                  results.add((false, 'LLM: API Key 未填写'));
                                }
                              }

                              // Test ASR (check key presence only, no live connection test)
                              if (provider.hasASR) {
                                final asrFields = provider.credentialFields
                                    .where((f) => f.appliesTo(CloudCapability.asrStreaming) || f.appliesTo(CloudCapability.asrBatch))
                                    .toList();
                                final allFilled = asrFields.every((f) => (credControllers[f.key]?.text ?? '').isNotEmpty);
                                if (allFilled && asrFields.isNotEmpty) {
                                  results.add((true, 'ASR: 凭证已填写（需实际录音验证）'));
                                } else {
                                  results.add((false, 'ASR: 凭证未完整填写'));
                                }
                              }

                              setDialogState(() { testLoading = false; testResults = results; });
                            },
                            child: testLoading
                              ? const SizedBox(width: 16, height: 16, child: ProgressCircle(value: null))
                              : const Text('测试连接'),
                          ),
                          const Spacer(),
                        ],
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

                            // 凭证全空时自动禁用
                            final hasAnyCred = provider != null &&
                                provider.hasAnyValidCredentials(creds);

                            if (isEdit) {
                              final updated = CloudAccount(
                                id: existingAccount.id,
                                providerId: existingAccount.providerId,
                                displayName: displayName.isNotEmpty ? displayName : (provider?.name ?? selectedProviderId),
                                credentials: creds,
                                isEnabled: hasAnyCred && existingAccount.isEnabled,
                                createdAt: existingAccount.createdAt,
                              );
                              await CloudAccountService().updateAccount(updated);
                            } else {
                              final account = CloudAccount(
                                id: const Uuid().v4(),
                                providerId: selectedProviderId,
                                displayName: displayName.isNotEmpty ? displayName : (provider?.name ?? selectedProviderId),
                                credentials: creds,
                                isEnabled: hasAnyCred,
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
  Widget _buildCredentialFieldsGrouped(CloudProvider provider, Map<String, TextEditingController> controllers, {Set<String>? visibleSecrets, void Function(void Function())? setDialogState}) {
    final universal = provider.credentialFields.where((f) => f.scope.isEmpty).toList();
    final asrOnly = provider.credentialFields.where((f) => f.scope.contains(CloudCapability.asrStreaming) || f.scope.contains(CloudCapability.asrBatch)).toList();
    final llmOnly = provider.credentialFields.where((f) => f.scope.contains(CloudCapability.llm)).toList();

    final hasGroups = asrOnly.isNotEmpty || llmOnly.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 通用凭证（有分组时才显示标题）
        if (universal.isNotEmpty) ...[
          if (hasGroups) _buildSectionCard(
            icon: CupertinoIcons.lock_shield,
            label: '通用凭证',
            color: MacosColors.systemGrayColor,
            fields: universal,
            controllers: controllers,
            visibleSecrets: visibleSecrets,
            setDialogState: setDialogState,
          )
          else
            ..._buildFieldList(universal, controllers, visibleSecrets: visibleSecrets, setState: setDialogState),
        ],
        // ASR 凭证区域
        if (asrOnly.isNotEmpty) ...[
          if (universal.isNotEmpty) const SizedBox(height: 8),
          _buildSectionCard(
            icon: CupertinoIcons.waveform,
            label: '语音识别 (ASR)',
            color: MacosColors.systemBlueColor,
            fields: asrOnly,
            controllers: controllers,
            visibleSecrets: visibleSecrets,
            setDialogState: setDialogState,
          ),
        ],
        // LLM 凭证区域
        if (llmOnly.isNotEmpty) ...[
          if (universal.isNotEmpty || asrOnly.isNotEmpty) const SizedBox(height: 8),
          _buildSectionCard(
            icon: CupertinoIcons.sparkles,
            label: '大语言模型 (LLM)',
            color: MacosColors.systemOrangeColor,
            fields: llmOnly,
            controllers: controllers,
            visibleSecrets: visibleSecrets,
            setDialogState: setDialogState,
          ),
        ],
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String label,
    required Color color,
    required List<CredentialField> fields,
    required Map<String, TextEditingController> controllers,
    Set<String>? visibleSecrets,
    void Function(void Function())? setDialogState,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color.withValues(alpha: 0.5), width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分组标题
          Row(children: [
            MacosIcon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(label, style: AppTheme.caption(context).copyWith(fontWeight: FontWeight.w600, color: color)),
          ]),
          const SizedBox(height: 10),
          // 字段列表
          ..._buildFieldList(fields, controllers, visibleSecrets: visibleSecrets, setState: setDialogState),
        ],
      ),
    );
  }

  List<Widget> _buildFieldList(List<CredentialField> fields, Map<String, TextEditingController> controllers, {Set<String>? visibleSecrets, void Function(void Function())? setState}) {
    return fields.map((field) {
      final ctrl = controllers[field.key] ??= TextEditingController();
      final isObscured = field.isSecret && !(visibleSecrets?.contains(field.key) ?? false);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: MacosTextField(
                    placeholder: field.placeholder ?? field.label,
                    obscureText: isObscured,
                    controller: ctrl,
                  ),
                ),
                if (field.isSecret && setState != null)
                  MacosIconButton(
                    icon: MacosIcon(
                      isObscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                      size: 14,
                      color: MacosColors.systemGrayColor,
                    ),
                    backgroundColor: MacosColors.transparent,
                    onPressed: () => setState(() {
                      if (visibleSecrets!.contains(field.key)) {
                        visibleSecrets.remove(field.key);
                      } else {
                        visibleSecrets.add(field.key);
                      }
                    }),
                  ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }
}
