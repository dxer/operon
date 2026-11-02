import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';

class SelectionActionDialog extends StatefulWidget {
  final String selectedText;
  final LlmConfig config;
  final Function(String text)? onFillInput;

  const SelectionActionDialog({
    Key? key,
    required this.selectedText,
    required this.config,
    this.onFillInput,
  }) : super(key: key);

  @override
  State<SelectionActionDialog> createState() => _SelectionActionDialogState();
}

class _SelectionActionDialogState extends State<SelectionActionDialog> {
  bool _isLoading = false;
  String? _resultText;
  String? _currentAction;
  String? _error;

  Future<void> _executeAction(String actionType, String label) async {
    setState(() {
      _isLoading = true;
      _currentAction = label;
      _error = null;
      _resultText = null;
    });

    try {
      final llmService = LlmService();
      final result = await llmService.querySelection(
        config: widget.config,
        selectedText: widget.selectedText,
        actionType: actionType,
      );

      if (mounted) {
        setState(() {
          _resultText = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _copyResult() {
    if (_resultText == null) return;
    Clipboard.setData(ClipboardData(text: _resultText!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 AI 回复到剪贴板！'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
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
          // Drag handle
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

          // Title & Selected text preview
          Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text('划词 AI 伴随', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          // Snippet Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16181C) : const Color(0xFFF0F3F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Text(
              widget.selectedText.length > 120
                  ? '${widget.selectedText.substring(0, 120)}...'
                  : widget.selectedText,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3 Quick Action Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.translate, size: 16, color: AppTheme.primary),
                label: const Text('翻译', style: TextStyle(fontSize: 12)),
                onPressed: _isLoading ? null : () => _executeAction('translate', '翻译'),
              ),
              ActionChip(
                avatar: const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                label: const Text('解释/释义', style: TextStyle(fontSize: 12)),
                onPressed: _isLoading ? null : () => _executeAction('explain', '通俗解释'),
              ),
              ActionChip(
                avatar: const Icon(Icons.chat_bubble_outline, size: 16, color: AppTheme.accent),
                label: const Text('生成评论回复', style: TextStyle(fontSize: 12)),
                onPressed: _isLoading ? null : () => _executeAction('reply', '生成回复'),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Result display
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text('AI 正在$_currentAction中...', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                '执行失败: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            )
          else if (_resultText != null)
            Flexible(
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF19202A) : const Color(0xFFF7F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$_currentAction结果:',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _copyResult,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 14, color: AppTheme.accent),
                                SizedBox(width: 4),
                                Text('复制', style: TextStyle(fontSize: 11, color: AppTheme.accent)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _resultText!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
