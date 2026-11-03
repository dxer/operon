import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../config/tool_catalog.dart';
import '../../models/llm_config.dart';
import '../../models/skill.dart';
import '../../services/skill_service.dart';
import '../../services/skill_validator.dart';
import '../../services/webview_controller_wrapper.dart';
import '../widgets/skill_ai_create_sheet.dart';
import '../widgets/skill_run_sheet.dart';
import 'skill_editor_page.dart';
import 'skill_runs_page.dart';

class SkillsPage extends StatefulWidget {
  final LlmConfig? config;
  final WebViewControllerWrapper? webView;
  final Future<void> Function(SkillRunRequest request)? onRun;

  const SkillsPage({
    super.key,
    this.config,
    this.webView,
    this.onRun,
  });

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  SkillService? _service;
  List<Skill> _skills = const [];
  bool _loading = true;
  String _query = '';
  String _filter = 'all';

  List<Skill> get _visibleSkills {
    final keyword = _query.trim().toLowerCase();
    return _skills.where((skill) {
      if (_filter == 'instruction' && skill.kind != SkillKind.instruction) {
        return false;
      }
      if (_filter == 'flow' && skill.kind != SkillKind.flow) {
        return false;
      }
      if (_filter == 'builtin' && !skill.builtin) return false;
      if (_filter == 'user' && skill.builtin) return false;
      if (keyword.isEmpty) return true;
      return skill.name.toLowerCase().contains(keyword) ||
          skill.description.toLowerCase().contains(keyword) ||
          (skill.kind == SkillKind.instruction
              ? skill.instructions.toLowerCase().contains(keyword)
              : skill.steps.any(
                  (step) =>
                      step.name.toLowerCase().contains(keyword) ||
                      step.tool.toLowerCase().contains(keyword),
                ));
    }).toList();
  }

  bool get _canReorder => _query.trim().isEmpty && _filter == 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _service = await SkillService.getInstance();
    if (!mounted) return;
    setState(() {
      _skills = _service!.getSkills();
      _loading = false;
    });
  }

  Future<void> _edit([Skill? skill]) async {
    final saved = await Navigator.of(context).push<Skill>(
      MaterialPageRoute(
        builder: (_) => SkillEditPage(
          skill: skill,
          config: widget.config,
          webView: widget.webView,
        ),
      ),
    );
    if (saved != null) await _load();
  }

  Future<void> _aiCreate() async {
    final config = widget.config;
    if (config == null || !config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在 AI 引擎设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    final skill = await showModalBottomSheet<Skill>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SkillAuthoringSheet(
        config: config,
        webView: widget.webView,
      ),
    );
    if (skill != null) await _load();
  }

  Future<void> _delete(Skill skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除技能？'),
        content: Text('「${skill.name}」将从列表中移除，已有运行记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service!.deleteSkill(skill.id);
    await _load();
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认技能？'),
        content: const Text('内置技能会恢复为初始版本，你自己创建的技能会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service!.restoreDefaults();
    await _load();
  }

  Future<void> _exportAll() async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'skills': _skills.map((skill) => skill.toJson()).toList(),
    });
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${_skills.length} 个技能到剪贴板')),
      );
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板里没有技能 JSON')),
      );
      return;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON 解析失败：$e')),
      );
      return;
    }
    final rawList = decoded is Map && decoded['skills'] is List
        ? decoded['skills'] as List
        : (decoded is List ? decoded : [decoded]);
    final validator = SkillValidator();
    final imported = <Skill>[];
    final errors = <String>[];
    for (final raw in rawList) {
      if (raw is! Map) {
        errors.add('条目不是 JSON 对象');
        continue;
      }
      try {
        final skill = Skill.fromJson(Map<String, dynamic>.from(raw));
        final validation = validator.validate(skill);
        if (validation.hasErrors) {
          errors.add('${skill.name}: ${validation.errors.first.message}');
          continue;
        }
        imported.add(skill);
      } catch (e) {
        errors.add('解析失败：$e');
      }
    }
    for (final skill in imported) {
      await _service!.saveSkill(skill);
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errors.isEmpty
              ? '已导入 ${imported.length} 个技能'
              : '已导入 ${imported.length} 个，跳过 ${errors.length} 个',
        ),
      ),
    );
  }

  Future<void> _run(Skill skill) async {
    final onRun = widget.onRun;
    if (onRun == null) return;
    final request = await showModalBottomSheet<SkillRunRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SkillRunSheet(
        skill: skill,
        webView: widget.webView,
      ),
    );
    if (request == null) return;
    await onRun(request);
    if (mounted) await _load();
  }

  String _riskSummary(Skill skill) {
    if (skill.kind == SkillKind.instruction) {
      return 'Agent 自主执行 · ${skill.policy.maxSteps} 步上限';
    }
    var writes = 0;
    var llm = 0;
    for (final step in skill.steps) {
      final tool = ToolCatalog.find(step.tool);
      if (tool?.isWrite == true) writes++;
      if (tool?.usesLlm == true) llm++;
    }
    return '${skill.steps.length} 个步骤'
        '${writes > 0 ? ' · $writes 个写入' : ''}'
        '${llm > 0 ? ' · $llm 次 AI' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('技能'),
        actions: [
          IconButton(
            tooltip: 'AI 创建',
            icon: const Icon(Icons.auto_awesome),
            onPressed: _loading ? null : _aiCreate,
          ),
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restore_rounded),
            onPressed: _loading ? null : _restoreDefaults,
          ),
          IconButton(
            tooltip: '新建技能',
            icon: const Icon(Icons.add_rounded),
            onPressed: _loading ? null : () => _edit(),
          ),
          PopupMenuButton<String>(
            tooltip: '导入导出',
            onSelected: (value) {
              if (value == 'export') _exportAll();
              if (value == 'import') _importFromClipboard();
              if (value == 'runs') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SkillRunsPage()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('导出全部到剪贴板')),
              PopupMenuItem(value: 'import', child: Text('从剪贴板导入')),
              PopupMenuItem(value: 'runs', child: Text('运行记录')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skills.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    _buildSearchAndFilter(isDark),
                    Expanded(
                      child: _visibleSkills.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的技能',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          : _canReorder
                              ? ReorderableListView.builder(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    90 +
                                        MediaQuery.of(context)
                                            .viewPadding
                                            .bottom,
                                  ),
                                  itemCount: _visibleSkills.length,
                                  onReorderItem: (oldIndex, newIndex) async {
                                    final list = [..._skills];
                                    final item = list.removeAt(oldIndex);
                                    final target = newIndex < 0
                                        ? 0
                                        : (newIndex > list.length
                                            ? list.length
                                            : newIndex);
                                    list.insert(target, item);
                                    setState(() => _skills = list);
                                    await _service!.saveSkills(list);
                                    await _load();
                                  },
                                  itemBuilder: (context, index) => _buildCard(
                                    _visibleSkills[index],
                                    isDark,
                                    key: ValueKey(_visibleSkills[index].id),
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    90 +
                                        MediaQuery.of(context)
                                            .viewPadding
                                            .bottom,
                                  ),
                                  itemCount: _visibleSkills.length,
                                  itemBuilder: (context, index) => _buildCard(
                                    _visibleSkills[index],
                                    isDark,
                                    key: ValueKey(_visibleSkills[index].id),
                                  ),
                                ),
                    ),
                  ],
                ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _aiCreate,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI 创建'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
    );
  }

  Widget _buildCard(
    Skill skill,
    bool isDark, {
    Key? key,
  }) {
    return _SkillCard(
      key: key,
      skill: skill,
      isDark: isDark,
      summary: _riskSummary(skill),
      onRun: widget.onRun == null ? null : () => _run(skill),
      onEdit: () => _edit(skill),
      onDelete: () => _delete(skill),
    );
  }

  Widget _buildSearchAndFilter(bool isDark) {
    final filters = <String, String>{
      'all': '全部',
      'user': '我的',
      'builtin': '内置',
      'instruction': '指令型',
      'flow': '流程型',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索技能名称、说明或工具',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: filters.entries.map((entry) {
                final selected = _filter == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primary,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Text('还没有技能', style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          Text(
            '用一句话描述任务，让 AI 起草；也可以手动创建',
            style: TextStyle(fontSize: 12, color: muted.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _aiCreate,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('用 AI 创建第一个技能'),
          ),
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final Skill skill;
  final bool isDark;
  final String summary;
  final VoidCallback? onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SkillCard({
    super.key,
    required this.skill,
    required this.isDark,
    required this.summary,
    this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: isDark ? 0.7 : 0.58);
    const accent = AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    skill.isFlow
                        ? Icons.account_tree_outlined
                        : Icons.auto_awesome,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              skill.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (skill.builtin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '内置',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        skill.description.isEmpty
                            ? '${skill.kind.label} · $summary'
                            : skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRun != null)
                  IconButton(
                    tooltip: '运行',
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    onPressed: onRun,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${skill.kind.label} · $summary',
                  style: TextStyle(fontSize: 9.5, color: muted),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('编辑', style: TextStyle(fontSize: 11)),
                ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: AppTheme.danger,
                  ),
                  child: const Text('删除', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
