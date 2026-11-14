import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/agent_prompt.dart';
import '../../services/storage_service.dart';

/// Saved prompts: a name, and a sentence the agent should be asked again.
///
/// The list is short by design. These are the tasks a person actually repeats
/// — "整理今天的 AI 新闻", "把这个页面填成草稿" — not a script library.
class AgentPromptsPage extends StatefulWidget {
  const AgentPromptsPage({super.key});

  @override
  State<AgentPromptsPage> createState() => _AgentPromptsPageState();
}

class _AgentPromptsPageState extends State<AgentPromptsPage> {
  late StorageService _storage;
  bool _isLoading = true;
  List<AgentPrompt> _prompts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _storage = await StorageService.getInstance();
    _prompts = _storage.getAgentPrompts();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save(List<AgentPrompt> prompts) async {
    await _storage.saveAgentPrompts(prompts);
    if (!mounted) return;
    setState(() => _prompts = prompts);
  }

  Future<void> _edit([AgentPrompt? existing]) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final goalController = TextEditingController(text: existing?.goal ?? '');
    final result = await showDialog<AgentPrompt>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '新建快捷指令' : '编辑快捷指令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：今日 AI 新闻',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: goalController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '要发送的指令',
                hintText: '例如：搜索今天的 AI 新闻并总结要点',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final goal = goalController.text.trim();
              if (goal.isEmpty) {
                Navigator.of(ctx).pop();
                return;
              }
              final title = titleController.text.trim();
              Navigator.of(ctx).pop(AgentPrompt(
                id: existing?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                title: title.isEmpty ? goal : title,
                goal: goal,
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;

    final list = [..._prompts];
    final index = list.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      list[index] = result;
    } else {
      list.add(result);
    }
    await _save(list);
  }

  Future<void> _delete(AgentPrompt prompt) async {
    await _save([..._prompts]..removeWhere((item) => item.id == prompt.id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Scaffold(
      appBar: AppBar(title: const Text('快捷指令')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 96 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Text(
            '在输入框里打一个「/」就能选。存的是这句话，不是一组动作：'
            '每次怎么点、怎么填，由智能体按当时的页面决定。',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppTheme.neutralOf(isDark),
            ),
          ),
          const SizedBox(height: 14),
          if (_prompts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  '还没有快捷指令',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
            )
          else
            for (final prompt in _prompts)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.8),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt.displayTitle,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prompt.goal,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppTheme.neutralOf(isDark),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _edit(prompt),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('编辑',
                              style: TextStyle(fontSize: 11.5)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryOf(isDark),
                            minimumSize: const Size(0, 30),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _delete(prompt),
                          icon: const Icon(Icons.delete_outline, size: 15),
                          label: const Text('删除',
                              style: TextStyle(fontSize: 11.5)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.dangerOf(isDark),
                            minimumSize: const Size(0, 30),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
