part of '../agent_bottom_sheet.dart';

// What replaces the composer while a run needs the thumb area.

extension _SheetRunBar on _AgentBottomSheetState {
  /// Fixed bottom control bar while a task runs.
  Widget _buildRunBar({required AgentState state}) {
    final isDark = _isDarkTheme;
    final surface = AppInk.sunken(isDark);
    final hairline = AppInk.hairline(isDark);
    final onSurface = AppInk.primary(isDark);
    final paused = state.status == AgentStatus.paused;
    final waiting = state.status == AgentStatus.waitingConfirmation ||
        state.status == AgentStatus.waitingCaptcha;
    final accent = paused || waiting
        ? AppTheme.warningOf(isDark)
        : AppTheme.primaryOf(isDark);
    final label = paused
        ? '已暂停 · 点继续回到这一步'
        : waiting
            ? '等待你的操作'
            : '正在执行…';
    // Where the run actually is, not just that it is running: the page is the
    // half of the task the panel covers.
    final host = hostOf(state.targetUrl ?? widget.currentUrl ?? '');
    final running = host.isEmpty
        ? label
        : (paused || waiting ? label : '正在 ${compactHost(host)} 操作…');

    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Row(
        children: [
          Icon(
            paused
                ? Icons.pause_circle_outline_rounded
                : waiting
                    ? Icons.shield_outlined
                    : Icons.bolt_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              running,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(color: onSurface),
            ),
          ),
          // No pause button. Stopping a run half-way through a form is the
          // thing this bar exists to do; pausing it left the page in a
          // half-filled state with nothing on screen explaining why. The one
          // pause that remains is involuntary — the app going to the
          // background with "后台继续执行" off — and for that the bar offers
          // its way back.
          if (paused)
            IconButton(
              tooltip: '继续',
              onPressed: widget.onResume,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              color: accent,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          IconButton(
            tooltip: '停止运行',
            onPressed: widget.onStop,
            icon: const Icon(Icons.stop_rounded, size: 20),
            color: AppTheme.dangerOf(_isDarkTheme),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}
