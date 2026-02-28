import 'dart:io';

import 'native_input.dart';
import 'native_input_base.dart';
import 'native_input_windows.dart';

/// 根据当前平台创建对应的 NativeInput 实现
NativeInputBase createNativeInput() {
  if (Platform.isMacOS) return NativeInput();
  if (Platform.isWindows) return NativeInputWindows();
  // if (Platform.isLinux) return NativeInputLinux();
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
