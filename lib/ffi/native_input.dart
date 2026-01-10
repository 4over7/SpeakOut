import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'native_input_base.dart';

class NativeInput implements NativeInputBase {
  late DynamicLibrary _dylib;

  late StartKeyboardListenerDart _startListener;
  late StopKeyboardListenerDart _stopListener;
  late InjectTextDart _injectText;
  late CheckPermissionDart _checkPermission;

  // Debug Logger
  void _log(String msg) {
    try {
      final f = File('/tmp/SpeakOut_debug.log');
      final time = DateTime.now().toIso8601String();
      f.writeAsStringSync("[$time] [Dart] $msg\n", mode: FileMode.append);
    } catch (e) {
      print("Log Failed: $e");
    }
  }

  NativeInput() {
    _log("Initializing NativeInput...");
    
    // Correct Path Resolution for App Bundle vs Debug
    var path = 'native_lib/libnative_input.dylib';
    
    // Check if we are in an App Bundle (Contents/MacOS/SpeakOut)
    final exeDir = File(Platform.resolvedExecutable).parent;
    _log("ExeDir: ${exeDir.path}");
    
    // Check injected path (Manual Install Script)
    final bundleLibPath = '${exeDir.path}/native_lib/libnative_input.dylib';
    _log("Checking Bundle Path: $bundleLibPath");
    
    // Normalize path to verify
    try {
      if (File(bundleLibPath).existsSync()) {
        path = bundleLibPath;
        _log("Found in Bundle: $path");
      } else if (!File(path).existsSync()) {
         // Fallback for terminal 'dart run' from root
         path = '${Directory.current.path}/native_lib/libnative_input.dylib';
         _log("Fallback to CWD: $path");
      }
    } catch (e) {
       _log("Path Verify Error: $e");
    }
    
    // Safety check
    if (!File(path).existsSync()) {
       _log("CRITICAL: File Not Found at $path");
    }

    try {
       _dylib = DynamicLibrary.open(path);
       _log("DynamicLibrary.open($path) SUCCESS");
    } catch (e) {
       _log("DynamicLibrary.open FAILED: $e");
       rethrow;
    }

    try {
      _startListener = _dylib
          .lookup<NativeFunction<StartKeyboardListenerC>>('start_keyboard_listener')
          .asFunction();
      _log("Lookup start_keyboard_listener SUCCESS");

      _stopListener = _dylib
          .lookup<NativeFunction<StopKeyboardListenerC>>('stop_keyboard_listener')
          .asFunction();

      _injectText = _dylib
          .lookup<NativeFunction<InjectTextC>>('inject_text')
          .asFunction();

      _checkPermission = _dylib
          .lookup<NativeFunction<CheckPermissionC>>('check_permission')
          .asFunction();
          
    } catch (e) {
      _log("Symbol Lookup FAILED: $e");
      rethrow;
    }
  }

  @override
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback) {
    _log("Dart: Calling start_keyboard_listener...");
    final result = _startListener(callback);
    _log("Dart: start_keyboard_listener returned $result");
    return result == 1;
  }

  @override
  void stopListener() {
    _log("Dart: Calling stop_keyboard_listener...");
    _stopListener();
  }

  @override
  void inject(String text) {
    // _log("Dart: Injecting text...");
    final ptr = text.toNativeUtf8();
    _injectText(ptr);
    calloc.free(ptr);
  }

  @override
  bool checkPermission() {
    _log("Dart: Calling check_permission...");
    final result = _checkPermission();
    _log("Dart: check_permission returned $result");
    return result == 1; // Assuming 1 is true
  }
}
