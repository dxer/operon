import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill_run.dart';

void main() {
  test('run record JSON round-trip', () {
    final record = SkillRunRecord(
      id: 'run1',
      skillId: 'skill1',
      skillName: '测试技能',
      status: SkillRunStatus.completed,
      inputs: const {'count': '3'},
      steps: [
        SkillStepResult(
          stepId: 'read',
          name: '读取',
          tool: 'page.read_region',
          status: SkillStepStatus.succeeded,
          data: const {'items': ['a', 'b']},
          durationMs: 120,
          startedAt: DateTime(2026, 1, 1, 10),
          endedAt: DateTime(2026, 1, 1, 10, 0, 1),
        ),
      ],
      output: const {'summary': 'ok'},
      url: 'https://example.com',
      startedAt: DateTime(2026, 1, 1, 10),
      endedAt: DateTime(2026, 1, 1, 10, 0, 2),
      llmCalls: 1,
      sideEffects: 0,
    );

    final restored = SkillRunRecord.fromJson(record.toJson());

    expect(restored.id, 'run1');
    expect(restored.status, SkillRunStatus.completed);
    expect(restored.inputs['count'], '3');
    expect(restored.steps.single.status, SkillStepStatus.succeeded);
    expect(restored.steps.single.durationMs, 120);
    expect(restored.output['summary'], 'ok');
    expect(restored.llmCalls, 1);
  });

  test('run state reports running and terminal states', () {
    const state = SkillRunState(
      runId: 'r',
      skillId: 's',
      skillName: 'S',
      status: SkillRunStatus.running,
      currentStep: 1,
      totalSteps: 3,
    );

    expect(state.isRunning, isTrue);
    expect(
      state.copyWith(status: SkillRunStatus.completed).isRunning,
      isFalse,
    );
  });
}
