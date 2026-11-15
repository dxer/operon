part of '../agent_bottom_sheet.dart';

// What replaces the composer while a run needs the thumb area.

extension _SheetRunBar on _AgentBottomSheetState {
  /// Fixed bottom control bar while a task runs.
  Widget _buildRunBar({required AgentState state}) {
    final isDark = _isDarkTheme;
    final surface = AppInk.sunken(isDark);
    final hairline = AppInk.hairline(isDark);
    final onSurface = AppInk.primary(isDark);
    final muted = AppInk.tertiary(isDark);
    final paused = state.status == AgentStatus.paused;
    final waiting = state.status == AgentStatus.waitingConfirmation ||
        state.status == AgentStatus.waitingCaptcha;
    final accent = paused || waiting
        ? AppTheme.warningOf(isDark)
        : AppTheme.primaryOf(isDark);
    // The message itself is already in the transcript above; repeating it in
    // the control bar was the old form's way of saying "this is what is
    // running". Here the bar says what the run is *doing*.
    final label = paused
        ? '已暂停 · 点继续回到这一步'
        : waiting
            ? '等待你的操作'
            : '正在执行…';

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
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(color: onSurface),
            ),
          ),
          IconButton(
            tooltip: paused ? '继续' : '暂停',
            onPressed:
                waiting ? null : (paused ? widget.onResume : widget.onPause),
            icon: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
            ),
            color: paused ? accent : muted,
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
