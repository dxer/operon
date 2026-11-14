part of '../browser_page.dart';

// The address bar and toolbar stepping out of the way while the user reads.

extension _ChromeActions on _BrowserPageState {
  /// Scroll feedback from the page, which is the only place that knows whether
  /// the user is reading downwards or reaching back up.
  void _onPageScroll(int y) {
    if (!mounted) return;
    final action = _chrome.onScroll(y.toDouble());
    if (action == ChromeAction.none) return;
    final shown = action == ChromeAction.show;
    if (shown == (_chromeController.value > 0.5)) return;
    if (shown) {
      _chromeController.forward();
    } else {
      _chromeController.reverse();
    }
  }

  /// Brings the chrome back for a moment that needs it: a new page, a submitted
  /// address, a switch of tab, or the panel opening over the page.
  void _revealChrome() {
    _chrome.show();
    if (_chromeController.value < 1) _chromeController.forward();
  }
}
