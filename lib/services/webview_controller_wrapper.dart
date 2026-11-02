import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/agent_action.dart';

class DOMSnapshot {
  final String url;
  final String title;
  final int elementCount;
  final String textTree;

  DOMSnapshot({
    required this.url,
    required this.title,
    required this.elementCount,
    required this.textTree,
  });

  factory DOMSnapshot.fromJson(Map<String, dynamic> json) {
    return DOMSnapshot(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      elementCount: json['elementCount'] ?? 0,
      textTree: json['text_tree'] ?? '',
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
      source: 'window.BBX_AGENT.extractPrunedDOM($showBadges, $includeContent);',
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
      source: 'window.BBX_AGENT.executeAction($jsonPayload);',
    );

    if (result == null) {
      return {'success': false, 'error': 'No response from JS execution'};
    }

    if (result is String) {
      return jsonDecode(result) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(result);
  }

  /// Waits dynamically until DOM mutations cease (stable rendering)
  Future<bool> waitForDomStable({int timeoutMs = 2500}) async {
    try {
      await ensureScriptInjected();
      final res = await controller.evaluateJavascript(
        source: 'await window.BBX_AGENT.waitForDomStable($timeoutMs);',
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
        source: 'if (window.BBX_AGENT) { window.BBX_AGENT.clearHighlights(); }',
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
}
