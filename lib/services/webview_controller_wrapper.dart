import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/agent_action.dart';

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

  WebViewControllerWrapper(this.controller);

  /// Injects the core agent JS script if not already initialized
  Future<void> ensureScriptInjected() async {
    _cachedJsScript ??= await rootBundle.loadString('assets/js/agent_dom.js');

    await controller.evaluateJavascript(source: _cachedJsScript!);
  }

  /// Extracts the observable interactive DOM representation & key content
  Future<DOMSnapshot> extractPrunedDOM({bool showBadges = true, bool includeContent = true}) async {
    await ensureScriptInjected();

    final result = await controller.evaluateJavascript(
      source: 'window.OPERON.extractPrunedDOM($showBadges, $includeContent);',
    );

    if (result == null) {
      throw Exception('无法从当前页面读取 DOM 状态');
    }

    final Map<String, dynamic> parsed =
        result is String ? jsonDecode(result) : Map<String, dynamic>.from(result);

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
    final result = await controller.evaluateJavascript(
      source: 'window.OPERON.executeAction($jsonPayload);',
    );

    if (result == null) {
      return {'success': false, 'error': 'No response from JS execution'};
    }

    if (result is String) {
      return jsonDecode(result) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(result);
  }

  /// Captures current viewport screenshot as PNG bytes for Vision Fallback
  Future<Uint8List?> takeScreenshot() async {
    try {
      return await controller.takeScreenshot();
    } catch (_) {
      return null;
    }
  }

  /// Waits dynamically until DOM mutations cease (stable rendering)
  Future<bool> waitForDomStable({int timeoutMs = 2500}) async {
    try {
      await ensureScriptInjected();
      final res = await controller.evaluateJavascript(
        source: 'await window.OPERON.waitForDomStable($timeoutMs);',
      );
      return res == true;
    } catch (_) {
      return false;
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
      final res = await controller.evaluateJavascript(
        source: 'if (window.OPERON && window.OPERON.cleanPageMode) { window.OPERON.cleanPageMode(); }',
      );
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
      final res = await controller.evaluateJavascript(
        source: 'if (window.OPERON && window.OPERON.extractReadableContent) { window.OPERON.extractReadableContent(); }',
      );
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
      return await controller.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('[WebView] evaluateJavascript error: $e');
      return null;
    }
  }

  /// Gets currently selected text info on the page
  Future<Map<String, dynamic>> getSelectedTextInfo() async {
    try {
      await ensureScriptInjected();
      final res = await controller.evaluateJavascript(
        source: 'if (window.OPERON && window.OPERON.getSelectedTextInfo) { window.OPERON.getSelectedTextInfo(); }',
      );
      if (res != null) {
        return res is String ? jsonDecode(res) : Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {'hasSelection': false};
  }
}
