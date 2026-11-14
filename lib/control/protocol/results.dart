import 'errors.dart';

/// Whether an input event reached the page.
///
/// Kept apart from "did the page react" on purpose: an event can be delivered
/// and do nothing (wrong target, framework ignored it), and the two facts lead
/// the caller to different next steps.
enum Delivery { delivered, notDelivered, unknown }

/// What the layer observed around one action.
///
/// The three outcomes are reported separately, never folded into a boolean:
/// input was dispatched, the page reacted, the expected state was reached.
class Receipt {
  Receipt({
    required this.tool,
    required this.delivery,
    this.pageReacted,
    this.expectedStateReached,
    this.changes = const [],
    this.urlBefore,
    this.urlAfter,
    this.elapsed,
    this.note,
    this.details,
  });

  final String tool;
  final Delivery delivery;

  /// True when the outline or the URL differed afterwards.
  final bool? pageReacted;

  /// True when the caller's expectation held after the action.
  final bool? expectedStateReached;

  /// Lines added or removed by the action, `+` and `-` prefixed.
  final List<String> changes;

  final String? urlBefore;
  final String? urlAfter;
  final Duration? elapsed;

  /// Something the caller needs to know that is not a failure, such as a
  /// shortened wait or a partially captured document.
  final String? note;

  final Map<String, Object?>? details;

  /// One line for a log or a step card, in the caller's words.
  String get summary {
    final parts = <String>[
      switch (delivery) {
        Delivery.delivered => '已派发',
        Delivery.notDelivered => '未派发',
        Delivery.unknown => '派发状态未知',
      },
      if (pageReacted == true) '页面有反应' else if (pageReacted == false) '页面无变化',
      if (expectedStateReached == true) '达到预期' else if (expectedStateReached == false) '未达预期',
      if (urlBefore != null && urlAfter != null && urlBefore != urlAfter) 'URL 已变',
      if (elapsed != null) '${elapsed!.inMilliseconds}ms',
    ];
    return parts.join(' · ');
  }

  Map<String, Object?> toJson() => {
        'tool': tool,
        'delivery': delivery.name,
        if (pageReacted != null) 'pageReacted': pageReacted,
        if (expectedStateReached != null) 'expectedStateReached': expectedStateReached,
        if (changes.isNotEmpty) 'changes': changes,
        if (urlBefore != null) 'urlBefore': urlBefore,
        if (urlAfter != null) 'urlAfter': urlAfter,
        if (elapsed != null) 'elapsedMs': elapsed!.inMilliseconds,
        if (note != null) 'note': note,
        if (details != null) 'details': details,
      };
}

/// The outcome of one tool call.
class ToolResult {
  const ToolResult({
    required this.ok,
    this.data,
    this.receipt,
    this.error,
    this.text,
  });

  factory ToolResult.failure(ControlException error) =>
      ToolResult(ok: false, error: error);

  final bool ok;
  final Map<String, Object?>? data;
  final Receipt? receipt;
  final ControlException? error;

  /// What the model reads, when the caller asked for a rendered result.
  final String? text;

  Map<String, Object?> toJson() => {
        'ok': ok,
        if (text != null) 'text': text,
        if (data != null) 'data': data,
        if (receipt != null) 'receipt': receipt!.toJson(),
        if (error != null) 'error': error!.toJson(),
      };
}

/// One line of the outline, with the ref the caller addresses it by.
class OutlineLine {
  const OutlineLine({
    required this.ref,
    required this.role,
    required this.name,
    this.value,
    this.states = const [],
    this.depth = 0,
    this.backendNodeId,
    this.frameId,
  });

  final String ref;
  final String role;
  final String name;
  final String? value;
  final List<String> states;
  final int depth;
  final int? backendNodeId;
  final String? frameId;

  /// `[a3] button "登录" disabled`
  String render() {
    final buffer = StringBuffer('  ' * depth)
      ..write('[$ref] ')
      ..write(role);
    if (name.isNotEmpty) buffer.write(' "${_trim(name)}"');
    if (value != null && value!.isNotEmpty) buffer.write(' = "${_trim(value!)}"');
    for (final state in states) {
      buffer.write(' $state');
    }
    return buffer.toString();
  }

  static String _trim(String text) =>
      text.length <= 80 ? text : '${text.substring(0, 79)}…';
}
