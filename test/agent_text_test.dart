import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_action.dart';
import 'package:operon/utils/agent_text.dart';

void main() {
  test('typing is described without repeating the payload', () {
    const action = AgentAction(
      thought: 'reply',
      action: ActionType.type,
      elementId: 7,
      text: '支持！祝你早日突破百万粉丝',
    );
    final label = agentActionLabel(action);
    expect(label, '在 [7] 输入内容');
    expect(label.contains('支持'), isFalse);
  });

  test('other actions fall back to the model description', () {
    expect(
      agentActionLabel(const AgentAction(
        thought: 'submit',
        action: ActionType.click,
        elementId: 2,
      )),
      '点击元素 [2]',
    );
    expect(agentActionLabel(null), '');
  });
}
