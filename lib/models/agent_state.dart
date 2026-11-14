enum AgentStatus {
  idle,
  observing,
  thinking,
  executing,
  waitingConfirmation,
  waitingCaptcha,
  paused,
  completed,
  maxStepsReached,
  error,
}

/// What a timeline entry is, so the panel can render one line for each kind.
enum LogKind {
  /// The model's own reasoning. Same timeline as the actions: reading them apart
  /// is what made the old panel hard to follow.
  thought,

  /// One tool call: the row a step card grows from.
  action,

  /// Something the loop says about itself — context trimming, a nudge, a wait.
  note,

  /// How the run ended.
  result,
  error,
}

/// What one action did to the page, in the terms a step card shows.
///
/// Built from the control layer's receipt. The three outcomes stay apart on
/// purpose: "点到了", "页面动了" and "做成了" are three different answers, and a
/// card that folds them into one boolean hides the failure that matters.
class StepEvidence {
  const StepEvidence({
    this.delivery,
    this.pageReacted,
    this.expectedStateReached,
    this.changes = const [],
    this.urlBefore,
    this.urlAfter,
    this.note,
    this.elapsedMs,
    this.image,
  });

  /// Reads the receipt the control layer already serialised.
  factory StepEvidence.fromReceipt(
    Map<String, Object?> receipt, {
    String? image,
  }) {
    List<String> lines(Object? raw) =>
        raw is List ? raw.whereType<String>().toList(growable: false) : const [];
    return StepEvidence(
      delivery: receipt['delivery'] as String?,
      pageReacted: receipt['pageReacted'] as bool?,
      expectedStateReached: receipt['expectedStateReached'] as bool?,
      changes: lines(receipt['changes']),
      urlBefore: receipt['urlBefore'] as String?,
      urlAfter: receipt['urlAfter'] as String?,
      note: receipt['note'] as String?,
      elapsedMs: receipt['elapsedMs'] as int?,
      image: image,
    );
  }

  static const StepEvidence none = StepEvidence();

  /// `delivered`, `notDelivered` or `unknown`.
  final String? delivery;
  final bool? pageReacted;
  final bool? expectedStateReached;

  /// Lines the action added or removed, `+` and `-` prefixed.
  final List<String> changes;

  final String? urlBefore;
  final String? urlAfter;

  /// Not a failure, but something the user should see: a shortened wait, a
  /// partially captured document.
  final String? note;
  final int? elapsedMs;

  /// Base64 PNG of the page right after the action, when the step captured one.
  final String? image;

  bool get isEmpty =>
      delivery == null &&
      pageReacted == null &&
      expectedStateReached == null &&
      changes.isEmpty &&
      note == null &&
      image == null;

  bool get urlChanged =>
      urlBefore != null && urlAfter != null && urlBefore != urlAfter;

  String? get deliveryLabel => switch (delivery) {
        'delivered' => '已派发',
        'notDelivered' => '未派发',
        'unknown' => '派发未知',
        _ => null,
      };

  String? get reactionLabel => pageReacted == null
      ? null
      : (pageReacted! ? '页面有反应' : '页面无变化');

  String? get expectationLabel => expectedStateReached == null
      ? null
      : (expectedStateReached! ? '达到预期' : '未达预期');

  /// One line of chips: "已派发 · 页面有反应 · 达到预期 · 320ms".
  String get summary => <String?>[
        deliveryLabel,
        reactionLabel,
        expectationLabel,
        if (elapsedMs != null) '${elapsedMs}ms',
      ].whereType<String>().join(' · ');
}

class AgentLogItem {
  final DateTime timestamp;
  final int step;
  final String title;
  final String? detail;
  final bool isError;
  final LogKind kind;
  final StepEvidence? evidence;

  AgentLogItem({
    required this.step,
    required this.title,
    this.detail,
    this.isError = false,
    this.kind = LogKind.note,
    this.evidence,
    DateTime? at,
  }) : timestamp = at ?? DateTime.now();

  /// The same row with its outcome filled in, keeping its original time.
  ///
  /// The card appears when the action starts and is completed when the page
  /// answers, so one call stays one row. A failure keeps the action's own words
  /// and only changes the badge: the old panel appended a second, differently
  /// worded row that the user had to pair up by hand.
  AgentLogItem completeWith({
    required bool failed,
    StepEvidence? evidence,
    String? detail,
  }) =>
      AgentLogItem(
        step: step,
        title: title,
        detail: failed ? (detail ?? this.detail) : this.detail,
        isError: failed || isError,
        kind: failed ? LogKind.error : kind,
        evidence: evidence ?? this.evidence,
        at: timestamp,
      );

  /// A copy with one field changed, for the places that only need a tweak.
  AgentLogItem copyWith({
    StepEvidence? evidence,
    bool? isError,
    String? detail,
    LogKind? kind,
  }) =>
      AgentLogItem(
        step: step,
        title: title,
        detail: detail ?? this.detail,
        isError: isError ?? this.isError,
        kind: kind ?? this.kind,
        evidence: evidence ?? this.evidence,
        at: timestamp,
      );
}

class AgentState {
  final AgentStatus status;
  final String goal;
  final int currentStep;
  final int maxSteps;
  final String currentThought;
  final dynamic extractedData; // Structured data scraped from the web
  final String? captchaType; // Name of detected CAPTCHA challenge
  final String? errorMessage;
  final String? confirmationReason; // Why the action needs authorization
  final String? targetUrl; // Page URL where the pending action will run
  final String? confirmationPayload; // Exact text/url that will be sent
  final List<AgentLogItem> logs;

  const AgentState({
    this.status = AgentStatus.idle,
    this.goal = '',
    this.currentStep = 0,
    this.maxSteps = 15,
    this.currentThought = '',
    this.extractedData,
    this.captchaType,
    this.errorMessage,
    this.confirmationReason,
    this.targetUrl,
    this.confirmationPayload,
    this.logs = const [],
  });

  bool get isRunning =>
      status == AgentStatus.observing ||
      status == AgentStatus.thinking ||
      status == AgentStatus.executing ||
      status == AgentStatus.waitingConfirmation ||
      status == AgentStatus.waitingCaptcha;

  AgentState copyWith({
    AgentStatus? status,
    String? goal,
    int? currentStep,
    int? maxSteps,
    String? currentThought,
    dynamic extractedData,
    String? captchaType,
    String? errorMessage,
    String? confirmationReason,
    String? targetUrl,
    String? confirmationPayload,
    List<AgentLogItem>? logs,
    bool clearCaptchaType = false,
    bool clearErrorMessage = false,
    bool clearExtractedData = false,
    bool clearConfirmationContext = false,
  }) {
    return AgentState(
      status: status ?? this.status,
      goal: goal ?? this.goal,
      currentStep: currentStep ?? this.currentStep,
      maxSteps: maxSteps ?? this.maxSteps,
      currentThought: currentThought ?? this.currentThought,
      extractedData:
          clearExtractedData ? null : (extractedData ?? this.extractedData),
      captchaType: clearCaptchaType ? null : (captchaType ?? this.captchaType),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      confirmationReason: clearConfirmationContext
          ? null
          : (confirmationReason ?? this.confirmationReason),
      targetUrl:
          clearConfirmationContext ? null : (targetUrl ?? this.targetUrl),
      confirmationPayload: clearConfirmationContext
          ? null
          : (confirmationPayload ?? this.confirmationPayload),
      logs: logs ?? this.logs,
    );
  }
}
