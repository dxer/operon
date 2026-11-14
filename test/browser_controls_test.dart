import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/views/widgets/browser_controls.dart';

/// The AI entry lives to the left of the address pill: outside it, where the
/// address keeps its width, and in the same place on every page.

Widget _bar({
  required TextEditingController controller,
  VoidCallback? onOpenAgent,
  bool busy = false,
  VoidCallback? onSummarize,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          BrowserControls(
            urlController: controller,
            isLoading: false,
            progress: 0,
            onSubmitUrl: (_) {},
            onSummarize: onSummarize ?? () {},
            onOpenAgent: onOpenAgent,
            agentBusy: busy,
          ),
        ],
      ),
    ),
  );
}

void main() {
  _narrowWidthTests();

  testWidgets('the assistant entry sits left of the address', (tester) async {
    final controller = TextEditingController(text: 'https://example.com/');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_bar(controller: controller, onOpenAgent: () {}));
    await tester.pump();

    final entry = find.byType(AgentEntryButton);
    expect(entry, findsOneWidget);
    expect(
      find.descendant(of: entry, matching: find.byIcon(Icons.auto_awesome_rounded)),
      findsOneWidget,
      reason: 'the entry is the AI mark',
    );
    final entryRect = tester.getRect(entry);
    final fieldRect = tester.getRect(find.byType(TextField));
    expect(entryRect.right, lessThanOrEqualTo(fieldRect.left));
    expect(entryRect.left, lessThan(24), reason: 'it leads the row');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping it asks for the panel, not for a summary', (tester) async {
    final controller = TextEditingController(text: 'https://example.com/');
    addTearDown(controller.dispose);
    var opened = 0;
    var summarized = 0;

    await tester.pumpWidget(_bar(
      controller: controller,
      onOpenAgent: () => opened++,
      onSummarize: () => summarized++,
    ));
    await tester.tap(find.byType(AgentEntryButton));
    await tester.pump();

    expect(opened, 1);
    expect(summarized, 0, reason: 'summarising stays a separate action');
  });

  testWidgets('no entry is shown when the page does not offer one', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_bar(controller: controller));
    await tester.pump();

    expect(find.byType(AgentEntryButton), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a running task marks the entry instead of hiding it', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _bar(controller: controller, onOpenAgent: () {}, busy: true),
    );
    await tester.pump();

    // Still there — the user needs it most while a task runs.
    expect(find.byType(AgentEntryButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentEntryButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

// A phone-width row: the entry must not steal the address's width, and a long
// URL must still have room before the clear button appears.
void _narrowWidthTests() {
  testWidgets('the entry and the pill fit a 360dp phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = TextEditingController(
      text: 'https://www.example.com/a/very/long/path/that/keeps/going?q=1',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_bar(controller: controller, onOpenAgent: () {}));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'no overflow at phone width');
    final entry = tester.getRect(find.byType(AgentEntryButton));
    final field = tester.getRect(find.byType(TextField));
    expect(field.width, greaterThan(200), reason: 'the address keeps its room');
    expect(entry.width, 44, reason: 'the touch target does not shrink');
  });
}
