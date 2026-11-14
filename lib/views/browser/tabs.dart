part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// The tab list and what happens when one opens, switches or closes.

extension _TabActions on _BrowserPageState {
  void _createNewTab({String? url, bool switchToTab = true}) {
    final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final targetUrl = url ?? homepage;
    final isDesktop = _storage?.getDesktopMode() ?? false;

    final newTab = WebTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}_${_tabs.length}',
      url: targetUrl,
      title: '新标签页',
      isDesktopMode: isDesktop,
    );

    setState(() {
      _tabs.add(newTab);
      if (switchToTab) {
        _currentTabIndex = _tabs.length - 1;
        _urlController.text =
            targetUrl.startsWith('operon://') ? '' : targetUrl;
      }
    });
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
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
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        final homepage =
            _storage?.getHomepage() ?? AppConstants.defaultHomepage;
        _tabs.add(WebTab(
          id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
          url: homepage,
          title: '新标签页',
        ));
        _currentTabIndex = 0;
      } else if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _urlController.text =
          _currentTab.url.startsWith('operon://') ? '' : _currentTab.url;
    });
  }

  void _closeAllTabs() {
    if (_runCoordinator.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务运行中，请先停止后再关闭全部标签页')),
      );
      return;
    }
    setState(() {
      _tabs.clear();
      final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
      _tabs.add(WebTab(
        id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
        url: homepage,
        title: '新标签页',
      ));
      _currentTabIndex = 0;
      _urlController.text = homepage.startsWith('operon://') ? '' : homepage;
    });
    Navigator.of(context).pop();
  }

  void _goHome() {
    _chrome.reset();
    _revealChrome();
    _currentTab.controller?.stopLoading();
    _currentTab.controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    setState(() {
      _currentTab.url = 'operon://newtab';
      _currentTab.title = '新标签页';
      _currentTab.errorMessage = null;
      _currentTab.canGoBack = false;
      _currentTab.canGoForward = false;
      _currentTab.isLoading = false;
      _urlController.text = '';
    });
  }

  void _openTabOverview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TabsOverviewSheet(
        tabs: _tabs,
        activeIndex: _currentTabIndex,
        onSelectTab: _switchTab,
        onCloseTab: (idx) {
          _closeTab(idx);
          if (mounted) setState(() {});
        },
        onNewTab: () => _createNewTab(),
        onCloseAll: _closeAllTabs,
      ),
    );
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty || url == 'about:blank') return 'operon://newtab';
    return url;
  }
}
