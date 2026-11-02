import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../models/agent_state.dart';
import '../../models/macro_workflow.dart';
import '../../services/macro_service.dart';
import 'macro_dialog.dart';
import 'step_log_view.dart';

class AgentBottomSheet extends StatefulWidget {
  final AgentState state;
  final Function(String goal) onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final Function(bool confirmed) onConfirmAction;
  final Function(bool passed) onConfirmCaptcha;
  final Function(MacroWorkflow macro) onRunMacro;
  final bool safeMode;
  final ValueChanged<bool> onSafeModeChanged;
  final VoidCallback? onAllowSite;

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
  });

  @override
  State<AgentBottomSheet> createState() => _AgentBottomSheetState();
}

class _AgentBottomSheetState extends State<AgentBottomSheet> {
  late TextEditingController _goalController;
  late bool _safeMode;
  bool _showLogs = false;
  final bool _showExtractedData = true;

  @override
  void initState() {
    super.initState();
    _goalController = TextEditingController(text: widget.state.goal);
    _safeMode = widget.safeMode;
  }

  @override
  void didUpdateWidget(covariant AgentBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.goal.isNotEmpty && _goalController.text.isEmpty) {
      _goalController.text = widget.state.goal;
    }
    if (widget.safeMode != oldWidget.safeMode) {
      _safeMode = widget.safeMode;
    }
  }

  void _toggleSafeMode(bool enabled) {
    HapticFeedback.selectionClick();
    setState(() => _safeMode = enabled);
    widget.onSafeModeChanged(enabled);
  }

  @override
  void dispose() {
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined, color: Colors.amber, size: 20),
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: const Text('保存', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed == true && titleController.text.trim().isNotEmpty) {
      final macro = MacroWorkflow(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
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
    }
    titleController.dispose();
  }

  String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '';
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  Widget _buildStatusBadge(AgentStatus status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case AgentStatus.idle:
        bg = Colors.grey.withValues(alpha: 0.2);
        fg = Colors.grey;
        label = '待命';
        icon = Icons.stop_circle_outlined;
        break;
      case AgentStatus.observing:
        bg = Colors.blue.withValues(alpha: 0.2);
        fg = Colors.blueAccent;
        label = '读取页面中';
        icon = Icons.visibility_outlined;
        break;
      case AgentStatus.thinking:
        bg = Colors.purple.withValues(alpha: 0.2);
        fg = Colors.purpleAccent;
        label = 'AI 思考规划中';
        icon = Icons.psychology_outlined;
        break;
      case AgentStatus.executing:
        bg = Colors.orange.withValues(alpha: 0.2);
        fg = Colors.orangeAccent;
        label = '虚拟光标操控中';
        icon = Icons.touch_app_outlined;
        break;
      case AgentStatus.waitingConfirmation:
        bg = Colors.red.withValues(alpha: 0.2);
        fg = Colors.redAccent;
        label = '等待人工授权';
        icon = Icons.security_outlined;
        break;
      case AgentStatus.waitingCaptcha:
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber;
        label = '等待完成人机验证';
        icon = Icons.verified_user_outlined;
        break;
      case AgentStatus.paused:
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber;
        label = '已暂停';
        icon = Icons.pause_circle_outline;
        break;
      case AgentStatus.completed:
        bg = Colors.green.withValues(alpha: 0.2);
        fg = Colors.greenAccent;
        label = '任务顺利达成';
        icon = Icons.check_circle_outline;
        break;
      case AgentStatus.maxStepsReached:
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber;
        label = '已达步数上限';
        icon = Icons.timer_outlined;
        break;
      case AgentStatus.error:
        bg = Colors.red.withValues(alpha: 0.2);
        fg = Colors.redAccent;
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
    final surface = isDark ? const Color(0xFF16181C) : const Color(0xFFF1F4F6);
    final deepSurface = isDark ? AppTheme.darkBg : const Color(0xFFF7F9FA);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            20,
      ),
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

          // Header row with status, macro library button, and toggle log
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusBadge(state.status),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.bolt, size: 20, color: Colors.amber),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) =>
                            MacroDialog(onRunMacro: widget.onRunMacro),
                      );
                    },
                    tooltip: '快捷宏任务库 (0 Token)',
                  ),
                  if (hasExtractedData)
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 16, color: AppTheme.accent),
                      onPressed: _copyExtractedData,
                      tooltip: '复制已抓取数据',
                    ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showLogs = !_showLogs),
                    icon: Icon(
                      _showLogs ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    label: Text(
                      _showLogs ? '收起日志' : '日志 (${state.logs.length})',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Authorization switch: off means the agent auto-runs sensitive actions.
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hairline),
            ),
            child: Row(
              children: [
                Icon(
                  _safeMode ? Icons.shield_outlined : Icons.bolt_rounded,
                  size: 16,
                  color: _safeMode ? AppTheme.accent : Colors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '敏感操作人工授权',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _safeMode ? '支付 / 发布 / 删除前暂停并等待确认' : '已关闭：AI 将自动执行所有操作',
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _safeMode,
                  activeThumbColor: AppTheme.accent,
                  onChanged: _toggleSafeMode,
                ),
              ],
            ),
          ),

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
                      size: 16, color: Colors.amber),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.electric_bolt,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已成功执行 ${state.recordedMacroSteps.length} 个步骤',
                      style: TextStyle(fontSize: 12, color: onSurface),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saveAsMacro,
                    icon: const Icon(Icons.bookmark_add, size: 14),
                    label: const Text('存为快捷宏'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
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
                border:
                    Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
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
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            '一键复制',
                            style:
                                TextStyle(fontSize: 11, color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
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
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '页面弹出人机验证 (${state.captchaType ?? "验证码"})',
                          style: const TextStyle(
                            color: Colors.amber,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => widget.onConfirmCaptcha(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: muted,
                          side: BorderSide(color: hairline),
                        ),
                        child: const Text('中止任务'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => widget.onConfirmCaptcha(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
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
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: Colors.redAccent),
                      SizedBox(width: 6),
                      Text(
                        '敏感操作拦截提醒',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI 准备执行: ${state.currentAction?.description ?? ""}',
                    style: TextStyle(fontSize: 12, color: onSurface),
                  ),
                  if (state.confirmationReason != null &&
                      state.confirmationReason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '风险类型: ${state.confirmationReason}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_hostOf(state.targetUrl).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '目标站点: ${_hostOf(state.targetUrl)}',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => widget.onConfirmAction(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: muted,
                          side: BorderSide(color: hairline),
                        ),
                        child: const Text('取消任务'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => widget.onConfirmAction(true),
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
                      icon: const Icon(Icons.verified_user_outlined, size: 15),
                      label: Text(
                        '本站始终允许（${_hostOf(state.targetUrl)}）',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
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

          // Goal Input Field
          TextField(
            controller: _goalController,
            enabled: !isRunning,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入通用指令（抓取数据、发推、搜索、评论或任何网页操作）...',
              hintStyle: TextStyle(fontSize: 12, color: subtle),
              suffixIcon: isRunning
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_upward,
                          color: AppTheme.primary),
                      onPressed: () {
                        final text = _goalController.text.trim();
                        if (text.isNotEmpty) {
                          widget.onStart(text);
                        }
                      },
                    ),
            ),
          ),

          // Universal Workflow Recipe chips
          if (!isRunning) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: AppConstants.recipePresets.map((recipe) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ActionChip(
                      avatar: const Icon(Icons.auto_awesome,
                          size: 14, color: AppTheme.primary),
                      label: Text(
                        recipe['title']!,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      backgroundColor: surface,
                      side: BorderSide(color: hairline),
                      onPressed: () {
                        _goalController.text = recipe['prompt']!;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
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
                    label:
                        Text(state.status == AgentStatus.paused ? '恢复' : '暂停'),
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
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                    ),
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
