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
import '../../../engine/model_manager.dart';
import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../../vocab_settings_page.dart';
import '../settings_shared.dart';

class ModeTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const ModeTab({super.key, required this.onNavigateToTab});

  @override
  State<ModeTab> createState() => ModeTabState();
}

class ModeTabState extends State<ModeTab> {
  final ModelManager _modelManager = ModelManager();
  final CoreEngine _engine = CoreEngine();

  // Model management
  final Map<String, bool> _downloadedStatus = {};
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
  StreamSubscription<(int, int)>? _keySubscription;

  // Misc
  bool _isTestingLlm = false;
  (bool, String)? _llmTestResult;
  bool _llmConfigDirty = false;
  bool _workModeAdvancedExpanded = false;

  static const String _kCustomModelSentinel = '__custom__';

  // --- Public API for parent shell ---

  bool get hasUnsavedChanges => _llmConfigDirty;

  Future<void> saveChanges() async {
    await _flushLlmControllers();
    await ConfigService().savePresetConfig(ConfigService().llmPresetId);
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
    _keySubscription?.cancel();
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
    CoreEngine().pttKeyCode = _currentKeyCode;
  }

  void _startKeyCapture([String target = 'ptt']) {
    setState(() {
      switch (target) {
        case 'toggleInput':
          _isCapturingToggleInputKey = true;
        default:
          _isCapturingKey = true;
      }
    });

    _keySubscription = _engine.rawKeyEventStream.listen((event) {
      final (keyCode, modifierFlags) = event;
      final keyName = mapKeyCodeToString(keyCode);
      _saveHotkeyConfig(keyCode, keyName, modifierFlags: modifierFlags);
      _stopKeyCapture();
    });

    // Timeout after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && (_isCapturingKey || _isCapturingToggleInputKey)) {
        _stopKeyCapture();
      }
    });
  }

  void _stopKeyCapture() {
    _keySubscription?.cancel();
    _keySubscription = null;
    if (mounted) {
      setState(() {
        _isCapturingKey = false;
        _isCapturingToggleInputKey = false;
      });
    }
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
    if (_isCapturingKey) activeKeys.remove(ConfigService().toggleInputKeyCode);
    if (_isCapturingToggleInputKey) activeKeys.remove(ConfigService().pttKeyCode);
    if (activeKeys.containsKey(keyCode)) {
      final conflictWith = activeKeys[keyCode]!;
      _stopKeyCapture();
      if (mounted) {
        showMacosAlertDialog(
          context: context,
          builder: (_) => MacosAlertDialog(
            appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: Colors.orange),
            title: Text('$displayName 已被「$conflictWith」使用',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            message: const Text('该按键已被占用，请选择其他按键。'),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: const Text('好的'),
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
      setState(() {
        _toggleInputKeyName = displayName;
        _isCapturingToggleInputKey = false;
      });
    } else {
      // PTT key
      await config.setPttKey(keyCode, displayName, modifiers: requiredMods);
      CoreEngine().pttKeyCode = keyCode;
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
      {bool isCapturing = false, VoidCallback? onTap}) {
    final loc = AppLocalizations.of(context)!;
    final display = isCapturing
        ? loc.pressAnyKey
        : (keyName.isEmpty ? loc.notSet : keyName);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isCapturing
              ? AppTheme.getAccent(context)
              : MacosColors.systemGrayColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          display,
          style: AppTheme.mono(context).copyWith(
            fontSize: 11,
            color: isCapturing
                ? Colors.white
                : (keyName.isEmpty ? MacosColors.systemGrayColor : null),
          ),
        ),
      ),
    );
  }

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
          Text('快捷键与时长', style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        _compactRow('长按说话 (PTT)', _hotkeyBadge(_currentKeyName, isCapturing: _isCapturingKey, onTap: () => _startKeyCapture())),
        const SizedBox(height: 6),
        _compactRow('单击切换 (Toggle)', _hotkeyBadge(_toggleInputKeyName, isCapturing: _isCapturingToggleInputKey, onTap: () => _startKeyCapture('toggleInput'))),
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
            if (v != null) { await ConfigService().setToggleMaxDuration(v); setState(() => _toggleMaxDuration = v); }
          },
        )),
      ],
    );
  }

  Future<void> _refresh() async {
    for (var m in ModelManager.allModels) {
      _downloadedStatus[m.id] = await _modelManager.isModelDownloaded(m.id);
    }
    _downloadedStatus[ModelManager.punctuationModelId] = await _modelManager.isPunctuationModelDownloaded();
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
      await _modelManager.downloadAndExtractModel(model.id,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgressMap[model.id] = p < 0 ? null : p;
              _downloadStatusMap[model.id] = p < 0
                  ? "解压中..."
                  : loc.downloading((p * 100).toStringAsFixed(0));
            });
          }
        },
      );
      await _refresh();
    } catch (e) {
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(model.id); });
    }
  }

  Future<void> _activate(ModelInfo model) async {
    // Check if switching between streaming <-> offline mode
    final currentModel = _modelManager.getModelById(_activeModelId ?? '');
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
    setState(() => _activatingId = model.id);
    await _modelManager.setActiveModel(model.id);
    final path = await _modelManager.getActiveModelPath();
    if (path != null) {
      try {
        await _engine.initASR(path, modelType: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
      } catch (e) {
        // Init failed -> rollback
        if (previousModelId != null) {
          await _modelManager.setActiveModel(previousModelId);
          await ConfigService().setActiveModelId(previousModelId);
        }
        setState(() { _activatingId = null; });
        if (mounted) showSettingsError(context, '模型激活失败: $e');
        return;
      }
      // Model has no built-in punctuation -> prompt user + auto-load punctuation model
      if (!model.hasPunctuation) {
        final punctPath = await _modelManager.getPunctuationModelPath();
        if (punctPath != null) {
          await _engine.initPunctuation(punctPath, activeModelName: model.name);
          if (mounted) {
            showSettingsInfo('已自动加载标点模型');
          }
        } else if (mounted) {
          final confirmed = await showMacosAlertDialog<bool>(
            context: context,
            builder: (_) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.textformat_abc, size: 48),
              title: const Text('该模型不含标点符号'),
              message: const Text('此模型输出的文字没有标点。建议下载标点模型以获得更好的阅读体验。\n\n是否前往下载？'),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context, true),
                child: const Text('去下载'),
              ),
              secondaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('暂不需要'),
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
    setState(() { _activatingId = null; _activeModelId = model.id; });
  }

  Future<void> _delete(ModelInfo model) async {
    await _modelManager.deleteModel(model.id);
    await _refresh();
  }

  Future<void> _importModel(ModelInfo model) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final result = await const MethodChannel('com.SpeakOut/overlay')
          .invokeMethod<String>('pickFile');
      if (result == null || result.isEmpty) return;

      setState(() {
        _downloadingIds.add(model.id);
        _downloadProgressMap[model.id] = null;
        _downloadStatusMap[model.id] = loc.importing;
      });

      await _modelManager.importModel(model.id, result,
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
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(model.id); });
    }
  }

  Future<void> _downloadPunctuation() async {
    final loc = AppLocalizations.of(context)!;
    final punctId = ModelManager.punctuationModelId;

    setState(() {
      _downloadingIds.add(punctId);
      _downloadProgressMap[punctId] = 0;
      _downloadStatusMap[punctId] = loc.preparing;
    });

    try {
      await _modelManager.downloadPunctuationModel(
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
      final path = await _modelManager.getPunctuationModelPath();
      if (path != null) await _engine.initPunctuation(path);
    } catch (e) {
      showSettingsError(context, e.toString());
    } finally {
      if (mounted) setState(() { _downloadingIds.remove(punctId); });
    }
  }

  Future<void> _deletePunctuation() async {
    await _modelManager.deletePunctuationModel();
    await _refresh();
  }

  // --- Work Mode switching ---

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
    if (mode == 'cloud' && oldMode != 'cloud') {
      await _engine.initASR('', modelType: 'aliyun');
    } else if (mode != 'cloud' && oldMode == 'cloud') {
      final path = await _modelManager.getActiveModelPath();
      final model = _modelManager.getModelById(_activeModelId ?? '');
      if (path != null && model != null) {
        await _engine.initASR(path, modelType: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
        // Model has no built-in punctuation -> auto-load punctuation model
        if (!model.hasPunctuation && !_engine.isPunctuationEnabled) {
          final punctPath = await _modelManager.getPunctuationModelPath();
          if (punctPath != null) {
            await _engine.initPunctuation(punctPath, activeModelName: model.name);
          }
        }
      }
    }
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
    final asrAccountId = ConfigService().selectedAsrAccountId ?? '';
    final asrAccount = CloudAccountService().getAccountById(asrAccountId);
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

    // 1. Translation mode + wrong work mode
    if (isTranslation) {
      if (workMode == 'offline') {
        hints.add(_languageHintBanner(
          loc.translationNeedsSmartMode,
          color: MacosColors.systemOrangeColor,
          icon: CupertinoIcons.exclamationmark_triangle,
        ));
      } else if (workMode == 'cloud') {
        hints.add(_languageHintBanner(
          loc.translationCloudLimited,
          color: MacosColors.systemOrangeColor,
          icon: CupertinoIcons.exclamationmark_triangle,
        ));
      } else {
        // Smart mode — just show blue info
        hints.add(_languageHintBanner(
          loc.translationModeHint,
          color: MacosColors.systemBlueColor,
          icon: CupertinoIcons.arrow_right_arrow_left,
        ));
      }
    }

    // 2. Input language not supported by current offline model
    if (inputLang != 'auto' && workMode != 'cloud') {
      final model = ModelManager.allModels.where((m) => m.id == modelId).firstOrNull;
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
      final asrAccountId = ConfigService().selectedAsrAccountId;
      if (asrAccountId != null) {
        final asrAccount = CloudAccountService().getAccountById(asrAccountId);
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
      case 'smart': return MacosColors.systemBlueColor;
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
    final isTranslation = _isTranslationMode();

    return Column(
      children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Mode selector — 3 compact cards
              _buildModeSelector(loc, currentMode, isTranslation),

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
                                  _buildLanguageCard(loc),
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

                      // Smart mode warning banner (full-width below row 2)
                      if (currentMode == 'smart') ...[
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

  // --- Mode selector (3 horizontal cards) ---

  Widget _buildModeSelector(AppLocalizations loc, String currentMode, bool isTranslation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: _buildModeCard(
            value: 'offline',
            groupValue: currentMode,
            emoji: '🔒',
            label: loc.workModeOffline,
            subtitle: loc.workModeOfflineDesc,
            enabled: !isTranslation,
          )),
          const SizedBox(width: 8),
          Expanded(child: _buildModeCard(
            value: 'smart',
            groupValue: currentMode,
            emoji: '✦',
            label: loc.workModeSmart,
            subtitle: loc.workModeSmartDesc,
            enabled: true,
            badge: loc.recommended,
          )),
          const SizedBox(width: 8),
          Expanded(child: _buildModeCard(
            value: 'cloud',
            groupValue: currentMode,
            emoji: '☁️',
            label: loc.workModeCloud,
            subtitle: loc.workModeCloudDesc,
            enabled: !isTranslation,
          )),
        ],
      ),
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

  // --- Language card ---

  Widget _buildLanguageCard(AppLocalizations loc) {
    final inputItems = _buildInputLanguageItems(loc);
    final inputValue = ConfigService().inputLanguage;
    final inputLabel = inputItems[inputValue] ?? inputValue;

    final outputItems = {
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
    final outputValue = ConfigService().outputLanguage;
    final outputLabel = outputItems[outputValue] ?? outputValue;

    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        // Title row
        Row(
          children: [
            const Text('🌐', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(loc.languageSettings, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        // Input language
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(loc.inputLanguage, style: AppTheme.caption(context)),
            _buildCompactDropdown(
              value: inputValue,
              items: inputItems,
              onChanged: (v) async { await ConfigService().setInputLanguage(v!); setState(() {}); },
              label: inputLabel,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Output language
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(loc.outputLanguage, style: AppTheme.caption(context)),
            _buildCompactDropdown(
              value: outputValue,
              items: outputItems,
              onChanged: (v) async { await ConfigService().setOutputLanguage(v!); setState(() {}); },
              label: outputLabel,
            ),
          ],
        ),
      ],
    );
  }

  // --- AI config card (mode-dependent) ---

  Widget _buildAiConfigCard(AppLocalizations loc) {
    final currentMode = ConfigService().workMode;
    switch (currentMode) {
      case 'smart':
        return _buildAiConfigCardSmart(loc);
      case 'cloud':
        return _buildAiConfigCardCloud(loc);
      default:
        return _buildAiConfigCardOffline(loc);
    }
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
          '所有数据在本地处理，不上传任何信息',
          style: AppTheme.caption(context).copyWith(color: MacosColors.systemGreenColor, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildAiConfigCardCloud(AppLocalizations loc) {
    final asrAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.asrStreaming)
      + CloudAccountService().getAccountsWithCapability(CloudCapability.asrBatch);
    final seen = <String>{};
    final uniqueAsrAccounts = asrAccounts.where((a) => seen.add(a.id)).toList();

    final selectedAsrId = ConfigService().selectedAsrAccountId;

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
            onTap: () => widget.onNavigateToTab(3),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("已保存"), duration: Duration(seconds: 2)),
                  );
                }
              },
              child: Text(loc.saveApply),
            ),
          ),
        ],
      );
    }

    final effectiveAsrId = uniqueAsrAccounts.any((a) => a.id == selectedAsrId)
        ? selectedAsrId!
        : uniqueAsrAccounts.first.id;

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
            await _engine.initASR('', modelType: 'aliyun');
            setState(() {});
          },
        )),
        if (asrModels.length > 1) ...[
          const SizedBox(height: 6),
          _compactRow('识别模型', MacosPopupButton<String>(
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
              await _engine.initASR('', modelType: 'aliyun');
              setState(() {});
            },
          )),
        ],
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => widget.onNavigateToTab(3),
          child: Text('管理云服务账户 ▸', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
        ),
      ],
    );
  }

  Widget _buildAiConfigCardSmart(AppLocalizations loc) {
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
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
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
              setState(() {});
            }
          },
        )),
        const SizedBox(height: 6),
        // Typewriter effect
        _compactRow('打字机效果', Row(
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
              onChanged: (v) async { await ConfigService().setTypewriterEnabled(v); setState(() {}); },
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
        // LLM config (cloud or ollama)
        if (ConfigService().llmProviderType == 'cloud')
          _buildCloudLlmAccountSelector(loc)
        else ...[
          Text('确保 Ollama 已启动（ollama serve）', style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
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
    final activeModel = _modelManager.getModelById(_activeModelId ?? '');
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
            '管理模型 ▸',
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

  // --- Cloud LLM account selector ---

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
              onTap: () => widget.onNavigateToTab(2), // Navigate to Cloud Accounts tab
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
              Text('选型参考', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.getAccent(context))),
            ],
          ),
          const SizedBox(height: 8),
          _buildRecommendItem('DeepSeek deepseek-chat', '极致速度', '~129ms', '高峰期可能波动'),
          const SizedBox(height: 4),
          _buildRecommendItem('阿里云百炼 qwen-turbo', '稳定首选', '~573ms', '波动最小，质量稳定'),
          const SizedBox(height: 6),
          Text(
            '数据来源：2026-03-21 实测，非流式 API，中国大陆网络',
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
              Text('模型', style: AppTheme.caption(context)),
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
                    const MacosPopupMenuItem(
                      value: _kCustomModelSentinel,
                      child: Text('自定义...'),
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
              placeholder: provider?.llmModelHint ?? '模型名称',
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

          // AI polish matrix info
          if (currentMode == 'smart' || currentMode == 'offline') ...[
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
    final filteredOffline = ModelManager.offlineModels
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
    final activeModel = _modelManager.getModelById(_activeModelId ?? '');
    final modelHasPunct = activeModel?.hasPunctuation ?? false;
    final inputLang = ConfigService().inputLanguage;
    final filteredStreaming = ModelManager.availableModels
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
              isDownloaded: _downloadedStatus[ModelManager.punctuationModelId] ?? false,
              isLoading: _downloadingIds.contains(ModelManager.punctuationModelId),
              progress: _downloadProgressMap[ModelManager.punctuationModelId],
              statusText: _downloadStatusMap[ModelManager.punctuationModelId],
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
          ),
        ],
      ),
    );
  }
}
