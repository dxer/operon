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
          if (widget.state.currentStep > 0) ...[
            const SizedBox(width: 6),
            Text(
              '${widget.state.currentStep}/${widget.state.maxSteps}',
              style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11),
            ),
          ]
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
    final fg = host == null
        ? onSurface.withValues(alpha: 0.55)
        : onSurface.withValues(alpha: 0.78);

    return Tooltip(
      message: host == null ? '当前在起始页，AI 会按指令打开网页' : 'AI 将在这个站点上操作',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
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
                host ?? '起始页',
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

  Widget _buildSafeModeChip() {
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkillStrip({
    required Color surface,
    required Color hairline,
    required Color muted,
  }) {
    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: _skills.map((skill) {
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: ActionChip(
              avatar: Icon(
                skill.isFlow ? Icons.account_tree_outlined : Icons.auto_awesome,
                size: 14,
                color: AppTheme.primary,
              ),
              label: Text(
                skill.name,
                style: TextStyle(fontSize: 11, color: muted),
              ),
              backgroundColor: surface,
              side: BorderSide(color: hairline),
              onPressed: () => _applySkill(skill),
            ),
          );
        }).toList(),
      ),
    );

    // Fade the right edge to hint that more skills can be scrolled into view.
    if (_skills.length <= 3) return strip;
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.88, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: strip,
    );
  }

  Widget _buildHeader({required AgentState state, required bool isRunning}) {
    // The header packs four controls; clamp text scaling so large system
    // fonts cannot overflow the row on narrow phones.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Row(
        children: [
          _buildStatusBadge(state.status),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildPageChip(),
            ),
          ),
          _buildSafeModeChip(),
          if (!isRunning)
            IconButton(
              icon: const Icon(Icons.bolt, size: 20, color: AppTheme.primary),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => MacroDialog(onRunMacro: widget.onRunMacro),
                );
              },
              tooltip: '快捷宏任务库 (0 Token)',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          if (state.logs.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _showLogs = !_showLogs),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showLogs ? '收起' : '日志 ${state.logs.length}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  Icon(
                    _showLogs ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
    final deepSurface = isDark ? AppTheme.darkBg : AppTheme.lightBg;
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
                      const SizedBox(height: 12),

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

                      // Thought Display Box
                      if (state.currentThought.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: hairline),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.tips_and_updates_outlined,
                                  size: 16, color: AppTheme.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.currentThought,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Save As Macro Banner (when completed)
                      if (canSaveMacro) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.electric_bolt,
                                  size: 16, color: AppTheme.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '已成功执行 ${state.recordedMacroSteps.length} 个步骤',
                                  style:
                                      TextStyle(fontSize: 12, color: onSurface),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _saveAsMacro,
                                icon: const Icon(Icons.bookmark_add, size: 14),
                                label: const Text('存为快捷宏'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.warning,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 0),
                                  textStyle: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Extracted Data Viewer
                      if (hasExtractedData && _showExtractedData) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: deepSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.dataset_outlined,
                                      size: 14, color: AppTheme.accent),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '已抓取结构化数据',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: _copyExtractedData,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: Text(
                                        '一键复制',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.accent),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: Text(
                                    const JsonEncoder.withIndent('  ')
                                        .convert(state.extractedData),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: muted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // CAPTCHA Hand-Off Banner
                      if (state.status == AgentStatus.waitingCaptcha) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shield_outlined,
                                      color: isDark
                                          ? AppTheme.warning
                                          : const Color(0xFF8A5A12),
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '页面弹出人机验证 (${state.captchaType ?? "验证码"})',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppTheme.warning
                                            : const Color(0xFF8A5A12),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '请在上方网页中手动完成滑动或点击验证，完成后点击“我已通过验证”继续。',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        widget.onConfirmCaptcha(false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: muted,
                                      side: BorderSide(color: hairline),
                                    ),
                                    child: const Text('中止任务'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        widget.onConfirmCaptcha(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.warning,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('我已通过验证，继续'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Human Confirmation Banner
                      if (state.status == AgentStatus.waitingConfirmation) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.danger.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shield_outlined,
                                      size: 16, color: dangerInk),
                                  const SizedBox(width: 6),
                                  Text(
                                    '敏感操作拦截提醒',
                                    style: TextStyle(
                                      color: dangerInk,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'AI 准备执行: ${_actionLabel(state.currentAction)}',
                                style:
                                    TextStyle(fontSize: 12, color: onSurface),
                              ),
                              if (state.confirmationReason != null &&
                                  state.confirmationReason!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '风险类型: ${state.confirmationReason}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: dangerInk,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_hostOf(state.targetUrl).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '目标站点: ${_hostOf(state.targetUrl)}',
                                  style:
                                      TextStyle(fontSize: 11.5, color: muted),
                                ),
                              ],
                              if (state.confirmationPayload != null &&
                                  state.confirmationPayload!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '将发送：${state.confirmationPayload}',
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: onSurface,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        widget.onConfirmAction(false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: muted,
                                      side: BorderSide(color: hairline),
                                    ),
                                    child: const Text('取消任务'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        widget.onConfirmAction(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('授权继续'),
                                  ),
                                ],
                              ),
                              if (widget.onAllowSite != null) ...[
                                const SizedBox(height: 2),
                                TextButton.icon(
                                  onPressed: widget.onAllowSite,
                                  icon: const Icon(Icons.verified_user_outlined,
                                      size: 15),
                                  label: Text(
                                    '本站始终允许（${_hostOf(state.targetUrl)}）',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.accent,
                                    minimumSize: const Size(0, 30),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // Expandable Logs
                      if (_showLogs) ...[
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: StepLogView(logs: state.logs),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Skill templates (instruction or flow).
                      if (!isRunning) ...[
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 12),
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
    return TextField(
      controller: _goalController,
      enabled: !isRunning,
      maxLines: 3,
      minLines: 1,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _startGoal(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: '描述你想让 AI 做的事…',
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
