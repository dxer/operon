import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_action.dart';
import 'package:operon/services/action_loop_detector.dart';

AgentAction _click(int id) => AgentAction(
      thought: '点击',
      action: ActionType.click,
      elementId: id,
    );

void main() {
  test('stops on the fourth identical action on the same page', () {
    final detector = ActionLoopDetector();

    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isTrue);
  });

  test('a changed page makes the same action legitimate again', () {
    final detector = ActionLoopDetector();

    for (var page = 0; page < 8; page++) {
      expect(
        detector.record(_click(1), pageSignature: 'page-$page'),
        isFalse,
      );
    }
  });

  test('a different element breaks the streak', () {
    final detector = ActionLoopDetector();

    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(2), pageSignature: 'a');
    expect(detector.record(_click(2), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(2), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(2), pageSignature: 'a'), isTrue);
  });

  test('non-interactive actions reset the streak', () {
    final detector = ActionLoopDetector();

    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    expect(
      detector.record(
        const AgentAction(thought: '', action: ActionType.scroll),
        pageSignature: 'a',
      ),
      isFalse,
    );
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
  });

  test('notifyProgress breaks the streak', () {
    final detector = ActionLoopDetector();

    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.notifyProgress();
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
    expect(detector.record(_click(1), pageSignature: 'a'), isTrue);
  });

  test('reset clears all state', () {
    final detector = ActionLoopDetector();

    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.record(_click(1), pageSignature: 'a');
    detector.reset();
    expect(detector.record(_click(1), pageSignature: 'a'), isFalse);
  });
}
