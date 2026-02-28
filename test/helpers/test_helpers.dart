import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock path_provider: returns a temp directory for all platform paths.
/// Extracted from model_manager_test for reuse across test suites.
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  MockPathProviderPlatform(this.basePath);

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// Create an isolated temp directory for test file I/O.
Directory createTempDir(String prefix) {
  return Directory.systemTemp.createTempSync('speakout_${prefix}_');
}

/// Delete a temp directory if it still exists.
void cleanupTempDir(Directory dir) {
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}
