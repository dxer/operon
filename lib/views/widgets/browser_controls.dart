import 'package:flutter/material.dart';
import '../../config/app_theme.dart';

class BrowserControls extends StatelessWidget {
  final TextEditingController urlController;
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final Function(String url) onSubmitUrl;
  final VoidCallback onOpenSettings;

  const BrowserControls({
    Key? key,
    required this.urlController,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.progress,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onSubmitUrl,
    required this.onOpenSettings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: canGoBack ? Colors.white : Colors.white24,
                    onPressed: canGoBack ? onBack : null,
                    tooltip: '后退',
                  ),
                  // Forward button
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    color: canGoForward ? Colors.white : Colors.white24,
                    onPressed: canGoForward ? onForward : null,
                    tooltip: '前进',
                  ),
                  // Reload button
                  IconButton(
                    icon: Icon(
                      isLoading ? Icons.close : Icons.refresh,
                      size: 20,
                    ),
                    color: Colors.white70,
                    onPressed: onReload,
                    tooltip: isLoading ? '停止加载' : '刷新',
                  ),
                  // URL / Search input
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202327),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          const Icon(Icons.lock_outline, size: 14, color: AppTheme.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: urlController,
                              style: const TextStyle(fontSize: 13, color: Colors.white),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: '输入网址或搜索...',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.white38),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.go,
                              onSubmitted: onSubmitUrl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Settings button
                  IconButton(
                    icon: const Icon(Icons.tune_outlined, size: 20),
                    color: Colors.white70,
                    onPressed: onOpenSettings,
                    tooltip: '模型与浏览器设置',
                  ),
                ],
              ),
            ),
            // Linear loading indicator
            if (isLoading && progress < 1.0)
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
