import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/webview_controller_wrapper.dart';

class WebTab {
  final String id;
  String url;
  String title;
  InAppWebViewController? controller;
  WebViewControllerWrapper? wrapper;
  PullToRefreshController? pullToRefresh;
  FindInteractionController? findController;
  bool isLoading;
  double progress;
  bool canGoBack;
  bool canGoForward;
  bool isDesktopMode;
  bool isCleanMode;
  bool isIncognito;
  int? windowId;
  String? errorMessage;

  WebTab({
    required this.id,
    required this.url,
    this.title = '新标签页',
    this.controller,
    this.wrapper,
    this.pullToRefresh,
    this.findController,
    this.isLoading = false,
    this.progress = 0.0,
    this.canGoBack = false,
    this.canGoForward = false,
    this.isDesktopMode = false,
    this.isCleanMode = false,
    this.isIncognito = false,
    this.windowId,
    this.errorMessage,
  });

  WebTab copyWith({
    String? id,
    String? url,
    String? title,
    InAppWebViewController? controller,
    WebViewControllerWrapper? wrapper,
    PullToRefreshController? pullToRefresh,
    FindInteractionController? findController,
    bool? isLoading,
    double? progress,
    bool? canGoBack,
    bool? canGoForward,
    bool? isDesktopMode,
    bool? isCleanMode,
    bool? isIncognito,
    int? windowId,
    String? errorMessage,
  }) {
    return WebTab(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      controller: controller ?? this.controller,
      wrapper: wrapper ?? this.wrapper,
      pullToRefresh: pullToRefresh ?? this.pullToRefresh,
      findController: findController ?? this.findController,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      isDesktopMode: isDesktopMode ?? this.isDesktopMode,
      isCleanMode: isCleanMode ?? this.isCleanMode,
      isIncognito: isIncognito ?? this.isIncognito,
      windowId: windowId ?? this.windowId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
