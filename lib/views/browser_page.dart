import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import '../config/app_tokens.dart';
import '../models/agent_attachment.dart';
import '../models/agent_state.dart';
import '../models/agent_conversation.dart';
import '../models/download_item.dart';
import '../models/llm_config.dart';
import '../models/model_profile.dart';
import '../models/web_tab.dart';
import '../models/bookmark_item.dart';
import '../models/history_item.dart';
import '../agent/compactor.dart';
import '../agent/runner.dart';
import '../agent/transcript.dart' show estimateConversationTokens;
import '../control/protocol/gesture.dart';
import '../control/tab_host.dart';
import '../control/transport/endpoint.dart' show CdpTarget;
import '../services/conversation_store.dart';
import '../services/download_service.dart';
import '../services/goal_handoff.dart';
import '../services/haptic_service.dart';
import '../services/notification_service.dart';
import '../services/run_coordinator.dart';
import '../services/share_intent_service.dart';
import '../services/storage_service.dart';
import '../services/webview_controller_wrapper.dart';
import '../services/favicon_service.dart';
import '../utils/url_utils.dart';
import 'settings/browsing_settings_page.dart';
import 'settings/settings_page.dart';
import 'widgets/agent_bottom_sheet.dart';
import 'widgets/agent_confirmation_card.dart';
import 'widgets/agent_status_bar.dart';
import 'widgets/agent_working_frame.dart';
import 'widgets/browser_controls.dart';
import 'widgets/chrome_visibility.dart';
import 'widgets/downloads_sheet.dart';
import 'widgets/find_in_page_bar.dart';
import 'widgets/gesture_overlay.dart';
import 'widgets/omnibox_suggestions.dart';
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

  /// The chat history the panel shows. Opened once, kept in memory.
  ConversationStore? _conversations;

  /// The conversation the panel had open, so reopening lands where it left.
  String? _activeConversationId;

  /// The conversation the running task belongs to. Captured at start: the user
  /// can open another one while it runs, and the turn must go where it started.
  String? _runningConversationId;
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
  final ChromeVisibility _chrome = ChromeVisibility(threshold: 72, jitter: 10);
  bool _addressFocused = false;
  String? _clipboardUrl;
  bool _isFindingInPage = false;
  final TextEditingController _findController = TextEditingController();
  int _findActiveMatch = 0;
  int _findTotalMatches = 0;

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
  List<String> _runningAttachmentNames = const [];
  bool _turnSaved = false;
  bool _permissionDialogOpen = false;
  final Set<String> _trustedSslHosts = <String>{};
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
    _loopRunner.onGesture = (target) {
      // The layer decides the point and the box before dispatching; this only
      // draws them. CSS pixels become logical pixels through the page's own
      // zoom: at scale 1 they are the same, and a pinch-zoomed page scales
      // both the layout and the box the layer measured.
      unawaited(_showGesture(target));
    };
    _loopRunner.onAsk = _askUser;
    _loopRunner.onPickFiles = _pickUploadFiles;
    // The agent may switch or close tabs; only this page can move what the
    // user sees, so it owns that half of the contract.
    _loopRunner.tabHost = _buildTabHost();
    _loopSub = _loopRunner.stateStream.listen(_applyAgentState);
    NotificationService.getInstance().init();

    // Links shared into the app open as a tab instead of interrupting the
    // current page, so the note the user was reading stays put.
    ShareIntentService.instance.init();
    _shareSub = ShareIntentService.instance.links.listen(_openSharedLink);

    // "Ask this again" from the history page lands here.
    GoalHandoff.pending.addListener(_onGoalHandoff);
    _urlController.addListener(_onAddressControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntentService.instance.takeInitialLink();
      if (initial != null && mounted) _openSharedLink(initial);
    });

    _initStorage();
  }

  void _onAddressControllerChanged() {
    if (_addressFocused && mounted) {
      setState(() {});
    }
  }









  @override
  void dispose() {
    _loopSub?.cancel();
    _loopRunner.dispose();
    _gesturePulse.dispose();
    _shareSub?.cancel();
    GoalHandoff.pending.removeListener(_onGoalHandoff);
    _urlController.removeListener(_onAddressControllerChanged);
    _urlController.dispose();
    _findController.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isStartPage = _currentTab.url == 'operon://newtab' ||
        _currentTab.url == 'about:blank' ||
        _currentTab.url.isEmpty;
    final omniboxSuggestions = (!isStartPage &&
            !_isFindingInPage &&
            _addressFocused &&
            _storage != null)
        ? buildOmniboxSuggestions(
            query: _urlController.text,
            bookmarks: _storage!.getBookmarks(),
            history: _storage!.getHistory(),
            clipboardUrl: _clipboardUrl,
            currentUrl: _currentTab.url,
          )
        : const <OmniboxSuggestion>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_addressFocused) {
            FocusScope.of(context).unfocus();
            return;
          }
          if (_isFindingInPage) {
            _closeFindInPage();
            return;
          }
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
                  // Top Navigation & Wide Address Bar (or Find-in-Page bar)
                  if (!isStartPage && _isFindingInPage)
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.25,
                      child: FindInPageBar(
                        controller: _findController,
                        activeMatch: _findActiveMatch,
                        totalMatches: _findTotalMatches,
                        onQueryChanged: _updateFindQuery,
                        onPrevious: () =>
                            _currentTab.findController?.findNext(forward: false),
                        onNext: () =>
                            _currentTab.findController?.findNext(forward: true),
                        onClose: _closeFindInPage,
                      ),
                    )
                  else if (!isStartPage)
                    SizeTransition(
                      sizeFactor: _chromeController,
                      axisAlignment: -1,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.25,
                        child: BrowserControls(
                          urlController: _urlController,
                          pageTitle: _currentTab.title,
                          isLoading: _isLoading,
                          progress: _progress,
                          isIncognito: _currentTab.isIncognito,
                          onSubmitUrl: _loadUrl,
                          onReload: () => _webViewController?.reload(),
                          onStopLoad: () => _webViewController?.stopLoading(),
                          onSummarize: _quickSummarize,
                          onOpenAgent: _openAgentBottomSheet,
                          agentBusy: _agentState.isRunning,
                          onCopyUrl: _copyCurrentUrl,
                          onShareUrl: _shareCurrentUrl,
                          onFocusChanged: _handleAddressFocusChanged,
                        ),
                      ),
                    ),

                  // Full-screen IndexedStack Multi-Tab WebView Canvas.
                  Expanded(
                    child: Stack(
                      children: [
                        IndexedStack(
                          index: _currentTabIndex,
                          children: _tabs.map(_buildTabWebView).toList(),
                        ),
                        // Which page the agent is on, at a glance.
                        if (_agentState.isRunning)
                          const Positioned.fill(
                            child: IgnorePointer(child: AgentWorkingFrame()),
                          ),
                        if (_addressFocused && !isStartPage && !_isFindingInPage)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => FocusScope.of(context).unfocus(),
                              child: ColoredBox(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.18,
                                ),
                              ),
                            ),
                          ),
                        if (omniboxSuggestions.isNotEmpty)
                          Positioned(
                            top: AppSpace.x2,
                            left: AppSpace.x3,
                            right: AppSpace.x3,
                            child: OmniboxSuggestionsPanel(
                              suggestions: omniboxSuggestions,
                              onSelect: (url) {
                                FocusScope.of(context).unfocus();
                                _loadUrl(url);
                              },
                              onFillQuery: (url) {
                                _urlController.text = url;
                                _urlController.selection =
                                    TextSelection.collapsed(offset: url.length);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Docked agent status strip
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
                              onConfirmAction: _showConfirmationCard,
                              onDismiss: () =>
                                  setState(() => _statusBarDismissed = true),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  // Via-Style One-Handed Bottom Toolbar: anchored steadily at
                  // the thumb zone so Android WebView never flickers/resizes on
                  // every short scroll, with horizontal swipe tab switching.
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
                      isWebDarkMode: _webDarkEnabled,
                      isBlockImages: _storage?.getBlockImages() ?? false,
                      showCleanMode: _storage?.getReadingModeEnabled() ?? true,
                      showSummary: _storage?.getPageSummaryEnabled() ?? true,
                      onBack: () => _webViewController?.goBack(),
                      onForward: () => _webViewController?.goForward(),
                      onHome: () => _goHome(useConfiguredHomepage: true),
                      onOpenTabs: _openTabOverview,
                      onPreviousTab: _tabs.length > 1
                          ? () => _switchTab(
                                (_currentTabIndex - 1 + _tabs.length) %
                                    _tabs.length,
                              )
                          : null,
                      onNextTab: _tabs.length > 1
                          ? () => _switchTab(
                                (_currentTabIndex + 1) % _tabs.length,
                              )
                          : null,
                      onLongPressTabs: () => _createNewTab(),
                      onLongPressHome: () =>
                          _openHistoryBookmarksSheet(initialTab: 1),
                      onReload: () => _webViewController?.reload(),
                      onStopLoad: () => _webViewController?.stopLoading(),
                      onNewTab: () => _createNewTab(),
                      onNewIncognitoTab: () => _createNewTab(isIncognito: true),
                      onOpenDownloads: _openDownloadsSheet,
                      onFindInPage: _openFindInPage,
                      onShareUrl: _shareCurrentUrl,
                      onSummarize: _quickSummarize,
                      onCleanPage: _toggleCleanMode,
                      onToggleBookmark: _toggleBookmarkCurrentPage,
                      onOpenHistory: () =>
                          _openHistoryBookmarksSheet(initialTab: 0),
                      onOpenBookmarks: () =>
                          _openHistoryBookmarksSheet(initialTab: 1),
                      onToggleDesktopMode: _toggleDesktopMode,
                      onToggleWebDarkMode: _toggleQuickWebDarkMode,
                      onToggleBlockImages: _toggleQuickBlockImages,
                      onOpenSettings: _openSettings,
                      currentUrl: _currentTab.url,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
