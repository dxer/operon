part of '../agent_bottom_sheet.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The answer card: what the model concluded, and how to take it away.

extension _SheetResult on _AgentBottomSheetState {
  bool _hasResultCard(AgentState state) {
    if (state.currentThought.trim().isNotEmpty) return true;
    return state.status == AgentStatus.completed ||
        state.status == AgentStatus.error;
  }

  String _resultText(AgentState state) {
    // A failure explains itself: the model's last thought is stale by then, and
    // "see the logs" makes the user dig for the one sentence that matters.
    final error = state.errorMessage?.trim() ?? '';
    if (error.isNotEmpty && state.status == AgentStatus.error) return error;
    final thought = state.currentThought.trim();
    if (thought.isNotEmpty) return thought;
    switch (state.status) {
      case AgentStatus.completed:
        return '任务已完成。';
      case AgentStatus.error:
        return '任务执行失败，请查看日志。';
      default:
        return '';
    }
  }

  void _copyResult() {
    final text = _resultText(widget.state);
    if (text.isEmpty) return;
    HapticService.selection();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制任务结果')),
    );
  }

  /// 1234 → 1.2k, so a long run stays one glance wide.
  String _tokens(int value) {
    if (value < 1000) return '$value';
    return '${(value / 1000).toStringAsFixed(1)}k';
  }

  /// The result goes out as text, not as a file: every target a phone offers
  /// (chat, mail, notes) takes text, and a .md attachment would be unreadable
  /// in most of them.
  Future<void> _shareResult() async {
    final text = _resultText(widget.state);
    if (text.isEmpty) return;
    HapticService.selection();
    final shared = await const ShareService().shareText(
      text,
      subject: widget.state.goal.isEmpty ? null : widget.state.goal,
    );
    if (!shared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台设备没有可用的分享目标，可以改用复制')),
      );
    }
  }

  /// A text action on the result row. 44dp tall so the row is thumb-sized
  /// without looking like a toolbar of buttons.
  Widget _resultAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpace.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: AppSpace.x1),
                Text(label, style: AppType.label.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required AgentState state,
    required bool isDark,
    required Color surface,
    required Color hairline,
    required Color onSurface,
    required Color muted,
  }) {
    final sage = AppTheme.accentOf(isDark);
    final brick = AppTheme.dangerOf(isDark);
    final copper = AppTheme.primaryOf(isDark);

    late Color color;
    late IconData icon;
    late String title;
    var finished = true;
    switch (state.status) {
      case AgentStatus.completed:
        color = sage;
        icon = Icons.check_circle_rounded;
        title = '任务结果';
        break;
      case AgentStatus.error:
        color = brick;
        icon = Icons.error_outline_rounded;
        title = '执行异常';
        break;
      default:
        color = copper;
        finished = false;
        icon = Icons.auto_awesome_rounded;
        title = '当前思路';
        break;
    }

    final text = _resultText(state);
    final maxLines = finished ? 3 : 2;
    final needsToggle = text.length > (finished ? 84 : 56) ||
        text.split('\n').length > maxLines;
    final hasTokens = state.promptTokens + state.completionTokens > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: AppSpace.x2 - 2),
              Text(
                title,
                style: AppType.label.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x1 + 2),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _resultExpanded ? double.infinity : maxLines * 22.0,
            ),
            child: ClipRect(
              child: MarkdownAnswer(
                text,
                onOpenLink: widget.onOpenLink,
                baseStyle: AppType.body.copyWith(
                  height: 1.5,
                  color: onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          if (needsToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => setState(() => _resultExpanded = !_resultExpanded),
                borderRadius: BorderRadius.circular(AppRadius.chip - 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    _resultExpanded ? '收起' : '展开',
                    style: AppType.label.copyWith(color: color),
                  ),
                ),
              ),
            ),
          if (finished) ...[
            const SizedBox(height: AppSpace.x1 + 2),
            // One row: what you can do on the left, what it cost on the right.
            // A run that hides its price is a run nobody dares repeat.
            Row(
              children: [
                _resultAction(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  color: muted,
                  onTap: _copyResult,
                ),
                _resultAction(
                  icon: Icons.ios_share_rounded,
                  label: '分享',
                  color: muted,
                  onTap: _shareResult,
                ),
                const Spacer(),
                if (hasTokens)
                  Text(
                    '${_tokens(state.promptTokens)} / '
                    '${_tokens(state.completionTokens)} token',
                    style: AppType.micro.copyWith(
                      color: AppInk.tertiary(isDark),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
