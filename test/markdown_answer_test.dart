import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/views/widgets/markdown_answer.dart';

// The answer is the product. Rendering it as plain text turned every list the
// model wrote into a wall of asterisks.

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// The visible text of every span, joined: asserts on what the user reads
/// rather than on the widget tree that produced it.
String rendered(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is RichText) buffer.write(widget.text.toPlainText());
    if (widget is Text && widget.data != null) buffer.write(widget.data);
  }
  return buffer.toString();
}

void main() {
  testWidgets('emphasis is emphasis, not asterisks', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('这是 **重点** 和 *强调*。')));
    await tester.pump();

    expect(rendered(tester), contains('这是 重点 和 强调。'));
    expect(rendered(tester), isNot(contains('**')));
  });

  testWidgets('a list is a list', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('要做的事：\n\n- 打开热榜\n- 抓前五条\n- 整理')));
    await tester.pump();

    expect(find.text('•'), findsNWidgets(3));
    expect(rendered(tester), contains('打开热榜'));
    expect(rendered(tester), isNot(contains('- 打开热榜')));
  });

  testWidgets('an ordered list keeps its numbers', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('1. 第一步\n2. 第二步')));
    await tester.pump();

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('a code block is monospace and scrolls sideways', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('这样写：\n\n```dart\nfinal x = 1;\n```')));
    await tester.pump();

    final code = tester.widget<Text>(find.text('final x = 1;'));
    expect(code.style?.fontFamily, 'monospace');
    // A long line must scroll sideways, not wrap into the answer.
    final scrollers = tester.widgetList<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollers.any((s) => s.scrollDirection == Axis.horizontal), isTrue);
  });

  testWidgets('inline code is monospace too', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('用 `done` 结束。')));
    await tester.pump();

    expect(rendered(tester), contains('用 done 结束。'));
    expect(rendered(tester), isNot(contains('`')));
  });

  testWidgets('a link is tappable and reports where it goes', (tester) async {
    String? opened;
    await tester.pumpWidget(host(MarkdownAnswer(
      '详情见 [文档](https://example.com/doc)。',
      onOpenLink: (url) => opened = url,
    )));
    await tester.pump();

    // The link is a span with a recognizer; tapping its text is a hit test
    // against a range, so the wiring is what is worth asserting.
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    TapGestureRecognizer? link;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.recognizer is TapGestureRecognizer) {
        link = span.recognizer as TapGestureRecognizer;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }

    walk(rich.text);
    expect(link, isNotNull, reason: '答案里的链接应该是可点的');
    link!.onTap!();
    expect(opened, 'https://example.com/doc');
  });

  testWidgets('without a handler a link is still readable text', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('见 [文档](https://example.com)。')));
    await tester.pump();

    expect(rendered(tester), contains('文档'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a table becomes a table, not pipes', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer(
      '| 项目 | 数量 |\n| --- | --- |\n| 仓库 | 5 |',
    )));
    await tester.pump();

    expect(find.text('项目'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(rendered(tester), isNot(contains('|---')));
  });

  testWidgets('a heading is bigger than the body', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('## 结论\n\n就这样。')));
    await tester.pump();

    final heading = tester.widget<RichText>(find.byType(RichText).first);
    final size = heading.text.style?.fontSize ?? 0;
    expect(size, greaterThan(15));
  });

  testWidgets('plain prose is untouched', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('没有格式，就是一句话。')));
    await tester.pump();

    expect(rendered(tester), contains('没有格式，就是一句话。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty answer renders nothing at all', (tester) async {
    await tester.pumpWidget(host(const MarkdownAnswer('   ')));
    await tester.pump();

    expect(find.byType(RichText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
