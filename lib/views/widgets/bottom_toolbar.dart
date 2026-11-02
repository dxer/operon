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
  final VoidCallback onOpenAgent;
  final VoidCallback onReload;
  final VoidCallback onStopLoad;
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
    super.key,
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
    required this.onOpenAgent,
    required this.onReload,
    required this.onStopLoad,
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
  });

  void _copyUrlToClipboard(BuildContext context) {
    if (currentUrl.isNotEmpty && !currentUrl.startsWith('operon://')) {
      Clipboard.setData(ClipboardData(text: currentUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制网页链接'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
      builder: (ctx) {
        return _ActionMenuSheet(
          isDark: isDark,
          isLoading: isLoading,
          isCleanMode: isCleanMode,
          isBookmarked: isBookmarked,
          isDesktopMode: isDesktopMode,
          onReload: onReload,
          onStopLoad: onStopLoad,
          onNewTab: onNewTab,
          onCopyUrl: () => _copyUrlToClipboard(context),
          onSummarize: onSummarize,
          onCleanPage: onCleanPage,
          onOpenUserScripts: onOpenUserScripts,
          onToggleBookmark: onToggleBookmark,
          onOpenHistory: onOpenHistory,
          onOpenBookmarks: onOpenBookmarks,
          onToggleDesktopMode: onToggleDesktopMode,
          onOpenSettings: onOpenSettings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF536471);
    final disabledColor = isDark ? Colors.white24 : Colors.black26;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              _ToolbarButton(
                icon: Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: canGoBack ? iconColor : disabledColor,
                tooltip: '后退',
                onTap: canGoBack ? onBack : null,
              ),
              _ToolbarButton(
                icon: Icons.arrow_forward_ios_rounded,
                size: 18,
                color: canGoForward ? iconColor : disabledColor,
                tooltip: '前进',
                onTap: canGoForward ? onForward : null,
              ),
              _ToolbarButton(
                icon: Icons.home_outlined,
                size: 22,
                color: iconColor,
                tooltip: '主页',
                onTap: onHome,
              ),
              Expanded(
                child: Center(
                  child: InkResponse(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onOpenTabs();
                    },
                    radius: 20,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color:
                              isDark ? Colors.white54 : const Color(0xFF536471),
                          width: 1.4,
                        ),
                      ),
                      child: Text(
                        '$tabCount',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF0F141C),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _ToolbarButton(
                icon: Icons.smart_toy_outlined,
                size: 21,
                color: AppTheme.accent,
                tooltip: 'AI 智能体',
                onTap: onOpenAgent,
              ),
              _ToolbarButton(
                icon: Icons.menu_rounded,
                size: 23,
                color: iconColor,
                tooltip: '菜单',
                onTap: () => _showMenu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          radius: 24,
          child: Center(
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

class _ActionMenuSheet extends StatelessWidget {
  final bool isDark;
  final bool isLoading;
  final bool isCleanMode;
  final bool isBookmarked;
  final bool isDesktopMode;
  final VoidCallback onReload;
  final VoidCallback onStopLoad;
  final VoidCallback onNewTab;
  final VoidCallback onCopyUrl;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onOpenUserScripts;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback onOpenSettings;

  const _ActionMenuSheet({
    required this.isDark,
    required this.isLoading,
    required this.isCleanMode,
    required this.isBookmarked,
    required this.isDesktopMode,
    required this.onReload,
    required this.onStopLoad,
    required this.onNewTab,
    required this.onCopyUrl,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onOpenUserScripts,
    required this.onToggleBookmark,
    required this.onOpenHistory,
    required this.onOpenBookmarks,
    required this.onToggleDesktopMode,
    required this.onOpenSettings,
  });

  void _run(BuildContext context, VoidCallback action) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    final actions = <_MenuAction>[
      _MenuAction(
          Icons.auto_awesome_rounded, 'AI 速读', AppTheme.accent, onSummarize),
      _MenuAction(
        isCleanMode
            ? Icons.chrome_reader_mode
            : Icons.chrome_reader_mode_outlined,
        isCleanMode ? '退出纯净' : '纯净阅读',
        AppTheme.accent,
        onCleanPage,
      ),
      _MenuAction(
          Icons.code_rounded, '用户脚本', AppTheme.primary, onOpenUserScripts),
      _MenuAction(
        isBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
        isBookmarked ? '取消收藏' : '收藏',
        isBookmarked ? Colors.amber : null,
        onToggleBookmark,
      ),
      _MenuAction(Icons.history_rounded, '浏览历史', null, onOpenHistory),
      _MenuAction(Icons.bookmarks_outlined, '我的书签', null, onOpenBookmarks),
      _MenuAction(
        isDesktopMode
            ? Icons.phone_android_rounded
            : Icons.desktop_windows_rounded,
        isDesktopMode ? '手机版' : '桌面版',
        null,
        onToggleDesktopMode,
      ),
      _MenuAction(Icons.settings_outlined, '设置', null, onOpenSettings),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: border, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _QuickAction(
                    icon:
                        isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                    label: isLoading ? '停止' : '刷新',
                    isDark: isDark,
                    onTap: () =>
                        _run(context, isLoading ? onStopLoad : onReload),
                  ),
                  const SizedBox(width: 10),
                  _QuickAction(
                    icon: Icons.add_rounded,
                    label: '新标签',
                    isDark: isDark,
                    onTap: () => _run(context, onNewTab),
                  ),
                  const SizedBox(width: 10),
                  _QuickAction(
                    icon: Icons.content_copy_rounded,
                    label: '复制链接',
                    isDark: isDark,
                    onTap: () => _run(context, onCopyUrl),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(height: 0.6, color: border),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: actions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _run(context, action.onTap),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.035),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            action.icon,
                            size: 20,
                            color: action.color ??
                                (isDark
                                    ? Colors.white70
                                    : const Color(0xFF536471)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF536471),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark ? Colors.white70 : const Color(0xFF536471),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : const Color(0xFF536471),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  _MenuAction(this.icon, this.label, this.color, this.onTap);
}
