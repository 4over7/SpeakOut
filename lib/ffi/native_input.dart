import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'native_input_ffi.dart';

/// macOS 平台的 NativeInput 实现
///
/// 仅负责 macOS App Bundle 的动态库路径查找，
/// FFI 绑定逻辑全部复用 [NativeInputFFI] 基类。
class NativeInput extends NativeInputFFI {
  NativeInput() {
    debugPrint("[NativeInput] Initializing (macOS)...");

    final path = _resolveDylibPath();

    // Safety check
    if (!File(path).existsSync()) {
      debugPrint("[NativeInput] CRITICAL: File Not Found at $path");
    }

    try {
      final dylib = DynamicLibrary.open(path);
      debugPrint("[NativeInput] DynamicLibrary.open($path) SUCCESS");
      initWithLibrary(dylib);
    } catch (e) {
      debugPrint("[NativeInput] DynamicLibrary.open FAILED: $e");
      rethrow;
    }
  }

  /// macOS 特有的 dylib 路径查找逻辑
  ///
  /// 查找顺序:
  /// 1. Contents/MacOS/native_lib/ (install.sh 手动部署)
  /// 2. Contents/Frameworks/App.framework/.../flutter_assets/native_lib/ (Release build)
  /// 3. CWD/native_lib/ (开发模式 dart run)
  static String _resolveDylibPath() {
    var path = 'native_lib/libnative_input.dylib';

    final exeDir = File(Platform.resolvedExecutable).parent;
    debugPrint("[NativeInput] ExeDir: ${exeDir.path}");

    final bundleLibPath = '${exeDir.path}/native_lib/libnative_input.dylib';
    final appDir = exeDir.parent; // Contents/
    final flutterAssetsPath =
        '${appDir.path}/Frameworks/App.framework/Versions/A/Resources/flutter_assets/native_lib/libnative_input.dylib';

    try {
      if (File(bundleLibPath).existsSync()) {
        path = bundleLibPath;
        debugPrint("[NativeInput] Found in Bundle MacOS: $path");
      } else if (File(flutterAssetsPath).existsSync()) {
        path = flutterAssetsPath;
        debugPrint("[NativeInput] Found in flutter_assets: $path");
      } else if (!File(path).existsSync()) {
        path = '${Directory.current.path}/native_lib/libnative_input.dylib';
        debugPrint("[NativeInput] Fallback to CWD: $path");
      }
    } catch (e) {
      debugPrint("[NativeInput] Path Verify Error: $e");
    }

    return path;
  }
}
