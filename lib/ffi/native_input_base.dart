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

typedef CheckKeyPressedC = Int32 Function(Int32 keyCode);
typedef CheckKeyPressedDart = int Function(int keyCode);

// Audio Recording FFI Types
// Callback: void callback(const int16_t* samples, int sampleCount)
typedef AudioCallbackC = Void Function(Pointer<Int16> samples, Int32 sampleCount);
typedef AudioCallbackDart = void Function(Pointer<Int16> samples, int sampleCount);

typedef StartAudioRecordingC = Int32 Function(Pointer<NativeFunction<AudioCallbackC>> callback);
typedef StartAudioRecordingDart = int Function(Pointer<NativeFunction<AudioCallbackC>> callback);

typedef StopAudioRecordingC = Void Function();
typedef StopAudioRecordingDart = void Function();

typedef IsAudioRecordingC = Int32 Function();
typedef IsAudioRecordingDart = int Function();

typedef CheckMicrophonePermissionC = Int32 Function();
typedef CheckMicrophonePermissionDart = int Function();

typedef NativeFreeC = Void Function(Pointer<Void>);
typedef NativeFreeDart = void Function(Pointer<Void>);

abstract class NativeInputBase {
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback);
  void stopListener();
  void inject(String text);
  bool checkPermission();
  bool isKeyPressed(int keyCode);
  
  // Audio Recording
  bool startAudioRecording(Pointer<NativeFunction<AudioCallbackC>> callback);
  void stopAudioRecording();
  bool isAudioRecording();
  bool checkMicrophonePermission();
  void nativeFree(Pointer<Void> ptr);
}
