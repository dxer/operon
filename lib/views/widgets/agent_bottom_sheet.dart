import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/agent_action.dart';
import '../../models/agent_state.dart';
import '../../models/macro_workflow.dart';
import '../../models/quick_command.dart';
import '../../models/skill.dart';
import '../../services/macro_service.dart';
import '../../services/skill_agent_adapter.dart';
import '../../services/skill_from_macro.dart';
import '../../services/skill_service.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../services/skill_validator.dart';
import '../../utils/skill_template.dart';
import 'macro_dialog.dart';
import 'skill_run_sheet.dart';
import 'step_log_view.dart';

typedef AgentStartHandler = void Function(
  String goal,
  QuickCommandPolicy? policy,
);

enum _SheetAction { logs, macros, skills, close }

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
  });

  @override
  State<AgentBottomSheet> createState() => _AgentBottomSheetState();
}

class _AgentBottomSheetState extends State<AgentBottomSheet> {
  late TextEditingController _goalController;
  late bool _safeMode;
  late List<Skill> _skills;
  Skill? _activeSkill;
  QuickCommandPolicy? _activePolicy;
  bool _showLogs = false;
  final bool _showExtractedData = true;
  bool _resultExpanded = false;
  bool _hasDraft = false;
  bool _discardDialogOpen = false;

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
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
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

    if (skill.isFlow) {
      final run = widget.onRunSkill;
      if (run == null) return;
      final flowRequest = request ??
          SkillRunRequest(
            skill: skill,
            values: {
              for (final input in skill.inputs) input.key: input.defaultValue,
            },
            execute: true,
          );
      Navigator.of(context).pop();
      await run(flowRequest);
      return;
    }

    final values = request?.values ??
        {for (final input in skill.inputs) input.key: input.defaultValue};
    final prompt = SkillTemplate.renderString(
      skill.instructions,
      {'inputs': values},
      strict: false,
    );
    setState(() {
      _activeSkill = skill;
      _activePolicy = skillPolicyToAgentPolicy(skill.policy);
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
            _activePolicy = skillPolicyToAgentPolicy(skill.policy);
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
          initialUrl: '',
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
          initialUrl: '',
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
            currentHost: _hostOf(widget.state.targetUrl ?? ''),
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

  /// Never show typed text (passwords, drafts) in the authorization banner.
  String _actionLabel(AgentAction? action) {
    if (action == null) return '';
    if (action.action == ActionType.type) {
      return '在 [${action.elementId}] 输入内容';
    }
    return action.description;
  }

  String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '';
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  /// Long hosts collapse to their registrable domain so the header keeps room
  /// for the status and authorization chips. The full host stays in the tooltip.
  String _compactHost(String host) {
    if (host.length <= 18) return host;
    if (host.contains(':')) return host; // IPv6 literal; never split on dots.
    final labels = host.split('.');
    if (labels.length <= 2 ||
        labels.every((label) => int.tryParse(label) != null)) {
      return host;
    }
    final secondLevel = labels[labels.length - 2];
    final tld = labels.last;
    final keep = tld.length == 2 &&
            const ['co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne']
                .contains(secondLevel)
        ? 3
        : 2;
    if (labels.length <= keep) return host;
    return labels.sublist(labels.length - keep).join('.');
  }

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

  Widget _buildStatusBadge(AgentStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final copper = isDark ? const Color(0xFFE08A56) : AppTheme.primary;
    final sage = isDark ? const Color(0xFF6FC7A3) : const Color(0xFF237A5A);
    final ochre = isDark ? const Color(0xFFE0A23C) : const Color(0xFF8A5A12);
    final brick = isDark ? const Color(0xFFE06A5E) : AppTheme.danger;

    late Color bg;
    late Color fg;
    late String label;
    late IconData icon;

    void semantic(Color color) {
      bg = color.withValues(alpha: 0.14);
      fg = color;
    }

    switch (status) {
      case AgentStatus.idle:
        bg = onSurface.withValues(alpha: 0.08);
        fg = onSurface.withValues(alpha: 0.62);
        label = '待命';
        icon = Icons.stop_circle_outlined;
        break;
      case AgentStatus.observing:
        semantic(copper);
        label = '读取页面';
        icon = Icons.visibility_outlined;
        break;
      case AgentStatus.thinking:
        semantic(copper);
        label = '思考规划';
        icon = Icons.psychology_outlined;
        break;
      case AgentStatus.executing:
        semantic(copper);
        label = '执行中';
        icon = Icons.touch_app_outlined;
        break;
      case AgentStatus.waitingConfirmation:
        semantic(ochre);
        label = '等待授权';
        icon = Icons.security_outlined;
        break;
      case AgentStatus.waitingCaptcha:
        semantic(ochre);
        label = '等待验证';
        icon = Icons.verified_user_outlined;
        break;
      case AgentStatus.paused:
        semantic(ochre);
        label = '已暂停';
        icon = Icons.pause_circle_outline;
        break;
      case AgentStatus.completed:
        semantic(sage);
        label = '已完成';
        icon = Icons.check_circle_outline;
        break;
      case AgentStatus.maxStepsReached:
        semantic(ochre);
        label = '步数上限';
        icon = Icons.timer_outlined;
        break;
      case AgentStatus.error:
        semantic(brick);
        label = '执行异常';
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPageChip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final host = _pageHost;
    final displayHost = host == null ? null : _compactHost(host);
    final fg = host == null
        ? onSurface.withValues(alpha: 0.55)
        : onSurface.withValues(alpha: 0.78);

    return Tooltip(
      message: host == null ? '当前在起始页，AI 会按指令打开网页' : 'AI 将在这个站点上操作\n$host',
      child: Container(
        constraints: const BoxConstraints(minWidth: 54, maxWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hairline, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              host == null ? Icons.public_off : Icons.language,
              size: 12,
              color: fg,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                displayHost ?? '起始页',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: fg),
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
    HapticFeedback.selectionClick();
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
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
        icon = Icons.auto_awesome_rounded;
        title = 'AI 思路';
        finished = false;
    }

    final text = _resultText(state);
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
                if (canSaveMacro)
                  _smallAction(
                    icon: Icons.bookmark_add_outlined,
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

  Widget _buildSkillStrip({
    required Color surface,
    required Color hairline,
    required Color muted,
  }) {
    Widget chipFor(Skill skill) {
      return ActionChip(
        avatar: Icon(
          skill.isFlow ? Icons.account_tree_outlined : Icons.auto_awesome,
          size: 14,
          color: AppTheme.primary,
        ),
        label: Text(
          skill.name,
          style: TextStyle(fontSize: 11, color: muted),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: surface,
        side: BorderSide(color: hairline),
        onPressed: () => _applySkill(skill),
      );
    }

    // A handful of skills fits cleanly on wrapped rows. Only fall back to a
    // scrolling strip when the list is long enough to need it.
    if (_skills.length <= 4) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _skills.map(chipFor).toList(),
      );
    }

    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: _skills
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
    // Keep this row to four controls. Logs, macros and skill management move
    // into the overflow menu so the host chip never collapses to a bare globe.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On narrow phones drop the authorization label to an icon so a long
          // host keeps enough room to show its registrable domain.
          final compact = constraints.maxWidth < 310;
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildStatusBadge(state.status),
                    const SizedBox(width: 6),
                    Flexible(child: _buildPageChip()),
                    const SizedBox(width: 6),
                    _buildSafeModeChip(showLabel: !compact),
                  ],
                ),
              ),
              const SizedBox(width: 4),
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
        if (widget.onManageSkills != null)
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
        width: 34,
        height: 34,
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
    final dangerInk = isDark ? const Color(0xFFE06A5E) : AppTheme.danger;

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
                                '请在上方网页完成验证，然后点击继续。',
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
                                      minimumSize: const Size(0, 34),
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
                                      minimumSize: const Size(0, 34),
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
                                    child: const Text('验证完成，继续'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Human Confirmation Banner
                      if (state.status == AgentStatus.waitingConfirmation) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.fromLTRB(11, 10, 11, 8),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.38),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shield_outlined,
                                      size: 15, color: dangerInk),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '敏感操作，等待授权',
                                      style: TextStyle(
                                        color: dangerInk,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_actionLabel(state.currentAction)
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '将执行：${_actionLabel(state.currentAction)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    color: onSurface,
                                  ),
                                ),
                              ],
                              if (state.confirmationReason != null &&
                                  state.confirmationReason!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '风险类型：${state.confirmationReason}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: dangerInk,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_hostOf(state.targetUrl).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '目标站点：${_compactHost(_hostOf(state.targetUrl))}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: muted),
                                ),
                              ],
                              if (state.confirmationPayload != null &&
                                  state.confirmationPayload!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '将发送：${state.confirmationPayload}',
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: onSurface,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        widget.onConfirmAction(false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: muted,
                                      side: BorderSide(color: hairline),
                                      minimumSize: const Size(0, 34),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      textStyle:
                                          const TextStyle(fontSize: 11.5),
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('取消任务'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () =>
                                        widget.onConfirmAction(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: Colors.black,
                                      minimumSize: const Size(0, 34),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      textStyle: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('授权继续'),
                                  ),
                                ],
                              ),
                              if (widget.onAllowSite != null &&
                                  _hostOf(state.targetUrl).isNotEmpty)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: widget.onAllowSite,
                                    icon: const Icon(
                                        Icons.verified_user_outlined,
                                        size: 14),
                                    label: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 210),
                                      child: Text(
                                        '本站始终允许（${_compactHost(_hostOf(state.targetUrl))}）',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.accent,
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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
                      if (hasExtractedData && _showExtractedData) ...[
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
                                  minimumSize: const Size(0, 28),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
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
                                  '${_activePolicy == null ? '' : ' · ${_activePolicy!.mode.label}'}',
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
                                  minimumSize: const Size(0, 24),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
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

                      // Control Action Buttons (when running)
                      if (isRunning) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: state.status == AgentStatus.paused
                                    ? widget.onResume
                                    : widget.onPause,
                                icon: Icon(
                                  state.status == AgentStatus.paused
                                      ? Icons.play_arrow
                                      : Icons.pause,
                                  size: 18,
                                ),
                                label: Text(state.status == AgentStatus.paused
                                    ? '恢复'
                                    : '暂停'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: onSurface,
                                  side: BorderSide(color: hairline),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: widget.onStop,
                                icon: const Icon(Icons.stop, size: 18),
                                label: const Text('停止运行'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppTheme.danger.withValues(alpha: 0.8),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  media.viewPadding.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGoalField(
                      isRunning: isRunning,
                      subtle: subtle,
                    ),
                    if (_pageHost == null && !_isTaskActive) ...[
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
                      minimumSize: const Size(0, 32),
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
