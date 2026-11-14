import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/run_coordinator.dart';

void main() {
  test('only one run may be active', () {
    final coordinator = RunCoordinator();

    expect(coordinator.begin(RunKind.agent, 'tab-1'), isNull);
    expect(coordinator.isBusy, isTrue);
    expect(coordinator.activeKind, RunKind.agent);
    expect(coordinator.activeTabId, 'tab-1');

    // A second start on the same tab, or on another one, is refused.
    expect(coordinator.begin(RunKind.agent, 'tab-1'), isNotNull);
    expect(coordinator.begin(RunKind.agent, 'tab-2'), isNotNull);

    coordinator.end(RunKind.agent);
    expect(coordinator.isBusy, isFalse);
    expect(coordinator.begin(RunKind.agent, 'tab-1'), isNull);
  });

  test('ending a run that is not active is ignored', () {
    final coordinator = RunCoordinator();

    // Nothing is active, so there is nothing to end.
    coordinator.end(RunKind.agent);
    expect(coordinator.isBusy, isFalse);

    coordinator.begin(RunKind.agent, 'tab-1');
    coordinator.end(RunKind.agent);
    expect(coordinator.activeKind, isNull);
  });

  test('the active tab cannot be closed', () {
    final coordinator = RunCoordinator()..begin(RunKind.agent, 'tab-1');

    expect(coordinator.closeTabRejection('tab-1'), isNotNull);
    expect(coordinator.closeTabRejection('tab-2'), isNull);
  });

  test('an idle coordinator lets any tab close', () {
    final coordinator = RunCoordinator();
    expect(coordinator.closeTabRejection('tab-1'), isNull);
  });
}
