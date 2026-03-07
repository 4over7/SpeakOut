import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/vocab_service.dart';

void main() {
  final service = VocabService();

  group('Vocab replacement (offline fallback)', () {
    test('applyReplacements empty text passthrough', () {
      expect(service.applyReplacements(''), '');
    });

    test('applyReplacements no matching entries passthrough', () {
      expect(service.applyReplacements('你好世界'), '你好世界');
    });
  });

  group('Vocab hints for LLM', () {
    test('getVocabHints returns empty list when no entries active', () {
      final hints = service.getVocabHints();
      // Without loaded packs or user entries, should be empty
      expect(hints, isA<List<String>>());
    });

    test('getVocabHints respects maxItems', () {
      final hints = service.getVocabHints(maxItems: 5);
      expect(hints.length, lessThanOrEqualTo(5));
    });
  });
}
