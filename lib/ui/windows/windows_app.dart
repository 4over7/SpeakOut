import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';
import 'windows_home.dart';

/// Windows 平台入口 Widget
///
/// 使用 fluent_ui 的 FluentApp，提供 Windows 11 风格的 UI。
class WindowsAppWrapper extends StatefulWidget {
  const WindowsAppWrapper({super.key});

  @override
  State<WindowsAppWrapper> createState() => _WindowsAppWrapperState();
}

class _WindowsAppWrapperState extends State<WindowsAppWrapper> {
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
      iconPath: 'assets/app_icon.ico',
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
      return FluentApp(
        debugShowCheckedModeBanner: false,
        home: const ScaffoldPage(
          content: Center(child: ProgressRing()),
        ),
      );
    }

    return ValueListenableBuilder<Locale?>(
      valueListenable: ConfigService().localeNotifier,
      builder: (context, locale, _) {
        return FluentApp(
          title: 'SpeakOut',
          theme: FluentThemeData.light().copyWith(
            accentColor: Colors.green,
          ),
          darkTheme: FluentThemeData.dark().copyWith(
            accentColor: Colors.green,
          ),
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            FluentLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WindowsHomePage(),
        );
      },
    );
  }
}
