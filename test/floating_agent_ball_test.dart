import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/views/widgets/floating_agent_ball.dart';

void main() {
  testWidgets('idle ball is neutral and tappable', (tester) async {
    var tapped = false;
    await _pumpBall(
      tester,
      const AgentState(),
      onTap: () => tapped = true,
    );

    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('!'), findsNothing);

    await tester.tap(find.byType(FloatingAgentBall));
    expect(tapped, isTrue);
  });

  testWidgets('running ball shows a ring and step badge', (tester) async {
    await _pumpBall(
      tester,
      const AgentState(
        status: AgentStatus.thinking,
        currentStep: 3,
        maxSteps: 15,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('waiting ball shows an alert badge', (tester) async {
    await _pumpBall(
      tester,
      const AgentState(status: AgentStatus.waitingConfirmation),
    );

    expect(find.text('!'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('completed ball shows a done badge', (tester) async {
    await _pumpBall(
      tester,
      const AgentState(status: AgentStatus.completed),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}

Future<void> _pumpBall(
  WidgetTester tester,
  AgentState state, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme.copyWith(
      splashFactory: InkRipple.splashFactory,
    ),
    home: Scaffold(
      body: Stack(
        children: [
          FloatingAgentBall(
            state: state,
            onTap: onTap ?? () {},
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
}
