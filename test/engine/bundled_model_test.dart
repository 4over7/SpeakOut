import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/engine/model_manager.dart';
import 'package:speakout/services/config_service.dart';
import 'dart:io';

class _MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  _MockPathProvider(this.basePath);
  @override
  Future<String?> getApplicationSupportPath() async => basePath;
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// 内置模型机制的边界行为。
///
/// 测试进程的 resolvedExecutable 是 flutter_tester，bundle 内不存在
/// Contents/Resources/models，因此探测必须一律返回「未内置」并优雅回退到原下载流程 ——
/// 这正是开发期 `flutter run` 的行为，绝不能误判成已内置。
void main() {
  late Directory tmpDir;
  late ModelManager manager;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('speakout_bundled_');
    PathProviderPlatform.instance = _MockPathProvider(tmpDir.path);
    SharedPreferences.setMockInitialValues({});
    await ConfigService().init();
    manager = ModelManager();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('测试环境下没有内置模型，isModelBundled 一律 false', () {
    for (final m in ModelManager.offlineModels) {
      expect(manager.isModelBundled(m.id), isFalse,
          reason: '${m.id} 不应被误判为内置（bundle 内无 Resources/models）');
    }
  });

  test('未知模型 id 不会崩，返回 null', () {
    expect(manager.bundledModelDir('no_such_model_id'), isNull);
  });

  test('没有内置模型时，冗余检测返回 0 且不报错', () async {
    final (total, dirs) = await manager.findRedundantBundledCopies();
    expect(total, 0);
    expect(dirs, isEmpty);
  });

  test('没有内置模型时，清理是安全的空操作', () async {
    final freed = await manager.cleanupRedundantBundledCopies();
    expect(freed, 0);
  });

  test('hasLocalCopy：目录不存在时为 false', () async {
    expect(await manager.hasLocalCopy(ModelManager.offlineModels.first.id), isFalse);
  });

  test('hasLocalCopy：有目录但缺 tokens 文件仍为 false（残缺不算可用副本）', () async {
    final m = ModelManager.offlineModels.first;
    final dirName = m.url.split('/').last.replaceAll('.tar.bz2', '');
    Directory('${tmpDir.path}/Models/$dirName').createSync(recursive: true);
    expect(await manager.hasLocalCopy(m.id), isFalse);
  });
}
