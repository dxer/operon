import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/views/widgets/agent_bottom_sheet.dart';

void main() {
  testWidgets('safe mode switch reflects and reports the new value',
      (tester) async {
    bool? changedTo;
    await tester.pumpWidget(MaterialApp(
      // InkSparkle shaders are unavailable in the headless test renderer.
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: Scaffold(
        body: AgentBottomSheet(
          state: const AgentState(),
          safeMode: true,
          onSafeModeChanged: (value) => changedTo = value,
          onStart: (_) {},
          onPause: () {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
          onRunMacro: (_) {},
        ),
      ),
    ));

    expect(find.text('敏感操作人工授权'), findsOneWidget);
    expect(find.textContaining('暂停并等待确认'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changedTo, isFalse);
    expect(find.textContaining('AI 将自动执行所有操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
