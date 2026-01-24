import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/config_service.dart';
import 'ui/recording_overlay.dart';
import 'ui/settings_page.dart';
import 'services/app_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'engine/core_engine.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'ui/theme.dart';
import 'ui/dialogs/tool_confirmation_dialog.dart';
import 'ui/chat/chat_page.dart';

// Global Error Catcher
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    
    // Catch Build Errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                "Startup Error:\n${details.exception}\nStack: ${details.stack}",
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ),
        ),
      );
    };

    runApp(const SpeakOutApp());
  }, (error, stack) {
    print("CRITICAL ERROR: $error\n$stack");
  });
}

class SpeakOutApp extends StatefulWidget {
  const SpeakOutApp({super.key});

  @override
  State<SpeakOutApp> createState() => _SpeakOutAppState();
}

class _SpeakOutAppState extends State<SpeakOutApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: ConfigService().localeNotifier,
      builder: (context, locale, child) {
        // Fallback to system or English if ConfigService not ready
        final targetLocale = locale; 

        return MacosApp(
          title: 'SpeakOut',
          // Auto-adapt to system light/dark mode
          theme: MacosThemeData.light().copyWith(
            primaryColor: AppTheme.accentColor,
          ),
          darkTheme: MacosThemeData.dark().copyWith(
             primaryColor: AppTheme.accentColor,
          ),
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          
          // Localization
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Ensure we have a fallback resolution
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return supportedLocales.first;
            for (var supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale.languageCode) {
                return supportedLocale;
              }
            }
            return supportedLocales.first;
          },
          supportedLocales: AppLocalizations.supportedLocales,
          
          home: const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppService _appService = AppService();
  final SystemTray _systemTray = SystemTray();
  
  String _status = "初始化中...";
  bool _ready = false;
  String _lastError = "";
  bool _isRecording = false;
  String _currentKeyName = "Left Option";
  String _recognizedText = ""; 
  
  AppNotification? _currentNotification;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    // Async Init after first frame to prevent White Screen
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       await _initWindow();
       await _appService.init(); 
    });
    
    // Listen to Engine status
    _appService.engine.statusStream.listen((msg) {
      if (mounted) {
        setState(() {
           if (msg.startsWith("Error")) {
             _lastError = msg;
             _ready = false;
           } else if (msg.contains("Trusted: true") || msg.contains("Listener Started") || msg.contains("就绪") || msg.contains("Ready")) {
             _lastError = ""; // Clear error on successful start
             _ready = true;
             // Subscribe to partial results AFTER ASR is ready
             _subscribeToPartialResults();
           }
          _status = msg;
        });
      }
    });
    
    // Subscribe to Notifications
    NotificationService().stream.listen((n) {
      if (mounted) {
        setState(() => _currentNotification = n);
        _notificationTimer?.cancel();
        _notificationTimer = Timer(n.duration, () {
          if (mounted && _currentNotification == n) {
             setState(() => _currentNotification = null);
          }
        });
      }
    });

    _appService.engine.recordingStream.listen((isRecording) {
      if (mounted) {
        setState(() {
          _isRecording = isRecording;
          // Clear recognized text when starting new recording
          if (isRecording) {
            _recognizedText = "";
          }
        });
      }
    });
    
    // Subscribe to recognized text results (final)
    _appService.engine.resultStream.listen((text) {
      if (mounted && text.isNotEmpty) {
        setState(() {
          _recognizedText = text;
        });
        // Clear OVERLAY text after 5 seconds (but keep main UI result)
        _overlayText = text;
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _overlayText == text && !_isRecording) {
            setState(() {
              _overlayText = "";
            });
          }
        });
      }
    });
  }
  
  bool _partialSubscribed = false;
  String _overlayText = ""; // Separate state for overlay (with auto-clear)
  
  static const _overlayChannel = MethodChannel('com.SpeakOut/overlay');
  
  void _subscribeToPartialResults() {
    if (_partialSubscribed) return;
    final stream = _appService.engine.partialTextStream;
    if (stream != null) {
      stream.listen((partialText) {
        if (mounted && _isRecording && partialText.isNotEmpty) {
          setState(() {
            _recognizedText = partialText;
            _overlayText = partialText;
          });
            // UPDATE NATIVE OVERLAY with partial text
            // Fix: Truncate to display valid tail for long text (Limited to ~12 chars)
            try {
              String displayText = partialText;
              if (displayText.length > 12) {
                 displayText = "...${displayText.substring(displayText.length - 12)}";
              }
              _overlayChannel.invokeMethod('updateStatus', {"text": displayText});
            } catch (e) {
              // Ignore
            }
        }
      });
      _partialSubscribed = true;
    }
  }
  
  // Waveform Animation State
  final List<double> _waveHeights = List.generate(5, (_) => 0.3);
  Timer? _waveTimer;
  
  @override
  void dispose() {
    _waveTimer?.cancel();
    super.dispose();
  }
  
  final _random = Random();
  
  void _startWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted && _isRecording) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            // Match native: random height between 4-24px (normalized to 0.17-1.0)
            _waveHeights[i] = 0.17 + _random.nextDouble() * 0.83;
          }
        });
      }
    });
  }
  
  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
  }
  
  Widget _buildAnimatedWaveform() {
    // Start timer if not running
    if (_waveTimer == null || !_waveTimer!.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startWaveAnimation();
      });
    }
    
    // 7 bars matching native overlay style EXACTLY
    // Native: barCount=7, barWidth=5, height range 4-24px
    // We scale to fit 120px circle: use height 8-48px 
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(7, (index) {
        final height = 8.0 + 40.0 * _waveHeights[index % _waveHeights.length];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: 5,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2.5),
          ),
        );
      }),
    );
  }

  Future<void> _initSystemTray() async {
    String path = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/tray_icon.png';
    // We assume assets exist or use default blank. 
    
    final AppWindow appWindow = AppWindow();
    
    await _systemTray.initSystemTray(
      title: "", // No title as requested
      iconPath: path,
      isTemplate: true,
    );
    
    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: 'Show', onClicked: (menuItem) => appWindow.show()),
      MenuItemLabel(label: 'Hide', onClicked: (menuItem) => appWindow.hide()),
      MenuItemLabel(label: 'Exit', onClicked: (menuItem) => appWindow.close()),
    ]);
    
    await _systemTray.setContextMenu(menu);
    
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        Platform.isWindows ? appWindow.show() : _systemTray.popUpContextMenu();
      } else if (eventName == kSystemTrayEventRightClick) {
        Platform.isWindows ? _systemTray.popUpContextMenu() : appWindow.show();
      }
    });
  }

  Future<void> _initWindow() async {
      // windowManager initialized in main now
      WindowOptions windowOptions = const WindowOptions(
        size: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setSize(const Size(800, 600));
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      });
      
      // Init Tray
      await _initSystemTray();
  }

  // Legacy init methods removed (See Refactor Phase 3)
  
  // Punctuation logic moved to AppService
  
  // Hotkey loaded by ConfigService

  String _getLocalizedStatus(String status) {
    // Basic mapping for known engine statuses
    final loc = AppLocalizations.of(context)!;
    if (status.contains("Initializing")) return loc.initializing;
    if (status.contains("Listener Started")) return ""; // Hidden, showed by Ready Tip
    if (status.contains("Trusted: true")) return "";
    // If it's an error, return as is (or map common errors)
    if (status.startsWith("Error")) return "${loc.error}: ${status.replaceAll("Error", "")}";
    // Fallback
    return status; 
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    
    return MacosWindow(
      // sidebar: removed for cleaner UI
      child: MacosScaffold(
        backgroundColor: AppTheme.getBackground(context), // Match mockup
        toolBar: ToolBar(title: Text(loc.appTitle)),
        children: [
          ContentArea(
            builder: (context, scrollController) {
              return Container(
                color: AppTheme.getBackground(context), // Force background
                child: Stack(
                children: [
                  // Chat Button (Top Right, Left of Settings)
                  Positioned(
                    top: 16,
                    right: 64, // Shift left
                    child: MacosIconButton(
                      icon: const MacosIcon(
                        CupertinoIcons.chat_bubble_2_fill,
                        color: MacosColors.systemGrayColor,
                        size: 32,
                      ),
                      backgroundColor: MacosColors.transparent,
                      onPressed: () {
                         Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const ChatPage()),
                         );
                      },
                    ),
                  ),

                  // Settings Button (Top Right)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: MacosIconButton(
                      icon: const MacosIcon(
                        CupertinoIcons.settings,
                        color: MacosColors.systemGrayColor,
                        size: 36,
                      ),
                      backgroundColor: MacosColors.transparent,
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SettingsPage()),
                        );
                        // Reload hotkey
                        if (mounted) {
                          setState(() {
                             _currentKeyName = ConfigService().pttKeyName;
                          });
                        }
                      },
                    ),
                  ),
                  
                  // === FIXED LAYOUT WITH STACK ===
                  // Error message at top
                  if (_lastError.isNotEmpty)
                    Positioned(
                      top: 16,
                      left: 24,
                      right: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const MacosIcon(CupertinoIcons.exclamationmark_triangle, color: AppTheme.errorColor, size: 16),
                            const SizedBox(width: 8),
                            Flexible(child: Text(_lastError, style: AppTheme.body(context).copyWith(color: AppTheme.errorColor))),
                          ],
                        ),
                      ),
                    ),
                  
                  // Notification Banner (Top Center, above Mic)
                  if (_currentNotification != null)
                    Positioned(
                      top: 80, 
                      left: 0, 
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _currentNotification!.type == NotificationType.error 
                                ? AppTheme.errorColor 
                                : (_currentNotification!.type == NotificationType.success ? MacosColors.systemGreenColor : MacosColors.systemBlueColor),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
                            ]
                          ),
                          child: Text(
                            _currentNotification!.message,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  
                  // Main content area - FIXED POSITIONS using LayoutBuilder
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate vertical center
                        final cy = constraints.maxHeight / 2;
                        
                        return Stack(
                          children: [
                            // 1. Mic Button: Center at (cy - 60)
                            // Size 120, so top = cy - 60 - 60 = cy - 120
                            Positioned(
                              top: cy - 100, // Slightly up from center
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _ready ? AppTheme.accentColor : MacosColors.systemGrayColor,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: _isRecording 
                                    ? _buildAnimatedWaveform()
                                    : const Icon(
                                        CupertinoIcons.mic_fill,
                                        size: 48, 
                                        color: Colors.white,
                                      ),
                                ),
                              ),
                            ),
                            
                            // 2. BRANDING: Fixed center title
                            Positioned(
                              top: cy + 40,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  "子曰",
                                  style: AppTheme.display(context).copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ),
                            ),
                            
                            // 3. Status/Hint: Dynamic line below title
                            Positioned(
                              top: cy + 90,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Builder(
                                  builder: (ctx) {
                                    // 1. Error Priority
                                    if (_lastError.isNotEmpty) {
                                      return Text(
                                        _lastError, 
                                        style: AppTheme.body(context).copyWith(color: MacosColors.systemRedColor),
                                      );
                                    }
                                    
                                    // 2. Recording / Processing
                                    if (_isRecording) {
                                      return Text(
                                        loc.recording,
                                        style: AppTheme.body(context).copyWith(color: AppTheme.accentColor),
                                      );
                                    }
                                    
                                    // 3. Not Ready (Initializing)
                                    if (!_ready) {
                                      return Text(
                                        _getLocalizedStatus(_status),
                                        style: AppTheme.body(context).copyWith(color: MacosColors.secondaryLabelColor),
                                      );
                                    }
                                    
                                    // 4. Ready -> Show Interaction Hint
                                    return Text(
                                      loc.readyTip(_currentKeyName),
                                      style: AppTheme.body(context).copyWith(
                                        color: MacosColors.secondaryLabelColor.resolveFrom(context),
                                      ),
                                    );
                                  }
                                ),
                              ),
                            ),
                            
                            // 4. Progress Circle (Init)
                            if (!_ready && _status.contains("初始化"))
                              Positioned(
                                top: cy + 120,
                                left: 0,
                                right: 0,
                                child: const Center(child: ProgressCircle(value: null)),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  // Result display - FIXED BOTTOM POSITION
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: AnimatedOpacity(
                      opacity: _recognizedText.isNotEmpty ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          constraints: const BoxConstraints(maxWidth: 500),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _recognizedText.isEmpty ? " " : _recognizedText,
                            style: AppTheme.body(context),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // === END FIXED LAYOUT ===
                ],
                ), // Stack
              ); // Container
            }
          )
        ],
      ),
    );
  }
}
