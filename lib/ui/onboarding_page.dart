import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_service.dart';
import '../engine/model_manager.dart';
import '../engine/core_engine.dart';
import '../config/app_constants.dart';
import 'theme.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';

/// Onboarding flow for first-time users
/// Steps: Welcome -> Permissions -> Model Selection -> Download -> Done
class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentStep = 0;
  final ModelManager _modelManager = ModelManager();
  final CoreEngine _engine = CoreEngine();

  // Permission state
  bool _inputMonitoringGranted = false;
  bool _accessibilityGranted = false;
  bool _microphoneGranted = false;
  bool _checkingPermissions = false;
  // 记录用户已点击"授权"，用于检测"授权后仍需重启"
  bool _inputMonitoringAttempted = false;
  bool _accessibilityAttempted = false;
  bool _microphoneAttempted = false;

  // Model selection state
  String _selectedModelId = AppConstants.kDefaultModelId;
  bool _showCustomModels = false;

  // Download state
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _downloadStatus = "";
  bool _downloadComplete = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _checkingPermissions = true);
    _inputMonitoringGranted = _engine.checkInputMonitoringPermission();
    _accessibilityGranted = _engine.checkAccessibilityPermission();
    _microphoneGranted = _engine.checkMicPermission();
    setState(() => _checkingPermissions = false);
  }

  Future<void> _openInputMonitoringSettings() async {
    setState(() => _inputMonitoringAttempted = true);
    final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openAccessibilitySettings() async {
    setState(() => _accessibilityAttempted = true);
    final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openMicrophoneSettings() async {
    setState(() => _microphoneAttempted = true);
    final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  Future<void> _downloadSelectedModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = _l10n.onboardingPreparing;
      _downloadError = null;
    });

    try {
      final selectedModel = _modelManager.getModelById(_selectedModelId);
      if (selectedModel == null) throw Exception("Model not found: $_selectedModelId");

      final needsPunctuation = !selectedModel.hasPunctuation;

      // Step 1: Download punctuation model if needed
      if (needsPunctuation) {
        setState(() => _downloadStatus = _l10n.onboardingDownloadPunct);
        await _modelManager.downloadPunctuationModel(
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _downloadProgress = p * 0.25; // 25% for punctuation
                _downloadStatus = _l10n.onboardingDownloadPunctPercent((p * 100).toStringAsFixed(0));
              });
            }
          },
          onStatus: (s) {
            if (mounted) setState(() => _downloadStatus = s);
          },
        );
      }

      // Step 2: Download ASR model
      final asrStart = needsPunctuation ? 0.25 : 0.0;
      final asrRange = needsPunctuation ? 0.75 : 1.0;
      setState(() {
        _downloadStatus = _l10n.onboardingDownloadASR;
        _downloadProgress = asrStart;
      });

      await _modelManager.downloadAndExtractModel(
        selectedModel.id,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              if (p < 0) {
                _downloadStatus = _l10n.unzipping;
              } else {
                _downloadProgress = asrStart + (p * asrRange);
                _downloadStatus = _l10n.onboardingDownloadASRPercent((p * 100).toStringAsFixed(0));
              }
            });
          }
        },
      );

      // Step 3: Activate model
      setState(() => _downloadStatus = _l10n.onboardingActivating);
      await _modelManager.setActiveModel(selectedModel.id);
      final path = await _modelManager.getActiveModelPath();
      if (path != null) {
        await _engine.initASR(path, modelType: selectedModel.type, modelName: selectedModel.name, hasPunctuation: selectedModel.hasPunctuation);
      }
      await ConfigService().setActiveModelId(selectedModel.id);

      // Initialize punctuation if downloaded
      if (needsPunctuation) {
        final punctPath = await _modelManager.getPunctuationModelPath();
        if (punctPath != null) {
          await _engine.initPunctuation(punctPath, activeModelName: selectedModel.name);
        }
      }

      setState(() {
        _isDownloading = false;
        _downloadComplete = true;
        _downloadProgress = 1.0;
        _downloadStatus = _l10n.onboardingDownloadDone;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadError = e.toString();
        _downloadStatus = _l10n.onboardingDownloadFail;
      });
    }
  }

  Future<void> _importSelectedModel() async {
    try {
      final result = await const MethodChannel('com.SpeakOut/overlay')
          .invokeMethod<String>('pickFile');
      if (result == null || result.isEmpty) return;

      final selectedModel = _modelManager.getModelById(_selectedModelId);
      if (selectedModel == null) throw Exception("Model not found: $_selectedModelId");

      setState(() {
        _isDownloading = true;
        _downloadProgress = 0;
        _downloadStatus = _l10n.importing;
        _downloadError = null;
      });

      await _modelManager.importModel(
        selectedModel.id,
        result,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              if (p < 0) {
                _downloadStatus = _l10n.unzipping;
              } else {
                _downloadProgress = p;
              }
            });
          }
        },
        onStatus: (s) {
          if (mounted) setState(() => _downloadStatus = s);
        },
      );

      // Activate model
      setState(() => _downloadStatus = _l10n.onboardingActivating);
      await _modelManager.setActiveModel(selectedModel.id);
      final path = await _modelManager.getActiveModelPath();
      if (path != null) {
        await _engine.initASR(path, modelType: selectedModel.type, modelName: selectedModel.name, hasPunctuation: selectedModel.hasPunctuation);
      }
      await ConfigService().setActiveModelId(selectedModel.id);

      setState(() {
        _isDownloading = false;
        _downloadComplete = true;
        _downloadProgress = 1.0;
        _downloadStatus = _l10n.onboardingDownloadDone;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadError = e.toString();
        _downloadStatus = _l10n.onboardingDownloadFail;
      });
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() => _currentStep++);

      // Auto-start download when reaching download step (step 3)
      if (_currentStep == 3 && !_downloadComplete && !_isDownloading) {
        _downloadSelectedModel();
      }
    }
  }

  void _finish() async {
    await ConfigService().completeOnboarding();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      child: MacosScaffold(
        backgroundColor: AppTheme.getBackground(context),
        children: [
          ContentArea(
            builder: (context, _) {
              return Container(
                color: AppTheme.getBackground(context),
                child: Center(
                  child: Container(
                    width: 520,
                    padding: const EdgeInsets.all(40),
                    child: _buildCurrentStep(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildPermissionsStep();
      case 2:
        return _buildModelSelectionStep();
      case 3:
        return _buildDownloadStep();
      case 4:
        return _buildDoneStep();
      default:
        return _buildWelcomeStep();
    }
  }

  // Step 0: Welcome
  Widget _buildWelcomeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppTheme.accentColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(CupertinoIcons.mic_fill, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 32),

        Text(
          _l10n.onboardingWelcome,
          style: AppTheme.display(context).copyWith(fontSize: 28),
        ),
        const SizedBox(height: 16),

        Text(
          _l10n.onboardingWelcomeDesc,
          textAlign: TextAlign.center,
          style: AppTheme.body(context).copyWith(
            color: MacosColors.systemGrayColor,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 48),

        PushButton(
          controlSize: ControlSize.large,
          onPressed: _nextStep,
          child: Text(_l10n.onboardingStartSetup),
        ),
      ],
    );
  }

  // Step 1: Permissions
  Widget _buildPermissionsStep() {
    final allGranted = _inputMonitoringGranted && _accessibilityGranted && _microphoneGranted;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MacosIcon(CupertinoIcons.shield_lefthalf_fill, size: 64, color: MacosColors.systemGrayColor),
        const SizedBox(height: 24),

        Text(_l10n.onboardingPermTitle, style: AppTheme.display(context).copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(_l10n.onboardingPermDesc, style: AppTheme.caption(context)),
        const SizedBox(height: 32),

        _buildPermissionTile(
          icon: CupertinoIcons.keyboard,
          title: _l10n.permInputMonitoring,
          description: _l10n.permInputMonitoringDesc,
          granted: _inputMonitoringGranted,
          needsRestart: _inputMonitoringAttempted && !_inputMonitoringGranted,
          onRequest: _openInputMonitoringSettings,
        ),
        const SizedBox(height: 12),

        _buildPermissionTile(
          icon: CupertinoIcons.text_cursor,
          title: _l10n.permAccessibility,
          description: _l10n.permAccessibilityDesc,
          granted: _accessibilityGranted,
          needsRestart: _accessibilityAttempted && !_accessibilityGranted,
          onRequest: _openAccessibilitySettings,
        ),
        const SizedBox(height: 12),

        _buildPermissionTile(
          icon: CupertinoIcons.mic,
          title: _l10n.permMicrophone,
          description: _l10n.permMicrophoneDesc,
          granted: _microphoneGranted,
          needsRestart: _microphoneAttempted && !_microphoneGranted,
          onRequest: _openMicrophoneSettings,
        ),

        const SizedBox(height: 32),

        if (_checkingPermissions)
          const CupertinoActivityIndicator()
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!allGranted)
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _checkPermissions,
                  child: Text(_l10n.permRefreshStatus),
                ),
              const SizedBox(width: 12),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: allGranted ? _nextStep : null,
                child: Text(allGranted ? _l10n.onboardingContinue : _l10n.onboardingGrantFirst),
              ),
            ],
          ),

        const SizedBox(height: 16),
        if (!allGranted)
          TextButton(
            onPressed: _nextStep,
            child: Text(_l10n.onboardingSetupLater, style: TextStyle(color: MacosColors.systemGrayColor)),
          ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool granted,
    required VoidCallback onRequest,
    bool needsRestart = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted
            ? Colors.green.withValues(alpha:0.1)
            : needsRestart
                ? Colors.orange.withValues(alpha:0.08)
                : MacosColors.systemGrayColor.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha:0.3)
              : needsRestart
                  ? Colors.orange.withValues(alpha:0.3)
                  : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          MacosIcon(icon, size: 28, color: granted ? Colors.green : needsRestart ? Colors.orange : MacosColors.systemGrayColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                Text(description, style: AppTheme.caption(context)),
                if (needsRestart)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _l10n.permRestartHint,
                      style: AppTheme.caption(context).copyWith(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (granted)
            const MacosIcon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 24)
          else
            PushButton(
              controlSize: ControlSize.small,
              secondary: true,
              onPressed: onRequest,
              child: Text(_l10n.permGrant),
            ),
        ],
      ),
    );
  }

  // Step 2: Model Selection — two-tier: Recommended vs Custom
  Widget _buildModelSelectionStep() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MacosIcon(CupertinoIcons.waveform, size: 64, color: MacosColors.systemGrayColor),
        const SizedBox(height: 24),

        Text(l10n.chooseModel, style: AppTheme.display(context).copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(l10n.chooseModelDesc, style: AppTheme.caption(context)),
        const SizedBox(height: 28),

        if (!_showCustomModels) ...[
          // --- Two big cards ---
          _buildModeCard(
            icon: CupertinoIcons.star_fill,
            iconColor: Colors.amber,
            title: l10n.modelSenseVoiceName,
            subtitle: l10n.onboardingModelSubtitle,
            highlighted: true,
            badge: l10n.recommended,
            onTap: () {
              setState(() => _selectedModelId = AppConstants.kDefaultModelId);
              _nextStep();
            },
          ),
          const SizedBox(height: 12),
          _buildModeCard(
            icon: CupertinoIcons.slider_horizontal_3,
            iconColor: MacosColors.systemGrayColor,
            title: l10n.onboardingCustomSelect,
            subtitle: l10n.onboardingBrowseModels(ModelManager.offlineModels.length.toString()),
            highlighted: false,
            onTap: () => setState(() {
              _showCustomModels = true;
              _selectedModelId = AppConstants.kDefaultModelId;
            }),
          ),
        ] else ...[
          // --- Custom model list ---
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: ModelManager.offlineModels
                    .map((model) => _buildModelOption(model, l10n))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () => setState(() => _showCustomModels = false),
                child: Text(l10n.onboardingBack),
              ),
              const SizedBox(width: 12),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: _nextStep,
                child: Text(l10n.onboardingContinue),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool highlighted,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: highlighted
                ? AppTheme.accentColor.withValues(alpha: 0.08)
                : MacosColors.systemGrayColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? AppTheme.accentColor.withValues(alpha: 0.35)
                  : MacosColors.systemGrayColor.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (highlighted ? AppTheme.accentColor : MacosColors.systemGrayColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTheme.body(context).copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.caption(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 16, color: MacosColors.systemGrayColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelOption(ModelInfo model, AppLocalizations l10n) {
    final isSelected = _selectedModelId == model.id;
    final isDefault = model.id == AppConstants.kDefaultModelId;
    final name = _localizedModelName(model, l10n);
    final desc = _localizedModelDesc(model, l10n);

    return GestureDetector(
      onTap: () => setState(() => _selectedModelId = model.id),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentColor.withValues(alpha: 0.12)
              : MacosColors.systemGrayColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentColor.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : MacosColors.systemGrayColor,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: AppTheme.body(context).copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.recommended,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          desc,
                          style: AppTheme.caption(context).copyWith(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: model.hasPunctuation
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          model.hasPunctuation ? l10n.builtInPunctuation : l10n.needsPunctuationModel,
                          style: TextStyle(
                            fontSize: 9,
                            color: model.hasPunctuation ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localizedModelName(ModelInfo model, AppLocalizations l10n) {
    switch (model.id) {
      case 'sensevoice_zh_en_int8': return l10n.modelSenseVoiceName;
      case 'sensevoice_zh_en_int8_2025': return l10n.modelSenseVoice2025Name;
      case 'offline_paraformer_zh': return l10n.modelOfflineParaformerName;
      case 'offline_paraformer_dialect_2025': return l10n.modelParaformerDialectName;
      case 'whisper_large_v3': return l10n.modelWhisperName;
      case 'fire_red_asr_large': return l10n.modelFireRedName;
      default: return model.name;
    }
  }

  String _localizedModelDesc(ModelInfo model, AppLocalizations l10n) {
    switch (model.id) {
      case 'sensevoice_zh_en_int8': return l10n.modelSenseVoiceDesc;
      case 'sensevoice_zh_en_int8_2025': return l10n.modelSenseVoice2025Desc;
      case 'offline_paraformer_zh': return l10n.modelOfflineParaformerDesc;
      case 'offline_paraformer_dialect_2025': return l10n.modelParaformerDialectDesc;
      case 'whisper_large_v3': return l10n.modelWhisperDesc;
      case 'fire_red_asr_large': return l10n.modelFireRedDesc;
      default: return model.description;
    }
  }

  // Step 3: Download
  Widget _buildDownloadStep() {
    final selectedModel = _modelManager.getModelById(_selectedModelId);
    final modelName = selectedModel != null
        ? _localizedModelName(selectedModel, _l10n)
        : _selectedModelId;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MacosIcon(CupertinoIcons.cloud_download, size: 64, color: MacosColors.systemGrayColor),
        const SizedBox(height: 24),

        Text(_l10n.onboardingDownloadTitle, style: AppTheme.display(context).copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(_l10n.onboardingDownloading(modelName), style: AppTheme.caption(context)),
        const SizedBox(height: 32),

        // Progress
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MacosColors.systemGrayColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 12,
                  backgroundColor: MacosColors.systemGrayColor.withValues(alpha:0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _downloadError != null ? Colors.red : AppTheme.accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _downloadStatus,
                style: AppTheme.body(context),
              ),
              if (_downloadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadError!.length > 100
                      ? "${_downloadError!.substring(0, 100)}..."
                      : _downloadError!,
                  style: AppTheme.caption(context).copyWith(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),

        if (_downloadComplete)
          PushButton(
            controlSize: ControlSize.large,
            onPressed: _nextStep,
            child: Text(_l10n.onboardingContinue),
          )
        else if (_downloadError != null)
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: _downloadSelectedModel,
                    child: Text(_l10n.onboardingRetry),
                  ),
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: _importSelectedModel,
                    child: Text(_l10n.importModel),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _nextStep,
                    child: Text(_l10n.onboardingSkip, style: TextStyle(color: MacosColors.systemGrayColor)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  final model = _modelManager.getModelById(_selectedModelId);
                  if (model != null) launchUrl(Uri.parse(model.url));
                },
                child: Text(
                  _l10n.manualDownload,
                  style: TextStyle(color: AppTheme.accentColor, fontSize: 12),
                ),
              ),
            ],
          )
        else if (_isDownloading)
          const CupertinoActivityIndicator()
        else
          PushButton(
            controlSize: ControlSize.large,
            onPressed: _downloadSelectedModel,
            child: Text(_l10n.onboardingStartDownload),
          ),
      ],
    );
  }

  // Step 4: Done
  Widget _buildDoneStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: const Icon(CupertinoIcons.checkmark_alt, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 32),

        Text(_l10n.onboardingDoneTitle, style: AppTheme.display(context).copyWith(fontSize: 28)),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: MacosColors.systemGrayColor.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ConfigService().pttKeyName,
                      style: AppTheme.mono(context).copyWith(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_l10n.onboardingHoldToSpeak, style: AppTheme.body(context)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _l10n.onboardingDoneDesc,
                style: AppTheme.caption(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        PushButton(
          controlSize: ControlSize.large,
          onPressed: _finish,
          child: Text(_l10n.onboardingBegin),
        ),
      ],
    );
  }
}
