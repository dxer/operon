part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// Turning a goal into a run, and everything the panel needs while it happens.

extension _AgentFlow on _BrowserPageState {
  /// The app's tab strip, as the control layer needs it.
  ///
  /// Targets and tabs are matched on URL because that is all they share: a
  /// DevTools target id never reaches the Flutter side. Two tabs on the same
  /// URL therefore match the first one, which is the same answer the user
  /// would give.
  TabHost _buildTabHost() => TabHost(
        activate: (page) async {
          final index = _tabIndexFor(page);
          if (index == null) return false;
          _switchTab(index);
          // The run lives on this tab now. The status strip and the close guard
          // both read this id; leaving it on the old tab means they protect a
          // page nobody is driving.
          if (_agentTabId != null) _agentTabId = _tabs[index].id;
          return true;
        },
        close: (page) async {
          final index = _tabIndexFor(page);
          if (index == null) return false;
          if (_tabs.length <= 1) return false;
          // The same guard the tab strip uses: a tab a run is driving is not
          // closed from under it.
          if (_runCoordinator.closeTabRejection(_tabs[index].id) != null) {
            return false;
          }
          _closeTab(index);
          return true;
        },
        open: (url) async {
          // Refused at the tab cap; there is no target to wait for.
          if (!_createNewTab(url: url)) return;
          // The WebView needs a frame before its DevTools target exists.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        },
      );

  int? _tabIndexFor(CdpTarget page) {
    for (var index = 0; index < _tabs.length; index++) {
      if (_tabs[index].url == page.url) return index;
    }
    // A half-typed address or a redirect can leave the two out of step; the
    // host is the next best identity for the same page.
    final host = Uri.tryParse(page.url)?.host ?? '';
    if (host.isEmpty) return null;
    for (var index = 0; index < _tabs.length; index++) {
      if ((Uri.tryParse(_tabs[index].url)?.host ?? '') == host) return index;
    }
    return null;
  }

  Future<void> _openConversations() async {
    final store = await ConversationStore.open();
    if (!mounted) return;
    setState(() {
      _conversations = store;
      // The most recent conversation is the useful default: it is almost
      // always the one the user means to open again.
      _activeConversationId ??=
          store.conversations.isEmpty ? null : store.conversations.first.id;
    });
  }

  /// Applies one state update, whichever engine produced it.
  ///
  /// Deliberately *not* a `setState`. This fires on every streamed chunk — up
  /// to ~8 times a second — and the only things on screen that change with it
  /// are the panel (which listens to the stream itself) and one boolean (kept
  /// in [_agentBusy]). Rebuilding the browser shell at that rate rebuilt every
  /// tab's WebView with it, which is why the page felt sticky while the model
  /// was typing.
  void _applyAgentState(AgentState state) {
    if (!mounted) return;
    // A run scrolls the page on its own; the controls must not disappear while
    // the user is watching it work.
    if (state.isRunning || state.status == AgentStatus.paused) {
      _chrome.lock();
      _revealChrome();
    } else if (!_agentSheetOpen) {
      _chrome.unlock();
    }
    if (state.status == AgentStatus.idle ||
        state.status == AgentStatus.completed ||
        state.status == AgentStatus.error) {
      _agentTabId = null;
      _runCoordinator.end(RunKind.agent);
    }
    _agentState = state;
    _agentBusy.value = state.isRunning;
    final isTerminal = state.status == AgentStatus.completed ||
        state.status == AgentStatus.error;
    final shouldRecord = isTerminal ||
        (state.status == AgentStatus.idle && _taskStartedAt != null);
    if (shouldRecord &&
        !_turnSaved &&
        state.goal.isNotEmpty &&
        state.goal != '/compact') {
      _turnSaved = true;
      unawaited(_saveTurn(state));
    }
    if (state.status == AgentStatus.idle) {
      _taskStartedAt = null;
    }
    _syncForegroundTask(state);
    if (state.status == AgentStatus.waitingConfirmation) {
      _maybeShowConfirmationCard(state);
    } else {
      _confirmationShownFor = null;
    }
    // A CAPTCHA is a stop that only a person can clear, and now that the dock
    // strip is gone the panel is the only place that says so.
    if (state.status == AgentStatus.waitingCaptcha) {
      _maybeOpenPanelForCaptcha();
    } else {
      _captchaPanelShown = false;
    }
  }

  Future<void> _compactConversation(
    AgentConversation conversation, {
    required LlmConfig config,
    String focusNote = '',
    bool isAuto = false,
  }) async {
    final outcome = await _loopRunner.compact(
      conversation,
      config: config,
      focusNote: focusNote,
    );
    if (outcome.summary.isEmpty) return;

    String fmtTokens(int tokens) =>
        tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}K' : '$tokens';
    final triggerLabel = isAuto ? 'Auto-Compact 自动压缩' : '/compact 上下文压缩';
    final methodLabel = outcome.usedLlm ? '模型摘要' : '本地结构化压缩';
    final reason =
        '$triggerLabel · $methodLabel（前 ${outcome.compactedTurnCount} 轮，'
        '约 ${fmtTokens(outcome.beforeTokens)} → ${fmtTokens(outcome.afterTokens)} tokens）';
    final now = DateTime.now();
    await _conversations?.applyCompaction(
      conversation.id,
      summary: outcome.summary,
      recordTurn: AgentTurn(
        id: 'compact_${now.microsecondsSinceEpoch}',
        message: isAuto
            ? 'Auto-Compact'
            : (focusNote.isEmpty ? '/compact' : '/compact $focusNote'),
        startedAt: now,
        endedAt: now,
        status: 'completed',
        result: outcome.summary,
        stopReason: reason,
        isCompaction: true,
      ),
    );
    if (mounted) {
      setState(() {});
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已压缩上下文：约 ${fmtTokens(outcome.beforeTokens)} → ${fmtTokens(outcome.afterTokens)} tokens',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _startAgentTask(
    String goal, [
    List<AgentAttachment> attachments = const [],
  ]) async {
    if (_wrapper == null) return;
    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    final compactCommand = parseCompactCommand(goal);
    if (compactCommand != null) {
      final store = _conversations;
      final conversation = store?.byId(_activeConversationId);
      if (conversation == null ||
          (!conversation.hasUncompactedHistory &&
              (conversation.compactedSummary ?? '').trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前对话暂无可压缩的上下文')),
        );
        return;
      }
      final rejection = _runCoordinator.begin(RunKind.agent, _currentTab.id);
      if (rejection != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(rejection)),
        );
        return;
      }
      _agentTabId = _currentTab.id;
      _runningConversationId = null;
      _turnSaved = true;
      try {
        await _compactConversation(
          conversation,
          config: config,
          focusNote: compactCommand.focusNote,
        );
      } finally {
        _agentTabId = null;
        _runCoordinator.end(RunKind.agent);
      }
      return;
    }

    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: '去设置',
            textColor: Colors.white,
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }

    final rejection = _runCoordinator.begin(RunKind.agent, _currentTab.id);
    if (rejection != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rejection)),
      );
      return;
    }

    final profile = _storage?.getModelProfile(config) ?? const ModelProfile();
    final autoCompact = _storage?.getAutoCompactEnabled() ?? true;
    final autoCompactTokens = _storage?.getAutoCompactTokens() ??
        AppConstants.defaultAutoCompactTokens;
    final safeMode = _storage?.getSafeMode() ?? true;

    // Which conversation this turn belongs to. Created here if the panel
    // opened one that has no messages yet.
    final store = _conversations;
    var conversation = store?.byId(_activeConversationId);
    if (conversation == null && store != null) {
      conversation = store.create();
      _activeConversationId = conversation.id;
    }
    _runningConversationId = conversation?.id;

    _agentTabId = _currentTab.id;
    _taskStartedAt = DateTime.now();
    _runningAttachmentNames =
        attachments.map((item) => item.label).toList(growable: false);
    _turnSaved = false;

    if (autoCompact &&
        conversation != null &&
        conversation.hasUncompactedHistory &&
        estimateConversationTokens(conversation) >= autoCompactTokens) {
      await _compactConversation(
        conversation,
        config: config,
        isAuto: true,
      );
    }

    unawaited(_loopRunner.run(
      goal: goal,
      urlHint: _currentTab.url,
      config: config,
      safeMode: safeMode,
      isSiteAllowed: (host) => _storage?.isAgentSiteAllowed(host) ?? false,
      isSiteBlocked: (host) => _storage?.isAgentSiteBlocked(host) ?? false,
      // What the user asked the agent to always keep in mind. It goes in as
      // extra system rules, after the contract, so it can never weaken it.
      extraSystemRules: _storage?.getAgentMemory(),
      // What this model can do: its context window, whether it takes images,
      // whether it accepts reasoning_effort, whether it calls tools at all.
      // Guessing all four is what used to break runs in ways nobody could see.
      profile: profile,
      autoCompact: autoCompact,
      autoCompactTokens: autoCompactTokens,
      attachments: attachments,
      // What this user and this agent already did together. Without it 「继续」
      // is a request to start over.
      priorTurns: conversation?.turns ?? const [],
      compactedSummary: conversation?.compactedSummary,
      compactedTurns: conversation?.compactedTurns ?? 0,
    ));
  }

  Future<void> _setSafeMode(bool enabled) async {
    await _storage?.saveSafeMode(enabled);
    if (mounted) setState(() {});
  }

  /// Mirrors the run into the task notification.
  ///
  /// The notification opens at the first state of a run and closes at the
  /// first terminal one; every state in between only replaces the status line.
  /// It is shown even when "后台继续执行" is off: the user may still switch
  /// apps, and without the service Android can kill the page and the pending
  /// confirmation while the notification explains why nothing is progressing.
  void _syncForegroundTask(AgentState state) {
    final status = state.status;
    if (!state.isRunning && status != AgentStatus.paused) {
      _autoPausedForBackground = false;
      if (!_foregroundTaskOpen) return;
      _foregroundTaskOpen = false;
      unawaited(ForegroundTaskService.instance.stop());
      return;
    }

    final paused = status == AgentStatus.paused;
    // Waiting for a person has nothing to pause; it has something to wait for.
    final waiting = status == AgentStatus.waitingConfirmation ||
        status == AgentStatus.waitingCaptcha;
    final canPause = !waiting;
    // `/compact` is a command, not something a person said; the notification
    // should read like a status, not echo the slash.
    final compacting = state.goal.trim() == '/compact';
    final detail = switch (status) {
      AgentStatus.paused => '点「继续」恢复执行',
      AgentStatus.waitingConfirmation => '等待你授权敏感操作',
      AgentStatus.waitingCaptcha => '需要你完成人机验证',
      AgentStatus.thinking => compacting ? '正在压缩对话上下文' : '正在思考下一步',
      AgentStatus.executing => _latestActionTitle(state) ?? '正在操作页面',
      AgentStatus.observing => '正在观察页面',
      _ => '正在执行任务',
    };

    if (!_foregroundTaskOpen) {
      _foregroundTaskOpen = true;
      final rawGoal = state.goal.trim();
      final startBody =
          rawGoal.isEmpty || rawGoal.startsWith('/') ? detail : rawGoal;
      unawaited(ForegroundTaskService.instance.start(
        goal: startBody,
        paused: paused,
        canPause: canPause,
      ));
      return;
    }
    unawaited(ForegroundTaskService.instance.update(
      detail: detail,
      paused: paused,
      canPause: canPause,
    ));
  }

  /// The last action the model took, in its one-line form.
  String? _latestActionTitle(AgentState state) {
    for (final log in state.logs.reversed) {
      if (log.kind != LogKind.action) continue;
      final title = log.title.trim();
      if (title.isNotEmpty) return title;
    }
    return null;
  }

  /// The notification is now the only control surface while the panel is
  /// closed, so its actions land here.
  void _onForegroundTaskAction(String action) {
    if (!mounted) return;
    switch (action) {
      case 'pause':
        _loopRunner.pause();
        return;
      case 'resume':
        _loopRunner.resume();
        return;
      case 'stop':
        _loopRunner.stop();
        return;
    }
  }

  Future<bool> _askWebPermission(String title, String detail) async {
    if (!mounted || _permissionDialogOpen) return false;
    _permissionDialogOpen = true;
    try {
      final allowed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(detail, style: const TextStyle(height: 1.45)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许'),
            ),
          ],
        ),
      );
      return allowed == true;
    } finally {
      _permissionDialogOpen = false;
    }
  }

  String _permissionLabel(String name) {
    switch (name) {
      case 'CAMERA':
        return '摄像头';
      case 'MICROPHONE':
        return '麦克风';
      case 'CAMERA_AND_MICROPHONE':
        return '摄像头与麦克风';
      case 'DEVICE_ORIENTATION_AND_MOTION':
        return '设备方向与运动';
      case 'PROTECTED_MEDIA_ID':
        return '受保护媒体';
      case 'MIDI_SYSEX':
        return 'MIDI 设备';
      case 'GEOLOCATION':
        return '定位';
      default:
        return name;
    }
  }

  /// Writes the finished run into its conversation.
  ///
  /// The steps are the actions the model asked for, in order, one readable
  /// line each. Thoughts are left out: a stored transcript is what happened,
  /// and re-reading a hundred "我看看" lines is not how you find out.
  Future<void> _saveTurn(AgentState state) async {
    final store = _conversations;
    final conversationId = _runningConversationId;
    if (store == null || conversationId == null) return;

    final startedAt = _taskStartedAt ??
        (state.logs.isNotEmpty ? state.logs.first.timestamp : DateTime.now());
    final now = DateTime.now();

    final steps = <AgentTurnStep>[
      for (final log in state.logs)
        if (log.kind == LogKind.action)
          AgentTurnStep(
            tool: '',
            summary: log.title,
            ok: !log.isError,
            detail: log.detail,
          ),
    ];

    // The answer the user reads: what `done` said, else the model's last
    // words. A run that stopped also says why.
    String? result;
    for (final log in state.logs.reversed) {
      if (log.kind == LogKind.result && (log.detail ?? '').isNotEmpty) {
        result = log.detail;
        break;
      }
    }
    result ??= state.currentThought.trim().isEmpty
        ? null
        : state.currentThought.trim();

    String? stopReason;
    for (final log in state.logs.reversed) {
      if (log.title == '结束原因') {
        stopReason = log.detail;
        break;
      }
    }
    if (state.errorMessage?.isNotEmpty == true) {
      stopReason ??= state.errorMessage;
      result ??= state.errorMessage;
    }

    final status = switch (state.status) {
      AgentStatus.completed => 'completed',
      AgentStatus.error => 'error',
      AgentStatus.idle => 'stopped',
      _ => 'partial',
    };

    final turn = AgentTurn(
      id: 't${startedAt.microsecondsSinceEpoch}',
      message: state.goal,
      startedAt: startedAt,
      endedAt: now,
      status: status,
      result: result,
      stopReason: stopReason,
      steps: steps,
      attachmentNames: _runningAttachmentNames,
      promptTokens: state.promptTokens,
      completionTokens: state.completionTokens,
      targetUrl: state.targetUrl ?? _currentTab.url,
    );
    try {
      await store.appendTurn(conversationId, turn);
    } catch (_) {
      // History is best-effort; never let persistence break the task flow.
    }
    if (mounted) {
      setState(() {
        _activeConversationId = conversationId;
      });
    }
  }

  Future<void> _allowSiteForTask() async {
    final url = _agentState.targetUrl ?? _currentTab.url;
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    if (host.isEmpty) {
      _loopRunner.confirmAction(true);
      return;
    }
    await _storage?.addAgentAllowedSite(host);
    _loopRunner.confirmAction(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将 $host 加入信任列表，之后该站点不再询问'),
          backgroundColor: AppTheme.accent,
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  String _confirmationToken(AgentState state) {
    return '${state.logs.length}|'
        '${state.confirmationPayload ?? ''}';
  }

  /// Pops the panel by itself when a run stops on a CAPTCHA.
  ///
  /// The banner with "我已完成验证" lives in the panel. The dock strip used to
  /// announce the block from the page; without it, a run that needs a human
  /// would wait behind a screen saying nothing at all. Once per episode: if the
  /// user closes the panel again, they know where it is.
  void _maybeOpenPanelForCaptcha() {
    if (_agentSheetOpen || _confirmationCardOpen || _captchaPanelShown) return;
    _captchaPanelShown = true;
    // A state update no longer calls setState, so nothing else schedules the
    // frame this callback needs. `addPostFrameCallback` does not schedule one.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _agentSheetOpen) return;
      if (_agentState.status != AgentStatus.waitingCaptcha) return;
      unawaited(_openAgentBottomSheet());
    });
  }

  /// Pops the dedicated authorization card as soon as a task stops on a
  /// sensitive action, so the user never has to hunt for the panel. Once per
  /// pending action: dismissing it leaves the panel's own banner.
  void _maybeShowConfirmationCard(AgentState state) {
    if (_agentSheetOpen || _confirmationCardOpen) return;
    final token = _confirmationToken(state);
    if (_confirmationShownFor == token) return;
    _confirmationShownFor = token;
    // See [_maybeOpenPanelForCaptcha]: nothing schedules the frame for us.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_agentSheetOpen) _showConfirmationCard();
    });
  }

  Future<void> _showConfirmationCard() async {
    if (_confirmationCardOpen || !mounted) return;
    _confirmationCardOpen = true;
    // The sheet usually arrives while the composer still has focus. The IME
    // would cover the approve button, and the decision is blocking, so let the
    // keyboard yield instead of squeezing the card. The sheet also lifts and
    // scrolls as a fallback for hardware keyboards.
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return StreamBuilder<AgentState>(
            stream: _loopRunner.stateStream,
            initialData: _agentState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? _agentState;
              if (state.status != AgentStatus.waitingConfirmation) {
                // The action was approved or the task stopped elsewhere.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted) Navigator.of(ctx).maybePop();
                });
                return const SizedBox.shrink();
              }
              return AgentConfirmationSheet(
                state: state,
                onConfirm: () {
                  Navigator.of(ctx).pop();
                  _loopRunner.confirmAction(true);
                },
                onCancel: () {
                  Navigator.of(ctx).pop();
                  _loopRunner.confirmAction(false);
                },
                onAllowSite: _allowSiteForTask,
              );
            },
          );
        },
      );
    } finally {
      _confirmationCardOpen = false;
    }
  }

  Future<void> _openAgentBottomSheet({String? initialGoal}) async {
    if (!mounted || _agentSheetOpen) return;
    _agentSheetOpen = true;
    _chrome.lock();
    _revealChrome();
    try {
      await _showAgentSheet(initialGoal: initialGoal);
    } finally {
      _agentSheetOpen = false;
      if (!_agentState.isRunning && _agentState.status != AgentStatus.paused) {
        _chrome.unlock();
      }
    }
  }

  Future<void> _showAgentSheet({String? initialGoal}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The scrim would sit between the panel and the page; a chat that grows
      // to full height wants the page gone, not dimmed behind it.
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        return DraggableScrollableSheet(
          // Three resting heights: enough to read an answer, enough to see the
          // page behind it, and 90% for a long transcript.
          //
          // Never full height. Even at its largest the panel leaves the top of
          // the page visible: what the agent is doing up there is the context
          // for the conversation, and a panel that can cover all of it turns
          // the browser into a chat app — the one thing this product is not.
          initialChildSize: 0.6,
          minChildSize: 0.38,
          maxChildSize: 0.9,
          snap: true,
          snapSizes: const [0.6, 0.75, 0.9],
          expand: false,
          builder: (context, scrollController) {
            return StreamBuilder<AgentState>(
              stream: _loopRunner.stateStream,
              initialData: _agentState,
              builder: (context, snapshot) {
                final state = snapshot.data ?? _agentState;
                return AgentBottomSheet(
                  scrollController: scrollController,
                  state: state,
                  currentUrl: _currentTab.url,
                  taskStartedAt: _taskStartedAt,
                  initialGoal: initialGoal,
                  imageAttachmentsEnabled: _modelTakesImages,
                  prompts: _storage?.getAgentPrompts() ?? const [],
                  safeMode: _storage?.getSafeMode() ?? true,
                  onSafeModeChanged: _setSafeMode,
                  onAllowSite: _allowSiteForTask,
                  store: _conversations,
                  conversationId: _activeConversationId,
                  onConversationChanged: (id) => _activeConversationId = id,
                  // A link in an answer is a place to go: this is a browser,
                  // so it opens where the user is already looking.
                  onOpenLink: (url) {
                    Navigator.of(ctx).pop();
                    _loadUrl(url);
                  },
                  onStart: (conversationId, goal, attachments) {
                    _activeConversationId = conversationId;
                    _startAgentTask(goal, attachments);
                  },
                  onResume: _loopRunner.resume,
                  onStop: _loopRunner.stop,
                  onConfirmAction: _loopRunner.confirmAction,
                  onConfirmCaptcha: _loopRunner.confirmCaptchaSolved,
                );
              },
            );
          },
        );
      },
    );
  }
}
