import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_action.dart';

void main() {
  group('AgentAction', () {
    test('parses press_key and select_option aliases', () {
      final press = AgentAction.fromJson({
        'thought': 'submit',
        'action': 'press_key',
        'params': {'key': 'Enter'},
      });
      expect(press.action, ActionType.pressKey);
      expect(press.key, 'Enter');

      final select = AgentAction.fromJson({
        'thought': 'pick',
        'action': 'select',
        'params': {'element_id': '3', 'value': '最新'},
      });
      expect(select.action, ActionType.selectOption);
      expect(select.elementId, 3);
      expect(select.selectValue, '最新');
    });

    test('round-trips through the JS payload', () {
      final action = AgentAction.fromJson({
        'thought': 'type',
        'action': 'type',
        'params': {'element_id': 7, 'text': 'DeepSeek', 'clear': true},
      });
      final payload = action.toJsPayload();
      expect(payload['action'], 'type');
      expect((payload['params'] as Map)['element_id'], 7);
      expect((payload['params'] as Map)['text'], 'DeepSeek');
      // Unknown params must survive for forward compatibility.
      expect((payload['params'] as Map)['clear'], true);
    });

    test('flags sensitive actions for safe mode', () {
      final publish = AgentAction.fromJson({
        'thought': '发布这条推文',
        'action': 'click',
        'params': {'element_id': 1},
      });
      expect(publish.isSensitive('发布'), isTrue);

      final scroll = AgentAction.fromJson({
        'thought': '继续下滑',
        'action': 'scroll',
        'params': {'direction': 'down'},
      });
      expect(scroll.isSensitive(''), isFalse);
    });
  });
}
