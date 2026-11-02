import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../models/agent_state.dart';
import '../models/llm_config.dart';
import '../models/macro_workflow.dart';
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

class BrowserPage extends StatefulWidget {
  const BrowserPage({Key? key}) : super(key: key);

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _webViewController;
  WebViewControllerWrapper? _wrapper;
  late AgentRunner _agentRunner;
  StorageService? _storage;
  StreamSubscription<AgentState>? _agentSub;

  final TextEditingController _urlController = TextEditingController();
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isLoading = false;
  double _progress = 0.0;
  bool _isDesktopMode = false;
  bool _isCleanMode = false;

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
    _urlController.text = homepage;
    _isDesktopMode = _storage?.getDesktopMode() ?? false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _agentSub?.cancel();
    _agentRunner.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    _wrapper = WebViewControllerWrapper(controller);
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    setState(() {
      _isLoading = false;
      _urlController.text = url?.toString() ?? '';
    });

    _canGoBack = await controller.canGoBack();
    _canGoForward = await controller.canGoForward();

    // Auto-inject agent script when page finishes loading
    if (_wrapper != null) {
      await _wrapper!.ensureScriptInjected();
      // If clean mode is enabled, auto-apply anti-jump & auto-expand
      if (_isCleanMode) {
        await _wrapper!.cleanPageMode();
      }
      _injectMatchedUserScripts(url?.toString() ?? '');
    }
    if (mounted) setState(() {});
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    setState(() {
      _progress = progress / 100.0;
      _isLoading = progress < 100;
    });
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

    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(trimmed)));
  }

  Future<void> _applyCurrentWebViewSettings() async {
    if (_webViewController == null) return;

    final userAgent = _storage?.getUserAgent() ?? AppConstants.uaAndroidChrome;
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
    _isDesktopMode = !_isDesktopMode;
    await _storage?.saveDesktopMode(_isDesktopMode);

    final newUA = _isDesktopMode
        ? AppConstants.uaDesktopChrome
        : AppConstants.uaAndroidChrome;
    await _storage?.saveUserAgent(newUA);

    await _applyCurrentWebViewSettings();
    _webViewController?.reload();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isDesktopMode ? '已切换至电脑桌面版模式' : '已切换至移动手机版模式'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _toggleCleanMode() async {
    _isCleanMode = !_isCleanMode;
    if (_wrapper != null) {
      final res = await _wrapper!.cleanPageMode();
      final count = res['removedCount'] ?? 0;
      final expCount = res['expandedCount'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isCleanMode
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
          content: const Text('请先在配置中心填写大模型 API Key！'),
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

    final maxSteps = _storage?.getMaxSteps() ?? 15;
    final safeMode = _storage?.getSafeMode() ?? true;

    _agentRunner.run(
      userGoal: goal,
      webView: _wrapper!,
      config: config,
      maxSteps: maxSteps,
      safeMode: safeMode,
    );
  }

  Future<void> _runMacro(MacroWorkflow macro) async {
    if (_wrapper == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ 开始以 0 Token 极速重放宏: ${macro.title}'),
        backgroundColor: Colors.amber[800],
      ),
    );

    final macroService = await MacroService.getInstance();
    await macroService.executeMacro(
      macro: macro,
      webView: _wrapper!,
      onProgress: (current, total, desc) {
        debugPrint('[Macro Progress] $current/$total: $desc');
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 宏任务执行完毕！耗时极短，消耗 0 Token'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );

    if (updated == true && mounted) {
      _isDesktopMode = _storage?.getDesktopMode() ?? false;
      await _applyCurrentWebViewSettings();
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
            final currentState = snapshot.data ?? _agentState;
            return AgentBottomSheet(
              state: currentState,
              onStart: (goal) {
                _startAgentTask(goal);
                Navigator.of(ctx).pop(); // dismiss sheet so user can watch webview
              },
              onPause: () => _agentRunner.pause(),
              onResume: () => _agentRunner.resume(),
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

  @override
  Widget build(BuildContext context) {
    final userAgent = _storage?.getUserAgent() ?? AppConstants.uaAndroidChrome;
    final initialUrl = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final webDarkMode = _storage?.getWebDarkMode() ?? false;
    final blockImages = _storage?.getBlockImages() ?? false;
    final jsEnabled = _storage?.getJavaScriptEnabled() ?? true;
    final textZoom = _storage?.getTextZoom() ?? 100;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            // Top Navigation & Address Bar
            BrowserControls(
              urlController: _urlController,
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              isLoading: _isLoading,
              progress: _progress,
              isDesktopMode: _isDesktopMode,
              isCleanMode: _isCleanMode,
              onBack: () => _webViewController?.goBack(),
              onForward: () => _webViewController?.goForward(),
              onReload: () => _webViewController?.reload(),
              onSubmitUrl: _loadUrl,
              onOpenSettings: _openSettings,
              onToggleDesktopMode: _toggleDesktopMode,
              onSummarize: _quickSummarize,
              onCleanPage: _toggleCleanMode,
              onOpenUserScripts: _openUserScripts,
            ),

            // Full-screen WebView Canvas + Draggable Edge-Snapping Floating Agent Ball
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
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
                    onWebViewCreated: _onWebViewCreated,
                    onLoadStop: _onLoadStop,
                    onProgressChanged: _onProgressChanged,
                    onLongPressHitTestResult: (controller, hitTestResult) {
                      // Trigger selection check on mobile long press
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _checkSelectionAndTrigger();
                      });
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      debugPrint('[WebView Console] ${consoleMessage.message}');
                    },
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
