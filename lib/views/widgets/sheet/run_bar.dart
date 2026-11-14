part of '../agent_bottom_sheet.dart';

// What replaces the composer while a run needs the thumb area.

extension _SheetRunBar on _AgentBottomSheetState {
  /// Fixed bottom control bar while a task runs.
  Widget _buildRunBar({
    required AgentState state,
    required Color surface,
    required Color hairline,
    required Color onSurface,
    required Color muted,
  }) {
    final paused = state.status == AgentStatus.paused;
    final waiting = state.status == AgentStatus.waitingConfirmation ||
        state.status == AgentStatus.waitingCaptcha;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = paused || waiting
        ? AppTheme.warningOf(isDark)
        : AppTheme.primaryOf(isDark);
    final goal = state.goal.trim();
    final label = goal.isEmpty
        ? (paused
            ? '已暂停'
            : waiting
                ? '等待你的操作'
                : '正在执行')
        : goal;

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
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.86),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${state.currentStep}/${state.maxSteps}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: muted,
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
