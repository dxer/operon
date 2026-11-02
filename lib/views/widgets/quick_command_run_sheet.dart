import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/quick_command.dart';

/// The rendered prompt plus the effective policy for this run.
class QuickCommandRunResult {
  final String prompt;
  final QuickCommandPolicy policy;

  const QuickCommandRunResult({required this.prompt, required this.policy});
}

/// Collects template variables and returns the final prompt.
///
/// The rendered text goes back into the main AI input, so the user can still
/// edit it before sending. Nothing is executed from this sheet.
class QuickCommandRunSheet extends StatefulWidget {
  final QuickCommand command;

  const QuickCommandRunSheet({super.key, required this.command});

  @override
  State<QuickCommandRunSheet> createState() => _QuickCommandRunSheetState();
}

class _QuickCommandRunSheetState extends State<QuickCommandRunSheet> {
  late final Map<String, String> _values;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final input in widget.command.inputs) input.key: input.defaultValue,
    };
    for (final input in widget.command.inputs) {
      if (input.type == QuickCommandInputType.select &&
          input.options.isNotEmpty &&
          !input.options.contains(_values[input.key])) {
        _values[input.key] = input.options.first;
      }
    }
  }

  String get _rendered {
    final values = Map<String, String>.from(_values);
    final policy = _effectivePolicy();
    final rawCount = values['count'];
    if (rawCount != null && policy.maxItems > 0) {
      final count = int.tryParse(rawCount.trim());
      if (count != null && count > policy.maxItems) {
        values['count'] = policy.maxItems.toString();
      }
    }
    return widget.command.render(values);
  }

  String _policySummary(QuickCommandPolicy policy) {
    final parts = <String>[policy.mode.label];
    if (policy.isBatch && policy.maxItems > 0) {
      parts.add(
        policy.mode == QuickCommandMode.paginate
            ? '最多 ${policy.maxItems} 页'
            : '最多 ${policy.maxItems} 项',
      );
    }
    if (policy.uniqueContent) parts.add('重复内容拦截');
    if (policy.uniqueTarget) parts.add('重复目标拦截');
    if (policy.confirmBeforeSideEffect) parts.add('敏感操作需确认');
    if (policy.pacingMs > 0) parts.add('间隔 ${policy.pacingMs ~/ 1000} 秒');
    if (policy.maxSteps != null) parts.add('${policy.maxSteps} 步上限');
    return parts.join(' · ');
  }

  void _setValue(String key, String value) {
    setState(() => _values[key] = value);
  }

  void _apply() {
    for (final input in widget.command.inputs) {
      if (!input.required) continue;
      final value = (_values[input.key] ?? '').trim();
      final effective = value.isEmpty ? input.defaultValue.trim() : value;
      if (effective.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请填写：${input.label}'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (input.type == QuickCommandInputType.number) {
        final parsed = int.tryParse(effective);
        if (parsed == null || parsed <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${input.label} 需要填写大于 0 的数字'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }
    }
    Navigator.of(context).pop(
      QuickCommandRunResult(prompt: _rendered, policy: _effectivePolicy()),
    );
  }

  /// A `count` parameter is a generic batch limit. Honor it as the hard cap
  /// while keeping the template's static maxItems as the safety ceiling.
  QuickCommandPolicy _effectivePolicy() {
    final policy = widget.command.policy;
    final raw = _values['count'];
    if (raw == null) return policy;
    final count = int.tryParse(raw.trim());
    if (count == null || count <= 0) return policy;
    final ceiling = policy.maxItems > 0 ? policy.maxItems : count;
    return policy.copyWith(maxItems: count > ceiling ? ceiling : count);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final surface = isDark ? const Color(0xFF16181C) : const Color(0xFFF1F4F6);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
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
              const Icon(Icons.bolt_rounded, size: 18, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.command.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (widget.command.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.command.description,
              style: TextStyle(fontSize: 11.5, color: muted, height: 1.35),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _policySummary(_effectivePolicy()),
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...widget.command.inputs.map(
                    (input) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildInput(input, isDark, surface, onSurface),
                    ),
                  ),
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
                      _rendered,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: onSurface,
                      ),
                    ),
                  ),
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
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('填入输入框'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(
    QuickCommandInput input,
    bool isDark,
    Color surface,
    Color onSurface,
  ) {
    final value = _values[input.key] ?? input.defaultValue;
    final decoration = InputDecoration(
      labelText: input.label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      isDense: true,
    );

    switch (input.type) {
      case QuickCommandInputType.multiline:
        return TextFormField(
          key: ValueKey('${widget.command.id}_${input.key}'),
          initialValue: value,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
      case QuickCommandInputType.number:
        return TextFormField(
          key: ValueKey('${widget.command.id}_${input.key}'),
          initialValue: value,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
      case QuickCommandInputType.select:
        final options = input.options.isEmpty
            ? <String>[input.defaultValue]
            : input.options;
        final selected = options.contains(value) ? value : options.first;
        return InputDecorator(
          decoration: decoration,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey('${widget.command.id}_${input.key}'),
              value: selected,
              isExpanded: true,
              isDense: true,
              style: TextStyle(fontSize: 12.5, color: onSurface),
              items: options
                  .map((option) => DropdownMenuItem(
                        value: option,
                        child: Text(option,
                            style: const TextStyle(fontSize: 12.5)),
                      ))
                  .toList(),
              onChanged: (next) {
                if (next != null) _setValue(input.key, next);
              },
            ),
          ),
        );
      case QuickCommandInputType.toggle:
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
      case QuickCommandInputType.text:
        return TextFormField(
          key: ValueKey('${widget.command.id}_${input.key}'),
          initialValue: value,
          style: const TextStyle(fontSize: 12.5),
          decoration: decoration,
          onChanged: (text) => _setValue(input.key, text),
        );
    }
  }
}
