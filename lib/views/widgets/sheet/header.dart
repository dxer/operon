part of '../agent_bottom_sheet.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The fixed top of the panel. It used to scroll away with the content, which
// meant the close button and the "am I still in safe mode" chip disappeared
// exactly when a run got long — the two things you look for while it runs.

extension _SheetHeader on _AgentBottomSheetState {
  void _toggleSafeMode(bool enabled) {
    HapticService.selection();
    setState(() => _safeMode = enabled);
    widget.onSafeModeChanged(enabled);
  }

  Widget _buildSafeModeChip({bool showLabel = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = _safeMode ? AppTheme.accentOf(isDark) : AppTheme.warningOf(isDark);
    return Tooltip(
      message: _safeMode ? '敏感操作需要人工确认，点击切换为全自动' : '全自动模式，点击恢复人工确认',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => _toggleSafeMode(!_safeMode),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? AppSpace.x2 : 6,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _safeMode ? Icons.shield_outlined : Icons.bolt_rounded,
                  size: 13,
                  color: fg,
                ),
                if (showLabel) ...[
                  const SizedBox(width: 3),
                  Text(
                    _safeMode ? '人工授权' : '全自动',
                    style: AppType.micro.copyWith(color: fg),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The list screen's header: one job, start a new conversation.
  Widget _buildListHeader() {
    final isDark = _isDarkTheme;
    return Row(
      children: [
        Text(
          '对话',
          style: AppType.headline.copyWith(color: AppInk.primary(isDark)),
        ),
        const Spacer(),
        _buildNewChatButton(isDark),
        const SizedBox(width: AppSpace.x1),
        _buildCloseButton(),
      ],
    );
  }

  Widget _buildNewChatButton(bool isDark) {
    return TextButton.icon(
      onPressed: () {
        HapticService.selection();
        _startNewConversation();
      },
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('新对话'),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primaryOf(isDark),
        textStyle: AppType.label,
        minimumSize: const Size(0, AppSpace.tap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
      ),
    );
  }

  /// The chat screen's header: back to the list, this conversation's name, and
  /// the safety state — the three things that must not scroll away mid-run.
  Widget _buildChatHeader({
    required AgentState state,
    required bool isRunning,
  }) {
    final isDark = _isDarkTheme;
    final meta = _statusMeta(state.status);
    final host = _pageHost;
    final running = state.isRunning || state.status == AgentStatus.paused;
    final title = _conversation?.displayTitle ?? '新对话';

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: '返回对话列表',
                child: InkResponse(
                  onTap: () {
                    HapticService.selection();
                    _backToList();
                  },
                  radius: 20,
                  child: SizedBox(
                    width: 32,
                    height: AppSpace.tap,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 24,
                      color: AppInk.secondary(isDark),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  // Tapping the title is the shortest path to a rename, and the
                  // only affordance a chat needs for it.
                  onTap: () {
                    final conversation = _conversation;
                    if (conversation == null) return;
                    _askRename(conversation);
                  },
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.headline.copyWith(
                      color: AppInk.primary(isDark),
                    ),
                  ),
                ),
              ),
              _buildSafeModeChip(),
              _buildOverflowMenu(state: state, isRunning: isRunning),
              _buildCloseButton(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpace.x1,
              right: AppSpace.x2,
            ),
            child: Row(
              children: [
                _StateDot(color: meta.color, running: running),
                const SizedBox(width: 5),
                Text(
                  meta.label,
                  style: AppType.caption.copyWith(
                    color: meta.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: AppType.caption.copyWith(
                      color: AppInk.tertiary(isDark),
                    ),
                  ),
                ),
                Icon(
                  host == null ? Icons.public_off : Icons.language,
                  size: 12,
                  color: AppInk.tertiary(isDark),
                ),
                const SizedBox(width: AppSpace.x1),
                Expanded(
                  // The row shows the registrable domain; the full host is a
                  // long-press away rather than a second line.
                  child: Tooltip(
                    message: host == null
                        ? '当前在起始页，AI 会按指令打开网页'
                        : 'AI 将在这个站点上操作\n$host',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        host == null ? '起始页' : compactHost(host),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: AppInk.secondary(isDark),
                        ),
                      ),
                    ),
                  ),
                ),
                if (running && widget.taskStartedAt != null) ...[
                  const SizedBox(width: AppSpace.x2),
                  ElapsedLabel(
                    startedAt: widget.taskStartedAt!,
                    color: AppInk.tertiary(isDark),
                    fontSize: AppType.caption.fontSize!,
                  ),
                ],
              ],
            ),
          ),
          if (isRunning) ...[
            const SizedBox(height: AppSpace.x2),
            Semantics(
              label: '正在执行任务',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  // There is no step ceiling to fill a bar against any more,
                  // and a bar that lies about progress is worse than a pulse.
                  value: null,
                  minHeight: 2,
                  backgroundColor: AppInk.hairline(isDark),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryOf(isDark),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return Semantics(
      button: true,
      label: '关闭面板',
      child: InkResponse(
        onTap: () {
          HapticService.selection();
          Navigator.of(context).maybePop();
        },
        radius: 20,
        containedInkWell: true,
        highlightShape: BoxShape.circle,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppInk.tertiary(
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowMenu({
    required AgentState state,
    required bool isRunning,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<_SheetAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      onSelected: (action) => _handleSheetAction(action, state: state),
      color: AppInk.raised(isDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppInk.hairline(isDark)),
      ),
      itemBuilder: (context) => [
        if (_conversation != null) ...[
          PopupMenuItem(
            value: _SheetAction.rename,
            height: 42,
            child: _menuRow(Icons.edit_outlined, '重命名'),
          ),
          PopupMenuItem(
            value: _SheetAction.delete,
            height: 42,
            child: _menuRow(Icons.delete_outline_rounded, '删除对话'),
          ),
        ],
        PopupMenuItem(
          value: _SheetAction.close,
          height: 42,
          child: _menuRow(Icons.close_rounded, '关闭面板'),
        ),
      ],
      child: SizedBox(
        width: AppSpace.tap,
        height: AppSpace.tap,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 20,
          color: AppInk.secondary(isDark),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 16, color: AppInk.secondary(isDark)),
        const SizedBox(width: AppSpace.x2),
        Text(
          label,
          style: AppType.label.copyWith(color: AppInk.primary(isDark)),
        ),
      ],
    );
  }

  Future<void> _handleSheetAction(
    _SheetAction action, {
    required AgentState state,
  }) async {
    switch (action) {
      case _SheetAction.rename:
        final conversation = _conversation;
        if (conversation == null) return;
        await _askRename(conversation);
        return;
      case _SheetAction.delete:
        final conversation = _conversation;
        if (conversation == null) return;
        await _askDelete(conversation);
        return;
      case _SheetAction.close:
        if (!mounted) return;
        await Navigator.of(context).maybePop();
        return;
    }
  }
}

/// The state mark: a dot that breathes while the agent works.
class _StateDot extends StatefulWidget {
  const _StateDot({required this.color, required this.running});

  final Color color;
  final bool running;

  @override
  State<_StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<_StateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Built here, not lazily in the field initialiser: a `late final` that is
    // first touched in dispose() would create a ticker while the element is
    // already deactivated.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.running) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StateDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.running && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.running) {
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 0.45 → 1.0: alive without flashing. Anything faster reads as an
        // error state.
        final t = 0.45 + 0.55 * _controller.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: t * 0.35),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
