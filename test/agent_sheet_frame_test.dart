import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/agent_sheet_frame.dart';

/// The panel's height is the number under test; the test surface is 800x600 and
/// has no status bar, so the frame's usable height is 600 and the three resting
/// sizes are 360 / 450 / 540.
void main() {
  Widget host() {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AgentSheetFrame(
            builder: (onHandleDrag, onHandleDragEnd) => Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) =>
                      onHandleDrag(-details.delta.dy),
                  onVerticalDragEnd: (_) => onHandleDragEnd(),
                  child: const SizedBox(
                    height: 24,
                    width: double.infinity,
                    child: Center(child: Text('handle')),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (var row = 0; row < 60; row++)
                        SizedBox(height: 40, child: Text('row $row')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double panelHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AgentSheetFrame)).height;

  testWidgets('opens at the reading height', (tester) async {
    await tester.pumpWidget(host());
    expect(panelHeight(tester), 360);
  });

  testWidgets('dragging the handle grows the panel and snaps on release',
      (tester) async {
    await tester.pumpWidget(host());

    await tester.drag(find.text('handle'), const Offset(0, -100));
    await tester.pumpAndSettle();

    // 100px up is between the reading and the half-page heights; the panel
    // settles on the nearer one instead of stopping at an arbitrary 460.
    expect(panelHeight(tester), 450);
  });

  testWidgets('the panel stops at 90% however far the handle goes',
      (tester) async {
    await tester.pumpWidget(host());

    await tester.drag(find.text('handle'), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(panelHeight(tester), 540);
  });

  testWidgets('shrinking below the reading height falls back to it',
      (tester) async {
    await tester.pumpWidget(host());

    await tester.drag(find.text('handle'), const Offset(0, 200));
    await tester.pumpAndSettle();

    // 0.6 is the shortest resting height: a smaller panel is not useful, and
    // stopping somewhere random is worse than returning.
    expect(panelHeight(tester), 360);
  });

  testWidgets('scrolling the conversation does not resize the panel',
      (tester) async {
    await tester.pumpWidget(host());
    final before = panelHeight(tester);

    await tester.drag(find.text('row 0'), const Offset(0, -200));
    await tester.pumpAndSettle();

    // The complaint this replaced: a scroll over the transcript used to grow the
    // window first, so the text jumped under the thumb.
    expect(panelHeight(tester), before);
    expect(tester.takeException(), isNull);
  });
}
