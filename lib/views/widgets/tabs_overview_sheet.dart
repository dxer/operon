import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/web_tab.dart';

class TabsOverviewSheet extends StatelessWidget {
  final List<WebTab> tabs;
  final int activeIndex;
  final Function(int index) onSelectTab;
  final Function(int index) onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onCloseAll;

  const TabsOverviewSheet({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
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
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header: Tabs count, New Tab, Close All
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${tabs.length} 个标签页',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                if (tabs.length > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('全部关闭', style: TextStyle(fontSize: 12)),
                    style:
                        TextButton.styleFrom(foregroundColor: AppTheme.danger),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      onCloseAll();
                    },
                  ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    onNewTab();
                  },
                ),
              ],
            ),

            const Divider(height: 20),

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

                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      onSelectTab(index);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isDark ? AppTheme.darkInput : AppTheme.lightInput,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primary
                              : (isDark
                                  ? AppTheme.darkBorder
                                  : AppTheme.lightBorder),
                          width: isActive ? 2.0 : 1.0,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card Header: Globe icon & Close 'X' button
                          Row(
                            children: [
                              Icon(
                                tab.url.startsWith('https://')
                                    ? Icons.lock
                                    : Icons.public,
                                size: 14,
                                color: isActive
                                    ? AppTheme.primary
                                    : (isDark
                                        ? Colors.white54
                                        : Colors.black45),
                              ),
                              const Spacer(),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '当前',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onCloseTab(index);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 14),
                                ),
                              ),
                            ],
                          ),

                          const Spacer(),

                          // Page Title
                          Text(
                            tab.title.isNotEmpty ? tab.title : '新标签页',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Page URL
                          Text(
                            tab.url.isNotEmpty ? tab.url : 'about:blank',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
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
