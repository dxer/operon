import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/services/favicon_service.dart';
import 'package:operon/views/widgets/operon_list_row.dart';
import 'package:operon/views/widgets/site_icon.dart';
import 'package:operon/views/widgets/step_log_view.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(FaviconService.reset);

  group('the timeline', () {
    testWidgets('labels each kind instead of showing bare text',
        (tester) async {
      await tester.pumpWidget(_host(StepLogView(logs: [
        AgentLogItem(step: 0, title: '先看列表里有几个仓库', kind: LogKind.thought),
        AgentLogItem(step: 1, title: '点击「Star」', kind: LogKind.action),
        AgentLogItem(step: 1, title: '已 star', kind: LogKind.result),
      ])));
      await tester.pump();

      expect(find.text('思考'), findsOneWidget);
      expect(find.text('动作'), findsOneWidget);
      expect(find.text('结果'), findsOneWidget);
      // Step counts are no longer displayed on action rows.
      expect(find.text('第 1 步'), findsNothing);
    });

    testWidgets('a running action says so without inventing a result',
        (tester) async {
      await tester.pumpWidget(_host(StepLogView(logs: [
        AgentLogItem(step: 1, title: '点击「Star」', kind: LogKind.action),
      ])));
      await tester.pump(const Duration(milliseconds: 300));

      // Skeleton, not a claim that it worked.
      expect(find.text('执行中…'), findsNothing);
      expect(find.text('已成功'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty run explains itself instead of showing a blank card',
        (tester) async {
      await tester.pumpWidget(_host(const StepLogView(logs: [])));
      await tester.pump();

      expect(find.textContaining('还没有开始'), findsOneWidget);
    });

    testWidgets('an error is drawn in the danger ink', (tester) async {
      await tester.pumpWidget(_host(StepLogView(logs: [
        AgentLogItem(step: 2, title: '点击失败：目标元素不存在', isError: true),
      ])));
      await tester.pump();

      final text = tester.widget<Text>(find.text('点击失败：目标元素不存在'));
      expect(text.style?.color, AppTheme.dangerOf(true));
      expect(find.text('错误'), findsOneWidget);
    });
  });

  group('site icons', () {
    testWidgets('fall back to a monogram when there is no favicon',
        (tester) async {
      // No server in a test: the fetch fails, and a letter is the answer.
      await tester.pumpWidget(_host(const SiteIcon(host: 'github.com')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('G'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short label wins over the host', (tester) async {
      await tester.pumpWidget(
        _host(const SiteIcon(host: 'news.ycombinator.com', label: '黑客新闻')),
      );
      await tester.pump();

      expect(find.text('黑'), findsOneWidget);
    });

    test('a favicon the WebView already has is kept, junk is not', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      FaviconService.put('example.com', png);
      expect(FaviconService.cached('EXAMPLE.COM'), isNotNull);

      // An HTML error page served for a favicon request is not an icon.
      final html = Uint8List.fromList('<html>404</html>'.codeUnits);
      FaviconService.put('bad.example', html);
      expect(FaviconService.cached('bad.example'), isNull);

      FaviconService.put('empty.example', Uint8List(0));
      expect(FaviconService.cached('empty.example'), isNull);
    });
  });

  group('the shared row', () {
    testWidgets('a destructive row is red and has no chevron', (tester) async {
      await tester.pumpWidget(_host(OperonListRow(
        title: '清除所有记录',
        danger: true,
        showChevron: false,
        onTap: () {},
      )));
      await tester.pump();

      final text = tester.widget<Text>(find.text('清除所有记录'));
      expect(text.style?.color, AppTheme.dangerOf(true));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

  });
}
