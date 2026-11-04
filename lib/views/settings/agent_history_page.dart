import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_task_record.dart';
import '../../models/macro_workflow.dart';
import '../../services/skill_from_macro.dart';
import '../../services/skill_from_task.dart';
import '../../services/skill_validator.dart';
import '../../services/storage_service.dart';
import 'skill_editor_page.dart';

class AgentHistoryPage extends StatefulWidget {
  const AgentHistoryPage({super.key});

  @override
  State<AgentHistoryPage> createState() => _AgentHistoryPageState();
}

class _AgentHistoryPageState extends State<AgentHistoryPage> {
  late StorageService _storage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _storage = await StorageService.getInstance();
    if (mounted) setState(() => _isLoading = false);
  }

  List<AgentTaskRecord> get _records => _storage.getAgentTaskHistory();

  void _clearAll() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空任务历史？'),
        content: const Text('所有任务的执行记录与审计日志都会被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _storage.clearAgentTaskHistory();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: Text('清空', style: TextStyle(color: AppTheme.dangerOf(isDark))),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(AgentTaskRecord record) async {
    await _storage.removeAgentTaskRecord(record.id);
    if (mounted) setState(() {});
  }

  Future<void> _saveAsSkill(AgentTaskRecord record) async {
    final macro = MacroWorkflow(
      id: 'history_${record.id}',
      title: record.goal.isEmpty ? '历史任务技能' : record.goal,
      initialUrl: record.targetUrl ?? '',
      createdAt: record.startedAt,
      steps: record.recordedMacroSteps,
    );
    final converted = SkillFromMacro.fromMacro(macro);
    if (converted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这条记录没有可转换的动作'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    // Same rule as saving from the live task: a recorded demo text becomes an
    // input, otherwise replaying the skill would keep posting the same words.
    final draft = SkillFromTask.withContentInput(converted);
    if (!draft.steps.any((step) => SkillFromMacro.isWrite(step.tool))) {
      // Navigation-only recordings do not make a useful flow skill.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这条记录没有实际写入动作，无法存为可重放的流程'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    final host = Uri.tryParse(record.targetUrl ?? '')?.host ?? '';
    final validation = SkillValidator().validateDraft(
      draft,
      allowWrites: true,
      currentHost: host.isEmpty ? null : host,
    );
    if (validation.hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法转换：${validation.errors.first.message}'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    final saved = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkillEditPage(draft: draft),
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存为技能，可在「设置 → 技能」继续编辑'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final records = _records;

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务历史与审计'),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: '清空全部',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 56,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有任务记录',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '完成、异常或达到步数上限的 AI 任务会自动记录在这里',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return _RecordTile(
                  record: record,
                  isDark: isDark,
                  onDelete: () => _delete(record),
                  onSaveAsSkill: () => _saveAsSkill(record),
                );
              },
            ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final AgentTaskRecord record;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onSaveAsSkill;

  const _RecordTile({
    required this.record,
    required this.isDark,
    required this.onDelete,
    required this.onSaveAsSkill,
  });

  Color get _successColor => AppTheme.accentOf(isDark);
  Color get _warningColor => AppTheme.warningOf(isDark);
  Color get _dangerColor => AppTheme.dangerOf(isDark);
  Color get _neutralColor => isDark ? AppTheme.darkMuted : AppTheme.lightMuted;

  Color get _statusColor {
    switch (record.status) {
      case 'completed':
        return _successColor;
      case 'maxStepsReached':
        return _warningColor;
      case 'error':
        return _dangerColor;
      case 'stopped':
        return _neutralColor;
      default:
        return _neutralColor;
    }
  }

  String get _statusLabel {
    switch (record.status) {
      case 'completed':
        return '已完成';
      case 'maxStepsReached':
        return '达到步数上限';
      case 'error':
        return '执行异常';
      case 'stopped':
        return '已手动停止';
      default:
        return record.status;
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _timeLabel {
    final t = record.startedAt;
    return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final seconds = record.duration.inSeconds;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: Text(
          record.goal.isEmpty ? '未命名任务' : record.goal,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _pill(_statusLabel, _statusColor),
              if (record.hasSensitiveActions)
                _pill('敏感操作 ${record.sensitiveActions.length}', _warningColor),
              if (!record.safeMode) _pill('完全自主', _dangerColor),
              Text(
                '$_timeLabel · ${record.steps}/${record.maxSteps} 步 · ${seconds}s',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        children: [
          if (record.errorMessage != null &&
              record.errorMessage!.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                record.errorMessage!,
                style: TextStyle(fontSize: 12, color: AppTheme.dangerOf(isDark)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (record.recordedMacroSteps.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onSaveAsSkill,
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: Text(
                  '存为技能（${record.recordedMacroSteps.length} 步）',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (record.hasSensitiveActions) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '授权与风险记录',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...record.sensitiveActions.map(
              (line) => Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $line',
                    style: TextStyle(fontSize: 11, color: _warningColor),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '执行日志',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (record.logs.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('无日志', style: TextStyle(fontSize: 11, color: muted)),
            )
          else
            ...record.logs.map(
              (line) => Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('删除这条记录', style: TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.dangerOf(isDark),
                minimumSize: const Size(0, 30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
