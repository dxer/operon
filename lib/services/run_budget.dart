import '../models/skill.dart';

enum RunLimit { steps, llmCalls, sideEffects, duration }

/// Tracks the per-run limits declared by [SkillPolicy].
///
/// Free-form agent tasks have no policy and only keep the step limit, so the
/// existing behaviour is preserved. Time spent waiting for the user (CAPTCHA,
/// confirmation, manual pause) is excluded from the duration budget.
class RunBudget {
  RunBudget({
    required this.maxSteps,
    this.maxLlmCalls,
    this.maxSideEffects,
    this.maxItems = 1,
    this.maxDuration,
    DateTime Function()? now,
    DateTime? startedAt,
  })  : _now = now ?? DateTime.now,
        _startedAt = startedAt ?? (now ?? DateTime.now)();

  factory RunBudget.fromPolicy(
    SkillPolicy? policy, {
    required int fallbackMaxSteps,
    DateTime Function()? now,
    DateTime? startedAt,
  }) {
    if (policy == null) {
      return RunBudget(
        maxSteps: fallbackMaxSteps,
        now: now,
        startedAt: startedAt,
      );
    }
    return RunBudget(
      maxSteps: policy.maxSteps,
      maxLlmCalls: policy.maxLlmCalls,
      maxSideEffects: policy.maxSideEffects,
      maxItems: policy.maxItems,
      maxDuration: Duration(milliseconds: policy.maxDurationMs),
      now: now,
      startedAt: startedAt,
    );
  }

  final int maxSteps;
  final int? maxLlmCalls;
  final int? maxSideEffects;
  final int maxItems;
  final Duration? maxDuration;

  final DateTime Function() _now;
  DateTime _startedAt;
  int _llmCalls = 0;
  int _sideEffects = 0;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;

  int get llmCalls => _llmCalls;
  int get sideEffects => _sideEffects;

  /// Active wall-clock time, excluding paused intervals.
  Duration get elapsed {
    var total = _now().difference(_startedAt);
    final pausedAt = _pausedAt;
    if (pausedAt != null) total -= _now().difference(pausedAt);
    total -= _pausedTotal;
    return total < Duration.zero ? Duration.zero : total;
  }

  bool get timedOut => maxDuration != null && elapsed > maxDuration!;

  bool get llmLimitReached => maxLlmCalls != null && _llmCalls >= maxLlmCalls!;

  bool get sideEffectLimitReached =>
      maxSideEffects != null && _sideEffects >= maxSideEffects!;

  /// Existing batch behaviour: a limit of 1 means single-item, not a cap.
  bool get itemLimitReached => maxItems > 1 && _sideEffects >= maxItems;

  bool canCallLlm() => !timedOut && !llmLimitReached;

  bool canStartSideEffect() => !timedOut && !sideEffectLimitReached;

  void recordLlmCall() => _llmCalls++;

  void recordSideEffect() => _sideEffects++;

  /// Starts a human-wait/pause interval. Repeated calls are ignored.
  void pause() {
    _pausedAt ??= _now();
  }

  /// Ends a pause interval; unmatched calls are ignored.
  void resume() {
    final started = _pausedAt;
    if (started == null) return;
    _pausedTotal += _now().difference(started);
    _pausedAt = null;
  }

  void reset() {
    _startedAt = _now();
    _llmCalls = 0;
    _sideEffects = 0;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
  }
}
