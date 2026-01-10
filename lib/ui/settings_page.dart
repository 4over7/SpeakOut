import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:record/record.dart'; // For InputDevice
import '../services/config_service.dart';
import '../services/app_service.dart';
import '../config/app_constants.dart';
import '../engine/model_manager.dart';
import '../engine/core_engine.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'settings/mcp_settings_view.dart';
import 'theme.dart';

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
  String? _loadingId;
  String? _activeModelId;
  double _downloadProgress = 0;
  String _downloadStatus = "";
  
  // Cloud State
  String _asrEngineType = 'sherpa';
  final TextEditingController _akIdController = TextEditingController();
  final TextEditingController _akSecretController = TextEditingController();
  final TextEditingController _appKeyController = TextEditingController();
  
  // Hotkey State
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  bool _isCapturingKey = false;
  // Diary Hotkey
  int _diaryKeyCode = 61;
  String _diaryKeyName = "Right Option";
  bool _isCapturingDiaryKey = false;
  
  final FocusNode _keyCaptureFocusNode = FocusNode();
  StreamSubscription<int>? _keySubscription;

  // UI State
  bool _showCustomApi = false;
  String _version = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _tabController = MacosTabController(initialIndex: 0, length: 5);
    _tabController.addListener(() {
      setState(() => _selectedIndex = _tabController.index);
    });
    
    _refresh();
    _loadHotkeyConfig();
    _loadActiveModel();
    _loadAliyunConfig();
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
      _diaryKeyCode = service.diaryKeyCode;
      _diaryKeyName = service.diaryKeyName;
    });
    _engine.pttKeyCode = _currentKeyCode;
  }
  
  Future<void> _saveHotkeyConfig(int keyCode, String keyName) async {
    if (_isCapturingDiaryKey) {
       await ConfigService().setDiaryKey(keyCode, keyName);
       setState(() {
         _diaryKeyCode = keyCode;
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
  void _startKeyCapture({bool isDiary = false}) {
    setState(() {
       if (isDiary) _isCapturingDiaryKey = true;
       else _isCapturingKey = true;
    });
    
    _keySubscription = _engine.rawKeyEventStream.listen((keyCode) {
       // Simple Key Mapping for Display
       String keyName = _mapKeyCodeToString(keyCode);
       _saveHotkeyConfig(keyCode, keyName);
       _stopKeyCapture();
    });
    // Timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && (_isCapturingKey || _isCapturingDiaryKey)) _stopKeyCapture();
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
    if (mounted) setState(() { _isCapturingKey = false; _isCapturingDiaryKey = false; });
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
    for (var m in ModelManager.availableModels) {
      _downloadedStatus[m.id] = await _modelManager.isModelDownloaded(m.id);
    }
    _downloadedStatus[ModelManager.punctuationModelId] = await _modelManager.isPunctuationModelDownloaded();
    setState(() {});
  }

  // --- Download & Actions ---
  // (Simplified for brevity in rewrite, keeping core logic)
  Future<void> _download(ModelInfo model) async {
     final loc = AppLocalizations.of(context)!;
     setState(() { _loadingId = model.id; _downloadStatus = loc.preparing; _downloadProgress = 0; });
     try {
       await _modelManager.downloadAndExtractModel(model.id, 
         onProgress: (p) { if(mounted) setState(() { _downloadProgress = p; _downloadStatus = loc.downloading((p*100).toStringAsFixed(0)); }); }
       );
       await _refresh();
     } catch(e) { _showError(e.toString()); }
     finally { if(mounted) setState(() { _loadingId = null; }); }
  }
  
  Future<void> _activate(ModelInfo model) async {
    setState(() => _loadingId = model.id);
    await _modelManager.setActiveModel(model.id);
    final path = await _modelManager.getActiveModelPath();
    if (path != null) await _engine.initASR(path, modelType: model.type);
    await ConfigService().setActiveModelId(model.id);
    setState(() { _loadingId = null; _activeModelId = model.id; });
  }

  Future<void> _delete(ModelInfo model) async {
     await _modelManager.deleteModel(model.id);
     await _refresh();
  }
  
  Future<void> _downloadPunctuation() async {
      // Similar download logic for punctuation
      // Implementation omitted for brevity, reusing existing patterns
      final loc = AppLocalizations.of(context)!;
     setState(() { _loadingId = ModelManager.punctuationModelId; _downloadStatus = loc.preparing; });
     try {
       await _modelManager.downloadPunctuationModel(onProgress: (p) { if(mounted) setState(() { _downloadProgress = p; _downloadStatus = loc.downloading((p*100).toStringAsFixed(0)); }); });
       await _refresh();
       final path = await _modelManager.getPunctuationModelPath();
       if (path != null) await _engine.initPunctuation(path);
     } catch(e) { _showError(e.toString()); }
     finally { if(mounted) setState(() { _loadingId = null; }); }
  }
  
  Future<void> _deletePunctuation() async {
    await _modelManager.deletePunctuationModel();
    await _refresh();
  }

  void _showError(String msg) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        title: const Text("Error"), message: Text(msg),
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
            selectedColor: AppTheme.accentColor.withOpacity(0.2),
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
                leading: MacosIcon(CupertinoIcons.book, color: _selectedIndex == 2 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.diaryMode, style: TextStyle(color: _selectedIndex == 2 ? AppTheme.accentColor : null)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.cube_box, color: _selectedIndex == 3 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text("Agent Tools", style: TextStyle(color: _selectedIndex == 3 ? AppTheme.accentColor : null)),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.info_circle, color: _selectedIndex == 4 ? AppTheme.accentColor : MacosColors.systemGrayColor),
                label: Text(loc.tabAbout, style: TextStyle(color: _selectedIndex == 4 ? AppTheme.accentColor : null)), 
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
                  child: SingleChildScrollView(
                    child: Builder(builder: (_) {
                       if (_selectedIndex == 0) return _buildGeneralView();
                       if (_selectedIndex == 1) return _buildModelsView();
                       if (_selectedIndex == 2) return _buildDiaryView();
                       if (_selectedIndex == 3) return const McpSettingsView();
                       return _buildAboutView(context, _version);
                    }),
                  ),
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
          title: "Engine Type",
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
                           _showError("Saved Cloud Config!");
                        }, 
                        child: Text(loc.saveApply)
                      ),
                    ],
                  ),
                )
             ],
           )
        else
           SettingsGroup(
             title: loc.tabModels,
             children: [
                // Punctuation
                SettingsTile(
                  label: "Punctuation Model",
                  child: _buildActionBtn(
                    context,
                    isDownloaded: _downloadedStatus[ModelManager.punctuationModelId] ?? false,
                    isLoading: _loadingId == ModelManager.punctuationModelId,
                    isActive: true, // Always active if present
                    onDownload: _downloadPunctuation,
                    onDelete: _deletePunctuation,
                    onActivate: () {},
                  ),
                ),
                const SettingsDivider(),
                // Models
                ...ModelManager.availableModels.map((m) {
                   return Column(
                     children: [
                       SettingsTile(
                         label: m.name,
                         child: _buildActionBtn(
                          context,
                           isDownloaded: _downloadedStatus[m.id] ?? false,
                           isLoading: _loadingId == m.id,
                           isActive: _activeModelId == m.id,
                           onDownload: () => _download(m),
                           onDelete: () => _delete(m),
                           onActivate: () => _activate(m),
                         ),
                       ),
                       if (m != ModelManager.availableModels.last) const SettingsDivider(),
                     ],
                   );
                }).toList(),
             ],
           ),
      ],
    );
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

  Widget _buildAudioDropdown(List<InputDevice> devices, String? currentId) {
     final loc = AppLocalizations.of(context)!;
     final displayMap = {for (var d in devices) d.id: d.label};
     displayMap['default'] = "${loc.systemDefault} (Default)";
     
     return Container(
        height: 28,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: MacosTheme.of(context).canvasColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MacosColors.separatorColor),
        ),
        child: MacosPopupButton<String?>(
          value: devices.any((d) => d.id == currentId) ? currentId : null,
          hint: const Text("Select Device"),
          items: [
            MacosPopupMenuItem(value: null, child: Text(loc.systemDefault)),
            ...devices.map((d) => MacosPopupMenuItem(value: d.id, child: Text(d.label, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (id) async {
             String? name = devices.where((d) => d.id == id).firstOrNull?.label;
             await ConfigService().setAudioInputDeviceId(id, name: name);
             setState((){});
             await AppService().engine.refreshInputDevice();
          },
        ),
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
             // Audio Input
             FutureBuilder<List<InputDevice>>(
               future: AppService().engine.listInputDevices(),
               builder: (ctx, snapshot) {
                 final devices = snapshot.data ?? [];
                 final current = ConfigService().audioInputDeviceId;
                 return SettingsTile(
                   label: loc.audioInput,
                   icon: CupertinoIcons.mic,
                   child: _buildAudioDropdown(devices, current),
                 );
               }
             ),
          ],
        ),
        

        const SizedBox(height: 32),
        // 3. Shortcuts
        SettingsGroup(
          title: loc.triggerKey,
          children: [
            SettingsTile(
              label: loc.triggerKeyDesc,
              icon: CupertinoIcons.keyboard,
              child: Row(
                children: [
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     decoration: BoxDecoration(
                       color: _isCapturingKey ? AppTheme.getAccent(context) : MacosColors.systemGrayColor.withOpacity(0.2),
                       borderRadius: BorderRadius.circular(6),
                     ),
                     child: Text(
                       _isCapturingKey ? loc.pressAnyKey : _currentKeyName,
                       style: AppTheme.mono(context).copyWith(
                         color: _isCapturingKey ? Colors.white : null
                       ),
                     ),
                   ),
                   const SizedBox(width: 8),
                   MacosIconButton(
                     icon: const MacosIcon(CupertinoIcons.pencil),
                     onPressed: _startKeyCapture,
                   ),
                ],
              ),
            ),
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
                       controller: TextEditingController(text: ConfigService().aiCorrectionPrompt),
                       decoration: BoxDecoration(
                          color: AppTheme.getInputBackground(context),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.getBorder(context)),
                       ),
                       onChanged: (v) => ConfigService().setAiCorrectionPrompt(v),
                     ),
                     
                     const SizedBox(height: 16),
                     
                     // 3. Custom API Toggle
                     Row(
                       children: [
                          MacosCheckbox(
                            value: _showCustomApi || (ConfigService().llmApiKeyOverride?.isNotEmpty ?? false),
                            onChanged: (v) {
                               setState(() => _showCustomApi = v);
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(loc.apiConfig, style: AppTheme.body(context)),
                       ],
                     ),
                     
                     // 4. API Fields
                     if (_showCustomApi || (ConfigService().llmApiKeyOverride?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MacosColors.systemGrayColor.withOpacity(0.1),
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
                 onChanged: (v) async { await ConfigService().setDiaryEnabled(v); setState((){}); },
               ),
             ),
             if (ConfigService().diaryEnabled) ...[
                const SettingsDivider(),
                SettingsTile(
                  label: loc.diaryTrigger,
                  icon: CupertinoIcons.keyboard_chevron_compact_down,
                  child: Row(
                    children: [
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(
                           color: _isCapturingDiaryKey ? AppTheme.getAccent(context) : MacosColors.systemGrayColor.withOpacity(0.2),
                           borderRadius: BorderRadius.circular(6),
                         ),
                         child: Text(
                           _isCapturingDiaryKey ? loc.pressAnyKey : _diaryKeyName,
                           style: AppTheme.mono(context).copyWith(
                             color: _isCapturingDiaryKey ? Colors.white : null
                           ),
                         ),
                       ),
                       const SizedBox(width: 8),
                       MacosIconButton(
                         icon: const MacosIcon(CupertinoIcons.pencil),
                         onPressed: () => _startKeyCapture(isDiary: true),
                       ),
                    ],
                  ),
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
                )
             ]
          ],
        ),
      ],
    );
  }

  Widget _buildActionBtn(BuildContext context, {
    required bool isDownloaded, required bool isLoading, required bool isActive,
    required VoidCallback onDownload, required VoidCallback onDelete, required VoidCallback onActivate
  }) {
    if (isLoading) return const ProgressCircle(value: null);
    if (!isDownloaded) {
       return PushButton(
         controlSize: ControlSize.regular,
         // Use Primary Color (Teal) for Download
         color: AppTheme.getAccent(context), 
         onPressed: onDownload,
         child: const Text("Download", style: TextStyle(color: Colors.white)),
       );
    }
    // Downloaded
    return Row(
      children: [
        if (isActive) 
           const Row(
             children: [
               Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppTheme.successColor),
               SizedBox(width: 4),
               Text("Active", style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold, fontSize: 12)),
             ],
           )
        else
           PushButton(
             controlSize: ControlSize.regular,
             color: MacosColors.controlColor.resolveFrom(context),
             onPressed: onActivate, 
             child: const Text("Activate")
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
                  color: Colors.black.withOpacity(0.2),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: MacosColors.systemGrayColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MacosColors.systemGrayColor.withOpacity(0.2)),
            ),
            child: Text(
              "v$version", 
              style: AppTheme.mono(context).copyWith(fontSize: 12, color: MacosColors.secondaryLabelColor)
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
  final Widget child;
  final IconData? icon; // Added Icon support

  const SettingsTile({super.key, required this.label, required this.child, this.icon});

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
          Expanded(child: Text(label, style: AppTheme.body(context))),
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
      color: MacosColors.separatorColor.withOpacity(0.5), 
      indent: 16, 
      endIndent: 0
    );
  }
}
