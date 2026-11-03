import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../models/agent_state.dart';
import '../models/agent_task_record.dart';
import '../models/llm_config.dart';
import '../models/macro_workflow.dart';
import '../models/skill.dart';
import '../models/skill_run.dart';
import '../models/web_tab.dart';
import '../models/bookmark_item.dart';
import '../models/history_item.dart';
import '../services/agent_runner.dart';
import '../services/execution_guard.dart';
import '../services/macro_service.dart';
import '../services/notification_service.dart';
import '../services/share_intent_service.dart';
import '../services/skill_repair_service.dart';
import '../services/skill_runner.dart';
import '../services/skill_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/user_script_service.dart';
import '../services/webview_controller_wrapper.dart';
import '../utils/cancellation.dart';
import '../utils/skill_template.dart';
import '../utils/url_utils.dart';
import 'settings/settings_page.dart';
import 'settings/skill_editor_page.dart';
import 'settings/skills_page.dart';
import 'settings/user_scripts_page.dart';
import 'widgets/agent_bottom_sheet.dart';
import 'widgets/agent_confirmation_card.dart';
import 'widgets/agent_status_bar.dart';
import 'widgets/browser_controls.dart';
import 'widgets/floating_agent_ball.dart';
import 'widgets/selection_action_dialog.dart';
import 'widgets/skill_run_sheet.dart';
import 'widgets/skill_run_timeline.dart';
import 'widgets/summary_bottom_sheet.dart';
import 'widgets/tabs_overview_sheet.dart';
import 'widgets/history_bookmarks_sheet.dart';
import 'widgets/start_page_view.dart';
import 'widgets/bottom_toolbar.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late AgentRunner _agentRunner;
  StorageService? _storage;
  ThemeService? _themeService;
  StreamSubscription<AgentState>? _agentSub;

  final TextEditingController _urlController = TextEditingController();

  // Multi-Tab State
  final List<WebTab> _tabs = [];
  int _currentTabIndex = 0;

  WebTab get _currentTab {
    final index = _currentTabIndex.clamp(0, _tabs.length - 1);
    return _tabs[index];
  }

  ThemeMode get _themeMode => _themeService?.themeMode ?? ThemeMode.system;

  InAppWebViewController? get _webViewController => _currentTab.controller;
  WebViewControllerWrapper? get _wrapper => _currentTab.wrapper;
  bool get _canGoBack => _currentTab.canGoBack;
  bool get _canGoForward => _currentTab.canGoForward;
  bool get _isLoading => _currentTab.isLoading;
  double get _progress => _currentTab.progress;
  bool get _isDesktopMode => _currentTab.isDesktopMode;
  bool get _isCleanMode => _currentTab.isCleanMode;

  AgentState _agentState = const AgentState();
  List<Skill> _skills = const [];
  bool _statusBarDismissed = false;
  bool _captchaCheckBusy = false;
  String? _agentTabId;
  DateTime? _taskStartedAt;
  bool _taskRecorded = false;
  bool _permissionDialogOpen = false;
  bool _agentSheetOpen = false;
  bool _confirmationCardOpen = false;
  String? _confirmationShownFor;
  StreamSubscription<String>? _shareSub;

  bool get _showAgentStatusBar {
    final status = _agentState.status;
    if (status == AgentStatus.idle) return false;
    if (status == AgentStatus.completed ||
        status == AgentStatus.maxStepsReached ||
        status == AgentStatus.error) {
      return !_statusBarDismissed;
    }
    return true;
  }

  bool get _showFloatingAgentBall {
    final status = _agentState.status;
    if (status == AgentStatus.idle) return true;
    // Re-appear once the user dismisses the finished-task status strip.
    final isTerminal = status == AgentStatus.completed ||
        status == AgentStatus.maxStepsReached ||
        status == AgentStatus.error;
    return isTerminal && _statusBarDismissed;
  }

  @override
  void initState() {
    super.initState();
    // Seed the first tab synchronously so build() never mutates state.
    _tabs.add(WebTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      url: AppConstants.defaultHomepage,
      title: '新标签页',
    ));
    _agentRunner = AgentRunner();
    _agentSub = _agentRunner.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state.isRunning || state.status == AgentStatus.paused) {
          _statusBarDismissed = false;
        }
        if (state.status == AgentStatus.idle ||
            state.status == AgentStatus.completed ||
            state.status == AgentStatus.maxStepsReached ||
            state.status == AgentStatus.error) {
          _agentTabId = null;
        }
        _agentState = state;
        final isTerminal = state.status == AgentStatus.completed ||
            state.status == AgentStatus.maxStepsReached ||
            state.status == AgentStatus.error;
        final shouldRecord = isTerminal ||
            (state.status == AgentStatus.idle && _taskStartedAt != null);
        if (shouldRecord && !_taskRecorded && state.goal.isNotEmpty) {
          _taskRecorded = true;
          unawaited(_persistTaskRecord(state));
        }
        if (state.status == AgentStatus.idle) {
          _taskStartedAt = null;
        }
      });
      if (state.status == AgentStatus.waitingConfirmation) {
        _maybeShowConfirmationCard(state);
      } else {
        _confirmationShownFor = null;
      }
    });
    NotificationService.getInstance().init();

    // Links shared into the app open as a tab instead of interrupting the
    // current page, so the note the user was reading stays put.
    ShareIntentService.instance.init();
    _shareSub = ShareIntentService.instance.links.listen(_openSharedLink);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntentService.instance.takeInitialLink();
      if (initial != null && mounted) _openSharedLink(initial);
    });

    _initStorage();
  }

  /// Shared text is usually `标题 https://…`; only the first link is opened.
  void _openSharedLink(String raw) {
    final url = extractSharedUrl(raw);
    if (url == null) return;
    final tab = _currentTab;
    final onStartPage = tab.url == 'operon://newtab' ||
        tab.url == 'about:blank' ||
        tab.url.isEmpty;
    if (onStartPage) {
      _loadUrl(url);
    } else {
      _createNewTab(url: url);
    }
  }

  Future<void> _loadSkills() async {
    final service = await SkillService.getInstance();
    if (!mounted) return;
    setState(() => _skills = service.getSkills());
  }

  Future<void> _openSkills() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkillsPage(
          config: _storage?.getLlmConfig() ?? LlmConfig.defaultConfig(),
          webView: _wrapper,
          onRun: (request) async {
            Navigator.of(context).pop();
            await _runSkill(request);
          },
        ),
      ),
    );
    if (!mounted) return;
    await _loadSkills();
  }

  Future<void> _initStorage() async {
    _storage = await StorageService.getInstance();
    _themeService = await ThemeService.getInstance();
    await _loadSkills();
    // Keep the runner aligned with the persisted policy from the very first run.
    _agentRunner.setSafeMode(_storage?.getSafeMode() ?? true);
    final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final isDesktop = _storage?.getDesktopMode() ?? false;

    // The seed tab has not navigated yet: apply the user's saved homepage once.
    if (_tabs.length == 1 && _tabs.first.url == AppConstants.defaultHomepage) {
      final tab = _tabs.first;
      final homepageChanged = tab.url != homepage;
      tab.url = homepage;
      tab.isDesktopMode = isDesktop;
      _urlController.text = homepage.startsWith('operon://') ? '' : homepage;

      if (homepageChanged &&
          tab.controller != null &&
          homepage.startsWith('http')) {
        await tab.controller!.loadUrl(
          urlRequest: URLRequest(url: WebUri(homepage)),
        );
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _agentSub?.cancel();
    _shareSub?.cancel();
    _agentRunner.dispose();
    _urlController.dispose();
    super.dispose();
  }

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

  void _loadUrl(String input) {
    String trimmed = input.trim();
    if (trimmed.isEmpty) return;

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
    final webDarkMode = _storage?.getWebDarkMode() ?? false;
    final isSystemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final isDark = webDarkMode ||
        (_themeMode == ThemeMode.dark) ||
        (_themeMode == ThemeMode.system && isSystemDark);

    // Nudge pages that declare `color-scheme` support. We deliberately avoid
    // overriding window.matchMedia(), which breaks sites that genuinely react
    // to prefers-color-scheme.
    final jsThemeSync = '''
    (function() {
      try {
        const mode = '${isDark ? 'dark' : 'light'}';
        let meta = document.querySelector('meta[name="color-scheme"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'color-scheme';
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.content = mode;
        if (document.documentElement) {
          document.documentElement.style.colorScheme = mode;
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
    final webDarkMode = _storage?.getWebDarkMode() ?? false;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;

    final isSystemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final isEffectivelyDark = webDarkMode ||
        (_themeMode == ThemeMode.dark) ||
        (_themeMode == ThemeMode.system && isSystemDark);

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
                style: const TextStyle(fontSize: 12, color: AppTheme.neutral),
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
                style: const TextStyle(fontSize: 12, color: AppTheme.neutral),
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

  void _quickSummarize() async {
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

  void _startAgentTask(
    String goal, {
    SkillPolicy? policy,
  }) async {
    if (_wrapper == null) return;
    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: '去设置',
            textColor: Colors.white,
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }

    final maxSteps = policy?.maxSteps ?? _storage?.getMaxSteps() ?? 15;
    final safeMode = _storage?.getSafeMode() ?? true;

    _agentTabId = _currentTab.id;
    _statusBarDismissed = false;
    _taskStartedAt = DateTime.now();
    _taskRecorded = false;

    _agentRunner.run(
      userGoal: goal,
      webView: _wrapper!,
      config: config,
      maxSteps: maxSteps,
      safeMode: safeMode,
      isSiteAllowed: (host) => _storage?.isAgentSiteAllowed(host) ?? false,
      policy: policy,
    );
  }

  Future<void> _runSkill(SkillRunRequest request) async {
    final wrapper = _wrapper;
    if (wrapper == null) return;
    if (!request.execute) {
      final prompt = SkillTemplate.renderString(
        request.skill.instructions,
        {'inputs': request.values},
        strict: false,
      );
      _startAgentTask(
        prompt,
        policy: request.skill.policy,
      );
      return;
    }
    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: '去设置',
            textColor: Colors.white,
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SkillRunHost(
        request: request,
        webView: wrapper,
        config: config,
        safeMode: _storage?.getSafeMode() ?? true,
        onConfirm: _confirmSkillAction,
      ),
    );
    if (mounted) await _loadSkills();
  }

  Future<bool> _confirmSkillAction(ConfirmationRequest request) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(request.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(request.reason, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 10),
              Text(
                '目标：${request.target}',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              if (request.payload != null &&
                  request.payload!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.payload!,
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
              if (request.url != null && request.url!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  request.url!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('允许执行'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _setSafeMode(bool enabled) async {
    await _storage?.saveSafeMode(enabled);
    // AgentRunner also releases a pending confirmation immediately when the
    // switch is turned off mid-task.
    _agentRunner.setSafeMode(enabled);
    if (mounted) setState(() {});
  }

  Future<bool> _askWebPermission(String title, String detail) async {
    if (!mounted || _permissionDialogOpen) return false;
    _permissionDialogOpen = true;
    try {
      final allowed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(detail, style: const TextStyle(height: 1.45)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许'),
            ),
          ],
        ),
      );
      return allowed == true;
    } finally {
      _permissionDialogOpen = false;
    }
  }

  String _permissionLabel(String name) {
    switch (name) {
      case 'CAMERA':
        return '摄像头';
      case 'MICROPHONE':
        return '麦克风';
      case 'CAMERA_AND_MICROPHONE':
        return '摄像头与麦克风';
      case 'DEVICE_ORIENTATION_AND_MOTION':
        return '设备方向与运动';
      case 'PROTECTED_MEDIA_ID':
        return '受保护媒体';
      case 'MIDI_SYSEX':
        return 'MIDI 设备';
      case 'GEOLOCATION':
        return '定位';
      default:
        return name;
    }
  }

  Future<void> _persistTaskRecord(AgentState state) async {
    final storage = _storage;
    if (storage == null) return;
    final startedAt = _taskStartedAt ??
        (state.logs.isNotEmpty ? state.logs.first.timestamp : DateTime.now());
    final lines = state.logs.map((log) {
      final detail =
          log.detail == null || log.detail!.isEmpty ? '' : ' — ${log.detail}';
      final line = '[${log.step}] ${log.title}$detail';
      return line.length > 300 ? '${line.substring(0, 300)}…' : line;
    }).toList();
    if (lines.length > 80) {
      lines.removeRange(0, lines.length - 80);
    }
    final sensitive = state.logs
        .where((log) =>
            log.title.contains('敏感操作') ||
            log.title.contains('完全自主模式') ||
            log.title.contains('信任列表') ||
            log.title.contains('取消'))
        .map((log) => log.detail == null || log.detail!.isEmpty
            ? log.title
            : '${log.title} — ${log.detail}')
        .toList();

    final record = AgentTaskRecord(
      id: startedAt.millisecondsSinceEpoch.toString(),
      goal: state.goal,
      status: state.status == AgentStatus.idle ? 'stopped' : state.status.name,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      steps: state.currentStep,
      maxSteps: state.maxSteps,
      safeMode: storage.getSafeMode(),
      errorMessage: state.errorMessage,
      targetUrl: _currentTab.url,
      logs: lines,
      sensitiveActions: sensitive,
      recordedMacroSteps: state.recordedMacroSteps,
    );
    try {
      await storage.addAgentTaskRecord(record);
    } catch (_) {
      // History is best-effort; never let persistence break the task flow.
    }
  }

  Future<void> _allowSiteForTask() async {
    final url = _agentState.targetUrl ?? _currentTab.url;
    var host = Uri.tryParse(url)?.host ?? '';
    host = host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    if (host.isEmpty) {
      _agentRunner.confirmAction(true);
      return;
    }
    await _storage?.addAgentAllowedSite(host);
    _agentRunner.confirmAction(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将 $host 加入信任列表，之后该站点不再询问'),
          backgroundColor: AppTheme.accent,
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  void _runMacro(MacroWorkflow macro) async {
    if (_wrapper == null) return;

    final macroService = await MacroService.getInstance();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在重放宏任务: ${macro.title}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    final success = await macroService.executeMacro(
      macro: macro,
      webView: _wrapper!,
      onProgress: (cur, total, desc) {
        debugPrint('[Macro Progress] Step $cur/$total: $desc');
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '宏任务 [${macro.title}] 执行完成！'
              : '宏任务 [${macro.title}] 执行中断：有步骤未成功。涉及发帖/支付等步骤时不会自动重试，请检查页面。',
        ),
        backgroundColor: success ? AppTheme.accent : AppTheme.danger,
        duration: Duration(seconds: success ? 3 : 6),
      ),
    );
  }

  Future<void> _pickLocator() async {
    final wrapper = _wrapper;
    if (wrapper == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('拾取模式：点击页面元素，按 Esc 取消'),
        duration: Duration(seconds: 2),
      ),
    );
    final result = await wrapper.pickLocator();
    if (!mounted) return;
    if (result['ok'] != true) {
      final error = result['error']?.toString() ?? '无法拾取定位器';
      final message = error.contains('TIMEOUT')
          ? '拾取超时，请重试'
          : (error.contains('CANCELLED') ? '已取消拾取' : error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    final locator = result['locator'];
    if (locator is! Map) return;
    final pretty = const JsonEncoder.withIndent('  ').convert(locator);
    await Clipboard.setData(ClipboardData(text: pretty));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('定位器已复制'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '目标：${result['label'] ?? result['tag'] ?? ''}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  pretty,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '匹配 ${result['count'] ?? 0} 个元素。打开「技能 → 编辑步骤 → 粘贴定位器」即可填入。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pretty));
              Navigator.of(ctx).pop();
            },
            child: const Text('再次复制'),
          ),
        ],
      ),
    );
  }

  void _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onRunMacro: _runMacro,
          onSafeModeChanged: _setSafeMode,
        ),
      ),
    );
    if (!mounted) return;
    // Settings sub-pages persist immediately, so always re-apply them on return.
    _storage = await StorageService.getInstance();
    _agentRunner.setSafeMode(_storage?.getSafeMode() ?? true);
    await _applyCurrentWebViewSettings();
    await _loadSkills();
    if (mounted) setState(() {});
  }

  /// Confirms a CAPTCHA only after re-checking the page.
  ///
  /// Tapping "done" before the challenge is actually solved would otherwise
  /// resume the agent into the same blocked page.
  Future<void> _confirmCaptchaSolved() async {
    if (_captchaCheckBusy) return;
    final wrapper = _wrapper;
    if (wrapper == null) {
      _agentRunner.confirmCaptchaSolved(true);
      return;
    }
    _captchaCheckBusy = true;
    try {
      final snapshot = await wrapper.extractPrunedDOM(
        showBadges: false,
        includeContent: false,
      );
      if (snapshot.hasCaptcha) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('仍未检测到验证通过，请先在网页上完成验证')),
          );
        }
        return;
      }
      _agentRunner.confirmCaptchaSolved(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂时无法确认验证状态，请稍后重试')),
        );
      }
    } finally {
      _captchaCheckBusy = false;
    }
  }

  String _confirmationToken(AgentState state) {
    return '${state.currentStep}|${state.currentAction?.elementId ?? ''}|'
        '${state.confirmationPayload ?? ''}';
  }

  /// Pops the dedicated authorization card as soon as a task stops on a
  /// sensitive action, so the user never has to hunt for the panel. Once per
  /// pending action: dismissing it leaves the status strip's "审阅" button.
  void _maybeShowConfirmationCard(AgentState state) {
    if (_agentSheetOpen || _confirmationCardOpen) return;
    final token = _confirmationToken(state);
    if (_confirmationShownFor == token) return;
    _confirmationShownFor = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_agentSheetOpen) _showConfirmationCard();
    });
  }

  Future<void> _showConfirmationCard() async {
    if (_confirmationCardOpen || !mounted) return;
    _confirmationCardOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return StreamBuilder<AgentState>(
            stream: _agentRunner.stateStream,
            initialData: _agentState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? _agentState;
              if (state.status != AgentStatus.waitingConfirmation) {
                // The action was approved or the task stopped elsewhere.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted) Navigator.of(ctx).maybePop();
                });
                return const SizedBox.shrink();
              }
              return AgentConfirmationSheet(
                state: state,
                onConfirm: () {
                  Navigator.of(ctx).pop();
                  _agentRunner.confirmAction(true);
                },
                onCancel: () {
                  Navigator.of(ctx).pop();
                  _agentRunner.confirmAction(false);
                },
                onAllowSite: _allowSiteForTask,
              );
            },
          );
        },
      );
    } finally {
      _confirmationCardOpen = false;
    }
  }

  Future<void> _openAgentBottomSheet() async {
    await _loadSkills();
    if (!mounted || _agentSheetOpen) return;
    _agentSheetOpen = true;
    try {
      await _showAgentSheet();
    } finally {
      _agentSheetOpen = false;
    }
  }

  Future<void> _showAgentSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StreamBuilder<AgentState>(
          stream: _agentRunner.stateStream,
          initialData: _agentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? _agentState;
            return AgentBottomSheet(
              state: state,
              currentUrl: _currentTab.url,
              taskStartedAt: _taskStartedAt,
              safeMode: _storage?.getSafeMode() ?? true,
              onSafeModeChanged: _setSafeMode,
              onAllowSite: _allowSiteForTask,
              skills: _skills,
              onManageSkills: _openSkills,
              onRunSkill: _runSkill,
              webView: _wrapper,
              onStart: (goal, policy) {
                _startAgentTask(goal, policy: policy);
                Navigator.of(ctx).pop();
              },
              onPause: () => _agentRunner.pause(),
              onResume: () => _agentRunner.resume(),
              onStop: () => _agentRunner.stop(),
              onConfirmAction: (confirmed) =>
                  _agentRunner.confirmAction(confirmed),
              onConfirmCaptcha: (passed) {
                if (passed) {
                  _confirmCaptchaSolved();
                } else {
                  _agentRunner.confirmCaptchaSolved(false);
                }
              },
              onRunMacro: (macro) {
                _runMacro(macro);
                Navigator.of(ctx).pop();
              },
            );
          },
        );
      },
    );
  }

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
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppTheme.danger,
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
    final webDarkMode = _storage?.getWebDarkMode() ?? false;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;

    final isSystemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final isEffectivelyDark = webDarkMode ||
        (_themeMode == ThemeMode.dark) ||
        (_themeMode == ThemeMode.system && isSystemDark);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    tab.pullToRefresh ??= PullToRefreshController(
      settings: PullToRefreshSettings(
        enabled: true,
        color: AppTheme.primary,
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
              if (tab.isCleanMode) {
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
            ),
          ),
        if (!isStartPage && tab.errorMessage != null) _buildErrorOverlay(tab),
      ],
    );
  }

  void _onUserTouchedWebView(PointerDownEvent event) {
    if (_agentState.isRunning &&
        (_agentState.status == AgentStatus.executing ||
            _agentState.status == AgentStatus.observing ||
            _agentState.status == AgentStatus.thinking)) {
      _agentRunner.pause();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('检测到触屏操作，已暂停自动化任务'),
          duration: Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStartPage = _currentTab.url == 'operon://newtab' ||
        _currentTab.url == 'about:blank' ||
        _currentTab.url.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!isStartPage) {
          if (_webViewController != null &&
              await _webViewController!.canGoBack()) {
            await _webViewController!.goBack();
            return;
          } else {
            _goHome();
            return;
          }
        } else if (_tabs.length > 1) {
          _closeTab(_currentTabIndex);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                // Top Navigation & Wide Address Bar (shown on web pages)
                if (!isStartPage)
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.25,
                    child: BrowserControls(
                      urlController: _urlController,
                      isLoading: _isLoading,
                      progress: _progress,
                      onSubmitUrl: _loadUrl,
                      onSummarize: _quickSummarize,
                    ),
                  ),

                // Full-screen IndexedStack Multi-Tab WebView Canvas with Touch-To-Interrupt
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _onUserTouchedWebView,
                    child: IndexedStack(
                      index: _currentTabIndex,
                      children: _tabs.asMap().entries.map((entry) {
                        return _buildTabWebView(entry.value, entry.key);
                      }).toList(),
                    ),
                  ),
                ),

                // Docked agent status strip: takes layout space instead of floating
                // over the page, so it can never cover web content.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _showAgentStatusBar
                      ? MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.2,
                          child: AgentStatusBar(
                            state: _agentState,
                            safeMode: _storage?.getSafeMode() ?? true,
                            startedAt: _taskStartedAt,
                            onOpen: _openAgentBottomSheet,
                            onPause: () => _agentRunner.pause(),
                            onResume: () => _agentRunner.resume(),
                            onStop: () => _agentRunner.stop(),
                            onConfirmCaptcha: _confirmCaptchaSolved,
                            // "审阅" opens the dedicated authorization card,
                            // which shows the exact text and target site.
                            onConfirmAction: _showConfirmationCard,
                            onDismiss: () =>
                                setState(() => _statusBarDismissed = true),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),

                // Via-Style One-Handed Bottom Toolbar
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.25,
                  child: BottomToolbar(
                    canGoBack: _canGoBack && !isStartPage,
                    canGoForward: _canGoForward && !isStartPage,
                    isLoading: _isLoading,
                    tabCount: _tabs.length,
                    isBookmarked:
                        _storage?.isBookmarked(_currentTab.url) ?? false,
                    isDesktopMode: _isDesktopMode,
                    isCleanMode: _isCleanMode,
                    onBack: () => _webViewController?.goBack(),
                    onForward: () => _webViewController?.goForward(),
                    onHome: _goHome,
                    onOpenTabs: _openTabOverview,
                    onReload: () => _webViewController?.reload(),
                    onStopLoad: () => _webViewController?.stopLoading(),
                    onNewTab: () => _createNewTab(),
                    onSummarize: _quickSummarize,
                    onCleanPage: _toggleCleanMode,
                    onOpenUserScripts: _openUserScripts,
                    onToggleBookmark: _toggleBookmarkCurrentPage,
                    onOpenHistory: () =>
                        _openHistoryBookmarksSheet(initialTab: 0),
                    onOpenBookmarks: () =>
                        _openHistoryBookmarksSheet(initialTab: 1),
                    onToggleDesktopMode: _toggleDesktopMode,
                    onOpenSettings: _openSettings,
                    onPickLocator: _pickLocator,
                    currentUrl: _currentTab.url,
                  ),
                ),
              ],
            ),

            // Self-snapping AI orb: shown only when no task needs the docked
            // status strip, so it never competes with page content.
            if (_showFloatingAgentBall)
              FloatingAgentBall(
                state: _agentState,
                onTap: _openAgentBottomSheet,
                onQuickSummarize: _quickSummarize,
              ),
          ],
        ),
      ),
    );
  }
}

class _SkillRunHost extends StatefulWidget {
  final SkillRunRequest request;
  final WebViewControllerWrapper webView;
  final LlmConfig config;
  final bool safeMode;
  final Future<bool> Function(ConfirmationRequest request) onConfirm;

  const _SkillRunHost({
    required this.request,
    required this.webView,
    required this.config,
    required this.safeMode,
    required this.onConfirm,
  });

  @override
  State<_SkillRunHost> createState() => _SkillRunHostState();
}

class _SkillRunHostState extends State<_SkillRunHost> {
  late SkillRunState _state;
  late Skill _skill;
  CancellationToken _token = CancellationToken();
  String? _shown;
  bool _running = false;
  bool _repairing = false;

  @override
  void initState() {
    super.initState();
    _skill = widget.request.skill;
    _state = _initialState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  SkillRunState _initialState() {
    return SkillRunState(
      runId: DateTime.now().millisecondsSinceEpoch.toString(),
      skillId: _skill.id,
      skillName: _skill.name,
      status: SkillRunStatus.running,
      totalSteps: _skill.steps.where((step) => step.enabled).length,
    );
  }

  Future<void> _start() async {
    if (_running || !mounted) return;
    final token = CancellationToken();
    final guard = ExecutionGuard(
      safeMode: widget.safeMode,
      onConfirm: widget.onConfirm,
    );
    setState(() {
      _running = true;
      _token = token;
      _state = _initialState();
    });

    final runner = SkillRunner();
    final record = await runner.run(
      skill: _skill,
      inputs: widget.request.values,
      webView: widget.webView,
      config: widget.config,
      guard: guard,
      token: token,
      dryRun: widget.request.dryRun,
      onState: (state) {
        if (mounted) setState(() => _state = state);
      },
      onShow: (title, markdown) async {
        if (mounted) setState(() => _shown = markdown);
      },
    );
    if (!mounted) return;
    setState(() => _running = false);
    final stored = _shown == null
        ? record
        : record.copyWith(output: {...record.output, 'result': _shown!});
    final storage = await StorageService.getInstance();
    await storage.addSkillRun(stored);
  }

  SkillStepResult? _repairTarget() {
    for (final result in _state.results) {
      if (result.status != SkillStepStatus.failed) continue;
      final step = _skill.stepById(result.stepId);
      if (step != null && SkillRepairService.canRepair(step)) return result;
    }
    return null;
  }

  Future<void> _repair() async {
    final target = _repairTarget();
    if (target == null || _repairing) return;
    setState(() => _repairing = true);
    final service = SkillRepairService();
    try {
      final result = await service.repairLocator(
        skill: _skill,
        failedStep: target,
        webView: widget.webView,
        config: widget.config,
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有生成可用的候选定位器，请手动编辑技能')),
        );
        return;
      }
      final saved = await Navigator.of(context).push<Skill>(
        MaterialPageRoute(
          builder: (_) => SkillEditPage(skill: result.skill),
        ),
      );
      if (saved != null && mounted) {
        setState(() => _skill = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.verified
                  ? '定位器已修复并保存，可以再运行一次'
                  : '已保存候选定位器（当前页面未验证通过），请检查后重试',
            ),
            backgroundColor:
                result.verified ? AppTheme.accent : AppTheme.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('修复失败：$e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRepair = !_running &&
        _state.status == SkillRunStatus.failed &&
        _repairTarget() != null;
    return SkillRunTimeline(
      state: _state,
      shownMarkdown: _shown,
      onCancel: _running ? _token.cancel : null,
      onClose: _running ? null : () => Navigator.of(context).pop(),
      onRetry: !_running &&
              (_state.status == SkillRunStatus.failed ||
                  _state.status == SkillRunStatus.cancelled)
          ? _start
          : null,
      onRepair: canRepair && !_repairing ? _repair : null,
    );
  }
}
