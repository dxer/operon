import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/macro_workflow.dart';
import '../../services/macro_service.dart';

class MacroDialog extends StatefulWidget {
  final Function(MacroWorkflow macro) onRunMacro;

  const MacroDialog({super.key, required this.onRunMacro});

  @override
  State<MacroDialog> createState() => _MacroDialogState();
}

class _MacroDialogState extends State<MacroDialog> {
  late MacroService _macroService;
  List<MacroWorkflow> _macros = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _macroService = await MacroService.getInstance();
    if (!mounted) return;
    setState(() {
      _macros = _macroService.getMacros();
      _isLoading = false;
    });
  }

  Future<void> _delete(String id) async {
    await _macroService.deleteMacro(id);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.bolt, color: AppTheme.warningOf(isDark), size: 22),
          const SizedBox(width: 8),
          const Text('零 Token 快捷宏库', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _macros.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text(
                        '暂无已保存的宏任务。\n当 AI 自动化完成一次任务后，可点击“存为快捷宏”！',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _macros.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final m = _macros[idx];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          m.title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '包含 ${m.steps.length} 个确定性步骤 • 0 Token消耗',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.play_circle_fill,
                                  color: AppTheme.accentOf(isDark)),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onRunMacro(m);
                              },
                              tooltip: '立即执行宏',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: muted),
                              onPressed: () => _delete(m.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
