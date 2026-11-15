part of '../browser_page.dart';

// setState is protected to stop code calling it on *another* State. These
// extensions are on this State, in this library, and always run inside the
// widget that owns it, so the warning is about the shape of the code, not
// about a misuse.
// ignore_for_file: invalid_use_of_protected_member

// Startup, storage, shared links and the small pieces the runner calls back into.

extension _LifecycleActions on _BrowserPageState {
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

  Future<void> _initStorage() async {
    _storage = await StorageService.getInstance();
    unawaited(DownloadService.instance.init());
    // The chat history is a file, not a preference, so it loads on its own and
    // may arrive after the first frame. The panel copes with a null store: it
    // shows the list and the button that creates the first conversation.
    unawaited(_openConversations());
    final homepage = _storage?.getHomepage() ?? AppConstants.defaultHomepage;
    final isDesktop = _storage?.getDesktopMode() ?? false;

    final seedUntouched =
        _tabs.length == 1 && _tabs.first.url == AppConstants.defaultHomepage;
    final savedSession = seedUntouched ? _storage?.getSavedTabSession() : null;

    if (seedUntouched && savedSession != null && savedSession.tabs.isNotEmpty) {
      final restored = <WebTab>[];
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < savedSession.tabs.length; i++) {
        final item = savedSession.tabs[i];
        restored.add(WebTab(
          id: 'tab_${base}_$i',
          url: item.url,
          title: item.title,
          isDesktopMode: item.isDesktopMode,
        ));
      }
      _tabs
        ..clear()
        ..addAll(restored);
      _currentTabIndex = savedSession.activeIndex;
      final activeUrl = _currentTab.url;
      _urlController.text = activeUrl.startsWith('operon://') ? '' : activeUrl;
    } else if (seedUntouched) {
      // The seed tab has not navigated yet: apply the user's saved homepage once.
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

  void _persistTabSession() {
    final storage = _storage;
    if (storage == null) return;
    final snapshots = <SavedTabSnapshot>[];
    var mappedActive = 0;
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.isIncognito) continue;
      if (i == _currentTabIndex) {
        mappedActive = snapshots.length;
      }
      snapshots.add(SavedTabSnapshot(
        url: tab.url,
        title: tab.title,
        isDesktopMode: tab.isDesktopMode,
      ));
    }
    unawaited(storage.saveTabSession(snapshots, mappedActive));
  }

  /// Opens the composer with a goal the user asked to repeat, on the page it
  /// ran on last time when there is one.
  ///
  /// Deferred by a frame: the history page pops back to this one just before
  /// telling us, and a sheet pushed mid-transition ends up fighting the pop.
  void _onGoalHandoff() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final request = GoalHandoff.take();
      if (request == null) return;
      final url = request.url;
      if (url != null && url != _currentTab.url) _loadUrl(url);
      unawaited(_openAgentBottomSheet(initialGoal: request.goal));
    });
  }

  /// Says why a disabled feature did nothing, and where to turn it back on.
  void _showFeatureDisabled(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const BrowsingSettingsPage(),
            ),
          ),
        ),
      ),
    );
  }

  /// Draws one gesture above the WebView: the cursor, and the box it is about
  /// to operate.
  Future<void> _showGesture(GestureTarget target) async {
    var scale = 1.0;
    final controller = _webViewController;
    if (controller != null) {
      try {
        scale = await controller.getZoomScale() ?? 1.0;
      } catch (_) {
        // A page that cannot report its zoom is drawn at 1:1.
      }
    }
    if (!mounted) return;
    _gesturePulse.value = GesturePulse(
      at: Offset(target.x * scale, target.y * scale),
      bounds: target.hasBox
          ? Rect.fromLTWH(
              target.x * scale,
              target.y * scale,
              target.width * scale,
              target.height * scale,
            )
          : null,
      label: target.label,
      seq: ++_gestureSeq,
    );
  }

  /// Asks the user a question the agent could not answer from the page.
  ///
  /// A run with no way to ask would have to guess, so the panel always offers
  /// an answer box while it is open.
  Future<String?> _askUser(String question) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    try {
      final answer = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('智能体需要你确认'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(question, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '在这里回答',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消任务'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim().isEmpty
                      ? '（用户没有填写内容）'
                      : controller.text.trim()),
              child: const Text('回答'),
            ),
          ],
        ),
      );
      return answer;
    } finally {
      controller.dispose();
    }
  }

  /// Opens the system file picker when the agent calls `upload` without paths.
  Future<List<String>?> _pickUploadFiles() async {
    if (!mounted) return null;
    try {
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result == null) return null;
      final paths = result.files
          .map((file) => file.path?.trim() ?? '')
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      return paths.isEmpty ? null : paths;
    } catch (_) {
      return null;
    }
  }
}
