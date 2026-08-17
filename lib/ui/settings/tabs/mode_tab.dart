import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../services/config_service.dart';
import '../../../services/llm_service.dart';
import '../../../services/cloud_account_service.dart';
import '../../../config/app_constants.dart';
import '../../../config/cloud_providers.dart';
import '../../../models/cloud_account.dart';
import '../../../services/app_service.dart';
import '../../../services/engine_types.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../../vocab_settings_page.dart';
import '../settings_shared.dart';
import '../sidebar/sidebar_shell.dart';
import '../../../services/notification_service.dart';

/// Which subset of mode_tab to render.
/// `all` — legacy 5-tab settings page (default).
/// `recognition` — v1.8 sidebar 识别引擎 page: mode selector + language + models + aliyun.
/// `aiPlus` — v1.8 sidebar AI Plus page: LLM 配置独立视图.
enum ModeTabView { all, recognition, aiPlus }

class ModeTab extends StatefulWidget {
  final ModeTabView viewFilter;

  const ModeTab({
    super.key,
    this.viewFilter = ModeTabView.all,
  });

  @override
  State<ModeTab> createState() => ModeTabState();
}

class ModeTabState extends State<ModeTab> {
  final AppService _app = AppService();

  // Model management
  final Map<String, bool> _downloadedStatus = {};
  final Map<String, bool> _hasLocalCopy = {};
  final Set<String> _downloadingIds = {};
  final Map<String, double?> _downloadProgressMap = {};
  final Map<String, String> _downloadStatusMap = {};
  String? _activatingId;
  String? _activeModelId;

  // Aliyun config
  final TextEditingController _akIdController = TextEditingController();
  final TextEditingController _akSecretController = TextEditingController();
  final TextEditingController _appKeyController = TextEditingController();

  // AI prompt
  late final TextEditingController _aiPromptController;
  late final TextEditingController _organizePromptController;

  // LLM config controllers
  final TextEditingController _llmApiKeyController = TextEditingController();
  final TextEditingController _llmBaseUrlController = TextEditingController();
  final TextEditingController _llmModelController = TextEditingController();
  final TextEditingController _llmCustomModelController = TextEditingController();
  bool _llmModelCustom = false;

  // Hotkey capture state
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  bool _isCapturingKey = false;
  String _toggleInputKeyName = '';
  bool _isCapturingToggleInputKey = false;
  int _toggleMaxDuration = 0;
  HotkeyCapturer? _keyCapturer;

  // Misc
  bool _llmConfigDirty = false;
  bool _workModeAdvancedExpanded = false;

  static const String _kCustomModelSentinel = '__custom__';

  // --- Public API for parent shell ---

  bool get hasUnsavedChanges => _llmConfigDirty;

  Future<void> saveChanges() async {
    await _flushLlmControllers();
    await ConfigService().savePresetConfig(ConfigService().llmPresetId);
    if (!mounted) return;
    setState(() => _llmConfigDirty = false);
  }

  void discardChanges() {
    _syncLlmControllers();
    setState(() => _llmConfigDirty = false);
  }

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    _aiPromptController = TextEditingController(text: ConfigService().aiCorrectionPrompt);
    _organizePromptController = TextEditingController(text: ConfigService().organizePrompt);
    _refresh();
    _loadActiveModel();
    _loadAliyunConfig();
    _loadHotkeyConfig();
  }

  @override
  void dispose() {
    _keyCapturer?.cancel();
    _akIdController.dispose();
    _akSecretController.dispose();
    _appKeyController.dispose();
    _aiPromptController.dispose();
    _organizePromptController.dispose();
    _llmApiKeyController.dispose();
    _llmBaseUrlController.dispose();
    _llmModelController.dispose();
    _llmCustomModelController.dispose();
    super.dispose();
  }

  // --- Data loading ---

  Future<void> _loadActiveModel() async {
    setState(() => _activeModelId = ConfigService().activeModelId);
  }

  Future<void> _loadAliyunConfig() async {
    final s = ConfigService();
    setState(() {
      _akIdController.text = s.aliyunAccessKeyId;
      _akSecretController.text = s.aliyunAccessKeySecret;
      _appKeyController.text = s.aliyunAppKey;
    });
  }

  // ---------------------------------------------------------------------------
  // Hotkey config
  // ---------------------------------------------------------------------------

  void _loadHotkeyConfig() {
    final service = ConfigService();
    setState(() {
      _currentKeyCode = service.pttKeyCode;
      _currentKeyName = service.pttKeyName;
      _toggleInputKeyName = service.toggleInputKeyName;
      _toggleMaxDuration = service.toggleMaxDuration;
    });
    AppService().pttKeyCode = _currentKeyCode;
  }

  void _startKeyCapture([String target = 'ptt']) {
    // 取消之前可能的捕获
    _keyCapturer?.cancel();
    setState(() {
      switch (target) {
        case 'toggleInput':
          _isCapturingToggleInputKey = true;
        default:
          _isCapturingKey = true;
      }
    });

    _keyCapturer = HotkeyCapturer(
      keyStream: _app.rawKeyEventStream,
      onCaptured: (keyCode, modifierFlags) {
        final keyName = mapKeyCodeToString(keyCode);
        _saveHotkeyConfig(keyCode, keyName, modifierFlags: modifierFlags);
        _resetCaptureState();
      },
      onTimeout: _resetCaptureState,
    )..start();
  }

  void _resetCaptureState() {
    if (mounted) {
      setState(() {
        _isCapturingKey = false;
        _isCapturingToggleInputKey = false;
      });
    }
  }

  void _stopKeyCapture() {
    _keyCapturer?.cancel();
    _keyCapturer = null;
    _resetCaptureState();
  }

  Future<void> _saveHotkeyConfig(int keyCode, String keyName,
      {int modifierFlags = 0}) async {
    final config = ConfigService();
    final requiredMods = stripOwnModifier(keyCode, modifierFlags);
    final displayName =
        requiredMods != 0 ? comboKeyName(keyCode, requiredMods) : keyName;

    // Conflict check — PTT 和 Toggle 允许共键（短按=toggle，长按=PTT）
    final activeKeys = getActiveHotkeys(context, excludeFeature: _isCapturingKey ? 'ptt' : 'toggleInput');
    // 额外排除 PTT↔Toggle 互相（它们可以相同）
    final c = ConfigService();
    if (_isCapturingKey) activeKeys.remove((c.toggleInputKeyCode, c.toggleInputModifiers));
    if (_isCapturingToggleInputKey) activeKeys.remove((c.pttKeyCode, c.pttModifiers));
    final hotkeyId = (keyCode, requiredMods);
    final conflictWith = findHotkeyConflict(activeKeys, hotkeyId);
    if (conflictWith != null) {
      _stopKeyCapture();
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        showMacosAlertDialog(
          context: context,
          builder: (_) => MacosAlertDialog(
            appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: Colors.orange),
            title: Text(loc.hotkeyInUseTitle(displayName, conflictWith),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            message: Text(loc.hotkeyConflictTaken),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: Text(loc.hotkeyInUseOk),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
      return;
    }

    if (_isCapturingToggleInputKey) {
      await config.setToggleInputKey(keyCode, displayName,
          modifiers: requiredMods);
      if (!mounted) return;
      setState(() {
        _toggleInputKeyName = displayName;
        _isCapturingToggleInputKey = false;
      });
    } else {
      // PTT key
      await config.setPttKey(keyCode, displayName, modifiers: requiredMods);
      AppService().pttKeyCode = keyCode;
      if (!mounted) return;
      setState(() {
        _currentKeyCode = keyCode;
        _currentKeyName = displayName;
        _isCapturingKey = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Compact UI helpers (hotkey section)
  // ---------------------------------------------------------------------------

  Widget _compactRow(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body(context).copyWith(fontSize: 12)),
          trailing,
        ],
      ),
    );
  }

  Widget _hotkeyBadge(String keyName,
      {bool isCapturing = false,
      VoidCallback? onTap,
      VoidCallback? onClear}) =>
      hotkeyBadge(context, keyName,
          isCapturing: isCapturing, onTap: onTap, onClear: onClear);

  Widget _compactDivider() {
    return Divider(
      height: 12,
      color: MacosColors.separatorColor.withValues(alpha: 0.3),
    );
  }

  Widget _buildHotkeyCard(AppLocalizations loc) {
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          const Text('⌨️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(loc.shortcutsAndDuration, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        _compactRow(loc.shortcutsPttTitle, _hotkeyBadge(
          _currentKeyName,
          isCapturing: _isCapturingKey,
          onTap: () => _startKeyCapture(),
        )),
        const SizedBox(height: 6),
        _compactRow(loc.shortcutsToggleTitle, _hotkeyBadge(
          _toggleInputKeyName,
          isCapturing: _isCapturingToggleInputKey,
          onTap: () => _startKeyCapture('toggleInput'),
          onClear: _toggleInputKeyName.isEmpty ? null : () async {
            await ConfigService().clearToggleInputKey();
            if (!mounted) return;
            setState(() => _toggleInputKeyName = '');
          },
        )),
        _compactDivider(),
        _compactRow(loc.toggleMaxDuration, MacosPopupButton<int>(
          value: _toggleMaxDuration,
          items: [
            MacosPopupMenuItem(value: 0, child: Text(loc.toggleMaxNone, style: const TextStyle(fontSize: 12))),
            MacosPopupMenuItem(value: 60, child: Text(loc.toggleMaxMin(1), style: const TextStyle(fontSize: 12))),
            MacosPopupMenuItem(value: 180, child: Text(loc.toggleMaxMin(3), style: const TextStyle(fontSize: 12))),
            MacosPopupMenuItem(value: 300, child: Text(loc.toggleMaxMin(5), style: const TextStyle(fontSize: 12))),
            MacosPopupMenuItem(value: 600, child: Text(loc.toggleMaxMin(10), style: const TextStyle(fontSize: 12))),
          ],
          onChanged: (v) async {
            if (v != null) { await ConfigService().setToggleMaxDuration(v); if (!mounted) return;
                                                                            setState(() => _toggleMaxDuration = v); }
          },
        )),
      ],
    );
  }

  Future<void> _refresh() async {
    for (var m in AppService.allModels) {
      _downloadedStatus[m.id] = await _app.isModelDownloaded(m.id);
      _hasLocalCopy[m.id] = await _app.hasLocalCopy(m.id);
    }
    _downloadedStatus[AppService.punctuationModelId] = await _app.isPunctuationModelDownloaded();
    if (!mounted) return;
    setState(() {});
  }

  // --- Download & Actions ---

  Future<void> _download(ModelInfo model) async {
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _downloadingIds.add(model.id);
      _downloadProgressMap[model.id] = 0;
      _downloadStatusMap[model.id] = loc.preparing;
    });

    try {
      await _app.downloadAndExtractModel(model.id,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgressMap[model.id] = p < 0 ? null : p;
              _downloadStatusMap[model.id] = p < 0
                  ? loc.modeExtracting
                  : loc.downloading((p * 100).toStringAsFixed(0));
            });
          }
        },
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      if (!context.mounted) return;
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(model.id); });
    }
  }

  Future<void> _activate(ModelInfo model) async {
    // Check if switching between streaming <-> offline mode
    final currentModel = _app.getModelById(_activeModelId ?? '');
    final isCrossModeSwitch = currentModel != null && currentModel.isOffline != model.isOffline;

    if (isCrossModeSwitch && mounted) {
      final loc = AppLocalizations.of(context)!;
      final title = model.isOffline ? loc.switchToOfflineTitle : loc.switchToStreamingTitle;
      final body = model.isOffline ? loc.switchToOfflineBody : loc.switchToStreamingBody;

      final confirmed = await showMacosAlertDialog<bool>(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: MacosIcon(
            model.isOffline ? CupertinoIcons.waveform_path_ecg : CupertinoIcons.waveform,
            size: 48,
          ),
          title: Text(title),
          message: Text(body),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.confirm),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.cancel),
          ),
        ),
      );
      if (confirmed != true) return;
    }

    final previousModelId = _activeModelId;
    if (!mounted) return;
    setState(() => _activatingId = model.id);
    await _app.setActiveModel(model.id);
    final path = await _app.getActiveModelPath();
    if (path != null) {
      try {
        await _app.initASR(modelPath: path, type: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
      } catch (e) {
        // Init failed -> rollback
        if (previousModelId != null) {
          await _app.setActiveModel(previousModelId);
          await ConfigService().setActiveModelId(previousModelId);
        }
        if (!mounted) return;
        setState(() { _activatingId = null; });
        if (mounted) {
          final loc = AppLocalizations.of(context)!;
          showSettingsError(context, loc.modelActivateFailed('$e'));
        }
        return;
      }
      // Model has no built-in punctuation -> prompt user + auto-load punctuation model
      if (!model.hasPunctuation) {
        final punctPath = await _app.getPunctuationModelPath();
        if (punctPath != null) {
          await _app.initPunctuation(punctPath, activeModelName: model.name);
          if (mounted) {
            showSettingsInfo(AppLocalizations.of(context)!.punctAutoLoaded);
          }
        } else if (mounted) {
          final loc = AppLocalizations.of(context)!;
          final confirmed = await showMacosAlertDialog<bool>(
            context: context,
            builder: (_) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.textformat_abc, size: 48),
              title: Text(loc.punctMissingTitle),
              message: Text(loc.punctMissingMsg),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context, true),
                child: Text(loc.punctDownload),
              ),
              secondaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context, false),
                child: Text(loc.punctSkip),
              ),
            ),
          );
          if (confirmed == true) {
            _downloadPunctuation();
          }
        }
      }
    }
    await ConfigService().setActiveModelId(model.id);
    if (!mounted) return;
    setState(() { _activatingId = null; _activeModelId = model.id; });
  }

  Future<void> _delete(ModelInfo model) async {
    await _app.deleteModel(model.id);
    if (!mounted) return;
    // deleteModel 可能因删除的是 active 模型而切换了 active_model_id，UI 同步重读
    setState(() => _activeModelId = ConfigService().activeModelId);
    await _refresh();
  }

  Future<void> _importModel(ModelInfo model) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final result = await const MethodChannel('com.SpeakOut/overlay')
          .invokeMethod<String>('pickFile');
      if (result == null || result.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _downloadingIds.add(model.id);
        _downloadProgressMap[model.id] = null;
        _downloadStatusMap[model.id] = loc.importing;
      });

      await _app.importModel(model.id, result,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgressMap[model.id] = p < 0 ? null : p;
              _downloadStatusMap[model.id] = p < 0 ? loc.unzipping : loc.importing;
            });
          }
        },
        onStatus: (s) {
          if (mounted) setState(() => _downloadStatusMap[model.id] = s);
        },
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      if (!context.mounted) return;
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(model.id); });
    }
  }

  Future<void> _downloadPunctuation() async {
    final loc = AppLocalizations.of(context)!;
    final punctId = AppService.punctuationModelId;

    setState(() {
      _downloadingIds.add(punctId);
      _downloadProgressMap[punctId] = 0;
      _downloadStatusMap[punctId] = loc.preparing;
    });

    try {
      await _app.downloadPunctuationModel(
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgressMap[punctId] = p;
              _downloadStatusMap[punctId] = loc.downloading((p * 100).toStringAsFixed(0));
            });
          }
        },
        onStatus: (s) {
          if (mounted) {
            setState(() { _downloadStatusMap[punctId] = s; });
          }
        },
      );
      await _refresh();
      final path = await _app.getPunctuationModelPath();
      if (path != null) await _app.initPunctuation(path);
    } catch (e) {
      if (!mounted) return;
      if (!context.mounted) return;
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(punctId); });
    }
  }

  Future<void> _deletePunctuation() async {
    await _app.deletePunctuationModel();
    await _refresh();
  }

  // --- Work Mode switching ---

  /// 云端账户 / 模型下拉切换后重建 ASR。
  /// 选择已经落盘了，initASR 抛出来就必须让用户看见 ——
  /// 否则下拉框显示新账户、引擎还连着旧的，跟 v1.10.0 那批「显示 A 跑 B」同源。
  Future<void> _reinitCloudAsr() async {
    try {
      await _app.initASR(modelPath: '', type: 'aliyun');
    } catch (e) {
      if (!mounted) return;
      if (context.mounted) {
        showSettingsError(context, AppLocalizations.of(context)!.modelActivateFailed('$e'));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchWorkMode(String? mode) async {
    if (mode == null) return;
    final oldMode = ConfigService().workMode;
    await ConfigService().setWorkMode(mode);

    // Reset input language if current selection is not supported by cloud ASR model
    if (mode == 'cloud') {
      final cloudModel = _getCurrentCloudAsrModel();
      final inputLang = ConfigService().inputLanguage;
      if (cloudModel != null && inputLang != 'auto' && !cloudModel.supportsLanguage(inputLang)) {
        await ConfigService().setInputLanguage('auto');
      }
    }

    // Re-init ASR when switching between sherpa <-> aliyun
    // 必须 try/catch：workMode 已经落盘了，initASR 再抛出来的话异常直接跑进
    // 全局 zone —— 下面的 setState 不执行，UI 停在旧模式，而配置里已经是新模式。
    // 「显示 A 跑 B」正是 v1.10.0 修过一轮的那类问题，不要再放回来。
    try {
      if (mode == 'cloud' && oldMode != 'cloud') {
        await _app.initASR(modelPath: '', type: 'aliyun');
      } else if (mode != 'cloud' && oldMode == 'cloud') {
        final path = await _app.getActiveModelPath();
        final model = _app.getModelById(_activeModelId ?? '');
        if (path != null && model != null) {
          await _app.initASR(modelPath: path, type: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
          // Model has no built-in punctuation -> auto-load punctuation model
          if (!model.hasPunctuation && !_app.isPunctuationEnabled) {
            final punctPath = await _app.getPunctuationModelPath();
            if (punctPath != null) {
              await _app.initPunctuation(punctPath, activeModelName: model.name);
            }
          }
        }
      }
    } catch (e) {
      // 回滚到旧模式，别让配置停在一个引擎起不来的状态
      await ConfigService().setWorkMode(oldMode);
      if (!mounted) return;
      setState(() {});
      if (context.mounted) {
        showSettingsError(context, AppLocalizations.of(context)!.modelActivateFailed('$e'));
      }
      return;
    }
    if (!mounted) return;
    setState(() {});
  }

  // --- LLM controllers sync ---

  void _syncLlmControllers() {
    _llmApiKeyController.text = ConfigService().llmApiKeyOverride ?? '';
    _llmBaseUrlController.text = ConfigService().llmBaseUrlOverride ?? '';
    _llmModelController.text = ConfigService().llmModelOverride ?? '';
  }

  Future<void> _flushLlmControllers() async {
    try {
      await ConfigService().setLlmApiKey(_llmApiKeyController.text);
    } catch (e) {
      LLMService().log("FLUSH: setLlmApiKey failed: $e");
    }
    await ConfigService().setLlmBaseUrl(_llmBaseUrlController.text);
    await ConfigService().setLlmModel(_llmModelController.text);
    LLMService().log("FLUSH: done, keyLen=${_llmApiKeyController.text.length}");
  }

  // --- Language helpers ---

  String _langDisplayName(String code, AppLocalizations loc) {
    return switch (code) {
      'zh' => loc.langZh,
      'en' => loc.langEn,
      'ja' => loc.langJa,
      'ko' => loc.langKo,
      'yue' => loc.langYue,
      'zh-Hans' => loc.langZhHans,
      'zh-Hant' => loc.langZhHant,
      'es' => loc.langEs,
      'fr' => loc.langFr,
      'de' => loc.langDe,
      'ru' => loc.langRu,
      'pt' => loc.langPt,
      _ => code,
    };
  }

  Map<String, String> _buildInputLanguageItems(AppLocalizations loc) {
    final allItems = {
      'auto': loc.langAutoDetect,
      'zh': loc.langZh,
      'en': loc.langEn,
      'ja': loc.langJa,
      'ko': loc.langKo,
      'yue': loc.langYue,
      'es': loc.langEs,
      'fr': loc.langFr,
      'de': loc.langDe,
      'ru': loc.langRu,
      'pt': loc.langPt,
    };

    // In cloud mode, filter by current ASR model's supported languages
    if (ConfigService().workMode == 'cloud') {
      final cloudAsrModel = _getCurrentCloudAsrModel();
      if (cloudAsrModel != null && cloudAsrModel.supportedLanguages.isNotEmpty) {
        return Map.fromEntries(allItems.entries.where((e) =>
          e.key == 'auto' || cloudAsrModel.supportsLanguage(e.key)));
      }
    }
    return allItems;
  }

  CloudASRModel? _getCurrentCloudAsrModel() {
    // 必须与 Engine 实际使用的账户一致：直读 selectedAsrAccountId 时，
    // 用户没显式选过就拿不到账户 → 语言过滤整个失效，
    // 界面会放出该服务商并不支持的语言而不给任何提示
    final asrAccount = CloudAccountService().effectiveAsrAccount();
    if (asrAccount == null) return null;
    final asrProvider = CloudProviders.getById(asrAccount.providerId);
    if (asrProvider == null) return null;
    final asrModelId = ConfigService().selectedAsrModelId;
    return asrProvider.asrModels
        .where((m) => m.id == asrModelId).firstOrNull
        ?? (asrProvider.asrModels.isNotEmpty ? asrProvider.asrModels.first : null);
  }

  List<Widget> _buildLanguageHints(AppLocalizations loc) {
    final hints = <Widget>[];
    final isTranslation = _isTranslationMode();
    final workMode = ConfigService().workMode;
    final inputLang = ConfigService().inputLanguage;
    final modelId = ConfigService().activeModelId;

    // 1. 翻译需要 AI 润色（LLM 翻译），与本地/云端识别模式无关
    if (isTranslation) {
      if (!ConfigService().aiCorrectionEnabled) {
        hints.add(_languageHintBanner(
          loc.translationNeedsSmartMode,
          color: MacosColors.systemOrangeColor,
          icon: CupertinoIcons.exclamationmark_triangle,
        ));
      } else {
        hints.add(_languageHintBanner(
          loc.translationModeHint,
          color: MacosColors.systemBlueColor,
          icon: CupertinoIcons.arrow_right_arrow_left,
        ));
      }
    }

    // 2. Input language not supported by current offline model
    if (inputLang != 'auto' && workMode != 'cloud') {
      final model = AppService.allModels.where((m) => m.id == modelId).firstOrNull;
      if (model != null && !model.supportsLanguage(inputLang)) {
        final langName = _langDisplayName(inputLang, loc);
        hints.add(_languageHintBanner(
          loc.inputLangModelHint(langName),
          color: MacosColors.systemOrangeColor,
          icon: CupertinoIcons.exclamationmark_triangle,
        ));
      }
    }

    // 3. Input language not supported by current cloud ASR provider
    if (inputLang != 'auto' && workMode == 'cloud') {
      {
        final asrAccount = CloudAccountService().effectiveAsrAccount();
        if (asrAccount != null) {
          final asrProvider = CloudProviders.getById(asrAccount.providerId);
          if (asrProvider != null) {
            final asrModelId = ConfigService().selectedAsrModelId;
            final asrModel = asrProvider.asrModels
                .where((m) => m.id == asrModelId).firstOrNull
                ?? (asrProvider.asrModels.isNotEmpty ? asrProvider.asrModels.first : null);
            if (asrModel != null && !asrModel.supportsLanguage(inputLang)) {
              hints.add(_languageHintBanner(
                loc.cloudAsrLangUnsupported,
                color: MacosColors.systemOrangeColor,
                icon: CupertinoIcons.exclamationmark_triangle,
              ));
            }
          }
        }
      }
    }

    return hints;
  }

  Widget _languageHintBanner(String text, {required Color color, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MacosIcon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  bool _isTranslationMode() {
    final input = ConfigService().inputLanguage;
    final output = ConfigService().outputLanguage;
    if (output == 'auto') return false;
    if (input == 'auto') return true;
    final outputBase = output.startsWith('zh') ? 'zh' : output;
    return input != outputBase;
  }

  // --- Model name localization ---

  String _localizedModelName(ModelInfo model, AppLocalizations loc) {
    switch (model.id) {
      case 'zipformer_bi_2023_02_20': return loc.modelZipformerName;
      case 'paraformer_bi_zh_en': return loc.modelParaformerName;
      case 'sensevoice_zh_en_int8': return loc.modelSenseVoiceName;
      case 'sensevoice_zh_en_int8_2025': return loc.modelSenseVoice2025Name;
      case 'offline_paraformer_zh': return loc.modelOfflineParaformerName;
      case 'offline_paraformer_dialect_2025': return loc.modelParaformerDialectName;
      case 'whisper_large_v3': return loc.modelWhisperName;
      case 'fire_red_asr_large': return loc.modelFireRedName;
      default: return model.name;
    }
  }

  String _localizedModelDesc(ModelInfo model, AppLocalizations loc) {
    switch (model.id) {
      case 'zipformer_bi_2023_02_20': return loc.modelZipformerDesc;
      case 'paraformer_bi_zh_en': return loc.modelParaformerDesc;
      case 'sensevoice_zh_en_int8': return loc.modelSenseVoiceDesc;
      case 'sensevoice_zh_en_int8_2025': return loc.modelSenseVoice2025Desc;
      case 'offline_paraformer_zh': return loc.modelOfflineParaformerDesc;
      case 'offline_paraformer_dialect_2025': return loc.modelParaformerDialectDesc;
      case 'whisper_large_v3': return loc.modelWhisperDesc;
      case 'fire_red_asr_large': return loc.modelFireRedDesc;
      default: return model.description;
    }
  }

  // --- Mode color ---

  Color _modeColor(String mode) {
    switch (mode) {
      case 'offline': return MacosColors.systemGreenColor;
      case 'cloud': return MacosColors.systemOrangeColor;
      default: return MacosColors.systemGrayColor;
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return _buildWorkModeView();
  }

  Widget _buildWorkModeView() {
    final loc = AppLocalizations.of(context)!;
    final currentMode = ConfigService().workMode;

    switch (widget.viewFilter) {
      case ModeTabView.recognition:
        return _buildRecognitionOnlyView(loc, currentMode);
      case ModeTabView.aiPlus:
        return _buildAiPlusOnlyView(loc);
      case ModeTabView.all:
        break;
    }

    return Column(
      children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Mode selector — 3 compact cards
              _buildModeSelector(loc, currentMode),

              // Language hints (between mode selector and card grid)
              ..._buildLanguageHints(loc),

              const SizedBox(height: 12),

              // Animated content below mode selector
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey('mode_content_$currentMode'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main content: AI config (left, tall) | stacked cards (right)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left: stacked cards
                            Expanded(
                              child: Column(
                                children: [
                                  Row(children: [
                                    Expanded(child: _buildInputLanguageCard(loc)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildOutputLanguageCard(loc)),
                                  ]),
                                  const SizedBox(height: 10),
                                  _buildHotkeyCard(loc),
                                  if (currentMode != 'cloud') ...[
                                    const SizedBox(height: 10),
                                    _buildModelInfoCard(loc),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Right: AI config card (takes full height)
                            Expanded(child: _buildAiConfigCard(loc)),
                          ],
                        ),
                      ),

                      // AI 润色警告 banner（开启 AI 润色时显示）
                      if (ConfigService().aiCorrectionEnabled) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 14, color: MacosColors.systemOrangeColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                loc.aiPolishWarning,
                                style: TextStyle(fontSize: 11, color: MacosColors.systemOrangeColor, height: 1.4),
                              )),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Advanced settings (collapsible)
                      _buildWorkModeAdvanced(loc, currentMode),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )),

      ],
    );
  }

  // --- v1.8 sidebar filtered views ---

  /// v1.8 sidebar 识别引擎页：模式选择 + 语言 + 模型/ASR 相关
  /// 不包含 hotkey（在 general_tab）、vocab（在 vocab_page）、LLM（在 ai_plus_page）
  /// Simple：模式 + 语言 + 当前模型卡；Advanced：加 offline 模型列表 + streaming/punct。
  /// 视觉上分两区：顶部"工作模式"（模式选择+hints）+ 下方"配置"（语言/模型 双列卡）。
  Widget _buildRecognitionOnlyView(AppLocalizations loc, String currentMode) {
    final advanced = ConfigService().showAdvanced;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 区 1: 语言设置（顶部，决定后续模型/语种） ---
          SettingsCardGrid(
            forceDualColumn: true,
            children: [
              _buildInputLanguageCard(loc),
              _buildOutputLanguageCard(loc),
            ],
          ),

          // Section separator
          const SizedBox(height: 20),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: AppTheme.getBorder(context),
          ),
          const SizedBox(height: 20),

          // --- 区 2: 工作模式 ---
          _buildModeSelector(loc, currentMode),
          ..._buildLanguageHints(loc),
          if (ConfigService().aiCorrectionEnabled) ...[
            const SizedBox(height: 10),
            _buildSmartModeAiPlusHint(),
          ],

          // Section separator
          const SizedBox(height: 24),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: AppTheme.getBorder(context),
          ),
          const SizedBox(height: 20),

          // --- 区 3: 模型配置 ---
          // 云端模式：单卡 AiConfigCardCloud
          // 非云端 + 高级关：[当前模型] + [流式 & 标点]
          // 非云端 + 高级开：[非流式模型库] + [流式 & 标点]
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey('recognition_${currentMode}_$advanced'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentMode == 'cloud')
                    _buildAiConfigCardCloud(loc)
                  else
                    SettingsCardGrid(
                      forceDualColumn: true,
                      children: [
                        advanced ? _buildOfflineModelListCard(loc) : _buildModelInfoCard(loc),
                        _buildStreamingAndPunctCard(loc),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Smart 模式下给出"前往 AI Plus 配置 LLM"的提示横幅
  Widget _buildSmartModeAiPlusHint() {
    final loc = AppLocalizations.of(context)!;
    final nav = SidebarNavigation.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getAccent(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.getAccent(context).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          MacosIcon(CupertinoIcons.sparkles, size: 16, color: AppTheme.getAccent(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loc.smartNeedsAiPlusConfig,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.getTextPrimary(context),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (nav != null)
            PushButton(
              controlSize: ControlSize.regular,
              color: AppTheme.getAccent(context),
              onPressed: () => nav.goto('ai_plus'),
              child: Text(loc.gotoAiPlus, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  /// v1.8 sidebar AI Plus 页：只渲染 LLM 配置，独立于 workMode
  /// （与原 _buildAiConfigCardSmart 同内容）
  Widget _buildAiPlusOnlyView(AppLocalizations loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ConfigService().aiCorrectionEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MacosIcon(CupertinoIcons.info_circle, size: 14, color: MacosColors.systemOrangeColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      loc.aiPlusNotActive,
                      style: TextStyle(fontSize: 11, color: MacosColors.systemOrangeColor, height: 1.4),
                    )),
                  ],
                ),
              ),
            ),
          _buildAiConfigCardSmart(loc),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Mode selector (3 horizontal cards) ---

  /// 识别模式（本地/云端）与翻译无关：翻译由 LLMService.correctText(translateTo:) 完成，
  /// ASR provider 全程不参与。曾因智能模式时代的遗留逻辑在翻译时锁死这两张卡片。
  Widget _buildModeSelector(AppLocalizations loc, String currentMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildModeCard(
                value: 'offline',
                groupValue: currentMode,
                emoji: '🔒',
                label: loc.workModeOffline,
                subtitle: loc.workModeOfflineDesc,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildModeCard(
                value: 'cloud',
                groupValue: currentMode,
                emoji: '☁️',
                label: loc.workModeCloud,
                subtitle: loc.workModeCloudDesc,
              )),
            ],
          ),
          const SizedBox(height: 10),
          _buildAiPolishToggle(loc),
        ],
      ),
    );
  }

  /// AI 润色独立开关（原 Smart 模式降级而来）：可叠加在本地/云端任一模式上
  Widget _buildAiPolishToggle(AppLocalizations loc) {
    final enabled = ConfigService().aiCorrectionEnabled;
    return SettingsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        Row(
          children: [
            const Text('✦', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.aiCorrection, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(loc.aiCorrectionDesc, style: AppTheme.caption(context).copyWith(fontSize: 11, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MacosSwitch(
              value: enabled,
              onChanged: (v) async {
                await ConfigService().setAiCorrectionEnabled(v);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String value,
    required String groupValue,
    required String emoji,
    required String label,
    required String subtitle,
    bool enabled = true,
    String? badge,
  }) {
    final isSelected = value == groupValue;
    final color = _modeColor(value);
    final accent = AppTheme.getAccent(context);

    return GestureDetector(
      onTap: enabled ? () => _switchWorkMode(value) : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.08)
                : AppTheme.getCardBackground(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.5) : AppTheme.getBorder(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTheme.body(context).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? color : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? color.withValues(alpha: 0.8) : AppTheme.getTextSecondary(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (badge != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: accent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Language cards (split: input / output) ---

  Widget _buildInputLanguageCard(AppLocalizations loc) {
    final items = _buildInputLanguageItems(loc);
    final value = ConfigService().inputLanguage;
    return _buildLanguageItemCard(
      title: loc.inputLanguage,
      value: value,
      items: items,
      onChanged: (v) async { await ConfigService().setInputLanguage(v!); if (!mounted) return;
                                                                         setState(() {}); },
    );
  }

  Widget _buildOutputLanguageCard(AppLocalizations loc) {
    final items = {
      'auto': loc.langFollowInput,
      'zh-Hans': loc.langZhHans,
      'zh-Hant': loc.langZhHant,
      'en': loc.langEn,
      'ja': loc.langJa,
      'ko': loc.langKo,
      'es': loc.langEs,
      'fr': loc.langFr,
      'de': loc.langDe,
      'ru': loc.langRu,
      'pt': loc.langPt,
    };
    final value = ConfigService().outputLanguage;
    return _buildLanguageItemCard(
      title: loc.outputLanguage,
      value: value,
      items: items,
      onChanged: (v) async { await ConfigService().setOutputLanguage(v!); if (!mounted) return;
                                                                          setState(() {}); },
    );
  }

  Widget _buildLanguageItemCard({
    required String title,
    required String value,
    required Map<String, String> items,
    required Function(String?) onChanged,
  }) {
    final label = items[value] ?? value;
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text('🌐', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(title, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            _buildCompactDropdown(value: value, items: items, onChanged: onChanged, label: label),
          ],
        ),
      ],
    );
  }

  // --- AI config card (mode-dependent) ---

  Widget _buildAiConfigCard(AppLocalizations loc) {
    final currentMode = ConfigService().workMode;
    if (currentMode == 'cloud') return _buildAiConfigCardCloud(loc);
    // 非云端：开了 AI 润色 → smart 卡（含 LLM 配置入口）；否则纯离线卡
    if (ConfigService().aiCorrectionEnabled) return _buildAiConfigCardSmart(loc);
    return _buildAiConfigCardOffline(loc);
  }

  Widget _buildAiConfigCardOffline(AppLocalizations loc) {
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const MacosIcon(CupertinoIcons.lock_shield_fill, size: 16, color: MacosColors.systemGreenColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                loc.workModeOfflineIcon,
                style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: MacosColors.systemGreenColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          loc.offlineDataLocal,
          style: AppTheme.caption(context).copyWith(color: MacosColors.systemGreenColor, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildAiConfigCardCloud(AppLocalizations loc) {
    // 池与「当前生效账户」都取自 CloudAccountService，与 Engine 共用同一份判断，
    // 避免界面显示 A、实际连 B
    final uniqueAsrAccounts = CloudAccountService().asrAccountPool();

    if (uniqueAsrAccounts.isEmpty) {
      return SettingsCard(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            const Text('☁️', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(loc.aliyunConfig, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          Text(loc.aliyunConfigDesc, style: AppTheme.caption(context).copyWith(fontSize: 11)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => SidebarNavigation.of(context)?.goto('cloud_accounts'),
            child: Text(loc.cloudAccountGoConfig, style: TextStyle(fontSize: 12, color: AppTheme.getAccent(context))),
          ),
          const SizedBox(height: 10),
          MacosTextField(controller: _akIdController, placeholder: "AccessKey ID"),
          const SizedBox(height: 6),
          MacosTextField(controller: _akSecretController, placeholder: "AccessKey Secret", obscureText: true),
          const SizedBox(height: 6),
          MacosTextField(controller: _appKeyController, placeholder: "AppKey"),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: PushButton(
              controlSize: ControlSize.regular,
              onPressed: () async {
                await ConfigService().setAliyunCredentials(_akIdController.text, _akSecretController.text, _appKeyController.text);
                if (mounted) {
                  NotificationService().notifySuccess(loc.commonSaved);
                }
              },
              child: Text(loc.saveApply),
            ),
          ),
        ],
      );
    }

    final effectiveAsrId = CloudAccountService().effectiveAsrAccount()!.id;

    final selectedAsrAccount = uniqueAsrAccounts.firstWhere((a) => a.id == effectiveAsrId);
    final selectedAsrProvider = CloudProviders.getById(selectedAsrAccount.providerId);
    final asrModels = selectedAsrProvider?.asrModels ?? [];
    final selectedAsrModelId = ConfigService().selectedAsrModelId;
    final effectiveAsrModelId = asrModels.any((m) => m.id == selectedAsrModelId)
        ? selectedAsrModelId!
        : (asrModels.isNotEmpty ? asrModels.first.id : '');

    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          const Text('☁️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(loc.workModeCloud, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        _compactRow(loc.cloudAccountSelectAsr, MacosPopupButton<String>(
          value: effectiveAsrId,
          items: uniqueAsrAccounts.map((a) {
            final provider = CloudProviders.getById(a.providerId);
            return MacosPopupMenuItem(
              value: a.id,
              child: Text(a.displayName.isNotEmpty ? a.displayName : (provider?.name ?? a.providerId)),
            );
          }).toList(),
          onChanged: (v) async {
            if (v == null) return;
            final acc = uniqueAsrAccounts.firstWhere((a) => a.id == v);
            final prov = CloudProviders.getById(acc.providerId);
            final defaultModelId = prov?.asrModels.isNotEmpty == true ? prov!.asrModels.first.id : null;
            await ConfigService().setSelectedAsrAccount(v, modelId: defaultModelId);
            await _reinitCloudAsr();
          },
        )),
        if (asrModels.length > 1) ...[
          const SizedBox(height: 6),
          _compactRow(loc.asrModel, MacosPopupButton<String>(
            value: effectiveAsrModelId,
            items: asrModels.map((m) => MacosPopupMenuItem(
              value: m.id,
              child: Row(children: [
                Text(m.name),
                if (m.priceHint != null) ...[
                  const SizedBox(width: 6),
                  Text(m.priceHint!, style: const TextStyle(fontSize: 10, color: MacosColors.systemGrayColor)),
                ],
              ]),
            )).toList(),
            onChanged: (v) async {
              if (v == null) return;
              await ConfigService().setSelectedAsrAccount(effectiveAsrId, modelId: v);
              await _reinitCloudAsr();
            },
          )),
        ],
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => SidebarNavigation.of(context)?.goto('cloud_accounts'),
          child: Text('${loc.manageCloudAccounts} ▸', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
        ),
      ],
    );
  }

  Widget _buildAiConfigCardSmart(AppLocalizations loc) {
    // v1.8 sidebar AI Plus 的高级开关（旧 5-tab 用 ModeTabView.all，默认全展示）
    final advanced = widget.viewFilter != ModeTabView.aiPlus || ConfigService().showAdvanced;
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        // Title row with toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✨', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(loc.tabAiPolish, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            MacosSwitch(
              value: ConfigService().aiCorrectionEnabled,
              onChanged: (v) async {
                await ConfigService().setAiCorrectionEnabled(v);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (advanced) ...[
          // LLM Provider type
          _compactRow(loc.llmProvider, MacosPopupButton<String>(
            value: ConfigService().llmProviderType,
            items: [
              MacosPopupMenuItem(value: 'cloud', child: Text(loc.llmProviderCloud)),
              MacosPopupMenuItem(value: 'ollama', child: Text(loc.llmProviderOllama)),
            ],
            onChanged: (v) async {
              if (v != null) {
                await ConfigService().setLlmProviderType(v);
                if (!mounted) return;
                setState(() {});
              }
            },
          )),
          const SizedBox(height: 6),
          // Typewriter effect
          _compactRow(loc.typewriterEffect, Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: MacosColors.systemRedColor.withValues(alpha: 0.5)),
                ),
                child: const Text('Alpha', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: MacosColors.systemRedColor)),
              ),
              const SizedBox(width: 8),
              MacosSwitch(
                value: ConfigService().typewriterEnabled,
                onChanged: (v) async { await ConfigService().setTypewriterEnabled(v); if (!mounted) return;
                                                                                      setState(() {}); },
              ),
            ],
          )),
          Divider(height: 16, color: AppTheme.getBorder(context)),
          // System Prompt
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.systemPrompt, style: AppTheme.body(context).copyWith(fontSize: 12)),
              GestureDetector(
                onTap: () async {
                  await ConfigService().setAiCorrectionPrompt(AppConstants.kDefaultAiCorrectionPrompt);
                  _aiPromptController.text = AppConstants.kDefaultAiCorrectionPrompt;
                  if (!mounted) return;
                  setState(() {});
                },
                child: Text(loc.resetDefault, style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MacosTextField(
            maxLines: 4,
            placeholder: "Enter instructions for AI...",
            controller: _aiPromptController,
            decoration: BoxDecoration(
              color: AppTheme.getInputBackground(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.getBorder(context)),
            ),
            onChanged: (v) => ConfigService().setAiCorrectionPrompt(v),
          ),
          Divider(height: 16, color: AppTheme.getBorder(context)),
        ],
        // LLM config — Simple 模式强制 cloud；Advanced 按 provider 切换
        if (!advanced || ConfigService().llmProviderType == 'cloud')
          _buildCloudLlmCombinedSelector(loc)
        else ...[
          Text(loc.ollamaServerRequired, style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
          const SizedBox(height: 8),
          buildApiItem(context, loc.ollamaUrl, CupertinoIcons.link, ConfigService().ollamaBaseUrl, (v) => ConfigService().setOllamaBaseUrl(v), placeholder: "http://localhost:11434"),
          const SizedBox(height: 6),
          buildApiItem(context, loc.ollamaModel, CupertinoIcons.cube_box, ConfigService().ollamaModel, (v) => ConfigService().setOllamaModel(v), placeholder: "qwen3:0.6b"),
        ],
      ],
    );
  }

  // --- Model info card ---

  Widget _buildModelInfoCard(AppLocalizations loc) {
    final activeModel = _app.getModelById(_activeModelId ?? '');
    final modelName = activeModel != null ? _localizedModelName(activeModel, loc) : loc.notSet;

    // Build language tags
    final langTags = activeModel?.supportedLanguages ?? [];
    final langLabels = langTags.map((l) => _langDisplayName(l, loc)).toList();

    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const Text('🎙️', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(loc.offlineModels, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        if (activeModel != null) ...[
          // Active model info
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(modelName, style: AppTheme.body(context).copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                    if (langLabels.isNotEmpty)
                      Text(
                        langLabels.join(' · '),
                        style: AppTheme.caption(context).copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('✓', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
              ),
            ],
          ),
        ] else ...[
          Text(loc.notSet, style: AppTheme.caption(context)),
        ],
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _workModeAdvancedExpanded = true),
          child: Text(
            '${loc.manageModels} ▸',
            style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context)),
          ),
        ),
      ],
    );
  }

  // --- Compact dropdown (pill-style wrapper around MacosPopupButton) ---

  Widget _buildCompactDropdown({
    required String value,
    required Map<String, String> items,
    required Function(String?) onChanged,
    required String label,
  }) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.getAccent(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: MacosPopupButton<String>(
        value: value,
        items: items.entries.map((e) => MacosPopupMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // --- Cloud LLM combined selector（合并下拉：Provider · Model 平铺 + 每个 account 的自定义项）---

  Widget _buildCloudLlmCombinedSelector(AppLocalizations loc) {
    final llmAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.llm);
    if (llmAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 16, color: MacosColors.systemOrangeColor),
            const SizedBox(width: 8),
            Expanded(child: Text(loc.cloudAccountNone, style: AppTheme.caption(context).copyWith(color: MacosColors.systemOrangeColor))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => SidebarNavigation.of(context)?.goto('cloud_accounts'),
              child: Text(loc.cloudAccountGoConfig, style: AppTheme.caption(context).copyWith(color: AppTheme.getAccent(context), decoration: TextDecoration.underline)),
            ),
          ],
        ),
      );
    }

    // 构造 account × model 组合，每个 account 末尾加"自定义..."项
    final items = <MacosPopupMenuItem<String>>[];
    for (final account in llmAccounts) {
      final provider = CloudProviders.getById(account.providerId);
      final accountName = account.displayName.isNotEmpty
          ? account.displayName
          : (provider?.name ?? account.providerId);
      final models = provider?.llmModels ?? [];
      if (models.isEmpty) {
        items.add(MacosPopupMenuItem(
          value: '${account.id}|${provider?.llmDefaultModel ?? ""}',
          child: Text(accountName),
        ));
      } else {
        for (final m in models) {
          items.add(MacosPopupMenuItem(
            value: '${account.id}|${m.id}',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$accountName · ${m.name}'),
              if (m.description != null) ...[
                const SizedBox(width: 6),
                Text(m.description!, style: const TextStyle(fontSize: 10, color: MacosColors.systemGrayColor)),
              ],
            ]),
          ));
        }
      }
      // 每个 account 末尾加"自定义..."项
      items.add(MacosPopupMenuItem(
        value: '${account.id}|$_kCustomModelSentinel',
        child: Text('$accountName · ${loc.llmModelCustom}',
            style: TextStyle(color: MacosColors.systemGrayColor)),
      ));
    }

    // 计算当前值：savedAccount 的 currentModel 是否在预设里？不在则视为 custom
    final savedAccountId = ConfigService().selectedLlmAccountId ?? '';
    final currentModelId = ConfigService().llmModelOverride ?? '';
    // savedAccountId 失效时按推荐优先级兜底（避免回退到 llmAccounts.first 可能是豆包 lite）
    final savedAccount = llmAccounts.firstWhere(
      (a) => a.id == savedAccountId,
      orElse: () => CloudAccountService().pickRecommendedLlmAccount() ?? llmAccounts.first,
    );
    final savedProvider = CloudProviders.getById(savedAccount.providerId);
    final savedModels = savedProvider?.llmModels ?? [];
    final isPresetModel = savedModels.any((m) => m.id == currentModelId);
    final isCustom = _llmModelCustom ||
        (currentModelId.isNotEmpty && !isPresetModel && savedModels.isNotEmpty);

    final currentValue = isCustom
        ? '${savedAccount.id}|$_kCustomModelSentinel'
        : '${savedAccount.id}|$currentModelId';
    final validValues = items.map((i) => i.value!).toSet();
    final effectiveValue = validValues.contains(currentValue) ? currentValue : items.first.value!;

    // 同步 custom controller 文本
    if (isCustom && _llmCustomModelController.text != currentModelId) {
      _llmCustomModelController.text = currentModelId;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MacosIcon(CupertinoIcons.building_2_fill, size: 16, color: MacosColors.systemGrayColor),
            const SizedBox(width: 8),
            Text('${loc.cloudAccountSelectLlm} · ${loc.llmModelField}', style: AppTheme.caption(context)),
            const Spacer(),
            MacosPopupButton<String>(
              value: effectiveValue,
              items: items,
              onChanged: (v) async {
                if (v == null) return;
                final parts = v.split('|');
                final newAccountId = parts[0];
                final newModelId = parts.length > 1 ? parts[1] : '';
                await ConfigService().setSelectedLlmAccountId(newAccountId);
                final account = CloudAccountService().getAccountById(newAccountId);
                if (account != null) {
                  await ConfigService().setLlmPresetId(account.providerId);
                }
                if (!mounted) return;
                if (newModelId == _kCustomModelSentinel) {
                  // 进入 custom 模式；先保留当前 model，让用户编辑
                  setState(() => _llmModelCustom = true);
                } else if (newModelId.isNotEmpty) {
                  await ConfigService().setLlmModel(newModelId);
                  if (!mounted) return;
                  setState(() => _llmModelCustom = false);
                }
              },
            ),
          ],
        ),
        // Custom 输入框（仅在选中"自定义..."时显示）
        if (isCustom) ...[
          const SizedBox(height: 10),
          MacosTextField(
            controller: _llmCustomModelController,
            placeholder: savedProvider?.llmModelHint ?? loc.llmModelNamePlaceholder,
            onChanged: (v) async {
              if (v.isNotEmpty) await ConfigService().setLlmModel(v);
            },
          ),
        ],
        const SizedBox(height: 12),
        _buildLlmRecommendation(),
      ],
    );
  }

  // --- Cloud LLM account selector (dead code, Phase 6 清理时删) ---

  // ignore: unused_element
  Widget _buildCloudLlmAccountSelector(AppLocalizations loc) {
    final llmAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.llm);
    final savedId = ConfigService().selectedLlmAccountId ?? '';
    final effectiveId = llmAccounts.any((a) => a.id == savedId) ? savedId : (llmAccounts.isNotEmpty ? llmAccounts.first.id : '');
    final selectedAccount = effectiveId.isNotEmpty ? CloudAccountService().getAccountById(effectiveId) : null;
    final selectedProvider = selectedAccount != null ? CloudProviders.getById(selectedAccount.providerId) : null;

    if (llmAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 16, color: MacosColors.systemOrangeColor),
            const SizedBox(width: 8),
            Expanded(child: Text(loc.cloudAccountNone, style: AppTheme.caption(context).copyWith(color: MacosColors.systemOrangeColor))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => SidebarNavigation.of(context)?.goto('cloud_accounts'),
              child: Text(loc.cloudAccountGoConfig, style: AppTheme.caption(context).copyWith(color: AppTheme.getAccent(context), decoration: TextDecoration.underline)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account selector
        Row(
          children: [
            const MacosIcon(CupertinoIcons.building_2_fill, size: 16, color: MacosColors.systemGrayColor),
            const SizedBox(width: 8),
            Text(loc.cloudAccountSelectLlm, style: AppTheme.caption(context)),
            const Spacer(),
            MacosPopupButton<String>(
              value: effectiveId,
              items: llmAccounts.map((a) {
                final p = CloudProviders.getById(a.providerId);
                return MacosPopupMenuItem(
                  value: a.id,
                  child: Text(a.displayName.isNotEmpty ? a.displayName : (p?.name ?? a.providerId)),
                );
              }).toList(),
              onChanged: (v) async {
                if (v == null) return;
                await ConfigService().setSelectedLlmAccountId(v);
                final account = CloudAccountService().getAccountById(v);
                if (account != null) {
                  await ConfigService().setLlmPresetId(account.providerId);
                  final p = CloudProviders.getById(account.providerId);
                  if (p?.llmDefaultModel != null) await ConfigService().setLlmModel(p!.llmDefaultModel!);
                }
                if (!mounted) return;
                setState(() => _llmModelCustom = false);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Model selector
        _buildLlmModelSelector(selectedAccount, selectedProvider),
        const SizedBox(height: 12),
        // LLM recommendation
        _buildLlmRecommendation(),
      ],
    );
  }

  // --- LLM recommendation ---

  Widget _buildLlmRecommendation() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.getAccent(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.getAccent(context).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MacosIcon(CupertinoIcons.lightbulb, size: 14, color: AppTheme.getAccent(context)),
              const SizedBox(width: 6),
              Text(loc.llmRecommendations, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.getAccent(context))),
            ],
          ),
          const SizedBox(height: 8),
          // 数据取自 ADR-005 实测（V4 thinking 默认关闭后的横向对比）。
          // 顺序按实测总耗时排 —— V3 时代 DeepSeek 最快（129ms），V4 之后已退居其后。
          _buildRecommendItem(loc.llmProviderBailianQwenTurbo, loc.llmTagFastest, '~446ms', loc.llmTagFastestNote),
          const SizedBox(height: 4),
          _buildRecommendItem('DeepSeek deepseek-v4-flash', loc.llmTagStable, '~1309ms', loc.llmTagStableNote),
          const SizedBox(height: 6),
          Text(
            loc.llmDataSource,
            style: TextStyle(fontSize: 9, color: MacosColors.systemGrayColor),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendItem(String model, String tag, String latency, String note) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: AppTheme.getAccent(context).withValues(alpha: 0.12),
          ),
          child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.getAccent(context))),
        ),
        const SizedBox(width: 6),
        Text(model, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Text(latency, style: const TextStyle(fontSize: 11, color: MacosColors.systemGrayColor)),
        const SizedBox(width: 6),
        Expanded(child: Text(note, style: const TextStyle(fontSize: 10, color: MacosColors.systemGrayColor), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  // --- LLM model selector ---

  Widget _buildLlmModelSelector(CloudAccount? account, CloudProvider? provider) {
    final loc = AppLocalizations.of(context)!;
    final presets = provider?.llmModels ?? [];
    final currentModel = ConfigService().llmModelOverride ?? provider?.llmDefaultModel ?? '';

    final showCustom = _llmModelCustom || presets.isEmpty;

    // Dropdown current value
    String dropdownValue;
    if (showCustom) {
      dropdownValue = _kCustomModelSentinel;
    } else {
      dropdownValue = presets.any((m) => m.id == currentModel)
          ? currentModel
          : presets.first.id;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacosColors.systemGrayColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // API Key source hint
          Row(
            children: [
              MacosIcon(CupertinoIcons.checkmark_seal_fill, size: 14, color: AppTheme.getAccent(context)),
              const SizedBox(width: 6),
              Text(
                account?.displayName ?? provider?.name ?? '',
                style: AppTheme.caption(context).copyWith(color: AppTheme.getAccent(context), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Model row
          Row(
            children: [
              const MacosIcon(CupertinoIcons.cube_box, size: 14, color: MacosColors.systemGrayColor),
              const SizedBox(width: 6),
              Text(loc.llmModelField, style: AppTheme.caption(context)),
              const Spacer(),
              if (presets.isNotEmpty)
                MacosPopupButton<String>(
                  value: dropdownValue,
                  items: [
                    ...presets.map((m) => MacosPopupMenuItem(
                      value: m.id,
                      child: Row(
                        children: [
                          Text(m.name),
                          if (m.description != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              m.description!,
                              style: const TextStyle(fontSize: 10, color: MacosColors.systemGrayColor),
                            ),
                          ],
                        ],
                      ),
                    )),
                    MacosPopupMenuItem(
                      value: _kCustomModelSentinel,
                      child: Text(loc.llmModelCustom),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == _kCustomModelSentinel) {
                      setState(() => _llmModelCustom = true);
                    } else {
                      _llmCustomModelController.clear();
                      await ConfigService().setLlmModel(v);
                      _llmModelController.text = v;
                      if (!mounted) return;
                      setState(() => _llmModelCustom = false);
                    }
                  },
                ),
            ],
          ),
          // Custom input (only when "Custom..." is selected)
          if (dropdownValue == _kCustomModelSentinel) ...[
            const SizedBox(height: 8),
            MacosTextField(
              controller: _llmCustomModelController,
              placeholder: provider?.llmModelHint ?? loc.llmModelNamePlaceholder,
              onChanged: (v) async {
                _llmModelController.text = v;
                await ConfigService().setLlmModel(v);
              },
            ),
          ],
          // Price hint (preset mode)
          if (dropdownValue != _kCustomModelSentinel && presets.isNotEmpty) ...[
            Builder(builder: (_) {
              final hint = presets.firstWhere((m) => m.id == dropdownValue, orElse: () => presets.first).priceHint;
              if (hint == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(hint, style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
              );
            }),
          ],
        ],
      ),
    );
  }

  // --- Advanced settings ---

  Widget _buildWorkModeAdvanced(AppLocalizations loc, String currentMode) {
    if (currentMode == 'cloud') return const SizedBox.shrink();
    return Column(
      children: [
        // Collapsible header
        GestureDetector(
          onTap: () => setState(() => _workModeAdvancedExpanded = !_workModeAdvancedExpanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.getCardBackground(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.getBorder(context)),
            ),
            child: Row(
              children: [
                MacosIcon(
                  _workModeAdvancedExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                  size: 12, color: MacosColors.systemGrayColor,
                ),
                const SizedBox(width: 8),
                Text(loc.workModeAdvanced, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
        ),

        if (_workModeAdvancedExpanded) ...[
          const SizedBox(height: 10),

          // Row 1: Offline models (left) | Streaming + Punctuation (right)
          SettingsCardGrid(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildOfflineModelListCard(loc),
              _buildStreamingAndPunctCard(loc),
            ],
          ),

          const SizedBox(height: 10),

          // Full-width: Vocab settings
          const VocabSettingsView(),

          // AI polish matrix info（非云端模式下展示离线/润色矩阵）
          if (currentMode != 'cloud') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MacosColors.systemGrayColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                loc.aiPolishMatrix,
                style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor, height: 1.5, fontSize: 10),
              ),
            ),
          ],
        ],
      ],
    );
  }

  // --- Offline model list card (advanced) ---

  Widget _buildOfflineModelListCard(AppLocalizations loc) {
    final inputLang = ConfigService().inputLanguage;
    final filteredOffline = AppService.offlineModels
        .where((m) => m.supportsLanguage(inputLang)).toList();
    return SettingsCard(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          const Text('🎙️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(loc.offlineModels, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
          const Spacer(),
          Text(loc.offlineModelsDesc, style: AppTheme.caption(context).copyWith(fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        ...filteredOffline.map((m) => _buildModelRow(m, loc, isOffline: true)),
      ],
    );
  }

  // --- Streaming + Punctuation card (advanced) ---

  Widget _buildStreamingAndPunctCard(AppLocalizations loc) {
    final activeModel = _app.getModelById(_activeModelId ?? '');
    final modelHasPunct = activeModel?.hasPunctuation ?? false;
    final inputLang = ConfigService().inputLanguage;
    final filteredStreaming = AppService.availableModels
        .where((m) => m.supportsLanguage(inputLang)).toList();

    return SettingsCard(
      padding: const EdgeInsets.all(12),
      children: [
        // Punctuation model section
        Row(children: [
          const Text('📝', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(child: Text(loc.punctuationModel, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
        const SizedBox(height: 6),
        if (modelHasPunct)
          Text(loc.builtInPunctuation, style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGreenColor))
        else
          Row(children: [
            Text(loc.punctuationModelDesc, style: AppTheme.caption(context).copyWith(fontSize: 10)),
            const Spacer(),
            buildActionBtn(context,
              isDownloaded: _downloadedStatus[AppService.punctuationModelId] ?? false,
              isLoading: _downloadingIds.contains(AppService.punctuationModelId),
              progress: _downloadProgressMap[AppService.punctuationModelId],
              statusText: _downloadStatusMap[AppService.punctuationModelId],
              isActive: true, onDownload: _downloadPunctuation,
              onDelete: _deletePunctuation, onActivate: () {},
            ),
          ]),
        // Divider
        Divider(height: 16, color: AppTheme.getBorder(context)),
        // Streaming models section
        Row(children: [
          const Text('📡', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(loc.streamingModels, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
          const Spacer(),
          Text(loc.streamingModelsDesc, style: AppTheme.caption(context).copyWith(fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        ...filteredStreaming.map((m) => _buildModelRow(m, loc, isOffline: false)),
      ],
    );
  }

  /// Compact model row for advanced settings
  Widget _buildModelRow(ModelInfo m, AppLocalizations loc, {required bool isOffline}) {
    final isActive = _activeModelId == m.id;
    final isDownloaded = _downloadedStatus[m.id] ?? false;
    final isLoading = _downloadingIds.contains(m.id) || _activatingId == m.id;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.getBorder(context).withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedModelName(m, loc),
                  style: AppTheme.body(context).copyWith(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? AppTheme.getAccent(context) : null,
                  ),
                ),
                Text(
                  _localizedModelDesc(m, loc),
                  style: AppTheme.caption(context).copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          buildActionBtn(context,
            isDownloaded: isDownloaded,
            isLoading: isLoading,
            progress: _downloadProgressMap[m.id],
            statusText: _downloadStatusMap[m.id],
            isActive: isActive,
            isOffline: isOffline,
            onDownload: () => _download(m),
            onDelete: () => _delete(m),
            onActivate: () => _activate(m),
            modelUrl: m.url,
            onImport: () => _importModel(m),
            // 仅「纯内置（无本地副本）」隐藏删除；有副本时保留按钮用于删副本
            isBundled: _app.isModelBundled(m.id) && !(_hasLocalCopy[m.id] ?? false),
          ),
        ],
      ),
    );
  }
}
