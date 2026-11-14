part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The WebView itself and the overlay that stands in when it fails.

extension _WebViewBuilders on _BrowserPageState {
  Widget _buildErrorOverlay(WebTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightCard;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppTheme.dangerOf(isDark),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '无法访问此页面',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tab.errorMessage ?? '网络连接失败，请检查网络连接或网址',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新加载'),
              onPressed: () {
                setState(() {
                  tab.errorMessage = null;
                  tab.isLoading = true;
                });
                tab.controller?.reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabWebView(WebTab tab, int tabIndex) {
    final isStartPage = tab.url == 'operon://newtab' ||
        tab.url == 'about:blank' ||
        tab.url.isEmpty;

    final userAgent = tab.isDesktopMode
        ? AppConstants.uaDesktopChrome
        : (_storage?.getUserAgent() ?? AppConstants.uaAndroidChrome);
    final isEffectivelyDark = _webDarkEnabled;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    tab.pullToRefresh ??= PullToRefreshController(
      settings: PullToRefreshSettings(
        enabled: true,
        color: AppTheme.primaryOf(isDarkMode),
        backgroundColor: isDarkMode ? AppTheme.darkBg : AppTheme.lightBg,
      ),
      onRefresh: () async {
        await tab.controller?.reload();
      },
    );

    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(tab.id),
          initialUrlRequest: URLRequest(
            url: WebUri(tab.url.startsWith('http') ? tab.url : 'about:blank'),
          ),
          pullToRefreshController: tab.pullToRefresh,
          initialSettings: InAppWebViewSettings(
            userAgent: userAgent,
            javaScriptEnabled: jsEnabled,
            domStorageEnabled: true,
            databaseEnabled: true,
            cacheEnabled: true,
            transparentBackground: false,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            supportZoom: true,
            builtInZoomControls: false,
            displayZoomControls: false,
            allowsInlineMediaPlayback: true,
            useHybridComposition: true,
            forceDark: isEffectivelyDark ? ForceDark.ON : ForceDark.OFF,
            algorithmicDarkeningAllowed: isEffectivelyDark,
            blockNetworkImage: blockImages,
            textZoom: textZoom,
            supportMultipleWindows: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useOnDownloadStart: true,
          ),
          onScrollChanged: (controller, x, y) {
            if (tabIndex == _currentTabIndex) _onPageScroll(y);
          },
          onWebViewCreated: (controller) {
            tab.controller = controller;
            tab.wrapper = WebViewControllerWrapper(controller);
            if (tabIndex == _currentTabIndex && mounted) {
              setState(() {});
            }
          },
          onCreateWindow: (controller, createWindowAction) async {
            final url = createWindowAction.request.url?.toString();
            if (url != null && url.isNotEmpty) {
              _createNewTab(url: url, switchToTab: true);
              return true;
            }
            return false;
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            final filename =
                downloadStartRequest.suggestedFilename ?? 'download';
            final url = downloadStartRequest.url.toString();
            final len = downloadStartRequest.contentLength;
            final sizeMb = len > 0
                ? ' (${(len / (1024 * 1024)).toStringAsFixed(1)} MB)'
                : '';

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('检测到文件下载: $filename$sizeMb'),
                  action: SnackBarAction(
                    label: '复制链接',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                    },
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          },
          onLoadStart: (controller, url) {
            setState(() {
              tab.isLoading = true;
              tab.progress = 0.1;
              tab.errorMessage = null;
            });
            // A new document is never something to read with the controls
            // hidden: the user needs to see where they landed.
            if (tabIndex == _currentTabIndex) {
              _chrome.reset();
              _revealChrome();
            }
            _applyThemeToWebPage(controller);
          },
          onLoadStop: (controller, url) async {
            tab.pullToRefresh?.endRefreshing();
            final title = await controller.getTitle() ?? tab.title;
            final urlStr = _normalizeUrl(url?.toString() ?? tab.url);
            final canBack = await controller.canGoBack();
            final canFwd = await controller.canGoForward();

            setState(() {
              tab.isLoading = false;
              tab.progress = 1.0;
              tab.title = title.isNotEmpty ? title : '新标签页';
              tab.url = urlStr;
              tab.canGoBack = canBack;
              tab.canGoForward = canFwd;
              if (tabIndex == _currentTabIndex) {
                _urlController.text =
                    urlStr.startsWith('operon://') ? '' : urlStr;
              }
            });

            // Auto-record history for valid web URLs
            if (urlStr.startsWith('http')) {
              _storage?.addHistoryItem(HistoryItem(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                url: urlStr,
                title: title.isNotEmpty ? title : urlStr,
                visitedAt: DateTime.now(),
              ));
            }

            _applyThemeToWebPage(controller);

            // Auto-inject agent script when page finishes loading
            if (tab.wrapper != null) {
              await tab.wrapper!.ensureScriptInjected();
              if (tab.isCleanMode && (_storage?.getReadingModeEnabled() ?? true)) {
                await tab.wrapper!.cleanPageMode();
              }
              _injectMatchedUserScripts(urlStr);
            }
          },
          onProgressChanged: (controller, progress) {
            setState(() {
              tab.progress = progress / 100.0;
              tab.isLoading = progress < 100;
            });
          },
          onTitleChanged: (controller, title) {
            if (title != null && title.isNotEmpty) {
              setState(() {
                tab.title = title;
              });
            }
          },
          onUpdateVisitedHistory: (controller, url, isReload) async {
            // Keep back/forward arrows and the address bar in sync with SPA
            // history changes that never trigger onLoadStop.
            if (url == null) return;
            final canBack = await controller.canGoBack();
            final canFwd = await controller.canGoForward();
            final urlStr = _normalizeUrl(url.toString());
            if (!mounted) return;
            setState(() {
              tab.url = urlStr;
              tab.canGoBack = canBack;
              tab.canGoForward = canFwd;
              if (tabIndex == _currentTabIndex) {
                _urlController.text =
                    tab.url.startsWith('operon://') ? '' : tab.url;
              }
            });
          },
          onLongPressHitTestResult: (controller, hitTestResult) {
            final type = hitTestResult.type;
            final extra = hitTestResult.extra;

            if ((type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
                    type ==
                        InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) &&
                extra != null &&
                extra.isNotEmpty) {
              _showLinkContextMenu(extra);
              return;
            }

            if (type == InAppWebViewHitTestResultType.IMAGE_TYPE &&
                extra != null &&
                extra.isNotEmpty) {
              _showImageContextMenu(extra);
              return;
            }

            Future.delayed(const Duration(milliseconds: 300), () {
              _checkSelectionAndTrigger();
            });
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) {
              tab.pullToRefresh?.endRefreshing();
              setState(() {
                tab.errorMessage = error.description;
                tab.isLoading = false;
              });
            }
          },
          onPermissionRequest: (controller, permissionRequest) async {
            final url = (await controller.getUrl())?.toString() ?? '';
            final host = Uri.tryParse(url)?.host ?? '当前网页';
            final kinds = permissionRequest.resources
                .map((r) => _permissionLabel(r.toString().split('.').last))
                .toSet()
                .join('、');
            final allowed = await _askWebPermission(
              '网页权限请求',
              '$host 请求使用：$kinds。\n\n仅在你信任该网站时允许。',
            );
            return PermissionResponse(
              resources: permissionRequest.resources,
              action: allowed
                  ? PermissionResponseAction.GRANT
                  : PermissionResponseAction.DENY,
            );
          },
          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            final allowed = await _askWebPermission(
              '定位权限请求',
              '${origin.isEmpty ? '当前网页' : origin} 请求获取你的位置信息。\n\n仅在你信任该网站时允许。',
            );
            return GeolocationPermissionShowPromptResponse(
              origin: origin,
              allow: allowed,
              retain: allowed,
            );
          },
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint('[WebView Console] ${consoleMessage.message}');
          },
        ),
        // Minimalist Native Start Page Overlay when tab is on operon://newtab
        if (isStartPage && _storage != null)
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: StartPageView(
              storageService: _storage!,
              onOpenUrl: _loadUrl,
              onOpenAgent: _openAgentBottomSheet,
              agentBusy: _agentState.isRunning,
            ),
          ),
        if (!isStartPage && tab.errorMessage != null) _buildErrorOverlay(tab),
        // Above the page, below the chrome: the gesture the layer is about to
        // dispatch, drawn by Flutter rather than injected into the document.
        if (tab.id == _currentTab.id && !isStartPage)
          GestureOverlay(pulse: _gesturePulse),
      ],
    );
  }
}
