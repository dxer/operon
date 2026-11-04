import 'dart:async';
import 'package:flutter/services.dart';

/// Bridges Android share/`VIEW` intents into the running app.
///
/// The native side sends the raw shared text (never a parsed URL) so all the
/// parsing rules live in one testable place: `extractSharedUrl`.
class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();
  static const MethodChannel channel = MethodChannel('operon/share');

  final StreamController<String> _links = StreamController<String>.broadcast();
  bool _initialized = false;

  /// Raw text of every share that arrived while the app was already running.
  Stream<String> get links => _links.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) {
        _links.add(call.arguments as String);
      }
      return null;
    });
  }

  /// Text from the intent that cold-started the app. The native side clears it
  /// after reading, so a hot restart cannot replay an old share.
  Future<String?> takeInitialLink() async {
    try {
      return await channel.invokeMethod<String>('initialShared');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Desktop/web builds have no native handler; sharing is Android-only.
      return null;
    }
  }

  /// Opens the system share sheet with [text].
  ///
  /// Returns false when nothing was shared: an empty string, or a platform
  /// without the native handler (desktop/web). Callers show their own feedback.
  Future<bool> shareText(String text) async {
    final value = text.trim();
    if (value.isEmpty) return false;
    try {
      final ok = await channel.invokeMethod<bool>(
        'shareText',
        {'text': value},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
