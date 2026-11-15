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

  /// Built-in system slash commands matching the current "/" query.
  List<BuiltinSlashCommand> _builtinMatches() {
    final text = _goalController.text;
    if (!text.startsWith('/')) return const [];
    final query = text.substring(1);
    if (query.contains(' ')) return const [];
    return builtinSlashCommands.where((cmd) => cmd.matches(query)).toList();
  }

  /// Saved prompts to offer while the composer starts with "/".
  List<AgentPrompt> _promptMatches() {
    final text = _goalController.text;
    if (!text.startsWith('/')) return const [];
    final query = text.substring(1);
    if (query.contains(' ')) return const [];
    return widget.prompts.where((prompt) => prompt.matches(query)).take(4).toList();
  }

  void _useBuiltinCommand(BuiltinSlashCommand command) {
    HapticService.selection();
    final filled = '/${command.name} ';
    _goalController.text = filled;
    _goalController.selection = TextSelection.collapsed(offset: filled.length);
    _goalFocus.requestFocus();
    setState(() {});
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
    // A message always belongs to a conversation. Without one, this is the
    // first: create it now so the panel has somewhere to write the answer.
    // A missing store is not a missing conversation: the sheet still has to
    // send, and the parent can still keep the id.
    final store = widget.store;
    var id = _activeId;
    if (store != null && (id == null || store.byId(id) == null)) {
      id = store.create().id;
      _activeId = id;
      widget.onConversationChanged?.call(id);
    }
    widget.onStart(id ?? '', text, attachments);
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

  /// Suggestions only while the conversation is still empty: once it has a
  /// turn, the history is the suggestion.
  bool get _showsExamples =>
      !_isTaskActive &&
      widget.state.status == AgentStatus.idle &&
      widget.state.logs.isEmpty &&
      !_hasDraft &&
      (_conversation?.turns.isEmpty ?? true);

  List<_ExampleGoal> get _exampleGoals => _pageHost == null
      ? const [
          _ExampleGoal(
            '搜索并总结',
            '打开 Bing 搜索「Flutter 3.35 发布说明」，打开第一条结果，总结更新要点',
          ),
          _ExampleGoal(
            '网页转表格',
            '打开 GitHub Trending，把前 5 个项目整理成表格，'
                '包含项目名、语言和今日新增 star',
          ),
          _ExampleGoal(
            '填表查资料',
            '打开维基百科，搜索「Alan Turing」，告诉我他的出生日期和主要贡献',
          ),
        ]
      : const [
          _ExampleGoal('总结这一页', '总结这一页的主要内容，并列出 3 个关键结论'),
          _ExampleGoal(
            '提取列表',
            '把当前页面的列表提取成表格，缺失的字段直接标出来',
          ),
          _ExampleGoal(
            '继续深入',
            '找出当前页面里最值得继续点进去的 3 个链接，并说明理由',
          ),
        ];

  /// The bottom of the chat: suggestions while it is empty, attachments,
  /// saved prompts, the field itself.
  Widget _buildComposer({required AgentState state}) {
    final isDark = _isDarkTheme;
    final surface = AppInk.sunken(isDark);
    final hairline = AppInk.hairline(isDark);
    final subtle = AppInk.tertiary(isDark);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Collapsing must not make the composer jump while the user is typing.
        AnimatedSize(
          duration: MediaQuery.maybeDisableAnimationsOf(context) == true
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: _showsExamples
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildExamples(
                    surface: surface,
                    hairline: hairline,
                    subtle: subtle,
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        if (_attachments.isNotEmpty) _buildAttachmentStrip(subtle: subtle),
        // Rebuilt on every keystroke: the strip appears the moment the field
        // starts with "/".
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _goalController,
          builder: (context, _, __) => _buildPromptStrip(subtle: subtle),
        ),
        _buildGoalField(isRunning: state.isRunning, subtle: subtle),
        if (_pageHost == null) ...[
          const SizedBox(height: 4),
          Text(
            '当前是起始页；可直接在指令里写要打开的网址或搜索目标',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: subtle),
          ),
        ],
      ],
    );
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
    final builtins = _builtinMatches();
    final matches = _promptMatches();
    if (builtins.isEmpty && matches.isEmpty) return const SizedBox.shrink();
    final isDark = _isDarkTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final command in builtins)
            InkWell(
              onTap: () => _useBuiltinCommand(command),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.compress_rounded,
                      size: 14,
                      color: AppTheme.primaryOf(isDark),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      command.label,
                      style: AppType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppInk.primary(isDark),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        command.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: subtle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final prompt in matches)
            InkWell(
              onTap: () => _usePrompt(prompt),
              borderRadius: BorderRadius.circular(AppRadius.chip),
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
                        style: AppType.caption,
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
            widget.state.status == AgentStatus.error);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppInk.sunken(isDark);
    final hairline = AppInk.hairline(isDark);
    final primary = AppTheme.primaryOf(isDark);

    return ListenableBuilder(
      listenable: _goalFocus,
      builder: (context, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.card + 2),
          border: Border.all(
            color: _goalFocus.hasFocus
                ? primary.withValues(alpha: 0.55)
                : hairline,
          ),
        ),
        child: child,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _goalController,
            focusNode: _goalFocus,
            enabled: !isRunning,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _startGoal(),
            style: AppType.body.copyWith(color: AppInk.primary(isDark)),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              hintText: finished ? '继续追问，或开始新任务…' : '描述你想让 AI 做的事…',
              hintStyle: AppType.label.copyWith(color: subtle),
            ),
          ),
          if (!isRunning)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _goalController,
              builder: (context, value, _) {
                final hasText = value.text.isNotEmpty;
                final canSend = value.text.trim().isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 8, 6),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip:
                            widget.imageAttachmentsEnabled ? '添加附件' : '添加文本附件',
                        icon: _isPickingAttachment
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 1.6),
                              )
                            : Icon(
                                Icons.attach_file_rounded,
                                size: 19,
                                color: subtle,
                              ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 38,
                          minHeight: 36,
                        ),
                        onPressed: _isPickingAttachment ? null : _attachFile,
                      ),
                      if (!hasText)
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: () {
                            HapticService.selection();
                            _goalController.text = '/';
                            _goalController.selection =
                                const TextSelection.collapsed(offset: 1);
                            _goalFocus.requestFocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded, size: 14, color: subtle),
                                const SizedBox(width: 2),
                                Text(
                                  '指令',
                                  style: AppType.caption.copyWith(color: subtle),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (hasText)
                        IconButton(
                          tooltip: '清空输入',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: subtle,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: _clearGoal,
                        ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: canSend ? '开始任务' : '请输入指令',
                        child: Material(
                          color: canSend
                              ? primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06)),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: canSend ? _startGoal : null,
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.arrow_upward,
                                size: 18,
                                color: canSend
                                    ? (isDark ? Colors.black : Colors.white)
                                    : subtle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
