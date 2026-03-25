/// 分发渠道标识，通过编译 flag 注入
/// 用法: flutter build macos --dart-define=DISTRIBUTION=appstore
class Distribution {
  Distribution._();

  static const String channel = String.fromEnvironment(
    'DISTRIBUTION',
    defaultValue: 'github',
  );

  /// 是否为 App Store 版本
  static bool get isAppStore => channel == 'appstore';

  /// 是否允许应用内自动更新（App Store 禁止绕过更新）
  static bool get supportsAutoUpdate => !isAppStore;

  /// 是否允许检查 GitHub/Gateway 更新
  static bool get supportsUpdateCheck => !isAppStore;
}
