import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/models/macro_workflow.dart';
import 'package:operon/models/skill.dart';
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
  List<Skill> skills = const [],
  Future<void> Function()? onManageSkills,
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
        skills: skills,
        onManageSkills: onManageSkills,
        onAllowSite: onAllowSite,
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

  testWidgets('while running the composer becomes a control bar',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.thinking,
        goal: '正在执行的任务',
        currentStep: 3,
        maxSteps: 15,
      ),
    ));
    await tester.pump();

    // The disabled composer used to sit in the thumb area while the actual
    // controls lived inside the scroll view. The bar replaces both.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('正在执行的任务'), findsOneWidget);
    expect(find.text('3/15'), findsOneWidget);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(find.byTooltip('停止运行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a paused task offers resume and stop', (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.paused,
        goal: '每日签到',
        currentStep: 2,
        maxSteps: 10,
      ),
    ));
    await tester.pump();

    expect(find.text('每日签到'), findsOneWidget);
    expect(find.text('2/10'), findsOneWidget);
    expect(find.byTooltip('继续'), findsOneWidget);
    expect(find.byTooltip('停止运行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty panel suggests goals and fills the composer',
      (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pump();

    expect(find.text('试试'), findsOneWidget);
    expect(find.text('GitHub 热榜'), findsOneWidget);

    await tester.tap(find.text('GitHub 热榜'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '打开 GitHub 热榜并总结前 5 个项目');
    expect(tester.takeException(), isNull);
  });

  testWidgets('run bar fits a 320px screen with a long goal',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.executing,
        goal: '在页面里找到所有包含人工智能关键词的文章并逐条总结要点',
        currentStep: 12,
        maxSteps: 30,
      ),
    ));
    await tester.pump();

    expect(find.byTooltip('停止运行'), findsOneWidget);
    expect(find.text('12/30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('example chips wrap on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet());
    await tester.pump();

    expect(find.text('试试'), findsOneWidget);
    expect(find.text('Hacker News'), findsOneWidget);
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

  testWidgets('header shows elapsed time while the task runs', (tester) async {
    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
      taskStartedAt: DateTime.now().subtract(const Duration(seconds: 42)),
      state: const AgentState(
        status: AgentStatus.executing,
        currentStep: 3,
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

  testWidgets('empty logs are not offered in the overflow menu',
      (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pump();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
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

  testWidgets('completed task consolidates the result into one card',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: AgentState(
        status: AgentStatus.completed,
        goal: '回复推文',
        currentStep: 5,
        currentThought: '回复已发布，任务目标达成。',
        logs: [AgentLogItem(step: 1, title: '打开推文')],
        recordedMacroSteps: const [
          MacroStep(action: 'click', description: '打开推文'),
        ],
      ),
    ));
    await tester.pump();

    expect(find.text('任务结果'), findsOneWidget);
    expect(find.text('共 5 步'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('存为宏'), findsOneWidget);
    expect(find.text('日志 1'), findsOneWidget);
    expect(find.textContaining('已成功执行'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extracted data shows a compact summary and opens the full view',
      (tester) async {
    await tester.pumpWidget(_sheet(
      state: const AgentState(
        status: AgentStatus.completed,
        currentStep: 2,
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

    await tester.tap(find.byTooltip('展开全部'));
    await tester.pumpAndSettle();

    expect(find.text('抓取的数据'), findsOneWidget);
    expect(find.textContaining('"action": "reply"'), findsOneWidget);
  });

  testWidgets('overflow menu exposes logs, macros, skills and close',
      (tester) async {
    await tester.pumpWidget(_sheet(
      skills: const [Skill(id: 'a', name: '批量智能回复')],
      onManageSkills: () async {},
      state: AgentState(
        status: AgentStatus.completed,
        currentThought: '完成。',
        logs: [AgentLogItem(step: 1, title: '打开推文')],
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('日志 1'), findsWidgets);
    expect(find.text('快捷宏任务库'), findsOneWidget);
    expect(find.text('管理技能'), findsOneWidget);
    expect(find.text('关闭面板'), findsOneWidget);
  });

  testWidgets('an error surfaces its logs automatically', (tester) async {
    var state = AgentState(
      status: AgentStatus.executing,
      currentStep: 2,
      currentThought: '正在点击。',
      logs: [
        AgentLogItem(step: 2, title: '点击失败：目标元素不存在', isError: true),
      ],
    );
    late StateSetter rebuild;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AgentBottomSheet(
              state: state,
              safeMode: true,
              onSafeModeChanged: (_) {},
              onStart: (_, __) {},
              onPause: () {},
              onResume: () {},
              onStop: () {},
              onConfirmAction: (_) {},
              onConfirmCaptcha: (_) {},
              onRunMacro: (_) {},
            );
          },
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('点击失败'), findsNothing);

    rebuild(() => state = state.copyWith(status: AgentStatus.error));
    await tester.pump();

    expect(find.textContaining('点击失败'), findsOneWidget);
  });

  testWidgets('completed panel fits a 320px screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      state: AgentState(
        status: AgentStatus.completed,
        currentStep: 5,
        currentThought: '页面顶部已显示发送成功提示，任务目标达成，可以继续下一步操作。',
        extractedData: const [
          {
            'action': 'reply',
            'target_tweet_handle': '@jwx1250',
            'target_tweet_url': 'https://x.com/jwx1250/status/1',
            'reply_content': '支持！',
            'extra': 'more',
          }
        ],
        logs: [AgentLogItem(step: 1, title: '打开推文')],
        recordedMacroSteps: const [
          MacroStep(action: 'click', description: '打开推文'),
        ],
      ),
    ));
    await tester.pump();

    expect(find.text('任务结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow menu is pinned to the trailing edge', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheet(
      currentUrl: 'https://www.example.com/articles/1',
      state: AgentState(
        status: AgentStatus.completed,
        currentStep: 5,
        currentThought: '完成。',
        logs: [AgentLogItem(step: 1, title: '打开页面')],
      ),
    ));
    await tester.pump();

    final rect = tester.getRect(find.byIcon(Icons.more_horiz_rounded));
    expect(rect.right, greaterThan(320 - 40));
    expect(tester.takeException(), isNull);
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
        currentStep: 3,
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
        currentStep: 4,
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
}
