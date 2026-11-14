import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The WebView as the browser itself needs it.
///
/// Reading a page for an agent and acting on one moved to the control layer,
/// which speaks the DevTools protocol; what stays here is what the UI does with
/// its own WebView: inject the page helpers, draw the gesture overlay, and run
/// the reading-mode and selection helpers.
class WebViewControllerWrapper {
  WebViewControllerWrapper(this.controller);

  final InAppWebViewController controller;

  /// The page helpers, injected once per document.
  String? _cachedJsScript;

  static const Duration _scriptInjectionTimeout = Duration(seconds: 15);
  static const Duration _extractTimeout = Duration(seconds: 15);

  /// Injects `assets/js/page_helpers.js`, once per document.
  Future<void> ensureScriptInjected() async {
    try {
      final injected = await controller.evaluateJavascript(
        source: 'Boolean(window.OPERON && window.OPERON.version === "0.4.0")',
      );
      if (injected == true || '$injected' == 'true') return;

      _cachedJsScript ??= await rootBundle.loadString('assets/js/page_helpers.js');
      await controller
          .evaluateJavascript(source: _cachedJsScript!)
          .timeout(_scriptInjectionTimeout);
    } catch (error) {
      debugPrint('[WebView] script injection failed: $error');
    }
  }

  /// Reloads the current document.
  Future<void> reload() async {
    await controller.reload();
  }

  /// The page's current zoom, so a CSS pixel can become a logical pixel.
  Future<double> getScale() async {
    try {
      return await controller.getZoomScale() ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  /// Gets the current URL.
  Future<String> getUrl() async {
    final uri = await controller.getUrl();
    return uri?.toString() ?? '';
  }

  /// Gets the current page title.
  Future<String> getTitle() async {
    return await controller.getTitle() ?? '';
  }

  /// Removes app-jump banners and modal masks, and re-expands collapsed bodies.
  Future<Map<String, dynamic>> cleanPageMode() async {
    try {
      await ensureScriptInjected();
      final res = await controller
          .evaluateJavascript(
            source:
                'if (window.OPERON && window.OPERON.cleanPageMode) { window.OPERON.cleanPageMode(); }',
          )
          .timeout(_extractTimeout);
      if (res != null) {
        return res is String ? jsonDecode(res) : Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {'success': false};
  }

  /// Extracts readable article content and metadata, for the summary sheet.
  Future<Map<String, dynamic>> extractReadableContent() async {
    try {
      await ensureScriptInjected();
      final res = await controller
          .evaluateJavascript(
            source:
                'if (window.OPERON && window.OPERON.extractReadableContent) { window.OPERON.extractReadableContent(); }',
          )
          .timeout(_extractTimeout);
      if (res != null) {
        return res is String ? jsonDecode(res) : Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {
      'title': await getTitle(),
      'url': await getUrl(),
      'content': '',
      'length': 0,
    };
  }

  /// Runs JavaScript in the page.
  ///
  /// Used by the reading-mode and selection features only; the control layer
  /// has its own channel and does not go through here.
  Future<dynamic> evaluateJavascript(String source) async {
    try {
      return await controller
          .evaluateJavascript(source: source)
          .timeout(_scriptInjectionTimeout);
    } catch (error) {
      debugPrint('[WebView] evaluateJavascript error: $error');
      return null;
    }
  }

  /// Gets the current selection and where it sits on screen.
  Future<Map<String, dynamic>> getSelectedTextInfo() async {
    try {
      await ensureScriptInjected();
      final res = await controller
          .evaluateJavascript(
            source:
                'if (window.OPERON && window.OPERON.getSelectedTextInfo) { window.OPERON.getSelectedTextInfo(); }',
          )
          .timeout(const Duration(seconds: 3));
      final decoded = _decodeMap(res);
      if (decoded != null) return decoded;
    } catch (_) {}
    return {'hasSelection': false};
  }

  dynamic _decodeMap(dynamic result) {
    if (result == null) return null;
    if (result is String) {
      final decoded = jsonDecode(result);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }
}
