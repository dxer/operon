import 'dart:async';
import '../models/agent_action.dart';
import '../models/agent_action_result.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/macro_workflow.dart';
import '../utils/cancellation.dart';
import '../utils/prompt_builder.dart';
import 'finish_verifier.dart';
import 'llm_service.dart';
import 'notification_service.dart';
import 'side_effect_ledger.dart';
import 'webview_controller_wrapper.dart';

class AgentRunner {
  final LlmService _llmService;
  final NotificationService _notificationService =
      NotificationService.getInstance();

  AgentState _state = const AgentState();
  final StreamController<AgentState> _stateController =
      StreamController<AgentState>.broadcast();

  bool _isCancelled = false;
  bool _isPaused = false;
  bool _safeMode = true;
  int _generation = 0;
  bool Function(String host)? _isSiteAllowed;
  CancellationToken? _taskToken;
  Completer<bool>? _confirmationCompleter;
  Completer<bool>? _captchaCompleter;

  String? _lastActionSignature;
  int _repeatedActionCount = 0;
  String? _prevPageSignature;
  bool _checkProgressNextStep = false;
  int _noProgressCount = 0;
  int _invalidActionCount = 0;
  int _failedScrollCount = 0;
  int _navigateCount = 0;
  int _finishRejections = 0;
  final SideEffectLedger _sideEffects = SideEffectLedger();
  AgentActionResult? _pendingActionResult;
  String? _pendingUrl;
  String? _pendingSideEffectKey;
  String? _lastActionDescription;
  String? _lastConfirmedCaptchaKey;

  AgentRunner({LlmService? llmService})
      : _llmService = llmService ?? LlmService();

  Stream<AgentState> get stateStream => _stateController.stream;
  AgentState get state => _state;

  void _emit(AgentState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
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
    bool Function(String host)? isSiteAllowed,
  }) async {
    _isCancelled = false;
    _isPaused = false;
    _safeMode = safeMode;
    _isSiteAllowed = isSiteAllowed;
    _taskToken = CancellationToken();
    _lastActionSignature = null;
    _repeatedActionCount = 0;
    _prevPageSignature = null;
    _checkProgressNextStep = false;
    _noProgressCount = 0;
    _invalidActionCount = 0;
    _failedScrollCount = 0;
    _navigateCount = 0;
    _finishRejections = 0;
    _sideEffects.reset();
    _pendingActionResult = null;
    _pendingUrl = null;
    _pendingSideEffectKey = null;
    _lastActionDescription = null;
    _lastConfirmedCaptchaKey = null;
    final token = _taskToken!;
    final generation = ++_generation;

    final List<MacroStep> macroSteps = [];

    _emit(AgentState(
      status: AgentStatus.observing,
      goal: userGoal,
      currentStep: 0,
      maxSteps: maxSteps,
      extractedData: null,
      logs: [],
      recordedMacroSteps: [],
    ));

    _addLog('启动任务', detail: '目标: $userGoal');

    int step = 0;

    try {
      while (step < maxSteps) {
        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (_isCancelled) {
            _addLog('任务已由用户手动停止');
            _emit(_state.copyWith(
              status: AgentStatus.idle,
              clearCurrentAction: true,
            ));
            await webView.clearHighlights();
            return;
          }
        }

        step++;
        _emit(_state.copyWith(
          currentStep: step,
          status: AgentStatus.observing,
        ));

        // 1. Observe (Extract Pruned DOM & Check CAPTCHA)
        late DOMSnapshot snapshot;
        try {
          snapshot = await webView.extractPrunedDOM(
              showBadges: false, includeContent: true);
        } catch (firstError) {
          // Right after a navigation the old JS context may already be gone.
          // Wait for the new document before treating this as a real failure.
          _addLog('页面正在加载，等待后重新读取', detail: '$firstError');
          await Future.delayed(const Duration(milliseconds: 1500));
          if (_isCancelled) {
            await _abortTask(webView, generation: generation);
            return;
          }
          try {
            snapshot = await webView.extractPrunedDOM(
                showBadges: false, includeContent: true);
          } catch (e) {
            _addLog('获取页面元素失败', detail: e.toString(), isError: true);
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }

        // 1.1 CAPTCHA Hand-Off Check
        final captchaKey = '${snapshot.url}|${snapshot.captchaType}';
        if (snapshot.hasCaptcha &&
            snapshot.captchaType != null &&
            captchaKey != _lastConfirmedCaptchaKey) {
          _emit(_state.copyWith(
            status: AgentStatus.waitingCaptcha,
            captchaType: snapshot.captchaType,
          ));
          _addLog('检测到人机验证码', detail: snapshot.captchaType);
          await _notificationService
              .notifyCaptchaDetected(snapshot.captchaType!);

          _captchaCompleter = Completer<bool>();
          final passed = await _captchaCompleter!.future;
          _captchaCompleter = null;
          if (generation != _generation) return;

          if (!passed || _isCancelled) {
            _addLog('验证码处理取消，任务中止');
            _emit(_state.copyWith(
              status: AgentStatus.idle,
              clearCaptchaType: true,
              clearCurrentAction: true,
            ));
            await webView.clearHighlights();
            return;
          }

          _addLog('人机验证已通过，继续自动化任务...');
          _lastConfirmedCaptchaKey = captchaKey;
          _emit(_state.copyWith(
            status: AgentStatus.observing,
            clearCaptchaType: true,
          ));
          await webView.waitForDomStable(timeoutMs: 2000);
          continue; // Re-observe DOM after CAPTCHA
        }

        // 1.2 Verify the previous action. A slow SPA update gets one extra
        // chance before we declare "no effect".
        if (_checkProgressNextStep) {
          _checkProgressNextStep = false;
          var pageChanged = _pageSignature(snapshot) != _prevPageSignature;
          if (!pageChanged) {
            await Future.delayed(const Duration(milliseconds: 700));
            if (_isCancelled) {
              await _abortTask(webView, generation: generation);
              return;
            }
            try {
              snapshot = await webView.extractPrunedDOM(
                  showBadges: false, includeContent: true);
            } catch (_) {}
            pageChanged = _pageSignature(snapshot) != _prevPageSignature;
          }

          final pendingResult = _pendingActionResult;
          final sideEffectKey = _pendingSideEffectKey;
          final urlChanged = _pendingUrl != null && snapshot.url != _pendingUrl;
          final responded = pageChanged || urlChanged;

          if (pendingResult != null) {
            final verifiedResult = pendingResult.copyWith(
              pageChanged: pageChanged,
              urlChanged: urlChanged,
              verification: responded
                  ? ActionResultVerification.verified
                  : ActionResultVerification.noEffect,
            );
            if (sideEffectKey != null) {
              _addLog(
                '提交结果验证',
                detail: verifiedResult.describe(),
                isError: !responded,
              );
            }
          }

          if (responded) {
            _noProgressCount = 0;
            if (sideEffectKey != null) {
              _sideEffects.markVerified(sideEffectKey);
            }
          } else if (sideEffectKey != null) {
            // The click was dispatched but no response is visible yet.
            // Never repeat a non-idempotent action automatically.
            _sideEffects.markUnverified(sideEffectKey);
            _addLog(
              '提交结果未确认，已阻止重复提交',
              detail: '「${_lastActionDescription ?? '提交操作'}」执行后页面没有变化。'
                  '为避免重复发送，本任务内不会再次自动提交同一目标，请手动检查页面结果。',
              isError: true,
            );
          } else {
            _noProgressCount++;
            _addLog(
              '页面没有变化',
              detail:
                  '上一步「${_lastActionDescription ?? '操作'}」执行后页面无任何变化，可能未生效。请重新识别元素、滚动、后退或改用其他方式，不要原样重复。',
              isError: true,
            );
            if (_noProgressCount >= 3) {
              _addLog('连续多步页面无变化，任务已自动停止', isError: true);
              _emit(_state.copyWith(
                status: AgentStatus.error,
                errorMessage: '页面连续三次操作后都没有变化，任务可能被卡住。可刷新页面、调整目标或换个入口后重试。',
              ));
              await webView.clearHighlights();
              return;
            }
          }

          _pendingActionResult = null;
          _pendingUrl = null;
          _pendingSideEffectKey = null;
        }
        _prevPageSignature = _pageSignature(snapshot);

        if (snapshot.textTree.trim().isEmpty) {
          _addLog('未检测到可视交互元素，正在轻微滚动寻路...');
          final emptyScrollResult =
              await webView.executeAction(const AgentAction(
            thought: '滚动寻找元素',
            action: ActionType.scroll,
            direction: 'down',
          ));
          if (emptyScrollResult['success'] != true) {
            _failedScrollCount++;
            _addLog(
              '未检测到内容且无法继续滚动',
              detail: '${emptyScrollResult['error'] ?? '页面可能为空或已到边界'}',
              isError: true,
            );
            if (_failedScrollCount >= 3) {
              _emit(_state.copyWith(
                status: AgentStatus.error,
                errorMessage: '页面没有可操作内容，且连续滚动也无法加载新内容。',
              ));
              await webView.clearHighlights();
              return;
            }
          } else {
            _failedScrollCount = 0;
          }
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
          extractedData: _state.extractedData,
        );

        AgentAction action;
        try {
          action = await _llmService.getNextAction(
            config: config,
            messages: messages,
            cancelToken: token,
          );
        } on LlmCancelledException {
          await _abortTask(webView, generation: generation);
          return;
        } catch (e) {
          if (generation != _generation) return;
          _addLog('大模型调用异常', detail: e.toString(), isError: true);
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: e.toString(),
          ));
          await webView.clearHighlights();
          return;
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
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

        // Reject malformed actions early instead of burning a step on a JS
        // call that can only fail (`element_id` missing, unknown action, ...).
        final requiresElement = action.action == ActionType.click ||
            action.action == ActionType.type ||
            action.action == ActionType.selectOption ||
            action.action == ActionType.hover;
        final invalidAction = action.action == ActionType.unknown ||
            (requiresElement && action.elementId == null) ||
            (action.action == ActionType.navigate &&
                (action.url == null || action.url!.trim().isEmpty));
        if (invalidAction) {
          _invalidActionCount++;
          _addLog(
            '模型返回了无效操作，已跳过',
            detail: '缺少 element_id、url 或动作类型不受支持。请重新选择带 [id] 的元素。',
            isError: true,
          );
          if (_invalidActionCount >= 3) {
            _addLog('连续返回无效操作，任务已自动停止', isError: true);
            _emit(_state.copyWith(
              status: AgentStatus.error,
              errorMessage: '模型连续 3 次返回无效动作，已停止任务。可更换模型或调整目标后重试。',
            ));
            await webView.clearHighlights();
            return;
          }
          continue;
        }
        _invalidActionCount = 0;
        if (action.action == ActionType.navigate) {
          _navigateCount++;
        }

        // Stop early when the model keeps choosing the same target: it almost
        // always means the page ignored the action or the element is gone.
        if (_recordActionAndDetectLoop(action)) {
          _addLog(
            '检测到连续重复操作，自动停止以避免空转',
            detail: action.description,
            isError: true,
          );
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: '连续 4 次重复同一操作，任务已自动停止。可调整目标后重试。',
          ));
          await webView.clearHighlights();
          return;
        }

        // 3. Handle Data Extraction Event
        if (action.extractedData != null) {
          _emit(_state.copyWith(extractedData: action.extractedData));
          _addLog('成功解析结构化数据', detail: '已暂存数据，可随时在控制台复制查看');
        }

        // 4. Handle Completion
        if (action.action == ActionType.finish) {
          final decision = FinishVerifier.verify(
            goal: userGoal,
            summary: action.summary ?? '',
            extractedData: action.extractedData ?? _state.extractedData,
            step: step,
            navigateCount: _navigateCount,
            pageHasContent: snapshot.textTree.trim().isNotEmpty,
            currentUrl: snapshot.url,
            rejectionCount: _finishRejections,
          );
          if (!decision.allowed) {
            _finishRejections++;
            _addLog(
              '完成校验未通过',
              detail: decision.reason ?? '尚未取得可验证的页面结果',
              isError: true,
            );
            continue;
          }
          if (decision.warning) {
            _addLog(
              '完成校验放行（结果可能不完整）',
              detail: decision.reason,
              isError: true,
            );
          }

          _emit(_state.copyWith(
            status: AgentStatus.completed,
            extractedData: action.extractedData ?? _state.extractedData,
            recordedMacroSteps: List.unmodifiable(macroSteps),
          ));
          _addLog('任务顺利完成', detail: action.summary);
          await _notificationService
              .notifyTaskCompleted(action.summary ?? '任务完成');
          await webView.clearHighlights();
          return;
        }

        // 5. Handle Sensitive Action Confirmation (Human-in-the-loop)
        var isSensitive =
            action.isSensitive(action.thought, pageUrl: snapshot.url);
        String? riskReason;
        Map<String, dynamic>? elementRisk;

        final needsElementRisk = action.elementId != null &&
            (action.action == ActionType.click ||
                action.action == ActionType.type ||
                action.action == ActionType.pressKey ||
                action.action == ActionType.selectOption);
        if (needsElementRisk) {
          elementRisk = await webView.getElementRisk(action.elementId!);
          if (elementRisk?['sensitive'] == true) {
            isSensitive = true;
            riskReason = elementRisk?['reason'] as String?;
          }
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        final targetHost = _hostOf(snapshot.url);
        final siteAllowed =
            isSensitive && (_isSiteAllowed?.call(targetHost) ?? false);

        if (isSensitive && _safeMode && !siteAllowed) {
          _emit(_state.copyWith(
            status: AgentStatus.waitingConfirmation,
            confirmationReason: riskReason ?? action.description,
            targetUrl: snapshot.url,
          ));
          _addLog(
            '检测到敏感操作，等待人工授权...',
            detail: riskReason != null
                ? '目标：$riskReason · ${action.description} · $targetHost'
                : '${action.description} · $targetHost',
          );
          await _notificationService
              .notifyConfirmationNeeded(action.description);

          _confirmationCompleter = Completer<bool>();
          final confirmed = await _confirmationCompleter!.future;
          _confirmationCompleter = null;
          if (generation != _generation) return;

          if (!confirmed || _isCancelled) {
            _addLog('用户取消了该操作，任务终止');
            _emit(_state.copyWith(
              status: AgentStatus.idle,
              clearCurrentAction: true,
              clearConfirmationContext: true,
            ));
            await webView.clearHighlights();
            return;
          }
        } else if (isSensitive && siteAllowed) {
          _addLog(
            '本站已加入信任列表，自动执行敏感操作',
            detail: '${action.description} · $targetHost',
          );
        } else if (isSensitive) {
          // Keep an audit trail even in fully autonomous mode.
          _addLog(
            '完全自主模式：直接执行敏感操作',
            detail: riskReason != null
                ? '目标：$riskReason · ${action.description}'
                : action.description,
          );
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        final elementText = (elementRisk?['text'] ?? '').toString();
        final submitLike = isSensitive && _looksLikeSubmit(action, elementText);
        final submitKey = submitLike
            ? _sideEffectKey(action, elementText, snapshot.url)
            : null;

        // At-most-once: an unverified submit blocks further attempts on the
        // same target instead of risking a duplicate post/payment.
        if (submitKey != null && !_sideEffects.canAttempt(submitKey)) {
          _addLog(
            '重复提交已拦截',
            detail: '「${action.description}」刚刚执行过，尚未确认完成。'
                '为避免重复发送，本次已阻止；请先检查页面结果。',
            isError: true,
          );
          _checkProgressNextStep = false;
          continue;
        }

        // Actions that do not touch the page should not be sent to the DOM
        // executor: it would return "unknown action" and poison the history.
        if (action.action == ActionType.wait) {
          _emit(_state.copyWith(
            status: AgentStatus.executing,
            clearConfirmationContext: true,
          ));
          await Future.delayed(Duration(milliseconds: action.duration ?? 1500));
          continue;
        }
        if (action.action == ActionType.extractData) {
          _lastActionDescription = action.description;
          _checkProgressNextStep = false;
          await webView.waitForDomStable(timeoutMs: 1200);
          continue;
        }

        // 6. Execute Action
        _emit(_state.copyWith(
          status: AgentStatus.executing,
          clearConfirmationContext: true,
        ));

        final execResult = await webView.executeAction(action);

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        final result = AgentActionResult.fromMap(execResult).copyWith(
          sideEffect: submitLike,
          targetText: elementText.isEmpty ? null : elementText,
        );
        final actionSucceeded = result.success;
        final needsVerification = _shouldCheckProgress(action) || submitLike;

        // 6.1 Record Macro Step if successful
        if (actionSucceeded && action.action != ActionType.wait) {
          macroSteps.add(MacroStep(
            action: action.action.name,
            selector: execResult['macroSelector'] as String?,
            text: action.text,
            key: action.key,
            direction: action.direction,
            selectValue: action.selectValue,
            url: action.url,
            description: action.description,
            targetText: elementText.isEmpty ? null : elementText,
            nonIdempotent: submitLike,
          ));
          _emit(_state.copyWith(
              recordedMacroSteps: List.unmodifiable(macroSteps)));
        } else if (!actionSucceeded) {
          if (submitKey != null) {
            // Failed before dispatch (not found/disabled): no side effect.
            _sideEffects.clear(submitKey);
          }
          _addLog(
            '操作未生效',
            detail: '${result.error ?? '未知原因'}（动作：${action.description}）',
            isError: true,
          );
          if (action.action == ActionType.scroll) {
            _failedScrollCount++;
            if (_failedScrollCount >= 3) {
              _addLog('连续滚动均无法移动，任务已自动停止', isError: true);
              _emit(_state.copyWith(
                status: AgentStatus.error,
                errorMessage: '连续 3 次滚动都没有效果，页面可能已到边界或滚动区域未识别。'
                    '可直接提取当前内容，或手动滚动后再试。',
              ));
              await webView.clearHighlights();
              return;
            }
          }
        }
        if (action.action != ActionType.scroll ||
            (action.action == ActionType.scroll && actionSucceeded)) {
          _failedScrollCount = 0;
        }

        _lastActionDescription = action.description;
        _checkProgressNextStep = actionSucceeded && needsVerification;

        if (actionSucceeded && needsVerification) {
          _pendingActionResult = result;
          _pendingUrl = snapshot.url;
          _pendingSideEffectKey = submitKey;
          if (submitKey != null) {
            _sideEffects.markPending(submitKey);
          }
        } else {
          _pendingActionResult = null;
          _pendingUrl = null;
          _pendingSideEffectKey = null;
        }

        if (submitLike && actionSucceeded) {
          // Let the server answer before reading the modal again; otherwise
          // the reply button still looks clickable and gets pressed twice.
          await Future.delayed(const Duration(milliseconds: 1200));
        }

        // 7. Dynamic DOM Settle (Ghost cursor animation + MutationObserver)
        if (action.action == ActionType.wait) {
          await Future.delayed(Duration(milliseconds: action.duration ?? 1500));
        } else {
          if (action.action == ActionType.navigate ||
              action.action == ActionType.goBack) {
            // Give the new document a moment to start loading before asking
            // the old document whether it is stable.
            await Future.delayed(const Duration(milliseconds: 500));
          }
          await webView.waitForDomStable(timeoutMs: 2500);
        }
      }

      // Max steps exceeded: keep a visible terminal state instead of silently
      // returning to idle, so the user knows the goal was not reached.
      if (generation != _generation) return;
      _addLog('已达到最大执行步数限制 ($maxSteps 步)，自动停止', isError: true);
      _emit(_state.copyWith(
        status: AgentStatus.maxStepsReached,
        errorMessage: '已达到 $maxSteps 步上限，任务未完成。可调高步数后重试。',
        recordedMacroSteps: List.unmodifiable(macroSteps),
      ));
      await webView.clearHighlights();
    } catch (e) {
      if (generation != _generation) return;
      _addLog('执行过程发生未捕获异常', detail: e.toString(), isError: true);
      _emit(_state.copyWith(
        status: AgentStatus.error,
        errorMessage: e.toString(),
      ));
      await webView.clearHighlights();
    }
  }

  String _pageSignature(DOMSnapshot snapshot) {
    return '${snapshot.url}|${snapshot.title}|'
        '${snapshot.elementCount}|${snapshot.textTree.hashCode}';
  }

  /// Stable key for the at-most-once ledger. Uses page URL + action + target
  /// text so a different button/tweet is not blocked by the previous one.
  String _sideEffectKey(AgentAction action, String targetText, String url) {
    final normalizedTarget = targetText.trim().toLowerCase();
    final target = normalizedTarget.isEmpty
        ? action.description.trim().toLowerCase()
        : normalizedTarget;
    final trigger = action.key?.toLowerCase() ?? action.action.name;
    return '$url|$trigger|$target';
  }

  /// Detects actions that can create a post/message, so duplicate submissions
  /// (the reply button is still visible while the request is in flight) can be
  /// blocked.
  bool _looksLikeSubmit(AgentAction action, String targetText) {
    // Only clicks and Enter can submit something. Typing into a field is
    // idempotent and must not be treated as a non-repeatable side effect.
    if (action.action != ActionType.click &&
        action.action != ActionType.pressKey) {
      return false;
    }
    final haystack =
        '${action.thought} $targetText ${action.description}'.toLowerCase();
    const words = [
      'reply',
      'post',
      'tweet',
      'send',
      'submit',
      'publish',
      'comment',
      '回复',
      '发布',
      '发送',
      '提交',
      '评论',
      '发推',
      '支付',
      '付款',
      '购买',
      '下单',
    ];
    // Enter is also used for search. The keyword check below keeps plain
    // "按回车搜索" from being treated as a side effect.
    return words.any(haystack.contains);
  }

  /// Verifying progress only makes sense for actions that should change the
  /// page. Typing/selecting updates a field value that the DOM signature may
  /// not include, so counting them as "no progress" would abort legitimate
  /// multi-field form filling.
  bool _shouldCheckProgress(AgentAction action) {
    switch (action.action) {
      case ActionType.click:
      case ActionType.navigate:
      case ActionType.goBack:
        return true;
      case ActionType.pressKey:
        return action.key?.toLowerCase() == 'enter';
      default:
        return false;
    }
  }

  /// Returns a normalized host used for the per-site allowlist.
  String _hostOf(String url) {
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  /// Returns a task to idle and releases this task's page decorations.
  /// Stale runs (a newer task already started) are ignored.
  Future<void> _abortTask(
    WebViewControllerWrapper webView, {
    required int generation,
    String message = '任务已由用户手动停止',
  }) async {
    if (generation != _generation) return;
    _addLog(message);
    _emit(_state.copyWith(
      status: AgentStatus.idle,
      clearCurrentAction: true,
    ));
    await webView.clearHighlights();
  }

  /// Tracks consecutive identical interactive actions.
  bool _recordActionAndDetectLoop(AgentAction action) {
    const interactive = {
      ActionType.click,
      ActionType.type,
      ActionType.pressKey,
      ActionType.selectOption,
      ActionType.hover,
      ActionType.navigate,
      ActionType.goBack,
    };
    if (!interactive.contains(action.action)) {
      _lastActionSignature = null;
      _repeatedActionCount = 0;
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

    if (signature == _lastActionSignature) {
      _repeatedActionCount++;
    } else {
      _lastActionSignature = signature;
      _repeatedActionCount = 1;
    }
    return _repeatedActionCount >= 4;
  }

  void confirmAction(bool proceed) {
    if (_confirmationCompleter != null &&
        !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(proceed);
    }
  }

  void confirmCaptchaSolved(bool proceed) {
    if (_captchaCompleter != null && !_captchaCompleter!.isCompleted) {
      _captchaCompleter!.complete(proceed);
    }
  }

  void confirmCaptcha(bool proceed) => confirmCaptchaSolved(proceed);

  void pause() {
    _isPaused = true;
    _emit(_state.copyWith(status: AgentStatus.paused));
  }

  /// Allows the console or settings switch to change authorization behaviour
  /// mid-task. Disabling it while a confirmation is pending lets the agent
  /// continue immediately.
  void setSafeMode(bool enabled) {
    if (_safeMode == enabled) return;
    _safeMode = enabled;
    if (!enabled && _state.status == AgentStatus.waitingConfirmation) {
      confirmAction(true);
    }
  }

  bool get safeMode => _safeMode;

  void resume() {
    _isPaused = false;
    _emit(_state.copyWith(status: AgentStatus.executing));
  }

  void stop() {
    _isCancelled = true;
    _isPaused = false;
    _taskToken?.cancel();
    if (_confirmationCompleter != null &&
        !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(false);
    }
    if (_captchaCompleter != null && !_captchaCompleter!.isCompleted) {
      _captchaCompleter!.complete(false);
    }
    _emit(_state.copyWith(
      status: AgentStatus.idle,
      clearCurrentAction: true,
      clearCaptchaType: true,
      clearConfirmationContext: true,
    ));
  }

  void cancel() => stop();

  void dispose() {
    stop();
    _stateController.close();
    _llmService.dispose();
  }
}
