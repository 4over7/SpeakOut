import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_service.dart';
import '../services/app_service.dart';
import '../config/app_constants.dart';
import '../engine/model_manager.dart';
import '../engine/core_engine.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'theme.dart';
import 'widgets/settings_widgets.dart';
import '../services/audio_device_service.dart';
import 'package:speakout/config/app_log.dart';
import 'vocab_settings_page.dart';
import '../services/update_service.dart';
import '../services/llm_service.dart';
import '../services/cloud_account_service.dart';
import '../config/cloud_providers.dart';
import '../models/cloud_account.dart';
// import 'billing_page.dart'; // 暂时隐藏
import '../services/config_backup_service.dart';
import 'cloud_accounts_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ModelManager _modelManager = ModelManager();
  final CoreEngine _engine = CoreEngine();
  
  int _selectedIndex = 0;
  late MacosTabController _tabController;

  // Model State
  final Map<String, bool> _downloadedStatus = {};
  final Set<String> _downloadingIds = {}; // Support concurrent downloads
  final Map<String, double?> _downloadProgressMap = {}; // Per-model progress (null = indeterminate)
  final Map<String, String> _downloadStatusMap = {}; // Per-model status text
  String? _activatingId; // Only one model can be activating at a time
  String? _activeModelId;
  
  final TextEditingController _akIdController = TextEditingController();
  final TextEditingController _akSecretController = TextEditingController();
  final TextEditingController _appKeyController = TextEditingController();
  late final TextEditingController _aiPromptController;
  late final TextEditingController _organizePromptController;
  // LLM API config controllers (persistent to survive setState rebuilds)
  final TextEditingController _llmApiKeyController = TextEditingController();
  final TextEditingController _llmBaseUrlController = TextEditingController();
  final TextEditingController _llmModelController = TextEditingController();
  // 自定义模型输入框（选"自定义..."时显示）
  final TextEditingController _llmCustomModelController = TextEditingController();
  // 是否处于自定义模型模式（仅用户主动选"自定义..."时才为 true）
  bool _llmModelCustom = false;

  // Hotkey State
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  bool _isCapturingKey = false;
  // Diary Hotkey
  String _diaryKeyName = "Right Option";
  bool _isCapturingDiaryKey = false;
  // Toggle Hotkeys
  String _toggleInputKeyName = "";
  String _toggleDiaryKeyName = "";
  bool _isCapturingToggleInputKey = false;
  bool _isCapturingToggleDiaryKey = false;
  bool _isCapturingOrganizeKey = false;
  bool _isCheckingUpdate = false;
  bool _versionCopied = false;
  String? _updateResult;
  int _toggleMaxDuration = 0;
  // LLM Test
  bool _isTestingLlm = false;
  (bool, String)? _llmTestResult;
  bool _llmConfigDirty = false; // True when LLM config has unsaved changes
  bool _workModeAdvancedExpanded = false;
  // 笔记目录写入权限验证结果（null = 未验证 / '' = 验证通过 / 非空 = 错误信息）
  String? _diaryDirError;

  final FocusNode _keyCaptureFocusNode = FocusNode();
  StreamSubscription<(int, int)>? _keySubscription;

  // UI State
  String _version = "";
  
  // Audio Device State
  List<AudioDevice> _audioDevices = [];
  AudioDevice? _currentAudioDevice;
  bool _autoManageAudio = true;

  @override
  void initState() {
    super.initState();
    _aiPromptController = TextEditingController(text: ConfigService().aiCorrectionPrompt);
    _loadVersion();
    _organizePromptController = TextEditingController(text: ConfigService().organizePrompt);
    _tabController = MacosTabController(initialIndex: 0, length: 7);
    _tabController.addListener(() {
      final newIndex = _tabController.index;
      // Warn if leaving Work Mode tab with unsaved LLM changes
      if (_selectedIndex == 1 && newIndex != 1 && _llmConfigDirty) {
        _showUnsavedChangesDialog(newIndex);
        return;
      }
      setState(() => _selectedIndex = newIndex);
    });
    
    _refresh();
    _loadHotkeyConfig();
    _loadActiveModel();
    _loadAliyunConfig();
    _loadAudioDevices();
    // 监听设备插拔，自动刷新列表
    _deviceChangeSubscription = _engine.audioDeviceService?.deviceChanges.listen((_) {
      if (mounted) _loadAudioDevices();
    });
  }

  StreamSubscription? _deviceChangeSubscription;
  bool _useSystemDefaultAudio = true;

  void _loadAudioDevices() {
    final service = _engine.audioDeviceService;
    if (service == null) return;
    service.refreshDevices();
    setState(() {
      _audioDevices = service.devices;
      _currentAudioDevice = service.currentDevice;
      _autoManageAudio = service.autoManageEnabled;
      _useSystemDefaultAudio = service.isUsingSystemDefault;
    });
  }
  
  Future<void> _loadAliyunConfig() async {
    final s = ConfigService();
    setState(() {
      _akIdController.text = s.aliyunAccessKeyId;
      _akSecretController.text = s.aliyunAccessKeySecret;
      _appKeyController.text = s.aliyunAppKey;
    });
  }
  
  @override
  void dispose() {
    _keySubscription?.cancel();
    _deviceChangeSubscription?.cancel();
    _keyCaptureFocusNode.dispose();
    _tabController.dispose();
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
  
  Future<void> _loadActiveModel() async {
    setState(() => _activeModelId = ConfigService().activeModelId);
  }
  
  Future<void> _loadHotkeyConfig() async {
    final service = ConfigService();
    setState(() {
      _currentKeyCode = service.pttKeyCode;
      _currentKeyName = service.pttKeyName;
      _diaryKeyName = service.diaryKeyName;
      _toggleInputKeyName = service.toggleInputKeyName;
      _toggleDiaryKeyName = service.toggleDiaryKeyName;
      _toggleMaxDuration = service.toggleMaxDuration;
    });
    _engine.pttKeyCode = _currentKeyCode;
  }
  
  /// Build a display name for a key + modifier combo
  String _comboKeyName(int keyCode, int modifiers) {
    final parts = <String>[];
    if (modifiers & 0x0008 != 0) parts.add('L.Cmd');
    if (modifiers & 0x0010 != 0) parts.add('R.Cmd');
    if (modifiers & 0x0001 != 0) parts.add('L.Ctrl');
    if (modifiers & 0x2000 != 0) parts.add('R.Ctrl');
    if (modifiers & 0x0020 != 0) parts.add('L.Opt');
    if (modifiers & 0x0040 != 0) parts.add('R.Opt');
    if (modifiers & 0x0002 != 0) parts.add('L.Shift');
    if (modifiers & 0x0004 != 0) parts.add('R.Shift');
    parts.add(_mapKeyCodeToString(keyCode));
    return parts.join(' + ');
  }

  /// Strip the trigger key's own modifier from flags
  int _stripOwnModifier(int keyCode, int flags) {
    const ownMasks = {58: 0x0020, 61: 0x0040, 56: 0x0002, 60: 0x0004, 55: 0x0008, 54: 0x0010, 59: 0x0001, 62: 0x2000};
    return flags & ~(ownMasks[keyCode] ?? 0);
  }

  Future<void> _saveHotkeyConfig(int keyCode, String keyName, {int modifierFlags = 0}) async {
    final config = ConfigService();
    final isInputGroup = _isCapturingKey || _isCapturingToggleInputKey;
    final isDiaryGroup = _isCapturingDiaryKey || _isCapturingToggleDiaryKey;

    // Strip the trigger key's own modifier bit (e.g., Right Option press includes its own flag)
    final requiredMods = _stripOwnModifier(keyCode, modifierFlags);
    final displayName = requiredMods != 0 ? _comboKeyName(keyCode, requiredMods) : keyName;

    // Cross-group conflict check: input keys vs diary keys (skip disabled keys = 0)
    if (isInputGroup) {
      final diaryKeys = [config.diaryKeyCode, config.toggleDiaryKeyCode].where((k) => k != 0);
      if (diaryKeys.contains(keyCode)) {
        _showHotkeyConflict(displayName, true);
        return;
      }
    } else if (isDiaryGroup) {
      final inputKeys = [config.pttKeyCode, config.toggleInputKeyCode].where((k) => k != 0);
      if (inputKeys.contains(keyCode)) {
        _showHotkeyConflict(displayName, false);
        return;
      }
    }

    if (_isCapturingOrganizeKey) {
       // AI 梳理快捷键与所有录音键冲突检测
       final allRecordingKeys = [config.pttKeyCode, config.diaryKeyCode, config.toggleInputKeyCode, config.toggleDiaryKeyCode].where((k) => k != 0);
       if (allRecordingKeys.contains(keyCode)) {
         _stopKeyCapture();
         return;
       }
       await config.setOrganizeKey(keyCode, displayName, modifiers: requiredMods);
       setState(() => _isCapturingOrganizeKey = false);
    } else if (_isCapturingToggleInputKey) {
       await config.setToggleInputKey(keyCode, displayName, modifiers: requiredMods);
       setState(() {
         _toggleInputKeyName = displayName;
         _isCapturingToggleInputKey = false;
       });
    } else if (_isCapturingToggleDiaryKey) {
       await config.setToggleDiaryKey(keyCode, displayName, modifiers: requiredMods);
       setState(() {
         _toggleDiaryKeyName = displayName;
         _isCapturingToggleDiaryKey = false;
       });
    } else if (_isCapturingDiaryKey) {
       await config.setDiaryKey(keyCode, displayName, modifiers: requiredMods);
       setState(() {
         _diaryKeyName = displayName;
         _isCapturingDiaryKey = false;
       });
    } else {
       await config.setPttKey(keyCode, displayName, modifiers: requiredMods);
       _engine.pttKeyCode = keyCode;
       setState(() {
         _currentKeyCode = keyCode;
         _currentKeyName = displayName;
         _isCapturingKey = false;
       });
    }
  }

  void _showHotkeyConflict(String keyName, bool conflictsWithDiary) {
    final loc = AppLocalizations.of(context)!;
    final target = conflictsWithDiary ? loc.diaryMode : loc.tabTrigger;
    _stopKeyCapture();
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: Colors.orange),
        title: Text('$keyName 已被 $target 使用', style: const TextStyle(fontWeight: FontWeight.bold)),
        message: const Text('文本注入和闪念笔记不能使用相同的热键，请选择其他按键。'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('好的'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
  
  // --- Key Capture Logic ---
  void _startKeyCapture([String target = 'ptt']) {
    setState(() {
       switch (target) {
         case 'toggleInput': _isCapturingToggleInputKey = true;
         case 'toggleDiary': _isCapturingToggleDiaryKey = true;
         case 'diary': _isCapturingDiaryKey = true;
         case 'organize': _isCapturingOrganizeKey = true;
         default: _isCapturingKey = true;
       }
    });

    _keySubscription = _engine.rawKeyEventStream.listen((event) {
       final (keyCode, modifierFlags) = event;
       final keyName = _mapKeyCodeToString(keyCode);
       _saveHotkeyConfig(keyCode, keyName, modifierFlags: modifierFlags);
       _stopKeyCapture();
    });
    // Timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && (_isCapturingKey || _isCapturingDiaryKey || _isCapturingToggleInputKey || _isCapturingToggleDiaryKey || _isCapturingOrganizeKey)) {
        _stopKeyCapture();
      }
    });
  }
  
  String _mapKeyCodeToString(int keyCode) {
      if (keyCode == 63) return "FN";
      if (keyCode == 58) return "Left Option";
      if (keyCode == 61) return "Right Option";
      if (keyCode == 55) return "Left Command";
      if (keyCode == 54) return "Right Command"; 
      if (keyCode == 56) return "Left Shift";
      if (keyCode == 60) return "Right Shift";
      if (keyCode == 59) return "Left Control";
      if (keyCode == 62) return "Right Control";
      if (keyCode == 49) return "Space";
      if (keyCode == 36) return "Return";
      if (keyCode == 48) return "Tab";
      if (keyCode == 51) return "Delete";
      if (keyCode == 53) return "Escape";
      return "Key $keyCode";
  }

  void _stopKeyCapture() {
    _keySubscription?.cancel();
    _keySubscription = null;
    if (mounted) {
      setState(() {
        _isCapturingKey = false;
        _isCapturingDiaryKey = false;
        _isCapturingToggleInputKey = false;
        _isCapturingToggleDiaryKey = false;
        _isCapturingOrganizeKey = false;
      });
    }
  }

  Future<void> _pickDiaryFolder() async {
    try {
      final String? outputDir = await const MethodChannel('com.SpeakOut/overlay').invokeMethod('pickDirectory');
      if (outputDir != null) {
        await ConfigService().setDiaryDirectory(outputDir);
        await _validateDiaryDirectory();
        setState((){});
      }
    } catch (e) {
      AppLog.d("Pick Directory Failed: $e");
    }
  }

  /// 测试笔记目录是否可写，更新 [_diaryDirError]。
  Future<void> _validateDiaryDirectory() async {
    final dirPath = ConfigService().diaryDirectory;
    if (dirPath.isEmpty) {
      setState(() => _diaryDirError = '未设置保存目录');
      return;
    }
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final testFile = File('${dir.path}/.speakout_write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      setState(() => _diaryDirError = '');
    } catch (e) {
      setState(() => _diaryDirError = '无法写入目录，请重新选择（macOS 需重新授权）');
    }
  }

  Future<void> _refresh() async {
    for (var m in ModelManager.allModels) {
      _downloadedStatus[m.id] = await _modelManager.isModelDownloaded(m.id);
    }
    _downloadedStatus[ModelManager.punctuationModelId] = await _modelManager.isPunctuationModelDownloaded();
    setState(() {});
  }

  // --- Download & Actions ---
  // (Simplified for brevity in rewrite, keeping core logic)
  Future<void> _download(ModelInfo model) async {
     final loc = AppLocalizations.of(context)!;
     // Add to downloading set
     setState(() { 
       _downloadingIds.add(model.id); 
       _downloadProgressMap[model.id] = 0;
       _downloadStatusMap[model.id] = loc.preparing;
     });
     
     try {
       await _modelManager.downloadAndExtractModel(model.id,
         onProgress: (p) {
            if(mounted) {
              setState(() {
                _downloadProgressMap[model.id] = p < 0 ? null : p;
                _downloadStatusMap[model.id] = p < 0
                    ? "解压中..."
                    : loc.downloading((p*100).toStringAsFixed(0));
              });
            }
         }
       );
       await _refresh();
     } catch(e) { _showError(e.toString()); }
     finally {
       if(mounted) setState(() { _downloadingIds.remove(model.id); });
     }
  }
  
  Future<void> _activate(ModelInfo model) async {
    // Check if switching between streaming ↔ offline mode
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
        // 初始化失败 → 回滚到之前的模型
        if (previousModelId != null) {
          await _modelManager.setActiveModel(previousModelId);
          await ConfigService().setActiveModelId(previousModelId);
        }
        setState(() { _activatingId = null; });
        if (mounted) _showError('模型激活失败: $e');
        return;
      }
      // 模型无内置标点 → 提示用户 + 自动加载标点模型
      if (!model.hasPunctuation) {
        final punctPath = await _modelManager.getPunctuationModelPath();
        if (punctPath != null) {
          await _engine.initPunctuation(punctPath, activeModelName: model.name);
          if (mounted) {
            _showInfoSnackBar('已自动加载标点模型');
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
      _showError(e.toString());
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
            if(mounted) {
              setState(() {
                _downloadProgressMap[punctId] = p;
                _downloadStatusMap[punctId] = loc.downloading((p*100).toStringAsFixed(0));
              });
            }
          },
          onStatus: (s) {
             if(mounted) {
               setState(() { _downloadStatusMap[punctId] = s; });
             }
          }
        );
        await _refresh();
        final path = await _modelManager.getPunctuationModelPath();
        if (path != null) await _engine.initPunctuation(path);
      } catch(e) { _showError(e.toString()); }
      finally { 
        if(mounted) setState(() { _downloadingIds.remove(punctId); }); 
      }
  }
  
  Future<void> _deletePunctuation() async {
    await _modelManager.deletePunctuationModel();
    await _refresh();
  }

  void _showInfoSnackBar(String msg) {
    if (!mounted) return;
    _engine.updateStatus('ℹ️ $msg');
  }

  void _showError(String msg) {
    // Sanitize long URLs
    String cleanMsg = msg.replaceAll(RegExp(r'uri=https?:\/\/[^\s,]+'), '[URL]');
    
    // Translate common errors
    if (cleanMsg.contains("ClientException") || cleanMsg.contains("SocketException")) {
       cleanMsg = "网络连接失败，请检查网络设置。\n\n详细信息: $cleanMsg";
    }
    
    // Limits
    if (cleanMsg.length > 300) {
      cleanMsg = "${cleanMsg.substring(0, 300)}...";
    }
    
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        title: const Text("Error"), message: Text(cleanMsg),
        primaryButton: PushButton(controlSize: ControlSize.large, onPressed: () => Navigator.pop(context), child: const Text("OK")),
      ),
    );
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = "${info.version}+${info.buildNumber}");
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return MacosWindow(
      backgroundColor: AppTheme.getBackground(context),
      disableWallpaperTinting: true, // Disable vibrancy so sidebar uses our explicit colors
      sidebar: Sidebar(
        minWidth: 200,
        decoration: BoxDecoration(
          color: AppTheme.getSidebarBackground(context),
        ),
        builder: (context, scrollController) {
          final unselectedColor = MacosTheme.brightnessOf(context) == Brightness.dark
              ? MacosColors.systemGrayColor
              : const Color(0xFF6E6E73); // Visible gray for light sidebar
          return SidebarItems(
            currentIndex: _selectedIndex,
            onChanged: (i) => setState(() => _selectedIndex = i),
            selectedColor: AppTheme.accentColor.withValues(alpha:0.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            items: [
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.settings, color: _selectedIndex == 0 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabGeneral, style: TextStyle(color: _selectedIndex == 0 ? AppTheme.accentColor : unselectedColor)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.waveform_circle_fill, color: _selectedIndex == 1 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabWorkMode, style: TextStyle(color: _selectedIndex == 1 ? AppTheme.accentColor : unselectedColor)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.hand_draw, color: _selectedIndex == 2 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabTrigger, style: TextStyle(color: _selectedIndex == 2 ? AppTheme.accentColor : unselectedColor)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.text_alignleft, color: _selectedIndex == 3 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabOrganize, style: TextStyle(color: _selectedIndex == 3 ? AppTheme.accentColor : unselectedColor)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.book, color: _selectedIndex == 4 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.diaryMode, style: TextStyle(color: _selectedIndex == 4 ? AppTheme.accentColor : unselectedColor)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.cloud, color: _selectedIndex == 5 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabCloudAccounts, style: TextStyle(color: _selectedIndex == 5 ? AppTheme.accentColor : unselectedColor)),
              ),
              // 订阅 tab 暂时隐藏，等支付宝/Stripe 开通后恢复
              // SidebarItem(
              //   leading: MacosIcon(CupertinoIcons.creditcard, color: _selectedIndex == 6 ? AppTheme.accentColor : unselectedColor),
              //   label: Text('订阅', style: TextStyle(color: _selectedIndex == 6 ? AppTheme.accentColor : unselectedColor)),
              // ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.info_circle, color: _selectedIndex == 6 ? AppTheme.accentColor : unselectedColor),
                label: Text(loc.tabAbout, style: TextStyle(color: _selectedIndex == 6 ? AppTheme.accentColor : unselectedColor)),
              ),
            ],
          );
        },
      ),
      child: MacosScaffold(
        backgroundColor: AppTheme.getBackground(context), // Match mockup
        toolBar: ToolBar(
          title: Text(loc.settings), 
          titleWidth: 150.0,
        ),
        children: [
          ContentArea(
            builder: (context, _) {
              return Container(
                color: AppTheme.getBackground(context), // Force background
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Builder(builder: (_) {
                    // Work Mode page manages its own scroll (fixed bottom save bar)
                    if (_selectedIndex == 1) return _buildWorkModeView();
                    // Cloud Accounts page has its own scroll
                    if (_selectedIndex == 5) return const CloudAccountsPage();
                    // if (_selectedIndex == 6) return const BillingPage(); // 暂时隐藏
                    return SingleChildScrollView(
                      child: Builder(builder: (_) {
                         if (_selectedIndex == 0) return _buildGeneralView();
                         if (_selectedIndex == 2) return _buildTriggerView();
                         if (_selectedIndex == 3) return _buildOrganizeView();
                         if (_selectedIndex == 4) return _buildDiaryView();
                         return _buildAboutView(context, _version);
                      }),
                    );
                  }),
                ),
              );
            },
          ),
        ],
      )
    );
  }
  
  // --- View: Work Mode (merged Models + AI Polish) ---
  Widget _buildWorkModeView() {
    final loc = AppLocalizations.of(context)!;
    final currentMode = ConfigService().workMode;
    final currentPresetId = ConfigService().llmPresetId;
    final provider = CloudProviders.getById(currentPresetId);
    final isTranslation = _isTranslationMode();

    return Column(
      children: [
        Expanded(child: SingleChildScrollView(child: Column(
          children: [
            // Language settings (moved from General tab)
            SettingsGroup(
              title: loc.languageSettings,
              children: [
                // Input Language (filtered by cloud ASR model capability in cloud mode)
                SettingsTile(
                  label: loc.inputLanguage,
                  subtitle: loc.inputLanguageDesc,
                  icon: CupertinoIcons.mic,
                  child: _buildDropdown(
                    value: ConfigService().inputLanguage,
                    items: _buildInputLanguageItems(loc),
                    onChanged: (v) async { await ConfigService().setInputLanguage(v!); setState((){}); }
                  ),
                ),
                const SettingsDivider(),
                // Output Language
                SettingsTile(
                  label: loc.outputLanguage,
                  subtitle: loc.outputLanguageDesc,
                  icon: CupertinoIcons.textformat,
                  child: _buildDropdown(
                    value: ConfigService().outputLanguage,
                    items: {
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
                    },
                    onChanged: (v) async { await ConfigService().setOutputLanguage(v!); setState((){}); }
                  ),
                ),
                // Language hints (translation mode info, model compatibility)
                ..._buildLanguageHints(loc),
              ],
            ),

            const SizedBox(height: 16),

            // Mode selector
            SettingsGroup(
              title: loc.tabWorkMode,
              children: [
                _buildModeRadio(
                  value: 'offline',
                  groupValue: currentMode,
                  icon: CupertinoIcons.lock_shield,
                  label: loc.workModeOffline,
                  description: loc.workModeOfflineDesc,
                  enabled: !isTranslation,
                  disabledReason: isTranslation ? loc.translationDisabledReason : null,
                ),
                const SettingsDivider(),
                _buildModeRadio(
                  value: 'smart',
                  groupValue: currentMode,
                  icon: CupertinoIcons.sparkles,
                  label: loc.workModeSmart,
                  description: loc.workModeSmartDesc,
                  badge: loc.recommended,
                ),
                const SettingsDivider(),
                _buildModeRadio(
                  value: 'cloud',
                  groupValue: currentMode,
                  icon: CupertinoIcons.cloud,
                  label: loc.workModeCloud,
                  description: loc.workModeCloudDesc,
                  enabled: !isTranslation,
                  disabledReason: isTranslation ? loc.translationDisabledReason : null,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Mode-specific config
            if (currentMode == 'smart') ...[
              // Warning banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
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
                      child: MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 16, color: MacosColors.systemOrangeColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.aiPolishWarning,
                        style: AppTheme.caption(context).copyWith(
                          color: MacosColors.systemOrangeColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSmartModeConfig(loc),
            ],

            if (currentMode == 'cloud') ...[
              _buildCloudModeConfig(loc),
            ],

            if (currentMode == 'offline') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacosColors.systemGreenColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MacosColors.systemGreenColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const MacosIcon(CupertinoIcons.lock_shield_fill, size: 16, color: MacosColors.systemGreenColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.workModeOfflineIcon,
                        style: AppTheme.caption(context).copyWith(color: MacosColors.systemGreenColor, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Advanced settings (collapsible)
            _buildWorkModeAdvanced(loc, currentMode),

            const SizedBox(height: 24),
          ],
        ))),

        // Fixed bottom save bar (smart mode + cloud LLM only)
        if (currentMode == 'smart' && ConfigService().llmProviderType == 'cloud')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.getBackground(context),
              border: Border(top: BorderSide(color: AppTheme.getBorder(context))),
            ),
            child: Row(
              children: [
                if (_llmConfigDirty)
                  Row(children: [
                    const MacosIcon(CupertinoIcons.circle_fill, size: 8, color: MacosColors.systemOrangeColor),
                    const SizedBox(width: 6),
                    Text("有未保存的修改", style: AppTheme.caption(context).copyWith(color: MacosColors.systemOrangeColor, fontSize: 11)),
                  ])
                else
                  Row(children: [
                    MacosIcon(CupertinoIcons.checkmark_circle, size: 14, color: MacosColors.systemGrayColor.resolveFrom(context)),
                    const SizedBox(width: 6),
                    Text(provider?.name ?? currentPresetId, style: AppTheme.caption(context).copyWith(fontSize: 11)),
                  ]),
                const Spacer(),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _isTestingLlm ? null : () async {
                    setState(() { _isTestingLlm = true; _llmTestResult = null; });
                    try {
                      // 从账户凭证中读取（与 LLMService._resolveLlmConfig 逻辑一致）
                      final llmAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.llm);
                      final savedId = ConfigService().selectedLlmAccountId ?? '';
                      final effectiveId = llmAccounts.any((a) => a.id == savedId) ? savedId : (llmAccounts.isNotEmpty ? llmAccounts.first.id : '');
                      final testAccount = effectiveId.isNotEmpty ? CloudAccountService().getAccountById(effectiveId) : null;
                      final testProvider = testAccount != null ? CloudProviders.getById(testAccount.providerId) : null;
                      final testApiKey = testAccount?.credentials['api_key'] ?? _llmApiKeyController.text;
                      final testBaseUrl = testProvider?.llmBaseUrl ?? _llmBaseUrlController.text;
                      final savedModel = ConfigService().llmModelOverride;
                      final testModel = (savedModel != null && savedModel.isNotEmpty)
                          ? savedModel
                          : (testProvider?.llmDefaultModel ?? _llmModelController.text);
                      final (ok, msg) = await LLMService().testConnectionWith(
                        apiKey: testApiKey,
                        baseUrl: testBaseUrl,
                        model: testModel,
                        apiFormat: testProvider?.llmApiFormat ?? LlmApiFormat.openai,
                      );
                      if (mounted) setState(() { _isTestingLlm = false; _llmTestResult = (ok, msg); });
                    } catch (e) {
                      if (mounted) setState(() { _isTestingLlm = false; _llmTestResult = (false, e.toString()); });
                    }
                  },
                  child: _isTestingLlm
                    ? const SizedBox(width: 14, height: 14, child: ProgressCircle())
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        MacosIcon(CupertinoIcons.antenna_radiowaves_left_right, size: 14),
                        SizedBox(width: 4),
                        Text("测试"),
                      ]),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: _llmConfigDirty ? () async {
                    try {
                      await _flushLlmControllers();
                      await ConfigService().savePresetConfig(currentPresetId);
                      if (mounted) setState(() { _llmConfigDirty = false; });
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("保存失败: $e"), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating),
                        );
                      }
                    }
                  } : null,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    MacosIcon(CupertinoIcons.checkmark_circle, size: 14),
                    SizedBox(width: 4),
                    Text("保存"),
                  ]),
                ),
              ],
            ),
          ),
        // Test result (below save bar)
        if (_llmTestResult != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.getBackground(context),
            ),
            child: Row(children: [
              Icon(
                _llmTestResult!.$1 ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.xmark_circle_fill,
                size: 14,
                color: _llmTestResult!.$1 ? AppTheme.successColor : AppTheme.errorColor,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(
                _llmTestResult!.$2,
                style: TextStyle(fontSize: 12, color: _llmTestResult!.$1 ? AppTheme.successColor : AppTheme.errorColor),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              )),
            ]),
          ),
      ],
    );
  }

  /// Mode color: offline=green, smart=blue, cloud=orange
  Color _modeColor(String mode) {
    switch (mode) {
      case 'offline': return MacosColors.systemGreenColor;
      case 'smart': return MacosColors.systemBlueColor;
      case 'cloud': return MacosColors.systemOrangeColor;
      default: return MacosColors.systemGrayColor;
    }
  }

  Widget _buildModeRadio({
    required String value,
    required String groupValue,
    required IconData icon,
    required String label,
    required String description,
    String? badge,
    bool enabled = true,
    String? disabledReason,
  }) {
    final isSelected = value == groupValue;
    final color = _modeColor(value);
    final disabledColor = MacosColors.systemGrayColor.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: enabled ? () => _switchWorkMode(value) : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          decoration: isSelected ? BoxDecoration(
            color: color.withValues(alpha: 0.06),
            border: Border(left: BorderSide(color: color, width: 3)),
          ) : null,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              MacosIcon(icon, size: 20, color: isSelected ? color : MacosColors.systemGrayColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTheme.body(context).copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? color : null,
                    )),
                    const SizedBox(height: 2),
                    Text(description, style: AppTheme.caption(context).copyWith(
                      color: MacosColors.secondaryLabelColor.resolveFrom(context),
                    )),
                    if (!enabled && disabledReason != null) ...[
                      const SizedBox(height: 4),
                      Text(disabledReason, style: TextStyle(
                        fontSize: 11,
                        color: disabledColor,
                      )),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
              ],
              MacosRadioButton<String>(
                groupValue: groupValue,
                value: value,
                onChanged: enabled ? (v) => _switchWorkMode(v) : null,
              ),
            ],
          ),
        ),
      ),
    );
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
    if (mode == 'cloud' && oldMode != 'cloud') {
      await _engine.initASR('', modelType: 'aliyun');
    } else if (mode != 'cloud' && oldMode == 'cloud') {
      final path = await _modelManager.getActiveModelPath();
      final model = _modelManager.getModelById(_activeModelId ?? '');
      if (path != null && model != null) {
        await _engine.initASR(path, modelType: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
        // 模型无内置标点 → 自动加载标点模型
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

  Widget _buildSmartModeConfig(AppLocalizations loc) {
    return SettingsGroup(
      title: loc.workModeSmartConfig,
      children: [
        SettingsTile(
          label: '打字机效果（Alpha）',
          subtitle: '流式逐步注入文字到光标处，会临时占用剪贴板。',
          icon: CupertinoIcons.text_cursor,
          child: Row(
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
                onChanged: (v) async { await ConfigService().setTypewriterEnabled(v); setState((){}); },
              ),
            ],
          ),
        ),
        const SettingsDivider(),
        SettingsTile(
          label: loc.llmProvider,
          icon: CupertinoIcons.arrow_right_arrow_left,
          child: MacosPopupButton<String>(
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
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // System Prompt
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loc.systemPrompt, style: AppTheme.body(context)),
                  GestureDetector(
                    onTap: () async {
                      await ConfigService().setAiCorrectionPrompt(AppConstants.kDefaultAiCorrectionPrompt);
                      _aiPromptController.text = AppConstants.kDefaultAiCorrectionPrompt;
                      setState((){});
                    },
                    child: Text(loc.resetDefault, style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, fontSize: 11)),
                  )
                ],
              ),
              const SizedBox(height: 8),
              MacosTextField(
                maxLines: 5,
                placeholder: "Enter instructions for AI...",
                controller: _aiPromptController,
                decoration: BoxDecoration(
                  color: AppTheme.getInputBackground(context),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.getBorder(context)),
                ),
                onChanged: (v) => ConfigService().setAiCorrectionPrompt(v),
              ),
              const SizedBox(height: 16),

              // LLM 配置
              if (ConfigService().llmProviderType == 'cloud') ...[
                _buildCloudLlmAccountSelector(loc),
              ] else ...[
                // Ollama
                Text(loc.ollamaUrl, style: AppTheme.body(context)),
                const SizedBox(height: 4),
                Text("确保 Ollama 已启动（ollama serve）", style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGrayColor)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MacosColors.systemGrayColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildApiItem(context, loc.ollamaUrl, CupertinoIcons.link, ConfigService().ollamaBaseUrl, (v) => ConfigService().setOllamaBaseUrl(v), placeholder: "http://localhost:11434"),
                      const SizedBox(height: 8),
                      _buildApiItem(context, loc.ollamaModel, CupertinoIcons.cube_box, ConfigService().ollamaModel, (v) => ConfigService().setOllamaModel(v), placeholder: "qwen3:0.6b"),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Cloud LLM account selector — replaces old preset-based API Key input
  Widget _buildCloudLlmAccountSelector(AppLocalizations loc) {
    final llmAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.llm);
    final savedId = ConfigService().selectedLlmAccountId ?? '';
    // effectiveId: 已保存的 ID 若不在账户列表中则回退到第一个账户，保证 account/provider 与下拉显示一致
    final effectiveId = llmAccounts.any((a) => a.id == savedId) ? savedId : (llmAccounts.isNotEmpty ? llmAccounts.first.id : '');
    final selectedAccount = effectiveId.isNotEmpty ? CloudAccountService().getAccountById(effectiveId) : null;
    final selectedProvider = selectedAccount != null ? CloudProviders.getById(selectedAccount.providerId) : null;

    if (llmAccounts.isEmpty) {
      // No accounts configured — show hint
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
              onTap: () => setState(() => _selectedIndex = 5), // Navigate to Cloud Accounts tab
              child: Text(loc.cloudAccountGoConfig, style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, decoration: TextDecoration.underline)),
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
                  // 切换服务商时重置模型为该服务商默认，避免旧模型名污染
                  final p = CloudProviders.getById(account.providerId);
                  if (p?.llmDefaultModel != null) await ConfigService().setLlmModel(p!.llmDefaultModel!);
                }
                setState(() => _llmModelCustom = false); // 切换服务商时重置到预设下拉
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Model selector
        _buildLlmModelSelector(selectedAccount, selectedProvider),
        const SizedBox(height: 12),
        // LLM 服务商推荐
        _buildLlmRecommendation(),
      ],
    );
  }

  /// LLM 服务商推荐（基于实测延迟数据）
  Widget _buildLlmRecommendation() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MacosIcon(CupertinoIcons.lightbulb, size: 14, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text('选型参考', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
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
            color: AppTheme.accentColor.withValues(alpha: 0.12),
          ),
          child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
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

  static const String _kCustomModelSentinel = '__custom__';

  /// 模型选择器：预设下拉 + 自定义文本框
  Widget _buildLlmModelSelector(CloudAccount? account, CloudProvider? provider) {
    final presets = provider?.llmModels ?? [];
    final currentModel = ConfigService().llmModelOverride ?? provider?.llmDefaultModel ?? '';

    // _llmModelCustom 只在用户主动选"自定义..."时才为 true。
    // 旧版本残留的不匹配模型名不触发自定义模式，直接显示下拉并默认第一项。
    final showCustom = _llmModelCustom || presets.isEmpty;

    // 下拉当前值
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
          // API Key 来源提示
          Row(
            children: [
              const MacosIcon(CupertinoIcons.checkmark_seal_fill, size: 14, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text(
                account?.displayName ?? provider?.name ?? '',
                style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 模型行
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
                      // 用户主动选"自定义..."
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
          // 自定义输入框（仅在选了"自定义..."时显示）
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
          // 价格提示（预设模式下显示）
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

  Widget _buildCloudModeConfig(AppLocalizations loc) {
    final asrAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.asrStreaming)
      + CloudAccountService().getAccountsWithCapability(CloudCapability.asrBatch);
    // Deduplicate by account id
    final seen = <String>{};
    final uniqueAsrAccounts = asrAccounts.where((a) => seen.add(a.id)).toList();

    final selectedAsrId = ConfigService().selectedAsrAccountId;

    if (uniqueAsrAccounts.isEmpty) {
      // 没有配置 ASR 账户: 保留旧版阿里云直接输入
      return SettingsGroup(
        title: loc.aliyunConfig,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(loc.aliyunConfigDesc, style: AppTheme.caption(context)),
          ),
          // 提示去账户中心配置
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = 5), // 云服务账户 tab
              child: Row(
                children: [
                  MacosIcon(CupertinoIcons.arrow_right_circle, size: 14, color: AppTheme.accentColor),
                  const SizedBox(width: 6),
                  Text(loc.cloudAccountGoConfig, style: TextStyle(fontSize: 12, color: AppTheme.accentColor)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                MacosTextField(controller: _akIdController, placeholder: "AccessKey ID"),
                const SizedBox(height: 8),
                MacosTextField(controller: _akSecretController, placeholder: "AccessKey Secret", obscureText: true),
                const SizedBox(height: 8),
                MacosTextField(controller: _appKeyController, placeholder: "AppKey"),
                const SizedBox(height: 12),
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: () async {
                     await ConfigService().setAliyunCredentials(_akIdController.text, _akSecretController.text, _appKeyController.text);
                     if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("Saved Cloud Config!"), duration: Duration(seconds: 2)),
                       );
                     }
                  },
                  child: Text(loc.saveApply)
                ),
              ],
            ),
          )
        ],
      );
    }

    // 有 ASR 账户: 显示下拉选择
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

    return SettingsGroup(
      title: loc.cloudAccountSelectAsr,
      children: [
        SettingsTile(
          label: loc.cloudAccountSelectAsr,
          icon: CupertinoIcons.cloud,
          child: MacosPopupButton<String>(
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
              // 切换账户时自动选取新服务商的默认 ASR 模型
              final acc = uniqueAsrAccounts.firstWhere((a) => a.id == v);
              final prov = CloudProviders.getById(acc.providerId);
              final defaultModelId = prov?.asrModels.isNotEmpty == true ? prov!.asrModels.first.id : null;
              await ConfigService().setSelectedAsrAccount(v, modelId: defaultModelId);
              await _engine.initASR('', modelType: 'aliyun');
              setState(() {});
            },
          ),
        ),
        // ASR 模型选择（有多个模型时显示）
        if (asrModels.length > 1) ...[
          const SettingsDivider(),
          SettingsTile(
            label: '识别模型',
            icon: CupertinoIcons.waveform,
            child: MacosPopupButton<String>(
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
            ),
          ),
        ],
        // 前往云服务账户添加服务商
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () => setState(() => _selectedIndex = 5), // 云服务账户 tab
            child: Row(
              children: [
                MacosIcon(CupertinoIcons.plus_circle, size: 14, color: AppTheme.accentColor),
                const SizedBox(width: 6),
                Text(loc.cloudAccountAdd, style: TextStyle(fontSize: 12, color: AppTheme.accentColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkModeAdvanced(AppLocalizations loc, String currentMode) {
    // 云端模式下高级设置全部不适用，直接隐藏
    if (currentMode == 'cloud') return const SizedBox.shrink();
    return Column(
      children: [
        // Collapsible header
        GestureDetector(
          onTap: () => setState(() => _workModeAdvancedExpanded = !_workModeAdvancedExpanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: MacosColors.systemGrayColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                MacosIcon(
                  _workModeAdvancedExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                  size: 14,
                  color: MacosColors.systemGrayColor,
                ),
                const SizedBox(width: 8),
                Text(loc.workModeAdvanced, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),

        if (_workModeAdvancedExpanded) ...[
          const SizedBox(height: 16),

          // Voice model management (offline/smart modes)
          if (currentMode != 'cloud') ...[
            // Punctuation model
            Builder(builder: (_) {
              final activeModel = _modelManager.getModelById(_activeModelId ?? '');
              final modelHasPunct = activeModel?.hasPunctuation ?? false;
              final punctLabel = modelHasPunct
                  ? loc.punctuationModel
                  : "${loc.punctuationModel} (${loc.required})";
              final punctDesc = modelHasPunct
                  ? loc.builtInPunctuation
                  : loc.punctuationModelDesc;
              return SettingsGroup(
                title: punctLabel,
                children: [
                   Padding(
                     padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                     child: Text(punctDesc, style: AppTheme.caption(context)),
                   ),
                   if (!modelHasPunct)
                     SettingsTile(
                       label: loc.punctuationModel,
                       child: _buildActionBtn(
                         context,
                         isDownloaded: _downloadedStatus[ModelManager.punctuationModelId] ?? false,
                         isLoading: _downloadingIds.contains(ModelManager.punctuationModelId),
                         progress: _downloadProgressMap[ModelManager.punctuationModelId],
                         statusText: _downloadStatusMap[ModelManager.punctuationModelId],
                         isActive: true,
                         onDownload: _downloadPunctuation,
                         onDelete: _deletePunctuation,
                         onActivate: () {},
                       ),
                     ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Offline models (filtered by input language) — shown first (recommended)
            Builder(builder: (_) {
              final inputLang = ConfigService().inputLanguage;
              final filteredOffline = ModelManager.offlineModels
                  .where((m) => m.supportsLanguage(inputLang)).toList();
              return SettingsGroup(
                title: loc.offlineModels,
                children: [
                   Padding(
                     padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                     child: Text(loc.offlineModelsDesc, style: AppTheme.caption(context)),
                   ),
                   ...filteredOffline.map((m) {
                      return Column(
                        children: [
                          SettingsTile(
                            label: _localizedModelName(m, loc),
                            subtitle: _localizedModelDesc(m, loc),
                            child: _buildActionBtn(
                             context,
                              isDownloaded: _downloadedStatus[m.id] ?? false,
                              isLoading: _downloadingIds.contains(m.id) || _activatingId == m.id,
                              progress: _downloadProgressMap[m.id],
                              statusText: _downloadStatusMap[m.id],
                              isActive: _activeModelId == m.id,
                              isOffline: true,
                              onDownload: () => _download(m),
                              onDelete: () => _delete(m),
                              onActivate: () => _activate(m),
                              modelUrl: m.url,
                              onImport: () => _importModel(m),
                            ),
                          ),
                          if (m != filteredOffline.last) const SettingsDivider(),
                        ],
                      );
                   }),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Streaming models (filtered by input language) — shown after offline
            Builder(builder: (_) {
              final inputLang = ConfigService().inputLanguage;
              final filteredStreaming = ModelManager.availableModels
                  .where((m) => m.supportsLanguage(inputLang)).toList();
              return SettingsGroup(
                title: loc.streamingModels,
                children: [
                   Padding(
                     padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                     child: Text(loc.streamingModelsDesc, style: AppTheme.caption(context)),
                   ),
                   ...filteredStreaming.map((m) {
                      return Column(
                        children: [
                          SettingsTile(
                            label: _localizedModelName(m, loc),
                            subtitle: _localizedModelDesc(m, loc),
                            child: _buildActionBtn(
                             context,
                              isDownloaded: _downloadedStatus[m.id] ?? false,
                              isLoading: _downloadingIds.contains(m.id) || _activatingId == m.id,
                              progress: _downloadProgressMap[m.id],
                              statusText: _downloadStatusMap[m.id],
                              isActive: _activeModelId == m.id,
                              isOffline: false,
                              onDownload: () => _download(m),
                              onDelete: () => _delete(m),
                              onActivate: () => _activate(m),
                              modelUrl: m.url,
                              onImport: () => _importModel(m),
                            ),
                          ),
                          if (m != filteredStreaming.last) const SettingsDivider(),
                        ],
                      );
                   }),
                ],
              );
            }),

            const SizedBox(height: 24),
          ],

          // Vocab section (offline/smart modes)
          if (currentMode != 'cloud') ...[
            const VocabSettingsView(),
            const SizedBox(height: 16),
          ],

          // 2x2 matrix explanation
          if (currentMode == 'smart' || currentMode == 'offline')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MacosColors.systemGrayColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const MacosIcon(CupertinoIcons.info_circle, size: 14, color: MacosColors.systemGrayColor),
                      const SizedBox(width: 6),
                      Text(
                        loc.tabAiPolish,
                        style: AppTheme.caption(context).copyWith(fontWeight: FontWeight.w600, color: MacosColors.systemGrayColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.aiPolishMatrix,
                    style: AppTheme.caption(context).copyWith(
                      color: MacosColors.systemGrayColor,
                      height: 1.6,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

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

  // --- View: General ---
  Widget _buildDropdown({required String value, required Map<String, String> items, required Function(String?) onChanged}) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: MacosTheme.of(context).canvasColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MacosColors.separatorColor),
        ),
        child: MacosPopupButton<String>(
          value: value,
          items: items.entries.map((e) => MacosPopupMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: onChanged,
        ),
      );
  }

  Widget _buildAudioInputSection(AppLocalizations loc) {
    // 只在"系统默认"且系统默认恰好是蓝牙时才显示警告
    // 用户手动选了设备说明他知道自己在做什么，不再提示
    final isBluetooth = _useSystemDefaultAudio && (_currentAudioDevice?.isBluetooth ?? false);
    return Column(
      children: [
        SettingsTile(
          label: loc.audioInput,
          icon: CupertinoIcons.mic,
          child: MacosPopupButton<String>(
            value: () {
              if (_useSystemDefaultAudio) return 'system';
              final savedId = ConfigService().audioInputDeviceId;
              // If saved device not in current list, fall back to 'system'
              if (savedId != null && _audioDevices.any((d) => d.id == savedId)) {
                return savedId;
              }
              return 'system';
            }(),
            items: [
              MacosPopupMenuItem(
                value: 'system',
                child: Text(loc.systemDefault, style: AppTheme.body(context)),
              ),
              ..._audioDevices.map((d) => MacosPopupMenuItem(
                value: d.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (d.isBluetooth)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: MacosIcon(CupertinoIcons.bluetooth, size: 12),
                      ),
                    Text(d.name, style: AppTheme.body(context)),
                  ],
                ),
              )),
            ],
            onChanged: (value) async {
              if (value == null) return;
              final service = _engine.audioDeviceService;
              if (service == null) return;
              if (value == 'system') {
                service.clearPreferredDevice();
                await ConfigService().setAudioInputDeviceId(null);
              } else {
                service.setInputDevice(value);
                final device = _audioDevices.firstWhere((d) => d.id == value, orElse: () => _audioDevices.first);
                await ConfigService().setAudioInputDeviceId(value, name: device.name);
              }
              _loadAudioDevices();
            },
          ),
        ),
        // Show current device info when using system default
        if (_useSystemDefaultAudio && _currentAudioDevice != null)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Text(
              '当前系统设备: ${_currentAudioDevice!.name}',
              style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
            ),
          ),
        // Show Bluetooth warning if current device is Bluetooth
        if (isBluetooth)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Row(
              children: [
                const MacosIcon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 14),
                const SizedBox(width: 4),
                Text(
                  '蓝牙麦克风可能降低转写质量',
                  style: AppTheme.caption(context).copyWith(color: Colors.orange),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final service = _engine.audioDeviceService;
                    if (service == null) return;
                    service.switchToBuiltinMic();
                    final builtIn = service.builtInMicrophone;
                    if (builtIn != null && builtIn.id.isNotEmpty) {
                      await ConfigService().setAudioInputDeviceId(builtIn.id, name: builtIn.name);
                    }
                    _loadAudioDevices();
                  },
                  child: Text(
                    '切换到内置麦克风',
                    style: AppTheme.caption(context).copyWith(
                      color: MacosColors.systemBlueColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SettingsDivider(),
        // Auto-manage toggle
        SettingsTile(
          label: '自动优化音频',
          icon: CupertinoIcons.wand_stars,
          child: MacosSwitch(
            value: _autoManageAudio,
            onChanged: (v) {
              setState(() => _autoManageAudio = v);
              _engine.audioDeviceService?.autoManageEnabled = v;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 2),
          child: Text(
            '检测到蓝牙耳机时自动切换到高质量麦克风',
            style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
          ),
        ),
      ],
    );
  }


  /// Language code → display name
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

  /// Build input language dropdown items, filtered by cloud ASR model capability.
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

  /// Get the currently selected cloud ASR model (if any).
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

  /// Build contextual hints for language settings
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

  /// Check if current config implies translation mode (needs LLM).
  /// True when output is explicitly set AND input can't guarantee a match.
  bool _isTranslationMode() {
    final input = ConfigService().inputLanguage;
    final output = ConfigService().outputLanguage;
    if (output == 'auto') return false;
    if (input == 'auto') return true; // can't guarantee input matches output
    // Compare base language: zh-Hans/zh-Hant → zh
    final outputBase = output.startsWith('zh') ? 'zh' : output;
    return input != outputBase;
  }

  Widget _buildGeneralView() {
    final loc = AppLocalizations.of(context)!;

    return Column(
      children: [
        // 1. General Config (Interface Language & Audio)
        SettingsGroup(
          title: loc.tabGeneral,
          children: [
             // Interface Language
             SettingsTile(
               label: loc.language,
               icon: CupertinoIcons.globe,
               child: _buildDropdown(
                 value: ConfigService().appLanguage,
                 items: {'system': loc.langSystem, 'zh': "简体中文", 'en': "English"},
                 onChanged: (v) async { await ConfigService().setAppLanguage(v!); setState((){}); }
               ),
             ),
             const SettingsDivider(),
             // Audio Input with Device Selection
             _buildAudioInputSection(loc),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }





  // --- View: AI 梳理 (Organize) ---
  Widget _buildOrganizeView() {
    final loc = AppLocalizations.of(context)!;
    final config = ConfigService();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基本设置
          SettingsGroup(
            title: loc.tabOrganize,
            children: [
              SettingsTile(
                label: loc.organizeEnabled,
                icon: CupertinoIcons.text_alignleft,
                child: MacosSwitch(
                  value: config.organizeEnabled,
                  onChanged: (v) async {
                    await config.setOrganizeEnabled(v);
                    setState(() {});
                  },
                ),
              ),
              if (config.organizeEnabled) ...[
                const SettingsDivider(),
                _buildKeyCaptureTile(loc.organizeHotkey, CupertinoIcons.keyboard,
                  keyName: config.organizeKeyName.isEmpty ? '未设置' : config.organizeKeyName,
                  isCapturing: _isCapturingOrganizeKey,
                  onEdit: () => _startKeyCapture('organize'),
                  onClear: config.organizeKeyCode != 0 ? () async {
                    await config.clearOrganizeKey();
                    setState(() {});
                  } : null,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // 功能说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: MacosIcon(CupertinoIcons.lightbulb, size: 16, color: AppTheme.accentColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.organizeDesc,
                    style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 梳理指令
          if (config.organizeEnabled) ...[
            SettingsGroup(
              title: loc.organizePrompt,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(loc.organizePrompt, style: AppTheme.body(context)),
                          GestureDetector(
                            onTap: () async {
                              await config.setOrganizePrompt(AppConstants.kDefaultOrganizePrompt);
                              _organizePromptController.text = AppConstants.kDefaultOrganizePrompt;
                              setState(() {});
                            },
                            child: Text(loc.organizeResetDefault, style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      MacosTextField(
                        maxLines: 8,
                        controller: _organizePromptController,
                        decoration: BoxDecoration(
                          color: AppTheme.getInputBackground(context),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.getBorder(context)),
                        ),
                        onChanged: (v) => config.setOrganizePrompt(v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // LLM 服务提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const MacosIcon(CupertinoIcons.info_circle, size: 14, color: MacosColors.systemGrayColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(loc.organizeLlmHint, style: AppTheme.caption(context))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 1), // 跳转到工作模式 tab
                    child: Text(loc.organizeGoConfig, style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- View: Diary (闪念笔记) ---
  Widget _buildDiaryView() {
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        SettingsGroup(
          title: loc.diaryMode,
          children: [
            SettingsTile(
              label: loc.enabled,
              icon: CupertinoIcons.book,
              child: MacosSwitch(
                value: ConfigService().diaryEnabled,
                onChanged: (v) async {
                  await ConfigService().setDiaryEnabled(v);
                  if (v) await _validateDiaryDirectory();
                  setState((){});
                },
              ),
            ),
            if (ConfigService().diaryEnabled) ...[
              // 目录权限警告横幅
              if (_diaryDirError == null || _diaryDirError!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (_diaryDirError == null
                          ? MacosColors.systemOrangeColor
                          : MacosColors.systemRedColor).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (_diaryDirError == null
                            ? MacosColors.systemOrangeColor
                            : MacosColors.systemRedColor).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        MacosIcon(
                          CupertinoIcons.exclamationmark_triangle_fill,
                          size: 14,
                          color: _diaryDirError == null
                              ? MacosColors.systemOrangeColor
                              : MacosColors.systemRedColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _diaryDirError == null
                                ? '请点击右侧文件夹图标选择保存目录，以授权访问'
                                : _diaryDirError!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _diaryDirError == null
                                  ? MacosColors.systemOrangeColor
                                  : MacosColors.systemRedColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SettingsDivider(),
              _buildKeyCaptureTile(
                loc.pttMode, CupertinoIcons.keyboard_chevron_compact_down,
                isCapturing: _isCapturingDiaryKey,
                keyName: _diaryKeyName,
                onEdit: () => _startKeyCapture('diary'),
              ),
              const SettingsDivider(),
              _buildKeyCaptureTile(
                loc.toggleModeTip, CupertinoIcons.book,
                isCapturing: _isCapturingToggleDiaryKey,
                keyName: _toggleDiaryKeyName,
                onEdit: () => _startKeyCapture('toggleDiary'),
                onClear: () async {
                  await ConfigService().clearToggleDiaryKey();
                  setState(() => _toggleDiaryKeyName = "");
                },
              ),
              const SettingsDivider(),
              SettingsTile(
                label: loc.diaryPath,
                icon: CupertinoIcons.folder,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        ConfigService().diaryDirectory.split('/').last,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption(context),
                        maxLines: 1,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MacosIconButton(
                      icon: const MacosIcon(CupertinoIcons.folder_open),
                      onPressed: _pickDiaryFolder,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // _buildAiPolishView removed — merged into _buildWorkModeView()

  Widget _buildKeyCaptureTile(String label, IconData icon, {
    required bool isCapturing,
    required String keyName,
    required VoidCallback onEdit,
    VoidCallback? onClear,
  }) {
    final loc = AppLocalizations.of(context)!;
    final displayName = keyName.isEmpty ? loc.notSet : keyName;
    return SettingsTile(
      label: label,
      icon: icon,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCapturing ? AppTheme.getAccent(context) : MacosColors.systemGrayColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isCapturing ? loc.pressAnyKey : displayName,
              style: AppTheme.mono(context).copyWith(
                color: isCapturing ? Colors.white : (keyName.isEmpty ? MacosColors.systemGrayColor : null),
              ),
            ),
          ),
          const SizedBox(width: 8),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.pencil),
            onPressed: onEdit,
          ),
          if (onClear != null && keyName.isNotEmpty)
            MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.trash),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }

  Widget _buildTriggerView() {
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        // 1. Text Injection group
        SettingsGroup(
          title: loc.textInjection,
          children: [
            _buildKeyCaptureTile(
              loc.pttMode, CupertinoIcons.keyboard,
              isCapturing: _isCapturingKey,
              keyName: _currentKeyName,
              onEdit: _startKeyCapture,
            ),
            const SettingsDivider(),
            _buildKeyCaptureTile(
              loc.toggleModeTip, CupertinoIcons.text_cursor,
              isCapturing: _isCapturingToggleInputKey,
              keyName: _toggleInputKeyName,
              onEdit: () => _startKeyCapture('toggleInput'),
              onClear: () async {
                await ConfigService().clearToggleInputKey();
                setState(() => _toggleInputKeyName = "");
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 2. Recording Protection group
        SettingsGroup(
          title: loc.recordingProtection,
          children: [
            SettingsTile(
              label: loc.toggleMaxDuration,
              icon: CupertinoIcons.timer,
              child: MacosPopupButton<int>(
                value: _toggleMaxDuration,
                items: [
                  MacosPopupMenuItem(value: 0, child: Text(loc.toggleMaxNone)),
                  MacosPopupMenuItem(value: 60, child: Text(loc.toggleMaxMin(1))),
                  MacosPopupMenuItem(value: 180, child: Text(loc.toggleMaxMin(3))),
                  MacosPopupMenuItem(value: 300, child: Text(loc.toggleMaxMin(5))),
                  MacosPopupMenuItem(value: 600, child: Text(loc.toggleMaxMin(10))),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    await ConfigService().setToggleMaxDuration(v);
                    setState(() => _toggleMaxDuration = v);
                  }
                },
              ),
            ),
            const SettingsDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  MacosIcon(CupertinoIcons.info_circle, color: MacosColors.systemGrayColor, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.toggleHint,
                      style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBtn(BuildContext context, {
    required bool isDownloaded, required bool isLoading, required bool isActive,
    required VoidCallback onDownload, required VoidCallback onDelete, required VoidCallback onActivate,
    double? progress, String? statusText, bool isOffline = false,
    String? modelUrl, VoidCallback? onImport,
  }) {
    final loc = AppLocalizations.of(context)!;
    if (isLoading) {
      return SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: MacosColors.systemGrayColor.withValues(alpha:0.2),
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getAccent(context)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              statusText ?? loc.preparing,
              style: AppTheme.caption(context),
            ),
          ],
        ),
      );
    }
    if (!isDownloaded) {
       return Row(
         mainAxisSize: MainAxisSize.min,
         children: [
           PushButton(
             controlSize: ControlSize.regular,
             color: AppTheme.getAccent(context),
             onPressed: onDownload,
             child: Text(loc.download, style: const TextStyle(color: Colors.white)),
           ),
           if (onImport != null) ...[
             const SizedBox(width: 6),
             PushButton(
               controlSize: ControlSize.regular,
               secondary: true,
               onPressed: onImport,
               child: Text(loc.importModel),
             ),
           ],
           if (modelUrl != null) ...[
             const SizedBox(width: 4),
             MacosIconButton(
               icon: const MacosIcon(CupertinoIcons.link, size: 16),
               onPressed: () => launchUrl(Uri.parse(modelUrl)),
             ),
           ],
         ],
       );
    }
    // Downloaded
    return Row(
      children: [
        if (isActive)
           Row(
             children: [
               const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppTheme.successColor),
               const SizedBox(width: 4),
               Text(loc.active, style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold, fontSize: 12)),
               const SizedBox(width: 6),
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                 decoration: BoxDecoration(
                   color: isOffline
                       ? Colors.orange.withValues(alpha: 0.15)
                       : AppTheme.getAccent(context).withValues(alpha: 0.15),
                   borderRadius: BorderRadius.circular(4),
                 ),
                 child: Text(
                   isOffline ? loc.modeOffline : loc.modeStreaming,
                   style: TextStyle(
                     fontSize: 10,
                     fontWeight: FontWeight.w600,
                     color: isOffline ? Colors.orange : AppTheme.getAccent(context),
                   ),
                 ),
               ),
             ],
           )
        else
           PushButton(
             controlSize: ControlSize.regular,
             color: MacosColors.controlColor.resolveFrom(context),
             onPressed: onActivate,
             child: Text(loc.activate)
           ),
        const SizedBox(width: 12),
        MacosIconButton(
          icon: const MacosIcon(CupertinoIcons.trash, color: AppTheme.errorColor, size: 18),
          onPressed: onDelete,
        )
      ],
    );
  }
  void _showUnsavedChangesDialog(int targetIndex) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 48, color: MacosColors.systemOrangeColor),
        title: const Text("有未保存的修改"),
        message: const Text("AI 润色配置尚未保存，是否保存后再切换？"),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () async {
            Navigator.of(context).pop();
            await _flushLlmControllers();
            await ConfigService().savePresetConfig(ConfigService().llmPresetId);
            setState(() { _llmConfigDirty = false; _selectedIndex = targetIndex; });
            _tabController.index = targetIndex;
          },
          child: const Text("保存"),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () {
            Navigator.of(context).pop();
            _syncLlmControllers(); // Revert to saved values
            setState(() { _llmConfigDirty = false; _selectedIndex = targetIndex; });
            _tabController.index = targetIndex;
          },
          child: const Text("放弃"),
        ),
      ),
    );
  }

  void _syncLlmControllers() {
    _llmApiKeyController.text = ConfigService().llmApiKeyOverride ?? '';
    _llmBaseUrlController.text = ConfigService().llmBaseUrlOverride ?? '';
    _llmModelController.text = ConfigService().llmModelOverride ?? '';
  }

  // _buildCloudPresetSection removed — replaced by _buildCloudLlmAccountSelector

  Widget _buildApiItem(BuildContext context, String label, IconData icon, String? value, Function(String) onChanged, {bool isSecret = false, String? placeholder}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
           const SizedBox(height: 4),
           MacosTextField(
             placeholder: placeholder ?? label,
             obscureText: isSecret,
             maxLines: 1,
             decoration: BoxDecoration(
               color: AppTheme.getInputBackground(context),
               borderRadius: BorderRadius.circular(6),
               border: Border.all(color: AppTheme.getBorder(context)),
             ),
             prefix: Padding(padding: const EdgeInsets.only(left: 8), child: MacosIcon(icon, size: 14)),
             controller: TextEditingController(text: value),
             onChanged: onChanged,
           ),
        ],
      );
  }

  /// Flush all LLM controller values to ConfigService (Keychain + SharedPreferences)
  Future<void> _flushLlmControllers() async {
    try {
      await ConfigService().setLlmApiKey(_llmApiKeyController.text);
    } catch (e) {
      // Keychain write failed — log and continue
      LLMService().log("FLUSH: setLlmApiKey failed: $e");
    }
    await ConfigService().setLlmBaseUrl(_llmBaseUrlController.text);
    await ConfigService().setLlmModel(_llmModelController.text);
    LLMService().log("FLUSH: done, keyLen=${_llmApiKeyController.text.length}");
  }


  // --- View: About ---
  Widget _buildAboutView(BuildContext context, String version) {
    final loc = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: Column(
        children: [
          // Logo and info section (centered)
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset("assets/app_icon.png", width: 100, height: 100),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "子曰 SpeakOut",
            style: AppTheme.display(context).copyWith(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2
            )
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onDoubleTap: () {
                  Clipboard.setData(ClipboardData(text: version));
                  setState(() => _versionCopied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _versionCopied = false);
                  });
                },
                child: Tooltip(
                  message: "双击复制版本号",
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _versionCopied
                          ? MacosColors.systemGreenColor.withValues(alpha: 0.15)
                          : MacosColors.systemGrayColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _versionCopied
                            ? MacosColors.systemGreenColor.withValues(alpha: 0.4)
                            : MacosColors.systemGrayColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_versionCopied) ...[
                          const MacosIcon(CupertinoIcons.checkmark, size: 12, color: MacosColors.systemGreenColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _versionCopied ? "已复制" : "v$version",
                          style: AppTheme.mono(context).copyWith(
                            fontSize: 12,
                            color: _versionCopied
                                ? MacosColors.systemGreenColor
                                : MacosColors.labelColor.resolveFrom(context).withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isCheckingUpdate ? null : () async {
                  setState(() { _isCheckingUpdate = true; _updateResult = null; });
                  try {
                    final info = await PackageInfo.fromPlatform();
                    // Reset so it can check again
                    UpdateService().resetCheck();
                    await UpdateService().checkForUpdate();
                    final latest = UpdateService().latestVersion;
                    if (latest != null && UpdateService.isNewer(latest, info.version)) {
                      setState(() => _updateResult = loc.updateAvailable(latest));
                    } else {
                      setState(() => _updateResult = loc.updateUpToDate);
                    }
                  } catch (_) {
                    setState(() => _updateResult = loc.updateUpToDate);
                  }
                  setState(() => _isCheckingUpdate = false);
                },
                child: Tooltip(
                  message: loc.updateAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: MacosColors.systemGrayColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha:0.2)),
                    ),
                    child: _isCheckingUpdate
                      ? const SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator())
                      : const MacosIcon(CupertinoIcons.arrow_clockwise, size: 14, color: MacosColors.secondaryLabelColor),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: _updateResult != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _updateResult == loc.updateUpToDate
                      ? Text(
                          _updateResult!,
                          style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGrayColor),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _updateResult!,
                              style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemOrangeColor),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                final url = UpdateService().downloadUrl ?? 'https://github.com/4over7/SpeakOut/releases/latest';
                                launchUrl(Uri.parse(url));
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(loc.updateAction, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                  )
                : null,
          ),
          Text(
            loc.aboutTagline,
            style: AppTheme.body(context).copyWith(
              fontSize: 16,
              color: AppTheme.getAccent(context)
            )
          ),
          const SizedBox(height: 8),
          Text(
            loc.aboutSubTagline,
            style: AppTheme.caption(context).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 48),
          Column(
            children: [
              Text(loc.aboutPoweredBy, style: AppTheme.caption(context).copyWith(fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Sherpa-ONNX", style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text("•", style: TextStyle(color: MacosColors.tertiaryLabelColor)),
                  ),
                  Text("Aliyun NLS", style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text("•", style: TextStyle(color: MacosColors.tertiaryLabelColor)),
                  ),
                  Text("Ollama", style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            loc.aboutCopyright,
            style: AppTheme.caption(context).copyWith(color: MacosColors.quaternaryLabelColor)
          ),

          const SizedBox(height: 48),

          // Developer / Debug (hidden at bottom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SettingsGroup(
              title: '开发者',
              children: [
                SettingsTile(
                  label: '详细日志',
                  icon: CupertinoIcons.doc_text,
                  child: MacosSwitch(
                    value: ConfigService().verboseLogging,
                    onChanged: (v) async {
                      await ConfigService().setVerboseLogging(v);
                      AppService().applyVerboseLogging();
                      setState(() {});
                    },
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  label: '日志输出目录',
                  icon: CupertinoIcons.folder,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ConfigService().logDirectory.isEmpty
                            ? '未设置（仅输出到控制台）'
                            : ConfigService().logDirectory.replaceFirst(RegExp(r'^/Users/[^/]+'), '~'),
                        style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: const MacosIcon(CupertinoIcons.folder_badge_plus, size: 16),
                        backgroundColor: MacosColors.transparent,
                        onPressed: () async {
                          final dir = await FilePicker.platform.getDirectoryPath(
                            dialogTitle: '选择日志输出目录',
                          );
                          if (dir != null) {
                            await ConfigService().setLogDirectory(dir);
                            AppService().applyVerboseLogging();
                            setState(() {});
                          }
                        },
                      ),
                      if (ConfigService().logDirectory.isNotEmpty)
                        MacosIconButton(
                          icon: const MacosIcon(CupertinoIcons.xmark_circle, size: 16),
                          backgroundColor: MacosColors.transparent,
                          onPressed: () async {
                            await ConfigService().setLogDirectory('');
                            AppService().applyVerboseLogging();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 配置备份与恢复
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SettingsGroup(
              title: '配置备份',
              children: [
                SettingsTile(
                  label: '导出配置',
                  subtitle: '将所有设置和凭证导出为文件（含明文密钥，请妥善保管）',
                  icon: CupertinoIcons.arrow_up_doc,
                  child: PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () async {
                      final path = await FilePicker.platform.saveFile(
                        dialogTitle: '导出配置文件',
                        fileName: 'speakout_config.json',
                        allowedExtensions: ['json'],
                        type: FileType.custom,
                      );
                      if (path != null) {
                        final result = await ConfigBackupService.exportToFile(path);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(result.success ? '已导出：${result.message}' : '导出失败：${result.error}'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: const Text('导出'),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  label: '导入配置',
                  subtitle: '从备份文件恢复所有设置，立即生效',
                  icon: CupertinoIcons.arrow_down_doc,
                  child: PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        dialogTitle: '选择配置文件',
                        allowedExtensions: ['json'],
                        type: FileType.custom,
                      );
                      if (result != null && result.files.single.path != null) {
                        final importResult = await ConfigBackupService.importFromFile(result.files.single.path!);
                        if (mounted) {
                          setState(() {}); // 刷新 UI
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(importResult.success
                              ? '${importResult.message}，配置已生效'
                              : '导入失败：${importResult.error}'),
                            backgroundColor: importResult.success ? MacosColors.systemGreenColor : null,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: const Text('导入'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

