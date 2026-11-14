part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// Things the user does to a page: bookmark, share, summarise, scroll to it.

extension _PageActions on _BrowserPageState {
  void _toggleBookmarkCurrentPage() async {
    final url = _currentTab.url;
    final title = _currentTab.title;
    if (url.isEmpty || url.startsWith('about:')) return;

    final isBookmarked = _storage?.isBookmarked(url) ?? false;
    if (isBookmarked) {
      await _storage?.removeBookmark(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已从书签中移除'),
            duration: Duration(seconds: 1),
          ),
        );
        setState(() {});
      }
    } else {
      final item = BookmarkItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        url: url,
        title: title.isNotEmpty ? title : url,
        createdAt: DateTime.now(),
      );
      await _storage?.addBookmark(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已添加到书签收藏'),
            duration: Duration(seconds: 1),
          ),
        );
        setState(() {});
      }
    }
  }

  void _openHistoryBookmarksSheet({int initialTab = 0}) {
    if (_storage == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HistoryBookmarksSheet(
        storageService: _storage!,
        initialTabIndex: initialTab,
        onOpenUrl: (url) {
          _loadUrl(url);
        },
      ),
    );
  }

  void _showLinkContextMenu(String linkUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                linkUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('在新标签页中打开'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewTab(url: linkUrl, switchToTab: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tab_unselected_rounded),
              title: const Text('在后台打开新标签页'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewTab(url: linkUrl, switchToTab: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制链接地址'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: linkUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制链接地址')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImageContextMenu(String imageUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                imageUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.image_search_rounded),
              title: const Text('在新标签页中打开图片'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewTab(url: imageUrl, switchToTab: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制图片链接'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: imageUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制图片链接')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _copyCurrentUrl() {
    final url = _sharableUrl;
    if (url == null) return;
    HapticService.selection();
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制网页链接'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _shareCurrentUrl() async {
    final url = _sharableUrl;
    if (url == null) return;
    HapticService.selection();
    final ok = await ShareIntentService.instance.shareText(url);
    if (!ok && mounted) {
      // No native share on this platform; the clipboard is the fallback.
      Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前系统不支持分享，已复制链接'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _quickSummarize() async {
    if (_storage?.getPageSummaryEnabled() == false) {
      _showFeatureDisabled('页面总结已在设置 → 浏览与隐私保护中关闭');
      return;
    }
    if (_wrapper == null) return;

    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: '去配置',
            textColor: Colors.white,
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在提取网页正文...'),
        duration: Duration(milliseconds: 900),
      ),
    );

    final articleData = await _wrapper!.extractReadableContent();
    final title = articleData['title'] as String? ?? await _wrapper!.getTitle();
    final url = articleData['url'] as String? ?? await _wrapper!.getUrl();
    final content = articleData['content'] as String? ?? '';

    if (content.length < 30) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前页面正文内容过少，无法生成深度速读摘要'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SummaryBottomSheet(
          title: title,
          url: url,
          content: content,
          config: config,
        ),
      );
    }
  }

  void _checkSelectionAndTrigger() async {
    // Reading the selection is a page round trip; skip it entirely when the
    // feature is off, rather than fetching and discarding.
    if (_storage?.getSelectionMenuEnabled() == false) return;
    if (_wrapper == null) return;
    final selInfo = await _wrapper!.getSelectedTextInfo();
    if (selInfo['hasSelection'] == true) {
      final selectedText = selInfo['text'] as String? ?? '';
      if (selectedText.isNotEmpty) {
        final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => SelectionActionDialog(
              selectedText: selectedText,
              config: config,
            ),
          );
        }
      }
    }
  }

  void _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onSafeModeChanged: _setSafeMode,
        ),
      ),
    );
    if (!mounted) return;
    // Settings sub-pages persist immediately, so always re-apply them on return.
    _storage = await StorageService.getInstance();
    await _applyCurrentWebViewSettings();
    if (mounted) setState(() {});
  }
}
