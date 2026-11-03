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
          onStart: (_, __) {},
          onPause: () {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
          onRunMacro: (_) {},
        ),
      ),
    ));

    expect(find.text('人工授权'), findsOneWidget);

    await tester.tap(find.text('人工授权'));
    await tester.pump();

    expect(changedTo, isFalse);
    expect(find.text('全自动'), findsOneWidget);
    expect(find.textContaining('不会暂停确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _moreTests();
}

Widget _sheet({
  AgentState state = const AgentState(),
  AgentStartHandler? onStart,
  String? currentUrl,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme.copyWith(
      splashFactory: InkRipple.splashFactory,
    ),
    home: Scaffold(
      body: AgentBottomSheet(
        state: state,
        currentUrl: currentUrl,
        safeMode: true,
        onSafeModeChanged: (_) {},
        onStart: onStart ?? (_, __) {},
        onPause: () {},
        onResume: () {},
        onStop: () {},
        onConfirmAction: (_) {},
        onConfirmCaptcha: (_) {},
        onRunMacro: (_) {},
      ),
    ),
  );
}

void _moreTests() {
  testWidgets('completed task does not prefill the previous goal',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(status: AgentStatus.completed, goal: '旧任务目标'),
    ));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(find.text('旧任务目标'), findsNothing);
  });

  testWidgets('clear button empties the composer', (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.enterText(find.byType(TextField), '临时指令');
    await tester.pump();

    expect(find.byTooltip('清空输入'), findsOneWidget);
    await tester.tap(find.byTooltip('清空输入'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(find.byTooltip('清空输入'), findsNothing);
  });

  testWidgets('sending clears the composer before the next task',
      (tester) async {
    String? started;
    await tester.pumpWidget(_sheet(
      onStart: (goal, _) => started = goal,
    ));
    await tester.enterText(find.byType(TextField), '打开设置并搜索');
    await tester.pump();

    await tester.tap(find.byTooltip('开始任务'));
    await tester.pump();

    expect(started, '打开设置并搜索');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('completing a task clears its untouched composer text',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.thinking,
        goal: '正在执行的任务',
      ),
    ));
    await tester.pump();

    var field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '正在执行的任务');

    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.completed,
        goal: '正在执行的任务',
      ),
    ));
    await tester.pump();

    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('send is inert until the composer has text', (tester) async {
    String? started;
    await tester.pumpWidget(_sheet(onStart: (goal, _) => started = goal));
    await tester.pump();

    expect(find.byTooltip('请输入指令'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(started, isNull);

    await tester.enterText(find.byType(TextField), '提取本页标题');
    await tester.pump();
    expect(find.byTooltip('开始任务'), findsOneWidget);
  });

  testWidgets('header shows the current operating host', (tester) async {
    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
    ));
    await tester.pump();

    expect(find.text('example.com'), findsOneWidget);
    expect(find.textContaining('当前是起始页'), findsNothing);
  });

  testWidgets('start page shows an empty-context hint', (tester) async {
    await tester.pumpWidget(_sheet(currentUrl: 'operon://newtab'));
    await tester.pump();

    expect(find.text('起始页'), findsOneWidget);
    expect(find.textContaining('当前是起始页'), findsOneWidget);
  });

  testWidgets('dismissing with a draft asks before discarding', (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.enterText(find.byType(TextField), '还没发送的指令');
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('放弃当前输入？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '还没发送的指令');
  });

  testWidgets('empty logs are not shown in the header', (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pump();

    expect(find.textContaining('日志'), findsNothing);
  });

  testWidgets('header fits a narrow phone with logs and a long status',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
      state: AgentState(
        status: AgentStatus.waitingConfirmation,
        goal: '测试任务',
        logs: [AgentLogItem(step: 1, title: '打开页面')],
      ),
    ));
    await tester.pump();

    expect(find.text('日志 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header survives a 320px screen with the longest state',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
      state: AgentState(
        status: AgentStatus.waitingCaptcha,
        goal: '测试任务',
        logs: [AgentLogItem(step: 1, title: '打开页面')],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard inset does not overflow the sheet', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: 320),
          viewPadding: EdgeInsets.only(bottom: 24),
        ),
        child: _sheet(),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
