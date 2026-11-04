import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../models/skill.dart';
import '../../services/skill_authoring_service.dart';
import '../../services/skill_creator_service.dart';
import '../../services/skill_precheck_service.dart';
import '../../services/skill_service.dart';
import '../../services/webview_controller_wrapper.dart';
import '../../utils/cancellation.dart';

/// Records a flow skill by driving the real page once.
///
/// This is the advanced path: it is the only way to capture real element
/// anchors. The terminal submit is resolved but never dispatched.
class SkillRecordingSheet extends StatefulWidget {
  final LlmConfig config;
  final WebViewControllerWrapper? webView;
  final bool Function()? canStartRun;

  const SkillRecordingSheet({
    super.key,
    required this.config,
    this.webView,
    this.canStartRun,
  });

  @override
  State<SkillRecordingSheet> createState() => _SkillRecordingSheetState();
}

class _SkillRecordingSheetState extends State<SkillRecordingSheet> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _sampleContent = TextEditingController();
  CancellationToken _token = CancellationToken();

  bool _generating = false;
  bool _checking = false;
  String _stage = '';
  String? _error;
  SkillAuthoringResult? _result;

  @override
  void dispose() {
    _description.dispose();
    _sampleContent.dispose();
    _token.cancel();
    super.dispose();
  }

  Future<void> _record() async {
    final text = _description.text.trim();
    if (text.isEmpty) return;
    final webView = widget.webView;
    if (webView == null) {
      setState(() => _error = '请先在浏览器中打开目标网站');
      return;
    }
    if (!widget.config.isValid) {
      setState(() => _error = '请先在设置中配置有效的大模型 API Key');
      return;
    }
    if (widget.canStartRun?.call() == false) {
      setState(() => _error = '请先停止正在运行的任务');
      return;
    }

    _token = CancellationToken();
    setState(() {
      _generating = true;
      _error = null;
      _result = null;
      _stage = '正在演示并录制页面…';
    });

    final result = await const SkillCreatorService().create(
      description: text,
      config: widget.config,
      webView: webView,
      sampleContent: _sampleContent.text.trim(),
      token: _token,
      onProgress: (stage) {
        if (mounted) setState(() => _stage = stage);
      },
    );
    if (!mounted) return;
    setState(() {
      _generating = false;
      _stage = '';
      _result = result;
      _error = result.ok ? null : _errorText(result);
    });
  }

  String _errorText(SkillAuthoringResult result) {
    if (result.error != null && result.error!.trim().isNotEmpty) {
      return result.error!;
    }
    if (result.validation.hasErrors) {
      return result.validation.errors.first.message;
    }
    return '没有录到可执行的步骤。';
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
        title: const Text('定位器检查'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.isEmpty
                ? const [
                    Text('这个技能没有需要检查的定位器。', style: TextStyle(fontSize: 12)),
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

  Future<void> _save() async {
    final draft = _result?.draft;
    if (draft == null) return;
    final service = await SkillService.getInstance();
    final skill = draft.toSkill(
      id: 'skill_${DateTime.now().millisecondsSinceEpoch}',
      origin: SkillOrigin.recorded,
    );
    await service.saveSkill(skill);
    if (!mounted) return;
    Navigator.of(context).pop(skill);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final surface = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.72 : 0.6);
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final draft = _result?.draft;

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
              const Icon(Icons.fiber_manual_record_outlined,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '录制操作流程',
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
          const SizedBox(height: 4),
          Text(
            '适合每次都要点同样按钮的固定流程。AI 会在当前页面真实演示一遍，'
            '记录元素定位器；最后的发布按钮只记录，不会点击。',
            style: TextStyle(fontSize: 11, color: muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_generating,
                    decoration: InputDecoration(
                      labelText: '要录制的流程',
                      hintText: '例如：回复当前推文',
                      hintStyle: TextStyle(fontSize: 12, color: muted),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sampleContent,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_generating,
                    decoration: InputDecoration(
                      labelText: '演示时输入的内容（可选）',
                      hintText: '例如：很有启发，感谢分享。',
                      hintStyle: TextStyle(fontSize: 11, color: muted),
                      helperText: '运行技能时会替换为 {{inputs.content}}',
                      helperStyle: TextStyle(fontSize: 10, color: muted),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 13, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '录制会真实操作当前页面。结束后页面可能停在编辑框，'
                          '请手动关闭，不要点发布。',
                          style: TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ),
                    ],
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
                  if (draft != null) ...[
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
                            '${draft.steps.length} 个步骤',
                            style: TextStyle(fontSize: 10.5, color: muted),
                          ),
                          const SizedBox(height: 4),
                          ...draft.steps.asMap().entries.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '${entry.key + 1}. ${entry.value.name}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: muted,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                          if (draft.notes.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              draft.notes,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: muted,
                                height: 1.4,
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
                  onPressed: _generating
                      ? null
                      : (draft != null && _result?.ok == true
                          ? _save
                          : _record),
                  icon: Icon(
                    draft != null && _result?.ok == true
                        ? Icons.check_rounded
                        : Icons.fiber_manual_record,
                    size: 16,
                  ),
                  label: Text(
                    draft != null && _result?.ok == true
                        ? '保存技能'
                        : (_result == null ? '开始录制' : '重新录制'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (draft != null && _result?.ok == true && widget.webView != null)
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
        ],
      ),
    );
  }
}
