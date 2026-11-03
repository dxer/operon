import 'dart:async';
import '../models/agent_action.dart';
import '../models/agent_action_result.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/macro_workflow.dart';
import '../models/skill.dart';
import '../utils/cancellation.dart';
import '../utils/extracted_data.dart';
import '../utils/prompt_builder.dart';
import '../utils/url_utils.dart';
import 'action_loop_detector.dart';
import 'execution_guard.dart';
import 'finish_verifier.dart';
import 'llm_service.dart';
import 'notification_service.dart';
import 'run_budget.dart';
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

  final ActionLoopDetector _loopDetector = ActionLoopDetector();
  late RunBudget _budget;
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
  SkillPolicy? _policy;
  Set<String>? _allowedTools;
  final List<String> _sentContentPreviews = [];
  final ExecutionGuard _dedupe = ExecutionGuard();
  String? _lastTypedText;
  int _lastTypedStep = -10;
  bool _lastTypedSecret = false;
  bool _batchLimitReached = false;
  String? _pendingItemContextKey;
  String? _pendingItemUrl;

  /// How long a hand-off CAPTCHA waits for the user before the task stops.
  static const Duration _captchaWait = Duration(minutes: 5);

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
    SkillPolicy? policy,
    Set<String>? allowedTools,
  }) async {
    _isCancelled = false;
    _isPaused = false;
    _safeMode = safeMode;
    _isSiteAllowed = isSiteAllowed;
    _taskToken = CancellationToken();
    _loopDetector.reset();
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
    _policy = policy;
    _allowedTools = allowedTools;
    _sentContentPreviews.clear();
    _dedupe.clearDedupe();
    _lastTypedText = null;
    _lastTypedStep = -10;
    _lastTypedSecret = false;
    _budget = RunBudget.fromPolicy(policy, fallbackMaxSteps: maxSteps);
    _batchLimitReached = false;
    _pendingItemContextKey = null;
    _pendingItemUrl = null;
    final stepLimit = _budget.maxSteps;
    final token = _taskToken!;
    final generation = ++_generation;

    final List<MacroStep> macroSteps = [];

    _emit(AgentState(
      status: AgentStatus.observing,
      goal: userGoal,
      currentStep: 0,
      maxSteps: stepLimit,
      extractedData: null,
      logs: [],
      recordedMacroSteps: [],
    ));

    _addLog('启动任务', detail: '目标: $userGoal');

    int step = 0;

    try {
      while (step < stepLimit) {
        if (_budget.timedOut) {
          _addLog('超过本次运行的最长时长，任务已停止', isError: true);
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: '超过本次运行的最长时长，任务已停止。',
          ));
          await webView.clearHighlights();
          return;
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        if (!await _waitWhilePaused(webView, generation)) return;

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

        // 1.05 Stop on generic rate-limit / temporary-block pages. This is
        // checked before spending another model call.
        if (((_policy?.stopOn ?? const ['rateLimit']).contains('rateLimit')) &&
            _isRateLimited(snapshot)) {
          _addLog(
            '检测到访问频率限制，任务已停止',
            detail: '页面提示操作过于频繁或稍后再试。请稍后手动重试，避免账号被限制。',
            isError: true,
          );
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: '目标网站提示访问频率限制，任务已停止。请稍后重试。',
          ));
          await webView.clearHighlights();
          return;
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
          // Do not wait forever: the user may have walked away after the
          // notification, and the task would otherwise hang until stopped.
          // Human-wait time must not consume the run's duration budget.
          _budget.pause();
          bool passed = false;
          try {
            passed = await _captchaCompleter!.future.timeout(
              _captchaWait,
              onTimeout: () => false,
            );
          } finally {
            _budget.resume();
          }
          _captchaCompleter = null;
          if (generation != _generation) return;

          if (!passed || _isCancelled) {
            final timedOut = !passed && !_isCancelled;
            _addLog(
              timedOut ? '等待人机验证超时，任务已停止' : '验证码处理取消，任务中止',
              isError: timedOut,
            );
            _emit(_state.copyWith(
              status: timedOut ? AgentStatus.error : AgentStatus.idle,
              errorMessage: timedOut
                  ? '等待人机验证超过 ${_captchaWait.inMinutes} 分钟，任务已停止。'
                  : null,
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
            _loopDetector.notifyProgress();
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

        if (!_budget.canCallLlm()) {
          final reason = _budget.timedOut ? '超过本次运行的最长时长' : '已达到本次运行的 AI 调用上限';
          _addLog('$reason，任务已停止', isError: true);
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: '$reason，任务已停止。',
          ));
          await webView.clearHighlights();
          return;
        }
        _budget.recordLlmCall();

        final messages = PromptBuilder.buildMessages(
          userGoal: userGoal,
          historyLogs: _state.logs,
          currentUrl: snapshot.url,
          pageTitle: snapshot.title,
          currentDomTree: snapshot.textTree,
          currentStep: step,
          maxSteps: stepLimit,
          extractedData: _state.extractedData,
          sentContents: _sentContentPreviews,
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

        // The user may have paused while the model was thinking. Honour it
        // before the action touches the page, not after.
        if (!await _waitWhilePaused(webView, generation)) return;

        _emit(_state.copyWith(
          currentThought: _safeThought(action),
          currentAction: action,
        ));

        _addLog(
          _actionLogDescription(action),
          detail:
              action.thought.isNotEmpty ? '思考: ${_safeThought(action)}' : null,
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
        final requestedTool = _toolIdForAction(action.action);
        if (_allowedTools != null &&
            requestedTool != null &&
            !_allowedTools!.contains(requestedTool)) {
          _addLog(
            '子任务调用了未授权的工具，已停止',
            detail: '工具：$requestedTool · 允许：${_allowedTools!.join(', ')}',
            isError: true,
          );
          _emit(_state.copyWith(
            status: AgentStatus.error,
            errorMessage: '子任务尝试使用未授权的工具：$requestedTool',
          ));
          await webView.clearHighlights();
          return;
        }
        if (action.action == ActionType.navigate) {
          _navigateCount++;
        }

        // Stop early when the model keeps choosing the same target: it almost
        // always means the page ignored the action or the element is gone.
        if (_loopDetector.record(
          action,
          pageSignature: _pageSignature(snapshot),
        )) {
          _addLog(
            '检测到连续重复操作，自动停止以避免空转',
            detail: _actionLogDescription(action),
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
          // Accumulate instead of replace: a second page reports only its new
          // records, and overwriting here used to drop everything before it.
          final merged = mergeExtractedData(
            _state.extractedData,
            action.extractedData,
          );
          _emit(_state.copyWith(extractedData: merged));
          _addLog('成功解析结构化数据', detail: '已暂存数据，可随时在控制台复制查看');
        }

        // 4. Handle Completion
        if (action.action == ActionType.finish) {
          final finalData = action.extractedData == null
              ? _state.extractedData
              : mergeExtractedData(_state.extractedData, action.extractedData);
          final decision = FinishVerifier.verify(
            goal: userGoal,
            summary: action.summary ?? '',
            extractedData: finalData,
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
            extractedData: finalData,
            recordedMacroSteps: List.unmodifiable(macroSteps),
          ));
          _addLog('任务顺利完成', detail: action.summary);
          await _notificationService
              .notifyTaskCompleted(action.summary ?? '任务完成');
          await webView.clearHighlights();
          return;
        }

        // 5. Handle Sensitive Action Confirmation (Human-in-the-loop)
        String? riskReason;
        Map<String, dynamic>? elementRisk;

        final needsElementRisk = action.elementId != null &&
            (action.action == ActionType.click ||
                action.action == ActionType.type ||
                action.action == ActionType.pressKey ||
                action.action == ActionType.selectOption);
        if (needsElementRisk) {
          elementRisk = await webView.getElementRisk(action.elementId!);
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        final elementText = (elementRisk?['text'] ?? '').toString();
        final elementContextKey = (elementRisk?['contextKey'] ?? '').toString();

        // Saving a draft is not a reply. Reply composers often show a
        // highlighted "保存草稿" button next to send; reject it deterministically
        // instead of trusting the model to ignore it.
        if (action.action == ActionType.click &&
            ExecutionGuard.looksLikeDraftAction(elementText)) {
          _addLog(
            '已拦截草稿按钮',
            detail: '「$elementText」是草稿按钮，不能用于回复。'
                '请改为点击“发送 / 回复 / 发布 / 提交”按钮。',
            isError: true,
          );
          _checkProgressNextStep = false;
          continue;
        }
        var isSensitive = action.isSensitive(
          '${action.thought} $elementText',
          pageUrl: snapshot.url,
        );
        if (elementRisk?['sensitive'] == true) {
          isSensitive = true;
          riskReason = elementRisk?['reason'] as String?;
        }
        // Search submissions are not publishing side effects, even when the
        // model's thought says "提交搜索".
        final searchOnly = ExecutionGuard.isSearchOnly(
          '${action.thought} $elementText ${action.description}',
        );
        if (searchOnly) {
          isSensitive = false;
          riskReason = null;
        }
        final elementTag = (elementRisk?['tag'] ?? '').toString().toUpperCase();
        // Typing an ordinary reply/message is local until it is submitted.
        // Only credential/payment entry needs confirmation here.
        final credentialIntent = RegExp(
          r'password|passwd|密码|验证码|credit card|card number|信用卡|卡号|'
          r'cvv|cvc|安全码|身份证|social security',
        ).hasMatch(
          '${action.thought} ${action.text ?? ''} $elementText'.toLowerCase(),
        );
        final credentialRisk = riskReason != null &&
            (riskReason.contains('密码') ||
                riskReason.contains('凭证') ||
                riskReason.contains('支付'));
        final credentialField = credentialRisk ||
            ((elementTag == 'INPUT' || elementTag == 'TEXTAREA') &&
                credentialIntent);
        final secretTyping =
            action.action == ActionType.type && credentialField && !searchOnly;
        if (action.action == ActionType.type) {
          if (secretTyping) {
            isSensitive = true;
          } else if (isSensitive) {
            isSensitive = false;
            riskReason = null;
          }
        }
        // Clicking a text/password field only focuses it; the actual submit
        // is a separate action. Do not ask for confirmation on focus.
        final inputType = (elementRisk?['type'] ?? '').toString().toLowerCase();
        final focusOnlyInput = inputType.isEmpty ||
            const [
              'text',
              'password',
              'email',
              'search',
              'tel',
              'url',
              'number',
            ].contains(inputType);
        if (action.action == ActionType.click &&
            elementTag == 'INPUT' &&
            focusOnlyInput) {
          isSensitive = false;
          riskReason = null;
        }
        // Focusing a text field / textarea / select usually does not change
        // the DOM signature. Do not count it as a failed action.
        final focusOnlyClick = action.action == ActionType.click &&
            ((elementTag == 'INPUT' && focusOnlyInput) ||
                elementTag == 'TEXTAREA' ||
                elementTag == 'SELECT');
        final submitLikeRaw =
            isSensitive && _looksLikeSubmit(action, elementText);
        final submittedContent =
            submitLikeRaw ? _contentForSubmit(action) : null;
        // Opening a reply/comment composer is not a side effect by itself.
        // The actual send is detected separately, when typed content exists
        // or the intent explicitly says send/post/publish.
        final openerOnly = submitLikeRaw &&
            submittedContent == null &&
            ExecutionGuard.isComposerOpener(
              '${action.thought} $elementText ${action.description}',
              elementText,
            );
        final submitLike = submitLikeRaw && !openerOnly;
        if (openerOnly && elementContextKey.isNotEmpty) {
          // Remember which item the composer was opened for, so the actual
          // send is deduplicated by the item rather than by the modal.
          _pendingItemContextKey = elementContextKey;
          _pendingItemUrl = snapshot.url;
        }
        // Soft write budget: stop starting new writes, but let the model
        // summarize what it already completed instead of failing the task.
        if (submitLike && !_budget.canStartSideEffect()) {
          final reason = _budget.timedOut
              ? '超过本次运行的最长时长'
              : '已达到本次写入上限（${_budget.sideEffects} 条）';
          _addLog(
            '$reason，已跳过该写入',
            detail: '请汇总已有结果并 finish。',
            isError: true,
          );
          _checkProgressNextStep = false;
          continue;
        }
        final targetContextKey =
            (_pendingItemContextKey != null && _pendingItemUrl == snapshot.url)
                ? _pendingItemContextKey!
                : elementContextKey;
        final targetHost = hostOf(snapshot.url);
        final siteAllowed =
            isSensitive && (_isSiteAllowed?.call(targetHost) ?? false);

        final mustConfirm = isSensitive &&
            !openerOnly &&
            !siteAllowed &&
            (_safeMode || (_policy?.confirmWrites ?? false));

        if (mustConfirm) {
          _emit(_state.copyWith(
            status: AgentStatus.waitingConfirmation,
            confirmationReason: riskReason ?? _actionLogDescription(action),
            targetUrl: snapshot.url,
            confirmationPayload: _confirmationPayload(
              action,
              elementRisk,
              secret: secretTyping,
            ),
          ));
          _addLog(
            '检测到敏感操作，等待人工授权...',
            detail: riskReason != null
                ? '目标：$riskReason · ${_actionLogDescription(action)} · $targetHost'
                : '${_actionLogDescription(action)} · $targetHost',
          );
          await _notificationService
              .notifyConfirmationNeeded(_actionLogDescription(action));

          _confirmationCompleter = Completer<bool>();
          // Waiting for a human decision is not automation time.
          _budget.pause();
          bool confirmed = false;
          try {
            confirmed = await _confirmationCompleter!.future;
          } finally {
            _budget.resume();
          }
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
        } else if (isSensitive && !openerOnly && siteAllowed) {
          _addLog(
            '本站已加入信任列表，自动执行敏感操作',
            detail: '${_actionLogDescription(action)} · $targetHost',
          );
        } else if (isSensitive && !openerOnly) {
          // Keep an audit trail even in fully autonomous mode.
          _addLog(
            '完全自主模式：直接执行敏感操作',
            detail: riskReason != null
                ? '目标：$riskReason · ${_actionLogDescription(action)}'
                : _actionLogDescription(action),
          );
        }

        if (_isCancelled) {
          await _abortTask(webView, generation: generation);
          return;
        }

        final submitKey = submitLike
            ? _sideEffectKey(
                action,
                elementText,
                snapshot.url,
                contextKey: targetContextKey,
              )
            : null;

        if (submitLike && _batchLimitReached) {
          _addLog(
            '已达到本次批量上限',
            detail: '本任务已处理 ${_budget.sideEffects} 条，请汇总结果并 finish。',
            isError: true,
          );
          _checkProgressNextStep = false;
          continue;
        }

        // Generic content dedupe: the same reply/message must never be sent
        // twice in one task, even if the model ignores the prompt.
        if (submitLike &&
            (_policy?.uniqueContent ?? false) &&
            submittedContent != null) {
          if (_dedupe.contentAlreadySent(submittedContent)) {
            _addLog(
              '重复内容已拦截',
              detail: '本次任务已经发送过相同内容，已阻止重复发送。'
                  '请为当前条目生成不同的内容。',
              isError: true,
            );
            _checkProgressNextStep = false;
            continue;
          }
        }

        // Generic target dedupe for batch templates. Without a policy this is
        // left to the at-most-once ledger so normal single-item tasks keep
        // working as before.
        if (submitKey != null &&
            (_policy?.uniqueTarget ?? false) &&
            _dedupe.targetAlreadyProcessed(submitKey)) {
          _addLog(
            '重复目标已拦截',
            detail: '本次任务已经处理过这个目标，已跳过。请处理下一个不同的条目。',
            isError: true,
          );
          _checkProgressNextStep = false;
          continue;
        }

        // At-most-once: an unverified submit blocks further attempts on the
        // same target instead of risking a duplicate post/payment.
        if (submitKey != null && !_sideEffects.canAttempt(submitKey)) {
          _addLog(
            '重复提交已拦截',
            detail: '「${_actionLogDescription(action)}」刚刚执行过，尚未确认完成。'
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
          _lastActionDescription = _actionLogDescription(action);
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
        final needsVerification =
            (_shouldCheckProgress(action) && !focusOnlyClick) || submitLike;

        if (actionSucceeded) {
          if (action.action == ActionType.type &&
              action.text != null &&
              action.text!.trim().isNotEmpty) {
            _lastTypedText = action.text;
            _lastTypedStep = step;
            _lastTypedSecret = secretTyping;
          }
          if (submitLike) {
            if (submittedContent != null) {
              _dedupe.rememberContent(submittedContent);
              if (!_lastTypedSecret) {
                final preview = submittedContent.trim();
                if (preview.isNotEmpty) {
                  _sentContentPreviews.add(
                    preview.length > 80
                        ? '${preview.substring(0, 80)}…'
                        : preview,
                  );
                  if (_sentContentPreviews.length > 20) {
                    _sentContentPreviews.removeAt(0);
                  }
                }
              }
            }
            // Count every completed write, including deletes/follows that carry
            // no text. Content dedupe only applies when there is content.
            _budget.recordSideEffect();
            if (submitKey != null) {
              _dedupe.rememberTarget(submitKey);
            }
            if (_budget.itemLimitReached) {
              _batchLimitReached = true;
              _addLog(
                '已达到本次批量上限',
                detail: '已完成 ${_budget.sideEffects} 条，请汇总结果并 finish。',
              );
            }
            // Do not reuse this text for the next target.
            _lastTypedText = null;
            _lastTypedStep = -10;
            _lastTypedSecret = false;
            _pendingItemContextKey = null;
            _pendingItemUrl = null;
          }
        }

        // 6.1 Record Macro Step if successful
        if (actionSucceeded && action.action != ActionType.wait) {
          macroSteps.add(MacroStep(
            action: action.action.name,
            selector: execResult['macroSelector'] as String?,
            text: secretTyping ? null : action.text,
            key: action.key,
            direction: action.direction,
            selectValue: action.selectValue,
            url: action.url,
            description: _actionLogDescription(action),
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
          if (openerOnly) {
            _pendingItemContextKey = null;
            _pendingItemUrl = null;
          }
          _addLog(
            '操作未生效',
            detail:
                '${result.error ?? '未知原因'}（动作：${_actionLogDescription(action)}）',
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

        _lastActionDescription = _actionLogDescription(action);
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
          // Batch templates can add a larger pacing gap between items.
          final pacing = _policy?.pacingMs ?? 0;
          await Future.delayed(
            Duration(milliseconds: pacing > 1200 ? pacing : 1200),
          );
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
      _addLog('已达到最大执行步数限制 ($stepLimit 步)，自动停止', isError: true);
      _emit(_state.copyWith(
        status: AgentStatus.maxStepsReached,
        errorMessage: '已达到 $stepLimit 步上限，任务未完成。可调高步数后重试。',
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
  /// Hide a credential value if the model echoed it in its reasoning.
  String? _toolIdForAction(ActionType action) {
    switch (action) {
      case ActionType.click:
        return 'page.click';
      case ActionType.type:
        return 'page.type';
      case ActionType.pressKey:
        return 'page.press_key';
      case ActionType.selectOption:
        return 'page.select';
      case ActionType.hover:
        return 'page.hover';
      case ActionType.scroll:
        return 'page.scroll';
      case ActionType.navigate:
        return 'page.open';
      case ActionType.goBack:
        return 'page.back';
      case ActionType.wait:
        return 'page.wait';
      case ActionType.extractData:
      case ActionType.finish:
      case ActionType.unknown:
        return null;
    }
  }

  String _safeThought(AgentAction action) {
    if (action.action != ActionType.type) return action.thought;
    final looksSecret = RegExp(
      r'password|passwd|密码|验证码|credit card|card number|信用卡|卡号|'
      r'cvv|cvc|安全码|身份证|social security',
    ).hasMatch(
      '${action.thought} ${action.text ?? ''}'.toLowerCase(),
    );
    return looksSecret ? '正在填写敏感信息…' : action.thought;
  }

  /// Log/macro label that never embeds typed text (passwords, drafts).
  String _actionLogDescription(AgentAction action) {
    if (action.action == ActionType.type) {
      return '在 [${action.elementId}] 输入内容';
    }
    return action.description;
  }

  String _sideEffectKey(
    AgentAction action,
    String targetText,
    String url, {
    String contextKey = '',
  }) {
    final normalizedTarget = targetText.trim().toLowerCase();
    final target = normalizedTarget.isEmpty
        ? action.description.trim().toLowerCase()
        : normalizedTarget;
    final trigger = action.key?.toLowerCase() ?? action.action.name;
    return '$url|$trigger|$target|$contextKey';
  }

  /// Content that the current submit-like action is about to send.
  ///
  /// The typed text is only considered when it was entered in the last two
  /// steps; otherwise a stale draft could be mis-attributed to a later
  /// "reply" button that merely opens a composer.
  String? _contentForSubmit(AgentAction action) {
    // Never treat a password/card value as reply content.
    if (_lastTypedSecret) return null;
    // A click does not carry content; it submits whatever was typed just
    // before it. Only keyboard actions may carry text in the action itself.
    if (action.action != ActionType.click &&
        action.text != null &&
        action.text!.trim().isNotEmpty) {
      return action.text;
    }
    if (_lastTypedText != null &&
        _lastTypedText!.trim().isNotEmpty &&
        _state.currentStep - _lastTypedStep <= 2) {
      return _lastTypedText;
    }
    return null;
  }

  String? _confirmationPayload(
    AgentAction action,
    Map<String, dynamic>? risk, {
    bool secret = false,
  }) {
    final reason = (risk?['reason'] ?? '').toString();
    final isSecret = secret ||
        _lastTypedSecret ||
        reason.contains('密码') ||
        reason.contains('凭证') ||
        reason.contains('支付');
    String? raw;
    if (action.action == ActionType.type) {
      raw = action.text;
    } else if (action.action != ActionType.click &&
        action.text != null &&
        action.text!.trim().isNotEmpty) {
      raw = action.text;
    } else if (_lastTypedText != null &&
        _state.currentStep - _lastTypedStep <= 2 &&
        _lastTypedText!.trim().isNotEmpty) {
      raw = _lastTypedText;
    } else if (action.url != null && action.url!.trim().isNotEmpty) {
      raw = action.url;
    } else {
      raw = (risk?['text'] ?? '').toString();
    }
    if (raw == null || raw.trim().isEmpty) return null;
    final shown = isSecret ? '••••••（已隐藏敏感内容）' : raw.trim();
    return shown.length > 300 ? '${shown.substring(0, 300)}…' : shown;
  }

  /// Conservative generic rate-limit detector. It only scans the title and
  /// the first part of the visible tree, so an article *about* rate limits
  /// further down the page will not stop the task.
  bool _isRateLimited(DOMSnapshot snapshot) {
    if (ExecutionGuard.looksRateLimited(snapshot.title)) return true;
    // Long articles usually mention these words as part of their content.
    // Only inspect the first part of short/error-like pages.
    final tree = snapshot.textTree.toLowerCase();
    if (tree.length > 4000) return false;
    final head = tree.length > 1500 ? tree.substring(0, 1500) : tree;
    return ExecutionGuard.looksRateLimited(head);
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
    return ExecutionGuard.looksLikeSubmitIntent(
      thought: action.thought,
      targetText: targetText,
      description: action.description,
    );
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

  /// Blocks while the user has paused the task.
  ///
  /// Returns false when the run was stopped or superseded. It is called at the
  /// top of a step and again right after the model answers: pressing pause
  /// while the model is thinking must still keep the pending click from
  /// running, otherwise "pause" only takes effect after the side effect.
  Future<bool> _waitWhilePaused(
    WebViewControllerWrapper webView,
    int generation,
  ) async {
    if (!_isPaused) return true;
    // Paused time is not automation time.
    _budget.pause();
    try {
      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (generation != _generation) return false;
        if (_isCancelled) {
          _addLog('任务已由用户手动停止');
          _emit(_state.copyWith(
            status: AgentStatus.idle,
            clearCurrentAction: true,
          ));
          await webView.clearHighlights();
          return false;
        }
      }
    } finally {
      _budget.resume();
    }
    _emit(_state.copyWith(status: AgentStatus.executing));
    return true;
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

  void dispose() {
    stop();
    _stateController.close();
    _llmService.dispose();
  }
}
