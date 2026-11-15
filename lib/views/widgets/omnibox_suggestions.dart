import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/bookmark_item.dart';
import '../../models/history_item.dart';
import '../../services/haptic_service.dart';
import '../../utils/url_utils.dart';
import 'site_icon.dart';

enum OmniboxSuggestionKind { clipboard, bookmark, history, search }

class OmniboxSuggestion {
  const OmniboxSuggestion({
    required this.kind,
    required this.title,
    required this.url,
    this.subtitle = '',
  });

  final OmniboxSuggestionKind kind;
  final String title;
  final String url;
  final String subtitle;
}

/// Extracts a clean single-line HTTP(S) URL from clipboard text, if present.
String? extractClipboardWebUrl(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.contains('\n') || trimmed.contains(' ')) {
    return null;
  }
  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  return trimmed;
}

/// Builds deduplicated omnibox suggestions from clipboard, bookmarks, history,
/// and the typed query itself.
List<OmniboxSuggestion> buildOmniboxSuggestions({
  required String query,
  required List<BookmarkItem> bookmarks,
  required List<HistoryItem> history,
  String? clipboardUrl,
  String? currentUrl,
  int maxMatches = 5,
}) {
  final trimmed = query.trim();
  final q = trimmed.toLowerCase();
  final results = <OmniboxSuggestion>[];
  final seenUrls = <String>{};

  final clip = extractClipboardWebUrl(clipboardUrl);
  if (clip != null &&
      clip != currentUrl &&
      (q.isEmpty || clip.toLowerCase().contains(q))) {
    seenUrls.add(clip);
    results.add(OmniboxSuggestion(
      kind: OmniboxSuggestionKind.clipboard,
      title: '粘贴并前往剪贴板链接',
      url: clip,
      subtitle: clip,
    ));
  }

  var matchCount = 0;
  for (final bookmark in bookmarks) {
    if (matchCount >= maxMatches) break;
    if (seenUrls.contains(bookmark.url)) continue;
    final matches = q.isEmpty ||
        bookmark.title.toLowerCase().contains(q) ||
        bookmark.url.toLowerCase().contains(q);
    if (!matches) continue;
    seenUrls.add(bookmark.url);
    matchCount++;
    results.add(OmniboxSuggestion(
      kind: OmniboxSuggestionKind.bookmark,
      title: bookmark.title.isNotEmpty ? bookmark.title : hostOf(bookmark.url),
      url: bookmark.url,
      subtitle: bookmark.url,
    ));
  }

  for (final item in history) {
    if (matchCount >= maxMatches) break;
    if (seenUrls.contains(item.url)) continue;
    final matches = q.isEmpty ||
        item.title.toLowerCase().contains(q) ||
        item.url.toLowerCase().contains(q);
    if (!matches) continue;
    seenUrls.add(item.url);
    matchCount++;
    results.add(OmniboxSuggestion(
      kind: OmniboxSuggestionKind.history,
      title: item.title.isNotEmpty ? item.title : hostOf(item.url),
      url: item.url,
      subtitle: item.url,
    ));
  }

  if (trimmed.isNotEmpty) {
    results.add(OmniboxSuggestion(
      kind: OmniboxSuggestionKind.search,
      title: '前往或搜索「$trimmed」',
      url: trimmed,
    ));
  }

  return results;
}

/// Compact suggestion list displayed under the address bar or start-page box.
class OmniboxSuggestionsPanel extends StatelessWidget {
  const OmniboxSuggestionsPanel({
    super.key,
    required this.suggestions,
    required this.onSelect,
    this.onFillQuery,
  });

  final List<OmniboxSuggestion> suggestions;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onFillQuery;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: AppInk.raised(isDark),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: AppInk.hairline(isDark),
          width: AppStroke.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => Divider(
            height: AppStroke.hairline,
            thickness: AppStroke.hairline,
            indent: 48,
            color: AppInk.hairline(isDark),
          ),
          itemBuilder: (context, index) {
            final item = suggestions[index];
            return _SuggestionRow(
              item: item,
              isDark: isDark,
              onTap: () {
                HapticService.selection();
                onSelect(item.url);
              },
              onFill: onFillQuery == null ||
                      item.kind == OmniboxSuggestionKind.search
                  ? null
                  : () {
                      HapticService.selection();
                      onFillQuery!(item.url);
                    },
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.item,
    required this.isDark,
    required this.onTap,
    this.onFill,
  });

  final OmniboxSuggestion item;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onFill;

  @override
  Widget build(BuildContext context) {
    final host = hostOf(item.url);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x3,
          AppSpace.x2,
          AppSpace.x1,
          AppSpace.x2,
        ),
        child: Row(
          children: [
            _buildLeading(host),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(
                      color: item.kind == OmniboxSuggestionKind.clipboard ||
                              item.kind == OmniboxSuggestionKind.search
                          ? AppTheme.primaryOf(isDark)
                          : AppInk.primary(isDark),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppInk.tertiary(isDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onFill != null)
              IconButton(
                tooltip: '填入输入栏',
                onPressed: onFill,
                icon: Icon(
                  Icons.north_west_rounded,
                  size: 16,
                  color: AppInk.tertiary(isDark),
                ),
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                padding: EdgeInsets.zero,
              )
            else
              const SizedBox(width: AppSpace.x2),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(String host) {
    return switch (item.kind) {
      OmniboxSuggestionKind.clipboard => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppInk.accentTint(isDark),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(
            Icons.content_paste_go_rounded,
            size: 15,
            color: AppTheme.primaryOf(isDark),
          ),
        ),
      OmniboxSuggestionKind.bookmark => Stack(
          clipBehavior: Clip.none,
          children: [
            SiteIcon(host: host, size: 28, label: item.title),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: AppInk.raised(isDark),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_rounded,
                  size: 10,
                  color: AppTheme.warningOf(isDark),
                ),
              ),
            ),
          ],
        ),
      OmniboxSuggestionKind.history => SiteIcon(
          host: host,
          size: 28,
          label: item.title,
        ),
      OmniboxSuggestionKind.search => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppInk.sunken(isDark),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(
            Icons.search_rounded,
            size: 15,
            color: AppInk.secondary(isDark),
          ),
        ),
    };
  }
}
