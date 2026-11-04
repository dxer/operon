import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/tool_catalog.dart';
import '../../models/skill.dart';
import '../../models/tool_descriptor.dart';
import '../../services/skill_precheck_service.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../utils/skill_template.dart';

class SkillRunRequest {
  final Skill skill;
  final Map<String, String> values;
  final bool execute;
  final bool dryRun;

  const SkillRunRequest({
    required this.skill,
    required this.values,
    required this.execute,
    this.dryRun = false,
  });

  Map<String, dynamic> get templateContext => {
        'inputs': values,
        'env': <String, dynamic>{},
        'run': <String, dynamic>{},
      };
}

/// Collects skill inputs, shows permissions/plan, and returns a run request.
class SkillRunSheet extends StatefulWidget {
  final Skill skill;
  final WebViewControllerWrapper? webView;

  const SkillRunSheet({super.key, required this.skill, this.webView});

  @override
  State<SkillRunSheet> createState() => _SkillRunSheetState();
}

class _SkillRunSheetState extends State<SkillRunSheet> {
  late final Map<String, String> _values;
  bool _dryRun = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final input in widget.skill.inputs) input.key: input.defaultValue,
    };
    for (final input in widget.skill.inputs) {
      if (input.type == SkillInputType.select &&
          input.options.isNotEmpty &&
          !input.options.contains(_values[input.key])) {
        _values[input.key] = input.options.first;
      }
    }
  }

  void _setValue(String key, String value) {
    setState(() => _values[key] = value);
  }

  String get _instructionPreview {
    try {
      return SkillTemplate.renderString(
        widget.skill.instructions,
        {'inputs': _values},
        strict: false,
      );
    } catch (_) {
      return widget.skill.instructions;
    }
  }

  List<SkillStep> get _enabledSteps =>
      widget.skill.steps.where((step) => step.enabled).toList();

  String _riskLabel(ToolRisk risk) {
    switch (risk) {
      case ToolRisk.read:
        return '读取';
      case ToolRisk.navigate:
        return '跳转';
      case ToolRisk.write:
        return '写入';
      case ToolRisk.destructive:
        return '高危';
    }
  }

  Color _riskColor(ToolRisk risk) {
    switch (risk) {
      case ToolRisk.read:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case ToolRisk.navigate:
        return AppTheme.primary;
      case ToolRisk.write:
        return Theme.of(context).brightness == Brightness.dark
            ? AppTheme.warning
            : const Color(0xFF8A5A12);
      case ToolRisk.destructive:
        return AppTheme.danger;
    }
  }

  String get _permissionSummary {
    if (widget.skill.isInstruction) {
      return '交给 Agent 自主执行 · ${widget.skill.policy.maxSteps} 步上限';
    }
    final tools = <String>{};
    var writes = 0;
    var llm = 0;
    for (final step in _enabledSteps) {
      final tool = ToolCatalog.find(step.tool);
      if (tool == null) continue;
      tools.add(tool.name);
      if (tool.isWrite) writes++;
      if (tool.usesLlm) llm++;
    }
    final parts = <String>[
      '${_enabledSteps.length} 个步骤',
      if (writes > 0) '$writes 个写入',
      if (llm > 0) '$llm 次 AI',
      ...tools.take(4),
    ];
    return parts.join(' · ');
  }

  bool _validateInputs() {
    for (final input in widget.skill.inputs) {
      final raw = (_values[input.key] ?? '').trim();
      final value = raw.isEmpty ? input.defaultValue.trim() : raw;
      if (input.required && value.isEmpty) {
        _toast('请填写：${input.label}');
        return false;
      }
      if (input.type == SkillInputType.number && value.isNotEmpty) {
        final parsed = int.tryParse(value);
        if (parsed == null || parsed <= 0) {
          _toast('${input.label} 需要填写大于 0 的数字');
          return false;
        }
      }
    }
    return true;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _checkLocators() async {
    final webView = widget.webView;
    if (webView == null) {
      _toast('当前没有可检查的页面');
      return;
    }
    setState(() => _checking = true);
    final draft = SkillDraft(
      name: widget.skill.name,
      description: widget.skill.description,
      kind: widget.skill.kind,
      inputs: widget.skill.inputs,
      instructions: widget.skill.instructions,
      steps: widget.skill.steps,
      policy: widget.skill.policy,
    );
    final items = await SkillPrecheckService().check(draft, webView);
    if (!mounted) return;
    setState(() => _checking = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('定位器检查'),
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

  void _apply() {
    if (!_validateInputs()) return;
    Navigator.of(context).pop(
      SkillRunRequest(
        skill: widget.skill,
        values: Map<String, String>.from(_values),
        execute: widget.skill.isFlow,
        dryRun: widget.skill.isFlow && _dryRun,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
              Icon(
                widget.skill.isFlow
                    ? Icons.account_tree_outlined
                    : Icons.auto_awesome,
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.skill.name,
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
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.skill.kind.label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (widget.skill.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.skill.description,
              style: TextStyle(fontSize: 11.5, color: muted, height: 1.35),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _permissionSummary,
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
          if (widget.skill.isInstruction) ...[
            const SizedBox(height: 2),
            Text(
              '元素由 Agent 在运行时定位；写入前会再次确认。',
              style: TextStyle(fontSize: 10.5, color: muted),
            ),
          ],
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...widget.skill.inputs.map(
                    (input) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildInput(input, isDark, surface, onSurface),
                    ),
                  ),
                  if (widget.skill.isFlow) ...[
                    if (widget.webView != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _checking ? null : _checkLocators,
                          icon: _checking
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.center_focus_strong,
                                  size: 15,
                                ),
                          label: const Text(
                            '检查定位器',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '只读试运行',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      subtitle: const Text(
                        '执行到第一个写入步骤前停止，用于检查定位器',
                        style: TextStyle(fontSize: 10),
                      ),
                      value: _dryRun,
                      onChanged: (value) => setState(() => _dryRun = value),
                    ),
                    Text(
                      '执行计划',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._enabledSteps.asMap().entries.map((entry) {
                      final step = entry.value;
                      final tool = ToolCatalog.find(step.tool);
                      final risk = tool?.risk ?? ToolRisk.read;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: hairline),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${entry.key + 1}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: onSurface,
                                    ),
                                  ),
                                  Text(
                                    tool?.name ?? step.tool,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _riskColor(risk).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _riskLabel(risk),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: _riskColor(risk),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    Text(
                      '最终提示词预览',
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
                      child: Text(
                        _instructionPreview,
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
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    side: BorderSide(color: hairline),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    widget.skill.isFlow ? '开始执行' : '运行',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(
    SkillInput input,
    bool isDark,
    Color surface,
    Color onSurface,
  ) {
    final value = _values[input.key] ?? input.defaultValue;
    final decoration = InputDecoration(
      labelText: input.label,
      hintText: input.hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      isDense: true,
    );

    switch (input.type) {
      case SkillInputType.multiline:
        return TextFormField(
          key: ValueKey('${widget.skill.id}_${input.key}'),
          initialValue: value,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
      case SkillInputType.number:
        return TextFormField(
          key: ValueKey('${widget.skill.id}_${input.key}'),
          initialValue: value,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
      case SkillInputType.secret:
        return TextFormField(
          key: ValueKey('${widget.skill.id}_${input.key}'),
          initialValue: '',
          obscureText: true,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
      case SkillInputType.select:
        final options = input.options.isEmpty
            ? <String>[input.defaultValue]
            : input.options;
        final selected = options.contains(value) ? value : options.first;
        return InputDecorator(
          decoration: decoration,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey('${widget.skill.id}_${input.key}'),
              value: selected,
              isExpanded: true,
              isDense: true,
              style: TextStyle(fontSize: 12.5, color: onSurface),
              items: options
                  .map((option) => DropdownMenuItem(
                        value: option,
                        child: Text(
                          option,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ))
                  .toList(),
              onChanged: (next) {
                if (next != null) _setValue(input.key, next);
              },
            ),
          ),
        );
      case SkillInputType.toggle:
        final enabled = value == '是' || value == 'true';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              input.label,
              style: TextStyle(fontSize: 12.5, color: onSurface),
            ),
            value: enabled,
            activeThumbColor: AppTheme.accent,
            onChanged: (next) => _setValue(input.key, next ? '是' : '否'),
          ),
        );
      case SkillInputType.text:
        return TextFormField(
          key: ValueKey('${widget.skill.id}_${input.key}'),
          initialValue: value,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
    }
  }
}
