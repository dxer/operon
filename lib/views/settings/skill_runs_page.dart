import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/skill_run.dart';
import '../../services/storage_service.dart';
import '../widgets/skill_run_timeline.dart';

class SkillRunsPage extends StatefulWidget {
  const SkillRunsPage({super.key});

  @override
  State<SkillRunsPage> createState() => _SkillRunsPageState();
}

class _SkillRunsPageState extends State<SkillRunsPage> {
  List<SkillRunRecord> _runs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await StorageService.getInstance();
    if (!mounted) return;
    setState(() {
      _runs = storage.getSkillRuns();
      _loading = false;
    });
  }

  Future<void> _delete(SkillRunRecord record) async {
    final storage = await StorageService.getInstance();
    await storage.removeSkillRun(record.id);
    await _load();
  }

  Future<void> _clear() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空技能运行记录？'),
        content: const Text('只删除本地审计记录，不会影响技能本身。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: TextStyle(color: AppTheme.dangerOf(isDark))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final storage = await StorageService.getInstance();
    await storage.clearSkillRuns();
    await _load();
  }

  void _show(SkillRunRecord record) {
    final state = SkillRunState(
      runId: record.id,
      skillId: record.skillId,
      skillName: record.skillName,
      status: record.status,
      currentStep: record.steps.length,
      totalSteps: record.steps.length,
      results: record.steps,
      output: record.output,
      error: record.error,
      url: record.url,
      llmCalls: record.llmCalls,
      sideEffects: record.sideEffects,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SkillRunTimeline(
        state: state,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Color _statusColor(SkillRunStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case SkillRunStatus.idle:
        return AppTheme.neutralOf(isDark);
      case SkillRunStatus.running:
        return AppTheme.primaryOf(isDark);
      case SkillRunStatus.completed:
        return AppTheme.accentOf(isDark);
      case SkillRunStatus.failed:
        return AppTheme.dangerOf(isDark);
      case SkillRunStatus.cancelled:
        return AppTheme.neutralOf(isDark);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('技能运行记录'),
        actions: [
          if (_runs.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? Center(
                  child: Text(
                    '还没有运行记录',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    16 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  itemCount: _runs.length,
                  itemBuilder: (context, index) {
                    final run = _runs[index];
                    final color = _statusColor(run.status);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _show(run),
                        leading: Icon(
                          run.status == SkillRunStatus.completed
                              ? Icons.check_circle_outline
                              : (run.status == SkillRunStatus.failed
                                  ? Icons.error_outline
                                  : Icons.history_rounded),
                          color: color,
                        ),
                        title: Text(
                          run.skillName,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${run.status.label} · ${run.steps.length} 步'
                          '${run.llmCalls > 0 ? ' · ${run.llmCalls} 次 AI' : ''}'
                          '${run.sideEffects > 0 ? ' · ${run.sideEffects} 次写入' : ''}',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _delete(run),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
