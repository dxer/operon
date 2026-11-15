import 'dart:async';
import 'dart:convert';

import '../control/control.dart';
import '../control/tab_host.dart';
import '../control/transport/endpoint.dart' show SocketConnector;
import '../control/perception/captcha.dart';
import '../control/protocol/errors.dart';
import '../control/protocol/gesture.dart';
import '../control/protocol/results.dart';
import '../models/agent_attachment.dart';
import '../models/agent_conversation.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/model_profile.dart';
import '../services/llm_service.dart';
import '../services/llm_tools.dart';
import '../services/notification_service.dart';
import '../utils/cancellation.dart';
import 'compactor.dart';
import 'context.dart';
import 'loop.dart';
import 'ports.dart';
import 'prompt.dart';
import 'tools.dart';
import 'transcript.dart';

/// Runs the new agent loop and reports it in the shape the panel already reads.
///
/// The loop knows nothing about `AgentState`, notifications or the panel: this
/// class is the seam. That keeps the loop testable with fakes and keeps the UI
/// free of loop details.
class AgentLoopRunner {
  AgentLoopRunner({NotificationService? notifications})
      : _notifications = notifications ?? NotificationService.getInstance();

  final NotificationService _notifications;
  final StreamController<AgentState> _states = StreamController<AgentState>.broadcast();
  CancellationToken _token = CancellationToken();

  AgentState _state = const AgentState();
  List<AgentLogItem> _logs = [];

  /// Tool call id → the timeline row it opened, so the outcome lands on the row
  /// the action started rather than on a new one.
  final Map<String, int> _openCards = {};
  Control? _control;
  Completer<bool>? _pendingConfirm;
  Completer<String?>? _pendingPerson;
  Completer<void>? _resumeGate;
  bool _paused = false;
  bool _stopped = false;
  bool _notifyOnComplete = true;
  bool _attached = false;

  /// Notified before an input is dispatched, with the point and box it lands
  /// on.
  void Function(GestureTarget target)? onGesture;

  /// Asks the user a question the agent cannot answer from the page.
  ///
  /// The panel supplies this; without it a question simply ends the run, which
  /// is better than an agent guessing an answer.
  Future<String?> Function(String question)? onAsk;

  /// Picks local device files when an `upload` tool call omits `files`.
  Future<List<String>?> Function()? onPickFiles;

  /// The app's tab strip. Set by the page that owns it; without it the layer
  /// can switch its own target but not what the user sees.
  TabHost? tabHost;

  /// The control layer is up: the run is using real input, not page script.
  bool get usesControlLayer => _attached;

  Stream<AgentState> get stateStream => _states.stream;

  AgentState get state => _state;

  Future<void> run({
    required String goal,
    required String? urlHint,
    required LlmConfig config,
    bool safeMode = true,
    bool Function(String host)? isSiteAllowed,
    bool Function(String host)? isSiteBlocked,
    String? extraSystemRules,
    bool notifyOnComplete = true,
    bool vision = false,
    ModelProfile profile = const ModelProfile.fallback(),
    bool autoCompact = true,
    int autoCompactTokens = 200000,
    List<AgentAttachment> attachments = const [],
    List<AgentTurn> priorTurns = const [],
    String? compactedSummary,
    int compactedTurns = 0,
    SocketConnector? controlConnect,
  }) async {
    _stopped = false;
    _paused = false;
    // Fresh token per run so cancelling an earlier task never aborts the next.
    _token = CancellationToken();
    _notifyOnComplete = notifyOnComplete;
    _logs = [];
    _openCards.clear();
    _state = AgentState(
      status: AgentStatus.observing,
      goal: goal,
      targetUrl: urlHint,
      logs: const [],
    );
    _emit();

    _log('启动任务', detail: '目标: $goal');

    // Checked before attaching and before any call is paid for. A model that
    // cannot call tools cannot run a task, and the settings wording is the fix.
    if (!profile.supportsTools) {
      const message = '这个模型在设置里被标记为不支持工具调用，智能体无法使用它。'
          '如果它其实支持 function calling，请在 设置 → AI 智能体引擎 → 模型能力 里打开。';
      _fail(message);
      throw StateError(message);
    }

    // Attach first: if the control layer is unavailable, this throws before a
    // single model call is paid for.
    try {
      _control = await Control.attach(
        urlHint: urlHint,
        connect: controlConnect,
        tabHost: tabHost,
      );
      _control!.onGesture = (target) => onGesture?.call(target);
      _attached = true;
      final notes = _control!.notes;
      if (notes.isNotEmpty) {
        for (final note in notes) {
          _log('控制层提示', detail: note);
        }
      }
    } on ControlException catch (error) {
      _fail('控制层不可用：${error.message}${error.hint == null ? '' : '（${error.hint}）'}');
      rethrow;
    }

    // One answer for the whole run: whether images can be sent at all. It
    // decides the screenshot tool, the attachment message, and what the user is
    // told when they attached an image to a model that cannot see.
    final modelVision = vision || profile.visionFor(config.model);
    if (!modelVision && attachments.any((item) => item.isImage)) {
      _log(
        '图片附件已忽略',
        detail: '这个模型不支持图片输入（可在 设置 → AI 智能体引擎 → 模型能力 里改）。'
            '文字附件和页面内容不受影响。',
      );
    }

    final llmService = LlmService();
    final loop = AgentLoop(
      llm: _LlmServicePort(
        service: llmService,
        config: config,
        token: _token,
        profile: profile,
        onStreamDelta: _onStreamDelta,
        onEffortDropped: (level) => _log(
          '端点不支持「${level.label}」',
          detail: '服务端拒绝了 reasoning_effort，本次及之后的请求按「自动」发送。'
              '要控制思考程度，只能换一个支持该字段的模型。',
        ),
      ),
      control: _ControlAdapter(_control!),
      host: _HostAdapter(this),
      system: systemPrompt(extra: extraSystemRules),
      tools: buildToolSchemas(vision: modelVision),
      safeMode: safeMode,
      isSiteAllowed: isSiteAllowed,
      isSiteBlocked: isSiteBlocked,
      vision: modelVision,
      attachments: attachments,
      keepGoing: _keepGoing,
      context: ContextLimits(
        windowTokens: profile.contextWindow,
        autoCompact: autoCompact,
        autoCompactTokens: autoCompactTokens,
      ),
      startUrl: urlHint,
      prior: priorMessages(
        priorTurns,
        compactedSummary: compactedSummary,
        compactedTurns: compactedTurns,
      ),
      onTurn: _onTurn,
      onThought: _onThought,
      onToolStarted: _onToolStarted,
      onToolFinished: _onToolFinished,
      onSkipped: (call, reason) => _log(
        '跳过 ${describeToolCall(call.name, call.args)}',
        detail: reason,
      ),
      onContextNote: (note) => _log('上下文', detail: note),
      onUrlChanged: _onUrlChanged,
    );

    try {
      final end = await loop.run(goal);
      _state = _state.copyWith(
        promptTokens: loop.promptTokens,
        completionTokens: loop.completionTokens,
      );
      await _finish(end);
    } catch (error) {
      _fail(describeLlmFailure(error));
    } finally {
      llmService.dispose();
      await _control?.detach();
      _control = null;
      _attached = false;
    }
  }

  /// Summarizes [conversation]'s uncompacted turns via `/compact` or Auto-Compact
  /// while surfacing live progress through [stateStream].
  Future<CompactionOutcome> compact(
    AgentConversation conversation, {
    required LlmConfig config,
    String focusNote = '',
    LlmService? llmService,
  }) async {
    _stopped = false;
    _paused = false;
    _token = CancellationToken();
    _logs = [];
    _streamBuffer.clear();
    _state = const AgentState(
      status: AgentStatus.thinking,
      goal: '/compact',
      currentThought: '正在压缩对话上下文…',
      logs: [],
    );
    _emit();
    try {
      final outcome = await ContextCompactor.compactConversation(
        conversation,
        config: config,
        focusNote: focusNote,
        llmService: llmService,
        cancelToken: _token,
        onDelta: _onStreamDelta,
      );
      _state = const AgentState();
      _emit();
      return outcome;
    } catch (_) {
      _state = const AgentState();
      _emit();
      rethrow;
    }
  }

  /// Answers a pending challenge hand-off.
  void confirmCaptchaSolved(bool passed) {
    final pending = _pendingPerson;
    if (pending == null || pending.isCompleted) return;
    _pendingPerson = null;
    _state = _state.copyWith(
      status: AgentStatus.executing,
      clearCaptchaType: true,
    );
    _emit();
    pending.complete(passed ? 'ok' : null);
  }

  /// Answers a pending write confirmation.
  void confirmAction(bool proceed) {
    final pending = _pendingConfirm;
    if (pending == null || pending.isCompleted) return;
    _pendingConfirm = null;
    _state = _state.copyWith(
      status: AgentStatus.executing,
      clearConfirmationContext: true,
    );
    _emit();
    pending.complete(proceed);
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    _resumeGate = Completer<void>();
    _state = _state.copyWith(status: AgentStatus.paused);
    _emit();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    final gate = _resumeGate;
    _resumeGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    _state = _state.copyWith(status: AgentStatus.observing);
    _emit();
  }

  void stop() {
    _stopped = true;
    _token.cancel();
    resume();
    final pendingConfirm = _pendingConfirm;
    if (pendingConfirm != null && !pendingConfirm.isCompleted) {
      _pendingConfirm = null;
      pendingConfirm.complete(false);
    }
    final pendingPerson = _pendingPerson;
    if (pendingPerson != null && !pendingPerson.isCompleted) {
      _pendingPerson = null;
      pendingPerson.complete(null);
    }
  }

  final StringBuffer _streamBuffer = StringBuffer();
  DateTime _lastStreamEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void dispose() {
    stop();
    _states.close();
  }

  // --- loop callbacks ---------------------------------------------------------

  void _onTurn(int turn) {
    if (_stopped) return;
    _streamBuffer.clear();
    _state = _state.copyWith(
      status: AgentStatus.thinking,
      streamingText: '',
    );
    _emit();
  }

  void _onStreamDelta(String delta) {
    if (_stopped || delta.isEmpty) return;
    _streamBuffer.write(delta);
    final now = DateTime.now();
    if (now.difference(_lastStreamEmit).inMilliseconds < 120) return;
    _lastStreamEmit = now;
    _publishStreamText();
  }

  void _publishStreamText() {
    final compact = _streamBuffer
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) return;
    const maxChars = 96;
    final excerpt = compact.length > maxChars
        ? '…${compact.substring(compact.length - maxChars)}'
        : compact;
    if (_state.streamingText == excerpt) return;
    _state = _state.copyWith(streamingText: excerpt);
    _emit();
  }

  void _onThought(String? thought) {
    if (thought == null || thought.isEmpty) return;
    _log(
      thought.length > 160 ? '${thought.substring(0, 160)}…' : thought,
      kind: LogKind.thought,
    );
  }

  void _onToolStarted(int index, ToolCallRequest call, String description) {
    if (_stopped) return;
    _streamBuffer.clear();
    _state = _state.copyWith(
      status: AgentStatus.executing,
      streamingText: '',
    );
    // The card is created here and completed by _onToolFinished, so one call is
    // one row: the old panel appended a second row on failure and the user had
    // to pair them up by eye.
    _openCards[call.id] = _logs.length;
    _log(description, kind: LogKind.action);
  }

  void _onToolFinished(ToolCallRequest call, ToolResultLike result) {
    final evidence = result.receipt == null
        ? null
        : StepEvidence.fromReceipt(result.receipt!);
    final failed = !result.ok;
    final slot = _openCards.remove(call.id);
    if (slot == null) {
      // A call that never announced itself (a refusal, a guard) still deserves a
      // row, but only when it went wrong.
      if (failed) {
        _log(
          '${describeToolCall(call.name, call.args)} 失败',
          detail: _failureText(result),
          isError: true,
          kind: LogKind.error,
        );
      }
      return;
    }
    _completeCard(
      slot,
      evidence,
      failed: failed,
      detail: failed ? _failureText(result) : null,
    );
  }

  /// A failure reads better as "what happened / what to do" than as a stack.
  String? _failureText(ToolResultLike result) {
    final message = result.error?.trim() ?? '';
    final hint = result.hint?.trim() ?? '';
    if (message.isEmpty) return hint.isEmpty ? null : hint;
    if (hint.isEmpty || hint == message) return message;
    return '$message\n$hint';
  }

  void _completeCard(
    int slot,
    StepEvidence? evidence, {
    required bool failed,
    String? detail,
  }) {
    if (slot < 0 || slot >= _logs.length) return;
    _logs = [
      ..._logs.sublist(0, slot),
      _logs[slot].completeWith(failed: failed, evidence: evidence, detail: detail),
      ..._logs.sublist(slot + 1),
    ];
    _state = _state.copyWith(logs: List.unmodifiable(_logs));
    _emit();
  }

  Future<bool> _keepGoing() async {
    if (_stopped) return false;
    final gate = _resumeGate;
    if (gate != null && !gate.isCompleted) await gate.future;
    return !_stopped;
  }

  // --- reporting --------------------------------------------------------------

  Future<String?> _askPerson(PersonRequest request) async {
    final completer = Completer<String?>();
    _pendingPerson = completer;
    if (request.isCaptcha) {
      _state = _state.copyWith(
        status: AgentStatus.waitingCaptcha,
        captchaType: request.title,
      );
      _emit();
      await _notifications.notifyCaptchaDetected(request.title);
    } else {
      final ui = onAsk;
      if (ui == null) {
        _pendingPerson = null;
        _log('无法提问', detail: '当前界面没有提供回答入口', isError: true);
        return null;
      }
      final answer = await ui(request.title);
      _pendingPerson = null;
      return answer;
    }
    final result = await completer.future;
    if (_stopped) return null;
    return result;
  }

  void _onUrlChanged(String url) {
    if (_stopped || url == _state.targetUrl) return;
    _state = _state.copyWith(targetUrl: url);
    _emit();
  }

  Future<bool> _askConfirmation(ConfirmRequest request) async {
    final completer = Completer<bool>();
    _pendingConfirm = completer;
    _state = _state.copyWith(
      status: AgentStatus.waitingConfirmation,
      confirmationReason: '${request.title}：${request.reason}',
      targetUrl: request.url ?? _state.targetUrl,
      confirmationPayload: request.payload,
      confirmationHandoff: request.handoff,
      confirmationNavigation: request.navigation,
    );
    _emit();
    final approved = await completer.future;
    if (_stopped) return false;
    return approved;
  }

  Future<void> _finish(LoopEnd end) async {
    _state = _state.copyWith(
      status: end.outcome == LoopOutcome.failed
          ? AgentStatus.error
          : (end.stoppedByUser ? AgentStatus.idle : AgentStatus.completed),
      streamingText: '',
      extractedData: end.data,
      errorMessage: end.error,
      clearConfirmationContext: true,
    );
    if (end.summary != null && end.summary!.isNotEmpty) {
      // Marked as a result: this is the sentence the user reads, and the one a
      // stored turn keeps as its answer.
      _log(end.outcomeLabel, detail: end.summary, kind: LogKind.result);
    }
    if (end.stopReason != null) {
      _log('结束原因', detail: end.stopReason, isError: end.outcome == LoopOutcome.failed);
    }
    _emit();
    if (_notifyOnComplete && !end.stoppedByUser && end.outcome == LoopOutcome.success) {
      await _notifications.notifyTaskCompleted(end.summary ?? '任务完成');
    }
  }

  void _fail(String message) {
    _state = _state.copyWith(
      status: AgentStatus.error,
      errorMessage: message,
      clearConfirmationContext: true,
    );
    _log('任务失败', detail: message, isError: true);
    _emit();
  }

  void _log(
    String title, {
    String? detail,
    bool isError = false,
    LogKind kind = LogKind.note,
  }) {
    _logs = [
      ..._logs,
      AgentLogItem(title: title, detail: detail, isError: isError, kind: kind),
    ];
    _state = _state.copyWith(logs: List.unmodifiable(_logs));
  }

  void _emit() {
    if (!_states.isClosed) _states.add(_state);
  }
}

/// Adapts the concrete [LlmService] to the loop's port.
class _LlmServicePort implements LlmPort {
  _LlmServicePort({
    required this.service,
    required this.config,
    required this.token,
    this.profile = const ModelProfile.fallback(),
    this.onStreamDelta,
    this.onEffortDropped,
  });

  final ModelProfile profile;

  final LlmService service;
  final LlmConfig config;
  final CancellationToken token;
  final void Function(String delta)? onStreamDelta;
  final void Function(ThinkingLevel level)? onEffortDropped;

  @override
  Future<LlmTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    final response = await service.chatWithTools(
      config: config,
      messages: messages,
      tools: tools,
      cancelToken: token,
      profile: profile,
      onTextDelta: onStreamDelta,
      onReasoningDelta: onStreamDelta,
    );
    if (response.effortDropped) onEffortDropped?.call(config.thinking);
    return LlmTurn(
      content: response.content,
      finishReason: response.finishReason,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      calls: _parseCalls(response.message['tool_calls']),
      reasoningOnly: response.reasoningOnly,
    );
  }

  List<ToolCallRequest> _parseCalls(Object? raw) {
    if (raw is! List) return const [];
    final calls = <ToolCallRequest>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) continue;
      final function = entry['function'];
      if (function is! Map) continue;
      final name = function['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final rawArguments = function['arguments']?.toString() ?? '';
      var args = <String, Object?>{};
      if (rawArguments.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawArguments);
          if (decoded is Map) args = Map<String, Object?>.from(decoded);
        } catch (_) {
          // A model that wrote broken JSON gets an empty call: the tool will
          // report the missing argument, which is a better message than a
          // parse error the model cannot see.
        }
      }
      calls.add(ToolCallRequest(
        id: entry['id']?.toString() ?? 'call_$index',
        name: name,
        args: args,
        rawArguments: rawArguments,
      ));
    }
    return calls;
  }
}

/// Adapts the control layer to the loop's port.
class _ControlAdapter implements ControlPort {
  _ControlAdapter(this.control);

  final Control control;

  @override
  Future<ToolResult> execute(String tool, [Map<String, Object?> args = const {}]) =>
      control.execute(tool, args);

  @override
  CaptchaInfo? get captcha => control.session.captcha;

  @override
  String? refLabel(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    try {
      final record = control.session.refs.lookup(ref);
      return record.label;
    } on ControlException {
      return null;
    }
  }

  @override
  set onGesture(void Function(GestureTarget target)? value) =>
      control.onGesture = value;
}

/// The runner as the loop's host: confirmations and log lines.
class _HostAdapter implements HostPort {
  _HostAdapter(this.runner);

  final AgentLoopRunner runner;

  @override
  Future<bool> confirm(ConfirmRequest request) => runner._askConfirmation(request);

  @override
  Future<String?> askPerson(PersonRequest request) => runner._askPerson(request);

  @override
  Future<List<String>?> pickFiles() async {
    final picker = runner.onPickFiles;
    if (picker == null) return null;
    return picker();
  }

  @override
  void note(String title, {String? detail, bool isError = false}) =>
      runner._log(title, detail: detail, isError: isError);
}
