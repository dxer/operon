part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The tab list and what happens when one opens, switches or closes.

extension _TabActions on _BrowserPageState {
  /// Opens a tab. Returns false when the strip is already at its cap.
  bool _createNewTab({
    String? url,
    bool switchToTab = true,
    bool isIncognito = false,
    int? windowId,
  }) {
    // A tab is a live WebView, not a row in a list. Past the cap the honest
    // move is to refuse and say so, not to let the phone decide which tab dies.
    if (_tabs.length >= AppConstants.maxTabs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '最多同时打开 ${AppConstants.maxTabs} 个标签页，先关掉一个再试',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final targetUrl = isIncognito && url == null
        ? AppConstants.defaultHomepage
        : (url ?? homepage);
    final isDesktop = _storage?.getDesktopMode() ?? false;

    final newTab = WebTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}_${_tabs.length}',
      url: targetUrl,
      title: isIncognito ? '无痕标签页' : '新标签页',
      isDesktopMode: isDesktop,
      isIncognito: isIncognito,
      windowId: windowId,
    );

    setState(() {
      _tabs.add(newTab);
      if (switchToTab) {
        _currentTabIndex = _tabs.length - 1;
        _urlController.text =
            targetUrl.startsWith('operon://') || targetUrl == 'about:blank'
                ? ''
                : targetUrl;
      }
    });
    _persistTabSession();
    return true;
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _closeFindInPage();
    _chrome.reset();
    _revealChrome();
    final agentActive =
        _agentState.isRunning || _agentState.status == AgentStatus.paused;
    WebTab? agentTab;
    for (final tab in _tabs) {
      if (tab.id == _agentTabId) {
        agentTab = tab;
        break;
      }
    }
    if (agentActive && agentTab != null && _tabs[index].id != _agentTabId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI 仍在「${agentTab.title}」上运行，切换标签不会中断任务'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    setState(() {
      _currentTabIndex = index;
      _urlController.text =
          _currentTab.url.startsWith('operon://') ? '' : _currentTab.url;
    });
    _persistTabSession();
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final rejection = _runCoordinator.closeTabRejection(_tabs[index].id);
    if (rejection != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(rejection)),
      );
      return;
    }
    if (index == _currentTabIndex) {
      _closeFindInPage();
    }
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        final homepage =
            _storage?.getHomepage() ?? AppConstants.defaultHomepage;
        _tabs.add(WebTab(
          id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
          url: homepage,
          title: '新标签页',
          isDesktopMode: _storage?.getDesktopMode() ?? false,
        ));
        _currentTabIndex = 0;
      } else if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _urlController.text =
          _currentTab.url.startsWith('operon://') ? '' : _currentTab.url;
    });
    _persistTabSession();
  }

  void _closeAllTabs() {
    if (_runCoordinator.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务运行中，请先停止后再关闭全部标签页')),
      );
      return;
    }
    _closeFindInPage();
    setState(() {
      _tabs.clear();
      final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
      _tabs.add(WebTab(
        id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
        url: homepage,
        title: '新标签页',
        isDesktopMode: _storage?.getDesktopMode() ?? false,
      ));
      _currentTabIndex = 0;
      _urlController.text = homepage.startsWith('operon://') ? '' : homepage;
    });
    _persistTabSession();
    Navigator.of(context).pop();
  }

  void _goHome({bool useConfiguredHomepage = false}) {
    if (useConfiguredHomepage) {
      final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
      if (homepage.startsWith('http://') || homepage.startsWith('https://')) {
        _loadUrl(homepage);
        return;
      }
    }
    _closeFindInPage();
    _chrome.reset();
    _revealChrome();
    _currentTab.controller?.stopLoading();
    _currentTab.controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    setState(() {
      _currentTab.url = 'operon://newtab';
      _currentTab.title = _currentTab.isIncognito ? '无痕标签页' : '新标签页';
      _currentTab.errorMessage = null;
      _currentTab.canGoBack = false;
      _currentTab.canGoForward = false;
      _currentTab.isLoading = false;
      _urlController.text = '';
    });
    _persistTabSession();
  }

  void _openTabOverview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) => TabsOverviewSheet(
          tabs: _tabs,
          activeIndex: _currentTabIndex,
          onSelectTab: _switchTab,
          onCloseTab: (idx) {
            _closeTab(idx);
            sheetSetState(() {});
          },
          onNewTab: () => _createNewTab(),
          onNewIncognitoTab: () => _createNewTab(isIncognito: true),
          onCloseAll: _closeAllTabs,
        ),
      ),
    );
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty || url == 'about:blank') return 'operon://newtab';
    return url;
  }
}
