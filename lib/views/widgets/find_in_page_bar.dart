import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';

/// Compact Via-style find-in-page bar sitting at the top of the browser shell.
class FindInPageBar extends StatelessWidget {
  const FindInPageBar({
    super.key,
    required this.controller,
    required this.activeMatch,
    required this.totalMatches,
    required this.onQueryChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final int activeMatch;
  final int totalMatches;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final hasQuery = controller.text.isNotEmpty;
    final countLabel = !hasQuery
        ? ''
        : totalMatches <= 0
            ? '0/0'
            : '${activeMatch + 1}/$totalMatches';

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          bottom: BorderSide(
            color: AppInk.hairline(isDark),
            width: AppStroke.hairline,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.x3,
            AppSpace.x1 + 2,
            AppSpace.x2,
            AppSpace.x1 + 2,
          ),
          child: Container(
            height: AppSpace.tap,
            decoration: BoxDecoration(
              color: AppInk.sunken(isDark),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            padding: const EdgeInsets.only(left: AppSpace.x3, right: AppSpace.x1),
            child: Row(
              children: [
                Icon(
                  Icons.find_in_page_outlined,
                  size: 16,
                  color: AppInk.tertiary(isDark),
                ),
                const SizedBox(width: AppSpace.x2),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    style: AppType.body.copyWith(color: AppInk.primary(isDark)),
                    cursorColor: AppTheme.primaryOf(isDark),
                    textInputAction: TextInputAction.search,
                    decoration: AppTheme.flatInput.copyWith(
                      hintText: '在网页中查找…',
                      hintStyle: AppType.label.copyWith(
                        color: AppInk.tertiary(isDark),
                      ),
                    ),
                    onChanged: onQueryChanged,
                    onSubmitted: (_) => onNext(),
                  ),
                ),
                if (countLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
                    child: Text(
                      countLabel,
                      style: AppType.caption.copyWith(
                        color: totalMatches > 0
                            ? AppInk.secondary(isDark)
                            : AppTheme.dangerOf(isDark),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '上一个',
                  icon: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: totalMatches > 0
                        ? AppInk.secondary(isDark)
                        : AppInk.tertiary(isDark).withValues(alpha: 0.4),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: totalMatches > 0
                      ? () {
                          HapticService.selection();
                          onPrevious();
                        }
                      : null,
                ),
                IconButton(
                  tooltip: '下一个',
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: totalMatches > 0
                        ? AppInk.secondary(isDark)
                        : AppInk.tertiary(isDark).withValues(alpha: 0.4),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: totalMatches > 0
                      ? () {
                          HapticService.selection();
                          onNext();
                        }
                      : null,
                ),
                IconButton(
                  tooltip: '关闭查找',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppInk.secondary(isDark),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {
                    HapticService.selection();
                    onClose();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
