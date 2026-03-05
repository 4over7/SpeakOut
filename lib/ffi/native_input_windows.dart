import 'dart:ffi';
import 'dart:io';
import 'native_input_ffi.dart';
import 'package:speakout/config/app_log.dart';

/// Windows 平台的 NativeInput 实现
///
/// 仅负责 Windows 的 DLL 路径查找，
/// FFI 绑定逻辑全部复用 [NativeInputFFI] 基类。
class NativeInputWindows extends NativeInputFFI {
  NativeInputWindows() {
    AppLog.d("[NativeInputWindows] Initializing...");

    final path = _resolveDllPath();

    try {
      final dylib = DynamicLibrary.open(path);
      AppLog.d("[NativeInputWindows] DynamicLibrary.open($path) SUCCESS");
      initWithLibrary(dylib);
    } catch (e) {
      AppLog.d("[NativeInputWindows] DynamicLibrary.open FAILED: $e");
      rethrow;
    }
  }

  /// Windows 的 DLL 路径查找逻辑
  ///
  /// 查找顺序:
  /// 1. 可执行文件同级目录 (Release build: runner 目录)
  /// 2. CWD/native_lib/ (开发模式)
  static String _resolveDllPath() {
    const libName = 'native_input.dll';

    final exeDir = File(Platform.resolvedExecutable).parent;
    AppLog.d("[NativeInputWindows] ExeDir: ${exeDir.path}");

    // Path 1: 与 .exe 同级 (flutter build windows --release 的输出目录)
    final exeDirPath = '${exeDir.path}/$libName';
    if (File(exeDirPath).existsSync()) {
      AppLog.d("[NativeInputWindows] Found next to exe: $exeDirPath");
      return exeDirPath;
    }

    // Path 2: native_lib 子目录 (开发时)
    final nativeLibPath = '${exeDir.path}/native_lib/$libName';
    if (File(nativeLibPath).existsSync()) {
      AppLog.d("[NativeInputWindows] Found in native_lib: $nativeLibPath");
      return nativeLibPath;
    }

    // Path 3: CWD fallback
    final cwdPath = '${Directory.current.path}/native_lib/$libName';
    AppLog.d("[NativeInputWindows] Fallback to CWD: $cwdPath");
    return cwdPath;
  }
}
