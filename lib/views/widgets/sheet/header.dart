part of '../agent_bottom_sheet.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The one row at the top: state, safety, and the menu behind it.

extension _SheetHeader on _AgentBottomSheetState {
  void _toggleSafeMode(bool enabled) {
    HapticService.selection();
    setState(() => _safeMode = enabled);
    widget.onSafeModeChanged(enabled);
  }

  /// One chip carries both the agent state and the site it operates on, so the
  /// header keeps a single line of context instead of three competing pills.
  Widget _buildStatusChip(AgentState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = _statusMeta(state.status);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final host = _pageHost;
    final running = state.status == AgentStatus.observing ||
        state.status == AgentStatus.thinking ||
        state.status == AgentStatus.executing ||
        state.status == AgentStatus.paused;

    return Tooltip(
      message: host == null ? '当前在起始页，AI 会按指令打开网页' : 'AI 将在这个站点上操作\n$host',
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, size: 13, color: meta.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                meta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: meta.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (running && widget.taskStartedAt != null) ...[
              const SizedBox(width: 6),
              ElapsedLabel(
                startedAt: widget.taskStartedAt!,
                color: meta.color.withValues(alpha: 0.72),
                fontSize: 10.5,
              ),
            ],
            Container(
              width: 1,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: hairline,
            ),
            Icon(
              host == null ? Icons.public_off : Icons.language,
              size: 11,
              color: onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                host == null ? '起始页' : compactHost(host),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: onSurface.withValues(alpha: 0.66),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeModeChip({bool showLabel = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sage = AppTheme.accentOf(isDark);
    final ochre = AppTheme.warningOf(isDark);
    final fg = _safeMode ? sage : ochre;
    return Tooltip(
      message: _safeMode ? '敏感操作需要人工确认，点击切换为全自动' : '全自动模式，点击恢复人工确认',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleSafeMode(!_safeMode),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 8 : 6,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: fg.withValues(alpha: 0.35),
                width: 0.8,
              ),
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
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required AgentState state, required bool isRunning}) {
    // Status and site share one chip; logs live in the overflow menu, which
    // keeps the header to a single context line
    // instead of three competing pills.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildStatusChip(state),
                ),
              ),
              const SizedBox(width: 6),
              _buildSafeModeChip(),
              const SizedBox(width: 2),
              _buildOverflowMenu(state: state, isRunning: isRunning),
              // The panel slides up over the page, so it needs its own way out:
              // reaching for the scrim to close it is a guess.
              _buildCloseButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCloseButton() {
    final subtle = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
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
          child: Center(child: Icon(Icons.close_rounded, size: 18, color: subtle)),
        ),
      ),
    );
  }

  Widget _buildOverflowMenu({
    required AgentState state,
    required bool isRunning,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PopupMenuButton<_SheetAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      onSelected: (action) => _handleSheetAction(action, state: state),
      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      itemBuilder: (context) => [
        if (state.logs.isNotEmpty)
          PopupMenuItem(
            value: _SheetAction.logs,
            height: 42,
            child: _menuRow(
              Icons.subject_rounded,
              _showLogs ? '收起日志' : '日志 ${state.logs.length}',
            ),
          ),
        PopupMenuItem(
          value: _SheetAction.close,
          height: 42,
          child: _menuRow(Icons.close_rounded, '关闭面板'),
        ),
      ],
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 20,
          color: onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 16, color: onSurface.withValues(alpha: 0.62)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }

  Future<void> _handleSheetAction(
    _SheetAction action, {
    required AgentState state,
  }) async {
    switch (action) {
      case _SheetAction.logs:
        setState(() => _showLogs = !_showLogs);
        return;
      case _SheetAction.close:
        if (!mounted) return;
        await Navigator.of(context).maybePop();
        return;
    }
  }
}
