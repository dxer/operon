/// Loop guards, taken from the same numbers a mature agent uses.
///
/// The point is to catch the three ways a loop wastes a run: the same action
/// again and again, an action that keeps having no effect, and a provider that
/// keeps failing. Each one ends the run with a reason the user can act on,
/// instead of burning the whole turn budget.
class GuardLimits {
  const GuardLimits({
    this.repeatWindow = 6,
    this.repeatLimit = 3,
    this.noEffectNudge = 2,
    this.noEffectStop = 3,
    this.errorStop = 5,
  });

  /// How many recent actions the repeat check looks at.
  final int repeatWindow;

  /// The same signature this many times inside the window stops the run.
  final int repeatLimit;

  /// Consecutive no-effect results that earn a nudge, then a stop.
  final int noEffectNudge;
  final int noEffectStop;

  /// Consecutive failed calls that stop the run.
  final int errorStop;
}

/// Why the loop should stop, in one line the user can read.
class GuardStop {
  const GuardStop(this.reason, this.detail);

  final String reason;
  final String detail;
}

/// A nudge is a line added to the tool result, so the model can change course
/// before the guard has to stop anything.
class GuardNudge {
  const GuardNudge(this.text);

  final String text;
}

/// The state the guards keep across a run, exposed so a resumed run can carry it.
class GuardState {
  GuardState({
    List<String>? recent,
    this.noEffect = 0,
    this.errors = 0,
  }) : recent = recent ?? <String>[];

  final List<String> recent;
  int noEffect;
  int errors;

  GuardState copy() =>
      GuardState(recent: List<String>.of(recent), noEffect: noEffect, errors: errors);

  Map<String, Object?> toJson() => {
        'recent': recent,
        'noEffect': noEffect,
        'errors': errors,
      };

  factory GuardState.fromJson(Map<String, Object?> json) => GuardState(
        recent: (json['recent'] as List?)?.whereType<String>().toList(),
        noEffect: (json['noEffect'] as num?)?.toInt() ?? 0,
        errors: (json['errors'] as num?)?.toInt() ?? 0,
      );
}

/// Checks one call before it is dispatched and records what happened.
class Guards {
  Guards({this.limits = const GuardLimits(), GuardState? state})
      : state = state ?? GuardState();

  final GuardLimits limits;
  final GuardState state;

  /// A signature that says "the same thing again": the tool, its target, and
  /// the text it would send. Volatile arguments are left out on purpose so a
  /// retried scroll or a re-observation does not look like a new action.
  static String signature(String tool, Map<String, Object?> args) {
    final ref = args['ref']?.toString() ?? '';
    final text = args['text']?.toString() ?? '';
    final url = args['url']?.toString() ?? '';
    final key = args['key']?.toString() ?? '';
    final direction = args['direction']?.toString() ?? '';
    final query = args['query']?.toString() ?? '';
    return [tool, ref, text, url, key, direction, query].join('|');
  }

  /// Returns a stop when this action has already been tried to death.
  GuardStop? before(String tool, Map<String, Object?> args) {
    if (tool == 'snapshot' || tool == 'read' || tool == 'find') {
      // Re-reading is how an agent recovers; it must never trip the guard.
      return null;
    }
    final sig = signature(tool, args);
    final window = state.recent.length <= limits.repeatWindow
        ? state.recent
        : state.recent.sublist(state.recent.length - limits.repeatWindow);
    final same = window.where((item) => item == sig).length;
    if (same + 1 >= limits.repeatLimit) {
      return GuardStop(
        '同一操作重复失败',
        '「$tool」用同样的参数已经尝试 $same 次，没有生效。'
            '请换一个元素、先滚动寻找、或换一条路径。',
      );
    }
    if (state.errors >= limits.errorStop) {
      return GuardStop(
        '连续错误过多',
        '连续 ${state.errors} 次工具调用失败，已停止。请检查模型能力或页面状态后重试。',
      );
    }
    return null;
  }

  /// Records an outcome and says whether the model needs a nudge.
  ///
  /// "No effect" is not a failure: the call succeeded and the page did not
  /// change. It is the shape of a dead button, so it gets its own counter.
  GuardNudge? record(String tool, Map<String, Object?> args, ToolResultSummary result) {
    state.recent.add(signature(tool, args));
    if (state.recent.length > limits.repeatWindow * 2) {
      state.recent.removeRange(0, state.recent.length - limits.repeatWindow * 2);
    }

    if (!result.ok) {
      state.errors++;
      state.noEffect = 0;
      return null;
    }
    state.errors = 0;

    final dead = result.mutates && result.pageReacted == false;
    if (!dead) {
      state.noEffect = 0;
      return null;
    }
    state.noEffect++;
    if (state.noEffect >= limits.noEffectStop) {
      return const GuardNudge(
        '这一步已经连续多次没有让页面发生任何变化，继续原样重试没有意义。'
        '请先 snapshot 确认页面现状，再换一个元素或换一条路径；如果目标已达成，用 done 结束。',
      );
    }
    if (state.noEffect >= limits.noEffectNudge) {
      return const GuardNudge('页面没有变化。不要原样重试，先重新观察。');
    }
    return null;
  }

  /// True when the no-effect counter has reached the point of stopping.
  bool get noEffectExhausted => state.noEffect >= limits.noEffectStop;
}

/// The few fields of a tool result the guards need, so guards do not depend on
/// the layer's result type.
class ToolResultSummary {
  const ToolResultSummary({
    required this.ok,
    required this.mutates,
    this.pageReacted,
  });

  final bool ok;
  final bool mutates;
  final bool? pageReacted;

  factory ToolResultSummary.of(bool ok, bool mutates, {bool? pageReacted}) =>
      ToolResultSummary(ok: ok, mutates: mutates, pageReacted: pageReacted);
}
