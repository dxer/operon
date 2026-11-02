import 'dart:async';

/// Cancellation signal for a single agent task.
///
/// The runner owns one token per task and cancels it when the user presses
/// stop, so an in-flight model request is aborted instead of burning tokens
/// for another 45 seconds.
class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when [cancel] is called. Never completes with an error.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
