import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';

class SummaryBottomSheet extends StatefulWidget {
  final String title;
  final String url;
  final String content;
  final LlmConfig config;

  const SummaryBottomSheet({
    Key? key,
    required this.title,
    required this.url,
    required this.content,
    required this.config,
  }) : super(key: key);

  @override
  State<SummaryBottomSheet> createState() => _SummaryBottomSheetState();
}

class _SummaryBottomSheetState extends State<SummaryBottomSheet> {
  bool _isLoading = true;
  String _summaryText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateSummary();
  }

  Future<void> _generateSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final llmService = LlmService();
      final summary = await llmService.summarizeWebPage(
        config: widget.config,
        title: widget.title,
        url: widget.url,
        content: widget.content,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt, color: AppTheme.primary, size: 20),
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
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
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

          // Content body
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(strokeWidth: 3),
                        const SizedBox(height: 16),
                        const Text(
                          '⚡ AI 正在提取正文并智能提炼精髓...',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已提取约 ${widget.content.length} 字正文',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
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
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                            const SizedBox(height: 12),
                            Text(
                              '提炼失败: $_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _generateSummary,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: SelectableText(
                          _summaryText,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF0F141C),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
