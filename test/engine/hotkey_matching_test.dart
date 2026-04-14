import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/core_engine.dart';
import 'package:speakout/ui/settings/settings_shared.dart';

/// 运行时 `_modifiersMatch` 与设置侧 `findHotkeyConflict` 语义对齐回归测试
///
/// 背景：这两者必须语义一致，否则设置页能通过但运行时行为意外（或反之）。
/// 历史上出现过多次：
/// - 裸键 modifiers=0 在运行时匹配一切，但设置页按裸键精确匹配放行
/// - 子集匹配 vs 精确匹配不一致
/// - AI 一键调试基础键保存/匹配为裸键但冲突检查用了带 modifier
///
/// 本测试锁定当前（2026-04-14）语义：
/// - 裸键（requiredFlags=0）匹配任何 modifier 组合
/// - 组合键（requiredFlags≠0）精确匹配（Cmd+K 不在 Cmd+Shift+K 按下时触发）
void main() {
  // Modifier flag constants (from CoreEngine)
  const int cmd = CoreEngine.kModLCmd;    // 0x0008
  const int shift = CoreEngine.kModLShift; // 0x0002
  const int opt = CoreEngine.kModLAlt;    // 0x0020

  // Sample non-modifier keyCode (not in ownModifierMask switch)
  const int keyK = 40;
  const int keyJ = 38;
  // Modifier keyCode itself
  const int keyRightOption = 61;

  group('CoreEngine.modifiersMatch — runtime matching semantics', () {
    test('裸键（requiredFlags=0）匹配无 modifier 的按键', () {
      expect(CoreEngine.modifiersMatch(keyK, 0, 0), isTrue);
    });

    test('裸键匹配任何 modifier 组合（设计上：裸键吃掉一切）', () {
      expect(CoreEngine.modifiersMatch(keyK, cmd, 0), isTrue);
      expect(CoreEngine.modifiersMatch(keyK, cmd | shift, 0), isTrue);
      expect(CoreEngine.modifiersMatch(keyK, cmd | opt, 0), isTrue);
    });

    test('Cmd+K 在按 Cmd+K 时匹配', () {
      expect(CoreEngine.modifiersMatch(keyK, cmd, cmd), isTrue);
    });

    test('Cmd+K 在按裸 K 时不匹配', () {
      expect(CoreEngine.modifiersMatch(keyK, 0, cmd), isFalse);
    });

    test('Cmd+K 在按 Cmd+Shift+K 时不匹配（精确匹配，不是子集）', () {
      expect(CoreEngine.modifiersMatch(keyK, cmd | shift, cmd), isFalse);
    });

    test('Cmd+K 在按 Option+K 时不匹配', () {
      expect(CoreEngine.modifiersMatch(keyK, opt, cmd), isFalse);
    });

    test('Cmd+K 在按 Cmd+Option+K 时不匹配（不同修饰键组合相互独立）', () {
      expect(CoreEngine.modifiersMatch(keyK, cmd | opt, cmd), isFalse);
    });

    test('Cmd+Shift+K 在按 Cmd+Shift+K 时匹配', () {
      expect(CoreEngine.modifiersMatch(keyK, cmd | shift, cmd | shift), isTrue);
    });

    test('修饰键自身的 own-modifier bit 被剥离', () {
      // 设 Right Option 为 PTT key（裸键）。按下时 current 包含 Right Option 自身的 flag (kModRAlt)。
      // 由于 requiredFlags=0 走 early return → true，不依赖剥离
      expect(CoreEngine.modifiersMatch(keyRightOption, CoreEngine.kModRAlt, 0), isTrue);
    });

    test('修饰键 + 额外 modifier: stripped 后精确匹配', () {
      // 触发键是 Right Option，需要同时按 Shift
      // current 包含 Right Option 自身 (kModRAlt) + Shift
      // stripped = shift（剥离 own-modifier kModRAlt）
      expect(CoreEngine.modifiersMatch(keyRightOption, CoreEngine.kModRAlt | shift, shift), isTrue);
    });
  });

  group('findHotkeyConflict — settings-side conflict detection', () {
    test('不同 keyCode → 不冲突', () {
      final active = {(keyK, cmd): 'Feature A'};
      expect(findHotkeyConflict(active, (keyJ, cmd)), isNull);
    });

    test('同 keyCode 同 modifiers → 冲突', () {
      final active = {(keyK, cmd): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, cmd)), equals('Feature A'));
    });

    test('同 keyCode 都是裸键 → 冲突', () {
      final active = {(keyK, 0): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, 0)), equals('Feature A'));
    });

    test('裸键 vs 组合键（同 keyCode）→ 冲突', () {
      final active = {(keyK, 0): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, cmd)),
          equals('Feature A'),
          reason: '裸键在运行时匹配一切，会吃掉组合键');
    });

    test('组合键 vs 裸键（同 keyCode，顺序反过来）→ 冲突', () {
      final active = {(keyK, cmd): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, 0)),
          equals('Feature A'),
          reason: '新候选的裸键会吃掉已有的组合键');
    });

    test('Cmd+K vs Option+K（同 keyCode 不同非零 modifiers）→ 不冲突', () {
      final active = {(keyK, cmd): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, opt)), isNull,
          reason: '运行时精确匹配后两者独立，可共存');
    });

    test('Cmd+K vs Cmd+Shift+K（同 keyCode 不同非零 modifiers）→ 不冲突', () {
      final active = {(keyK, cmd): 'Feature A'};
      expect(findHotkeyConflict(active, (keyK, cmd | shift)), isNull,
          reason: '精确匹配下 Cmd+K 不会在 Cmd+Shift+K 时触发');
    });

    test('多个已有热键，只要有一个冲突就返回它', () {
      final active = {
        (keyK, cmd): 'Feature A',
        (keyJ, 0): 'Feature B',
      };
      expect(findHotkeyConflict(active, (keyJ, cmd)), equals('Feature B'));
    });

    test('空 activeKeys → 永远不冲突', () {
      expect(findHotkeyConflict({}, (keyK, cmd)), isNull);
    });
  });

  group('HotkeyCapturer — 捕获流程（修饰键延迟确认）', () {
    const int cmdL = 55; // Left Command keyCode
    const int keyK = 40;
    const int keyF1 = 122;
    const cmdMods = CoreEngine.kModLCmd;
    const shortDebounce = Duration(milliseconds: 50);
    const shortTimeout = Duration(milliseconds: 500);

    test('非修饰键立即捕获（裸 K）', () async {
      final controller = StreamController<(int, int)>.broadcast();
      final completer = Completer<(int, int)>();
      final capturer = HotkeyCapturer(
        keyStream: controller.stream,
        onCaptured: (kc, mf) => completer.complete((kc, mf)),
        onTimeout: () => completer.completeError('timeout'),
        modifierDebounce: shortDebounce,
        timeout: shortTimeout,
      )..start();

      controller.add((keyK, 0));
      final result = await completer.future;
      expect(result, (keyK, 0));
      capturer.cancel();
      await controller.close();
    });

    test('修饰键后接非修饰键 → 捕获组合键（Cmd+K）', () async {
      final controller = StreamController<(int, int)>.broadcast();
      final completer = Completer<(int, int)>();
      final capturer = HotkeyCapturer(
        keyStream: controller.stream,
        onCaptured: (kc, mf) => completer.complete((kc, mf)),
        onTimeout: () => completer.completeError('timeout'),
        modifierDebounce: shortDebounce,
        timeout: shortTimeout,
      )..start();

      // 模拟用户先按 Cmd，再按 K（两个事件都带 Cmd flag）
      controller.add((cmdL, cmdMods));
      await Future.delayed(const Duration(milliseconds: 20));
      controller.add((keyK, cmdMods));

      final result = await completer.future;
      expect(result.$1, keyK, reason: '应捕获主键 K，不是 Cmd');
      expect(result.$2, cmdMods, reason: '应保留 Cmd modifier flag');
      capturer.cancel();
      await controller.close();
    });

    test('只按修饰键（400ms 内无后续）→ 捕获裸修饰键', () async {
      final controller = StreamController<(int, int)>.broadcast();
      final completer = Completer<(int, int)>();
      final capturer = HotkeyCapturer(
        keyStream: controller.stream,
        onCaptured: (kc, mf) => completer.complete((kc, mf)),
        onTimeout: () => completer.completeError('timeout'),
        modifierDebounce: shortDebounce,
        timeout: shortTimeout,
      )..start();

      controller.add((cmdL, cmdMods));
      // 等待超过 debounce 时间
      final result = await completer.future;
      expect(result.$1, cmdL);
      capturer.cancel();
      await controller.close();
    });

    test('非修饰键（F1）立即捕获，不等 debounce', () async {
      final controller = StreamController<(int, int)>.broadcast();
      final completer = Completer<(int, int)>();
      final capturer = HotkeyCapturer(
        keyStream: controller.stream,
        onCaptured: (kc, mf) => completer.complete((kc, mf)),
        onTimeout: () => completer.completeError('timeout'),
        modifierDebounce: const Duration(milliseconds: 1000), // 长 debounce，如果 F1 走了它会超时
        timeout: shortTimeout,
      )..start();

      controller.add((keyF1, 0));
      final result = await completer.future;
      expect(result, (keyF1, 0));
      capturer.cancel();
      await controller.close();
    });

    test('cancel() 后不再触发回调', () async {
      final controller = StreamController<(int, int)>.broadcast();
      var captured = false;
      final capturer = HotkeyCapturer(
        keyStream: controller.stream,
        onCaptured: (_, _) => captured = true,
        onTimeout: () {},
        modifierDebounce: shortDebounce,
        timeout: shortTimeout,
      )..start();

      capturer.cancel();
      controller.add((keyK, 0));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(captured, isFalse);
      await controller.close();
    });
  });

  group('设置侧 × 运行时 — 跨层一致性', () {
    // 核心契约：如果设置侧说"不冲突"，运行时就不应该让两个热键同时触发
    //          如果设置侧说"冲突"，运行时至少在某个按键组合下会同时触发
    //
    // 验证方法：枚举常见的 modifier 组合，对每一对热键：
    // 1. 看 findHotkeyConflict 是否报冲突
    // 2. 看是否存在一个按键组合 M，使得两个热键在 M 下都匹配
    // 两者必须一致

    const modifierSets = [0, cmd, shift, opt, cmd | shift, cmd | opt, shift | opt, cmd | shift | opt];

    bool runtimeOverlap(HotkeyId a, HotkeyId b) {
      // 枚举所有可能的 current modifier 组合，看是否有一个让两者都匹配
      for (final m in modifierSets) {
        // 两个热键的 keyCode 必须相同（不同 keyCode 不可能同时触发）
        if (a.$1 != b.$1) return false;
        // own-modifier bit 会被剥离，这里模拟 current 包含该 bit 或不包含
        if (CoreEngine.modifiersMatch(a.$1, m, a.$2) &&
            CoreEngine.modifiersMatch(b.$1, m, b.$2)) {
          return true;
        }
      }
      return false;
    }

    test('findHotkeyConflict 与运行时可否同时触发 一致', () {
      // 列出典型配置组合
      final pairs = <(HotkeyId, HotkeyId, String)>[
        // (hotkey A, hotkey B, 期望的冲突说明)
        ((keyK, 0), (keyK, 0), '同裸键'),
        ((keyK, cmd), (keyK, cmd), '完全相同组合键'),
        ((keyK, 0), (keyK, cmd), '裸键 vs 组合键'),
        ((keyK, cmd), (keyK, opt), '不同 modifier 组合键'),
        ((keyK, cmd), (keyK, cmd | shift), '子集关系组合键'),
        ((keyK, cmd), (keyJ, cmd), '不同 keyCode'),
      ];

      for (final (a, b, desc) in pairs) {
        final conflictDetected = findHotkeyConflict({a: 'A'}, b) != null;
        final actuallyOverlaps = runtimeOverlap(a, b);
        expect(conflictDetected, equals(actuallyOverlaps),
            reason: '配置 $desc: 设置侧=${conflictDetected ? "冲突" : "不冲突"}, '
                    '运行时=${actuallyOverlaps ? "有重叠" : "无重叠"}');
      }
    });
  });
}
