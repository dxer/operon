import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_task_record.dart';
import 'package:operon/models/macro_workflow.dart';

void main() {
  test('task record preserves recorded macro steps', () {
    final record = AgentTaskRecord(
      id: 'r1',
      goal: '完成一次任务',
      status: 'completed',
      startedAt: DateTime(2026, 1, 1, 10),
      endedAt: DateTime(2026, 1, 1, 10, 1),
      steps: 3,
      maxSteps: 10,
      safeMode: true,
      targetUrl: 'https://example.com/post/1',
      recordedMacroSteps: const [
        MacroStep(
          action: 'click',
          selector: '#reply',
          description: '点击回复',
          targetText: '回复',
        ),
        MacroStep(
          action: 'type',
          selector: 'textarea',
          text: '你好',
          description: '输入回复',
        ),
      ],
    );

    final restored = AgentTaskRecord.fromJson(record.toJson());

    expect(restored.recordedMacroSteps.length, 2);
    expect(restored.recordedMacroSteps.first.selector, '#reply');
    expect(restored.recordedMacroSteps.last.text, '你好');
    expect(restored.targetUrl, 'https://example.com/post/1');
  });

  test('old records without macro steps still parse', () {
    final restored = AgentTaskRecord.fromJson({
      'id': 'old',
      'goal': '旧任务',
      'status': 'completed',
      'startedAt': '2026-01-01T10:00:00.000',
      'endedAt': '2026-01-01T10:01:00.000',
      'steps': 1,
      'maxSteps': 5,
      'safeMode': true,
    });

    expect(restored.recordedMacroSteps, isEmpty);
    expect(restored.goal, '旧任务');
  });
}
