import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_action.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/views/widgets/agent_status_bar.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      // InkSparkle's shader isn't available in the headless test renderer.
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: ColoredBox(color: Colors.white)),
            child,
          ],
        ),
      ),
    );
  }

  testWidgets('running status bar shows step progress and pause/stop',
      (tester) async {
    await tester.pumpWidget(wrap(AgentStatusBar(
      state: const AgentState(
        status: AgentStatus.observing,
        currentStep: 2,
        maxSteps: 10,
      ),
      onOpen: () {},
      onPause: () {},
      onResume: () {},
      onStop: () {},
      onConfirmCaptcha: () {},
      onConfirmAction: () {},
    )));

    expect(find.textContaining('正在读取页面'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captcha and confirmation states expose their approve action',
      (tester) async {
    var captchaConfirmed = false;
    await tester.pumpWidget(wrap(AgentStatusBar(
      state: const AgentState(status: AgentStatus.waitingCaptcha),
      onOpen: () {},
      onPause: () {},
      onResume: () {},
      onStop: () {},
      onConfirmCaptcha: () => captchaConfirmed = true,
      onConfirmAction: () {},
    )));
    expect(find.textContaining('人机验证'), findsOneWidget);
    await tester.tap(find.text('已通过'));
    expect(captchaConfirmed, isTrue);

    var actionApproved = false;
    await tester.pumpWidget(wrap(AgentStatusBar(
      state: const AgentState(
        status: AgentStatus.waitingConfirmation,
        currentAction: AgentAction(
          thought: 'submit',
          action: ActionType.click,
          elementId: 1,
        ),
      ),
      onOpen: () {},
      onPause: () {},
      onResume: () {},
      onStop: () {},
      onConfirmCaptcha: () {},
      onConfirmAction: () => actionApproved = true,
    )));
    expect(find.textContaining('敏感操作待授权'), findsOneWidget);
    await tester.tap(find.text('授权'));
    expect(actionApproved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed and error states can be dismissed', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(wrap(AgentStatusBar(
      state: const AgentState(status: AgentStatus.completed),
      onOpen: () {},
      onPause: () {},
      onResume: () {},
      onStop: () {},
      onConfirmCaptcha: () {},
      onConfirmAction: () {},
      onDismiss: () => dismissed = true,
    )));

    expect(find.textContaining('任务已完成'), findsOneWidget);
    await tester.tap(find.byTooltip('收起'));
    expect(dismissed, isTrue);

    await tester.pumpWidget(wrap(AgentStatusBar(
      state: const AgentState(
        status: AgentStatus.error,
        errorMessage: '模型超时',
      ),
      onOpen: () {},
      onPause: () {},
      onResume: () {},
      onStop: () {},
      onConfirmCaptcha: () {},
      onConfirmAction: () {},
    )));
    expect(find.textContaining('模型超时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
