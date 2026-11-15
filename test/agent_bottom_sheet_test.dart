import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_conversation.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/services/conversation_store.dart';
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
          conversationId: 'test',
          onStart: (_, __, ___) {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
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
  void Function(String goal)? onStart,
  String? currentUrl,
  VoidCallback? onAllowSite,
  DateTime? taskStartedAt,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme.copyWith(
      splashFactory: InkRipple.splashFactory,
    ),
    home: Scaffold(
      body: AgentBottomSheet(
        state: state,
        currentUrl: currentUrl,
        taskStartedAt: taskStartedAt,
        safeMode: true,
        onAllowSite: onAllowSite,
        onSafeModeChanged: (_) {},
        conversationId: 'test',
        onStart: (_, goal, __) => onStart?.call(goal),
        onResume: () {},
        onStop: () {},
        onConfirmAction: (_) {},
        onConfirmCaptcha: (_) {},
      ),
    ),
  );
}

void _moreTests() {
  testWidgets('a finished task leaves its goal in the transcript, not the field',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(status: AgentStatus.completed, goal: '旧任务目标'),
    ));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    // What the user sent stays where they can read it: the transcript.
    expect(find.text('旧任务目标'), findsOneWidget);
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
      onStart: (goal) => started = goal,
    ));
    await tester.enterText(find.byType(TextField), '打开设置并搜索');
    await tester.pump();

    await tester.tap(find.byTooltip('开始任务'));
    await tester.pump();

    expect(started, '打开设置并搜索');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('while running the composer becomes a control bar',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.thinking,
        goal: '正在执行的任务',
      ),
    ));
    await tester.pump();

    // The disabled composer used to sit in the thumb area while the actual
    // controls lived inside the scroll view. The bar replaces both.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('正在执行的任务'), findsOneWidget);
    expect(find.text('第 3 步'), findsNothing);
    // One control, not two. Pausing mid-form left the page half-filled with
    // nothing on screen saying why, so the bar only offers stop.
    expect(find.byTooltip('暂停'), findsNothing);
    expect(find.byTooltip('停止运行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the transcript is selectable text, not a picture of it',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.completed,
        goal: '这一页讲了什么',
        currentThought: '讲的是三件事。',
      ),
    ));
    await tester.pump();

    // Long-press → drag → 复制 is what a phone does with text. The copy button
    // hands over the whole answer; this is how you take one sentence out of it.
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('这一页讲了什么'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a paused task offers resume and stop', (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.paused,
        goal: '每日签到',
      ),
    ));
    await tester.pump();

    expect(find.text('每日签到'), findsOneWidget);
    expect(find.text('第 2 步'), findsNothing);
    expect(find.byTooltip('继续'), findsOneWidget);
    expect(find.byTooltip('停止运行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty panel suggests goals and fills the composer',
      (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pump();

    expect(find.text('试试'), findsOneWidget);
    expect(find.text('搜索并总结'), findsOneWidget);

    await tester.tap(find.text('搜索并总结'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller?.text,
      '打开 Bing 搜索「Flutter 3.35 发布说明」，打开第一条结果，总结更新要点',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('completing a task clears its untouched composer text',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.completed,
        goal: '正在执行的任务',
      ),
    ));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('send is inert until the composer has text', (tester) async {
    String? started;
    await tester.pumpWidget(_sheet(onStart: (goal) => started = goal));
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

  testWidgets('header shows elapsed time while the task runs', (tester) async {
    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
      taskStartedAt: DateTime.now().subtract(const Duration(seconds: 42)),
      state: const AgentState(
        status: AgentStatus.executing,
      ),
    ));
    await tester.pump();

    expect(find.text('0:42'), findsOneWidget);
    // Status and site share one chip, so the header stays one line.
    expect(find.text('执行中'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('completed task consolidates the result into one card',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: AgentState(
        status: AgentStatus.completed,
        goal: '回复推文',
        currentThought: '回复已发布，任务目标达成。',
        logs: [AgentLogItem(step: 1, title: '打开推文')],
      ),
    ));
    await tester.pump();

    expect(find.text('任务结果'), findsOneWidget);
    expect(find.textContaining('5 步'), findsNothing);
    expect(find.text('复制'), findsOneWidget);
    // The steps are one tap away, not on screen: a finished turn reads like a
    // chat reply, not like a debugger.
    expect(find.text('打开推文'), findsNothing);
    await tester.tap(find.textContaining('查看'));
    await tester.pumpAndSettle();
    expect(find.text('打开推文'), findsOneWidget);
    // Saving a macro is gone with the replay engine.
    expect(find.text('存为宏'), findsNothing);
    expect(find.textContaining('已成功执行'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extracted data shows a compact summary and opens the full view',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.completed,
        currentThought: '已抓取数据。',
        extractedData: [
          {
            'action': 'reply',
            'target_tweet_handle': '@jwx1250',
            'target_tweet_url': 'https://x.com/jwx1250/status/1',
            'reply_content': '支持！',
            'extra': 'more',
          }
        ],
      ),
    ));
    await tester.pump();

    expect(find.text('1 条数据 · 5 个字段'), findsOneWidget);
    expect(find.text('target_tweet_handle'), findsOneWidget);
    // The three ways out are on the card itself, not behind a menu.
    expect(find.text('表格'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);

    await tester.tap(find.text('表格'));
    await tester.pumpAndSettle();

    // The sheet opens on the table: the rows are what a person checks.
    expect(find.text('1 条 · 5 个字段'), findsOneWidget);
    // The card's preview and the table's cell are the same value, on purpose:
    // both are built from the same export table.
    expect(find.text('@jwx1250'), findsNWidgets(2));

    // The raw payload is one tap away for whoever wants to verify the model.
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"action": "reply"'), findsOneWidget);
  });

  testWidgets('long hosts collapse to the registrable domain', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      currentUrl: 'https://very-long-subdomain.example.co.uk/deep/path',
      state: AgentState(
        status: AgentStatus.waitingCaptcha,
        goal: '测试任务',
        logs: [AgentLogItem(step: 1, title: '打开页面')],
      ),
    ));
    await tester.pump();

    expect(find.text('example.co.uk'), findsOneWidget);
    expect(find.textContaining('very-long-subdomain'), findsNothing);
    expect(
      find.byTooltip('AI 将在这个站点上操作\nvery-long-subdomain.example.co.uk'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('short hosts are not abbreviated', (tester) async {
    await tester.pumpWidget(_sheet(
      currentUrl: 'https://x.com/linyun1128',
    ));
    await tester.pump();

    expect(find.text('x.com'), findsOneWidget);
  });

  testWidgets('captcha hand-off stays compact on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.waitingCaptcha,
        captchaType: '滑动验证',
        currentThought: '页面弹出验证码。',
      ),
    ));
    await tester.pump();

    expect(find.text('需要人机验证 · 滑动验证'), findsOneWidget);
    expect(
      find.text('请在上方网页完成验证，然后点击「我已完成验证」。'),
      findsOneWidget,
    );

    final abort = tester.getCenter(find.text('中止任务'));
    final proceed = tester.getCenter(find.text('我已完成验证'));
    expect((abort.dy - proceed.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation banner stays compact and shortens the host',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      onAllowSite: () {},
      state: const AgentState(
        status: AgentStatus.waitingConfirmation,
        goal: '发送回复',
        confirmationReason: '发布内容',
        targetUrl: 'https://very-long-subdomain.example.co.uk/status/1',
        confirmationPayload: '支持！祝你早日突破百万粉丝，期待更多优质内容。',
      ),
    ));
    await tester.pump();

    expect(find.text('敏感操作，等待授权'), findsOneWidget);
    expect(find.text('本站始终允许（example.co.uk）'), findsOneWidget);

    final cancel = tester.getCenter(find.text('取消任务'));
    final allow = tester.getCenter(find.text('授权继续'));
    expect((cancel.dy - allow.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeating the same goal keeps live progress and new result visible',
      (tester) async {
    final store = ConversationStore.inMemory();
    final conv = store.create(now: DateTime(2026, 1, 1, 10, 0));
    await store.appendTurn(
      conv.id,
      AgentTurn(
        id: 't1',
        message: '总结这一页',
        startedAt: DateTime(2026, 1, 1, 10, 0, 0),
        endedAt: DateTime(2026, 1, 1, 10, 0, 5),
        status: 'completed',
        result: '第一次的总结。',
      ),
    );

    final newStart = DateTime(2026, 1, 1, 10, 5, 0);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: AgentBottomSheet(
          store: store,
          conversationId: conv.id,
          taskStartedAt: newStart,
          state: AgentState(
            status: AgentStatus.executing,
            goal: '总结这一页',
            logs: [AgentLogItem(step: 2, title: '读取正文', kind: LogKind.action)],
          ),
          safeMode: true,
          onSafeModeChanged: (_) {},
          onStart: (_, __, ___) {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('第一次的总结。'), findsOneWidget);
    expect(find.textContaining('读取正文'), findsOneWidget);
    // Header title + persisted first bubble + current live bubble.
    expect(find.text('总结这一页'), findsNWidgets(3));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: AgentBottomSheet(
          store: store,
          conversationId: conv.id,
          taskStartedAt: newStart,
          state: const AgentState(
            status: AgentStatus.completed,
            goal: '总结这一页',
            currentThought: '第二次的总结。',
          ),
          safeMode: true,
          onSafeModeChanged: (_) {},
          onStart: (_, __, ___) {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('第一次的总结。'), findsOneWidget);
    expect(find.text('第二次的总结。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persisted turn shows attachment names and re-ask fills composer',
      (tester) async {
    final store = ConversationStore.inMemory();
    final conv = store.create(now: DateTime(2026, 1, 1, 10, 0));
    await store.appendTurn(
      conv.id,
      AgentTurn(
        id: 't1',
        message: '分析这两份材料',
        startedAt: DateTime(2026, 1, 1, 10, 0, 0),
        endedAt: DateTime(2026, 1, 1, 10, 0, 5),
        status: 'completed',
        result: '已完成分析。',
        attachmentNames: const ['report.pdf', 'chart.png'],
      ),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: AgentBottomSheet(
          store: store,
          conversationId: conv.id,
          state: const AgentState(),
          safeMode: true,
          onSafeModeChanged: (_) {},
          onStart: (_, __, ___) {},
          onResume: () {},
          onStop: () {},
          onConfirmAction: (_) {},
          onConfirmCaptcha: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('report.pdf、chart.png'), findsOneWidget);
    await tester.tap(find.text('重问'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '分析这两份材料');
    expect(tester.takeException(), isNull);
  });
}
