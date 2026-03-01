import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';
import 'linux_home.dart';

/// Linux 平台入口 Widget
///
/// 使用 Material Design 3，提供 GNOME/GTK 风格的 UI。
class LinuxAppWrapper extends StatefulWidget {
  const LinuxAppWrapper({super.key});

  @override
  State<LinuxAppWrapper> createState() => _LinuxAppWrapperState();
}

class _LinuxAppWrapperState extends State<LinuxAppWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ConfigService().init();
    await _initWindow();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _initWindow() async {
    const windowOptions = WindowOptions(
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

    await _initSystemTray();
  }

  Future<void> _initSystemTray() async {
    final systemTray = SystemTray();
    final appWindow = AppWindow();

    await systemTray.initSystemTray(
      title: "SpeakOut",
      iconPath: 'assets/tray_icon.png',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: 'Show', onClicked: (_) => appWindow.show()),
      MenuItemLabel(label: 'Hide', onClicked: (_) => appWindow.hide()),
      MenuItemLabel(label: 'Exit', onClicked: (_) => appWindow.close()),
    ]);
    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        appWindow.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ValueListenableBuilder<Locale?>(
      valueListenable: ConfigService().localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'SpeakOut',
          theme: ThemeData(
            colorSchemeSeed: Colors.green,
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.green,
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LinuxHomePage(),
        );
      },
    );
  }
}
