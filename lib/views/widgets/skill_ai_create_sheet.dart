import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/tool_catalog.dart';
import '../../models/llm_config.dart';
import '../../models/skill.dart';
import '../../services/skill_authoring_service.dart';
import '../../services/skill_precheck_service.dart';
import '../../services/skill_service.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../utils/cancellation.dart';
import '../settings/skill_editor_page.dart';

class SkillAuthoringSheet extends StatefulWidget {
  final LlmConfig config;
  final WebViewControllerWrapper? webView;

  const SkillAuthoringSheet({
    super.key,
    required this.config,
    this.webView,
  });

  @override
  State<SkillAuthoringSheet> createState() => _SkillAuthoringSheetState();
}

class _SkillAuthoringSheetState extends State<SkillAuthoringSheet> {
  final TextEditingController _description = TextEditingController();
  final CancellationToken _token = CancellationToken();
  final SkillAuthoringService _service = SkillAuthoringService();

  bool _referencePage = true;
  bool _allowWrites = false;
  bool _generating = false;
  bool _checking = false;
  String _stage = '';
  SkillAuthoringResult? _result;

  @override
  void dispose() {
    _description.dispose();
    _token.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _description.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先描述你想让技能做什么')),
      );
      return;
    }
    if (!widget.config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: '知道了',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    setState(() {
      _generating = true;
      _result = null;
      _stage = '正在准备…';
    });
    final service = await SkillService.getInstance();
    final existingNames =
        service.getSkills().map((skill) => skill.name).toList();
    if (!mounted) return;
    final result = await _service.generate(
      description: text,
      config: widget.config,
      existingNames: existingNames,
      webView: widget.webView,
      referencePage: _referencePage,
      allowWrites: _allowWrites,
      restrictToCurrentHost: _allowWrites,
      token: _token,
      onProgress: (stage) {
        if (mounted) setState(() => _stage = stage);
      },
    );
    if (!mounted) return;
    setState(() {
      _generating = false;
      _result = result;
      _stage = '';
    });
  }

  Future<void> _precheck() async {
    final draft = _result?.draft;
    final webView = widget.webView;
    if (draft == null || webView == null) return;
    setState(() => _checking = true);
    final items = await SkillPrecheckService().check(draft, webView);
    if (!mounted) return;
    setState(() => _checking = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('定位器预检'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.isEmpty
                ? const [
                    Text(
                      '这个技能没有需要检查的定位器。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ]
                : items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.found
                                  ? Icons.check_circle_outline
                                  : (item.ambiguous
                                      ? Icons.error_outline
                                      : Icons.help_outline),
                              size: 15,
                              color: item.found
                                  ? AppTheme.accent
                                  : (item.ambiguous
                                      ? AppTheme.warning
                                      : AppTheme.danger),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${item.stepName} · ${item.param}\n${item.detail}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDraft() async {
    final draft = _result?.draft;
    if (draft == null) return;
    final skill = await Navigator.of(context).push<Skill>(
      MaterialPageRoute(
        builder: (_) => SkillEditPage(
          draft: draft,
          config: widget.config,
          webView: widget.webView,
        ),
      ),
    );
    if (skill != null && mounted) {
      Navigator.of(context).pop(skill);
    }
  }

  void _manualCreate() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => SkillEditPage(
          config: widget.config,
          webView: widget.webView,
        ),
      ),
    )
        .then((skill) {
      if (skill is Skill && mounted) {
        Navigator.of(context).pop(skill);
      }
    });
  }

  String _riskSummary(SkillDraft draft) {
    var writes = 0;
    var llm = 0;
    for (final step in draft.steps) {
      final tool = ToolCatalog.find(step.tool);
      if (tool?.isWrite == true) writes++;
      if (tool?.usesLlm == true) llm++;
    }
    return '${draft.steps.length} 个步骤'
        '${writes > 0 ? ' · $writes 个写入' : ''}'
        '${llm > 0 ? ' · $llm 次 AI' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final result = _result;
    final draft = result?.draft;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            16,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '用 AI 创建技能',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
              if (_generating)
                TextButton(
                  onPressed: () {
                    _token.cancel();
                    setState(() {
                      _generating = false;
                      _stage = '已取消';
                    });
                  },
                  child: const Text('取消'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_generating,
                    decoration: InputDecoration(
                      hintText: '例如：读取当前页面评论区，按主题总结，并给出三条建议',
                      hintStyle: TextStyle(fontSize: 12, color: muted),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _preset('评论区总结'),
                      _preset('收集本页链接'),
                      _preset('总结当前页面'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title:
                        const Text('参考当前页面', style: TextStyle(fontSize: 12.5)),
                    subtitle: const Text(
                      '只发送标题、网址和正文摘要，不发送输入框内容',
                      style: TextStyle(fontSize: 10),
                    ),
                    value: _referencePage,
                    onChanged: _generating
                        ? null
                        : (value) => setState(() => _referencePage = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title:
                        const Text('允许写入操作', style: TextStyle(fontSize: 12.5)),
                    subtitle: const Text(
                      '允许生成点击、输入等步骤；运行前仍会确认',
                      style: TextStyle(fontSize: 10),
                    ),
                    value: _allowWrites,
                    onChanged: _generating
                        ? null
                        : (value) => setState(() => _allowWrites = value),
                  ),
                  if (_allowWrites)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 13, color: muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '写入技能默认仅限当前网站，运行前仍会逐步确认',
                              style: TextStyle(fontSize: 10.5, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_generating) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: AppTheme.primary,
                      backgroundColor: hairline,
                    ),
                    const SizedBox(height: 6),
                    Text(_stage, style: TextStyle(fontSize: 11, color: muted)),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (draft != null) ...[
                            Text(
                              draft.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              draft.description,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${draft.kind.label} · ${_riskSummary(draft)}',
                              style: TextStyle(fontSize: 10.5, color: muted),
                            ),
                          ],
                          if (result.error != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              result.error!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.danger,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (result.validation.errors.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...result.validation.errors.take(5).map(
                                  (issue) => Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      '• ${issue.message}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.danger,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _generating ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _generating
                      ? null
                      : (draft != null && result?.ok == true
                          ? _editDraft
                          : _generate),
                  icon: Icon(
                    draft != null && result?.ok == true
                        ? Icons.edit_outlined
                        : Icons.auto_awesome,
                    size: 16,
                  ),
                  label: Text(
                    draft != null && result?.ok == true
                        ? '编辑并保存'
                        : (result == null ? '生成技能' : '再试一次'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (draft != null && result?.ok == true && widget.webView != null)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _checking ? null : _precheck,
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.center_focus_strong, size: 15),
                label: const Text('检查定位器'),
              ),
            ),
          if (result != null && result.ok != true)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _manualCreate,
                child: const Text('手动创建'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preset(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 10.5)),
      onPressed: _generating ? null : () => _description.text = text,
      visualDensity: VisualDensity.compact,
    );
  }
}
