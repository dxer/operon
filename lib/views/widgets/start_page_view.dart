import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';
import 'operon_mark.dart';

class StartPageView extends StatefulWidget {
  final StorageService storageService;
  final Function(String url) onOpenUrl;

  const StartPageView({
    super.key,
    required this.storageService,
    required this.onOpenUrl,
  });

  @override
  State<StartPageView> createState() => _StartPageViewState();
}

class _StartPageViewState extends State<StartPageView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, String>> _shortcuts = [];
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _searchController.addListener(_onSearchChanged);
    _loadShortcuts();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _focusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted && _hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  void _loadShortcuts() {
    setState(() {
      _shortcuts = widget.storageService.getShortcuts();
    });
  }

  void _handleSubmit(String input) {
    final query = input.trim();
    if (query.isEmpty) return;
    HapticService.selection();
    _focusNode.unfocus();
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
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showShortcutOptions(int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.dangerOf(isDark)),
              title: Text('删除此快捷方式',
                  style: TextStyle(color: AppTheme.dangerOf(isDark))),
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
    final bgTop = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final bgBottom = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final inputBg = isDark ? AppTheme.darkInput : AppTheme.lightCard;
    final borderColor = _hasFocus
        ? AppTheme.primaryOf(isDark)
        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);
    final tileBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final tileBorder = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final subtle = isDark ? Colors.white38 : Colors.black38;

    Widget shortcutGrid() {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _shortcuts.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 20,
          crossAxisSpacing: 10,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          if (index == _shortcuts.length) {
            return _ShortcutTile(
              label: '添加',
              tileBg: tileBg,
              borderColor: tileBorder,
              isDark: isDark,
              onTap: _showAddShortcutDialog,
              child: Icon(Icons.add_rounded, size: 22, color: subtle),
            );
          }

          final item = _shortcuts[index];
          final title = item['title'] ?? '';
          final url = item['url'] ?? '';

          return _ShortcutTile(
            label: title,
            tileBg: tileBg,
            borderColor: tileBorder,
            isDark: isDark,
            onTap: () {
              HapticService.selection();
              widget.onOpenUrl(url);
            },
            onLongPress: () => _showShortcutOptions(index),
            child: _buildShortcutIcon(title, isDark),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.maybeDisableAnimationsOf(context) == true
                  ? Duration.zero
                  : const Duration(milliseconds: 460),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Brand mark
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        width: 0.8,
                      ),
                    ),
                    child: OperonMark(
                      size: 26,
                      color: isDark
                          ? AppTheme.darkOnSurface
                          : AppTheme.lightOnSurface,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'OPERON',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8.0,
                      color: isDark
                          ? AppTheme.darkOnSurface
                          : AppTheme.lightOnSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'DON\'T JUST BROWSE. OPERATE.',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.4,
                      color: subtle,
                    ),
                  ),
                  const SizedBox(height: 34),

                  // Search box
                  GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 54,
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(27),
                        border: Border.all(color: borderColor, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.28 : 0.045),
                            blurRadius: isDark ? 18 : 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 21,
                            color: isDark
                                ? AppTheme.darkMuted
                                : AppTheme.lightMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              textAlignVertical: TextAlignVertical.center,
                              cursorColor: AppTheme.primaryOf(isDark),
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.normal,
                                color: isDark
                                    ? AppTheme.darkOnSurface
                                    : AppTheme.lightOnSurface,
                              ),
                              decoration: AppTheme.flatInput.copyWith(
                                hintText: '搜索或输入网址',
                                hintStyle: TextStyle(
                                  fontSize: 15.5,
                                  color: isDark
                                      ? AppTheme.darkMuted
                                          .withValues(alpha: 0.72)
                                      : AppTheme.lightMuted
                                          .withValues(alpha: 0.78),
                                ),
                              ),
                              textInputAction: TextInputAction.go,
                              onSubmitted: _handleSubmit,
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            Semantics(
                              button: true,
                              label: '清空搜索框',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: isDark
                                          ? AppTheme.darkMuted
                                          : AppTheme.lightMuted,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            IconButton(
                              tooltip: '打开',
                              icon: Icon(
                                Icons.arrow_forward_rounded,
                                size: 20,
                                color: isDark
                                    ? AppTheme.darkMuted
                                    : AppTheme.lightMuted,
                              ),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              onPressed: () =>
                                  _handleSubmit(_searchController.text),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Via-style shortcut grid
                  shortcutGrid(),
                  if (_shortcuts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '长按快捷方式可删除',
                      style: TextStyle(fontSize: 10.5, color: subtle),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final String label;
  final Color tileBg;
  final Color borderColor;
  final bool isDark;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ShortcutTile({
    required this.label,
    required this.tileBg,
    required this.borderColor,
    required this.isDark,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: child,
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? AppTheme.darkMuted : AppTheme.lightOnSurface,
            ),
          ),
        ],
      ),
    );
  }
}
