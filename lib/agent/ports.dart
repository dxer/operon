import '../control/perception/captcha.dart';
import '../control/protocol/results.dart';

/// One tool call the model asked for.
class ToolCallRequest {
  const ToolCallRequest({
    required this.id,
    required this.name,
    this.args = const {},
    this.rawArguments = '',
  });

  final String id;
  final String name;
  final Map<String, Object?> args;

  /// The arguments exactly as the model wrote them, kept for an error message.
  final String rawArguments;

  @override
  String toString() => 'ToolCallRequest($name, $args)';
}

/// One model reply: text, the calls it asked for, and what it cost.
class LlmTurn {
  const LlmTurn({
    this.content,
    this.calls = const [],
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });

  final String? content;
  final List<ToolCallRequest> calls;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;

  int get totalTokens => (promptTokens ?? 0) + (completionTokens ?? 0);

  /// The provider cut the reply off, so nothing in it can be trusted.
  bool get truncated => finishReason == 'length';
}

/// The model, as the loop needs it.
///
/// A port rather than the concrete client: the loop must be testable without a
/// network, and swapping the transport must not touch the policy code.
abstract class LlmPort {
  Future<LlmTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  });
}

/// One thing the loop can do to the page.
abstract class ControlPort {
  Future<ToolResult> execute(String tool, [Map<String, Object?> args]);

  /// What the last capture saw of a human-verification challenge.
  CaptchaInfo? get captcha;

  /// The outline line of a ref (`button "发送"`), when the layer still knows it.
  ///
  /// The confirmation decision depends on what a click will do, and the label is
  /// the only evidence available for that.
  String? refLabel(String? ref);

  /// Notified before an input is dispatched, with the point it lands on.
  set onGesture(void Function(double x, double y, String label)? value);
}

/// A question only a person may answer.
class ConfirmRequest {
  const ConfirmRequest({
    required this.title,
    required this.reason,
    this.payload,
    this.destructive = false,
  });

  final String title;
  final String reason;

  /// What would be sent or chosen, shown to the user verbatim.
  final String? payload;

  /// True for payments, deletions and credential entry: those always ask.
  final bool destructive;
}

/// A step only a person can take: solving a challenge, or answering a question
/// the agent cannot answer from the page.
class PersonRequest {
  const PersonRequest({
    required this.kind,
    required this.title,
    this.detail,
  });

  /// `captcha` or `question`.
  final String kind;
  final String title;
  final String? detail;

  bool get isCaptcha => kind == 'captcha';
}

/// The human side of a run: confirmations, hand-offs and the log the user reads.
abstract class HostPort {
  /// Asks the user. Returns false when they decline.
  Future<bool> confirm(ConfirmRequest request);

  /// Hands a step to the user and waits for them.
  ///
  /// Returns their answer for a question, `ok` once a challenge is solved, or
  /// null when they cancelled. The loop never answers either of these itself.
  Future<String?> askPerson(PersonRequest request);

  /// Reports an event the user should see, without stopping the run.
  void note(String title, {String? detail, bool isError = false});
}
