import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/run_coordinator.dart';

void main() {
  test('only one run may be active', () {
    final coordinator = RunCoordinator();

    expect(coordinator.begin(RunKind.agent, 'tab-1'), isNull);
    expect(coordinator.isBusy, isTrue);
    expect(coordinator.activeKind, RunKind.agent);
    expect(coordinator.activeTabId, 'tab-1');

    expect(coordinator.begin(RunKind.skill, 'tab-1'), isNotNull);
    expect(coordinator.begin(RunKind.macro, 'tab-2'), isNotNull);

    coordinator.end(RunKind.agent);
    expect(coordinator.isBusy, isFalse);
    expect(coordinator.begin(RunKind.skill, 'tab-1'), isNull);
  });

  test('ending a different kind does not release the active run', () {
    final coordinator = RunCoordinator()..begin(RunKind.agent, 'tab-1');

    coordinator.end(RunKind.skill);
    expect(coordinator.activeKind, RunKind.agent);

    coordinator.end(RunKind.agent);
    expect(coordinator.activeKind, isNull);
  });

  test('the active tab cannot be closed', () {
    final coordinator = RunCoordinator()..begin(RunKind.macro, 'tab-1');

    expect(coordinator.closeTabRejection('tab-1'), isNotNull);
    expect(coordinator.closeTabRejection('tab-2'), isNull);
  });

  test('a finished run can be restarted', () {
    final coordinator = RunCoordinator()..begin(RunKind.skill, 'tab-1');
    coordinator.end(RunKind.skill);

    expect(coordinator.begin(RunKind.agent, 'tab-1'), isNull);
    expect(coordinator.activeKind, RunKind.agent);
  });
}
