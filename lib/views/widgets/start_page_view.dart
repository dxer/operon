import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';
import '../../utils/url_utils.dart';
import 'browser_controls.dart' show AgentEntryButton;
import 'omnibox_suggestions.dart';
import 'operon_mark.dart';
import 'site_icon.dart';

class StartPageView extends StatefulWidget {
  final StorageService storageService;
  final Function(String url) onOpenUrl;

  /// Opens the assistant. Null hides the entry.
  final VoidCallback? onOpenAgent;

  /// A task is running, so the mark says so.
  final bool agentBusy;

  const StartPageView({
    super.key,
    required this.storageService,
    required this.onOpenUrl,
    this.onOpenAgent,
    this.agentBusy = false,
  });

  @override
  State<StartPageView> createState() => _StartPageViewState();
}

class _StartPageViewState extends State<StartPageView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, String>> _shortcuts = [];
  bool _hasFocus = false;
  String? _clipboardUrl;

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
    if (!mounted) return;
    final focused = _focusNode.hasFocus;
    if (_hasFocus != focused) {
      setState(() => _hasFocus = focused);
    }
    if (focused) {
      unawaited(_refreshClipboard());
    }
  }

  Future<void> _refreshClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final url = extractClipboardWebUrl(data?.text);
      if (mounted && url != _clipboardUrl) {
        setState(() => _clipboardUrl = url);
      }
    } catch (_) {}
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

  void _showShortcutDialog({int? editIndex}) {
    final editing = editIndex != null && editIndex < _shortcuts.length;
    final initial = editing ? _shortcuts[editIndex] : null;
    showDialog<void>(
      context: context,
      builder: (_) => _ShortcutDialog(
        editing: editing,
        initialTitle: initial?['title'] ?? '',
        initialUrl: initial?['url'] ?? 'https://',
        onSave: (title, url) async {
          final list = widget.storageService.getShortcuts();
          if (editing && editIndex < list.length) {
            list[editIndex] = {'title': title, 'url': url};
          } else {
            list.add({'title': title, 'url': url});
          }
          await widget.storageService.saveShortcuts(list);
          _loadShortcuts();
        },
      ),
    );
  }

  void _showShortcutOptions(int index) {
    HapticService.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _shortcuts[index];
    final title = item['title'] ?? '';
    final url = item['url'] ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.x2),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppInk.tertiary(isDark).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: SiteIcon(host: hostOf(url), size: 32, label: title),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.headline,
              ),
              subtitle: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(color: AppInk.secondary(isDark)),
              ),
            ),
            Divider(height: AppStroke.hairline, color: AppInk.hairline(isDark)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑快捷方式', style: AppType.body),
              onTap: () {
                Navigator.pop(ctx);
                _showShortcutDialog(editIndex: index);
              },
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.vertical_align_top_rounded),
                title: const Text('置顶到第一位', style: AppType.body),
                onTap: () async {
                  Navigator.pop(ctx);
                  final list = widget.storageService.getShortcuts();
                  if (index < list.length) {
                    final moved = list.removeAt(index);
                    list.insert(0, moved);
                    await widget.storageService.saveShortcuts(list);
                    _loadShortcuts();
                  }
                },
              ),
            ListTile(
              leading:
                  Icon(Icons.delete_outline, color: AppTheme.dangerOf(isDark)),
              title: Text(
                '删除此快捷方式',
                style: AppType.body.copyWith(color: AppTheme.dangerOf(isDark)),
              ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final borderColor =
        _hasFocus ? AppTheme.primaryOf(isDark) : AppInk.hairline(isDark);
    final tileBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final subtle = AppInk.tertiary(isDark);
    final suggestions = _hasFocus
        ? buildOmniboxSuggestions(
            query: _searchController.text,
            bookmarks: widget.storageService.getBookmarks(),
            history: widget.storageService.getHistory(),
            clipboardUrl: _clipboardUrl,
          )
        : const <OmniboxSuggestion>[];

    Widget shortcutGrid() {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _shortcuts.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: AppSpace.x5,
          crossAxisSpacing: AppSpace.x2,
          childAspectRatio: 0.86,
        ),
        itemBuilder: (context, index) {
          if (index == _shortcuts.length) {
            return _ShortcutTile(
              label: '添加',
              isDark: isDark,
              onTap: () => _showShortcutDialog(),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                  border: Border.all(
                    color: AppInk.hairline(isDark),
                    width: AppStroke.hairline,
                  ),
                ),
                child: Icon(Icons.add_rounded, size: 20, color: subtle),
              ),
            );
          }

          final item = _shortcuts[index];
          final title = item['title'] ?? '';
          final url = item['url'] ?? '';

          return _ShortcutTile(
            label: title,
            isDark: isDark,
            onTap: () {
              HapticService.selection();
              widget.onOpenUrl(url);
            },
            onLongPress: () => _showShortcutOptions(index),
            // The site's own mark. A browser that shows letters where icons
            // belong looks like a mock-up of a browser.
            child: SiteIcon(host: hostOf(url), size: 46, label: title),
          );
        },
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_hasFocus) _focusNode.unfocus();
      },
      child: ColoredBox(
        color: bg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x6,
                vertical: AppSpace.x6,
              ),
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
                  // A quiet brand row. The first screen of a browser owes its
                  // brightest pixels to the input field, not to its own name:
                  // it used to be a glass tile over `OPERON` at 900 weight with
                  // 8pt of letterspacing, plus an all-caps tagline — three
                  // devices competing with the thing the user came to use.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppInk.accentTint(isDark),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Center(
                          child: OperonMark(
                            size: 16,
                            color: AppTheme.primaryOf(isDark),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.x2 + 2),
                      Text(
                        'Operon',
                        style: AppType.headline.copyWith(
                          color: AppInk.primary(isDark),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.x8),
                  // Search box
                  // The assistant entry mirrors the address bar: outside the
                  // field, on the left, so it is in the same place whatever the
                  // page below it is.
                  Row(
                    children: [
                      if (widget.onOpenAgent != null) ...[
                        AgentEntryButton(
                          isDark: isDark,
                          busy: widget.agentBusy,
                          onTap: widget.onOpenAgent!,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _focusNode.requestFocus(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            height: AppSpace.pill,
                            decoration: BoxDecoration(
                              color: AppInk.sunken(isDark),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: borderColor,
                                width: AppStroke.hairline,
                              ),
                            ),
                            padding: const EdgeInsets.only(
                              left: AppSpace.x4,
                              right: AppSpace.x1,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: AppInk.tertiary(isDark),
                                ),
                                const SizedBox(width: AppSpace.x2),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _focusNode,
                                    textAlignVertical: TextAlignVertical.center,
                                    cursorColor: AppTheme.primaryOf(isDark),
                                    style: AppType.body.copyWith(
                                      color: AppInk.primary(isDark),
                                    ),
                                    decoration: AppTheme.flatInput.copyWith(
                                      hintText: '搜索或输入网址',
                                      hintStyle: AppType.body.copyWith(
                                        color: AppInk.tertiary(isDark),
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
                                        width: AppSpace.tap,
                                        height: AppSpace.tap,
                                        child: Center(
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: AppInk.tertiary(isDark),
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
                                      size: 19,
                                      color: AppInk.secondary(isDark),
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: AppSpace.tap,
                                      minHeight: AppSpace.tap,
                                    ),
                                    onPressed: () =>
                                        _handleSubmit(_searchController.text),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.x4),
                  if (_hasFocus && suggestions.isNotEmpty)
                    OmniboxSuggestionsPanel(
                      suggestions: suggestions,
                      onSelect: (url) {
                        _focusNode.unfocus();
                        widget.onOpenUrl(url);
                      },
                      onFillQuery: (url) {
                        _searchController.text = url;
                        _searchController.selection =
                            TextSelection.collapsed(offset: url.length);
                      },
                    )
                  else ...[
                    const SizedBox(height: AppSpace.x2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '常用',
                        style: AppType.label.copyWith(
                          color: AppInk.secondary(isDark),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.x3),
                    shortcutGrid(),
                  ],
                ],
              ),
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
  final bool isDark;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ShortcutTile({
    required this.label,
    required this.isDark,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.icon),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // No border and no shadow around the mark: a tile on a page
          // background is a surface, and surfaces here do not float. The
          // shadow used to make twelve tiles compete with the search field.
          child,
          const SizedBox(height: AppSpace.x2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: AppInk.secondary(isDark)),
          ),
        ],
      ),
    );
  }
}

class _ShortcutDialog extends StatefulWidget {
  final bool editing;
  final String initialTitle;
  final String initialUrl;
  final Future<void> Function(String title, String url) onSave;

  const _ShortcutDialog({
    required this.editing,
    required this.initialTitle,
    required this.initialUrl,
    required this.onSave,
  });

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.editing ? '编辑快捷网址' : '添加快捷网址',
        style: AppType.headline,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            style: AppType.body,
            decoration: const InputDecoration(
              labelText: '网站名称',
              hintText: '如: GitHub',
            ),
          ),
          const SizedBox(height: AppSpace.x3),
          TextField(
            controller: _urlCtrl,
            style: AppType.body,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '网址 URL',
              hintText: 'https://...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            final url = _urlCtrl.text.trim();
            if (title.isEmpty || url.isEmpty) return;
            await widget.onSave(title, url);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.editing ? '保存' : '添加'),
        ),
      ],
    );
  }
}
