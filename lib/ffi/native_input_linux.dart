import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'native_input_ffi.dart';

/// Linux 平台的 NativeInput 实现
///
/// 仅负责 Linux 的 .so 路径查找，
/// FFI 绑定逻辑全部复用 [NativeInputFFI] 基类。
class NativeInputLinux extends NativeInputFFI {
  NativeInputLinux() {
    debugPrint("[NativeInputLinux] Initializing...");

    final path = _resolveSoPath();

    try {
      final dylib = DynamicLibrary.open(path);
      debugPrint("[NativeInputLinux] DynamicLibrary.open($path) SUCCESS");
      initWithLibrary(dylib);
    } catch (e) {
      debugPrint("[NativeInputLinux] DynamicLibrary.open FAILED: $e");
      rethrow;
    }
  }

  /// Linux 的 .so 路径查找逻辑
  ///
  /// 查找顺序:
  /// 1. 可执行文件同级目录 (Release build)
  /// 2. lib/ 子目录 (Flutter bundle)
  /// 3. CWD/native_lib/ (开发模式)
  static String _resolveSoPath() {
    const libName = 'libnative_input.so';

    final exeDir = File(Platform.resolvedExecutable).parent;
    debugPrint("[NativeInputLinux] ExeDir: ${exeDir.path}");

    // Path 1: 与可执行文件同级
    final exeDirPath = '${exeDir.path}/$libName';
    if (File(exeDirPath).existsSync()) {
      debugPrint("[NativeInputLinux] Found next to exe: $exeDirPath");
      return exeDirPath;
    }

    // Path 2: lib/ 子目录 (snap/flatpak bundle)
    final libDirPath = '${exeDir.path}/lib/$libName';
    if (File(libDirPath).existsSync()) {
      debugPrint("[NativeInputLinux] Found in lib/: $libDirPath");
      return libDirPath;
    }

    // Path 3: CWD fallback (开发时)
    final cwdPath = '${Directory.current.path}/native_lib/$libName';
    debugPrint("[NativeInputLinux] Fallback to CWD: $cwdPath");
    return cwdPath;
  }
}
