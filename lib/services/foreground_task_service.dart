import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a running agent task protected while Operon is not on screen.
///
/// Android may reclaim a backgrounded process at any time. That would drop the
/// DevTools socket, the page state and any confirmation the user still owes the
/// agent, so a task that is still working runs under a foreground service with
/// a low-importance notification. The notification's pause/resume and stop
/// actions come back through [onAction].
///
/// The native side is deliberately dumb: it shows what Dart tells it and sends
/// taps back. All task state stays in the loop, so the two cannot disagree.
class ForegroundTaskService {
  ForegroundTaskService._();

  static final ForegroundTaskService instance = ForegroundTaskService._();

  /// Exposed so tests can stand in for the Android side.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('operon/agent_task');

  bool _started = false;
  bool _listening = false;
  bool _available = true;
  String? _lastBody;
  bool? _lastPaused;
  bool? _lastCanPause;

  /// Called with `pause`, `resume` or `stop` from the notification.
  void Function(String action)? onAction;

  @visibleForTesting
  void resetForTest() {
    _started = false;
    _listening = false;
    _available = true;
    _lastBody = null;
    _lastPaused = null;
    _lastCanPause = null;
    onAction = null;
  }

  /// Starts listening for notification actions. Safe to call more than once.
  Future<void> init() async {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onTaskAction') return null;
      final action = call.arguments?.toString() ?? '';
      if (action.isEmpty) return null;
      onAction?.call(action);
      return null;
    });
  }

  /// Opens the task notification and makes the service foreground.
  ///
  /// [goal] is what the user asked for, which is more useful in the shade than
  /// a status word: it says which task is running, not just that one is.
  Future<void> start({
    required String goal,
    bool paused = false,
    bool canPause = true,
  }) async {
    final body = _bodyFor(goal.isEmpty ? '正在执行任务' : goal);
    _started = true;
    _record(body, paused, canPause);
    await _invoke('start', {
      'title': _titleFor(paused, canPause),
      'body': body,
      'paused': paused,
      'canPause': canPause,
    });
  }

  /// Replaces the status line. Repeated identical updates are dropped: the loop
  /// emits on every streamed token, and a notification rebuilt per token would
  /// be pure churn.
  Future<void> update({
    required String detail,
    required bool paused,
    bool canPause = true,
  }) async {
    if (!_started) return;
    final body = _bodyFor(detail);
    if (body == _lastBody &&
        paused == _lastPaused &&
        canPause == _lastCanPause) {
      return;
    }
    _record(body, paused, canPause);
    await _invoke('update', {
      'title': _titleFor(paused, canPause),
      'body': body,
      'paused': paused,
      'canPause': canPause,
    });
  }

  /// Removes the notification. A later [update] without a new [start] is
  /// ignored, so a run that just finished cannot resurrect the service.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _lastBody = null;
    _lastPaused = null;
    _lastCanPause = null;
    await _invoke('stop', const {});
  }

  void _record(String body, bool paused, bool canPause) {
    _lastBody = body;
    _lastPaused = paused;
    _lastCanPause = canPause;
  }

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    if (!_available) return;
    try {
      await channel.invokeMethod<bool>(method, args);
    } on MissingPluginException {
      // No Android implementation (desktop, web, tests): showing a task
      // notification is optional, so stop asking for one.
      _available = false;
    } on PlatformException catch (error) {
      // Refused starts are normal on Android 12+ when the app is already in the
      // background. The task itself is unaffected; only the notification is.
      debugPrint('[ForegroundTask] $method failed: ${error.message}');
    }
  }

  static String _titleFor(bool paused, bool canPause) {
    if (paused) return '任务已暂停';
    if (!canPause) return 'Operon 需要你';
    return 'Operon 正在执行';
  }

  static String _bodyFor(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '正在执行任务';
    // One line in the shade; anything longer is noise next to the app icon.
    return compact.length > 80 ? '${compact.substring(0, 79)}…' : compact;
  }
}
