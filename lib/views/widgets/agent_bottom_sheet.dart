import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../agent/compactor.dart';
import '../../models/agent_attachment.dart';
import '../../models/agent_conversation.dart';
import '../../models/agent_prompt.dart';
import '../../models/agent_state.dart';
import '../../services/attachment_reader.dart';
import '../../services/conversation_store.dart';
import '../../services/haptic_service.dart';
import '../../services/share_service.dart';
import '../../utils/result_export.dart';
import '../../utils/url_utils.dart';
import 'agent_confirmation_card.dart';
import 'elapsed_label.dart';
import 'markdown_answer.dart';
import 'operon_card.dart';
import 'step_log_view.dart';
import 'extracted_data_sheet.dart';

part 'sheet/body.dart';
part 'sheet/conversations.dart';

part 'sheet/header.dart';
part 'sheet/result.dart';
part 'sheet/extracted.dart';
part 'sheet/composer.dart';
part 'sheet/run_bar.dart';

typedef AgentStartHandler = void Function(
  String conversationId,
  String goal,
  List<AgentAttachment> attachments,
);

enum _SheetAction { rename, delete, close }

/// A one-tap prompt suggestion shown in the empty conversation.
class _ExampleGoal {
  final String label;
  final String goal;

  const _ExampleGoal(this.label, this.goal);
}

/// The agent panel: a chat.
///
/// The first screen is the list of conversations, because that is the question
/// a returning user has — "what was I doing". Tapping one opens it, and the
/// panel stops being a form that runs a command and becomes a conversation that
/// continues: the agent already knows what it did two messages ago.
class AgentBottomSheet extends StatefulWidget {
  final AgentState state;
  final AgentStartHandler onStart;
  /// Only ever needed for a pause the app caused itself (backgrounded with
  /// "后台继续执行" off). There is no pause button left to ask for one.
  final VoidCallback onResume;
  final VoidCallback onStop;
  final Function(bool confirmed) onConfirmAction;
  final Function(bool passed) onConfirmCaptcha;
  final bool safeMode;
  final ValueChanged<bool> onSafeModeChanged;
  final VoidCallback? onAllowSite;

  /// URL of the tab the sheet was opened from, used to show the agent's
  /// current operating target.
  final String? currentUrl;

  /// When the current task started, so the header can show a live timer.
  final DateTime? taskStartedAt;

  /// A goal to put in the composer when the sheet opens, editable but not
  /// started: the user asked for this wording once and is about to ask again.
  final String? initialGoal;

  /// Whether this model takes images. Offering an image picker to a model that
  /// cannot read one wastes the user's time and their upload.
  final bool imageAttachmentsEnabled;

  /// Saved prompts, offered when the composer starts with "/".
  final List<AgentPrompt> prompts;

  /// Where conversations live. The panel owns the list screen, so it owns the
  /// store too: reopening the panel must show the conversation that was open,
  /// and a modal route cannot be rebuilt by its parent.
  final ConversationStore? store;

  /// Which conversation was open last time. Null shows the list.
  final String? conversationId;

  /// The turn the running task is writing into. It is drawn as the live block,
  /// so the store's copy of it must not be drawn as well.
  final String? liveTurnId;

  /// Told when the open conversation changes, so it survives a reopen.
  final ValueChanged<String?>? onConversationChanged;

  /// A link inside an answer: the browser the user is already in.
  final ValueChanged<String>? onOpenLink;

  /// Dragging the handle resizes the panel; nothing else does. Positive means
  /// "grow by this many logical pixels" — up is a negative drag, so the sign is
  /// already flipped for the frame.
  final ValueChanged<double>? onHandleDrag;

  /// The finger lifted: the frame settles on its nearest resting height.
  final VoidCallback? onHandleDragEnd;

  const AgentBottomSheet({
    super.key,
    required this.state,
    required this.onStart,
    required this.onResume,
    required this.onStop,
    required this.onConfirmAction,
    required this.onConfirmCaptcha,
    required this.safeMode,
    required this.onSafeModeChanged,
    this.onAllowSite,
    this.currentUrl,
    this.taskStartedAt,
    this.initialGoal,
    this.imageAttachmentsEnabled = true,
    this.prompts = const [],
    this.store,
    this.conversationId,
    this.liveTurnId,
    this.onConversationChanged,
    this.onOpenLink,
    this.onHandleDrag,
    this.onHandleDragEnd,
  });

  @override
  State<AgentBottomSheet> createState() => _AgentBottomSheetState();
}

class _AgentBottomSheetState extends State<AgentBottomSheet> {
  /// Brightness for one-off foreground tints outside a `build` scope.
  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;

  late TextEditingController _goalController;
  late bool _safeMode;
  bool _resultExpanded = false;

  /// Whether the running turn's steps are open. Closed by default: the point of
  /// the row above them is that a run is one line until asked otherwise.
  bool _liveDetailsOpen = false;
  bool _hasDraft = false;
  bool _isPickingAttachment = false;
  final List<AgentAttachment> _attachments = [];
  bool _discardDialogOpen = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _goalFocus = FocusNode();

  /// Which conversation is open. Null is the list screen.
  late String? _activeId;

  /// In the chat view the sheet scrolls the conversation, not the run.
  ScrollController get _bodyScroll => _scrollController;

  bool get _isTaskActive =>
      widget.state.isRunning || widget.state.status == AgentStatus.paused;

  List<AgentConversation> get _conversations =>
      widget.store?.conversations ?? const [];

  /// The conversation on screen, if any.
  AgentConversation? get _conversation => widget.store?.byId(_activeId);

  bool get _showsChat => _activeId != null;

  @override
  void initState() {
    super.initState();
    // The field is only ever for the *next* message. It used to be refilled
    // with the running goal, which in a chat means the message you just sent
    // sits in the input box until the answer arrives.
    _goalController = TextEditingController(
      text: (widget.initialGoal ?? '').trim(),
    );
    _hasDraft = _goalController.text.trim().isNotEmpty;
    _goalController.addListener(_syncDraftState);
    _safeMode = widget.safeMode;
    _activeId = widget.conversationId;
  }

  @override
  void didUpdateWidget(covariant AgentBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.safeMode != oldWidget.safeMode) {
      _safeMode = widget.safeMode;
    }
    if (widget.conversationId != oldWidget.conversationId &&
        widget.conversationId != _activeId) {
      _activeId = widget.conversationId;
    }
    // A confirmation or CAPTCHA card is pinned above the bottom bar while the
    // transcript sits above it; scroll to the bottom so the latest step stays
    // visible right next to the approval request.
    final becameWaiting = widget.state.status != oldWidget.state.status &&
        (widget.state.status == AgentStatus.waitingConfirmation ||
            widget.state.status == AgentStatus.waitingCaptcha);
    // A run that just ended is worth reading from its conclusion upwards, so
    // follow the newest line the way a chat does.
    final justFinished = oldWidget.state.isRunning && !widget.state.isRunning;
    if (becameWaiting || justFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_bodyScroll.hasClients) return;
        _scrollTo(_bodyScroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    // A conversation that never got a message is not worth a row in the list.
    unawaited(widget.store?.pruneEmpty() ?? Future<void>.value());
    _goalController.removeListener(_syncDraftState);
    _goalController.dispose();
    _scrollController.dispose();
    _goalFocus.dispose();
    super.dispose();
  }

  void _scrollTo(double target) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _bodyScroll.jumpTo(target);
    } else {
      _bodyScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Host of the tab the sheet was opened from; null means start page.
  String? get _pageHost => _hostOf(widget.currentUrl);

  /// The host of a URL, named the way the header shows it. Null for the start
  /// page and for anything that is not a web page.
  String? _hostOf(String? url) {
    if (url == null || url.isEmpty || url == 'about:blank') return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.scheme == 'operon') {
      return null;
    }
    var host = uri.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  ({Color color, String label, IconData icon}) _statusMeta(
    AgentStatus status,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final copper = AppTheme.primaryOf(isDark);
    final sage = AppTheme.accentOf(isDark);
    final ochre = AppTheme.warningOf(isDark);
    final brick = AppTheme.dangerOf(isDark);

    return switch (status) {
      AgentStatus.idle => (
          color: onSurface.withValues(alpha: 0.55),
          label: '待命',
          icon: Icons.stop_circle_outlined,
        ),
      AgentStatus.observing => (
          color: copper,
          label: '读取页面',
          icon: Icons.visibility_outlined,
        ),
      AgentStatus.thinking => (
          color: copper,
          label: '思考规划',
          icon: Icons.psychology_outlined,
        ),
      AgentStatus.executing => (
          color: copper,
          label: '执行中',
          icon: Icons.touch_app_outlined,
        ),
      AgentStatus.waitingConfirmation => (
          color: ochre,
          label: '等待授权',
          icon: Icons.security_outlined,
        ),
      AgentStatus.waitingCaptcha => (
          color: ochre,
          label: '等待验证',
          icon: Icons.verified_user_outlined,
        ),
      AgentStatus.paused => (
          color: ochre,
          label: '已暂停',
          icon: Icons.pause_circle_outline,
        ),
      AgentStatus.completed => (
          color: sage,
          label: '已完成',
          icon: Icons.check_circle_outline,
        ),
      AgentStatus.error => (
          color: brick,
          label: '执行异常',
          icon: Icons.error_outline,
        ),
    };
  }

  /// Fields of the first record; lists of primitives have no field names.
  List<MapEntry<String, dynamic>> _dataEntries(dynamic data) {
    dynamic record = data;
    if (data is List) {
      if (data.isEmpty) return const [];
      record = data.first;
    }
    if (record is Map) {
      return record.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isRunning = state.isRunning;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final horizontal =
        _showsChat ? 0.0 : AppSpace.page; // the list is full-bleed rows

    return PopScope(
      // Tapping the scrim dismisses the sheet. Keep typed instructions unless
      // the user explicitly discards them.
      canPop: _isTaskActive || !_hasDraft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscardDraft();
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Material(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Handle and header are part of the frame, not the content: the
              // way out and the safety state must not scroll away mid-run.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.page + horizontal,
                  AppSpace.x2,
                  AppSpace.page - AppSpace.x1,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHandle(isDark),
                    const SizedBox(height: AppSpace.x2 + 2),
                    _showsChat
                        ? _buildChatHeader(state: state, isRunning: isRunning)
                        : _buildListHeader(),
                    const SizedBox(height: AppSpace.x2),
                  ],
                ),
              ),
              if (_showsChat)
                Expanded(
                  // Answers are worth keeping, and what a user wants is usually
                  // one sentence inside one — the copy button hands over the
                  // whole reply. SelectionArea makes the transcript behave like
                  // text everywhere else on a phone: long-press, drag, copy.
                  child: SelectionArea(
                    child: _buildChatBody(
                      state: state,
                      isRunning: isRunning,
                    ),
                  ),
                )
              else
                Expanded(child: _buildConversationList()),
              if (_showsChat &&
                  (state.status == AgentStatus.waitingCaptcha ||
                      state.status == AgentStatus.waitingConfirmation))
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.x1,
                    AppSpace.page,
                    0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: media.size.height * 0.42,
                    ),
                    child: SingleChildScrollView(
                      child: state.status == AgentStatus.waitingCaptcha
                          ? _buildCaptchaBanner(
                              state: state,
                              isDark: isDark,
                              muted: AppInk.secondary(isDark),
                            )
                          : AgentConfirmationCard(
                              state: state,
                              compact: true,
                              onConfirm: () => widget.onConfirmAction(true),
                              onCancel: () => widget.onConfirmAction(false),
                              onAllowSite: widget.onAllowSite,
                            ),
                    ),
                  ),
                ),
              if (_showsChat)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    media.viewPadding.bottom + 12,
                  ),
                  // While a task runs the prime thumb area belongs to the run
                  // controls, not to a disabled text field.
                  child: _isTaskActive
                      ? _buildRunBar(state: state)
                      : _buildComposer(state: state),
                )
              else
                SizedBox(height: media.viewPadding.bottom + AppSpace.x2),
            ],
          ),
        ),
      ),
    );
  }

  /// The grab bar, and the only control that resizes the panel.
  ///
  /// The transcript below scrolls; it never resizes this. Making both gestures
  /// do the same thing meant a scroll over the conversation moved the window
  /// before it moved the text.
  Widget _buildHandle(bool isDark) {
    final bar = Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppInk.tertiary(isDark).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final drag = widget.onHandleDrag;
    if (drag == null) return Center(child: bar);
    return Semantics(
      label: '拖动调整面板高度',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Up is a negative dy, and up means taller.
        onVerticalDragUpdate: (details) => drag(-details.delta.dy),
        onVerticalDragEnd: (_) => widget.onHandleDragEnd?.call(),
        // The bar stays 4px tall; the gesture gets a 24px thumb-sized area.
        child: SizedBox(
          height: 24,
          width: double.infinity,
          child: Center(child: bar),
        ),
      ),
    );
  }
}
