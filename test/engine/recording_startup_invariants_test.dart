import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

/// CoreEngine 直接依赖 FFI 单例和真实 ASR provider，这里只守住启动
/// 状态机的关键顺序；这是形状回归测试，不代替真机麦克风故障冒烟。
void main() {
  const path = 'lib/engine/core_engine.dart';

  MethodDeclaration methodNamed(String name) {
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final cls = unit.declarations.whereType<ClassDeclaration>().firstWhere(
      (c) => c.name.lexeme == 'CoreEngine',
    );
    return cls.members.whereType<MethodDeclaration>().firstWhere(
      (m) => m.name.lexeme == name,
      orElse: () => throw StateError('没找到 $name，扫描失效'),
    );
  }

  test('provider.start 返回后必须再确认 starting，才能启动原生麦克风', () {
    final body = methodNamed('startRecording').toSource();
    final providerStartIdx = body.indexOf('await startingProvider.start()');
    final staleGuardIdx = body.indexOf(
      '_recordingState != RecordingState.starting',
      providerStartIdx,
    );
    final nativeStartIdx = body.indexOf(
      '_nativeInput.startAudioRecording()',
      staleGuardIdx,
    );

    expect(providerStartIdx, greaterThanOrEqualTo(0));
    expect(
      staleGuardIdx,
      greaterThan(providerStartIdx),
      reason: '异步 start 期间可能已被取消，返回后必须再验证状态',
    );
    expect(nativeStartIdx, greaterThan(staleGuardIdx), reason: '过期启动不能再打开麦克风');
  });

  test('原生麦克风启动失败时先回滚 ASR session，再清状态', () {
    final body = methodNamed('startRecording').toSource();
    final failureIdx = body.indexOf('if (!success)');
    final abortIdx = body.indexOf(
      'await _abortStartedAsrSession(startingProvider)',
      failureIdx,
    );
    final cleanupIdx = body.indexOf('_cleanupRecordingState()', abortIdx);

    expect(failureIdx, greaterThanOrEqualTo(0));
    expect(
      abortIdx,
      greaterThan(failureIdx),
      reason: '不回滚会遗留 WebSocket 或原生 recognizer stream',
    );
    expect(cleanupIdx, greaterThan(abortIdx));
  });

  test('权限早退与通用 cleanup 都会清掉 toggle/翻译临时意图', () {
    final startBody = methodNamed('startRecording').toSource();
    final permissionIdx = startBody.indexOf('checkMicrophonePermission()');
    final transitionIdx = startBody.indexOf(
      '_recordingState = RecordingState.starting',
    );
    final cleanupIdx = startBody.indexOf(
      '_cleanupRecordingState()',
      permissionIdx,
    );
    final cleanupBody = methodNamed('_cleanupRecordingState').toSource();

    expect(cleanupIdx, greaterThan(permissionIdx));
    expect(
      cleanupIdx,
      lessThan(transitionIdx),
      reason: '权限失败在进入 starting 前就必须回滚热键意图',
    );
    expect(cleanupBody, contains('_isToggleMode = false'));
    expect(cleanupBody, contains('_translateOverride = null'));
    expect(cleanupBody, contains('_activeHotkeyCode = null'));
  });

  test('ASR 切换锁必须在权限与 provider 启动前拒绝录音', () {
    final body = methodNamed('startRecording').toSource();
    final switchGuardIdx = body.indexOf('if (_asrSwitchInProgress)');
    final cleanupIdx = body.indexOf('_cleanupRecordingState()', switchGuardIdx);
    final permissionIdx = body.indexOf('checkMicrophonePermission()');

    expect(switchGuardIdx, greaterThanOrEqualTo(0));
    expect(cleanupIdx, greaterThan(switchGuardIdx));
    expect(permissionIdx, greaterThan(cleanupIdx),
        reason: '切换期间不能让录音穿过 await 窗口使用即将 dispose 的 provider');
  });

  test('starting 期间取消不能抢先 stop 尚未完成的 provider.start', () {
    final body = methodNamed('cancelRecording').toSource();
    final startingBranchIdx = body.indexOf('if (wasStarting)');
    final returnIdx = body.indexOf('return;', startingBranchIdx);
    final providerStopIdx = body.indexOf('_asrProvider!.stop()', returnIdx);

    expect(startingBranchIdx, greaterThanOrEqualTo(0));
    expect(returnIdx, greaterThan(startingBranchIdx));
    expect(
      providerStopIdx,
      greaterThan(returnIdx),
      reason: 'provider.start 返回后由原启动任务统一回滚',
    );
  });

  test('dispose 必须等待在途 start/stop，再关 provider 与状态流', () {
    final startBody = methodNamed('startRecording').toSource();
    final stopBody = methodNamed('stopRecording').toSource();
    final disposeBody = methodNamed('dispose').toSource();

    expect(startBody, contains('_recordingStartInFlight = completion.future'));
    expect(stopBody, contains('_recordingStopInFlight = completion.future'));

    final awaitStartIdx = disposeBody.indexOf('await _recordingStartInFlight');
    final awaitStopIdx = disposeBody.indexOf('await _recordingStopInFlight');
    final providerDisposeIdx = disposeBody.indexOf('await _asrProvider?.dispose()');
    final streamCloseIdx = disposeBody.indexOf('await _statusController.close()');
    expect(awaitStartIdx, greaterThanOrEqualTo(0));
    expect(awaitStopIdx, greaterThan(awaitStartIdx));
    expect(providerDisposeIdx, greaterThan(awaitStopIdx));
    expect(streamCloseIdx, greaterThan(providerDisposeIdx),
        reason: '否则在途识别/闪念落盘会被退出流程截断');
  });
}
