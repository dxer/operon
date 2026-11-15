import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/models/model_profile.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/services/theme_service.dart';
import 'package:operon/views/settings/about_settings_page.dart';
import 'package:operon/views/settings/ai_engine_settings_page.dart';
import 'package:operon/views/settings/appearance_settings_page.dart';
import 'package:operon/views/settings/general_settings_page.dart';
import 'package:operon/views/settings/settings_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Operon',
      packageName: 'app.operon',
      version: '0.5.0',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  testWidgets('settings groups AI entries before browser options',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const SettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('AI 与自动化'), findsOneWidget);
    expect(find.text('浏览与外观'), findsOneWidget);
    expect(find.text('AI 智能体引擎'), findsOneWidget);
    // The task-record page is gone: conversations are the only history now,
    // and they live in the agent panel where they are read.
    expect(find.text('任务历史与审计'), findsNothing);
    expect(find.text('快捷指令'), findsOneWidget);
    // Skills, macros and user scripts were removed: a page-level script runner
    // is the opposite of this app's "the layer does the acting" contract.
    expect(find.text('技能'), findsNothing);
    expect(find.text('快捷宏工作流'), findsNothing);
    expect(find.text('用户脚本'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('其他'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('关于 Operon'), findsOneWidget);

    // Compact single-line layout: no demo-like explanatory subtitles and
    // smaller typography than the legacy 17pt headlines.
    expect(find.text('配置模型与 API 密钥'), findsNothing);
    expect(find.text('人工授权已开启'), findsNothing);
    expect(find.textContaining('存下常说的话'), findsNothing);
    expect(find.textContaining('搜索引擎：'), findsNothing);
    expect(find.textContaining('极简轻量'), findsNothing);

    final rowTitle = tester.widget<Text>(find.text('AI 智能体引擎'));
    expect(rowTitle.style?.fontSize, lessThanOrEqualTo(14));
    final sectionTitle = tester.widget<Text>(find.text('AI 与自动化'));
    expect(sectionTitle.style?.fontSize, lessThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ai engine settings aligns buttons with inputs and uses dropdowns',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    StorageService.resetForTest();
    final storage = await StorageService.getInstance();
    await storage.saveLlmPreset(const LlmPreset(
      id: 'p1',
      name: 'DeepSeek 测试',
      config: LlmConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-ds',
        model: 'deepseek-chat',
      ),
    ));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const AiEngineSettingsPage(),
    ));
    await tester.pumpAndSettle();

    // Model TextField and "获取列表" button share the same height and top/bottom.
    final modelFieldFinder = find.widgetWithText(TextField, 'Model 模型名');
    final fetchBtnFinder = find.widgetWithText(OutlinedButton, '获取列表');
    final modelRect = tester.getRect(modelFieldFinder);
    final fetchRect = tester.getRect(fetchBtnFinder);
    expect((modelRect.height - fetchRect.height).abs(), lessThanOrEqualTo(1.0));
    expect((modelRect.top - fetchRect.top).abs(), lessThanOrEqualTo(1.0));

    // Presets dropdown + adjacent action button match height as well.
    final presetDropdownFinder =
        find.byType(DropdownButtonFormField<String>).first;
    final savePresetBtnFinder =
        find.widgetWithIcon(OutlinedButton, Icons.bookmark_add_outlined);
    final presetRect = tester.getRect(presetDropdownFinder);
    final saveBtnRect = tester.getRect(savePresetBtnFinder);
    expect((presetRect.height - saveBtnRect.height).abs(), lessThanOrEqualTo(1.0));

    // Selecting preset from dropdown applies its config.
    await tester.tap(presetDropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek 测试').last);
    await tester.pumpAndSettle();
    expect(storage.getLlmConfig().model, 'deepseek-chat');

    // Compact option-sheet rows for thinking level and model traits work without chips.
    expect(find.text('思考级别'), findsOneWidget);
    expect(find.text('图片输入'), findsOneWidget);
    expect(find.text('思考参数'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.scrollUntilVisible(
      find.text('图片输入'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图片输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('支持').last);
    await tester.pumpAndSettle();
    expect(storage.getModelProfile(storage.getLlmConfig()).vision, ModelTrait.yes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('general and appearance settings use compact option sheet selectors',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    StorageService.resetForTest();
    final storage = await StorageService.getInstance();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const GeneralSettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('默认搜索引擎'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bing (必应)').last);
    await tester.pumpAndSettle();
    expect(storage.getSearchEngine(), 'Bing (必应)');

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const AppearanceSettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<ThemeMode>), findsNothing);
    await tester.tap(find.text('主题切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暗色模式').last);
    await tester.pumpAndSettle();
    final themeService = await ThemeService.getInstance();
    expect(themeService.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the about page omits demo banners', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    StorageService.resetForTest();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const AboutSettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Operon'), findsOneWidget);
    expect(find.text('OPERON'), findsNothing);
    expect(find.text('轻量化设计'), findsNothing);
    expect(find.text('自主 Agent 引擎'), findsNothing);
    expect(find.text('控制层自检'), findsOneWidget);
    expect(find.text('开源代码仓库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
