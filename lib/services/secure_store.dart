import 'dart:io';

import 'package:flutter/services.dart';

/// Stores sensitive secrets (such as LLM API keys) via the Android Keystore
/// channel (`operon/secure_storage`).
///
/// Disabled automatically outside live Android builds (e.g., Flutter unit/widget
/// tests on desktop hosts) so tests run without platform bindings or hanging
/// binary-messenger calls, unless [forceSupportedForTest] is set.
class SecureStore {
  SecureStore({
    MethodChannel? channel,
    bool forceSupportedForTest = false,
  })  : _channel = channel ?? const MethodChannel('operon/secure_storage'),
        _supported = forceSupportedForTest ||
            (Platform.isAndroid &&
                !Platform.environment.containsKey('FLUTTER_TEST'));

  static final SecureStore instance = SecureStore();

  final MethodChannel _channel;
  bool _supported;

  bool get isSupported => _supported;

  Future<String?> read(String key) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('read', {'key': key});
    } on MissingPluginException {
      _supported = false;
      return null;
    } on PlatformException {
      return null;
    } on AssertionError {
      _supported = false;
      return null;
    }
  }

  Future<bool> write(String key, String value) async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('write', {
        'key': key,
        'value': value,
      });
      return ok ?? true;
    } on MissingPluginException {
      _supported = false;
      return false;
    } on PlatformException {
      return false;
    } on AssertionError {
      _supported = false;
      return false;
    }
  }

  Future<bool> delete(String key) async {
    if (!_supported) return false;
    try {
      await _channel.invokeMethod<bool>('delete', {'key': key});
      return true;
    } on MissingPluginException {
      _supported = false;
      return false;
    } on PlatformException {
      return false;
    } on AssertionError {
      _supported = false;
      return false;
    }
  }
}
