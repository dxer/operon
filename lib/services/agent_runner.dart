import 'dart:async';
import '../models/agent_action.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../utils/prompt_builder.dart';
import 'llm_service.dart';
import 'webview_controller_wrapper.dart';

class AgentRunner {
  final LlmService _llmService;

  AgentState _state = const AgentState();
  final StreamController<AgentState> _stateController =
      StreamController<AgentState>.broadcast();

  bool _isCancelled = false;
  bool _isPaused = false;
  Completer<bool>? _confirmationCompleter;

  AgentRunner({LlmService? llmService})
      : _llmService = llmService ?? LlmService();

  Stream<AgentState> get stateStream => _stateController.stream;
  AgentState get state => _state;

  void _emit(AgentState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void _addLog(String title, {String? detail, bool isError = false}) {
    final newLogs = List<AgentLogItem>.from(_state.logs);
    newLogs.add(AgentLogItem(
      step: _state.currentStep,
      title: title,
      detail: detail,
      isError: isError,
    ));
    _emit(_state.copyWith(logs: newLogs));
  }

  /// Starts the autonomous ReAct loop
  Future<void> run({
    required String userGoal,
    required WebViewControllerWrapper webView,
    required LlmConfig config,
    int maxSteps = 15,
    bool safeMode = true,
  }) async {
    _isCancelled = false;
    _isPaused = false;

    _emit(AgentState(
      status: AgentStatus.observing,
      goal: userGoal,
      currentStep: 0,
      maxSteps: maxSteps,
      extractedData: null,
      logs: [],
    ));

    _addLog('启动任务', detail: '目标: $userGoal');

    int step = 0;

    try {
      while (step < maxSteps) {
        if (_isCancelled) {
          _addLog('任务已由用户手动停止');
          _emit(_state.copyWith(status: AgentStatus.idle));
          await webView.clearHighlights();
          return;
        }

        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (_isCancelled) return;
        }

        step++;
        _emit(_state.copyWith(
          currentStep: step,
          status: AgentStatus.observing,
        ));

        // 1. Observe (Extract Pruned DOM & Content)
        DOMSnapshot snapshot;
        try {
          snapshot = await webView.extractPrunedDOM(showBadges: true, includeContent: true);
        } catch (e) {
          _addLog('获取页面元素失败', detail: e.toString(), isError: true);
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        if (snapshot.textTree.trim().isEmpty) {
          _addLog('未检测到可视交互元素，正在轻微滚动寻路...');
          await webView.executeAction(const AgentAction(
            thought: '滚动寻找元素',
            action: ActionType.scroll,
            direction: 'down',
          ));
          await webView.waitForDomStable(timeoutMs: 1500);
          continue;
        }

        // 2. Reason (Call LLM)
        _emit(_state.copyWith(status: AgentStatus.thinking));

        final messages = PromptBuilder.buildMessages(
          userGoal: userGoal,
          historyLogs: _state.logs,
          currentUrl: snapshot.url,
          pageTitle: snapshot.title,
          currentDomTree: snapshot.textTree,
          currentStep: step,
          maxSteps: maxSteps,
        );

        AgentAction action;
        try {
          action = await _llmService.getNextAction(
            config: config,
            messages: messages,
          );
        } catch (e) {
          _addLog('大模型调用异常', detail: e.toString(), isError: true);
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: e.toString(),
          ));
          await webView.clearHighlights();
          return;
        }

        _emit(_state.copyWith(
          currentThought: action.thought,
          currentAction: action,
        ));

        _addLog(
          action.description,
          detail: action.thought.isNotEmpty ? '思考: ${action.thought}' : null,
        );

        // 3. Handle Data Extraction Event
        if (action.extractedData != null) {
          _emit(_state.copyWith(extractedData: action.extractedData));
          _addLog('成功解析结构化数据', detail: '已暂存数据，可随时在控制台查看');
        }

        // 4. Handle Completion
        if (action.action == ActionType.finish) {
          _emit(_state.copyWith(
            status: AgentStatus.completed,
            extractedData: action.extractedData ?? _state.extractedData,
          ));
          _addLog('任务顺利完成 🎉', detail: action.summary);
          await webView.clearHighlights();
          return;
        }

        // 5. Handle Sensitive Action Confirmation
        if (safeMode && action.isSensitive(action.thought)) {
          _emit(_state.copyWith(status: AgentStatus.waitingConfirmation));
          _addLog('检测到敏感操作，等待人工授权...');

          _confirmationCompleter = Completer<bool>();
          final confirmed = await _confirmationCompleter!.future;
          _confirmationCompleter = null;

          if (!confirmed || _isCancelled) {
            _addLog('用户取消了该操作，任务终止');
            _emit(_state.copyWith(status: AgentStatus.idle));
            await webView.clearHighlights();
            return;
          }
        }

        // 6. Execute Action
        _emit(_state.copyWith(status: AgentStatus.executing));

        final execResult = await webView.executeAction(action);
        if (execResult['success'] == false) {
          _addLog(
            '执行反馈',
            detail: execResult['error'] ?? '可能需要重试',
            isError: false,
          );
        }

        // 7. Dynamic DOM Settle (replaces rigid sleep with MutationObserver debounce)
        if (action.action == ActionType.wait) {
          await Future.delayed(Duration(milliseconds: action.duration ?? 1500));
        } else {
          await webView.waitForDomStable(timeoutMs: 2500);
        }
      }

      // Max steps exceeded
      _addLog('已达到最大执行步数限制 ($maxSteps 步)，自动停止', isError: true);
      _emit(_state.copyWith(status: AgentStatus.idle));
      await webView.clearHighlights();
    } catch (e) {
      _addLog('执行过程发生未捕获异常', detail: e.toString(), isError: true);
      _emit(_state.copyWith(
        status: AgentStatus.error,
        errorMessage: e.toString(),
      ));
      await webView.clearHighlights();
    }
  }

  void confirmAction(bool proceed) {
    if (_confirmationCompleter != null && !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(proceed);
    }
  }

  void pause() {
    _isPaused = true;
    _emit(_state.copyWith(status: AgentStatus.paused));
  }

  void resume() {
    _isPaused = false;
    _emit(_state.copyWith(status: AgentStatus.executing));
  }

  void stop() {
    _isCancelled = true;
    if (_confirmationCompleter != null && !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(false);
    }
    _emit(_state.copyWith(status: AgentStatus.idle));
  }

  void dispose() {
    stop();
    _stateController.close();
  }
}
