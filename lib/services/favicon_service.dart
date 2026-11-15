import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Site icons, fetched once and kept in memory for the session.
///
/// A browser that shows monograms where icons belong reads as a mock-up: the
/// tab strip, the start page and history are three places where the user
/// recognises a site by its mark, not by its name. Nothing here is invented —
/// the bytes come from the site's own `/favicon.ico`, the same place every
/// browser has looked for thirty years.
///
/// Deliberately memory-only:
///
/// * an icon is worth nothing after a restart;
/// * writing them to disk means an eviction policy, a size budget and a cache
///   that can go stale, in exchange for saving one request per host;
/// * a missing icon is a normal answer (many sites have none), so a failed
///   fetch is cached as a failure and never retried in the same session.
///
/// All of it is best-effort. A site that does not answer gets its letter, and
/// nothing on screen waits for a network call to finish before drawing.
class FaviconService {
  FaviconService._();

  static const Duration _timeout = Duration(seconds: 4);

  /// A favicon is 16–64px; anything larger is a mistake or an attack.
  static const int _maxBytes = 256 * 1024;

  /// `null` value means "asked, nothing there" — cached so we do not ask again.
  static final Map<String, Uint8List?> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};

  /// What is already known, without any await.
  static Uint8List? cached(String host) => _cache[host.toLowerCase()];

  /// A favicon handed to us by the WebView, which already downloaded it.
  static void put(String host, Uint8List? bytes) {
    final key = host.toLowerCase();
    if (key.isEmpty) return;
    if (bytes == null || bytes.isEmpty) return;
    if (!_looksLikeImage(bytes)) return;
    _cache[key] = bytes;
  }

  /// Fetches `https://host/favicon.ico`, or returns the cached answer.
  static Future<Uint8List?> load(String host) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) return Future.value(null);
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _fetch(url: 'https://$key/favicon.ico').then((bytes) {
      _cache[key] = bytes;
      _inflight.remove(key);
      return bytes;
    }).catchError((Object _) {
      _cache[key] = null;
      _inflight.remove(key);
      return null;
    });
    _inflight[key] = future;
    return future;
  }

  /// Fetches an icon the page declared, and remembers it under [host].
  ///
  /// The WebView knows the exact URL the site points at (a `<link rel=icon>` in
  /// a subdirectory, an SVG, a data URI), which is more accurate than guessing
  /// `/favicon.ico` — and it is the only thing that works on sites behind a
  /// login, where the guess would come back as an HTML login page.
  static Future<Uint8List?> loadFromUrl(String host, String url) async {
    final key = host.trim().toLowerCase();
    if (key.isEmpty || url.isEmpty) return null;
    final cached = _cache[key];
    if (cached != null) return cached;
    // Bounded and quiet: a broken icon must never delay a page.
    try {
      final bytes = await _fetch(url: url).timeout(_timeout);
      if (bytes != null) _cache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetch({required String url}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request =
          await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        // Throw the body away; an unconsumed response leaks the connection.
        await response.drain<void>().catchError((Object _) {});
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        builder.add(chunk);
        if (builder.length > _maxBytes) return null;
      }
      final bytes = builder.takeBytes();
      return _looksLikeImage(bytes) ? bytes : null;
    } finally {
      client.close(force: true);
    }
  }

  /// Magic-number check. A server answering `text/html` for a favicon request
  /// is common; decoding that as an image wastes a render pass and logs noise.
  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // ICO
    if (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01) return true;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) return true;
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // WEBP: RIFF….WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return true;
    }
    // SVG: starts with '<', but so does an HTML error page, which is exactly
    // what a server returns for a missing favicon on many sites.
    if (bytes[0] == 0x3C) {
      final head = String.fromCharCodes(bytes.take(512));
      return head.contains('<svg') || head.contains('<SVG');
    }
    return false;
  }

  /// Test seam: forget everything.
  static void reset() {
    _cache.clear();
    _inflight.clear();
  }
}
