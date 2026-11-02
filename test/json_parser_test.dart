import 'package:flutter_test/flutter_test.dart';
import 'package:operon/utils/json_parser.dart';

void main() {
  group('JsonParser.extractJson', () {
    test('parses a plain JSON object', () {
      final result = JsonParser.extractJson(
        '{"thought":"ok","action":"click","params":{"element_id":1}}',
      );
      expect(result, isNotNull);
      expect(result!['action'], 'click');
      expect((result['params'] as Map)['element_id'], 1);
    });

    test('strips markdown fences', () {
      final result = JsonParser.extractJson(
        '```json\n{"action":"finish","params":{"summary":"done"}}\n```',
      );
      expect(result?['action'], 'finish');
    });

    test('recovers JSON surrounded by prose', () {
      final result = JsonParser.extractJson(
        '当然，下一步是：{"action":"scroll","params":{"direction":"down"}} 希望对你有帮助。',
      );
      expect(result?['action'], 'scroll');
    });

    test('returns null for empty or non-JSON text', () {
      expect(JsonParser.extractJson('   '), isNull);
      expect(JsonParser.extractJson('no json here'), isNull);
    });
  });
}
