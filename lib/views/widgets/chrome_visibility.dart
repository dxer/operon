/// When the browser chrome should get out of the way while the user reads.
///
/// The rule every mobile browser settled on: scrolling down means "give me the
/// page", scrolling up means "I want the controls back", and at the very top the
/// chrome is always visible because that is where the user starts.
///
/// Kept as a plain object with no widgets in it: the interesting part is the
/// thresholds and the reasons to force the chrome back, and none of that needs a
/// screen to be tested.
library;

/// What the page's scroll position asks for.
enum ChromeAction { none, hide, show }

class ChromeVisibility {
  ChromeVisibility({
    this.threshold = 28,
    this.jitter = 6,
    this.topZone = 8,
  });

  /// How far the page has to travel in one direction before the chrome moves.
  /// Small enough to feel immediate, large enough to ignore a finger's tremor.
  final double threshold;

  /// Movement below this is not a scroll: it is the same gesture wobbling.
  final double jitter;

  /// Within this distance of the top, the chrome is shown unconditionally.
  final double topZone;

  double _lastY = 0;
  double _travel = 0;
  bool _hidden = false;
  bool _locked = false;

  /// The first position after a reset is where the page *is*, not how far it
  /// moved: a page restored to a saved offset must not read as a scroll.
  bool _primed = false;

  /// The chrome is currently off screen.
  bool get hidden => _hidden;

  /// Something is holding the chrome in place — a focused address field, a
  /// running task, an open panel. Scrolling must not take it away.
  bool get locked => _locked;

  /// Stops the chrome from hiding until [unlock] is called, and shows it now:
  /// hiding the address field while it is being typed into is the one thing a
  /// user would call broken.
  void lock() {
    _locked = true;
    _hidden = false;
    _travel = 0;
  }

  void unlock() {
    _locked = false;
  }

  /// Shows the chrome regardless of scroll direction, keeping the position so
  /// the next scroll gesture starts from where the finger is.
  void show() {
    _hidden = false;
    _travel = 0;
  }

  /// A new page or a tab switch: start from the top, chrome visible.
  void reset() {
    _lastY = 0;
    _travel = 0;
    _hidden = false;
    _primed = false;
  }

  /// Feeds one scroll position, in CSS pixels from the top of the document.
  ChromeAction onScroll(double y) {
    if (y <= topZone) {
      _lastY = y;
      _travel = 0;
      _hidden = false;
      _primed = true;
      return ChromeAction.show;
    }
    final delta = y - _lastY;
    _lastY = y;
    if (!_primed) {
      _primed = true;
      return ChromeAction.none;
    }
    if (_locked || delta.abs() < jitter) return ChromeAction.none;

    // Accumulate only in the direction of travel: a wobble up then down is not
    // two gestures.
    if (_travel != 0 && delta.sign != _travel.sign) _travel = 0;
    _travel += delta;
    if (_travel > threshold && !_hidden) {
      _hidden = true;
      _travel = 0;
      return ChromeAction.hide;
    }
    if (_travel < -threshold && _hidden) {
      _hidden = false;
      _travel = 0;
      return ChromeAction.show;
    }
    return ChromeAction.none;
  }
}
