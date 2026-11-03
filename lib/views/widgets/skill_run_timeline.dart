import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../models/skill_run.dart';

class SkillRunTimeline extends StatelessWidget {
  final SkillRunState state;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final VoidCallback? onRetry;
  final VoidCallback? onRepair;
  final String? shownMarkdown;

  const SkillRunTimeline({
    super.key,
    required this.state,
    this.onCancel,
    this.onClose,
    this.onRetry,
    this.onRepair,
    this.shownMarkdown,
  });

  Color _statusColor(SkillRunStatus status) {
    switch (status) {
      case SkillRunStatus.idle:
        return AppTheme.neutral;
      case SkillRunStatus.running:
        return AppTheme.primary;
      case SkillRunStatus.completed:
        return AppTheme.accent;
      case SkillRunStatus.failed:
        return AppTheme.danger;
      case SkillRunStatus.cancelled:
        return AppTheme.neutral;
    }
  }

  Color _stepColor(SkillStepStatus status) {
    switch (status) {
      case SkillStepStatus.pending:
        return AppTheme.neutral;
      case SkillStepStatus.running:
        return AppTheme.primary;
      case SkillStepStatus.succeeded:
        return AppTheme.accent;
      case SkillStepStatus.failed:
        return AppTheme.danger;
      case SkillStepStatus.skipped:
        return AppTheme.neutral;
      case SkillStepStatus.cancelled:
        return AppTheme.neutral;
    }
  }

  IconData _stepIcon(SkillStepStatus status) {
    switch (status) {
      case SkillStepStatus.pending:
        return Icons.radio_button_unchecked;
      case SkillStepStatus.running:
        return Icons.autorenew_rounded;
      case SkillStepStatus.succeeded:
        return Icons.check_circle_rounded;
      case SkillStepStatus.failed:
        return Icons.error_rounded;
      case SkillStepStatus.skipped:
        return Icons.skip_next_rounded;
      case SkillStepStatus.cancelled:
        return Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final statusColor = _statusColor(state.status);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewPadding.bottom + 16,
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
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 18, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.skillName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.status.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            state.currentStepName == null
                ? '第 ${state.currentStep}/${state.totalSteps} 步'
                : '第 ${state.currentStep}/${state.totalSteps} 步 · ${state.currentStepName}',
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                state.error!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.danger,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ...state.results.asMap().entries.map((entry) {
                  final result = entry.value;
                  final color = _stepColor(result.status);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        leading: Icon(
                          _stepIcon(result.status),
                          size: 18,
                          color: color,
                        ),
                        title: Text(
                          '${entry.key + 1}. ${result.name}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${result.tool} · ${result.status.label}'
                          '${result.durationMs > 0 ? ' · ${result.durationMs}ms' : ''}',
                          style: TextStyle(fontSize: 10.5, color: muted),
                        ),
                        children: [
                          if (result.errorMessage != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                result.errorMessage!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          if (result.data != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppTheme.darkBg
                                      : AppTheme.lightBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  _pretty(result.data),
                                  maxLines: 12,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.35,
                                    color: onSurface,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if (shownMarkdown != null &&
                    shownMarkdown!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '结果',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline),
                    ),
                    child: SelectableText(
                      shownMarkdown!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: onSurface,
                      ),
                    ),
                  ),
                ],
                if (state.output.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '输出',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline),
                    ),
                    child: SelectableText(
                      _pretty(state.output),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (state.status == SkillRunStatus.running && onCancel != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('停止'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                  ),
                ),
              if (state.status != SkillRunStatus.running) ...[
                if (onRetry != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('再运行'),
                    ),
                  ),
                if (state.status == SkillRunStatus.failed && onRepair != null)
                  IconButton(
                    tooltip: '尝试修复失效的定位器',
                    onPressed: onRepair,
                    icon: const Icon(Icons.build_outlined, size: 18),
                  ),
                if (onClose != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onClose,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('关闭'),
                    ),
                  ),
              ],
              if (state.status == SkillRunStatus.completed &&
                  state.output.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '复制输出',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _pretty(state.output)),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制技能输出')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _pretty(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }
}
