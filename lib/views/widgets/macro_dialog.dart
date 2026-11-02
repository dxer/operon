import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/macro_workflow.dart';
import '../../services/macro_service.dart';

class MacroDialog extends StatefulWidget {
  final Function(MacroWorkflow macro) onRunMacro;

  const MacroDialog({Key? key, required this.onRunMacro}) : super(key: key);

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
    setState(() {
      _macros = _macroService.getMacros();
      _isLoading = false;
    });
  }

  Future<void> _delete(String id) async {
    await _macroService.deleteMacro(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.bolt, color: Colors.amber, size: 22),
          SizedBox(width: 8),
          Text('零 Token 快捷宏库', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _macros.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text(
                        '暂无已保存的宏任务。\n当 AI 自动化完成一次任务后，可点击“存为快捷宏”！',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _macros.length,
                    separatorBuilder: (_, __) => const Divider(color: AppTheme.darkBorder),
                    itemBuilder: (ctx, idx) {
                      final m = _macros[idx];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          m.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '包含 ${m.steps.length} 个确定性步骤 • 0 Token消耗',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: AppTheme.accent),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onRunMacro(m);
                              },
                              tooltip: '立即执行宏',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
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
