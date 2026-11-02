import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';

class BrowserControls extends StatefulWidget {
  final TextEditingController urlController;
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final double progress;
  final bool isDesktopMode;
  final bool isCleanMode;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final Function(String url) onSubmitUrl;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onOpenUserScripts;

  const BrowserControls({
    Key? key,
    required this.urlController,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.progress,
    required this.isDesktopMode,
    this.isCleanMode = false,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onSubmitUrl,
    required this.onOpenSettings,
    required this.onToggleDesktopMode,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onOpenUserScripts,
  }) : super(key: key);

  @override
  State<BrowserControls> createState() => _BrowserControlsState();
}

class _BrowserControlsState extends State<BrowserControls> {
  bool _showClear = false;

  @override
  void initState() {
    super.initState();
    _showClear = widget.urlController.text.isNotEmpty;
    widget.urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    widget.urlController.removeListener(_onUrlChanged);
    super.dispose();
  }

  void _onUrlChanged() {
    final hasText = widget.urlController.text.isNotEmpty;
    if (_showClear != hasText) {
      setState(() => _showClear = hasText);
    }
  }

  void _copyUrlToClipboard() {
    final text = widget.urlController.text;
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制网页链接到剪贴板！'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barBg = isDark ? AppTheme.darkBg : AppTheme.lightCard;
    final inputBg = isDark ? const Color(0xFF202327) : const Color(0xFFEFF3F4);
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final iconColor = isDark ? Colors.white70 : const Color(0xFF536471);

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: widget.canGoBack ? iconColor : iconColor.withOpacity(0.3),
                    onPressed: widget.canGoBack ? widget.onBack : null,
                    tooltip: '后退',
                  ),
                  // Forward button
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    color: widget.canGoForward ? iconColor : iconColor.withOpacity(0.3),
                    onPressed: widget.canGoForward ? widget.onForward : null,
                    tooltip: '前进',
                  ),
                  // Reload button
                  IconButton(
                    icon: Icon(
                      widget.isLoading ? Icons.close : Icons.refresh,
                      size: 20,
                    ),
                    color: iconColor,
                    onPressed: widget.onReload,
                    tooltip: widget.isLoading ? '停止' : '刷新',
                  ),
                  // URL / Search input
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          const Icon(Icons.lock_outline, size: 14, color: AppTheme.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: widget.urlController,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: '输入网址或搜索关键词...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.go,
                              onSubmitted: widget.onSubmitUrl,
                            ),
                          ),
                          // Clear button inside input
                          if (_showClear)
                            GestureDetector(
                              onTap: () => widget.urlController.clear(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Icon(
                                  Icons.cancel,
                                  size: 16,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Quick One-Click Summarize Button
                  IconButton(
                    icon: const Icon(Icons.bolt, size: 22, color: Colors.amber),
                    tooltip: '⚡ AI 网页速读',
                    onPressed: widget.onSummarize,
                  ),

                  // Quick tools menu (PopupMenuButton)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20, color: iconColor),
                    tooltip: '更多操作',
                    onSelected: (val) {
                      switch (val) {
                        case 'summarize':
                          widget.onSummarize();
                          break;
                        case 'clean':
                          widget.onCleanPage();
                          break;
                        case 'scripts':
                          widget.onOpenUserScripts();
                          break;
                        case 'copy':
                          _copyUrlToClipboard();
                          break;
                        case 'desktop':
                          widget.onToggleDesktopMode();
                          break;
                        case 'settings':
                          widget.onOpenSettings();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'summarize',
                        child: Row(
                          children: const [
                            Icon(Icons.bolt, size: 18, color: Colors.amber),
                            SizedBox(width: 10),
                            Text('⚡ AI 网页速读', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'clean',
                        child: Row(
                          children: const [
                            Icon(Icons.cleaning_services_outlined, size: 18, color: AppTheme.accent),
                            SizedBox(width: 10),
                            Text('🍃 纯净阅读 / 去跳App', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'scripts',
                        child: Row(
                          children: const [
                            Icon(Icons.code, size: 18, color: AppTheme.primary),
                            SizedBox(width: 10),
                            Text('🧪 AI 脚本工坊', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'copy',
                        child: Row(
                          children: const [
                            Icon(Icons.content_copy, size: 18),
                            SizedBox(width: 10),
                            Text('复制链接', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'desktop',
                        child: Row(
                          children: [
                            Icon(
                              widget.isDesktopMode ? Icons.phone_android : Icons.desktop_windows,
                              size: 18,
                              color: widget.isDesktopMode ? AppTheme.primary : null,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.isDesktopMode ? '切换为手机版' : '以电脑版浏览',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: const [
                            Icon(Icons.tune, size: 18),
                            SizedBox(width: 10),
                            Text('浏览器与 AI 设置', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Linear loading indicator
            if (widget.isLoading && widget.progress < 1.0)
              LinearProgressIndicator(
                value: widget.progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
