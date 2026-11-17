// A conversation is what the agent panel shows: a list of turns, each one a
// message from the user and everything the run did in response.
//
// It replaces the old "task record": the same run, but kept where the user can
// read it and continue it, instead of in a settings page nobody opened.
//
// Two things are deliberately *not* stored:
//
// * the raw model transcript (tool results, page snapshots, screenshots). It is
//   what the next turn needs, but re-reading a page costs nothing and storing
//   it costs megabytes per conversation;
// * anything that could be replayed. A stored turn is a record, not a program.

/// One tool call inside a turn, kept as a line the user can read and the next
/// turn can be reminded of.
///
/// A step is written twice: once as an intent, before the call is dispatched,
/// and once as an outcome. That is what makes a killed run readable — the rows
/// below are what actually went out, not what the model meant to do.
class AgentTurnStep {
  const AgentTurnStep({
    required this.tool,
    required this.summary,
    this.status = stepOk,
    this.detail,
    this.callId,
  });

  /// The intent is on disk and the result is not: the app died, or the call
  /// never came back.
  static const String stepStarted = 'started';
  static const String stepOk = 'ok';
  static const String stepFailed = 'failed';
  static const String stepSkipped = 'skipped';

  final String tool;

  /// Human-readable: 「点击「Star」」 rather than `click({"ref":"a3"})`.
  final String summary;

  final String status;

  /// The one line worth keeping: an error message, a new URL.
  final String? detail;

  /// The model's tool-call id, so the outcome lands on the row the intent
  /// opened instead of adding a second one.
  final String? callId;

  bool get ok => status != stepFailed;

  bool get isPending => status == stepStarted;

  AgentTurnStep copyWith({String? status, String? detail}) => AgentTurnStep(
        tool: tool,
        summary: summary,
        status: status ?? this.status,
        detail: detail ?? this.detail,
        callId: callId,
      );

  Map<String, Object?> toJson() => {
        'tool': tool,
        'summary': summary,
        if (status != stepOk) 'status': status,
        if (detail != null) 'detail': detail,
        if (callId != null) 'callId': callId,
      };

  factory AgentTurnStep.fromJson(Map<String, Object?> json) => AgentTurnStep(
        tool: (json['tool'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        // Older files carried `ok` instead of `status`.
        status: (json['status'] ?? '').toString().isNotEmpty
            ? (json['status'] ?? '').toString()
            : (json['ok'] == false ? stepFailed : stepOk),
        detail: json['detail']?.toString(),
        callId: json['callId']?.toString(),
      );
}

/// One user message and the run it triggered.
class AgentTurn {
  const AgentTurn({
    required this.id,
    required this.message,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    this.result,
    this.stopReason,
    this.steps = const [],
    this.attachmentNames = const [],
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.targetUrl,
    this.isCompaction = false,
  });

  final String id;

  /// What the user typed. Never rewritten: it is the history.
  final String message;

  final DateTime startedAt;
  final DateTime endedAt;

  /// `completed` / `partial` / `error` / `stopped`.
  final String status;

  /// A run that started and has not finished yet. Written to disk before the
  /// first action is dispatched, so a process that dies leaves a row instead of
  /// nothing at all.
  bool get isRunning => status == 'running';

  /// A run that never got to write its ending: the app was killed, the tab was
  /// lost, or the phone restarted. It is not a failure of the model, and it is
  /// not a success either — the steps below are as far as it got.
  bool get wasInterrupted => status == 'interrupted';

  /// What the agent said at the end.
  final String? result;

  /// Why it stopped when it did not finish.
  final String? stopReason;

  final List<AgentTurnStep> steps;

  /// File names only. The bytes were the model's to read for one run; keeping
  /// them would mean keeping the user's documents on disk forever.
  final List<String> attachmentNames;

  final int promptTokens;
  final int completionTokens;
  final String? targetUrl;

  /// Marks a synthetic `/compact` / Auto-Compact summary entry so UI shows it as
  /// a compaction marker without re-injecting it into future LLM transcripts.
  final bool isCompaction;

  bool get failed => status == 'error';

  Duration get duration => endedAt.difference(startedAt);

  /// A copy with new ending fields. The steps, message and id stay: they are
  /// what the turn *is*, and the journal already wrote them.
  AgentTurn copyWith({
    String? status,
    String? Function()? result,
    String? Function()? stopReason,
    DateTime? endedAt,
    List<AgentTurnStep>? steps,
    int? promptTokens,
    int? completionTokens,
    String? targetUrl,
  }) =>
      AgentTurn(
        id: id,
        message: message,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        status: status ?? this.status,
        result: result == null ? this.result : result(),
        stopReason: stopReason == null ? this.stopReason : stopReason(),
        steps: steps ?? this.steps,
        attachmentNames: attachmentNames,
        promptTokens: promptTokens ?? this.promptTokens,
        completionTokens: completionTokens ?? this.completionTokens,
        targetUrl: targetUrl ?? this.targetUrl,
        isCompaction: isCompaction,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'message': message,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'status': status,
        if (result != null) 'result': result,
        if (stopReason != null) 'stopReason': stopReason,
        if (steps.isNotEmpty) 'steps': [for (final step in steps) step.toJson()],
        if (attachmentNames.isNotEmpty) 'attachments': attachmentNames,
        if (promptTokens != 0) 'promptTokens': promptTokens,
        if (completionTokens != 0) 'completionTokens': completionTokens,
        if (targetUrl != null) 'targetUrl': targetUrl,
        if (isCompaction) 'isCompaction': true,
      };

  factory AgentTurn.fromJson(Map<String, Object?> json) => AgentTurn(
        id: (json['id'] ?? '').toString(),
        message: (json['message'] ?? '').toString(),
        startedAt:
            DateTime.tryParse((json['startedAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
        endedAt: DateTime.tryParse((json['endedAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: (json['status'] ?? 'completed').toString(),
        result: json['result']?.toString(),
        stopReason: json['stopReason']?.toString(),
        steps: [
          for (final step in (json['steps'] as List?) ?? const [])
            if (step is Map)
              AgentTurnStep.fromJson(step.cast<String, Object?>()),
        ],
        attachmentNames: [
          for (final name in (json['attachments'] as List?) ?? const [])
            name.toString(),
        ],
        promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
        targetUrl: json['targetUrl']?.toString(),
        isCompaction: json['isCompaction'] == true,
      );
}

/// One chat: a title and the turns behind it.
class AgentConversation {
  AgentConversation({
    required this.id,
    this.title = '',
    required this.createdAt,
    required this.updatedAt,
    List<AgentTurn>? turns,
    this.compactedSummary,
    this.compactedTurns = 0,
  }) : turns = turns ?? <AgentTurn>[];

  final String id;

  /// Empty until the first message. Derived titles are stored so a rename
  /// sticks and a deleted first turn does not rename the conversation.
  String title;

  final DateTime createdAt;
  DateTime updatedAt;
  final List<AgentTurn> turns;

  /// Compacted narrative summary covering [turns] prior to [compactedTurns].
  String? compactedSummary;

  /// Index in [turns] from which uncompacted raw turns start.
  int compactedTurns;

  List<AgentTurn> get uncompactedTurns {
    final start = compactedTurns.clamp(0, turns.length);
    return [
      for (var i = start; i < turns.length; i++)
        if (!turns[i].isCompaction) turns[i],
    ];
  }

  bool get hasUncompactedHistory => uncompactedTurns.isNotEmpty;

  /// What the list shows: the name, or the first thing the user said.
  String get displayTitle {
    final named = title.trim();
    if (named.isNotEmpty) return named;
    for (final turn in turns) {
      final text = turn.message.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) {
        return text.length > 24 ? '${text.substring(0, 24)}…' : text;
      }
    }
    return '新对话';
  }

  /// The second line in the list: the last answer, or what it is doing.
  String get preview {
    for (final turn in turns.reversed) {
      final text = (turn.result ?? turn.message).replaceAll(RegExp(r'\s+'), ' ');
      if (text.trim().isNotEmpty) {
        return text.length > 60 ? '${text.substring(0, 60)}…' : text;
      }
    }
    return '还没有消息';
  }

  bool get isEmpty => turns.isEmpty;

  void append(AgentTurn turn) {
    turns.add(turn);
    updatedAt = turn.endedAt;
    if (title.trim().isEmpty) title = displayTitle;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'turns': [for (final turn in turns) turn.toJson()],
        if (compactedSummary != null && compactedSummary!.isNotEmpty)
          'compactedSummary': compactedSummary,
        if (compactedTurns > 0) 'compactedTurns': compactedTurns,
      };

  factory AgentConversation.fromJson(Map<String, Object?> json) =>
      AgentConversation(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
                DateTime.now(),
        turns: [
          for (final turn in (json['turns'] as List?) ?? const [])
            if (turn is Map) AgentTurn.fromJson(turn.cast<String, Object?>()),
        ],
        compactedSummary: json['compactedSummary']?.toString(),
        compactedTurns: (json['compactedTurns'] as num?)?.toInt() ?? 0,
      );
}
