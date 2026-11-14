part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// Turning a goal into a run, and everything the panel needs while it happens.

extension _AgentFlow on _BrowserPageState {
  /// Applies one state update, whichever engine produced it.
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
    setState(() {
      if (state.isRunning || state.status == AgentStatus.paused) {
        _statusBarDismissed = false;
      }
      if (state.status == AgentStatus.idle ||
          state.status == AgentStatus.completed ||
          state.status == AgentStatus.maxStepsReached ||
          state.status == AgentStatus.error) {
        _agentTabId = null;
        _runCoordinator.end(RunKind.agent);
      }
      _agentState = state;
      final isTerminal = state.status == AgentStatus.completed ||
          state.status == AgentStatus.maxStepsReached ||
          state.status == AgentStatus.error;
      final shouldRecord = isTerminal ||
          (state.status == AgentStatus.idle && _taskStartedAt != null);
      if (shouldRecord && !_taskRecorded && state.goal.isNotEmpty) {
        _taskRecorded = true;
        unawaited(_persistTaskRecord(state));
      }
      if (state.status == AgentStatus.idle) {
        _taskStartedAt = null;
      }
    });
    if (state.status == AgentStatus.waitingConfirmation) {
      _maybeShowConfirmationCard(state);
    } else {
      _confirmationShownFor = null;
    }
  }

  void _startAgentTask(String goal) async {
    if (_wrapper == null) return;
    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
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

    final maxSteps = _storage?.getMaxSteps() ?? 15;
    final safeMode = _storage?.getSafeMode() ?? true;

    _agentTabId = _currentTab.id;
    _statusBarDismissed = false;
    _taskStartedAt = DateTime.now();
    _taskRecorded = false;

    unawaited(_loopRunner.run(
      goal: goal,
      urlHint: _currentTab.url,
      config: config,
      maxTurns: maxSteps,
      safeMode: safeMode,
      isSiteAllowed: (host) => _storage?.isAgentSiteAllowed(host) ?? false,
    ));
  }

  Future<void> _setSafeMode(bool enabled) async {
    await _storage?.saveSafeMode(enabled);
    if (mounted) setState(() {});
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

  Future<void> _persistTaskRecord(AgentState state) async {
    final storage = _storage;
    if (storage == null) return;
    final startedAt = _taskStartedAt ??
        (state.logs.isNotEmpty ? state.logs.first.timestamp : DateTime.now());
    final lines = state.logs.map((log) {
      final detail =
          log.detail == null || log.detail!.isEmpty ? '' : ' — ${log.detail}';
      final line = '[${log.step}] ${log.title}$detail';
      return line.length > 300 ? '${line.substring(0, 300)}…' : line;
    }).toList();
    if (lines.length > 80) {
      lines.removeRange(0, lines.length - 80);
    }
    final sensitive = state.logs
        .where((log) =>
            log.title.contains('敏感操作') ||
            log.title.contains('完全自主模式') ||
            log.title.contains('信任列表') ||
            log.title.contains('取消'))
        .map((log) => log.detail == null || log.detail!.isEmpty
            ? log.title
            : '${log.title} — ${log.detail}')
        .toList();

    final record = AgentTaskRecord(
      id: startedAt.millisecondsSinceEpoch.toString(),
      goal: state.goal,
      status: state.status == AgentStatus.idle ? 'stopped' : state.status.name,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      steps: state.currentStep,
      maxSteps: state.maxSteps,
      safeMode: storage.getSafeMode(),
      errorMessage: state.errorMessage,
      targetUrl: _currentTab.url,
      logs: lines,
      sensitiveActions: sensitive,
    );
    try {
      await storage.addAgentTaskRecord(record);
    } catch (_) {
      // History is best-effort; never let persistence break the task flow.
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
    return '${state.currentStep}|'
        '${state.confirmationPayload ?? ''}';
  }

  /// Pops the dedicated authorization card as soon as a task stops on a
  /// sensitive action, so the user never has to hunt for the panel. Once per
  /// pending action: dismissing it leaves the status strip's "审阅" button.
  void _maybeShowConfirmationCard(AgentState state) {
    if (_agentSheetOpen || _confirmationCardOpen) return;
    final token = _confirmationToken(state);
    if (_confirmationShownFor == token) return;
    _confirmationShownFor = token;
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

  Future<void> _openAgentBottomSheet() async {
    if (!mounted || _agentSheetOpen) return;
    _agentSheetOpen = true;
    _chrome.lock();
    _revealChrome();
    try {
      await _showAgentSheet();
    } finally {
      _agentSheetOpen = false;
      if (!_agentState.isRunning && _agentState.status != AgentStatus.paused) {
        _chrome.unlock();
      }
    }
  }

  Future<void> _showAgentSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StreamBuilder<AgentState>(
          stream: _loopRunner.stateStream,
          initialData: _agentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? _agentState;
            return AgentBottomSheet(
              state: state,
              currentUrl: _currentTab.url,
              taskStartedAt: _taskStartedAt,
              safeMode: _storage?.getSafeMode() ?? true,
              onSafeModeChanged: _setSafeMode,
              onAllowSite: _allowSiteForTask,
              onStart: (goal) {
                _startAgentTask(goal);
                Navigator.of(ctx).pop();
              },
              onPause: _loopRunner.pause,
              onResume: _loopRunner.resume,
              onStop: _loopRunner.stop,
              onConfirmAction: _loopRunner.confirmAction,
              onConfirmCaptcha: _loopRunner.confirmCaptchaSolved,
            );
          },
        );
      },
    );
  }
}
