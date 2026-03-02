import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';
import '../../engine/model_manager.dart';
import '../../engine/core_engine.dart';
import '../../config/app_constants.dart';

/// Windows 首次启动引导页
///
/// 步骤: 欢迎 → 模型选择 → 下载 → 完成
/// 跳过权限步骤（Windows 不需要 macOS 式的权限授权）
class WindowsOnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const WindowsOnboardingPage({super.key, required this.onComplete});

  @override
  State<WindowsOnboardingPage> createState() => _WindowsOnboardingPageState();
}

class _WindowsOnboardingPageState extends State<WindowsOnboardingPage> {
  int _currentStep = 0;
  final ModelManager _modelManager = ModelManager();
  final CoreEngine _engine = CoreEngine();

  // Model selection
  String _selectedModelId = AppConstants.kDefaultModelId;
  bool _showCustomModels = false;

  // Download state
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _downloadStatus = "";
  bool _downloadComplete = false;
  String? _downloadError;

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
                _downloadProgress = p * 0.25;
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

  Future<void> _importModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bz2'],
        dialogTitle: _l10n.importModel,
      );
      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
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
        filePath,
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
    if (_currentStep < 3) {
      setState(() => _currentStep++);
      if (_currentStep == 2 && !_downloadComplete && !_isDownloading) {
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
    return ScaffoldPage(
      content: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(40),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildModelSelectionStep();
      case 2:
        return _buildDownloadStep();
      case 3:
        return _buildDoneStep();
      default:
        return _buildWelcomeStep();
    }
  }

  // Step 0: Welcome
  Widget _buildWelcomeStep() {
    final theme = FluentTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Color(0xFF2ECC71),
            shape: BoxShape.circle,
          ),
          child: const Icon(FluentIcons.microphone, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 32),
        Text(
          _l10n.onboardingWelcome,
          style: theme.typography.title?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 16),
        Text(
          _l10n.onboardingWelcomeDesc,
          textAlign: TextAlign.center,
          style: theme.typography.body?.copyWith(
            color: Colors.grey[120],
            height: 1.6,
          ),
        ),
        const SizedBox(height: 48),
        FilledButton(
          onPressed: _nextStep,
          child: Text(_l10n.onboardingStartSetup),
        ),
      ],
    );
  }

  // Step 1: Model Selection
  Widget _buildModelSelectionStep() {
    final theme = FluentTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(FluentIcons.music_in_collection, size: 64, color: Colors.grey[120]),
        const SizedBox(height: 24),
        Text(_l10n.chooseModel, style: theme.typography.title?.copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(_l10n.chooseModelDesc, style: theme.typography.caption),
        const SizedBox(height: 28),
        if (!_showCustomModels) ...[
          _buildModeCard(
            icon: FluentIcons.favorite_star_fill,
            iconColor: Colors.orange,
            title: _l10n.modelSenseVoiceName,
            subtitle: _l10n.onboardingModelSubtitle,
            highlighted: true,
            badge: _l10n.recommended,
            onTap: () {
              setState(() => _selectedModelId = AppConstants.kDefaultModelId);
              _nextStep();
            },
          ),
          const SizedBox(height: 12),
          _buildModeCard(
            icon: FluentIcons.slider_thumb,
            iconColor: Colors.grey[120],
            title: _l10n.onboardingCustomSelect,
            subtitle: _l10n.onboardingBrowseModels(ModelManager.offlineModels.length.toString()),
            highlighted: false,
            onTap: () => setState(() {
              _showCustomModels = true;
              _selectedModelId = AppConstants.kDefaultModelId;
            }),
          ),
        ] else ...[
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: ModelManager.offlineModels
                    .map((model) => _buildModelOption(model))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Button(
                onPressed: () => setState(() => _showCustomModels = false),
                child: Text(_l10n.onboardingBack),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _nextStep,
                child: Text(_l10n.onboardingContinue),
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
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: highlighted
                ? const Color(0xFF2ECC71).withValues(alpha: 0.08)
                : Colors.grey[40].withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFF2ECC71).withValues(alpha: 0.35)
                  : Colors.grey[60].withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (highlighted ? const Color(0xFF2ECC71) : Colors.grey[100])
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
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
                        Text(title, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w600)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF2ECC71), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.typography.caption),
                  ],
                ),
              ),
              Icon(FluentIcons.chevron_right, size: 16, color: Colors.grey[120]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelOption(ModelInfo model) {
    final theme = FluentTheme.of(context);
    final isSelected = _selectedModelId == model.id;
    final isDefault = model.id == AppConstants.kDefaultModelId;
    final name = _localizedModelName(model);
    final desc = _localizedModelDesc(model);

    return GestureDetector(
      onTap: () => setState(() => _selectedModelId = model.id),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2ECC71).withValues(alpha: 0.12)
              : Colors.grey[40].withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
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
                  color: isSelected ? const Color(0xFF2ECC71) : Colors.grey[100],
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2ECC71),
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
                        child: Text(name, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _l10n.recommended,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF2ECC71), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(child: Text(desc, style: theme.typography.caption?.copyWith(fontSize: 11))),
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
                          model.hasPunctuation ? _l10n.builtInPunctuation : _l10n.needsPunctuationModel,
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

  String _localizedModelName(ModelInfo model) {
    switch (model.id) {
      case 'sensevoice_zh_en_int8': return _l10n.modelSenseVoiceName;
      case 'sensevoice_zh_en_int8_2025': return _l10n.modelSenseVoice2025Name;
      case 'offline_paraformer_zh': return _l10n.modelOfflineParaformerName;
      case 'offline_paraformer_dialect_2025': return _l10n.modelParaformerDialectName;
      case 'whisper_large_v3': return _l10n.modelWhisperName;
      case 'fire_red_asr_large': return _l10n.modelFireRedName;
      default: return model.name;
    }
  }

  String _localizedModelDesc(ModelInfo model) {
    switch (model.id) {
      case 'sensevoice_zh_en_int8': return _l10n.modelSenseVoiceDesc;
      case 'sensevoice_zh_en_int8_2025': return _l10n.modelSenseVoice2025Desc;
      case 'offline_paraformer_zh': return _l10n.modelOfflineParaformerDesc;
      case 'offline_paraformer_dialect_2025': return _l10n.modelParaformerDialectDesc;
      case 'whisper_large_v3': return _l10n.modelWhisperDesc;
      case 'fire_red_asr_large': return _l10n.modelFireRedDesc;
      default: return model.description;
    }
  }

  // Step 2: Download
  Widget _buildDownloadStep() {
    final theme = FluentTheme.of(context);
    final selectedModel = _modelManager.getModelById(_selectedModelId);
    final modelName = selectedModel != null
        ? _localizedModelName(selectedModel)
        : _selectedModelId;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(FluentIcons.cloud_download, size: 64, color: Colors.grey[120]),
        const SizedBox(height: 24),
        Text(_l10n.onboardingDownloadTitle, style: theme.typography.title?.copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(_l10n.onboardingDownloading(modelName), style: theme.typography.caption),
        const SizedBox(height: 32),

        // Progress
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[40].withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              ProgressBar(value: _downloadProgress * 100),
              const SizedBox(height: 12),
              Text(_downloadStatus, style: theme.typography.body),
              if (_downloadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadError!.length > 100
                      ? "${_downloadError!.substring(0, 100)}..."
                      : _downloadError!,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),

        if (_downloadComplete)
          FilledButton(onPressed: _nextStep, child: Text(_l10n.onboardingContinue))
        else if (_downloadError != null)
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Button(onPressed: _downloadSelectedModel, child: Text(_l10n.onboardingRetry)),
                  const SizedBox(width: 12),
                  Button(onPressed: _importModel, child: Text(_l10n.importModel)),
                  const SizedBox(width: 12),
                  HyperlinkButton(
                    onPressed: _nextStep,
                    child: Text(_l10n.onboardingSkip),
                  ),
                ],
              ),
            ],
          )
        else if (_isDownloading)
          const ProgressRing()
        else
          FilledButton(onPressed: _downloadSelectedModel, child: Text(_l10n.onboardingStartDownload)),
      ],
    );
  }

  // Step 3: Done
  Widget _buildDoneStep() {
    final theme = FluentTheme.of(context);
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
          child: Icon(FluentIcons.check_mark, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 32),
        Text(_l10n.onboardingDoneTitle, style: theme.typography.title?.copyWith(fontSize: 28)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[40].withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ConfigService().pttKeyName,
                      style: theme.typography.body?.copyWith(fontSize: 16, fontFamily: 'Consolas'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_l10n.onboardingHoldToSpeak, style: theme.typography.body),
                ],
              ),
              const SizedBox(height: 8),
              Text(_l10n.onboardingDoneDesc, style: theme.typography.caption),
            ],
          ),
        ),
        const SizedBox(height: 48),
        FilledButton(onPressed: _finish, child: Text(_l10n.onboardingBegin)),
      ],
    );
  }
}
