import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/goal_handoff.dart';
import 'package:operon/services/model_probe.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/views/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First run is the only screen every user sees before the browser. It has to
/// earn the API key, check the one capability the agent needs, and hand a real
/// task to the browser without starting it behind the user's back.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    GoalHandoff.clear();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required VoidCallback onDone,
    Future<ModelProbeResult> Function(LlmConfig config)? probe,
    Future<List<String>> Function(LlmConfig config)? fetchModels,
  }) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: OnboardingPage(
        onDone: onDone,
        probe: probe,
        fetchModels: fetchModels,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> fillModel(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('onboarding-base-url')),
      'https://api.deepseek.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('onboarding-api-key')),
      'sk-test',
    );
    await tester.enterText(
      find.byKey(const Key('onboarding-model')),
      'deepseek-chat',
    );
  }

  testWidgets('explains the value before asking for a key', (tester) async {
    var done = false;
    await pumpPage(tester, onDone: () => done = true);

    expect(find.text('不只是浏览，而是操控。'), findsOneWidget);
    expect(find.text('关键动作你说了算'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-api-key')), findsNothing);

    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();

    expect(find.text('连接一个模型'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-api-key')), findsOneWidget);
    expect(done, isFalse);
  });

  testWidgets('system back returns to the previous step', (tester) async {
    await pumpPage(tester, onDone: () {});

    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接一个模型'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('不只是浏览，而是操控。'), findsOneWidget);
    expect(find.text('连接一个模型'), findsNothing);
  });

  testWidgets('a model that calls tools stores the config and offers tasks',
      (tester) async {
    var done = false;
    LlmConfig? probed;
    await pumpPage(
      tester,
      onDone: () => done = true,
      probe: (config) async {
        probed = config;
        return const ModelProbeResult(calledTool: true);
      },
    );

    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    await fillModel(tester);
    await tester.tap(find.text('测试并继续'));
    await tester.pumpAndSettle();

    expect(probed?.model, 'deepseek-chat');
    expect(find.text('准备好了'), findsOneWidget);

    final storage = await StorageService.getInstance();
    expect(storage.getLlmConfig().baseUrl, 'https://api.deepseek.com/v1');
    expect(storage.getLlmConfig().model, 'deepseek-chat');
    expect(storage.getLlmConfig().apiKey, 'sk-test');
    expect(storage.getOnboardingDone(), isFalse);

    // A starter task is queued, not started: the browser opens the composer
    // with it so the user still confirms the spend.
    await tester.tap(find.byKey(const Key('onboarding-example-0')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(storage.getOnboardingDone(), isTrue);
    final pending = GoalHandoff.take();
    expect(pending, isNotNull);
    expect(pending!.goal, contains('Bing'));
    expect(pending.url, 'https://www.bing.com');
  });

  testWidgets('an endpoint that answers without a tool call explains the risk',
      (tester) async {
    await pumpPage(
      tester,
      onDone: () {},
      probe: (_) async => const ModelProbeResult(
        calledTool: false,
        content: '好的，我来帮你。',
      ),
    );

    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    await fillModel(tester);
    await tester.tap(find.text('测试并继续'));
    await tester.pumpAndSettle();

    expect(find.text('准备好了'), findsNothing);
    expect(find.textContaining('能连通，但模型没有调用工具'), findsOneWidget);
    expect(find.textContaining('好的，我来帮你。'), findsOneWidget);

    // The escape hatch saves the config the user chose.
    await tester.ensureVisible(find.text('仍然继续'));
    await tester.tap(find.text('仍然继续'));
    await tester.pumpAndSettle();

    expect(find.text('准备好了'), findsOneWidget);
    final storage = await StorageService.getInstance();
    expect(storage.getLlmConfig().model, 'deepseek-chat');
  });

  testWidgets('skipping marks setup done without inventing a task',
      (tester) async {
    var done = false;
    await pumpPage(tester, onDone: () => done = true);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    final storage = await StorageService.getInstance();
    expect(storage.getOnboardingDone(), isTrue);
    expect(GoalHandoff.pending.value, isNull);
  });

  testWidgets('the endpoint list can fill the model field', (tester) async {
    LlmConfig? fetchedFor;
    await pumpPage(
      tester,
      onDone: () {},
      fetchModels: (config) async {
        fetchedFor = config;
        return ['deepseek-chat', 'deepseek-reasoner', 'deepseek-chat'];
      },
    );

    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('onboarding-base-url')),
      'https://api.deepseek.com/v1',
    );
    await tester.tap(find.text('获取列表'));
    await tester.pumpAndSettle();

    expect(fetchedFor?.baseUrl, 'https://api.deepseek.com/v1');
    // Duplicates collapse before the sheet is built.
    expect(find.text('选择模型 · 2'), findsOneWidget);

    await tester.tap(find.text('deepseek-reasoner'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('onboarding-model')),
    );
    expect(field.controller?.text, 'deepseek-reasoner');
  });
}
