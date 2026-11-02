import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../config/tool_catalog.dart';
import '../../models/llm_config.dart';
import '../../models/skill.dart';
import '../../models/tool_descriptor.dart';
import '../../services/skill_authoring_service.dart';
import '../../services/skill_service.dart';
import '../../services/skill_validator.dart';
import '../../services/webview_controller_wrapper.dart';

class SkillEditPage extends StatefulWidget {
  final Skill? skill;
  final SkillDraft? draft;
  final LlmConfig? config;
  final WebViewControllerWrapper? webView;

  const SkillEditPage({
    super.key,
    this.skill,
    this.draft,
    this.config,
    this.webView,
  });

  @override
  State<SkillEditPage> createState() => _SkillEditPageState();
}

class _SkillEditPageState extends State<SkillEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _instructions;
  late final TextEditingController _maxSteps;
  late final TextEditingController _maxLlmCalls;
  late final TextEditingController _maxSideEffects;
  late final TextEditingController _maxItems;
  late final TextEditingController _maxDuration;
  late final TextEditingController _pacing;
  late final TextEditingController _allowedHosts;
  late final TextEditingController _output;

  late SkillKind _kind;
  late List<SkillInput> _inputs;
  late List<SkillStep> _steps;
  late SkillHostScope _hostScope;
  late bool _uniqueTarget;
  late bool _uniqueContent;
  late bool _confirmWrites;
  late bool _confirmDestructive;
  bool _saving = false;
  bool _aiBusy = false;

  Skill? get _existing => widget.skill;

  @override
  void initState() {
    super.initState();
    final source = widget.skill;
    final draft = widget.draft;
    _name = TextEditingController(text: source?.name ?? draft?.name ?? '');
    _description = TextEditingController(
      text: source?.description ?? draft?.description ?? '',
    );
    _instructions = TextEditingController(
      text: source?.instructions ?? draft?.instructions ?? '',
    );
    _kind = source?.kind ?? draft?.kind ?? SkillKind.flow;
    _inputs =
        List<SkillInput>.from(source?.inputs ?? draft?.inputs ?? const []);
    _steps = List<SkillStep>.from(source?.steps ?? draft?.steps ?? const []);

    final policy = source?.policy ?? draft?.policy ?? const SkillPolicy();
    _maxSteps = TextEditingController(text: '${policy.maxSteps}');
    _maxLlmCalls = TextEditingController(text: '${policy.maxLlmCalls}');
    _maxSideEffects = TextEditingController(text: '${policy.maxSideEffects}');
    _maxItems = TextEditingController(text: '${policy.maxItems}');
    _maxDuration = TextEditingController(text: '${policy.maxDurationMs}');
    _pacing = TextEditingController(text: '${policy.pacingMs}');
    _allowedHosts = TextEditingController(text: policy.allowedHosts.join(', '));
    _output = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(source?.output ?? const <String, String>{}),
    );
    _hostScope = policy.hostScope;
    _uniqueTarget = policy.uniqueTarget;
    _uniqueContent = policy.uniqueContent;
    _confirmWrites = policy.confirmWrites;
    _confirmDestructive = policy.confirmDestructive;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    _maxSteps.dispose();
    _maxLlmCalls.dispose();
    _maxSideEffects.dispose();
    _maxItems.dispose();
    _maxDuration.dispose();
    _pacing.dispose();
    _allowedHosts.dispose();
    _output.dispose();
    super.dispose();
  }

  Skill _buildSkill() {
    final now = DateTime.now();
    final existing = _existing;
    return Skill(
      id: existing?.id ??
          'skill_${DateTime.now().millisecondsSinceEpoch.toString()}',
      name: _name.text.trim(),
      description: _description.text.trim(),
      kind: _kind,
      origin: existing?.origin ?? SkillOrigin.user,
      version: existing?.version ?? 1,
      inputs: _inputs,
      instructions: _instructions.text.trim(),
      steps: _steps,
      output: _parseOutput(),
      policy: SkillPolicy(
        maxSteps: _int(_maxSteps.text, 30),
        maxLlmCalls: _int(_maxLlmCalls.text, 10),
        maxSideEffects: _int(_maxSideEffects.text, 10),
        maxItems: _int(_maxItems.text, 1),
        maxDurationMs: _int(_maxDuration.text, 120000),
        pacingMs: _int(_pacing.text, 0),
        uniqueTarget: _uniqueTarget,
        uniqueContent: _uniqueContent,
        confirmWrites: _confirmWrites,
        confirmDestructive: _confirmDestructive,
        hostScope: _hostScope,
        allowedHosts: _allowedHosts.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      ),
      builtin: existing?.builtin ?? false,
      sortOrder: existing?.sortOrder ?? 0,
      updatedAt: now,
    );
  }

  int _int(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  Map<String, String> _parseOutput() {
    try {
      final decoded = jsonDecode(
        _output.text.trim().isEmpty ? '{}' : _output.text,
      );
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return {};
  }

  void _applyDraft(SkillDraft draft) {
    setState(() {
      _name.text = draft.name;
      _description.text = draft.description;
      _kind = draft.kind;
      _inputs = List<SkillInput>.from(draft.inputs);
      _steps = List<SkillStep>.from(draft.steps);
      _instructions.text = draft.instructions;
      final policy = draft.policy;
      _maxSteps.text = '${policy.maxSteps}';
      _maxLlmCalls.text = '${policy.maxLlmCalls}';
      _maxSideEffects.text = '${policy.maxSideEffects}';
      _maxItems.text = '${policy.maxItems}';
      _maxDuration.text = '${policy.maxDurationMs}';
      _pacing.text = '${policy.pacingMs}';
      _allowedHosts.text = policy.allowedHosts.join(', ');
      _hostScope = policy.hostScope;
      _uniqueTarget = policy.uniqueTarget;
      _uniqueContent = policy.uniqueContent;
      _confirmWrites = policy.confirmWrites;
      _confirmDestructive = policy.confirmDestructive;
    });
  }

  Future<void> _aiModify() async {
    final config = widget.config;
    if (config == null || !config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置有效的大模型 API Key')),
      );
      return;
    }
    final controller = TextEditingController();
    final request = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 修改技能'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：把默认条数改成 10，并给点击步骤增加重试',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('生成修改'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (request == null || request.isEmpty || !mounted) return;

    setState(() => _aiBusy = true);
    final result = await SkillAuthoringService().generate(
      description: request,
      config: config,
      webView: widget.webView,
      referencePage: false,
      allowWrites: _buildSkill().hasWriteSteps,
      restrictToCurrentHost: _buildSkill().hasWriteSteps,
      baseSkill: _buildSkill(),
    );
    if (!mounted) return;
    setState(() => _aiBusy = false);
    if (result.draft != null) {
      _applyDraft(result.draft!);
    }
    if (result.error != null || result.validation.hasErrors) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改结果需要检查'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.error != null)
                  Text(
                    result.error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                    ),
                  ),
                ...result.validation.errors.take(6).map(
                      (issue) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '• ${issue.message}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _save() async {
    final skill = _buildSkill();
    final result = SkillValidator().validate(skill);
    if (result.hasErrors) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('技能还不能保存'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.errors
                  .take(8)
                  .map((issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• ${issue.message}',
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.redAccent,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('返回修改'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final service = await SkillService.getInstance();
      await service.saveSkill(skill);
      if (!mounted) return;
      Navigator.of(context).pop(skill);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addInput([SkillInput? current, int? index]) async {
    final result = await showDialog<SkillInput>(
      context: context,
      builder: (_) => SkillInputDialog(input: current),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _inputs.add(result);
      } else {
        _inputs[index] = result;
      }
    });
  }

  Future<void> _deleteInput(int index) async {
    setState(() => _inputs.removeAt(index));
  }

  Future<void> _addStep([SkillStep? current, int? index]) async {
    final result = await showDialog<SkillStep>(
      context: context,
      builder: (_) => SkillStepDialog(
        step: current,
        suggestedId: 'step_${_steps.length + 1}',
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps.add(result);
      } else {
        _steps[index] = result;
      }
    });
  }

  void _deleteStep(int index) {
    setState(() => _steps.removeAt(index));
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final item = _steps.removeAt(index);
      _steps.insert(target, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? '新建技能' : '编辑技能'),
        actions: [
          if (widget.config != null)
            IconButton(
              tooltip: 'AI 修改',
              onPressed: _saving || _aiBusy ? null : _aiModify,
              icon: _aiBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _sectionTitle('基本信息', muted),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '说明',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<SkillKind>(
            key: ValueKey(_kind),
            initialValue: _kind,
            decoration: const InputDecoration(
              labelText: '类型',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: SkillKind.values
                .map((kind) => DropdownMenuItem(
                      value: kind,
                      child: Text(
                        kind == SkillKind.flow
                            ? '流程型（固定步骤，省钱稳定）'
                            : '指令型（交给 Agent 自主执行）',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _kind = value);
            },
          ),
          if (_kind == SkillKind.instruction) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _instructions,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: '指令 / 提示词',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('输入参数', muted),
          ..._inputs.asMap().entries.map((entry) {
            final input = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  '${input.label}  {{${input.key}}}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  '${input.type.label}${input.required ? ' · 必填' : ''}'
                  '${input.defaultValue.isEmpty ? '' : ' · 默认 ${input.defaultValue}'}',
                  style: const TextStyle(fontSize: 10.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _addInput(input, entry.key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _deleteInput(entry.key),
                    ),
                  ],
                ),
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addInput(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加输入参数'),
            ),
          ),
          if (_kind == SkillKind.flow) ...[
            const SizedBox(height: 8),
            _sectionTitle('执行步骤', muted),
            ..._steps.asMap().entries.map((entry) {
              final step = entry.value;
              final tool = ToolCatalog.find(step.tool);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      '${entry.key + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    step.name,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    '${tool?.name ?? step.tool} · ${step.id}'
                    '${step.onError.action == StepFailureAction.stop ? '' : ' · ${step.onError.action.label}'}',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 16),
                        onPressed: entry.key == 0
                            ? null
                            : () => _moveStep(entry.key, -1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 16),
                        onPressed: entry.key == _steps.length - 1
                            ? null
                            : () => _moveStep(entry.key, 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _addStep(step, entry.key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _deleteStep(entry.key),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addStep(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加步骤'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _sectionTitle('执行策略', muted),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _numberField(_maxSteps, '最大步数'),
              _numberField(_maxLlmCalls, 'AI 调用上限'),
              _numberField(_maxSideEffects, '写入上限'),
              _numberField(_maxItems, '批量上限'),
              _numberField(_maxDuration, '最长毫秒'),
              _numberField(_pacing, '步骤间隔毫秒'),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('重复目标拦截', style: TextStyle(fontSize: 12.5)),
            value: _uniqueTarget,
            onChanged: (value) => setState(() => _uniqueTarget = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('重复内容拦截', style: TextStyle(fontSize: 12.5)),
            value: _uniqueContent,
            onChanged: (value) => setState(() => _uniqueContent = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('写入步骤每次确认', style: TextStyle(fontSize: 12.5)),
            value: _confirmWrites,
            onChanged: (value) => setState(() => _confirmWrites = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('高危操作始终确认', style: TextStyle(fontSize: 12.5)),
            value: _confirmDestructive,
            onChanged: (value) => setState(() => _confirmDestructive = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<SkillHostScope>(
            key: ValueKey(_hostScope),
            initialValue: _hostScope,
            decoration: const InputDecoration(
              labelText: '站点范围',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: SkillHostScope.values
                .map((scope) => DropdownMenuItem(
                      value: scope,
                      child: Text(scope.label,
                          style: const TextStyle(fontSize: 12.5)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _hostScope = value);
            },
          ),
          if (_hostScope == SkillHostScope.list) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _allowedHosts,
              decoration: const InputDecoration(
                labelText: '允许的域名（逗号分隔）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('输出映射（高级，可选）', muted),
          TextField(
            controller: _output,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            decoration: const InputDecoration(
              hintText: '{\n  "summary": "{{steps.summary.data.text}}"\n}',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('权限预览', muted),
          Text(
            _permissionPreview(),
            style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
          ),
        ],
      ),
    );
  }

  String _permissionPreview() {
    if (_kind == SkillKind.instruction) {
      return '此技能会交给 Agent 自主执行，可能打开网页、点击、输入或调用 AI。';
    }
    if (_steps.isEmpty) return '还没有步骤。';
    final lines = <String>[];
    for (final step in _steps) {
      final tool = ToolCatalog.find(step.tool);
      if (tool == null) {
        lines.add('未知工具：${step.tool}');
        continue;
      }
      lines.add('${step.name} · ${tool.name} · ${_riskLabel(tool.risk)}');
    }
    return lines.join('\n');
  }

  String _riskLabel(ToolRisk risk) {
    switch (risk) {
      case ToolRisk.read:
        return '只读';
      case ToolRisk.navigate:
        return '跳转';
      case ToolRisk.write:
        return '写入';
      case ToolRisk.destructive:
        return '高危';
    }
  }

  Widget _sectionTitle(String text, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: muted,
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class SkillInputDialog extends StatefulWidget {
  final SkillInput? input;

  const SkillInputDialog({super.key, this.input});

  @override
  State<SkillInputDialog> createState() => _SkillInputDialogState();
}

class _SkillInputDialogState extends State<SkillInputDialog> {
  late final TextEditingController _key;
  late final TextEditingController _label;
  late final TextEditingController _defaultValue;
  late final TextEditingController _options;
  late final TextEditingController _hint;
  late SkillInputType _type;
  late bool _required;
  String? _error;

  @override
  void initState() {
    super.initState();
    final input = widget.input;
    _key = TextEditingController(text: input?.key ?? '');
    _label = TextEditingController(text: input?.label ?? '');
    _defaultValue = TextEditingController(text: input?.defaultValue ?? '');
    _options = TextEditingController(text: input?.options.join(', ') ?? '');
    _hint = TextEditingController(text: input?.hint ?? '');
    _type = input?.type ?? SkillInputType.text;
    _required = input?.required ?? false;
  }

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _defaultValue.dispose();
    _options.dispose();
    _hint.dispose();
    super.dispose();
  }

  void _apply() {
    if (_key.text.trim().isEmpty || _label.text.trim().isEmpty) {
      setState(() => _error = 'key 和名称不能为空');
      return;
    }
    final options = _options.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    Navigator.of(context).pop(SkillInput(
      key: _key.text.trim(),
      label: _label.text.trim(),
      type: _type,
      defaultValue:
          _type == SkillInputType.secret ? '' : _defaultValue.text.trim(),
      options: options,
      required: _required,
      hint: _hint.text.trim().isEmpty ? null : _hint.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.input == null ? '添加输入参数' : '编辑输入参数'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'key（英文，如 count）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: '显示名称',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SkillInputType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                isDense: true,
              ),
              items: SkillInputType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 10),
            if (_type != SkillInputType.secret)
              TextField(
                controller: _defaultValue,
                decoration: const InputDecoration(
                  labelText: '默认值',
                  isDense: true,
                ),
              ),
            if (_type == SkillInputType.select) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                  labelText: '选项（逗号分隔）',
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _hint,
              decoration: const InputDecoration(
                labelText: '提示（可选）',
                isDense: true,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('必填', style: TextStyle(fontSize: 12.5)),
              value: _required,
              onChanged: (value) => setState(() => _required = value),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _apply,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class SkillStepDialog extends StatefulWidget {
  final SkillStep? step;
  final String suggestedId;

  const SkillStepDialog({
    super.key,
    this.step,
    required this.suggestedId,
  });

  @override
  State<SkillStepDialog> createState() => _SkillStepDialogState();
}

class _SkillStepDialogState extends State<SkillStepDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _saveAs;
  late final TextEditingController _params;
  late final TextEditingController _expectValue;
  late final TextEditingController _fallbackGoal;
  late final TextEditingController _fallbackTools;
  late String _tool;
  late StepFailureAction _failure;
  late ExpectationType? _expectType;
  String? _error;

  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _id = TextEditingController(text: step?.id ?? widget.suggestedId);
    _name = TextEditingController(text: step?.name ?? '');
    _saveAs = TextEditingController(text: step?.saveAs ?? '');
    _params = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(step?.params ?? {}),
    );
    _expectValue = TextEditingController(text: step?.expect?.value ?? '');
    _fallbackGoal = TextEditingController(
      text: step?.onError.fallbackGoal ?? '',
    );
    _fallbackTools = TextEditingController(
      text: step?.onError.fallbackTools.join(', ') ?? '',
    );
    _tool = step?.tool ?? ToolCatalog.available.first.id;
    _failure = step?.onError.action ?? StepFailureAction.stop;
    _expectType = step?.expect?.type;
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _saveAs.dispose();
    _params.dispose();
    _expectValue.dispose();
    _fallbackGoal.dispose();
    _fallbackTools.dispose();
    super.dispose();
  }

  Future<void> _pasteLocator() async {
    final tool = ToolCatalog.find(_tool);
    if (tool == null) return;
    ToolParam? locatorParam;
    for (final param in tool.params) {
      if (param.type == ToolParamType.locator) {
        locatorParam = param;
        break;
      }
    }
    if (locatorParam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个工具不需要定位器')),
      );
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板里没有定位器 JSON')),
      );
      return;
    }
    Map<String, dynamic>? locator;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        locator = Map<String, dynamic>.from(decoded);
        final nested = locator['locator'];
        if (nested is Map) locator = Map<String, dynamic>.from(nested);
      }
    } catch (_) {}
    if (locator == null || locator['candidates'] is! List) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板内容不是有效的定位器')),
      );
      return;
    }
    Map<String, dynamic> params;
    try {
      final decoded = jsonDecode(
        _params.text.trim().isEmpty ? '{}' : _params.text,
      );
      params = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      params = <String, dynamic>{};
    }
    params[locatorParam.key] = locator;
    setState(() {
      _params.text = const JsonEncoder.withIndent('  ').convert(params);
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已填入 ${locatorParam.key} 定位器')),
    );
  }

  void _apply() {
    if (_id.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = '步骤 id 和名称不能为空');
      return;
    }
    Map<String, dynamic> params;
    try {
      final decoded =
          jsonDecode(_params.text.trim().isEmpty ? '{}' : _params.text);
      if (decoded is! Map) {
        setState(() => _error = '参数必须是 JSON 对象');
        return;
      }
      params = Map<String, dynamic>.from(decoded);
    } catch (e) {
      setState(() => _error = '参数 JSON 解析失败：$e');
      return;
    }

    StepExpectation? expectation;
    if (_expectType != null) {
      expectation = StepExpectation(
        type: _expectType!,
        value:
            _expectValue.text.trim().isEmpty ? null : _expectValue.text.trim(),
      );
    }

    Navigator.of(context).pop(SkillStep(
      id: _id.text.trim(),
      name: _name.text.trim(),
      tool: _tool,
      params: params,
      saveAs: _saveAs.text.trim().isEmpty ? null : _saveAs.text.trim(),
      onError: StepFailurePolicy(
        action: _failure,
        fallbackGoal: _fallbackGoal.text.trim(),
        fallbackTools: _fallbackTools.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      ),
      expect: expectation,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tool = ToolCatalog.find(_tool);
    return AlertDialog(
      title: Text(widget.step == null ? '添加步骤' : '编辑步骤'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _id,
              decoration: const InputDecoration(
                labelText: 'id（英文，如 read）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '步骤名称',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _tool,
              decoration: const InputDecoration(
                labelText: '工具',
                isDense: true,
              ),
              items: ToolCatalog.available
                  .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.name} · ${item.id}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _tool = value);
              },
            ),
            if (tool != null) ...[
              const SizedBox(height: 4),
              Text(
                '参数：${tool.params.map((p) => '${p.key}${p.required ? '*' : ''}').join(', ')}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
              ),
              if (tool.params.any((p) => p.type == ToolParamType.locator))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pasteLocator,
                    icon: const Icon(Icons.content_paste_rounded, size: 15),
                    label: const Text(
                      '粘贴定位器',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              if (tool.params.any((p) => p.type == ToolParamType.locator))
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    '先在浏览器菜单点「拾取定位器」，再回来粘贴',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _saveAs,
              decoration: const InputDecoration(
                labelText: '结果变量名（可选，如 comments）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _params,
              minLines: 6,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              decoration: const InputDecoration(
                labelText: '参数 JSON',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<StepFailureAction>(
              initialValue: _failure,
              decoration: const InputDecoration(
                labelText: '失败策略',
                isDense: true,
              ),
              items: StepFailureAction.values
                  .map((action) => DropdownMenuItem(
                        value: action,
                        child: Text(action.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _failure = value);
              },
            ),
            if (_failure == StepFailureAction.fallbackAgent) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _fallbackGoal,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '交给 Agent 的子目标',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fallbackTools,
                decoration: const InputDecoration(
                  labelText: '允许的工具（逗号分隔，如 page.click, page.type）',
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _expectType?.name ?? 'none',
              decoration: const InputDecoration(
                labelText: '后置条件',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: 'none', child: Text('不校验')),
                ...ExpectationType.values.map((type) => DropdownMenuItem(
                      value: type.name,
                      child: Text(type.name),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _expectType = value == null || value == 'none'
                      ? null
                      : ExpectationType.values.firstWhere(
                          (item) => item.name == value,
                        );
                });
              },
            ),
            if (_expectType != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _expectValue,
                decoration: const InputDecoration(
                  labelText: '期望值（URL 片段 / 文本 / 定位器 JSON）',
                  isDense: true,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _apply,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
