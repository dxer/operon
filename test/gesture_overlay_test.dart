import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/gesture_overlay.dart';

void main() {
  Widget host(ValueNotifier<GesturePulse?> pulse) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              GestureOverlay(pulse: pulse),
            ],
          ),
        ),
      );

  testWidgets('draws nothing until the layer dispatches a gesture', (tester) async {
    final pulse = ValueNotifier<GesturePulse?>(null);
    addTearDown(pulse.dispose);

    await tester.pumpWidget(host(pulse));
    expect(find.text('button "发送"'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the point and what it hits, then fades out', (tester) async {
    final pulse = ValueNotifier<GesturePulse?>(null);
    addTearDown(pulse.dispose);

    await tester.pumpWidget(host(pulse));
    pulse.value = const GesturePulse(
      at: Offset(120, 240),
      label: 'button "发送"',
      seq: 1,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // The label names the target, so the user can tell what is being clicked.
    expect(find.text('button "发送"'), findsOneWidget);

    // Once the animation is over, the label is gone and nothing is left over
    // the page to intercept a touch.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('button "发送"'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outlines the box the layer measured', (tester) async {
    final pulse = ValueNotifier<GesturePulse?>(null);
    addTearDown(pulse.dispose);

    await tester.pumpWidget(host(pulse));
    pulse.value = const GesturePulse(
      at: Offset(190, 240),
      bounds: Rect.fromLTWH(100, 220, 180, 40),
      label: 'button "发送"',
      seq: 1,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final ring = find.byKey(const ValueKey('gesture-target-ring'));
    expect(ring, findsOneWidget);
    // The outline sits exactly on the measured box: it is a promise about
    // where the event lands, so being "near" is not good enough.
    expect(tester.getSize(ring), const Size(180, 40));

    await tester.pump(const Duration(milliseconds: 800));
    expect(ring, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws no ring when the node reported no box', (tester) async {
    final pulse = ValueNotifier<GesturePulse?>(null);
    addTearDown(pulse.dispose);

    await tester.pumpWidget(host(pulse));
    pulse.value = const GesturePulse(
      at: Offset(60, 60),
      label: 'link "下一条"',
      seq: 1,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('gesture-target-ring')), findsNothing);
    expect(find.text('link "下一条"'), findsOneWidget);
  });

  testWidgets('a second pulse on the same point still animates', (tester) async {
    final pulse = ValueNotifier<GesturePulse?>(null);
    addTearDown(pulse.dispose);

    await tester.pumpWidget(host(pulse));
    for (var seq = 1; seq <= 3; seq++) {
      pulse.value = GesturePulse(
        at: const Offset(60, 60),
        label: 'link "下一条"',
        seq: seq,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('link "下一条"'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
