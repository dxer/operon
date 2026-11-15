import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/web_tab.dart';
import '../../services/haptic_service.dart';
import '../../utils/url_utils.dart';
import 'site_icon.dart';

class TabsOverviewSheet extends StatelessWidget {
  final List<WebTab> tabs;
  final int activeIndex;
  final Function(int index) onSelectTab;
  final Function(int index) onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback? onNewIncognitoTab;
  final VoidCallback onCloseAll;

  const TabsOverviewSheet({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    this.onNewIncognitoTab,
    required this.onCloseAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.x3,
        AppSpace.page,
        AppSpace.x3,
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
      child: SafeArea(
        top: false,
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

            // Header: Tabs count, New Tab, Close All
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x2,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppInk.accentTint(isDark),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '${tabs.length} 个标签页',
                    style: AppType.label.copyWith(
                      color: AppTheme.primaryOf(isDark),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                if (tabs.length > 1)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.dangerOf(isDark),
                      textStyle: AppType.label,
                      minimumSize: const Size(0, AppSpace.tap),
                    ),
                    onPressed: () async {
                      HapticService.medium();
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('关闭全部标签页？'),
                          content: Text(
                            '将关闭当前 ${tabs.length} 个标签页并返回起始页。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.danger,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('全部关闭'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        onCloseAll();
                      }
                    },
                    child: const Text('全部关闭'),
                  ),
                const SizedBox(width: AppSpace.x1),
                if (onNewIncognitoTab != null) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppInk.primary(isDark),
                      side: BorderSide(color: AppInk.hairline(isDark)),
                      textStyle: AppType.label,
                      minimumSize: const Size(0, AppSpace.tap),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.x3,
                      ),
                    ),
                    onPressed: () {
                      HapticService.light();
                      Navigator.pop(context);
                      onNewIncognitoTab!();
                    },
                    child: const Text('无痕'),
                  ),
                  const SizedBox(width: AppSpace.x2),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryOf(isDark),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    textStyle: AppType.label,
                    minimumSize: const Size(0, AppSpace.tap),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x3,
                    ),
                  ),
                  onPressed: () {
                    HapticService.light();
                    Navigator.pop(context);
                    onNewTab();
                  },
                  child: const Text('新建'),
                ),
              ],
            ),

            const Divider(height: AppSpace.x5),

            // Tabs Grid
            Expanded(
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final isActive = index == activeIndex;
                  final host = hostOf(tab.url);

                  return Dismissible(
                    key: ValueKey('tab_${tab.id}_$index'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) {
                      HapticService.light();
                      onCloseTab(index);
                    },
                    child: InkWell(
                      onTap: () {
                        HapticService.selection();
                        Navigator.pop(context);
                        onSelectTab(index);
                      },
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppInk.sunken(isDark),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                            color: isActive
                                ? AppTheme.primaryOf(isDark)
                                : AppInk.hairline(isDark),
                            width: isActive ? 1.4 : AppStroke.hairline,
                          ),
                        ),
                        padding: const EdgeInsets.all(AppSpace.x3 - 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SiteIcon(
                                  host: host,
                                  size: 18,
                                  label: tab.title.isNotEmpty ? tab.title : host,
                                ),
                                const Spacer(),
                                if (tab.isIncognito)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: AppInk.sunken(isDark),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.chip - 4,
                                      ),
                                      border: Border.all(
                                        color: AppInk.hairline(isDark),
                                        width: AppStroke.hairline,
                                      ),
                                    ),
                                    child: Text(
                                      '无痕',
                                      style: AppType.micro.copyWith(
                                        color: AppInk.secondary(isDark),
                                      ),
                                    ),
                                  ),
                                if (isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.only(right: 2),
                                    decoration: BoxDecoration(
                                      color: AppInk.accentTint(isDark),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.chip - 4,
                                      ),
                                    ),
                                    child: Text(
                                      '当前',
                                      style: AppType.micro.copyWith(
                                        color: AppTheme.primaryOf(isDark),
                                      ),
                                    ),
                                  ),
                                Semantics(
                                  button: true,
                                  label: '关闭标签页',
                                  child: InkResponse(
                                    onTap: () {
                                      HapticService.selection();
                                      onCloseTab(index);
                                    },
                                    radius: 14,
                                    containedInkWell: true,
                                    highlightShape: BoxShape.circle,
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Center(
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 15,
                                          color: AppInk.tertiary(isDark),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Spacer(),

                            Text(
                              tab.title.isNotEmpty ? tab.title : '新标签页',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.body.copyWith(
                                color: AppInk.primary(isDark),
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              host.isNotEmpty ? host : 'about:blank',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                color: AppInk.tertiary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
