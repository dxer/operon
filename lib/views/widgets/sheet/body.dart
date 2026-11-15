part of '../agent_bottom_sheet.dart';

// These extensions are on this State, in this library, and always run inside
// the widget that owns it.
// ignore_for_file: invalid_use_of_protected_member

// What scrolls in the chat view: the turns already finished, then the run that
// is happening right now. The header above this no longer moves.

extension _SheetBody on _AgentBottomSheetState {
  /// The message the user sent, right-aligned like every chat: it is the one
  /// thing on screen that came from them.
  Widget _buildUserBubble(String text) {
    final isDark = _isDarkTheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x3,
          vertical: AppSpace.x2 + 2,
        ),
        decoration: BoxDecoration(
          color: AppInk.accentTint(isDark),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Text(
          text,
          style: AppType.body.copyWith(color: AppInk.primary(isDark)),
        ),
      ),
    );
  }

  /// One finished turn, as it reads in the transcript.
  Widget _buildTurnBlock(AgentTurn turn) {
    if (turn.isCompaction) {
      return _buildCompactionCard(turn);
    }
    final isDark = _isDarkTheme;
    final failed = turn.failed;
    final ink = failed
        ? AppTheme.dangerOf(isDark)
        : AppInk.primary(isDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildUserBubble(turn.message),
          if (turn.attachmentNames.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x1),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      size: 12,
                      color: AppInk.tertiary(isDark),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        turn.attachmentNames.join('、'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: AppInk.tertiary(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome_rounded,
                size: 14,
                color: failed ? ink : AppTheme.primaryOf(isDark),
              ),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Answers are written in Markdown; rendering them as
                    // plain text turned every list and heading into noise.
                    MarkdownAnswer(
                      (turn.result ?? turn.stopReason ?? '').trim().isEmpty
                          ? _statusLine(turn)
                          : (turn.result ?? turn.stopReason)!,
                      onOpenLink: widget.onOpenLink,
                      baseStyle: AppType.body.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: AppSpace.x1),
                    if (turn.steps.isNotEmpty)
                      _buildTurnSteps(turn)
                    else
                      Text(
                        _turnMeta(turn),
                        style: AppType.caption.copyWith(
                          color: AppInk.tertiary(isDark),
                        ),
                      ),
                    _buildAnswerActions(turn, isDark),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What you can do with an answer: copy it or put the prompt back into the
  /// composer to tweak and re-run.
  Widget _buildAnswerActions(AgentTurn turn, bool isDark) {
    final text = (turn.result ?? turn.stopReason ?? '').trim();
    final canCopy = text.isNotEmpty;
    final canReask = !_isTaskActive && turn.message.trim().isNotEmpty;
    if (!canCopy && !canReask) return const SizedBox.shrink();

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x2,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppInk.tertiary(isDark)),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.caption.copyWith(
                  color: AppInk.tertiary(isDark),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x1),
      child: Row(
        children: [
          if (canCopy)
            actionButton(
              icon: Icons.copy_rounded,
              label: '复制',
              onTap: () {
                HapticService.selection();
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制这条回答'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          if (canReask)
            actionButton(
              icon: Icons.refresh_rounded,
              label: '重问',
              onTap: () {
                HapticService.selection();
                _goalController.text = turn.message;
                _goalController.selection =
                    TextSelection.collapsed(offset: turn.message.length);
                _goalFocus.requestFocus();
              },
            ),
        ],
      ),
    );
  }

  /// Compact visual marker rendered inline for `/compact` or Auto-Compact.
  Widget _buildCompactionCard(AgentTurn turn) {
    final isDark = _isDarkTheme;
    final info = (turn.stopReason ?? '已压缩上下文').trim();
    final summary = (turn.result ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x5),
      child: OperonCard(
        color: AppInk.sunken(isDark),
        borderColor: AppInk.hairline(isDark),
        radius: AppRadius.card,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x3,
          vertical: AppSpace.x2 + 2,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: AppSpace.x2),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            visualDensity: VisualDensity.compact,
            title: Row(
              children: [
                Icon(
                  Icons.compress_rounded,
                  size: 14,
                  color: AppTheme.primaryOf(isDark),
                ),
                const SizedBox(width: AppSpace.x2),
                Expanded(
                  child: Text(
                    info,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      color: AppInk.secondary(isDark),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            children: [
              if (summary.isNotEmpty)
                MarkdownAnswer(
                  summary,
                  onOpenLink: widget.onOpenLink,
                  baseStyle: AppType.caption.copyWith(
                    color: AppInk.secondary(isDark),
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Everything except the answer, folded into one line.
  ///
  /// A finished turn reads like a chat reply: the answer, then a small line that
  /// says how it went. The steps are behind it — same data the running row
  /// shows, same order, just not in the way.
  Widget _buildTurnSteps(AgentTurn turn) {
    final isDark = _isDarkTheme;
    final failed = turn.steps.where((step) => !step.ok).length;
    final detailsOpen = ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: AppSpace.x1, bottom: 4),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      visualDensity: VisualDensity.compact,
      title: Row(
        children: [
          Flexible(
            child: Text(
              _turnMeta(turn, failed: failed),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                color: failed == 0
                    ? AppInk.tertiary(isDark)
                    : AppTheme.dangerOf(isDark),
              ),
            ),
          ),
        ],
      ),
      children: [
        for (final step in turn.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.ok ? '·' : '!',
                  style: AppType.caption.copyWith(
                    color: step.ok
                        ? AppInk.tertiary(isDark)
                        : AppTheme.dangerOf(isDark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpace.x2),
                Expanded(
                  child: Text(
                    step.summary,
                    style: AppType.caption.copyWith(
                      color: AppInk.secondary(isDark),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: detailsOpen,
    );
  }

  String _statusLine(AgentTurn turn) => switch (turn.status) {
        'completed' => '已完成。',
        'stopped' => '已停止。',
        'error' => '执行失败。',
        _ => '没有留下总结。',
      };

  String _turnMeta(AgentTurn turn, {int failed = 0}) {
    final parts = <String>[
      if (turn.steps.isNotEmpty) '执行过程',
      if (failed > 0) '存在失败操作',
    ];
    final duration = turn.duration.inSeconds;
    parts.add(duration < 60 ? '$duration 秒' : '${turn.duration.inMinutes} 分');
    final tokens = turn.promptTokens + turn.completionTokens;
    if (tokens > 0) parts.add('${_tokens(tokens)} token');
    final stop = (turn.stopReason ?? '').trim();
    if (stop.isNotEmpty && (turn.result ?? '').trim().isNotEmpty) parts.add(stop);
    return parts.join(' · ');
  }

  String _tokens(int value) => value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : '$value';

  Widget _buildChatBody({
    required AgentState state,
    required bool isRunning,
  }) {
    final isDark = _isDarkTheme;
    final hairline = AppInk.hairline(isDark);
    final surface = AppInk.sunken(isDark);
    final onSurface = AppInk.primary(isDark);
    final muted = AppInk.secondary(isDark);
    final turns = _conversation?.turns ?? const <AgentTurn>[];
    final live = _showsLiveBlock(state, turns);
    final goal = state.goal.trim();

    // One row per entry, each built only when it scrolls into view. The list
    // used to be passed whole to `ListView(children:)`: elements still mounted
    // lazily, but every turn's widget subtree was constructed on every rebuild
    // — and this pane rebuilds on every streamed chunk of a run.
    final rows = <Widget Function()>[];
    if (turns.isEmpty && !live) rows.add(_buildEmptyChat);
    for (final turn in turns) {
      rows.add(() => _buildTurnBlock(turn));
    }
    // The message you just sent belongs in the transcript the moment you
    // send it. It used to appear only when the answer did, because the
    // transcript was built from finished turns only.
    if (live && goal.isNotEmpty) {
      rows.add(() => Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.x3),
            child: _buildUserBubble(goal),
          ));
    }
    if (live) {
      rows.addAll(_buildLiveBlock(state).map((row) => () => row));
    }
    if (!live && turns.isNotEmpty && !isRunning) {
      // Room to breathe under the last answer: the composer sits directly
      // below, and text touching it reads as one paragraph.
      rows.add(() => const SizedBox(height: AppSpace.x1));
    }
    if (!_safeMode) {
      rows.add(() {
        final warning = AppTheme.warningOf(isDark);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpace.x2),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: warning),
              const SizedBox(width: AppSpace.x2 - 2),
              Expanded(
                child: Text(
                  '全自动模式：支付、发布、删除等操作不会暂停确认',
                  style: AppType.caption.copyWith(color: warning),
                ),
              ),
            ],
          ),
        );
      });
    }
    if (state.extractedData != null) {
      rows.add(() => Padding(
            padding: const EdgeInsets.only(top: AppSpace.x3),
            child: _buildExtractedCard(
              data: state.extractedData,
              surface: surface,
              hairline: hairline,
              onSurface: onSurface,
              muted: muted,
            ),
          ));
    }

    return ListView.builder(
      controller: _bodyScroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x2,
        AppSpace.page,
        AppSpace.x2,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }

  /// True while the current run is not yet a stored turn.
  ///
  /// After a run ends it is appended to the conversation, and both would draw
  /// the same thing: one from the record, one from the live state. The record
  /// wins, because it is what survives the panel.
  bool _showsLiveBlock(AgentState state, List<AgentTurn> turns) {
    if (state.isRunning || state.status == AgentStatus.paused) return true;
    if (state.status == AgentStatus.waitingCaptcha ||
        state.status == AgentStatus.waitingConfirmation) {
      return true;
    }
    // A finished run whose turn has not been written yet still has to be
    // readable — including the message the user sent, which is the only trace
    // left if the model never answered.
    if (state.goal.trim().isEmpty) return false;
    return !_turnPersisted(state, turns);
  }

  /// What a running turn looks like: one line that says what it is doing, and
  /// the steps behind a tap.
  ///
  /// The steps used to be on screen the whole time, which made the panel a
  /// debugger — every click, every receipt, always. A chat shows what the
  /// assistant is doing and gets out of the way; the detail is one tap deep for
  /// the people who want it.
  List<Widget> _buildLiveBlock(AgentState state) {
    final isDark = _isDarkTheme;
    final turns = _conversation?.turns ?? const <AgentTurn>[];
    // Once written, the turn block above renders this run, steps and all. Two
    // copies of one answer is the thing a chat never does.
    if (_turnPersisted(state, turns)) return const [];
    final running = state.isRunning || state.status == AgentStatus.paused;

    return [
      // While it runs: what it is doing. After it finished: the same row, but
      // as a way into the steps, because the answer is already below it.
      if (running)
        _buildProgressRow(state, expanded: _liveDetailsOpen)
      else if (state.logs.isNotEmpty)
        _buildStepsToggle(state, expanded: _liveDetailsOpen),
      if (_liveDetailsOpen && state.logs.isNotEmpty) ...[
        const SizedBox(height: AppSpace.x2),
        StepLogView(logs: state.logs),
      ],
      // The answer is not a finished turn yet: show it here, where it happened.
      if (state.status == AgentStatus.completed && _hasResultCard(state)) ...[
        const SizedBox(height: AppSpace.x3),
        _buildResultCard(
          state: state,
          isDark: isDark,
          surface: AppInk.sunken(isDark),
          hairline: AppInk.hairline(isDark),
          onSurface: AppInk.primary(isDark),
          muted: AppInk.secondary(isDark),
        ),
      ],
      const SizedBox(height: AppSpace.x3),
    ];
  }

  /// The one line a run deserves while it runs.
  ///
  /// One tap opens the same timeline the finished turn keeps: same data, same
  /// order, just not in the user's face while it is being produced.
  Widget _buildProgressRow(AgentState state, {required bool expanded}) {
    final isDark = _isDarkTheme;
    final meta = _statusMeta(state.status);
    final running = state.isRunning || state.status == AgentStatus.paused;
    final label = _progressLabel(state);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state.logs.isEmpty
            ? null
            : () {
                HapticService.selection();
                setState(() => _liveDetailsOpen = !expanded);
              },
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
          child: Row(
            children: [
              _StateDot(color: meta.color, running: running),
              const SizedBox(width: AppSpace.x2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(
                    color: AppInk.secondary(isDark),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (state.logs.isNotEmpty) ...[
                const SizedBox(width: AppSpace.x1),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppInk.tertiary(isDark),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The finished-run version of the same row: no verbs, just an invitation.
  Widget _buildStepsToggle(AgentState state, {required bool expanded}) {
    final isDark = _isDarkTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticService.selection();
          setState(() => _liveDetailsOpen = !expanded);
        },
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
          child: Row(
            children: [
              Text(
                '查看执行过程',
                style: AppType.caption.copyWith(
                  color: AppInk.tertiary(isDark),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppInk.tertiary(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _progressLabel(AgentState state) {
    final latestAction = state.logs
        .where((log) => log.kind == LogKind.action)
        .lastOrNull
        ?.title;
    return switch (state.status) {
      AgentStatus.observing => '正在读取页面…',
      AgentStatus.thinking => state.streamingText.trim().isNotEmpty
          ? '正在思考：${state.streamingText.trim()}'
          : '正在思考…',
      AgentStatus.executing => latestAction != null && latestAction.isNotEmpty
          ? latestAction
          : '正在操作页面…',
      AgentStatus.waitingConfirmation => '等待你的授权…',
      AgentStatus.waitingCaptcha => '等待你完成人机验证…',
      AgentStatus.paused => '已暂停',
      AgentStatus.completed => '已完成',
      AgentStatus.error => '出错了',
      AgentStatus.idle => '没有在运行',
    };
  }

  /// The record and the live state describe the same run once it finishes.
  /// The record wins, because it survives the panel.
  bool _turnPersisted(AgentState state, List<AgentTurn> turns) {
    // An active run never yields to an older identical prompt in history.
    if (state.isRunning || state.status == AgentStatus.paused) return false;
    if (turns.isEmpty) return false;
    final latest = turns.last;
    if (latest.message.trim() != state.goal.trim()) return false;
    final startedAt = widget.taskStartedAt;
    if (startedAt == null) return true;
    return !latest.endedAt.isBefore(startedAt);
  }

  Widget _buildEmptyChat() {
    final isDark = _isDarkTheme;
    final subtle = AppInk.tertiary(isDark);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x6, bottom: AppSpace.x4),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppInk.accentTint(isDark),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 22,
              color: AppTheme.primaryOf(isDark),
            ),
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            '说一件要在这台浏览器里做的事',
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: AppInk.secondary(isDark)),
          ),
          const SizedBox(height: AppSpace.x1),
          Text(
            '之后可以接着追问：它会记得刚才点了什么、看到了什么',
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: subtle, height: 1.5),
          ),
        ],
      ),
    );
  }
  Widget _buildCaptchaBanner({
    required AgentState state,
    required bool isDark,
    required Color muted,
  }) {
    final warnInk = AppTheme.warningOf(isDark);
    return Container(
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: warnInk.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: warnInk.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: warnInk, size: 15),
              const SizedBox(width: AppSpace.x2 - 2),
              Expanded(
                child: Text(
                  state.captchaType == null
                      ? '需要人机验证'
                      : '需要人机验证 · ${state.captchaType}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(
                    color: warnInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x1),
          Text(
            '请在上方网页完成验证，然后点击「我已完成验证」。',
            style: AppType.caption.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: AppSpace.x3 - 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => widget.onConfirmCaptcha(false),
                style: TextButton.styleFrom(
                  foregroundColor: muted,
                  minimumSize: const Size(0, AppSpace.tap),
                  textStyle: AppType.label,
                ),
                child: const Text('中止任务'),
              ),
              const SizedBox(width: AppSpace.x1),
              FilledButton(
                onPressed: () => widget.onConfirmCaptcha(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.warning,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, AppSpace.tap),
                  textStyle: AppType.label,
                ),
                child: const Text('我已完成验证'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
