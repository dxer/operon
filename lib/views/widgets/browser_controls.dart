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
  final int tabCount;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final Function(String url) onSubmitUrl;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onOpenUserScripts;
  final VoidCallback onOpenTabOverview;
  final VoidCallback onNewTab;

  const BrowserControls({
    Key? key,
    required this.urlController,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.progress,
    required this.isDesktopMode,
    this.isCleanMode = false,
    this.tabCount = 1,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onSubmitUrl,
    required this.onOpenSettings,
    required this.onToggleDesktopMode,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onOpenUserScripts,
    required this.onOpenTabOverview,
    required this.onNewTab,
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
    final inputBg = isDark ? const Color(0xFF1E242B) : const Color(0xFFEFF3F4);
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
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: Row(
                children: [
                  // 1. Wide Spacious Address & Search Input Box
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Icon(
                            widget.urlController.text.startsWith('https://')
                                ? Icons.lock
                                : (widget.urlController.text.isEmpty ? Icons.search : Icons.public),
                            size: 15,
                            color: widget.urlController.text.startsWith('https://')
                                ? AppTheme.accent
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                          const SizedBox(width: 8),

                          // Text input field
                          Expanded(
                            child: TextField(
                              controller: widget.urlController,
                              style: TextStyle(
                                fontSize: 13.5,
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
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.go,
                              onSubmitted: widget.onSubmitUrl,
                            ),
                          ),

                          // Clear 'X' button inside input
                          if (_showClear)
                            GestureDetector(
                              onTap: () {
                                widget.urlController.clear();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Icon(
                                  Icons.cancel,
                                  size: 17,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),

                          // Quick ⚡ AI Summarize Button inside input
                          IconButton(
                            icon: const Icon(Icons.bolt, size: 20, color: Colors.amber),
                            tooltip: '⚡ AI 网页速读',
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            constraints: const BoxConstraints(),
                            onPressed: widget.onSummarize,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // 2. Tab Switcher Button (Shows Tab Count, e.g. [ 2 ])
                  InkWell(
                    onTap: widget.onOpenTabOverview,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isDark ? Colors.white70 : const Color(0xFF536471),
                          width: 1.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.tabCount}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F141C),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 2),

                  // 3. More Tools & Navigation Menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 22, color: iconColor),
                    tooltip: '更多操作',
                    offset: const Offset(0, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (val) {
                      switch (val) {
                        case 'back':
                          if (widget.canGoBack) widget.onBack();
                          break;
                        case 'forward':
                          if (widget.canGoForward) widget.onForward();
                          break;
                        case 'reload':
                          widget.onReload();
                          break;
                        case 'new_tab':
                          widget.onNewTab();
                          break;
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
                      // Quick Navigation Top Bar (Back, Forward, Reload, New Tab)
                      PopupMenuItem(
                        enabled: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                              color: widget.canGoBack ? AppTheme.primary : (isDark ? Colors.white24 : Colors.black26),
                              tooltip: '后退',
                              onPressed: widget.canGoBack
                                  ? () {
                                      Navigator.pop(context);
                                      widget.onBack();
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios, size: 18),
                              color: widget.canGoForward ? AppTheme.primary : (isDark ? Colors.white24 : Colors.black26),
                              tooltip: '前进',
                              onPressed: widget.canGoForward
                                  ? () {
                                      Navigator.pop(context);
                                      widget.onForward();
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: Icon(widget.isLoading ? Icons.close : Icons.refresh, size: 20),
                              color: isDark ? Colors.white : Colors.black87,
                              tooltip: widget.isLoading ? '停止' : '刷新',
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onReload();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_box_outlined, size: 20, color: AppTheme.accent),
                              tooltip: '新建标签页',
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onNewTab();
                              },
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),

                      // AI & Feature Items
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
                          children: [
                            Icon(
                              widget.isCleanMode ? Icons.cleaning_services : Icons.cleaning_services_outlined,
                              size: 18,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.isCleanMode ? '🍃 纯净模式已开启' : '🍃 纯净阅读 / 去跳App',
                              style: const TextStyle(fontSize: 13),
                            ),
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
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.isDesktopMode ? '切换为手机版' : '请求电脑桌面版',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: const [
                            Icon(Icons.settings_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('浏览器设置', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Top Linear Progress Bar
            if (widget.isLoading)
              LinearProgressIndicator(
                value: widget.progress > 0 ? widget.progress : null,
                minHeight: 2.0,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
