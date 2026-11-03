import '../models/agent_action.dart';

/// Detects the model repeating the same interactive action on an unchanged
/// page.
///
/// The page signature is part of the comparison: clicking "next page" four
/// times in a row is legitimate when each click lands on a new page, but a
/// loop when the page never changes.
class ActionLoopDetector {
  ActionLoopDetector({this.threshold = 4}) : assert(threshold > 0);

  final int threshold;

  String? _lastSignature;
  String? _lastPageSignature;
  int _repeats = 0;

  static const Set<ActionType> _interactive = {
    ActionType.click,
    ActionType.type,
    ActionType.pressKey,
    ActionType.selectOption,
    ActionType.hover,
    ActionType.navigate,
    ActionType.goBack,
  };

  /// Records [action] and returns true once the same action has repeated
  /// [threshold] times on the same page.
  bool record(AgentAction action, {required String pageSignature}) {
    if (!_interactive.contains(action.action)) {
      reset();
      return false;
    }

    final signature = [
      action.action.name,
      action.elementId ?? '',
      action.text ?? '',
      action.url ?? '',
      action.key ?? '',
      action.selectValue ?? '',
    ].join('|');

    if (signature == _lastSignature && pageSignature == _lastPageSignature) {
      _repeats++;
    } else {
      _lastSignature = signature;
      _lastPageSignature = pageSignature;
      _repeats = 1;
    }
    return _repeats >= threshold;
  }

  /// A verified action made real progress; break the current streak.
  void notifyProgress() {
    _repeats = 0;
    _lastSignature = null;
    _lastPageSignature = null;
  }

  void reset() {
    _repeats = 0;
    _lastSignature = null;
    _lastPageSignature = null;
  }
}
