import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/elapsed_label.dart';

void main() {
  test('format keeps seconds padded and expands past an hour', () {
    expect(ElapsedLabel.format(Duration.zero), '0:00');
    expect(ElapsedLabel.format(const Duration(seconds: 7)), '0:07');
    expect(ElapsedLabel.format(const Duration(minutes: 1, seconds: 5)), '1:05');
    expect(ElapsedLabel.format(const Duration(minutes: 59, seconds: 59)),
        '59:59');
    expect(
      ElapsedLabel.format(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
    // A clock skew must never render a negative time.
    expect(ElapsedLabel.format(const Duration(seconds: -5)), '0:00');
  });

  testWidgets('ticks once per second while mounted', (tester) async {
    final startedAt = DateTime(2026, 1, 1, 12);
    var now = startedAt;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElapsedLabel(startedAt: startedAt, clock: () => now),
      ),
    ));

    expect(find.text('0:00'), findsOneWidget);

    now = now.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:04'), findsOneWidget);

    // Unmounting must cancel the timer, otherwise the test hangs on teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
