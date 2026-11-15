import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';
import 'markdown_answer.dart';

class SummaryBottomSheet extends StatefulWidget {
  final String title;
  final String url;
  final String content;
  final LlmConfig config;

  const SummaryBottomSheet({
    super.key,
    required this.title,
    required this.url,
    required this.content,
    required this.config,
  });

  @override
  State<SummaryBottomSheet> createState() => _SummaryBottomSheetState();
}

class _SummaryBottomSheetState extends State<SummaryBottomSheet> {
  final LlmService _llmService = LlmService();
  bool _isLoading = true;
  String _summaryText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateSummary();
  }

  @override
  void dispose() {
    _llmService.dispose();
    super.dispose();
  }

  Future<void> _generateSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      DateTime lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      final buffer = StringBuffer();
      final summary = await _llmService.summarizeWebPage(
        config: widget.config,
        title: widget.title,
        url: widget.url,
        content: widget.content,
        onDelta: (delta) {
          buffer.write(delta);
          final now = DateTime.now();
          if (mounted && now.difference(lastUpdate).inMilliseconds >= 80) {
            lastUpdate = now;
            setState(() => _summaryText = buffer.toString());
          }
        },
      );

      if (mounted) {
        setState(() {
          _summaryText = summary;
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

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _summaryText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制速读总结到剪贴板！'),
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
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 18,
            offset: Offset(0, -6),
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
                color: AppInk.tertiary(isDark).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOf(isDark).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child:
                    Icon(Icons.bolt, color: AppTheme.primaryOf(isDark), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.isNotEmpty ? widget.title : '网页速读摘要',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        color: AppInk.primary(isDark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro.copyWith(
                        color: AppInk.tertiary(isDark),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isLoading && _summaryText.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制速读摘要',
                  onPressed: _copyToClipboard,
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const Divider(height: 16),
          if (_isLoading && _summaryText.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          // Content body
          Expanded(
            child: _isLoading && _summaryText.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(strokeWidth: 3),
                        const SizedBox(height: 16),
                        const Text(
                          'AI 正在提取正文并提炼关键摘要...',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已提取约 ${widget.content.length} 字正文',
                          style: AppType.micro.copyWith(
                            color: AppInk.tertiary(isDark),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: AppTheme.dangerOf(isDark), size: 36),
                            const SizedBox(height: 12),
                            Text(
                              '提炼失败: $_error',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.dangerOf(isDark)),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _generateSummary,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: MarkdownAnswer(
                          _summaryText,
                          baseStyle: AppType.body.copyWith(
                            height: 1.6,
                            color: AppInk.primary(isDark),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
