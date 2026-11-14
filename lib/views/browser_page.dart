import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../models/agent_attachment.dart';
import '../models/agent_state.dart';
import '../models/agent_task_record.dart';
import '../models/llm_config.dart';
import '../models/model_profile.dart';
import '../models/web_tab.dart';
import '../models/bookmark_item.dart';
import '../models/history_item.dart';
import '../agent/runner.dart';
import '../services/goal_handoff.dart';
import '../services/haptic_service.dart';
import '../services/notification_service.dart';
import '../services/run_coordinator.dart';
import '../services/share_intent_service.dart';
import '../services/storage_service.dart';
import '../services/user_script_service.dart';
import '../services/webview_controller_wrapper.dart';
import '../utils/url_utils.dart';
import 'settings/browsing_settings_page.dart';
import 'settings/settings_page.dart';
import 'settings/user_scripts_page.dart';
import 'widgets/agent_bottom_sheet.dart';
import 'widgets/agent_confirmation_card.dart';
import 'widgets/agent_status_bar.dart';
import 'widgets/agent_working_frame.dart';
import 'widgets/browser_controls.dart';
import 'widgets/chrome_visibility.dart';
import 'widgets/gesture_overlay.dart';
import 'widgets/selection_action_dialog.dart';
import 'widgets/summary_bottom_sheet.dart';
import 'widgets/tabs_overview_sheet.dart';
import 'widgets/history_bookmarks_sheet.dart';
import 'widgets/start_page_view.dart';
import 'widgets/bottom_toolbar.dart';

part 'browser/lifecycle.dart';
part 'browser/agent_flow.dart';
part 'browser/chrome.dart';
part 'browser/tabs.dart';
part 'browser/navigation.dart';
part 'browser/page_actions.dart';
part 'browser/web_view.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage>
    with SingleTickerProviderStateMixin {
  late AgentLoopRunner _loopRunner;
  StorageService? _storage;
  StreamSubscription<AgentState>? _loopSub;
  final ValueNotifier<GesturePulse?> _gesturePulse = ValueNotifier(null);
  int _gestureSeq = 0;

  final TextEditingController _urlController = TextEditingController();

  /// The chrome sliding in and out of the way while the user reads.
  late final AnimationController _chromeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 160),
    value: 1,
  );
  final ChromeVisibility _chrome = ChromeVisibility();

  // Multi-Tab State
  final List<WebTab> _tabs = [];
  int _currentTabIndex = 0;

  WebTab get _currentTab {
    final index = _currentTabIndex.clamp(0, _tabs.length - 1);
    return _tabs[index];
  }

  /// Whether web pages should be rendered dark.
  ///
  /// Only the explicit "force web dark mode" switch counts. The app's own
  /// light/dark preference is a UI choice and must not invert websites: a user
  /// who picks a light UI still expects pages to look like the web.
  bool get _webDarkEnabled => _storage?.getWebDarkMode() ?? false;

  InAppWebViewController? get _webViewController => _currentTab.controller;
  WebViewControllerWrapper? get _wrapper => _currentTab.wrapper;
  bool get _canGoBack => _currentTab.canGoBack;
  bool get _canGoForward => _currentTab.canGoForward;
  bool get _isLoading => _currentTab.isLoading;
  double get _progress => _currentTab.progress;
  bool get _isDesktopMode => _currentTab.isDesktopMode;
  bool get _isCleanMode => _currentTab.isCleanMode;

  AgentState _agentState = const AgentState();
  final RunCoordinator _runCoordinator = RunCoordinator();
  bool _statusBarDismissed = false;
  String? _agentTabId;
  DateTime? _taskStartedAt;
  bool _taskRecorded = false;
  bool _permissionDialogOpen = false;
  bool _agentSheetOpen = false;
  bool _confirmationCardOpen = false;
  String? _confirmationShownFor;
  StreamSubscription<String>? _shareSub;

  /// Whether the configured model can read images: the composer offers an
  /// image picker only when something downstream can use one.
  bool get _modelTakesImages {
    final storage = _storage;
    if (storage == null) return true;
    final config = storage.getLlmConfig();
    return storage.getModelProfile(config).visionFor(config.model);
  }

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


  @override
  void initState() {
    super.initState();
    // Seed the first tab synchronously so build() never mutates state.
    _tabs.add(WebTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      url: AppConstants.defaultHomepage,
      title: '新标签页',
    ));
    _loopRunner = AgentLoopRunner();
    _loopRunner.onGesture = (x, y, label) {
      // The layer decides the point before dispatching; this only draws it.
      // CSS pixels become logical pixels through the page's own zoom: at
      // scale 1 they are the same, and a pinch-zoomed page scales both the
      // layout and the point the layer computed.
      unawaited(_showGesture(x, y, label));
    };
    _loopRunner.onAsk = _askUser;
    _loopSub = _loopRunner.stateStream.listen(_applyAgentState);
    NotificationService.getInstance().init();

    // Links shared into the app open as a tab instead of interrupting the
    // current page, so the note the user was reading stays put.
    ShareIntentService.instance.init();
    _shareSub = ShareIntentService.instance.links.listen(_openSharedLink);

    // "Ask this again" from the history page lands here.
    GoalHandoff.pending.addListener(_onGoalHandoff);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntentService.instance.takeInitialLink();
      if (initial != null && mounted) _openSharedLink(initial);
    });

    _initStorage();
  }









  @override
  void dispose() {
    _loopSub?.cancel();
    _loopRunner.dispose();
    _gesturePulse.dispose();
    _shareSub?.cancel();
    GoalHandoff.pending.removeListener(_onGoalHandoff);
    _urlController.dispose();
    _chromeController.dispose();
    super.dispose();
  }





















  /// The URL worth copying/sharing: the loaded page, not whatever is typed in
  /// the field, and never an internal `operon://` page.
  String? get _sharableUrl {
    final url = _currentTab.url.trim();
    if (url.isEmpty || url.startsWith('operon://')) return null;
    if (url == 'about:blank') return null;
    return url;
  }














  /// Confirms a CAPTCHA only after re-checking the page.
  ///
  /// Tapping "done" before the challenge is actually solved would otherwise
  /// resume the agent into the same blocked page.








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
                  SizeTransition(
                    sizeFactor: _chromeController,
                    axisAlignment: -1,
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.25,
                      child: BrowserControls(
                        urlController: _urlController,
                        isLoading: _isLoading,
                        progress: _progress,
                        onSubmitUrl: _loadUrl,
                        onSummarize: _quickSummarize,
                        onOpenAgent: _openAgentBottomSheet,
                        agentBusy: _agentState.isRunning,
                        onCopyUrl: _copyCurrentUrl,
                        onShareUrl: _shareCurrentUrl,
                        onFocusChanged: (focused) {
                          // Typing an address is not reading: hold the chrome.
                          if (focused) {
                            _chrome.lock();
                            _revealChrome();
                          } else {
                            _chrome.unlock();
                          }
                        },
                      ),
                    ),
                  ),

                // Full-screen IndexedStack Multi-Tab WebView Canvas.
                // Touches are intentionally not used to pause the agent; the
                // status strip's pause button is the explicit takeover path.
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(
                        index: _currentTabIndex,
                        children: _tabs.asMap().entries.map((entry) {
                          return _buildTabWebView(entry.value, entry.key);
                        }).toList(),
                      ),
                      // Which page the agent is on, at a glance. The strip
                      // below says what it is doing; this says where.
                      if (_agentState.isRunning)
                        const Positioned.fill(
                          child: IgnorePointer(child: AgentWorkingFrame()),
                        ),
                    ],
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
                            onPause: _loopRunner.pause,
                            onResume: _loopRunner.resume,
                            onStop: _loopRunner.stop,
                            onConfirmCaptcha: () =>
                                _loopRunner.confirmCaptchaSolved(true),
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
                // Slides away while reading; back on an upward flick.
                SizeTransition(
                  sizeFactor: _chromeController,
                  axisAlignment: 1,
                  child: MediaQuery.withClampedTextScaling(
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
                      showCleanMode: _storage?.getReadingModeEnabled() ?? true,
                      showSummary: _storage?.getPageSummaryEnabled() ?? true,
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
                      currentUrl: _currentTab.url,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
