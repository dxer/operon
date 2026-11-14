import 'dart:async';
import 'dart:convert';

import '../control/control.dart';
import '../control/transport/endpoint.dart' show SocketConnector;
import '../control/perception/captcha.dart';
import '../control/protocol/errors.dart';
import '../control/protocol/results.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../services/llm_service.dart';
import '../services/llm_tools.dart';
import '../services/notification_service.dart';
import '../utils/cancellation.dart';
import 'context.dart';
import 'loop.dart';
import 'ports.dart';
import 'prompt.dart';
import 'tools.dart';

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
  final CancellationToken _token = CancellationToken();

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

  /// Notified before an input is dispatched, with the point it lands on.
  void Function(double x, double y, String label)? onGesture;

  /// Asks the user a question the agent cannot answer from the page.
  ///
  /// The panel supplies this; without it a question simply ends the run, which
  /// is better than an agent guessing an answer.
  Future<String?> Function(String question)? onAsk;

  /// The control layer is up: the run is using real input, not page script.
  bool get usesControlLayer => _attached;

  Stream<AgentState> get stateStream => _states.stream;

  AgentState get state => _state;

  Future<void> run({
    required String goal,
    required String? urlHint,
    required LlmConfig config,
    int maxTurns = 40,
    bool safeMode = true,
    bool Function(String host)? isSiteAllowed,
    String? extraSystemRules,
    bool notifyOnComplete = true,
    bool vision = false,
    SocketConnector? controlConnect,
  }) async {
    _stopped = false;
    _paused = false;
    _notifyOnComplete = notifyOnComplete;
    _logs = [];
    _openCards.clear();
    _state = AgentState(
      status: AgentStatus.observing,
      goal: goal,
      currentStep: 0,
      maxSteps: maxTurns,
      logs: const [],
    );
    _emit();

    _log(0, '启动任务', detail: '目标: $goal');

    // Attach first: if the control layer is unavailable, this throws before a
    // single model call is paid for.
    try {
      _control = await Control.attach(urlHint: urlHint, connect: controlConnect);
      _control!.onGesture = (x, y, label) => onGesture?.call(x, y, label);
      _attached = true;
      final notes = _control!.notes;
      if (notes.isNotEmpty) {
        for (final note in notes) {
          _log(0, '控制层提示', detail: note);
        }
      }
    } on ControlException catch (error) {
      _fail('控制层不可用：${error.message}${error.hint == null ? '' : '（${error.hint}）'}');
      rethrow;
    }

    final loop = AgentLoop(
      llm: _LlmServicePort(
        service: LlmService(),
        config: config,
        token: _token,
        onEffortDropped: (level) => _log(
          0,
          '端点不支持「${level.label}」',
          detail: '服务端拒绝了 reasoning_effort，本次及之后的请求按「自动」发送。'
              '要控制思考程度，只能换一个支持该字段的模型。',
        ),
      ),
      control: _ControlAdapter(_control!),
      host: _HostAdapter(this),
      system: systemPrompt(extra: extraSystemRules),
      tools: buildToolSchemas(vision: vision),
      maxTurns: maxTurns,
      safeMode: safeMode,
      isSiteAllowed: isSiteAllowed,
      vision: vision || modelSupportsVision(config.model),
      keepGoing: _keepGoing,
      context: const ContextLimits(windowTokens: 32000),
      startUrl: urlHint,
      onTurn: _onTurn,
      onThought: _onThought,
      onToolStarted: _onToolStarted,
      onToolFinished: _onToolFinished,
      onSkipped: (call, reason) => _log(
        _state.currentStep,
        '跳过 ${describeToolCall(call.name, call.args)}',
        detail: reason,
      ),
      onContextNote: (note) => _log(_state.currentStep, '上下文', detail: note),
    );

    try {
      final end = await loop.run(goal);
      await _finish(end);
    } catch (error) {
      _fail(describeLlmFailure(error));
    } finally {
      await _control?.detach();
      _control = null;
      _attached = false;
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
    final pending = _pendingConfirm;
    if (pending != null && !pending.isCompleted) {
      _pendingConfirm = null;
      pending.complete(false);
    }
  }

  void dispose() {
    stop();
    _states.close();
  }

  // --- loop callbacks ---------------------------------------------------------

  void _onTurn(int turn) {
    if (_stopped) return;
    _state = _state.copyWith(
      currentStep: turn,
      status: AgentStatus.thinking,
    );
    _emit();
  }

  void _onThought(String? thought) {
    if (thought == null || thought.isEmpty) return;
    _log(
      _state.currentStep,
      thought.length > 160 ? '${thought.substring(0, 160)}…' : thought,
      kind: LogKind.thought,
    );
  }

  void _onToolStarted(int index, ToolCallRequest call, String description) {
    if (_stopped) return;
    _state = _state.copyWith(status: AgentStatus.executing);
    // The card is created here and completed by _onToolFinished, so one call is
    // one row: the old panel appended a second row on failure and the user had
    // to pair them up by eye.
    _openCards[call.id] = _logs.length;
    _log(_state.currentStep, description, kind: LogKind.action);
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
          _state.currentStep,
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
        _log(_state.currentStep, '无法提问', detail: '当前界面没有提供回答入口', isError: true);
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

  Future<bool> _askConfirmation(ConfirmRequest request) async {
    final completer = Completer<bool>();
    _pendingConfirm = completer;
    _state = _state.copyWith(
      status: AgentStatus.waitingConfirmation,
      confirmationReason: '${request.title}：${request.reason}',
      confirmationPayload: request.payload,
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
      extractedData: end.data,
      errorMessage: end.error,
      clearConfirmationContext: true,
    );
    if (end.summary != null && end.summary!.isNotEmpty) {
      _log(end.turns, end.outcomeLabel, detail: end.summary);
    }
    if (end.stopReason != null) {
      _log(end.turns, '结束原因', detail: end.stopReason, isError: end.outcome == LoopOutcome.failed);
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
    _log(_state.currentStep, '任务失败', detail: message, isError: true);
    _emit();
  }

  void _log(
    int step,
    String title, {
    String? detail,
    bool isError = false,
    LogKind kind = LogKind.note,
  }) {
    _logs = [
      ..._logs,
      AgentLogItem(step: step, title: title, detail: detail, isError: isError, kind: kind),
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
    this.onEffortDropped,
  });

  final LlmService service;
  final LlmConfig config;
  final CancellationToken token;
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
    );
    if (response.effortDropped) onEffortDropped?.call(config.thinking);
    return LlmTurn(
      content: response.content,
      finishReason: response.finishReason,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      calls: _parseCalls(response.message['tool_calls']),
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
  set onGesture(void Function(double x, double y, String label)? value) =>
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
  void note(String title, {String? detail, bool isError = false}) =>
      runner._log(runner._state.currentStep, title, detail: detail, isError: isError);
}
