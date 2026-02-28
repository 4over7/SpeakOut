import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_service.dart';
import '../config/app_constants.dart';
import '../engine/model_manager.dart';
import '../engine/core_engine.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'theme.dart';
import '../services/audio_device_service.dart';

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
  
  // Cloud State
  String _asrEngineType = 'sherpa';


  final TextEditingController _akIdController = TextEditingController();
  final TextEditingController _akSecretController = TextEditingController();
  final TextEditingController _appKeyController = TextEditingController();
  late final TextEditingController _aiPromptController;
  
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
  int _toggleMaxDuration = 0;
  
  final FocusNode _keyCaptureFocusNode = FocusNode();
  StreamSubscription<int>? _keySubscription;

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
    _tabController = MacosTabController(initialIndex: 0, length: 4);
    _tabController.addListener(() {
      setState(() => _selectedIndex = _tabController.index);
    });
    
    _refresh();
    _loadHotkeyConfig();
    _loadActiveModel();
    _loadAliyunConfig();
    _loadAudioDevices();
  }
  
  void _loadAudioDevices() {
    final service = _engine.audioDeviceService;
    if (service == null) return;
    service.refreshDevices();
    setState(() {
      _audioDevices = service.devices;
      _currentAudioDevice = service.currentDevice;
      _autoManageAudio = service.autoManageEnabled;
    });
  }
  
  Future<void> _loadAliyunConfig() async {
    final s = ConfigService();
    setState(() {
      _asrEngineType = s.asrEngineType;
      _akIdController.text = s.aliyunAccessKeyId;
      _akSecretController.text = s.aliyunAccessKeySecret;
      _appKeyController.text = s.aliyunAppKey;
    });
  }
  
  @override
  void dispose() {
    _keySubscription?.cancel();
    _keyCaptureFocusNode.dispose();
    _tabController.dispose();
    _akIdController.dispose();
    _akSecretController.dispose();
    _appKeyController.dispose();
    _aiPromptController.dispose();
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
  
  Future<void> _saveHotkeyConfig(int keyCode, String keyName) async {
    if (_isCapturingToggleInputKey) {
       await ConfigService().setToggleInputKey(keyCode, keyName);
       setState(() {
         _toggleInputKeyName = keyName;
         _isCapturingToggleInputKey = false;
       });
    } else if (_isCapturingToggleDiaryKey) {
       await ConfigService().setToggleDiaryKey(keyCode, keyName);
       setState(() {
         _toggleDiaryKeyName = keyName;
         _isCapturingToggleDiaryKey = false;
       });
    } else if (_isCapturingDiaryKey) {
       await ConfigService().setDiaryKey(keyCode, keyName);
       setState(() {
         _diaryKeyName = keyName;
         _isCapturingDiaryKey = false;
       });
    } else {
       await ConfigService().setPttKey(keyCode, keyName);
       _engine.pttKeyCode = keyCode;
       setState(() {
         _currentKeyCode = keyCode;
         _currentKeyName = keyName;
         _isCapturingKey = false;
       });
    }
  }
  
  // --- Key Capture Logic ---
  void _startKeyCapture({bool isDiary = false, bool isToggleInput = false, bool isToggleDiary = false}) {
    setState(() {
       if (isToggleInput) {
         _isCapturingToggleInputKey = true;
       } else if (isToggleDiary) {
         _isCapturingToggleDiaryKey = true;
       } else if (isDiary) {
         _isCapturingDiaryKey = true;
       } else {
         _isCapturingKey = true;
       }
    });

    _keySubscription = _engine.rawKeyEventStream.listen((keyCode) {
       final keyName = _mapKeyCodeToString(keyCode);
       _saveHotkeyConfig(keyCode, keyName);
       _stopKeyCapture();
    });
    // Timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && (_isCapturingKey || _isCapturingDiaryKey || _isCapturingToggleInputKey || _isCapturingToggleDiaryKey)) {
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
      });
    }
  }

  Future<void> _pickDiaryFolder() async {
    try {
      final String? outputDir = await const MethodChannel('com.SpeakOut/overlay').invokeMethod('pickDirectory');
      if (outputDir != null) {
        await ConfigService().setDiaryDirectory(outputDir);
        setState((){});
      }
    } catch (e) {
      // Fallback or ignore
      debugPrint("Pick Directory Failed: $e");
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

    setState(() => _activatingId = model.id);
    await _modelManager.setActiveModel(model.id);
    final path = await _modelManager.getActiveModelPath();
    if (path != null) await _engine.initASR(path, modelType: model.type, modelName: model.name, hasPunctuation: model.hasPunctuation);
    await ConfigService().setActiveModelId(model.id);
    setState(() { _activatingId = null; _activeModelId = model.id; });
  }

  Future<void> _delete(ModelInfo model) async {
     await _modelManager.deleteModel(model.id);
     await _refresh();
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
      backgroundColor: AppTheme.getBackground(context), // Match mockup #1C1C1E
      sidebar: Sidebar(
        minWidth: 200,
        decoration: BoxDecoration(
          color: AppTheme.getSidebarBackground(context), // Match mockup #2C2C2E
        ),
        builder: (context, scrollController) {
          return SidebarItems(
            currentIndex: _selectedIndex,
            onChanged: (i) => setState(() => _selectedIndex = i),
            selectedColor: AppTheme.accentColor.withValues(alpha:0.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            items: [
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.settings, color: _selectedIndex == 0 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.tabGeneral, style: TextStyle(color: _selectedIndex == 0 ? AppTheme.accentColor : null)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.waveform_circle_fill, color: _selectedIndex == 1 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.tabModels, style: TextStyle(color: _selectedIndex == 1 ? AppTheme.accentColor : null)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.hand_draw, color: _selectedIndex == 2 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.tabTrigger, style: TextStyle(color: _selectedIndex == 2 ? AppTheme.accentColor : null)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.info_circle, color: _selectedIndex == 3 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.tabAbout, style: TextStyle(color: _selectedIndex == 3 ? AppTheme.accentColor : null)), 
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
                  child: SingleChildScrollView(
                    child: Builder(builder: (_) {
                       if (_selectedIndex == 0) return _buildGeneralView();
                       if (_selectedIndex == 1) return _buildModelsView();
                       if (_selectedIndex == 2) return _buildTriggerView();
                       return _buildAboutView(context, _version);
                    }),
                  ),
                ),
              );
            },
          ),
        ],
      )
    );
  }
  
  // --- View: Models ---
  Widget _buildModelsView() {
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        SettingsGroup(
          title: loc.engineType,
          children: [
             SettingsTile(
               label: loc.engineLocal,
               child: MacosRadioButton(
                 groupValue: _asrEngineType,
                 value: 'sherpa',
                 onChanged: (v) async { if(v!=null) { await ConfigService().setAsrEngineType(v); setState(()=>_asrEngineType=v); } },
               ),
             ),
             const SettingsDivider(),
             SettingsTile(
               label: loc.engineCloud,
               child: MacosRadioButton(
                 groupValue: _asrEngineType,
                 value: 'aliyun',
                 onChanged: (v) async { if(v!=null) { await ConfigService().setAsrEngineType(v); setState(()=>_asrEngineType=v); } },
               ),
             ),
          ],
        ),
        const SizedBox(height: 24),
        
        if (_asrEngineType == 'aliyun') 
           SettingsGroup(
             title: loc.aliyunConfig,
             children: [
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
           )
        else ...[
           // 标点模型（根据当前模型决定是否必需）
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
           
           // 流式模型（实时显示）
           SettingsGroup(
             title: loc.streamingModels,
             children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Text(loc.streamingModelsDesc, style: AppTheme.caption(context)),
                ),
                ...ModelManager.availableModels.map((m) {
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
                         ),
                       ),
                       if (m != ModelManager.availableModels.last) const SettingsDivider(),
                     ],
                   );
                }),
             ],
           ),

           const SizedBox(height: 24),

           // 离线模型（高精度）
           SettingsGroup(
             title: loc.offlineModels,
             children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Text(loc.offlineModelsDesc, style: AppTheme.caption(context)),
                ),
                ...ModelManager.offlineModels.map((m) {
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
                         ),
                       ),
                       if (m != ModelManager.offlineModels.last) const SettingsDivider(),
                     ],
                   );
                }),
             ],
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
    final isBluetooth = _currentAudioDevice?.isBluetooth ?? false;
    return Column(
      children: [
        SettingsTile(
          label: loc.audioInput,
          icon: CupertinoIcons.mic,
          child: MacosPopupButton<String>(
            value: _currentAudioDevice?.id ?? 'system',
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
            onChanged: (value) {
              if (value == null || value == 'system') return;
              final service = _engine.audioDeviceService;
              if (service == null) return;
              service.setInputDevice(value);
              _loadAudioDevices();
            },
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
                  onTap: () {
                    _engine.audioDeviceService?.switchToBuiltinMic();
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


  Widget _buildGeneralView() {
    final loc = AppLocalizations.of(context)!;
    
    return Column(
      children: [
        // 1. General Config (Language & Audio)
        SettingsGroup(
          title: loc.tabGeneral,
          children: [
             // Language
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
        


        const SizedBox(height: 32),
        // 4. Config (AI Correction)
        SettingsGroup(
          title: loc.aiCorrection,
          children: [
             SettingsTile(
               label: loc.enabled,
               icon: CupertinoIcons.sparkles,
               child: MacosSwitch(
                 value: ConfigService().aiCorrectionEnabled,
                 onChanged: (v) async { await ConfigService().setAiCorrectionEnabled(v); setState((){}); },
               ),
             ),
             if (ConfigService().aiCorrectionEnabled) ...[
               const SettingsDivider(),
               // Provider selector
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

                     // 2. Prompt Text
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

                     if (ConfigService().llmProviderType == 'cloud') ...[
                       // Cloud API Config
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                            Text(loc.apiConfig, style: AppTheme.body(context)),
                            GestureDetector(
                              onTap: () async {
                                final uri = Uri.parse("https://help.aliyun.com/zh/model-studio/getting-started/first-api-call-to-qwen");
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                              child: Row(
                                children: [
                                  MacosIcon(CupertinoIcons.question_circle, size: 14, color: AppTheme.accentColor),
                                  const SizedBox(width: 4),
                                  Text("获取帮助", style: AppTheme.caption(context).copyWith(color: AppTheme.accentColor, fontSize: 11)),
                                ],
                              ),
                            ),
                         ],
                       ),
                       const SizedBox(height: 4),
                       Text(
                         "需要 OpenAI 兼容的 API（推荐阿里云百炼）",
                         style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGrayColor),
                       ),
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
                              _buildApiItem(
                                context,
                                "API Key", CupertinoIcons.lock, ConfigService().llmApiKeyOverride,
                                (v) => ConfigService().setLlmApiKey(v), isSecret: true
                              ),
                              const SizedBox(height: 8),
                              _buildApiItem(
                                context,
                                "Base URL", CupertinoIcons.link, ConfigService().llmBaseUrlOverride,
                                (v) => ConfigService().setLlmBaseUrl(v)
                              ),
                              const SizedBox(height: 8),
                              _buildApiItem(
                                context,
                                "Model Name", CupertinoIcons.cube_box, ConfigService().llmModelOverride,
                                (v) => ConfigService().setLlmModel(v), placeholder: "model-name"
                              ),
                           ],
                         ),
                       ),
                     ] else ...[
                       // Ollama Config
                       Text(loc.ollamaUrl, style: AppTheme.body(context)),
                       const SizedBox(height: 4),
                       Text(
                         "确保 Ollama 已启动（ollama serve）",
                         style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGrayColor),
                       ),
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
                              _buildApiItem(
                                context,
                                loc.ollamaUrl, CupertinoIcons.link, ConfigService().ollamaBaseUrl,
                                (v) => ConfigService().setOllamaBaseUrl(v), placeholder: "http://localhost:11434"
                              ),
                              const SizedBox(height: 8),
                              _buildApiItem(
                                context,
                                loc.ollamaModel, CupertinoIcons.cube_box, ConfigService().ollamaModel,
                                (v) => ConfigService().setOllamaModel(v), placeholder: "qwen3:0.6b"
                              ),
                           ],
                         ),
                       ),
                     ],
                    ],
                 ),
               ),
             ]
          ],
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }
  



  
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
              onEdit: () => _startKeyCapture(isToggleInput: true),
              onClear: () async {
                await ConfigService().clearToggleInputKey();
                setState(() => _toggleInputKeyName = "");
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 2. Flash Note group
        SettingsGroup(
          title: loc.diaryMode,
          children: [
            SettingsTile(
              label: loc.enabled,
              icon: CupertinoIcons.book,
              child: MacosSwitch(
                value: ConfigService().diaryEnabled,
                onChanged: (v) async { await ConfigService().setDiaryEnabled(v); setState((){}); },
              ),
            ),
            if (ConfigService().diaryEnabled) ...[
              const SettingsDivider(),
              _buildKeyCaptureTile(
                loc.pttMode, CupertinoIcons.keyboard_chevron_compact_down,
                isCapturing: _isCapturingDiaryKey,
                keyName: _diaryKeyName,
                onEdit: () => _startKeyCapture(isDiary: true),
              ),
              const SettingsDivider(),
              _buildKeyCaptureTile(
                loc.toggleModeTip, CupertinoIcons.book,
                isCapturing: _isCapturingToggleDiaryKey,
                keyName: _toggleDiaryKeyName,
                onEdit: () => _startKeyCapture(isToggleDiary: true),
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

        // 3. Recording Protection group
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
            SettingsTile(
              label: "ASR De-duplicate",
              icon: CupertinoIcons.textformat_abc,
              child: MacosSwitch(
                value: ConfigService().deduplicationEnabled,
                onChanged: (v) async { await ConfigService().setDeduplicationEnabled(v); setState((){}); },
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
       return PushButton(
         controlSize: ControlSize.regular,
         // Use Primary Color (Teal) for Download
         color: AppTheme.getAccent(context),
         onPressed: onDownload,
         child: Text(loc.download, style: const TextStyle(color: Colors.white)),
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



  // --- View: About ---
  Widget _buildAboutView(BuildContext context, String version) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Image.asset("assets/app_icon.png", width: 100, height: 100),
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
          GestureDetector(
            onDoubleTap: () {
              Clipboard.setData(ClipboardData(text: version));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("已复制版本号: v$version"),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  width: 220,
                ),
              );
            },
            child: Tooltip(
              message: "双击复制版本号",
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: MacosColors.systemGrayColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha:0.2)),
                ),
                child: Text(
                  "v$version",
                  style: AppTheme.mono(context).copyWith(fontSize: 12, color: MacosColors.secondaryLabelColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
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
                  Text("sherpa-onnx", style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text("•", style: TextStyle(color: MacosColors.tertiaryLabelColor)),
                  ),
                  Text("Alibaba Qwen", style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            loc.aboutCopyright, 
            style: AppTheme.caption(context).copyWith(color: MacosColors.quaternaryLabelColor)
          ),
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  
  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (title != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(title!, style: AppTheme.heading(context)),
          ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.getCardBackground(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.getBorder(context)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;
  final IconData? icon; // Added Icon support

  const SettingsTile({super.key, required this.label, this.subtitle, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            MacosIcon(icon, size: 20, color: MacosColors.systemGrayColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.body(context)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: AppTheme.caption(context)),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1, 
      color: MacosColors.separatorColor.withValues(alpha:0.5), 
      indent: 16, 
      endIndent: 0
    );
  }
}
