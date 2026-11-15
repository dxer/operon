import 'transport/endpoint.dart';

/// What switching, closing and opening a tab needs from the app that owns the
/// tab strip.
///
/// A DevTools target id never leaves the CDP socket: the Flutter side has its
/// own `WebTab` objects and no idea which target id belongs to which. So the
/// two are matched on the one thing they share — the page — and the app is the
/// one that moves what the user sees.
///
/// Why this exists at all: `switch_tab` used to attach the layer to another
/// target and stop there. The agent then acted on a page the user was not
/// looking at, and the gesture overlay drew its pulse on the wrong tab. An
/// agent that operates somewhere invisible is indistinguishable from a broken
/// one.
class TabHost {
  const TabHost({this.activate, this.close, this.open});

  /// Bring the page with this URL to the front. Returns false when the app has
  /// no tab for it any more.
  final Future<bool> Function(CdpTarget page)? activate;

  /// Close the page. Returns false when the app refused (the last tab, or a
  /// tab the run still needs).
  final Future<bool> Function(CdpTarget page)? close;

  /// Open a new tab on [url]. Returns once the tab exists, not once it loads.
  final Future<void> Function(String url)? open;

  bool get canActivate => activate != null;
  bool get canClose => close != null;
  bool get canOpen => open != null;
}
