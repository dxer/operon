import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/agent_action.dart';
import '../models/page_signature.dart';

class DOMSnapshot {
  final String url;
  final String title;
  final int elementCount;
  final String textTree;
  final bool hasCaptcha;
  final String? captchaType;
  final int scrollPercent;
  final double totalScreens;
  final double currentScreen;
  final bool canScrollDown;
  final bool canScrollUp;

  DOMSnapshot({
    required this.url,
    required this.title,
    required this.elementCount,
    required this.textTree,
    this.hasCaptcha = false,
    this.captchaType,
    this.scrollPercent = 0,
    this.totalScreens = 1.0,
    this.currentScreen = 1.0,
    this.canScrollDown = false,
    this.canScrollUp = false,
  });

  factory DOMSnapshot.fromJson(Map<String, dynamic> json) {
    final captcha = json['captcha'] as Map<String, dynamic>?;
    final macro = json['macro'] as Map<String, dynamic>?;
    return DOMSnapshot(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      elementCount: json['elementCount'] ?? 0,
      textTree: json['text_tree'] ?? '',
      hasCaptcha: captcha?['hasCaptcha'] == true,
      captchaType: captcha?['type'] as String?,
      scrollPercent: (macro?['scrollPercent'] as num?)?.toInt() ?? 0,
      totalScreens: (macro?['totalScreens'] as num?)?.toDouble() ?? 1.0,
      currentScreen: (macro?['currentScreen'] as num?)?.toDouble() ?? 1.0,
      canScrollDown: macro?['canScrollDown'] == true,
      canScrollUp: macro?['canScrollUp'] == true,
    );
  }
}

class WebViewControllerWrapper {
  final InAppWebViewController controller;
  String? _cachedJsScript;

  static const Duration _scriptInjectionTimeout = Duration(seconds: 15);
  static const Duration _extractTimeout = Duration(seconds: 15);
  static const Duration _actionTimeout = Duration(seconds: 10);

  WebViewControllerWrapper(this.controller);

  /// Injects the core agent JS script if not already initialized
  Future<void> ensureScriptInjected() async {
    _cachedJsScript ??= await rootBundle.loadString('assets/js/agent_dom.js');

    await controller
        .evaluateJavascript(source: _cachedJsScript!)
        .timeout(_scriptInjectionTimeout);
  }

  /// Extracts the observable interactive DOM representation & key content
  Future<DOMSnapshot> extractPrunedDOM(
      {bool showBadges = true, bool includeContent = true}) async {
    await ensureScriptInjected();

    dynamic result;
    try {
      result = await controller
          .evaluateJavascript(
            source:
                'window.OPERON.extractPrunedDOM($showBadges, $includeContent);',
          )
          .timeout(_extractTimeout);
    } on TimeoutException {
      throw Exception('页面长时间无响应，无法读取 DOM（可尝试刷新页面）');
    }

    if (result == null) {
      throw Exception('无法从当前页面读取 DOM 状态');
    }

    final Map<String, dynamic> parsed = result is String
        ? jsonDecode(result)
        : Map<String, dynamic>.from(result);

    return DOMSnapshot.fromJson(parsed);
  }

  /// Executes an action via JavaScript injection or native controller
  Future<Map<String, dynamic>> executeAction(AgentAction action) async {
    if (action.action == ActionType.goBack) {
      if (await controller.canGoBack()) {
        await controller.goBack();
        return {'success': true, 'message': 'Go back triggered'};
      }
      return {'success': false, 'error': 'Cannot go back further'};
    }

    await ensureScriptInjected();

    final jsonPayload = jsonEncode(action.toJsPayload());
    dynamic result;
    try {
      result = await controller
          .evaluateJavascript(
            source: 'window.OPERON.executeAction($jsonPayload);',
          )
          .timeout(_actionTimeout);
    } on TimeoutException {
      return {
        'success': false,
        'error': '页面脚本执行超时（10 秒），可能页面卡死，请刷新后重试',
      };
    }

    if (result == null) {
      return {'success': false, 'error': 'No response from JS execution'};
    }

    if (result is String) {
      return jsonDecode(result) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(result);
  }

  /// Classifies the real DOM target before a sensitive action runs.
  Future<Map<String, dynamic>?> getElementRisk(int elementId) async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(
            source: 'window.OPERON.getElementRisk($elementId);',
          )
          .timeout(const Duration(seconds: 3));
      if (result == null) return null;
      if (result is String) {
        final decoded = jsonDecode(result);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('[WebView] getElementRisk failed: $e');
      return null;
    }
  }

  /// Resolves the replayable locator chain of an element the agent just used.
  ///
  /// Returns null when the element is gone or the page cannot answer; the
  /// caller must then skip recording rather than invent a selector.
  Future<Map<String, dynamic>?> getElementLocator(int elementId) async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(
            source: 'window.OPERON.getElementLocator($elementId);',
          )
          .timeout(const Duration(seconds: 3));
      if (result == null) return null;
      final decoded = result is String ? jsonDecode(result) : result;
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['ok'] != true || map['locator'] is! Map) return null;
      return map;
    } catch (e) {
      debugPrint('[WebView] getElementLocator failed: $e');
      return null;
    }
  }

  /// Waits dynamically until DOM mutations cease (stable rendering)
  Future<bool> waitForDomStable({int timeoutMs = 2500}) async {
    try {
      // Cap the whole operation: after a link click the old JS context can be
      // destroyed mid-call, and ensureScriptInjected could otherwise stall.
      final res = await Future(() async {
        await ensureScriptInjected();
        // `callAsyncJavaScript` runs the body inside an async function, so the
        // Promise returned by waitForDomStable is properly awaited on Android.
        return controller.callAsyncJavaScript(
          functionBody:
              'return await window.OPERON.waitForDomStable(timeoutMs);',
          arguments: {'timeoutMs': timeoutMs},
        );
      }).timeout(Duration(milliseconds: timeoutMs + 1500));
      return res?.value == true;
    } catch (_) {
      return false;
    }
  }

  /// Reads a cheap page fingerprint before/after an action.
  ///
  /// Returns null when the page is navigating or the script is unavailable, so
  /// callers can fall back to URL comparison instead of treating that as "no
  /// change".
  Future<PageSignature?> tryGetPageSignature() async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(source: 'window.OPERON.getPageSignature();')
          .timeout(const Duration(seconds: 5));
      if (result == null) return null;
      final decoded = result is String ? jsonDecode(result) : result;
      if (decoded is! Map) return null;
      return PageSignature.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Removes all floating number badges and highlights
  Future<void> clearHighlights() async {
    try {
      await controller.evaluateJavascript(
        source: 'if (window.OPERON) { window.OPERON.clearHighlights(); }',
      );
    } catch (_) {}
  }

  /// Reloads the current document.
  Future<void> reload() async {
    await controller.reload();
  }

  /// Gets current URL
  Future<String> getUrl() async {
    final uri = await controller.getUrl();
    return uri?.toString() ?? '';
  }

  /// Gets current page title
  Future<String> getTitle() async {
    return await controller.getTitle() ?? '';
  }

  /// Removes mobile app-jump banners, modal masks, and auto-expands collapsed articles
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

  /// Extracts readable article content and metadata for AI summarization
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

  /// Executes arbitrary JavaScript in the current page
  Future<dynamic> evaluateJavascript(String source) async {
    try {
      return await controller
          .evaluateJavascript(source: source)
          .timeout(_scriptInjectionTimeout);
    } catch (e) {
      debugPrint('[WebView] evaluateJavascript error: $e');
      return null;
    }
  }

  /// Resolves a skill locator candidate chain to a temporary element id.
  Future<Map<String, dynamic>> resolveLocator(
    Map<String, dynamic> locator,
  ) async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(
            source: 'window.OPERON.resolveLocator(${jsonEncode(locator)});',
          )
          .timeout(const Duration(seconds: 5));
      return _decodeMap(result) ??
          {'found': false, 'error': 'EMPTY_LOCATOR_RESULT'};
    } catch (e) {
      return {'found': false, 'error': e.toString()};
    }
  }

  /// Lets the user tap an element and returns a locator candidate chain.
  Future<Map<String, dynamic>> pickLocator({
    int timeoutMs = 60000,
  }) async {
    try {
      await ensureScriptInjected();
      final result = await controller.callAsyncJavaScript(
        functionBody: 'return await window.OPERON.pickLocator(timeoutMs);',
        arguments: {'timeoutMs': timeoutMs},
      ).timeout(Duration(milliseconds: timeoutMs + 3000));
      return _decodeMap(result?.value) ??
          {'ok': false, 'error': 'EMPTY_PICKER_RESULT'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Returns labels of visible interactive elements, never their values.
  Future<List<Map<String, dynamic>>> getInteractiveSummary({
    int maxItems = 60,
  }) async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(
            source: 'window.OPERON.interactiveSummary($maxItems);',
          )
          .timeout(const Duration(seconds: 5));
      final decoded = result is String ? jsonDecode(result) : result;
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Cancels an in-flight locator picker overlay.
  Future<void> cancelLocatorPicker() async {
    try {
      await ensureScriptInjected();
      await controller.evaluateJavascript(
        source: 'window.OPERON.cancelLocatorPicker();',
      );
    } catch (_) {}
  }

  /// Reads a page region using a skill locator.
  Future<Map<String, dynamic>> readRegion(
    Map<String, dynamic> locator, {
    String mode = 'text',
    int limit = 20,
    int maxChars = 12000,
    Map<String, dynamic>? itemLocator,
    Map<String, dynamic>? fields,
  }) async {
    try {
      await ensureScriptInjected();
      final options = <String, dynamic>{
        'mode': mode,
        'limit': limit,
        'maxChars': maxChars,
        if (itemLocator != null) 'itemLocator': itemLocator,
        if (fields != null) 'fields': fields,
      };
      final result = await controller
          .evaluateJavascript(
            source:
                'window.OPERON.readRegion(${jsonEncode(locator)}, ${jsonEncode(options)});',
          )
          .timeout(const Duration(seconds: 15));
      return _decodeMap(result) ?? {'ok': false, 'error': 'EMPTY_READ_RESULT'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Waits until a locator is visible/hidden.
  Future<Map<String, dynamic>> waitForLocator(
    Map<String, dynamic> locator, {
    int timeoutMs = 10000,
    String state = 'visible',
  }) async {
    try {
      await ensureScriptInjected();
      final result = await controller.callAsyncJavaScript(
        functionBody:
            'return await window.OPERON.waitForLocator(locatorJson, timeoutMs, state);',
        arguments: {
          'locatorJson': jsonEncode(locator),
          'timeoutMs': timeoutMs,
          'state': state,
        },
      ).timeout(Duration(milliseconds: timeoutMs + 2000));
      return _decodeMap(result?.value) ??
          {'ok': false, 'error': 'EMPTY_WAIT_RESULT'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Scrolls a resolved locator into view.
  Future<Map<String, dynamic>> scrollToLocator(
    Map<String, dynamic> locator, {
    String align = 'center',
  }) async {
    try {
      await ensureScriptInjected();
      final result = await controller
          .evaluateJavascript(
            source:
                'window.OPERON.scrollToLocator(${jsonEncode(locator)}, ${jsonEncode(align)});',
          )
          .timeout(const Duration(seconds: 5));
      return _decodeMap(result) ??
          {'ok': false, 'error': 'EMPTY_SCROLL_RESULT'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
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

  /// Gets currently selected text info on the page
  Future<Map<String, dynamic>> getSelectedTextInfo() async {
    try {
      await ensureScriptInjected();
      final res = await controller
          .evaluateJavascript(
            source:
                'if (window.OPERON && window.OPERON.getSelectedTextInfo) { window.OPERON.getSelectedTextInfo(); }',
          )
          .timeout(const Duration(seconds: 3));
      if (res != null) {
        return res is String ? jsonDecode(res) : Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {'hasSelection': false};
  }
}
