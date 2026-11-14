import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/agent_attachment.dart';
import '../../models/agent_prompt.dart';
import '../../models/agent_state.dart';
import '../../services/attachment_reader.dart';
import '../../services/haptic_service.dart';
import '../../services/share_service.dart';
import '../../utils/url_utils.dart';
import 'agent_confirmation_card.dart';
import 'elapsed_label.dart';
import 'step_log_view.dart';
import 'extracted_data_sheet.dart';

part 'sheet/body.dart';

part 'sheet/header.dart';
part 'sheet/result.dart';
part 'sheet/extracted.dart';
part 'sheet/composer.dart';
part 'sheet/run_bar.dart';

typedef AgentStartHandler = void Function(
  String goal,
  List<AgentAttachment> attachments,
);

enum _SheetAction { logs, close }

/// A one-tap prompt suggestion shown in the empty panel.
class _ExampleGoal {
  final String label;
  final String goal;

  const _ExampleGoal(this.label, this.goal);
}

class AgentBottomSheet extends StatefulWidget {
  final AgentState state;
  final AgentStartHandler onStart;
  final VoidCallback onPause;
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

  const AgentBottomSheet({
    super.key,
    required this.state,
    required this.onStart,
    required this.onPause,
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
  });

  @override
  State<AgentBottomSheet> createState() => _AgentBottomSheetState();
}

class _AgentBottomSheetState extends State<AgentBottomSheet> {
  /// Brightness for one-off foreground tints outside a `build` scope.
  bool get _isDarkTheme => Theme.of(context).brightness == Brightness.dark;

  late TextEditingController _goalController;
  late bool _safeMode;
  bool _showLogs = false;
  bool _resultExpanded = false;
  bool _hasDraft = false;
  bool _isPickingAttachment = false;
  final List<AgentAttachment> _attachments = [];
  bool _discardDialogOpen = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _goalFocus = FocusNode();

  bool get _isTaskActive =>
      widget.state.isRunning || widget.state.status == AgentStatus.paused;

  @override
  void initState() {
    super.initState();
    final restoreGoal =
        widget.state.isRunning || widget.state.status == AgentStatus.paused;
    _goalController = TextEditingController(
      text: restoreGoal
          ? widget.state.goal
          : (widget.initialGoal ?? '').trim(),
    );
    _hasDraft = _goalController.text.trim().isNotEmpty;
    _goalController.addListener(_syncDraftState);
    _safeMode = widget.safeMode;
  }



  @override
  void didUpdateWidget(covariant AgentBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final restoreGoal =
        widget.state.isRunning || widget.state.status == AgentStatus.paused;
    if (restoreGoal &&
        widget.state.goal.isNotEmpty &&
        _goalController.text.isEmpty) {
      _goalController.text = widget.state.goal;
    }
    final finished = widget.state.status == AgentStatus.completed ||
        widget.state.status == AgentStatus.error ||
        widget.state.status == AgentStatus.maxStepsReached ||
        widget.state.status == AgentStatus.idle;
    if (finished && widget.state.goal.isNotEmpty) {
      final previousGoal = widget.state.goal.trim();
      if (_goalController.text.trim() == previousGoal) {
        // The last task is over; start the next composer cleanly.
        _goalController.clear();
      }
    }
    if (widget.safeMode != oldWidget.safeMode) {
      _safeMode = widget.safeMode;
    }
    // A confirmation or CAPTCHA card is inserted at the top of the scroll
    // area. If the user was reading logs further down they would never see
    // it, so snap back to the top as soon as the task blocks.
    final becameWaiting = widget.state.status != oldWidget.state.status &&
        (widget.state.status == AgentStatus.waitingConfirmation ||
            widget.state.status == AgentStatus.waitingCaptcha);
    if (becameWaiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (reduceMotion) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    // A failure is the moment logs matter most, so surface them immediately.
    if (oldWidget.state.status != AgentStatus.error &&
        widget.state.status == AgentStatus.error) {
      _showLogs = true;
    }
  }






  @override
  void dispose() {
    _goalController.removeListener(_syncDraftState);
    _goalController.dispose();
    _scrollController.dispose();
    _goalFocus.dispose();
    super.dispose();
  }



  /// Saves the finished task as a skill. The goal becomes the prompt; a
  /// recorded flow is offered only when the task actually performed a write,
  /// because replaying navigation alone does not accomplish anything.

  /// Never show typed text (passwords, drafts) in the authorization banner.
  /// Host of the tab the sheet was opened from; null means start page.
  String? get _pageHost {
    final url = widget.currentUrl;
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
      AgentStatus.maxStepsReached => (
          color: ochre,
          label: '步数上限',
          icon: Icons.timer_outlined,
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
    final hasExtractedData = state.extractedData != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final subtle = onSurface.withValues(alpha: 0.38);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    // Warning ink sits on the card, so it has to follow the brightness; the
    // solid `AppTheme.warning` chip fill stays dark-on-light in both themes.
    final warnInk = AppTheme.warningOf(isDark);

    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final maxSheetHeight =
        (media.size.height - keyboardInset - media.viewPadding.top - 24)
            .clamp(280.0, media.size.height)
            .toDouble();

    // Lift the sheet above the IME and let the body scroll, so the composer and
    // the focused field are never hidden behind the keyboard.
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
        child: Container(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildScrollBody(
                state: state,
                isRunning: isRunning,
                hasExtractedData: hasExtractedData,
                isDark: isDark,
                cardBg: cardBg,
                onSurface: onSurface,
                muted: muted,
                subtle: subtle,
                hairline: hairline,
                surface: surface,
                warnInk: warnInk,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  media.viewPadding.bottom + 12,
                ),
                // While a task runs the prime thumb area belongs to the run
                // controls, not to a disabled text field. The composer comes
                // back as soon as the task is idle or finished.
                child: _isTaskActive
                    ? _buildRunBar(
                        state: state,
                        surface: surface,
                        hairline: hairline,
                        onSurface: onSurface,
                        muted: muted,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Collapsing must not make the composer jump while
                          // the user is typing.
                          AnimatedSize(
                            duration:
                                MediaQuery.maybeDisableAnimationsOf(context) ==
                                        true
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
                                : const SizedBox(
                                    width: double.infinity,
                                    height: 0,
                                  ),
                          ),
                          if (_attachments.isNotEmpty)
                            _buildAttachmentStrip(subtle: subtle),
                          // Rebuilt on every keystroke: the strip appears
                          // the moment the field starts with "/".
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _goalController,
                            builder: (context, _, __) =>
                                _buildPromptStrip(subtle: subtle),
                          ),
                          _buildGoalField(
                            isRunning: isRunning,
                            subtle: subtle,
                          ),
                          if (_pageHost == null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '当前是起始页；可直接在指令里写要打开的网址或搜索目标',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: subtle),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty panel: show what the agent can do instead of a bare input box.
  bool get _showsExamples =>
      !_isTaskActive &&
      widget.state.status == AgentStatus.idle &&
      widget.state.logs.isEmpty &&
      !_hasDraft;

  List<_ExampleGoal> get _exampleGoals => _pageHost == null
      ? const [
          _ExampleGoal('GitHub 热榜', '打开 GitHub 热榜并总结前 5 个项目'),
          _ExampleGoal('今日 AI 新闻', '搜索今天的 AI 新闻并总结要点'),
          _ExampleGoal('Hacker News', '打开 Hacker News 看看热门内容'),
        ]
      : const [
          _ExampleGoal('总结这一页', '总结当前页面的主要内容'),
          _ExampleGoal('提取列表', '提取当前页面列表中的条目'),
          _ExampleGoal('找出链接', '找出当前页面可以继续点进去的链接'),
        ];




}