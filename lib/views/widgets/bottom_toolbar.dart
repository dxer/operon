import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';

class BottomToolbar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final int tabCount;
  final bool isBookmarked;
  final bool isDesktopMode;
  final bool isCleanMode;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onOpenTabs;
  final VoidCallback onReload;
  final VoidCallback onNewTab;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onOpenUserScripts;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onOpenSettings;
  final String currentUrl;

  const BottomToolbar({
    Key? key,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.tabCount,
    required this.isBookmarked,
    required this.isDesktopMode,
    required this.isCleanMode,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onOpenTabs,
    required this.onReload,
    required this.onNewTab,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onOpenUserScripts,
    required this.onToggleBookmark,
    required this.onOpenHistory,
    required this.onOpenBookmarks,
    required this.onToggleDesktopMode,
    required this.onOpenSettings,
    required this.currentUrl,
  }) : super(key: key);

  void _copyUrlToClipboard(BuildContext context) {
    if (currentUrl.isNotEmpty && !currentUrl.startsWith('operon://')) {
      Clipboard.setData(ClipboardData(text: currentUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制网页链接到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF13171F) : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final iconColor = isDark ? Colors.white70 : const Color(0xFF536471);
    final disabledColor = isDark ? Colors.white24 : Colors.black26;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 1. Back
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: canGoBack ? iconColor : disabledColor,
            tooltip: '后退',
            onPressed: canGoBack ? onBack : null,
          ),

          // 2. Forward
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            color: canGoForward ? iconColor : disabledColor,
            tooltip: '前进',
            onPressed: canGoForward ? onForward : null,
          ),

          // 3. Home
          IconButton(
            icon: const Icon(Icons.home_outlined, size: 22),
            color: iconColor,
            tooltip: '主页',
            onPressed: onHome,
          ),

          // 4. Tabs Overview Badge
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onOpenTabs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: iconColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$tabCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ),
          ),

          // 5. More Menu
          PopupMenuButton<String>(
            icon: Icon(Icons.menu_rounded, size: 22, color: iconColor),
            tooltip: '菜单',
            offset: const Offset(0, -420),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              switch (val) {
                case 'reload':
                  onReload();
                  break;
                case 'new_tab':
                  onNewTab();
                  break;
                case 'summarize':
                  onSummarize();
                  break;
                case 'clean':
                  onCleanPage();
                  break;
                case 'scripts':
                  onOpenUserScripts();
                  break;
                case 'toggle_bookmark':
                  onToggleBookmark();
                  break;
                case 'history':
                  onOpenHistory();
                  break;
                case 'bookmarks':
                  onOpenBookmarks();
                  break;
                case 'copy':
                  _copyUrlToClipboard(context);
                  break;
                case 'desktop':
                  onToggleDesktopMode();
                  break;
                case 'settings':
                  onOpenSettings();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              // Top Quick Actions Bar (Reload, New Tab, Copy)
              PopupMenuItem(
                enabled: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: Icon(isLoading ? Icons.close_rounded : Icons.refresh_rounded, size: 20),
                      color: isDark ? Colors.white : Colors.black87,
                      tooltip: isLoading ? '停止' : '刷新',
                      onPressed: () {
                        Navigator.pop(ctx);
                        onReload();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 22, color: AppTheme.accent),
                      tooltip: '新建标签页',
                      onPressed: () {
                        Navigator.pop(ctx);
                        onNewTab();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_copy_rounded, size: 19),
                      color: isDark ? Colors.white : Colors.black87,
                      tooltip: '复制链接',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _copyUrlToClipboard(context);
                      },
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),

              // Tools
              PopupMenuItem(
                value: 'summarize',
                child: Row(
                  children: const [
                    Icon(Icons.auto_awesome, size: 18, color: AppTheme.accent),
                    SizedBox(width: 12),
                    Text('AI 网页速读', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clean',
                child: Row(
                  children: [
                    Icon(
                      isCleanMode ? Icons.article : Icons.article_outlined,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 12),
                    Text(
                      isCleanMode ? '纯净阅读模式已开启' : '纯净阅读模式',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'scripts',
                child: Row(
                  children: const [
                    Icon(Icons.code_rounded, size: 18, color: AppTheme.primary),
                    SizedBox(width: 12),
                    Text('用户脚本工坊', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuDivider(),

              PopupMenuItem(
                value: 'toggle_bookmark',
                child: Row(
                  children: [
                    Icon(
                      isBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color: isBookmarked ? Colors.amber : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isBookmarked ? '移除书签收藏' : '添加书签收藏',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: Row(
                  children: const [
                    Icon(Icons.history_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('浏览历史', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'bookmarks',
                child: Row(
                  children: const [
                    Icon(Icons.bookmarks_outlined, size: 18),
                    SizedBox(width: 12),
                    Text('我的书签', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuDivider(),

              PopupMenuItem(
                value: 'desktop',
                child: Row(
                  children: [
                    Icon(
                      isDesktopMode ? Icons.phone_android_rounded : Icons.desktop_windows_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isDesktopMode ? '切换为手机版' : '请求电脑桌面版',
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
                    SizedBox(width: 12),
                    Text('浏览器设置', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
