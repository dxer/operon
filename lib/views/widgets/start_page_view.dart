import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/storage_service.dart';

class StartPageView extends StatefulWidget {
  final StorageService storageService;
  final Function(String url) onOpenUrl;

  const StartPageView({
    Key? key,
    required this.storageService,
    required this.onOpenUrl,
  }) : super(key: key);

  @override
  State<StartPageView> createState() => _StartPageViewState();
}

class _StartPageViewState extends State<StartPageView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, String>> _shortcuts = [];

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadShortcuts() {
    setState(() {
      _shortcuts = widget.storageService.getShortcuts();
    });
  }

  void _handleSubmit(String input) {
    final query = input.trim();
    if (query.isEmpty) return;
    widget.onOpenUrl(query);
  }

  void _showAddShortcutDialog() {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加快捷网址', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: '网站名称',
                hintText: '如: GitHub',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: '网址 URL',
                hintText: 'https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (title.isNotEmpty && url.isNotEmpty) {
                final list = widget.storageService.getShortcuts();
                list.add({'title': title, 'url': url});
                await widget.storageService.saveShortcuts(list);
                _loadShortcuts();
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showShortcutOptions(int index) {
    final item = _shortcuts[index];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item['url'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除此快捷方式',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                final list = widget.storageService.getShortcuts();
                if (index < list.length) {
                  list.removeAt(index);
                  await widget.storageService.saveShortcuts(list);
                  _loadShortcuts();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutIcon(String title, bool isDark) {
    final lower = title.toLowerCase();
    final textColor = isDark ? Colors.white : Colors.black87;

    if (lower == 'x' || lower.contains('twitter')) {
      return Center(
        child: Text(
          'X',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      );
    }

    if (lower.contains('github') || lower.contains('git')) {
      return Center(
        child: Icon(Icons.code_rounded, size: 22, color: textColor),
      );
    }

    if (lower.contains('google')) {
      return const Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF4285F4),
          ),
        ),
      );
    }

    if (lower.contains('bilibili')) {
      return const Center(
        child: Text(
          'bili',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEC),
          ),
        ),
      );
    }

    if (lower.contains('wiki')) {
      return Center(
        child: Text(
          'W',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'serif',
            color: textColor,
          ),
        ),
      );
    }

    final firstChar = title.isNotEmpty ? title[0].toUpperCase() : 'W';
    return Center(
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final inputBg = isDark ? const Color(0xFF1B222A) : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final tileBg = isDark ? const Color(0xFF1E2630) : Colors.white;

    return Container(
      color: bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                // 1. Minimalist Monochrome Brand Logo
                Text(
                  'OPERON',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6.0,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AUTONOMOUS AI BROWSER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3.0,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 36),

                // 2. Centered Search Box
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: '搜索或输入网址...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textInputAction: TextInputAction.go,
                          onSubmitted: _handleSubmit,
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _handleSubmit(_searchController.text),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // 3. Via-Style Shortcuts Grid (4 Columns)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _shortcuts.length + 1,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    // Last item is "+ Add Shortcut"
                    if (index == _shortcuts.length) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _showAddShortcutDialog,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: tileBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: borderColor,
                                    style: BorderStyle.solid),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 22,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '添加',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final item = _shortcuts[index];
                    final title = item['title'] ?? '';
                    final url = item['url'] ?? '';

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => widget.onOpenUrl(url),
                      onLongPress: () => _showShortcutOptions(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: tileBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _buildShortcutIcon(title, isDark),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
