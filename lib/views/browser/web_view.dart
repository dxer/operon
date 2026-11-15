part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The WebView itself and the overlay that stands in when it fails.

extension _WebViewBuilders on _BrowserPageState {
  /// Hands the page's icon to the icon cache, so the tab strip, history and
  /// start page can draw a real mark instead of a letter.
  Future<void> _cacheFavicon(
    InAppWebViewController controller,
    String url,
  ) async {
    final host = hostOf(url);
    if (host.isEmpty || FaviconService.cached(host) != null) return;
    try {
      final icons = await controller.getFavicons();
      if (icons.isEmpty) return;
      // The largest declaration wins; a 16px .ico upscaled looks like dirt.
      final best = icons.reduce(
        (a, b) => ((b.width ?? 0) > (a.width ?? 0)) ? b : a,
      );
      await FaviconService.loadFromUrl(host, best.url.toString());
    } catch (_) {
      // A missing icon is normal; the letter stands in.
    }
  }

  Widget _buildErrorOverlay(WebTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppInk.sunken(isDark),
                shape: BoxShape.circle,
                border: Border.all(color: AppInk.hairline(isDark)),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 34,
                color: AppTheme.dangerOf(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '无法访问此页面',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppInk.primary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tab.errorMessage ?? '网络连接失败，请检查网络连接或网址',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppInk.secondary(isDark),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _goHome,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppInk.secondary(isDark),
                    side: BorderSide(color: AppInk.hairline(isDark)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('返回首页'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryOf(isDark),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTabWebView(WebTab tab) {
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

    tab.findController ??= FindInteractionController(
      onFindResultReceived: (
        controller,
        activeMatchOrdinal,
        numberOfMatches,
        isDoneCounting,
      ) {
        if (!mounted || tab.id != _currentTab.id || !_isFindingInPage) {
          return;
        }
        setState(() {
          _findActiveMatch = activeMatchOrdinal;
          _findTotalMatches = numberOfMatches;
        });
      },
    );

    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(tab.id),
          windowId: tab.windowId,
          initialUrlRequest: tab.windowId != null
              ? null
              : URLRequest(
                  url: WebUri(
                    tab.url.startsWith('http') ? tab.url : 'about:blank',
                  ),
                ),
          pullToRefreshController: tab.pullToRefresh,
          findInteractionController: tab.findController,
          initialSettings: InAppWebViewSettings(
            userAgent: userAgent,
            javaScriptEnabled: jsEnabled,
            incognito: tab.isIncognito,
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
            if (mounted && tab.id == _currentTab.id) _onPageScroll(y);
          },
          onWebViewCreated: (controller) {
            tab.controller = controller;
            tab.wrapper = WebViewControllerWrapper(controller);
            if (mounted && tab.id == _currentTab.id) {
              setState(() {});
            }
          },
          onCreateWindow: (controller, createWindowAction) async {
            final url = createWindowAction.request.url?.toString();
            if (url != null && url.isNotEmpty) {
              _createNewTab(
                url: url,
                switchToTab: true,
                isIncognito: tab.isIncognito,
              );
              return true;
            }
            if (createWindowAction.windowId > 0) {
              _createNewTab(
                url: 'about:blank',
                switchToTab: true,
                isIncognito: tab.isIncognito,
                windowId: createWindowAction.windowId,
              );
              return true;
            }
            return false;
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            final filename = DownloadService.sanitizeFilename(
              downloadStartRequest.suggestedFilename,
              downloadStartRequest.url.toString(),
            );
            final url = downloadStartRequest.url.toString();
            final len = downloadStartRequest.contentLength;
            final sizeMb = len > 0
                ? ' (${(len / (1024 * 1024)).toStringAsFixed(1)} MB)'
                : '';

            String? cookieHeader;
            try {
              final cookies = await CookieManager.instance()
                  .getCookies(url: downloadStartRequest.url);
              if (cookies.isNotEmpty) {
                cookieHeader = cookies
                    .map((c) => '${c.name}=${c.value}')
                    .join('; ');
              }
            } catch (_) {}

            final ua = _storage?.getUserAgent();
            unawaited(DownloadService.instance.enqueue(
              url: url,
              suggestedFilename: filename,
              mimeType: downloadStartRequest.mimeType,
              userAgent: ua,
              cookieHeader: cookieHeader,
              contentLength: len,
              onFinished: (item) {
                if (!mounted) return;
                final msg = item.status == DownloadStatus.completed
                    ? '下载完成：${item.filename}'
                    : '下载失败：${item.filename}';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    action: SnackBarAction(
                      label: item.status == DownloadStatus.completed
                          ? '打开'
                          : '查看',
                      onPressed: () {
                        if (item.status == DownloadStatus.completed) {
                          DownloadService.instance.openFile(item);
                        } else {
                          _openDownloadsSheet();
                        }
                      },
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              },
            ));

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('开始下载：$filename$sizeMb'),
                  action: SnackBarAction(
                    label: '查看下载',
                    onPressed: _openDownloadsSheet,
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
          onLoadStart: (controller, url) {
            if (!mounted) return;
            setState(() {
              tab.isLoading = true;
              tab.progress = 0.1;
              tab.errorMessage = null;
            });
            // A new document is never something to read with the controls
            // hidden: the user needs to see where they landed.
            if (tab.id == _currentTab.id) {
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
            if (!mounted) return;

            setState(() {
              tab.isLoading = false;
              tab.progress = 1.0;
              tab.title = title.isNotEmpty ? title : '新标签页';
              tab.url = urlStr;
              tab.canGoBack = canBack;
              tab.canGoForward = canFwd;
              if (tab.id == _currentTab.id && !_addressFocused) {
                _urlController.text =
                    urlStr.startsWith('operon://') ? '' : urlStr;
              }
            });

            // The WebView has already downloaded the page's own icon, which is
            // more accurate than re-requesting /favicon.ico: it is the one the
            // site declared, and it works for sites behind a login.
            if (urlStr.startsWith('http')) _cacheFavicon(controller, urlStr);

            // Auto-record history for valid non-incognito web URLs
            if (!tab.isIncognito && urlStr.startsWith('http')) {
              _storage?.addHistoryItem(HistoryItem(
                id: '${DateTime.now().microsecondsSinceEpoch}',
                url: urlStr,
                title: title.isNotEmpty ? title : urlStr,
                visitedAt: DateTime.now(),
              ));
            }
            if (!tab.isIncognito) {
              _persistTabSession();
            }

            _applyThemeToWebPage(controller);

            // Auto-inject agent script when page finishes loading
            if (tab.wrapper != null) {
              await tab.wrapper!.ensureScriptInjected();
              if (!mounted) return;
              if (tab.isCleanMode && (_storage?.getReadingModeEnabled() ?? true)) {
                await tab.wrapper!.cleanPageMode();
              }
            }
          },
          onProgressChanged: (controller, progress) {
            if (!mounted) return;
            setState(() {
              tab.progress = progress / 100.0;
              tab.isLoading = progress < 100;
            });
          },
          onTitleChanged: (controller, title) {
            if (!mounted) return;
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
              if (tab.id == _currentTab.id && !_addressFocused) {
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
              if (mounted) _checkSelectionAndTrigger();
            });
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) {
              tab.pullToRefresh?.endRefreshing();
              if (!mounted) return;
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
          onReceivedServerTrustAuthRequest: (controller, challenge) async {
            final host = challenge.protectionSpace.host;
            if (host.isNotEmpty && _trustedSslHosts.contains(host)) {
              return ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.PROCEED,
              );
            }
            final displayHost = host.isEmpty ? '当前站点' : host;
            final allowed = await _askWebPermission(
              '安全证书异常',
              '「$displayHost」的 HTTPS 安全证书不受信任或已过期，继续访问可能存在信息泄露风险。\n\n除非你明确信任该站点，否则建议取消。',
            );
            if (allowed && host.isNotEmpty) {
              _trustedSslHosts.add(host);
            }
            return ServerTrustAuthResponse(
              action: allowed
                  ? ServerTrustAuthResponseAction.PROCEED
                  : ServerTrustAuthResponseAction.CANCEL,
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
