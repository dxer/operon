part of '../agent_bottom_sheet.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The answer card: what the model said, and how to take it away.

extension _SheetResult on _AgentBottomSheetState {
  bool _hasResultCard(AgentState state) {
    if (state.currentThought.trim().isNotEmpty) return true;
    return state.status == AgentStatus.completed ||
        state.status == AgentStatus.error ||
        state.status == AgentStatus.maxStepsReached;
  }

  String _resultText(AgentState state) {
    // A failure explains itself: the model's last thought is stale by then, and
    // "see the logs" makes the user dig for the one sentence that matters.
    final error = state.errorMessage?.trim() ?? '';
    if (error.isNotEmpty &&
        (state.status == AgentStatus.error ||
            state.status == AgentStatus.maxStepsReached)) {
      return error;
    }
    final thought = state.currentThought.trim();
    if (thought.isNotEmpty) return thought;
    switch (state.status) {
      case AgentStatus.completed:
        return '任务已完成。';
      case AgentStatus.error:
        return '任务执行失败，请查看日志。';
      case AgentStatus.maxStepsReached:
        return '已达到步数上限，任务已停止。';
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

  Widget _smallAction({
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
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sage = AppTheme.accentOf(isDark);
    final ochre = AppTheme.warningOf(isDark);
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
      case AgentStatus.maxStepsReached:
        color = ochre;
        icon = Icons.timer_outlined;
        title = '达到步数上限';
        break;
      default:
        color = copper;
        finished = false;
        icon = Icons.auto_awesome_rounded;
        title = 'AI 思路';
        break;
    }

    final text = _resultText(state);
    const secondary = '';
    final maxLines = finished ? 3 : 2;
    final needsToggle = text.length > (finished ? 84 : 56) ||
        text.split('\n').length > maxLines;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: color,
                ),
              ),
              const Spacer(),
              if (state.currentStep > 0)
                Text(
                  finished
                      ? '共 ${state.currentStep} 步'
                      : '第 ${state.currentStep}/${state.maxSteps} 步',
                  style: TextStyle(fontSize: 10.5, color: muted),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            text,
            maxLines: _resultExpanded ? null : maxLines,
            overflow:
                _resultExpanded ? TextOverflow.clip : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: onSurface.withValues(alpha: 0.88),
            ),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.4, color: muted),
            ),
          ],
          if (needsToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => setState(() => _resultExpanded = !_resultExpanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    _resultExpanded ? '收起' : '展开',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
              ),
            ),
          if (finished) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _smallAction(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  color: muted,
                  onTap: _copyResult,
                ),
                _smallAction(
                  icon: Icons.ios_share_rounded,
                  label: '分享',
                  color: muted,
                  onTap: _shareResult,
                ),
                if (state.logs.isNotEmpty)
                  _smallAction(
                    icon: Icons.subject_rounded,
                    label: _showLogs ? '收起日志' : '日志 ${state.logs.length}',
                    color: muted,
                    onTap: () => setState(() => _showLogs = !_showLogs),
                  ),
                // What this run cost. A user who cannot see it cannot decide
                // whether the task was worth running again.
                if (state.promptTokens + state.completionTokens > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${_tokens(state.promptTokens)} 输入 · '
                      '${_tokens(state.completionTokens)} 输出 token',
                      style: TextStyle(fontSize: 10.5, color: muted),
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
