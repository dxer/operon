import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';

class BottomToolbar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final int tabCount;
  final bool isBookmarked;
  final bool isDesktopMode;
  final bool isCleanMode;
  final bool isWebDarkMode;
  final bool isBlockImages;

  /// Reading features can be turned off in settings; their entries go with them.
  final bool showCleanMode;
  final bool showSummary;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onHome;
  final VoidCallback onOpenTabs;
  final VoidCallback? onPreviousTab;
  final VoidCallback? onNextTab;
  final VoidCallback? onLongPressTabs;
  final VoidCallback? onLongPressHome;
  final VoidCallback onReload;
  final VoidCallback onStopLoad;
  final VoidCallback onNewTab;
  final VoidCallback? onNewIncognitoTab;
  final VoidCallback? onOpenDownloads;
  final VoidCallback? onFindInPage;
  final VoidCallback? onShareUrl;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback? onToggleWebDarkMode;
  final VoidCallback? onToggleBlockImages;
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
    this.isWebDarkMode = false,
    this.isBlockImages = false,
    this.showCleanMode = true,
    this.showSummary = true,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onOpenTabs,
    this.onPreviousTab,
    this.onNextTab,
    this.onLongPressTabs,
    this.onLongPressHome,
    required this.onReload,
    required this.onStopLoad,
    required this.onNewTab,
    this.onNewIncognitoTab,
    this.onOpenDownloads,
    this.onFindInPage,
    this.onShareUrl,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onToggleBookmark,
    required this.onOpenHistory,
    required this.onOpenBookmarks,
    required this.onToggleDesktopMode,
    this.onToggleWebDarkMode,
    this.onToggleBlockImages,
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
    HapticService.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
      builder: (ctx) {
        return _ActionMenuSheet(
          isDark: isDark,
          showCleanMode: showCleanMode,
          showSummary: showSummary,
          isLoading: isLoading,
          isCleanMode: isCleanMode,
          isBookmarked: isBookmarked,
          isDesktopMode: isDesktopMode,
          isWebDarkMode: isWebDarkMode,
          isBlockImages: isBlockImages,
          hasWebPage:
              currentUrl.isNotEmpty && !currentUrl.startsWith('operon://'),
          onReload: onReload,
          onStopLoad: onStopLoad,
          onNewTab: onNewTab,
          onNewIncognitoTab: onNewIncognitoTab,
          onOpenDownloads: onOpenDownloads,
          onFindInPage: onFindInPage,
          onCopyUrl: () => _copyUrlToClipboard(context),
          onShareUrl: onShareUrl,
          onSummarize: onSummarize,
          onCleanPage: onCleanPage,
          onToggleBookmark: onToggleBookmark,
          onOpenHistory: onOpenHistory,
          onOpenBookmarks: onOpenBookmarks,
          onToggleDesktopMode: onToggleDesktopMode,
          onToggleWebDarkMode: onToggleWebDarkMode,
          onToggleBlockImages: onToggleBlockImages,
          onOpenSettings: onOpenSettings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final iconColor = AppInk.secondary(isDark);
    final disabledColor = AppInk.tertiary(isDark).withValues(alpha: 0.45);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: tabCount > 1
          ? (details) {
              final vx = details.primaryVelocity ?? 0;
              if (vx < -220 && onNextTab != null) {
                HapticService.selection();
                onNextTab!();
              } else if (vx > 220 && onPreviousTab != null) {
                HapticService.selection();
                onPreviousTab!();
              }
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            top: BorderSide(
              color: AppInk.hairline(isDark),
              width: AppStroke.hairline,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppSpace.row,
            child: Row(
              children: [
                _ToolbarButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: canGoBack ? iconColor : disabledColor,
                  tooltip: '后退',
                  onTap: canGoBack ? onBack : null,
                  onLongPress: canGoBack ? onHome : null,
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
                  tooltip: '主页（长按打开书签）',
                  onTap: onHome,
                  onLongPress: onLongPressHome ?? onOpenBookmarks,
                ),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: '标签页，共 $tabCount 个（长按新建）',
                      child: Tooltip(
                        message: '标签页（长按新建，左右滑动切换）',
                        child: InkResponse(
                          onTap: () {
                            HapticService.selection();
                            onOpenTabs();
                          },
                          onLongPress: onLongPressTabs == null
                              ? null
                              : () {
                                  HapticService.medium();
                                  onLongPressTabs!();
                                },
                          radius: 22,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.chip),
                                  border: Border.all(
                                    color: AppInk.secondary(isDark),
                                    width: 1.4,
                                  ),
                                ),
                                child: Text(
                                  '$tabCount',
                                  style: AppType.micro.copyWith(
                                    color: AppInk.primary(isDark),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ToolbarButton(
                  icon: Icons.menu_rounded,
                  size: 23,
                  color: iconColor,
                  tooltip: '菜单（长按进设置）',
                  onTap: () => _showMenu(context),
                  onLongPress: onOpenSettings,
                ),
              ],
            ),
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
  final VoidCallback? onLongPress;

  const _ToolbarButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: InkResponse(
            onTap: onTap == null
                ? null
                : () {
                    HapticService.selection();
                    onTap!();
                  },
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticService.medium();
                    onLongPress!();
                  },
            radius: 24,
            child: Center(
              child: Icon(icon, size: size, color: color),
            ),
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
  final bool isWebDarkMode;
  final bool isBlockImages;
  final bool hasWebPage;

  /// Reading features can be turned off in settings; their entries go with them.
  final bool showCleanMode;
  final bool showSummary;
  final VoidCallback onReload;
  final VoidCallback onStopLoad;
  final VoidCallback onNewTab;
  final VoidCallback? onNewIncognitoTab;
  final VoidCallback? onOpenDownloads;
  final VoidCallback? onFindInPage;
  final VoidCallback onCopyUrl;
  final VoidCallback? onShareUrl;
  final VoidCallback onSummarize;
  final VoidCallback onCleanPage;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onToggleDesktopMode;
  final VoidCallback? onToggleWebDarkMode;
  final VoidCallback? onToggleBlockImages;
  final VoidCallback onOpenSettings;

  const _ActionMenuSheet({
    required this.isDark,
    required this.isLoading,
    required this.isCleanMode,
    required this.isBookmarked,
    required this.isDesktopMode,
    this.isWebDarkMode = false,
    this.isBlockImages = false,
    this.hasWebPage = true,
    this.showCleanMode = true,
    this.showSummary = true,
    required this.onReload,
    required this.onStopLoad,
    required this.onNewTab,
    this.onNewIncognitoTab,
    this.onOpenDownloads,
    this.onFindInPage,
    required this.onCopyUrl,
    this.onShareUrl,
    required this.onSummarize,
    required this.onCleanPage,
    required this.onToggleBookmark,
    required this.onOpenHistory,
    required this.onOpenBookmarks,
    required this.onToggleDesktopMode,
    this.onToggleWebDarkMode,
    this.onToggleBlockImages,
    required this.onOpenSettings,
  });

  void _run(BuildContext context, VoidCallback action) {
    HapticService.selection();
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final hairline = AppInk.hairline(isDark);
    final primary = AppTheme.primaryOf(isDark);

    final actions = <_MenuAction>[
      _MenuAction(
        isBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
        isBookmarked ? '已收藏' : '添加书签',
        isBookmarked ? AppTheme.warningOf(isDark) : null,
        onToggleBookmark,
        active: isBookmarked,
      ),
      _MenuAction(Icons.history_rounded, '浏览历史', null, onOpenHistory),
      _MenuAction(Icons.bookmarks_outlined, '我的书签', null, onOpenBookmarks),
      if (onOpenDownloads != null)
        _MenuAction(
          Icons.download_outlined,
          '下载管理',
          null,
          onOpenDownloads!,
        ),
      if (onNewIncognitoTab != null)
        _MenuAction(
          Icons.visibility_off_outlined,
          '无痕标签',
          null,
          onNewIncognitoTab!,
        ),
      if (hasWebPage && onFindInPage != null)
        _MenuAction(
          Icons.find_in_page_outlined,
          '页内查找',
          null,
          onFindInPage!,
        ),
      if (showSummary && hasWebPage)
        _MenuAction(
          Icons.auto_awesome_rounded,
          'AI 速读',
          primary,
          onSummarize,
        ),
      if (showCleanMode && hasWebPage)
        _MenuAction(
          isCleanMode
              ? Icons.chrome_reader_mode
              : Icons.chrome_reader_mode_outlined,
          isCleanMode ? '退出纯净' : '纯净阅读',
          isCleanMode ? primary : null,
          onCleanPage,
          active: isCleanMode,
        ),
      if (onToggleWebDarkMode != null)
        _MenuAction(
          isWebDarkMode ? Icons.dark_mode_rounded : Icons.dark_mode_outlined,
          '网页夜间',
          isWebDarkMode ? primary : null,
          onToggleWebDarkMode!,
          active: isWebDarkMode,
        ),
      if (onToggleBlockImages != null)
        _MenuAction(
          isBlockImages ? Icons.hide_image_rounded : Icons.image_outlined,
          '无图省流',
          isBlockImages ? primary : null,
          onToggleBlockImages!,
          active: isBlockImages,
        ),
      _MenuAction(
        isDesktopMode
            ? Icons.desktop_windows_rounded
            : Icons.desktop_windows_outlined,
        isDesktopMode ? '桌面模式' : '桌面版',
        isDesktopMode ? primary : null,
        onToggleDesktopMode,
        active: isDesktopMode,
      ),
      _MenuAction(Icons.settings_outlined, '设置', null, onOpenSettings),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border(
          top: BorderSide(color: hairline, width: AppStroke.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.x5,
            AppSpace.x2 + 2,
            AppSpace.x5,
            AppSpace.x4,
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
                    color: AppInk.tertiary(isDark).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.x3),
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
                  const SizedBox(width: AppSpace.x2 + 2),
                  _QuickAction(
                    icon: Icons.add_rounded,
                    label: '新标签',
                    isDark: isDark,
                    onTap: () => _run(context, onNewTab),
                  ),
                  if (hasWebPage) ...[
                    const SizedBox(width: AppSpace.x2 + 2),
                    _QuickAction(
                      icon: Icons.content_copy_rounded,
                      label: '复制链接',
                      isDark: isDark,
                      onTap: () => _run(context, onCopyUrl),
                    ),
                    if (onShareUrl != null) ...[
                      const SizedBox(width: AppSpace.x2 + 2),
                      _QuickAction(
                        icon: Icons.ios_share_rounded,
                        label: '分享',
                        isDark: isDark,
                        onTap: () => _run(context, onShareUrl!),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.x3),
              Divider(
                height: AppStroke.hairline,
                thickness: AppStroke.hairline,
                color: hairline,
              ),
              const SizedBox(height: AppSpace.x2),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: actions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: AppSpace.x1,
                  crossAxisSpacing: AppSpace.x1,
                  childAspectRatio: 1.05,
                ),
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                    onTap: () => _run(context, action.onTap),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: AppSpace.tap,
                          height: AppSpace.tap,
                          decoration: BoxDecoration(
                            color: action.active
                                ? AppInk.accentTint(isDark)
                                : AppInk.sunken(isDark),
                            borderRadius: BorderRadius.circular(AppRadius.icon),
                            border: action.active
                                ? Border.all(
                                    color: primary.withValues(alpha: 0.35),
                                    width: AppStroke.hairline,
                                  )
                                : null,
                          ),
                          child: Icon(
                            action.icon,
                            size: 20,
                            color: action.color ?? AppInk.secondary(isDark),
                          ),
                        ),
                        const SizedBox(height: AppSpace.x1 + 2),
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.micro.copyWith(
                            color: action.active
                                ? primary
                                : AppInk.secondary(isDark),
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
        borderRadius: BorderRadius.circular(AppRadius.icon),
        onTap: onTap,
        child: Container(
          height: AppSpace.tap,
          decoration: BoxDecoration(
            color: AppInk.sunken(isDark),
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: AppInk.secondary(isDark),
              ),
              const SizedBox(width: AppSpace.x1),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(
                    color: AppInk.secondary(isDark),
                  ),
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
  final bool active;

  _MenuAction(
    this.icon,
    this.label,
    this.color,
    this.onTap, {
    this.active = false,
  });
}
