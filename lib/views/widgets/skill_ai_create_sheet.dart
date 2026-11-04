import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/skill_authoring_mode.dart';
import '../../models/llm_config.dart';
import '../../models/skill.dart';
import '../../services/skill_authoring_service.dart';
import '../../services/skill_service.dart';
import '../../services/skill_validator.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../utils/cancellation.dart';

/// One-field skill creation.
///
/// The user describes the task; the model writes the prompt and the skill is
/// saved immediately. There are deliberately no switches here: whether a skill
/// writes, which site it targets and what inputs it needs are all decided by
/// the model and by the runtime confirmation, not by the user up front.
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
  final SkillAuthoringService _service = SkillAuthoringService();
  CancellationToken _token = CancellationToken();

  bool _generating = false;
  String _stage = '';
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _token.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final text = _description.text.trim();
    if (text.isEmpty) return;
    if (!widget.config.isValid) {
      setState(() => _error = '请先在设置中配置有效的大模型 API Key');
      return;
    }

    _token = CancellationToken();
    setState(() {
      _generating = true;
      _error = null;
      _stage = '正在理解你的需求…';
    });

    final service = await SkillService.getInstance();
    if (!mounted) return;
    final existingNames = service.getSkills().map((skill) => skill.name).toList();
    final result = await _service.generate(
      description: text,
      config: widget.config,
      existingNames: existingNames,
      webView: widget.webView,
      referencePage: true,
      mode: SkillAuthoringMode.instruction,
      // Instruction skills describe writes in prose. The runtime confirmation
      // is the real gate, so creation does not need a write toggle.
      allowWrites: true,
      restrictToCurrentHost: false,
      token: _token,
      onProgress: (stage) {
        if (mounted) setState(() => _stage = stage);
      },
    );

    if (!mounted) return;
    final draft = result.draft;
    if (!result.ok || draft == null) {
      setState(() {
        _generating = false;
        _stage = '';
        _error = _errorText(result);
      });
      return;
    }

    final skill = draft.toSkill(
      id: 'skill_${DateTime.now().millisecondsSinceEpoch}',
      origin: SkillOrigin.user,
    );
    final validation = SkillValidator().validate(skill);
    if (validation.hasErrors) {
      setState(() {
        _generating = false;
        _stage = '';
        _error = validation.errors.first.message;
      });
      return;
    }

    await service.saveSkill(skill);
    if (!mounted) return;
    Navigator.of(context).pop(skill);
  }

  String _errorText(SkillAuthoringResult result) {
    if (result.error != null && result.error!.trim().isNotEmpty) {
      return result.error!;
    }
    if (result.validation.hasErrors) {
      return result.validation.errors.first.message;
    }
    return '没有生成可用的技能，请换个说法再试。';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
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
          const SizedBox(height: 12),
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
                    setState(() => _stage = '正在停止…');
                  },
                  child: const Text('取消'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    autofocus: true,
                    enabled: !_generating,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    decoration: InputDecoration(
                      hintText: '例如：回复当前推文，语气友好一点',
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
                      _preset('回复当前推文，语气友好'),
                      _preset('总结当前页面并给出三条建议'),
                      _preset('提取本页列表里的标题和链接'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI 会写好提示词并保存；点、输入、发布由 Agent 运行时完成，'
                    '写入前仍会确认。',
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: AppTheme.primary,
                      backgroundColor:
                          isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    ),
                    const SizedBox(height: 6),
                    Text(_stage, style: TextStyle(fontSize: 11, color: muted)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.danger,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _generating ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _generating ? null : _create,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_generating ? '正在创建…' : '创建技能'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
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
