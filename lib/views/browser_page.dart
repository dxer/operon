import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/macro_workflow.dart';
import '../models/web_tab.dart';
import '../services/agent_runner.dart';
import '../services/macro_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/user_script_service.dart';
import '../services/webview_controller_wrapper.dart';
import 'settings/settings_page.dart';
import 'settings/user_scripts_page.dart';
import 'widgets/agent_bottom_sheet.dart';
import 'widgets/browser_controls.dart';
import 'widgets/floating_agent_ball.dart';
import 'widgets/selection_action_dialog.dart';
import 'widgets/summary_bottom_sheet.dart';
import 'widgets/tabs_overview_sheet.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({Key? key}) : super(key: key);

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late AgentRunner _agentRunner;
  StorageService? _storage;
  StreamSubscription<AgentState>? _agentSub;

  final TextEditingController _urlController = TextEditingController();

  // Multi-Tab State
  final List<WebTab> _tabs = [];
  int _currentTabIndex = 0;

  WebTab get _currentTab {
    if (_tabs.isEmpty) {
      final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
      _tabs.add(WebTab(
        id: 'tab_init',
        url: homepage,
        title: '新标签页',
      ));
      _currentTabIndex = 0;
    }
    if (_currentTabIndex >= _tabs.length) {
      _currentTabIndex = _tabs.length - 1;
    }
    return _tabs[_currentTabIndex];
  }

  InAppWebViewController? get _webViewController => _currentTab.controller;
  WebViewControllerWrapper? get _wrapper => _currentTab.wrapper;
  bool get _canGoBack => _currentTab.canGoBack;
  bool get _canGoForward => _currentTab.canGoForward;
  bool get _isLoading => _currentTab.isLoading;
  double get _progress => _currentTab.progress;
  bool get _isDesktopMode => _currentTab.isDesktopMode;
  bool get _isCleanMode => _currentTab.isCleanMode;

  AgentState _agentState = const AgentState();

  @override
  void initState() {
    super.initState();
    _agentRunner = AgentRunner();
    _agentSub = _agentRunner.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _agentState = state;
        });
      }
    });
    NotificationService.getInstance().init();
    _initStorage();
  }

  Future<void> _initStorage() async {
    _storage = await StorageService.getInstance();
    final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final isDesktop = _storage?.getDesktopMode() ?? false;

    if (_tabs.isEmpty) {
      _tabs.add(WebTab(
        id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
        url: homepage,
        title: '主页',
        isDesktopMode: isDesktop,
      ));
      _currentTabIndex = 0;
      _urlController.text = homepage;
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _agentSub?.cancel();
    _agentRunner.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _createNewTab({String? url}) {
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
      _currentTabIndex = _tabs.length - 1;
      _urlController.text = targetUrl;
    });
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _currentTabIndex = index;
      _urlController.text = _currentTab.url;
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
        _tabs.add(WebTab(
          id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
          url: homepage,
          title: '新标签页',
        ));
        _currentTabIndex = 0;
      } else if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _urlController.text = _currentTab.url;
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
      _urlController.text = homepage;
    });
    Navigator.of(context).pop();
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

  void _loadUrl(String input) {
    String trimmed = input.trim();
    if (trimmed.isEmpty) return;

    final isUrl = trimmed.contains('.') &&
        !trimmed.contains(' ') &&
        (trimmed.startsWith('http://') ||
            trimmed.startsWith('https://') ||
            !trimmed.startsWith(' '));

    if (isUrl) {
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        trimmed = 'https://$trimmed';
      }
    } else {
      // Assemble search URL based on user's default search engine
      final engineName = _storage?.getSearchEngine() ?? AppConstants.defaultSearchEngine;
      final engineBase = AppConstants.searchEngines[engineName] ??
          AppConstants.searchEngines[AppConstants.defaultSearchEngine]!;
      trimmed = '$engineBase${Uri.encodeComponent(trimmed)}';
    }

    _currentTab.url = trimmed;
    _urlController.text = trimmed;
    _currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(trimmed)));
    setState(() {});
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

    await _webViewController!.setSettings(
      settings: InAppWebViewSettings(
        userAgent: userAgent,
        forceDark: webDarkMode ? ForceDark.ON : ForceDark.OFF,
        algorithmicDarkeningAllowed: webDarkMode,
        blockNetworkImage: blockImages,
        javaScriptEnabled: jsEnabled,
        textZoom: textZoom,
      ),
    );
  }

  void _toggleDesktopMode() async {
    _currentTab.isDesktopMode = !_currentTab.isDesktopMode;
    await _applyCurrentWebViewSettings();
    _currentTab.controller?.reload();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentTab.isDesktopMode ? '已切换至电脑桌面版模式' : '已切换至移动手机版模式'),
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
                  ? '🍃 纯净模式已开启：清理了 $count 处弹窗/遮罩，展开 $expCount 处折叠正文'
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
    if (currentUrl.isEmpty || currentUrl.startsWith('about:') || _wrapper == null) return;
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
        debugPrint('🚀 [UserScript] Injected $count active user scripts into $currentUrl');
      }
    } catch (e) {
      debugPrint('⚠️ [UserScript] Injection error: $e');
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

  void _quickSummarize() async {
    if (_wrapper == null) return;

    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: Colors.redAccent,
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
        content: Text('⚡ 正在提取网页正文...'),
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
            backgroundColor: Colors.amber,
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

  void _startAgentTask(String goal) async {
    if (_wrapper == null) return;

    final config = _storage?.getLlmConfig() ?? LlmConfig.defaultConfig();
    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置有效的大模型 API Key'),
          backgroundColor: Colors.redAccent,
          action: SnackBarAction(
            label: '去设置',
            textColor: Colors.white,
            onPressed: _openSettings,
          ),
        ),
      );
      return;
    }

    final maxSteps = _storage?.getMaxSteps() ?? 15;
    final safeMode = _storage?.getSafeMode() ?? true;

    _agentRunner.startTask(
      goal: goal,
      webView: _wrapper!,
      config: config,
      maxSteps: maxSteps,
      safeMode: safeMode,
    );
  }

  void _runMacro(MacroWorkflow macro) async {
    if (_wrapper == null) return;

    final macroService = await MacroService.getInstance();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在重放宏任务: ${macro.title}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    await macroService.executeMacro(
      macro: macro,
      webView: _wrapper!,
      onProgress: (cur, total, desc) {
        debugPrint('[Macro Progress] Step $cur/$total: $desc');
      },
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('宏任务 [${macro.title}] 执行完成！'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

  void _openSettings() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (updated == true && mounted) {
      _storage = await StorageService.getInstance();
      await _applyCurrentWebViewSettings();
      _currentTab.controller?.reload();
      setState(() {});
    }
  }

  void _openAgentBottomSheet() {
    showModalBottomSheet(
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
              currentUrl: _urlController.text,
              onSubmitGoal: (goal) {
                _startAgentTask(goal);
              },
              onStop: () => _agentRunner.stop(),
              onConfirmAction: (confirmed) => _agentRunner.confirmAction(confirmed),
              onConfirmCaptcha: (passed) => _agentRunner.confirmCaptchaSolved(passed),
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

  Widget _buildTabWebView(WebTab tab, int tabIndex) {
    final userAgent = tab.isDesktopMode
        ? AppConstants.uaDesktopChrome
        : (_storage?.getUserAgent() ?? AppConstants.uaAndroidChrome);
    final webDarkMode = _storage?.getWebDarkMode() ?? false;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;

    return InAppWebView(
      key: ValueKey(tab.id),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
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
        forceDark: webDarkMode ? ForceDark.ON : ForceDark.OFF,
        algorithmicDarkeningAllowed: webDarkMode,
        blockNetworkImage: blockImages,
        textZoom: textZoom,
      ),
      onWebViewCreated: (controller) {
        tab.controller = controller;
        tab.wrapper = WebViewControllerWrapper(controller);
        if (tabIndex == _currentTabIndex && mounted) {
          setState(() {});
        }
      },
      onLoadStart: (controller, url) {
        setState(() {
          tab.isLoading = true;
          tab.progress = 0.1;
        });
      },
      onLoadStop: (controller, url) async {
        final title = await controller.getTitle() ?? tab.title;
        final urlStr = url?.toString() ?? tab.url;
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
            _urlController.text = urlStr;
          }
        });

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
      onLongPressHitTestResult: (controller, hitTestResult) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _checkSelectionAndTrigger();
        });
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('[WebView Console] ${consoleMessage.message}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
        } else if (_tabs.length > 1) {
          _closeTab(_currentTabIndex);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            // Top Navigation & Wide Address Bar with Tab Counter
            BrowserControls(
              urlController: _urlController,
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              isLoading: _isLoading,
              progress: _progress,
              isDesktopMode: _isDesktopMode,
              isCleanMode: _isCleanMode,
              tabCount: _tabs.length,
              onBack: () => _webViewController?.goBack(),
              onForward: () => _webViewController?.goForward(),
              onReload: () => _webViewController?.reload(),
              onSubmitUrl: _loadUrl,
              onOpenSettings: _openSettings,
              onToggleDesktopMode: _toggleDesktopMode,
              onSummarize: _quickSummarize,
              onCleanPage: _toggleCleanMode,
              onOpenUserScripts: _openUserScripts,
              onOpenTabOverview: _openTabOverview,
              onNewTab: () => _createNewTab(),
            ),

            // Full-screen IndexedStack Multi-Tab WebView Canvas + Draggable Edge-Snapping Floating Agent Ball
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentTabIndex,
                    children: _tabs.asMap().entries.map((entry) {
                      return _buildTabWebView(entry.value, entry.key);
                    }).toList(),
                  ),

                  // Draggable & Magnetic Edge-Snapping Floating Agent Button
                  FloatingAgentBall(
                    state: _agentState,
                    onTap: _openAgentBottomSheet,
                    onQuickSummarize: _quickSummarize,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
