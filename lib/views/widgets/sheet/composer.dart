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

  /// Saved prompts to offer while the composer starts with "/".
  List<AgentPrompt> _promptMatches() {
    final text = _goalController.text;
    if (!text.startsWith('/')) return const [];
    final query = text.substring(1);
    if (query.contains(' ')) return const [];
    return widget.prompts.where((prompt) => prompt.matches(query)).take(4).toList();
  }

  void _usePrompt(AgentPrompt prompt) {
    HapticService.selection();
    _goalController.text = prompt.goal;
    _goalController.selection =
        TextSelection.collapsed(offset: prompt.goal.length);
    _goalFocus.requestFocus();
    setState(() {});
  }

  /// Picks one file and keeps it on the task. Cancelling the picker is not an
  /// error and says nothing.
  Future<void> _attachFile() async {
    if (_isPickingAttachment) return;
    HapticService.selection();
    setState(() => _isPickingAttachment = true);
    try {
      final pick = await AttachmentReader.pick();
      if (!mounted) return;
      if (pick.cancelled) return;
      final attachment = pick.attachment;
      if (attachment == null) {
        _say(pick.message ?? '无法读取这个文件');
        return;
      }
      if (attachment.isImage && !widget.imageAttachmentsEnabled) {
        _say('这个模型不支持图片输入，请先在 设置 → 模型能力 里打开「图片输入」');
        return;
      }
      setState(() => _attachments.add(attachment));
    } finally {
      if (mounted) setState(() => _isPickingAttachment = false);
    }
  }

  void _detachFile(AgentAttachment attachment) {
    HapticService.selection();
    setState(() => _attachments.remove(attachment));
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// The files riding with this task, each removable before it starts.
  Widget _buildAttachmentStrip({required Color subtle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final attachment in _attachments)
            InputChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                attachment.isImage
                    ? Icons.image_outlined
                    : Icons.description_outlined,
                size: 14,
                color: subtle,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              onDeleted: () => _detachFile(attachment),
              deleteIcon: const Icon(Icons.close_rounded, size: 13),
            ),
        ],
      ),
    );
  }

  void _startGoal() {
    final text = _goalController.text.trim();
    // An attachment with no instruction is still a question ("这张图是什么"),
    // but the text tells the model what to do with it.
    if (text.isEmpty) return;
    // A task is single-use: the composer starts clean after dispatch.
    final attachments = List<AgentAttachment>.unmodifiable(_attachments);
    _goalController.clear();
    setState(() {
      _resultExpanded = false;
      _attachments.clear();
    });
    widget.onStart(text, attachments);
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

  Widget _buildPromptStrip({required Color subtle}) {
    final matches = _promptMatches();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final prompt in matches)
            InkWell(
              onTap: () => _usePrompt(prompt),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: subtle),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        prompt.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
                      IconButton(
                        tooltip: widget.imageAttachmentsEnabled ? '添加附件' : '添加文本附件',
                        icon: _isPickingAttachment
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 1.6),
                              )
                            : Icon(Icons.attach_file_rounded, size: 19, color: subtle),
                        onPressed: _isPickingAttachment ? null : _attachFile,
                      ),
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
