/// Contract returned by every executed browser action.
///
/// `success == true` only means the DOM executor dispatched the action. The
/// verification fields are filled in on the next observation and describe
/// whether the page actually reacted.
enum ActionResultVerification {
  /// Waiting for the next DOM snapshot.
  pending,

  /// Page or URL changed as expected.
  verified,

  /// Executed successfully, but nothing observable changed.
  noEffect,

  /// The executor rejected the action before it had any side effect.
  failed,
}

class AgentActionResult {
  final bool success;
  final String? error;
  final String? message;
  final String? targetText;
  final bool atBoundary;
  final int? remaining;
  final bool sideEffect;
  final bool? pageChanged;
  final bool? urlChanged;
  final ActionResultVerification verification;
  final String? verificationNote;

  const AgentActionResult({
    required this.success,
    this.error,
    this.message,
    this.targetText,
    this.atBoundary = false,
    this.remaining,
    this.sideEffect = false,
    this.pageChanged,
    this.urlChanged,
    this.verification = ActionResultVerification.pending,
    this.verificationNote,
  });

  factory AgentActionResult.fromMap(Map<String, dynamic> map) {
    return AgentActionResult(
      success: map['success'] == true,
      error: map['error']?.toString(),
      message: map['message']?.toString(),
      targetText: map['targetText']?.toString(),
      atBoundary: map['atBoundary'] == true,
      remaining:
          map['remaining'] is num ? (map['remaining'] as num).toInt() : null,
      verification: map['success'] == true
          ? ActionResultVerification.pending
          : ActionResultVerification.failed,
    );
  }

  AgentActionResult copyWith({
    bool? success,
    String? error,
    String? message,
    String? targetText,
    bool? atBoundary,
    int? remaining,
    bool? sideEffect,
    bool? pageChanged,
    bool? urlChanged,
    ActionResultVerification? verification,
    String? verificationNote,
  }) {
    return AgentActionResult(
      success: success ?? this.success,
      error: error ?? this.error,
      message: message ?? this.message,
      targetText: targetText ?? this.targetText,
      atBoundary: atBoundary ?? this.atBoundary,
      remaining: remaining ?? this.remaining,
      sideEffect: sideEffect ?? this.sideEffect,
      pageChanged: pageChanged ?? this.pageChanged,
      urlChanged: urlChanged ?? this.urlChanged,
      verification: verification ?? this.verification,
      verificationNote: verificationNote ?? this.verificationNote,
    );
  }

  /// Compact human-readable result for the execution log.
  String describe() {
    if (!success) {
      return '失败：${error ?? '未知原因'}';
    }
    switch (verification) {
      case ActionResultVerification.pending:
        return '已执行，等待页面反馈';
      case ActionResultVerification.verified:
        final changes = <String>[
          if (pageChanged == true) '页面已变化',
          if (urlChanged == true) 'URL 已变化',
        ];
        return changes.isEmpty ? '已执行并确认' : '已执行 · ${changes.join(' · ')}';
      case ActionResultVerification.noEffect:
        return sideEffect ? '已执行，但没有观察到页面变化；提交结果未确认，已禁止重复提交' : '已执行，但页面没有变化';
      case ActionResultVerification.failed:
        return '失败：${error ?? '未知原因'}';
    }
  }
}
