import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/extracted_data_sheet.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester, dynamic data) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: ExtractedDataSheet(data: data)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows records as a table with the field names', (tester) async {
    await pumpSheet(tester, [
      {'标题': '第一条', '价格': '12'},
      {'标题': '第二条', '价格': '30'},
    ]);

    // The count in the header is the same number the CSV will contain.
    expect(find.text('2 条 · 2 个字段'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('共 2 行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a field a record left out is an empty cell, not a short row',
      (tester) async {
    await pumpSheet(tester, [
      {'标题': '甲'},
      {'标题': '乙', '价格': '9'},
    ]);

    // Both rows exist and both columns are there; the gap is visible.
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('共 2 行'), findsOneWidget);
  });

  testWidgets('the JSON view still shows the payload as it came',
      (tester) async {
    await pumpSheet(tester, [
      {'标题': '甲'},
    ]);

    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();

    final json = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(json.data, contains('"标题"'));
    expect(json.data, contains('甲'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lists say how many rows were not drawn', (tester) async {
    await pumpSheet(
      tester,
      [for (var index = 0; index < 250; index++) {'序号': '$index'}],
    );

    expect(find.text('只显示前 200 行，导出 CSV 取全部 250 行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
