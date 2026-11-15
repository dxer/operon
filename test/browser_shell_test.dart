import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/bookmark_item.dart';
import 'package:operon/models/history_item.dart';
import 'package:operon/views/widgets/bottom_toolbar.dart';
import 'package:operon/views/widgets/browser_controls.dart';
import 'package:operon/views/widgets/find_in_page_bar.dart';
import 'package:operon/views/widgets/omnibox_suggestions.dart';

void main() {
  group('omnibox suggestions', () {
    test('puts valid clipboard URL first and deduplicates bookmarks & history',
        () {
      final results = buildOmniboxSuggestions(
        query: '',
        clipboardUrl: 'https://news.ycombinator.com/item?id=1',
        bookmarks: [
          BookmarkItem(
            id: 'b1',
            url: 'https://github.com/trending',
            title: 'GitHub Trending',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        history: [
          HistoryItem(
            id: 'h1',
            url: 'https://github.com/trending',
            title: 'GitHub Trending',
            visitedAt: DateTime(2026, 1, 2),
          ),
          HistoryItem(
            id: 'h2',
            url: 'https://news.ycombinator.com/item?id=1',
            title: 'HN Item',
            visitedAt: DateTime(2026, 1, 2),
          ),
          HistoryItem(
            id: 'h3',
            url: 'https://example.com/docs',
            title: 'Example Docs',
            visitedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

      expect(results.first.kind, OmniboxSuggestionKind.clipboard);
      expect(results.first.url, 'https://news.ycombinator.com/item?id=1');
      final urls = results.map((r) => r.url).toList();
      expect(urls, [
        'https://news.ycombinator.com/item?id=1',
        'https://github.com/trending',
        'https://example.com/docs',
      ]);
    });

    test('filters by query and appends direct search/go suggestion', () {
      final results = buildOmniboxSuggestions(
        query: 'flutter',
        bookmarks: [
          BookmarkItem(
            id: 'b1',
            url: 'https://flutter.dev',
            title: 'Flutter Docs',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        history: [
          HistoryItem(
            id: 'h1',
            url: 'https://dart.dev',
            title: 'Dart',
            visitedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

      expect(results.length, 2);
      expect(results[0].kind, OmniboxSuggestionKind.bookmark);
      expect(results[1].kind, OmniboxSuggestionKind.search);
      expect(results[1].title, '前往或搜索「flutter」');
    });
  });

  group('browser controls reading title & refresh action', () {
    testWidgets('shows page title while reading and switches to URL when focused',
        (tester) async {
      final controller =
          TextEditingController(text: 'https://github.com/flutter/flutter');
      addTearDown(controller.dispose);
      var reloaded = 0;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: BrowserControls(
            urlController: controller,
            pageTitle: 'Flutter SDK · GitHub',
            isLoading: false,
            progress: 1.0,
            onSubmitUrl: (_) {},
            onReload: () => reloaded++,
            onStopLoad: () {},
            onSummarize: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Flutter SDK · GitHub'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新页面'));
      expect(reloaded, 1);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Flutter SDK · GitHub'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows stop action when loading', (tester) async {
      final controller = TextEditingController(text: 'https://example.com');
      addTearDown(controller.dispose);
      var stopped = 0;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: BrowserControls(
            urlController: controller,
            isLoading: true,
            progress: 0.4,
            onSubmitUrl: (_) {},
            onReload: () {},
            onStopLoad: () => stopped++,
            onSummarize: () {},
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('停止加载'));
      expect(stopped, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('bottom toolbar swipe & long press gestures', () {
    Widget wrapBar({
      int tabCount = 3,
      VoidCallback? onPreviousTab,
      VoidCallback? onNextTab,
      VoidCallback? onLongPressTabs,
      VoidCallback? onLongPressHome,
      VoidCallback? onFindInPage,
    }) {
      return MaterialApp(
        theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BottomToolbar(
              canGoBack: true,
              canGoForward: false,
              isLoading: false,
              tabCount: tabCount,
              isBookmarked: false,
              isDesktopMode: false,
              isCleanMode: false,
              onBack: () {},
              onForward: () {},
              onHome: () {},
              onOpenTabs: () {},
              onPreviousTab: onPreviousTab,
              onNextTab: onNextTab,
              onLongPressTabs: onLongPressTabs,
              onLongPressHome: onLongPressHome,
              onReload: () {},
              onStopLoad: () {},
              onNewTab: () {},
              onFindInPage: onFindInPage,
              onSummarize: () {},
              onCleanPage: () {},
              onToggleBookmark: () {},
              onOpenHistory: () {},
              onOpenBookmarks: () {},
              onToggleDesktopMode: () {},
              onOpenSettings: () {},
              currentUrl: 'https://example.com',
            ),
          ),
        ),
      );
    }

    testWidgets('horizontal drag switches tabs and long press creates new tab',
        (tester) async {
      var prev = 0;
      var next = 0;
      var newTab = 0;
      var bookmarks = 0;

      await tester.pumpWidget(wrapBar(
        onPreviousTab: () => prev++,
        onNextTab: () => next++,
        onLongPressTabs: () => newTab++,
        onLongPressHome: () => bookmarks++,
      ));

      await tester.fling(find.byType(BottomToolbar), const Offset(-120, 0), 800);
      await tester.pump();
      expect(next, 1);

      await tester.fling(find.byType(BottomToolbar), const Offset(120, 0), 800);
      await tester.pump();
      expect(prev, 1);

      await tester.longPress(find.text('3'));
      await tester.pump();
      expect(newTab, 1);

      await tester.longPress(find.byIcon(Icons.home_outlined));
      await tester.pump();
      expect(bookmarks, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('menu exposes find-in-page action', (tester) async {
      var findOpened = 0;
      await tester.pumpWidget(wrapBar(onFindInPage: () => findOpened++));

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('页内查找'), findsOneWidget);
      await tester.tap(find.text('页内查找'));
      await tester.pumpAndSettle();
      expect(findOpened, 1);
    });
  });

  group('find in page bar', () {
    testWidgets('displays match count and navigates results', (tester) async {
      final controller = TextEditingController(text: 'flutter');
      addTearDown(controller.dispose);
      var prev = 0;
      var next = 0;
      var closed = 0;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: FindInPageBar(
            controller: controller,
            activeMatch: 1,
            totalMatches: 5,
            onQueryChanged: (_) {},
            onPrevious: () => prev++,
            onNext: () => next++,
            onClose: () => closed++,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('2/5'), findsOneWidget);
      await tester.tap(find.byTooltip('上一个'));
      await tester.tap(find.byTooltip('下一个'));
      await tester.tap(find.byTooltip('关闭查找'));
      expect(prev, 1);
      expect(next, 1);
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
