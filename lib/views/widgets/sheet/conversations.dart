part of '../agent_bottom_sheet.dart';

// These extensions are on this State, in this library, and always run inside
// the widget that owns it.
// ignore_for_file: invalid_use_of_protected_member

// The first screen of the panel: what the user was doing. A chat that reopens
// as a blank form is a chat that forgets, and forgetting is what this whole
// change is about.

extension _SheetConversations on _AgentBottomSheetState {
  /// Opens a stored conversation, or starts one that only exists in memory
  /// until its first message.
  void _openConversation(String id) {
    setState(() => _activeId = id);
    widget.onConversationChanged?.call(id);
  }

  void _backToList() {
    setState(() => _activeId = null);
    widget.onConversationChanged?.call(null);
    unawaited(widget.store?.pruneEmpty() ?? Future<void>.value());
  }

  /// A new chat: created now so the composer knows where to write, listed only
  /// once it has a message.
  void _startNewConversation() {
    final store = widget.store;
    if (store == null) {
      // No store yet (it opens asynchronously): the list is the honest answer.
      return;
    }
    final conversation = store.create();
    setState(() => _activeId = conversation.id);
    widget.onConversationChanged?.call(conversation.id);
  }

  Widget _buildConversationList() {
    final isDark = _isDarkTheme;
    final items = _conversations;

    if (items.isEmpty) return _buildEmptyList(isDark);

    return ListView.separated(
      controller: _bodyScroll,
      padding: EdgeInsets.only(
        top: AppSpace.x1,
        bottom: AppSpace.x4 + MediaQuery.of(context).viewPadding.bottom,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: AppSpace.page + 44 + AppSpace.x3,
        endIndent: AppSpace.page,
        color: AppInk.hairline(isDark),
      ),
      itemBuilder: (context, index) =>
          _buildConversationTile(items[index], isDark),
    );
  }

  Widget _buildConversationTile(AgentConversation conversation, bool isDark) {
    final active = conversation.id == _activeId;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticService.selection();
          _openConversation(conversation.id);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            AppSpace.x3,
            AppSpace.x1,
            AppSpace.x3,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active
                      ? AppInk.accentTint(isDark)
                      : AppInk.sunken(isDark),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: active
                      ? AppTheme.primaryOf(isDark)
                      : AppInk.secondary(isDark),
                ),
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        color: AppInk.primary(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conversation.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppInk.tertiary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.x2),
              Text(
                _conversationTime(conversation.updatedAt),
                style: AppType.caption.copyWith(
                  color: AppInk.tertiary(isDark),
                ),
              ),
              _buildConversationMenu(conversation, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationMenu(AgentConversation conversation, bool isDark) {
    return PopupMenuButton<String>(
      tooltip: '会话操作',
      padding: EdgeInsets.zero,
      color: AppInk.raised(isDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppInk.hairline(isDark)),
      ),
      onSelected: (action) {
        if (action == 'rename') _askRename(conversation);
        if (action == 'delete') _askDelete(conversation);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          height: 42,
          child: _menuRow(Icons.edit_outlined, '重命名'),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 42,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: AppTheme.dangerOf(isDark),
              ),
              const SizedBox(width: AppSpace.x2),
              Text(
                '删除',
                style: AppType.label.copyWith(color: AppTheme.dangerOf(isDark)),
              ),
            ],
          ),
        ),
      ],
      child: SizedBox(
        width: AppSpace.tap,
        height: AppSpace.tap,
        child: Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: AppInk.tertiary(isDark),
        ),
      ),
    );
  }

  Widget _buildEmptyList(bool isDark) {
    return ListView(
      controller: _bodyScroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x8,
        AppSpace.page,
        AppSpace.x4,
      ),
      children: [
        Icon(
          Icons.forum_outlined,
          size: 26,
          color: AppInk.tertiary(isDark),
        ),
        const SizedBox(height: AppSpace.x3),
        Text(
          '还没有对话',
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(color: AppInk.secondary(isDark)),
        ),
        const SizedBox(height: AppSpace.x1),
        Text(
          '点右上角「新对话」，让 AI 在这台浏览器里做点什么',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(
            color: AppInk.tertiary(isDark),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Future<void> _askRename(AgentConversation conversation) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initial: conversation.displayTitle),
    );
    final trimmed = name?.trim() ?? '';
    if (!mounted || trimmed.isEmpty) return;
    await widget.store?.rename(conversation.id, trimmed);
    if (mounted) setState(() {});
  }

  Future<void> _askDelete(AgentConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段对话？'),
        content: Text(
          '「${conversation.displayTitle}」的 ${conversation.turns.length} 条消息会一起删除，'
          '无法恢复。',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await widget.store?.delete(conversation.id);
    if (!mounted) return;
    setState(() {
      if (_activeId == conversation.id) {
        _activeId = null;
        widget.onConversationChanged?.call(null);
      }
    });
  }

  String _conversationTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    String two(int value) => value.toString().padLeft(2, '0');
    if (diff == 0) return '${two(time.hour)}:${two(time.minute)}';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    if (time.year == now.year) return '${time.month}/${time.day}';
    return '${time.year}/${time.month}/${time.day}';
  }
}

/// The rename dialog owns its controller.
///
/// Creating one beside the `showDialog` call and disposing it on the line after
/// the await looks tidy and is wrong: the dialog's exit animation is still
/// rebuilding that TextField, which then reads a disposed controller.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名对话'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(
          hintText: '给这段对话起个名字',
          counterText: '',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
