import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_service.dart';
import '../engine/model_manager.dart';
import '../engine/core_engine.dart';
import '../config/app_constants.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'theme.dart';

/// Onboarding flow for first-time users
/// Steps: Welcome -> Permissions -> Model Download -> Done
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
  bool _accessibilityGranted = false;
  bool _microphoneGranted = false;
  bool _checkingPermissions = false;
  
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
    
    // Check accessibility (keyboard listener)
    _accessibilityGranted = _engine.checkAccessibilityPermission();
    
    // Check microphone
    _microphoneGranted = _engine.checkMicPermission();
    
    setState(() => _checkingPermissions = false);
  }

  Future<void> _openAccessibilitySettings() async {
    // Open System Preferences -> Security & Privacy -> Accessibility
    final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    // Re-check after user returns
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openMicrophoneSettings() async {
    // Open System Preferences -> Security & Privacy -> Microphone
    final uri = Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _downloadDefaultModels() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = "准备下载...";
      _downloadError = null;
    });

    try {
      // Step 1: Download punctuation model (required)
      setState(() => _downloadStatus = "下载标点模型...");
      await _modelManager.downloadPunctuationModel(
        onProgress: (p) {
          if (mounted) setState(() {
            _downloadProgress = p * 0.3; // 30% for punctuation
            _downloadStatus = "下载标点模型... ${(p * 100).toStringAsFixed(0)}%";
          });
        },
        onStatus: (s) {
          if (mounted) setState(() => _downloadStatus = s);
        },
      );

      // Step 2: Download ASR model (using default from AppConstants)
      final defaultModel = _modelManager.getModelById(AppConstants.kDefaultModelId) ?? ModelManager.availableModels.first;
      setState(() {
        _downloadStatus = "下载语音识别模型...";
        _downloadProgress = 0.3;
      });
      
      await _modelManager.downloadAndExtractModel(
        defaultModel.id,
        onProgress: (p) {
          if (mounted) setState(() {
            // -1 means extraction phase
            if (p < 0) {
              _downloadStatus = "解压中...";
            } else {
              _downloadProgress = 0.3 + (p * 0.7); // 70% for ASR
              _downloadStatus = "下载语音识别模型... ${(p * 100).toStringAsFixed(0)}%";
            }
          });
        },
      );

      // Step 3: Activate model
      setState(() => _downloadStatus = "激活模型...");
      await _modelManager.setActiveModel(defaultModel.id);
      final path = await _modelManager.getActiveModelPath();
      if (path != null) {
        await _engine.initASR(path, modelType: defaultModel.type);
      }
      await ConfigService().setActiveModelId(defaultModel.id);
      
      // Initialize punctuation
      final punctPath = await _modelManager.getPunctuationModelPath();
      if (punctPath != null) {
        await _engine.initPunctuation(punctPath);
      }

      setState(() {
        _isDownloading = false;
        _downloadComplete = true;
        _downloadProgress = 1.0;
        _downloadStatus = "下载完成!";
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadError = e.toString();
        _downloadStatus = "下载失败";
      });
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
      
      // Auto-start download when reaching download step
      if (_currentStep == 2 && !_downloadComplete && !_isDownloading) {
        _downloadDefaultModels();
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
                    width: 500,
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
        return _buildDownloadStep();
      case 3:
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
        // App Icon
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
          "欢迎使用子曰",
          style: AppTheme.display(context).copyWith(fontSize: 28),
        ),
        const SizedBox(height: 16),
        
        Text(
          "按住快捷键说话，松开后自动输入文字\n支持中英文混合识别",
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
          child: const Text("开始设置"),
        ),
      ],
    );
  }

  // Step 1: Permissions
  Widget _buildPermissionsStep() {
    final allGranted = _accessibilityGranted && _microphoneGranted;
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MacosIcon(CupertinoIcons.shield_lefthalf_fill, size: 64, color: MacosColors.systemGrayColor),
        const SizedBox(height: 24),
        
        Text("需要授权权限", style: AppTheme.display(context).copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text("为了正常工作，子曰需要以下权限", style: AppTheme.caption(context)),
        const SizedBox(height: 32),
        
        // Accessibility Permission
        _buildPermissionTile(
          icon: CupertinoIcons.keyboard,
          title: "辅助功能",
          description: "用于监听快捷键触发录音",
          granted: _accessibilityGranted,
          onRequest: _openAccessibilitySettings,
        ),
        const SizedBox(height: 16),
        
        // Microphone Permission
        _buildPermissionTile(
          icon: CupertinoIcons.mic,
          title: "麦克风",
          description: "用于录制语音进行识别",
          granted: _microphoneGranted,
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
                  child: const Text("刷新状态"),
                ),
              const SizedBox(width: 12),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: allGranted ? _nextStep : null,
                child: Text(allGranted ? "继续" : "请先授权"),
              ),
            ],
          ),
        
        const SizedBox(height: 16),
        if (!allGranted)
          TextButton(
            onPressed: _nextStep,
            child: Text("稍后设置", style: TextStyle(color: MacosColors.systemGrayColor)),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted 
            ? Colors.green.withOpacity(0.1) 
            : MacosColors.systemGrayColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted ? Colors.green.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          MacosIcon(icon, size: 28, color: granted ? Colors.green : MacosColors.systemGrayColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                Text(description, style: AppTheme.caption(context)),
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
              child: const Text("授权"),
            ),
        ],
      ),
    );
  }

  // Step 2: Download
  Widget _buildDownloadStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MacosIcon(CupertinoIcons.cloud_download, size: 64, color: MacosColors.systemGrayColor),
        const SizedBox(height: 24),
        
        Text("下载语音模型", style: AppTheme.display(context).copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text("首次使用需要下载约 1GB 的语音识别模型", style: AppTheme.caption(context)),
        const SizedBox(height: 32),
        
        // Progress
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MacosColors.systemGrayColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 12,
                  backgroundColor: MacosColors.systemGrayColor.withOpacity(0.2),
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
            child: const Text("继续"),
          )
        else if (_downloadError != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: _downloadDefaultModels,
                child: const Text("重试"),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _nextStep,
                child: Text("跳过", style: TextStyle(color: MacosColors.systemGrayColor)),
              ),
            ],
          )
        else if (_isDownloading)
          const CupertinoActivityIndicator()
        else
          PushButton(
            controlSize: ControlSize.large,
            onPressed: _downloadDefaultModels,
            child: const Text("开始下载"),
          ),
      ],
    );
  }

  // Step 3: Done
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
        
        Text("设置完成!", style: AppTheme.display(context).copyWith(fontSize: 28)),
        const SizedBox(height: 16),
        
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withOpacity(0.1),
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
                      color: MacosColors.systemGrayColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ConfigService().pttKeyName,
                      style: AppTheme.mono(context).copyWith(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text("按住说话", style: AppTheme.body(context)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "松开后自动输入到当前光标位置",
                style: AppTheme.caption(context),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 48),
        
        PushButton(
          controlSize: ControlSize.large,
          onPressed: _finish,
          child: const Text("开始使用"),
        ),
      ],
    );
  }
}
