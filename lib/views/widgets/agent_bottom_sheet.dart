import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';
import '../../models/macro_workflow.dart';
import '../../models/skill.dart';
import '../../services/haptic_service.dart';
import '../../services/macro_service.dart';
import '../../services/skill_from_macro.dart';
import '../../services/skill_from_task.dart';
import '../../services/skill_service.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../services/skill_validator.dart';
import '../../utils/agent_text.dart';
import '../../utils/skill_template.dart';
import '../../utils/url_utils.dart';
import 'agent_confirmation_card.dart';
import 'elapsed_label.dart';
import 'macro_dialog.dart';
import 'skill_run_sheet.dart';
import 'step_log_view.dart';

typedef AgentStartHandler = void Function(
  String goal,
  SkillPolicy? policy,
);

enum _SheetAction { logs, macros, skills, close }

/// A one-tap prompt suggestion shown in the empty panel.
class _ExampleGoal {
  final String label;
  final String goal;

  const _ExampleGoal(this.label, this.goal);
}

class AgentBottomSheet extends StatefulWidget {
  final AgentState state;
  final AgentStartHandler onStart;
  final List<Skill> skills;
  final Future<void> Function()? onManageSkills;
  final Future<void> Function(SkillRunRequest request)? onRunSkill;
  final WebViewControllerWrapper? webView;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final Function(bool confirmed) onConfirmAction;
  final Function(bool passed) onConfirmCaptcha;
  final Function(MacroWorkflow macro) onRunMacro;
  final bool safeMode;
  final ValueChanged<bool> onSafeModeChanged;
  final VoidCallback? onAllowSite;

  /// URL of the tab the sheet was opened from, used to show the agent's
  /// current operating target.
  final String? currentUrl;

  /// When the current task started, so the header can show a live timer.
  final DateTime? taskStartedAt;

  const AgentBottomSheet({
    super.key,
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onConfirmAction,
    required this.onConfirmCaptcha,
    required this.onRunMacro,
    required this.safeMode,
    required this.onSafeModeChanged,
    this.onAllowSite,
    this.skills = const [],
    this.onManageSkills,
    this.onRunSkill,
    this.webView,
    this.currentUrl,
    this.taskStartedAt,
  });

  @override
  State<AgentBottomSheet> createState() => _AgentBottomSheetState();
}

class _AgentBottomSheetState extends State<AgentBottomSheet> {
  late TextEditingController _goalController;
  late bool _safeMode;
  late List<Skill> _skills;
  Skill? _activeSkill;
  SkillPolicy? _activePolicy;

  String get _activePolicyLabel {
    final policy = _activePolicy;
    if (policy == null) return '';
    return policy.maxItems > 1 ? ' · 批量 ×${policy.maxItems}' : ' · 单条';
  }

  bool _showLogs = false;
  bool _resultExpanded = false;
  bool _hasDraft = false;
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
      text: restoreGoal ? widget.state.goal : '',
    );
    _hasDraft = _goalController.text.trim().isNotEmpty;
    _goalController.addListener(_syncDraftState);
    _safeMode = widget.safeMode;
    _skills = List<Skill>.from(widget.skills);
  }

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
        _activeSkill = null;
        _activePolicy = null;
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
    if (widget.skills != oldWidget.skills) {
      _skills = List<Skill>.from(widget.skills);
    }
    if (_activeSkill != null &&
        !_skills.any((item) => item.id == _activeSkill!.id)) {
      _activeSkill = null;
      _activePolicy = null;
    }
  }

  void _toggleSafeMode(bool enabled) {
    HapticService.selection();
    setState(() => _safeMode = enabled);
    widget.onSafeModeChanged(enabled);
  }

  void _startGoal() {
    final text = _goalController.text.trim();
    if (text.isEmpty) return;
    final policy = _activePolicy;
    // A task is single-use: never keep the previous goal or skill binding in
    // the composer after dispatch.
    _goalController.clear();
    setState(() {
      _activeSkill = null;
      _activePolicy = null;
      _resultExpanded = false;
    });
    widget.onStart(text, policy);
  }

  void _clearGoal() {
    HapticService.selection();
    _goalController.clear();
    setState(() {
      _activeSkill = null;
      _activePolicy = null;
    });
  }

  Future<void> _applySkill(Skill skill) async {
    SkillRunRequest? request;
    if (skill.inputs.isNotEmpty || skill.isFlow) {
      request = await showModalBottomSheet<SkillRunRequest>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SkillRunSheet(
          skill: skill,
          webView: widget.webView,
        ),
      );
      if (!mounted || request == null) return;
    }

    // A tap is the primary mobile interaction: run the skill directly instead
    // of filling the composer and making the user press send again.
    final run = widget.onRunSkill;
    if (run != null) {
      final effective = request ??
          SkillRunRequest(
            skill: skill,
            values: {
              for (final input in skill.inputs) input.key: input.defaultValue,
            },
            execute: skill.isFlow,
          );
      Navigator.of(context).pop();
      await run(effective);
      return;
    }

    // Fallback for hosts that only provide the composer.
    if (skill.isFlow) return;
    final values = request?.values ??
        {for (final input in skill.inputs) input.key: input.defaultValue};
    final prompt = SkillTemplate.renderString(
      skill.instructions,
      {'inputs': values},
      strict: false,
    );
    setState(() {
      _activeSkill = skill;
      _activePolicy = skill.policy;
      _goalController.text = prompt;
    });
  }

  Future<void> _manageSkills() async {
    final manage = widget.onManageSkills;
    if (manage == null) return;
    await manage();
    if (!mounted) return;
    final service = await SkillService.getInstance();
    if (!mounted) return;
    final skills = service.getSkills();
    setState(() {
      _skills = skills;
      final activeId = _activeSkill?.id;
      _activeSkill = null;
      _activePolicy = null;
      if (activeId != null) {
        for (final skill in skills) {
          if (skill.id == activeId) {
            _activeSkill = skill;
            _activePolicy = skill.policy;
            break;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _goalController.removeListener(_syncDraftState);
    _goalController.dispose();
    _scrollController.dispose();
    _goalFocus.dispose();
    super.dispose();
  }

  void _copyExtractedData() {
    if (widget.state.extractedData == null) return;
    final jsonStr =
        const JsonEncoder.withIndent('  ').convert(widget.state.extractedData);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制结构化数据至剪贴板！'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

  Future<void> _saveAsMacro() async {
    final steps = widget.state.recordedMacroSteps;
    if (steps.isEmpty) return;

    final titleController = TextEditingController(
      text: widget.state.goal.length > 15
          ? '${widget.state.goal.substring(0, 15)}...宏'
          : '${widget.state.goal} 宏',
    );

    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined,
                color: AppTheme.warning, size: 20),
            SizedBox(width: 8),
            Text('存为快捷宏任务', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '保存后，下次可通过宏直接以 0 Token 毫秒级重放该流程！',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '宏名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skill'),
            child: const Text('存为技能'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('macro'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: const Text('存为宏', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != null && titleController.text.trim().isNotEmpty) {
      final title = titleController.text.trim();
      if (confirmed == 'macro') {
        final macro = MacroWorkflow(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          initialUrl: widget.currentUrl ?? '',
          createdAt: DateTime.now(),
          steps: steps,
        );
        final macroService = await MacroService.getInstance();
        await macroService.saveMacro(macro);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已成功保存为快捷宏！随时可以在宏库中执行'),
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      } else {
        final macro = MacroWorkflow(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          initialUrl: widget.currentUrl ?? '',
          createdAt: DateTime.now(),
          steps: steps,
        );
        final draft = SkillFromMacro.fromMacro(macro);
        if (draft == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('录制步骤无法转换为技能，请先检查宏步骤'),
                backgroundColor: AppTheme.danger,
              ),
            );
          }
        } else {
          final validation = SkillValidator().validateDraft(
            draft,
            allowWrites: true,
            currentHost: hostOf(widget.state.targetUrl ?? ''),
          );
          if (validation.hasErrors) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('无法保存技能：${validation.errors.first.message}'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          } else {
            final skill = draft.toSkill(
              id: 'skill_${DateTime.now().millisecondsSinceEpoch}',
              origin: SkillOrigin.recorded,
            );
            final skillService = await SkillService.getInstance();
            await skillService.saveSkill(skill);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已保存为可编辑技能，可在“技能”页继续调整'),
                  backgroundColor: AppTheme.accent,
                ),
              );
            }
          }
        }
      }
    }
    titleController.dispose();
  }

  /// Saves the finished task as a skill. The goal becomes the prompt; a
  /// recorded flow is offered only when the task actually performed a write,
  /// because replaying navigation alone does not accomplish anything.
  Future<void> _saveTaskAsSkill() async {
    final state = widget.state;
    final canReplay = SkillFromTask.canReplayFlow(state.recordedMacroSteps);
    var preferFlow = false;
    if (canReplay) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存为技能'),
          content: const Text(
            '这次操作可以存成两种技能：\n\n'
            '· 提示词技能：每次由 AI 重新识别元素，页面改版也能用。\n'
            '· 固定流程：按这次的操作重放，更快，但页面改版可能失效。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('提示词技能'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('固定流程'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      preferFlow = choice;
    }
    final draft = SkillFromTask.draftFor(
      goal: state.goal,
      steps: state.recordedMacroSteps,
      url: state.targetUrl ?? widget.currentUrl ?? '',
      preferFlow: preferFlow,
    );

    // No editing form on the happy path: save the draft and let the user edit
    // later from the skills list.
    final service = await SkillService.getInstance();
    final skill = draft.toSkill(
      id: 'skill_${DateTime.now().millisecondsSinceEpoch}',
      origin: SkillOrigin.recorded,
    );
    await service.saveSkill(skill);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已保存为技能，可在技能面板直接使用'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final copper = isDark ? const Color(0xFFE08A56) : AppTheme.primary;
    final sage = isDark ? const Color(0xFF6FC7A3) : const Color(0xFF237A5A);
    final ochre = isDark ? const Color(0xFFE0A23C) : const Color(0xFF8A5A12);
    final brick = isDark ? const Color(0xFFE06A5E) : AppTheme.danger;

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

  /// One chip carries both the agent state and the site it operates on, so the
  /// header keeps a single line of context instead of three competing pills.
  Widget _buildStatusChip(AgentState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = _statusMeta(state.status);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final host = _pageHost;
    final running = state.status == AgentStatus.observing ||
        state.status == AgentStatus.thinking ||
        state.status == AgentStatus.executing ||
        state.status == AgentStatus.paused;

    return Tooltip(
      message: host == null ? '当前在起始页，AI 会按指令打开网页' : 'AI 将在这个站点上操作\n$host',
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, size: 13, color: meta.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                meta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: meta.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (running && widget.taskStartedAt != null) ...[
              const SizedBox(width: 6),
              ElapsedLabel(
                startedAt: widget.taskStartedAt!,
                color: meta.color.withValues(alpha: 0.72),
                fontSize: 10.5,
              ),
            ],
            Container(
              width: 1,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: hairline,
            ),
            Icon(
              host == null ? Icons.public_off : Icons.language,
              size: 11,
              color: onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                host == null ? '起始页' : compactHost(host),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: onSurface.withValues(alpha: 0.66),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeModeChip({bool showLabel = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sage = isDark ? const Color(0xFF6FC7A3) : const Color(0xFF237A5A);
    final ochre = isDark ? AppTheme.warning : const Color(0xFF8A5A12);
    final fg = _safeMode ? sage : ochre;
    return Tooltip(
      message: _safeMode ? '敏感操作需要人工确认，点击切换为全自动' : '全自动模式，点击恢复人工确认',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleSafeMode(!_safeMode),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 8 : 6,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: fg.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _safeMode ? Icons.shield_outlined : Icons.bolt_rounded,
                  size: 13,
                  color: fg,
                ),
                if (showLabel) ...[
                  const SizedBox(width: 3),
                  Text(
                    _safeMode ? '人工授权' : '全自动',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasResultCard(AgentState state) {
    if (state.currentThought.trim().isNotEmpty) return true;
    if (state.isRunning && state.currentAction != null) return true;
    return state.status == AgentStatus.completed ||
        state.status == AgentStatus.error ||
        state.status == AgentStatus.maxStepsReached;
  }

  String _resultText(AgentState state) {
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
    required bool canSaveMacro,
  }) {
    final sage = isDark ? const Color(0xFF6FC7A3) : const Color(0xFF237A5A);
    final ochre = isDark ? const Color(0xFFE0A23C) : const Color(0xFF8A5A12);
    final brick = isDark ? const Color(0xFFE06A5E) : AppTheme.danger;
    final copper = isDark ? const Color(0xFFE08A56) : AppTheme.primary;

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
        // While a step runs, the concrete action is more useful than the
        // model's reasoning, which is kept as a muted second line.
        if (state.currentAction != null) {
          icon = Icons.touch_app_rounded;
          title = '正在执行';
        } else {
          icon = Icons.auto_awesome_rounded;
          title = 'AI 思路';
        }
        break;
    }

    final actionText =
        finished ? '' : agentActionLabel(state.currentAction).trim();
    final hasAction = actionText.isNotEmpty;
    final text = hasAction ? actionText : _resultText(state);
    final secondary = hasAction ? _resultText(state) : '';
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
                if (state.status == AgentStatus.completed)
                  _smallAction(
                    icon: Icons.bookmark_add_outlined,
                    label: '存为技能',
                    color: muted,
                    onTap: _saveTaskAsSkill,
                  ),
                if (canSaveMacro)
                  _smallAction(
                    icon: Icons.bolt_rounded,
                    label: '存为宏',
                    color: muted,
                    onTap: _saveAsMacro,
                  ),
                if (state.logs.isNotEmpty)
                  _smallAction(
                    icon: Icons.subject_rounded,
                    label: _showLogs ? '收起日志' : '日志 ${state.logs.length}',
                    color: muted,
                    onTap: () => setState(() => _showLogs = !_showLogs),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int _dataCount(dynamic data) => data is List ? data.length : 1;

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

  String _shortValue(dynamic value) {
    if (value == null) return '—';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return jsonEncode(value);
  }

  String _dataSummary(dynamic data) {
    final fields = _dataEntries(data).length;
    if (fields == 0) return '已抓取结构化数据';
    final count = _dataCount(data);
    if (data is List) return '$count 条数据 · $fields 个字段';
    return '$fields 个字段';
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  Widget _buildExtractedCard({
    required dynamic data,
    required Color surface,
    required Color hairline,
    required Color onSurface,
    required Color muted,
  }) {
    final entries = _dataEntries(data);
    final count = _dataCount(data);
    final preview = entries.take(3).toList();
    final canExpand = entries.isEmpty ||
        entries.length > preview.length ||
        (data is List && count > 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
              const Icon(Icons.dataset_outlined,
                  size: 15, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dataSummary(data),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
              _iconAction(
                icon: Icons.copy_rounded,
                tooltip: '复制数据',
                color: muted,
                onTap: _copyExtractedData,
              ),
              if (canExpand)
                _iconAction(
                  icon: Icons.open_in_full_rounded,
                  tooltip: '展开全部',
                  color: muted,
                  onTap: _showExtractedDataSheet,
                ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...preview.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _shortValue(entry.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                          color: onSurface.withValues(alpha: 0.86),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showExtractedDataSheet() async {
    final data = widget.state.extractedData;
    if (data == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExtractedDataSheet(data: data),
    );
  }

  /// Site-specific skills for the current page come first, then general
  /// skills, then skills for other sites. Nothing is hidden: a skill the user
  /// saved elsewhere stays reachable.
  List<Skill> get _orderedSkills {
    final host = _pageHost;
    final matched = <Skill>[];
    final general = <Skill>[];
    final other = <Skill>[];
    for (final skill in _skills) {
      // A scope without recorded hosts is not a restriction; it belongs with
      // the general skills rather than under "other sites".
      if (!skill.policy.isSiteScoped) {
        general.add(skill);
      } else if (skill.matchesHost(host)) {
        matched.add(skill);
      } else {
        other.add(skill);
      }
    }
    return [...matched, ...general, ...other];
  }

  Widget _buildSkillStrip({
    required Color surface,
    required Color hairline,
    required Color muted,
  }) {
    Widget chipFor(Skill skill) {
      final hosts = skill.policy.allowedHosts;
      final usable = skill.allowsHost(_pageHost);
      final tooltip = hosts.isEmpty
          ? '通用技能'
          : (usable
              ? '仅限 ${hosts.join('、')}'
              : '只能在 ${hosts.join('、')} 运行');
      // A skill scoped to another site stays visible but cannot be tapped:
      // failing after the tap is worse than showing why up front.
      final chip = ActionChip(
        avatar: Icon(
          usable
              ? (skill.isFlow
                  ? Icons.account_tree_outlined
                  : Icons.auto_awesome)
              : Icons.lock_outline,
          size: 14,
          color: usable ? AppTheme.primary : muted,
        ),
        label: Text(
          skill.name,
          style: TextStyle(
            fontSize: 11,
            color: usable ? muted : muted.withValues(alpha: 0.55),
          ),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: surface,
        side: BorderSide(color: hairline),
        onPressed: usable ? () => _applySkill(skill) : null,
      );
      return Tooltip(message: tooltip, child: chip);
    }

    final ordered = _orderedSkills;
    // A handful of skills fits cleanly on wrapped rows. Only fall back to a
    // scrolling strip when the list is long enough to need it.
    if (ordered.length <= 4) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: ordered.map(chipFor).toList(),
      );
    }

    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: ordered
            .map((skill) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: chipFor(skill),
                ))
            .toList(),
      ),
    );

    // Fade the right edge to hint that more skills can be scrolled into view.
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.9, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: strip,
    );
  }

  Widget _buildHeader({required AgentState state, required bool isRunning}) {
    // Status and site share one chip; logs, macros and skill management live
    // in the overflow menu. That keeps the header to a single context line
    // instead of three competing pills.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildStatusChip(state),
                ),
              ),
              const SizedBox(width: 6),
              _buildSafeModeChip(),
              const SizedBox(width: 2),
              _buildOverflowMenu(state: state, isRunning: isRunning),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverflowMenu({
    required AgentState state,
    required bool isRunning,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PopupMenuButton<_SheetAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      onSelected: (action) => _handleSheetAction(action, state: state),
      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      itemBuilder: (context) => [
        if (state.logs.isNotEmpty)
          PopupMenuItem(
            value: _SheetAction.logs,
            height: 42,
            child: _menuRow(
              Icons.subject_rounded,
              _showLogs ? '收起日志' : '日志 ${state.logs.length}',
            ),
          ),
        if (!isRunning)
          PopupMenuItem(
            value: _SheetAction.macros,
            height: 42,
            child: _menuRow(Icons.bolt_rounded, '快捷宏任务库'),
          ),
        if (widget.onManageSkills != null && !isRunning)
          PopupMenuItem(
            value: _SheetAction.skills,
            height: 42,
            child: _menuRow(Icons.tune_rounded, '管理技能'),
          ),
        PopupMenuItem(
          value: _SheetAction.close,
          height: 42,
          child: _menuRow(Icons.close_rounded, '关闭面板'),
        ),
      ],
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 20,
          color: onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 16, color: onSurface.withValues(alpha: 0.62)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }

  Future<void> _handleSheetAction(
    _SheetAction action, {
    required AgentState state,
  }) async {
    switch (action) {
      case _SheetAction.logs:
        setState(() => _showLogs = !_showLogs);
        return;
      case _SheetAction.macros:
        await showDialog<void>(
          context: context,
          builder: (_) => MacroDialog(onRunMacro: widget.onRunMacro),
        );
        return;
      case _SheetAction.skills:
        await _manageSkills();
        return;
      case _SheetAction.close:
        if (!mounted) return;
        await Navigator.of(context).maybePop();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isRunning = state.isRunning;
    final hasExtractedData = state.extractedData != null;
    final canSaveMacro = state.status == AgentStatus.completed &&
        state.recordedMacroSteps.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final subtle = onSurface.withValues(alpha: 0.38);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;

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
              Flexible(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      _buildHeader(state: state, isRunning: isRunning),

                      // A thin progress line gives an at-a-glance answer to
                      // "how far along is this?" without another text row.
                      if (isRunning && state.maxSteps > 0) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          label: '任务进度 ${state.currentStep}/${state.maxSteps}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: (state.currentStep / state.maxSteps)
                                  .clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: hairline,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Full-auto is a risky state, so keep a visible warning
                      // instead of hiding it behind the compact chip.
                      if (!_safeMode) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: AppTheme.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '全自动模式：支付、发布、删除等操作不会暂停确认',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? AppTheme.warning
                                      : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // CAPTCHA Hand-Off Banner
                      if (state.status == AgentStatus.waitingCaptcha) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.warning.withValues(alpha: 0.32),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    color: isDark
                                        ? AppTheme.warning
                                        : const Color(0xFF8A5A12),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      state.captchaType == null
                                          ? '需要人机验证'
                                          : '需要人机验证 · ${state.captchaType}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isDark
                                            ? AppTheme.warning
                                            : const Color(0xFF8A5A12),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '请在上方网页完成验证，然后点击「我已完成验证」。',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        widget.onConfirmCaptcha(false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: muted,
                                      side: BorderSide(color: hairline),
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      textStyle:
                                          const TextStyle(fontSize: 11.5),
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('中止任务'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () =>
                                        widget.onConfirmCaptcha(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.warning,
                                      foregroundColor: Colors.black,
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      textStyle: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('我已完成验证'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Sensitive action. This is the same card that pops up
                      // on its own when the panel is closed, and the only
                      // surface that can approve a write.
                      if (state.status == AgentStatus.waitingConfirmation) ...[
                        const SizedBox(height: 8),
                        AgentConfirmationCard(
                          state: state,
                          compact: true,
                          onConfirm: () => widget.onConfirmAction(true),
                          onCancel: () => widget.onConfirmAction(false),
                          onAllowSite: widget.onAllowSite,
                        ),
                      ],

                      // Result card: one place for the conclusion, step count and
                      // follow-up actions instead of three stacked success banners.
                      if (_hasResultCard(state)) ...[
                        const SizedBox(height: 8),
                        _buildResultCard(
                          state: state,
                          isDark: isDark,
                          surface: surface,
                          hairline: hairline,
                          onSurface: onSurface,
                          muted: muted,
                          canSaveMacro: canSaveMacro,
                        ),
                      ],

                      // Extracted data: compact key/value preview, full view on demand.
                      if (hasExtractedData) ...[
                        const SizedBox(height: 8),
                        _buildExtractedCard(
                          data: state.extractedData,
                          surface: surface,
                          hairline: hairline,
                          onSurface: onSurface,
                          muted: muted,
                        ),
                      ],

                      // Expandable Logs
                      if (_showLogs) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: StepLogView(logs: state.logs),
                        ),
                      ],

                      // Skill templates (instruction or flow).
                      if (!isRunning) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 14, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              '技能',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (widget.onManageSkills != null)
                              TextButton.icon(
                                onPressed: _manageSkills,
                                icon: const Icon(Icons.tune_rounded, size: 14),
                                label: const Text('管理',
                                    style: TextStyle(fontSize: 11.5)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  minimumSize: const Size(0, 44),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_skills.isEmpty)
                          Text(
                            '暂无技能，点击“管理”用 AI 创建',
                            style: TextStyle(fontSize: 11.5, color: subtle),
                          )
                        else
                          _buildSkillStrip(
                            surface: surface,
                            hairline: hairline,
                            muted: muted,
                          ),
                        if (_activeSkill != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: AppTheme.accent,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '已套用：${_activeSkill!.name}'
                                  '$_activePolicyLabel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _activeSkill = null;
                                  _activePolicy = null;
                                }),
                                style: TextButton.styleFrom(
                                  foregroundColor: muted,
                                  minimumSize: const Size(0, 44),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: const Text(
                                  '清除',
                                  style: TextStyle(fontSize: 10.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
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
    final accent = paused || waiting ? AppTheme.warning : AppTheme.primary;
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
            color: AppTheme.danger,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
                          color: canSend ? AppTheme.primary : subtle,
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

/// Full-screen-ish viewer for extracted data. Keeping the sheet itself short
/// avoids a nested scroll area inside the agent panel.
class _ExtractedDataSheet extends StatefulWidget {
  final dynamic data;

  const _ExtractedDataSheet({required this.data});

  @override
  State<_ExtractedDataSheet> createState() => _ExtractedDataSheetState();
}

class _ExtractedDataSheetState extends State<_ExtractedDataSheet> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.6);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(widget.data);

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.dataset_outlined,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    '抓取的数据',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: jsonStr));
                      if (mounted) setState(() => _copied = true);
                    },
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _copied ? '已复制' : '复制',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, size: 18, color: muted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SelectableText(
                  jsonStr,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.5,
                    color: onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
