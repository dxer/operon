part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// Addresses, page settings and the scripts injected into a document.

extension _NavigationActions on _BrowserPageState {
  void _loadUrl(String input) {
    String trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // Submitting an address is a moment the user wants to watch.
    _revealChrome();

    if (trimmed == 'operon://newtab' || trimmed == 'about:blank') {
      _goHome();
      return;
    }

    final bool hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final bool looksLikeDomain = !trimmed.contains(' ') &&
        (RegExp(r'^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?([/?#].*)?$')
                .hasMatch(trimmed) ||
            trimmed.startsWith('localhost') ||
            RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?$').hasMatch(trimmed));
    final bool isUrl = hasScheme || looksLikeDomain;

    if (isUrl) {
      if (!hasScheme) {
        trimmed = 'https://$trimmed';
      }
    } else {
      // Assemble search URL based on user's default search engine
      final engineName =
          _storage?.getSearchEngine() ?? AppConstants.defaultSearchEngine;
      final engineBase = AppConstants.searchEngines[engineName] ??
          AppConstants.searchEngines[AppConstants.defaultSearchEngine]!;
      trimmed = '$engineBase${Uri.encodeComponent(trimmed)}';
    }

    _currentTab.url = trimmed;
    _currentTab.title = '加载中...';
    _currentTab.errorMessage = null;
    _urlController.text = trimmed;
    _currentTab.controller
        ?.loadUrl(urlRequest: URLRequest(url: WebUri(trimmed)));
    setState(() {});
  }

  Future<void> _applyThemeToWebPage(InAppWebViewController controller) async {
    // Only nudge pages when the user asked for a dark web. Forcing
    // `color-scheme: light` would tell sites that support dark themes to stay
    // light, which is the opposite of leaving the page alone.
    final jsThemeSync = _webDarkEnabled
        ? '''
    (function() {
      try {
        let meta = document.querySelector('meta[name="color-scheme"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'color-scheme';
          // Tagged so turning the option off removes only our own meta.
          meta.dataset.operonTheme = '1';
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.content = 'dark';
        if (document.documentElement) {
          document.documentElement.style.colorScheme = 'dark';
        }
      } catch(e) {}
    })();
    '''
        : '''
    (function() {
      try {
        // Remove only what we added; a page's own declaration is left alone.
        const meta = document.querySelector('meta[name="color-scheme"]');
        if (meta && meta.dataset.operonTheme === '1') meta.remove();
        if (document.documentElement) {
          document.documentElement.style.removeProperty('color-scheme');
        }
      } catch(e) {}
    })();
    ''';

    try {
      await controller.evaluateJavascript(source: jsThemeSync);
    } catch (_) {}
  }

  Future<void> _applyCurrentWebViewSettings() async {
    if (_webViewController == null) return;

    final userAgent = _currentTab.isDesktopMode
        ? AppConstants.uaDesktopChrome
        : (_storage?.getUserAgent() ?? AppConstants.uaAndroidChrome);
    final isEffectivelyDark = _webDarkEnabled;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;

    await _webViewController!.setSettings(
      settings: InAppWebViewSettings(
        userAgent: userAgent,
        forceDark: isEffectivelyDark ? ForceDark.ON : ForceDark.OFF,
        algorithmicDarkeningAllowed: isEffectivelyDark,
        blockNetworkImage: blockImages,
        javaScriptEnabled: jsEnabled,
        textZoom: textZoom,
      ),
    );
    _applyThemeToWebPage(_webViewController!);
  }

  void _toggleDesktopMode() async {
    _currentTab.isDesktopMode = !_currentTab.isDesktopMode;
    await _applyCurrentWebViewSettings();
    _currentTab.controller?.reload();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_currentTab.isDesktopMode ? '已切换至电脑桌面版模式' : '已切换至移动手机版模式'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _toggleCleanMode() async {
    if (_storage?.getReadingModeEnabled() == false) {
      _showFeatureDisabled('纯净阅读已在设置 → 浏览与隐私保护中关闭');
      return;
    }
    _currentTab.isCleanMode = !_currentTab.isCleanMode;
    if (_wrapper != null) {
      final res = await _wrapper!.cleanPageMode();
      final count = res['removedCount'] ?? 0;
      final expCount = res['expandedCount'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentTab.isCleanMode
                  ? '纯净模式已开启：清理了 $count 处遮罩，展开 $expCount 处折叠正文'
                  : '已关闭纯净模式',
            ),
            backgroundColor: AppTheme.accent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    setState(() {});
  }

  void _injectMatchedUserScripts(String currentUrl) async {
    if (currentUrl.isEmpty ||
        currentUrl.startsWith('about:') ||
        _wrapper == null) {
      return;
    }
    try {
      final scriptService = await UserScriptService.getInstance();
      final scripts = scriptService.getScripts();
      int count = 0;
      for (final s in scripts) {
        if (s.matchesUrl(currentUrl)) {
          await _wrapper!.evaluateJavascript(s.code);
          count++;
        }
      }
      if (count > 0) {
        debugPrint(
            '[UserScript] Injected $count active user scripts into $currentUrl');
      }
    } catch (e) {
      debugPrint('[UserScript] Injection error: $e');
    }
  }

  void _openUserScripts() async {
    final currentUrl = await _wrapper?.getUrl() ?? _urlController.text;
    final currentTitle = await _wrapper?.getTitle() ?? '';
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserScriptsPage(
            currentUrl: currentUrl,
            currentTitle: currentTitle,
          ),
        ),
      );
    }
  }
}
