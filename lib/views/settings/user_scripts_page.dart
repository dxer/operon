import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/user_script.dart';
import '../../services/llm_service.dart';
import '../../services/storage_service.dart';
import '../../services/user_script_service.dart';

class UserScriptsPage extends StatefulWidget {
  final String? currentUrl;
  final String? currentTitle;
  final String? domSnippet;

  const UserScriptsPage({
    super.key,
    this.currentUrl,
    this.currentTitle,
    this.domSnippet,
  });

  @override
  State<UserScriptsPage> createState() => _UserScriptsPageState();
}

class _UserScriptsPageState extends State<UserScriptsPage> {
  UserScriptService? _scriptService;
  List<UserScript> _scripts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    _scriptService = await UserScriptService.getInstance();
    setState(() {
      _scripts = _scriptService!.getScripts();
      _isLoading = false;
    });
  }

  Future<void> _toggleScript(UserScript script, bool enabled) async {
    await _scriptService?.toggleScript(script.id, enabled);
    if (!mounted) return;
    setState(() {
      final index = _scripts.indexWhere((s) => s.id == script.id);
      if (index != -1) {
        _scripts[index] = _scripts[index].copyWith(isEnabled: enabled);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(enabled ? '已启用脚本: ${script.name}' : '已禁用脚本: ${script.name}'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  Future<void> _deleteScript(UserScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除脚本「${script.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _scriptService?.deleteScript(script.id);
      if (!mounted) return;
      setState(() {
        _scripts.removeWhere((s) => s.id == script.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除脚本: ${script.name}')),
      );
    }
  }

  void _showAiGeneratorDialog() {
    final promptController = TextEditingController();
    bool isGenerating = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Colors.amber, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'AI 生成用户脚本',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.currentUrl != null &&
                      widget.currentUrl!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF16181C)
                            : const Color(0xFFEFF3F4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link,
                              size: 14, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '当前页面: ${widget.currentTitle ?? widget.currentUrl}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    '告诉我你希望对网页实现什么效果（例如：自动关闭登录弹窗、去除广告横幅、深色背景增强）：',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: promptController,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '例如：每次打开知乎时，自动把登录遮罩删除，并展开折叠的全文内容...',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt, size: 18),
                    label: Text(isGenerating ? 'AI 正在分析并编写脚本...' : '开始生成脚本'),
                    onPressed: isGenerating
                        ? null
                        : () async {
                            final prompt = promptController.text.trim();
                            if (prompt.isEmpty) return;

                            setModalState(() {
                              isGenerating = true;
                              errorText = null;
                            });

                            try {
                              final storage =
                                  await StorageService.getInstance();
                              final config = storage.getLlmConfig();
                              if (!config.isValid) {
                                throw Exception('请先在浏览器设置中配置有效的大模型 API Key');
                              }

                              final llm = LlmService();
                              Map<String, String> res;
                              try {
                                res = await llm.generateUserScript(
                                  config: config,
                                  prompt: prompt,
                                  currentUrl: widget.currentUrl ?? '',
                                  pageTitle: widget.currentTitle ?? '',
                                  domSnippet: widget.domSnippet,
                                );
                              } finally {
                                llm.dispose();
                              }

                              if (mounted && ctx.mounted) {
                                Navigator.pop(ctx);
                                _showScriptEditorDialog(
                                  initialScript: UserScript(
                                    id: 'script_${DateTime.now().millisecondsSinceEpoch}',
                                    name: res['name'] ?? '自定义 AI 脚本',
                                    description: res['description'] ?? prompt,
                                    matchPattern: res['matchPattern'] ?? '*',
                                    code: res['code'] ?? '',
                                    isEnabled: true,
                                    createdAt: DateTime.now(),
                                  ),
                                  isNew: true,
                                );
                              }
                            } catch (e) {
                              setModalState(() {
                                isGenerating = false;
                                errorText = '生成失败: $e';
                              });
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showScriptEditorDialog(
      {UserScript? initialScript, bool isNew = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: initialScript?.name ?? '');
    final descCtrl =
        TextEditingController(text: initialScript?.description ?? '');
    final matchCtrl =
        TextEditingController(text: initialScript?.matchPattern ?? '*');
    final codeCtrl = TextEditingController(
      text: initialScript?.code ??
          '(() => {\n  try {\n    // 在此编写你的 JS 代码\n  } catch (e) {\n    console.error(e);\n  }\n})();',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isNew ? Icons.add_circle_outline : Icons.edit_note,
                color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(isNew ? '新建用户脚本' : '编辑脚本'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '脚本名称',
                    hintText: '例如: 知乎自动展开',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: matchCtrl,
                  decoration: const InputDecoration(
                    labelText: '适用网址 (域名通配符)',
                    hintText: '如 *zhihu.com* 或 * 表示所有网址',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: '功能描述',
                    hintText: '简要说明此脚本的用途',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('JavaScript 代码:',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: codeCtrl.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制脚本代码到剪贴板')),
                        );
                      },
                    ),
                  ],
                ),
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF14181F)
                        : const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: codeCtrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final script = UserScript(
                id: initialScript?.id ??
                    'script_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                description: descCtrl.text.trim(),
                matchPattern:
                    matchCtrl.text.trim().isEmpty ? '*' : matchCtrl.text.trim(),
                code: codeCtrl.text.trim(),
                isEnabled: initialScript?.isEnabled ?? true,
                createdAt: initialScript?.createdAt ?? DateTime.now(),
                updatedAt: DateTime.now(),
              );

              await _scriptService?.saveScript(script);
              await _loadScripts();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(isNew ? '已添加并启用脚本: $name' : '已保存修改: $name')),
              );
            },
            child: const Text('保存脚本'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 脚本工坊 (UserScripts)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '手动添加脚本',
            onPressed: () => _showScriptEditorDialog(isNew: true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) async {
              if (val == 'reset') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('重置预设'),
                    content: const Text('是否恢复默认预设脚本？自定义脚本将被覆盖。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent),
                        child: const Text('重置'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _scriptService?.resetToDefaults();
                  await _loadScripts();
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('恢复默认脚本预设'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Banner
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 20, color: AppTheme.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '网页加载完成后自动执行匹配的脚本。随时切换开关即可立即启动或关闭单个脚本。',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),

                // Script List
                Expanded(
                  child: _scripts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.code_off,
                                  size: 48,
                                  color:
                                      isDark ? Colors.white30 : Colors.black26),
                              const SizedBox(height: 12),
                              const Text('暂无脚本',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              const Text('点击下方按钮让 AI 为当前网页编写专属脚本',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: _scripts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final script = _scripts[index];
                            return _buildScriptCard(script, isDark);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI 帮我写脚本'),
        onPressed: _showAiGeneratorDialog,
      ),
    );
  }

  Widget _buildScriptCard(UserScript script, bool isDark) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: script.isEnabled
              ? AppTheme.primary.withValues(alpha: 0.35)
              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          width: script.isEnabled ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.javascript,
                        size: 24,
                        color: script.isEnabled ? Colors.amber : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          script.name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: script.isEnabled ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle Switch for Enable / Disable
                Switch.adaptive(
                  value: script.isEnabled,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) => _toggleScript(script, val),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Match Pattern Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF19202A) : const Color(0xFFEFF3F4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '适用: ${script.matchPattern}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),

            if (script.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                script.description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],

            const Divider(height: 16),

            // Bottom action row: Edit, View Code, Delete
            Row(
              children: [
                Text(
                  '${script.code.length} 字符',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.code, size: 15),
                  label: const Text('查看/编辑', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showScriptEditorDialog(
                      initialScript: script, isNew: false),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.redAccent),
                  tooltip: '删除脚本',
                  onPressed: () => _deleteScript(script),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
