import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/run_budget.dart';

void main() {
  test('free-form runs keep only the step limit', () {
    final budget = RunBudget.fromPolicy(null, fallbackMaxSteps: 7);

    expect(budget.maxSteps, 7);
    for (var i = 0; i < 100; i++) {
      budget.recordSideEffect();
    }
    expect(budget.canContinue(), isTrue);
    expect(budget.canStartSideEffect(), isTrue);
    expect(budget.timedOut, isFalse);
  });

  test('there is no separate model-call cap', () {
    // Each step is at most one model call, so the step limit is the only
    // budget. An instruction skill with many steps must not stop early.
    final budget = RunBudget.fromPolicy(
      const SkillPolicy(maxSteps: 40, maxSideEffects: 3, maxItems: 2),
      fallbackMaxSteps: 5,
    );

    expect(budget.maxSteps, 40);
    expect(budget.canContinue(), isTrue);
    expect(budget.sideEffectLimitReached, isFalse);

    budget.recordSideEffect();
    budget.recordSideEffect();
    expect(budget.itemLimitReached, isTrue);
    expect(budget.sideEffectLimitReached, isFalse);
    budget.recordSideEffect();
    expect(budget.sideEffectLimitReached, isTrue);
    expect(budget.canStartSideEffect(), isFalse);
  });

  test('maxItems of one never triggers the batch limit', () {
    final budget = RunBudget.fromPolicy(
      const SkillPolicy(maxItems: 1, maxSideEffects: 5),
      fallbackMaxSteps: 5,
    );

    budget.recordSideEffect();
    expect(budget.itemLimitReached, isFalse);
  });

  test('paused time is excluded from the duration budget', () {
    var now = DateTime(2024, 1, 1);
    final budget = RunBudget.fromPolicy(
      const SkillPolicy(maxDurationMs: 1000),
      fallbackMaxSteps: 5,
      now: () => now,
    );

    now = now.add(const Duration(milliseconds: 1000));
    expect(budget.timedOut, isFalse);

    budget.pause();
    now = now.add(const Duration(seconds: 30));
    budget.resume();
    expect(budget.timedOut, isFalse);

    now = now.add(const Duration(milliseconds: 1001));
    expect(budget.timedOut, isTrue);
    expect(budget.canContinue(), isFalse);
    expect(budget.canStartSideEffect(), isFalse);
  });

  test('reset clears counters and the clock', () {
    var now = DateTime(2024, 1, 1);
    final budget = RunBudget.fromPolicy(
      const SkillPolicy(maxSideEffects: 1),
      fallbackMaxSteps: 5,
      now: () => now,
    );

    budget.recordSideEffect();
    expect(budget.sideEffectLimitReached, isTrue);

    now = now.add(const Duration(hours: 1));
    budget.reset();
    expect(budget.sideEffects, 0);
    expect(budget.elapsed, Duration.zero);
    expect(budget.canContinue(), isTrue);
    expect(budget.canStartSideEffect(), isTrue);
  });
}
