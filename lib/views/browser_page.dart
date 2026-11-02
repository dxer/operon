import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../models/agent_state.dart';
import '../services/agent_runner.dart';
import '../services/storage_service.dart';
import '../services/webview_controller_wrapper.dart';
import 'settings/settings_page.dart';
import 'widgets/agent_bottom_sheet.dart';
import 'widgets/browser_controls.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({Key? key}) : super(key: key);

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _webViewController;
  WebViewControllerWrapper? _wrapper;
  late AgentRunner _agentRunner;
  late StorageService _storage;
  StreamSubscription<AgentState>? _agentSub;

  final TextEditingController _urlController = TextEditingController();
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isLoading = false;
  double _progress = 0.0;
  bool _isAgentPanelOpen = true;

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
    _initStorage();
  }

  Future<void> _initStorage() async {
    _storage = await StorageService.getInstance();
    final homepage = _storage.getHomepage();
    _urlController.text = homepage;
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

    Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !trimmed.contains('.')) {
      // Treat as search query
      trimmed = 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    } else if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }

    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(trimmed)));
  }

  void _startAgentTask(String goal) async {
    if (_wrapper == null) return;

    final config = _storage.getLlmConfig();
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

    final maxSteps = _storage.getMaxSteps();
    final safeMode = _storage.getSafeMode();

    _agentRunner.run(
      userGoal: goal,
      webView: _wrapper!,
      config: config,
      maxSteps: maxSteps,
      safeMode: safeMode,
    );
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );

    if (updated == true && mounted) {
      // Reload settings such as User-Agent
      final currentUA = _storage.getUserAgent();
      await _webViewController?.setSettings(
        settings: InAppWebViewSettings(userAgent: currentUA),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAgent =
        _storage != null ? _storage.getUserAgent() : AppConstants.uaAndroidChrome;
    final initialUrl =
        _storage != null ? _storage.getHomepage() : AppConstants.defaultHomepage;

    return Scaffold(
      body: Column(
        children: [
          // Browser Navigation Bar
          BrowserControls(
            urlController: _urlController,
            canGoBack: _canGoBack,
            canGoForward: _canGoForward,
            isLoading: _isLoading,
            progress: _progress,
            onBack: () => _webViewController?.goBack(),
            onForward: () => _webViewController?.goForward(),
            onReload: () => _webViewController?.reload(),
            onSubmitUrl: _loadUrl,
            onOpenSettings: _openSettings,
          ),

          // Main WebView Canvas
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    userAgent: userAgent,
                    javaScriptEnabled: true,
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
                  ),
                  onWebViewCreated: _onWebViewCreated,
                  onLoadStop: _onLoadStop,
                  onProgressChanged: _onProgressChanged,
                  onConsoleMessage: (controller, consoleMessage) {
                    debugPrint('[WebView Console] ${consoleMessage.message}');
                  },
                ),

                // Floating Action Button to toggle Agent Sheet when minimized
                if (!_isAgentPanelOpen)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.extended(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.psychology),
                      label: Text(
                        _agentState.isRunning ? 'AI 运行中...' : '唤起 AI Agent',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => setState(() => _isAgentPanelOpen = true),
                    ),
                  ),
              ],
            ),
          ),

          // Docked Agent Control Panel
          if (_isAgentPanelOpen)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Panel minimize bar
                Container(
                  color: AppTheme.darkCard,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.white54),
                        onPressed: () => setState(() => _isAgentPanelOpen = false),
                        tooltip: '收起 AI 助手',
                      ),
                    ],
                  ),
                ),
                AgentBottomSheet(
                  state: _agentState,
                  onStart: _startAgentTask,
                  onPause: () => _agentRunner.pause(),
                  onResume: () => _agentRunner.resume(),
                  onStop: () => _agentRunner.stop(),
                  onConfirmAction: (confirmed) => _agentRunner.confirmAction(confirmed),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
