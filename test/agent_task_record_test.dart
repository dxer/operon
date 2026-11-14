import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_task_record.dart';

void main() {
  test('a task record round-trips through json', () {
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
      logs: const ['步骤 1: 点击回复'],
      sensitiveActions: const ['发布回复'],
    );

    final restored = AgentTaskRecord.fromJson(record.toJson());

    expect(restored.goal, '完成一次任务');
    expect(restored.targetUrl, 'https://example.com/post/1');
    expect(restored.logs, hasLength(1));
    expect(restored.sensitiveActions, hasLength(1));
    expect(restored.hasSensitiveActions, isTrue);
  });

  test('a record written before the change still parses', () {
    final restored = AgentTaskRecord.fromJson({
      'id': 'old',
      'goal': '旧任务',
      'status': 'completed',
      'startedAt': '2026-01-01T10:00:00.000',
      'endedAt': '2026-01-01T10:01:00.000',
      'steps': 1,
      'maxSteps': 5,
      'safeMode': true,
      // A field the old build wrote; unknown keys must not break a read.
      'recordedMacroSteps': [
        {'action': 'click', 'selector': '#reply'},
      ],
    });

    expect(restored.goal, '旧任务');
    expect(restored.safeMode, isTrue);
  });
}
