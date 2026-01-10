import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Typedefs matching C
typedef StartKeyboardListenerC = Int32 Function(Pointer<NativeFunction<KeyCallbackC>> callback);
typedef StartKeyboardListenerDart = int Function(Pointer<NativeFunction<KeyCallbackC>> callback);

typedef StopKeyboardListenerC = Void Function();
typedef StopKeyboardListenerDart = void Function();

typedef InjectTextC = Void Function(Pointer<Utf8> text);
typedef InjectTextDart = void Function(Pointer<Utf8> text);

typedef CheckPermissionC = Bool Function();
typedef CheckPermissionDart = bool Function();

// Callback type: void callback(int keyCode, bool isDown)
typedef KeyCallbackC = Void Function(Int32 keyCode, Bool isDown);

abstract class NativeInputBase {
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback);
  void stopListener();
  void inject(String text);
  bool checkPermission();
}
