import 'package:flutter/foundation.dart';

/// A goal saved in the history, on its way to the composer.
///
/// The history page lives in settings, the composer lives in the browser page,
/// and the user's intent is "ask this again". Rather than threading a
/// Navigator result through two screens, the browser listens to this. One slot
/// is enough: a second send replaces the first, because a user tapping two
/// rows in a row meant the second one.
class GoalHandoff {
  GoalHandoff._();

  /// The pending goal, and where it was run. Null means nothing is waiting.
  static final ValueNotifier<GoalHandoffRequest?> pending =
      ValueNotifier(null);

  /// Queues a goal for the browser page to pick up.
  static void send({required String goal, String? url}) {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) return;
    final target = url?.trim();
    pending.value = GoalHandoffRequest(
      goal: trimmed,
      url: target == null || target.isEmpty ? null : target,
    );
  }

  /// Takes the pending goal, if any. Taking it clears it: a goal is asked once.
  static GoalHandoffRequest? take() {
    final request = pending.value;
    if (request != null) pending.value = null;
    return request;
  }

  /// Drops anything waiting, for tests and for a page that is going away.
  static void clear() => pending.value = null;
}

class GoalHandoffRequest {
  const GoalHandoffRequest({required this.goal, this.url});

  final String goal;

  /// Where the task ran last time, when it had a page.
  final String? url;
}
