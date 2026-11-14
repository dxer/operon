part of '../agent_bottom_sheet.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The field at the bottom, its suggestions and the draft it protects.

extension _SheetComposer on _AgentBottomSheetState {
  void _syncDraftState() {
    final hasDraft = _goalController.text.trim().isNotEmpty;
    if (hasDraft == _hasDraft || !mounted) return;
    // Only rebuild when the composer crosses the empty boundary: this keeps
    // the dismiss guard accurate without rebuilding the sheet per keystroke.
    setState(() => _hasDraft = hasDraft);
  }

  Future<void> _confirmDiscardDraft() async {
    if (_discardDialogOpen) return;
    _discardDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃当前输入？'),
        content: const Text('关闭面板后，已输入的指令不会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _startGoal() {
    final text = _goalController.text.trim();
    if (text.isEmpty) return;
    // A task is single-use: the composer starts clean after dispatch.
    _goalController.clear();
    setState(() {
      _resultExpanded = false;
    });
    widget.onStart(text);
  }

  void _clearGoal() {
    HapticService.selection();
    _goalController.clear();
    setState(() {});
  }

  /// Fills the composer rather than sending immediately: a suggestion should
  /// never start a paid task the user did not explicitly confirm.
  void _useExample(_ExampleGoal example) {
    HapticService.selection();
    _goalController.text = example.goal;
    _goalController.selection =
        TextSelection.collapsed(offset: example.goal.length);
    _goalFocus.requestFocus();
  }

  Widget _buildExamples({
    required Color surface,
    required Color hairline,
    required Color subtle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '试试',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: subtle,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final example in _exampleGoals)
              ActionChip(
                label: Text(
                  example.label,
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () => _useExample(example),
                backgroundColor: surface,
                side: BorderSide(color: hairline),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoalField({
    required bool isRunning,
    required Color subtle,
  }) {
    final finished = !isRunning &&
        (widget.state.status == AgentStatus.completed ||
            widget.state.status == AgentStatus.error ||
            widget.state.status == AgentStatus.maxStepsReached);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _goalController,
      focusNode: _goalFocus,
      enabled: !isRunning,
      maxLines: 3,
      minLines: 1,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _startGoal(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: finished ? '继续追问，或开始新任务…' : '描述你想让 AI 做的事…',
        hintStyle: TextStyle(fontSize: 12, color: subtle),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 44,
        ),
        suffixIcon: isRunning
            ? null
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: _goalController,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (value.text.isNotEmpty)
                        IconButton(
                          tooltip: '清空输入',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: subtle,
                          ),
                          onPressed: _clearGoal,
                        ),
                      IconButton(
                        tooltip: canSend ? '开始任务' : '请输入指令',
                        icon: Icon(
                          Icons.arrow_upward,
                          color: canSend ? AppTheme.primaryOf(isDark) : subtle,
                        ),
                        onPressed: canSend ? _startGoal : null,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
