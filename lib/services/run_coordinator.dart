enum RunKind { agent, skill, macro }

/// Single-flight guard for everything that drives the WebView.
///
/// The UI hides most entry points while a run is active, but macros, the skills
/// page and tab switching/closure can bypass that. This is the authoritative
/// check so two runners never share one page.
class RunCoordinator {
  RunKind? _activeKind;
  String? _activeTabId;

  RunKind? get activeKind => _activeKind;
  String? get activeTabId => _activeTabId;
  bool get isBusy => _activeKind != null;

  /// Returns null on success, or a user-facing rejection reason.
  String? begin(RunKind kind, String tabId) {
    final active = _activeKind;
    if (active != null) {
      return '${_label(active)}正在运行，请先停止后再开始新的任务';
    }
    _activeKind = kind;
    _activeTabId = tabId;
    return null;
  }

  /// Ends the run only when [kind] is the active one.
  void end(RunKind kind) {
    if (_activeKind != kind) return;
    _activeKind = null;
    _activeTabId = null;
  }

  /// Returns null when the tab may close.
  String? closeTabRejection(String tabId) {
    final active = _activeKind;
    if (active != null && _activeTabId == tabId) {
      return '${_label(active)}正在这个标签页上运行，请先停止任务再关闭';
    }
    return null;
  }

  static String _label(RunKind kind) {
    switch (kind) {
      case RunKind.agent:
        return 'AI 任务';
      case RunKind.skill:
        return '技能任务';
      case RunKind.macro:
        return '宏任务';
    }
  }
}
