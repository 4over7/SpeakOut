import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _LaunchUpdaterC = Int32 Function(Pointer<Utf8> scriptPath);
typedef _LaunchUpdaterDart = int Function(Pointer<Utf8> scriptPath);

void main() {
  test(
    'launch_updater 对不存在的 helper 明确返回失败',
    () {
      final dylib = DynamicLibrary.open('native_lib/libnative_input.dylib');
      final launchUpdater = dylib
          .lookup<NativeFunction<_LaunchUpdaterC>>('launch_updater')
          .asFunction<_LaunchUpdaterDart>();
      final missingPath = '${Directory.systemTemp.path}/'
          'speakout-updater-does-not-exist-$pid-${DateTime.now().microsecondsSinceEpoch}.sh';
      expect(File(missingPath).existsSync(), isFalse);
      final ptr = missingPath.toNativeUtf8();

      try {
        expect(launchUpdater(ptr), 0);
      } finally {
        calloc.free(ptr);
      }
    },
    skip: !Platform.isMacOS ? 'native updater 仅在 macOS 可用' : null,
  );
}
