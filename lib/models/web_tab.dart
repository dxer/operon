import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/webview_controller_wrapper.dart';

class WebTab {
  final String id;
  String url;
  String title;
  InAppWebViewController? controller;
  WebViewControllerWrapper? wrapper;
  bool isLoading;
  double progress;
  bool canGoBack;
  bool canGoForward;
  bool isDesktopMode;
  bool isCleanMode;
  String? errorMessage;

  WebTab({
    required this.id,
    required this.url,
    this.title = '新标签页',
    this.controller,
    this.wrapper,
    this.isLoading = false,
    this.progress = 0.0,
    this.canGoBack = false,
    this.canGoForward = false,
    this.isDesktopMode = false,
    this.isCleanMode = false,
    this.errorMessage,
  });

  WebTab copyWith({
    String? id,
    String? url,
    String? title,
    InAppWebViewController? controller,
    WebViewControllerWrapper? wrapper,
    bool? isLoading,
    double? progress,
    bool? canGoBack,
    bool? canGoForward,
    bool? isDesktopMode,
    bool? isCleanMode,
    String? errorMessage,
  }) {
    return WebTab(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      controller: controller ?? this.controller,
      wrapper: wrapper ?? this.wrapper,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      isDesktopMode: isDesktopMode ?? this.isDesktopMode,
      isCleanMode: isCleanMode ?? this.isCleanMode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
