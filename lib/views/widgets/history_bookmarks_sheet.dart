import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/bookmark_item.dart';
import '../../models/history_item.dart';
import '../../services/storage_service.dart';

class HistoryBookmarksSheet extends StatefulWidget {
  final StorageService storageService;
  final Function(String url) onOpenUrl;
  final int initialTabIndex; // 0: History, 1: Bookmarks

  const HistoryBookmarksSheet({
    super.key,
    required this.storageService,
    required this.onOpenUrl,
    this.initialTabIndex = 0,
  });

  @override
  State<HistoryBookmarksSheet> createState() => _HistoryBookmarksSheetState();
}

class _HistoryBookmarksSheetState extends State<HistoryBookmarksSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<HistoryItem> _allHistory = [];
  List<BookmarkItem> _allBookmarks = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _allHistory = widget.storageService.getHistory();
      _allBookmarks = widget.storageService.getBookmarks();
    });
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要删除所有的浏览历史吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storageService.clearHistory();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightCard;
    final dividerColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightBg;

    final filteredHistory = _allHistory.where((h) {
      if (_searchQuery.isEmpty) return true;
      return h.title.toLowerCase().contains(_searchQuery) ||
          h.url.toLowerCase().contains(_searchQuery);
    }).toList();

    final filteredBookmarks = _allBookmarks.where((b) {
      if (_searchQuery.isEmpty) return true;
      return b.title.toLowerCase().contains(_searchQuery) ||
          b.url.toLowerCase().contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : Colors.black,
              unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
              indicatorColor: isDark ? Colors.white : Colors.black,
              indicatorWeight: 2.5,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('历史记录 (${_allHistory.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bookmark_border_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('书签收藏 (${_allBookmarks.length})'),
                    ],
                  ),
                ),
              ],
            ),

            // Search Box & Actions Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dividerColor),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              size: 18,
                              color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(fontSize: 13),
                              decoration: AppTheme.flatInput.copyWith(
                                hintText: '搜索标题或网址...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppTheme.darkMuted
                                          .withValues(alpha: 0.72)
                                      : AppTheme.lightMuted
                                          .withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => _searchController.clear(),
                              child: Icon(Icons.close,
                                  size: 16,
                                  color:
                                      isDark ? Colors.white38 : Colors.black38),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_allHistory.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.danger),
                      label: const Text('清空',
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.danger)),
                      onPressed: _clearAllHistory,
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1. History List
                  filteredHistory.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.history_rounded,
                          text: _searchQuery.isEmpty ? '暂无浏览历史' : '无匹配历史',
                          isDark: isDark,
                        )
                      : ListView.separated(
                          itemCount: filteredHistory.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: dividerColor),
                          itemBuilder: (context, index) {
                            final item = filteredHistory[index];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 2),
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.public,
                                    size: 18, color: AppTheme.primary),
                              ),
                              title: Text(
                                item.title.isNotEmpty ? item.title : item.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDateTime(item.visitedAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                color: isDark ? Colors.white38 : Colors.black38,
                                tooltip: '删除此记录',
                                onPressed: () async {
                                  await widget.storageService
                                      .removeHistoryItem(item.id);
                                  _loadData();
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onOpenUrl(item.url);
                              },
                            );
                          },
                        ),

                  // 2. Bookmarks List
                  filteredBookmarks.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.bookmark_border_rounded,
                          text: _searchQuery.isEmpty ? '暂无书签收藏' : '无匹配书签',
                          isDark: isDark,
                        )
                      : ListView.separated(
                          itemCount: filteredBookmarks.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: dividerColor),
                          itemBuilder: (context, index) {
                            final item = filteredBookmarks[index];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 2),
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.star_rounded,
                                    size: 20, color: AppTheme.warning),
                              ),
                              title: Text(
                                item.title.isNotEmpty ? item.title : item.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                item.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white38 : Colors.black45,
                                ),
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 16),
                                color: isDark ? Colors.white38 : Colors.black38,
                                tooltip: '移除书签',
                                onPressed: () async {
                                  await widget.storageService
                                      .removeBookmark(item.id);
                                  _loadData();
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onOpenUrl(item.url);
                              },
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String text,
    required bool isDark,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
