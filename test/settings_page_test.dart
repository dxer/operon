import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
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
    expect(find.text('任务历史与审计'), findsOneWidget);
    expect(find.text('用户脚本'), findsOneWidget);
    // Skills and macros were removed with the flow/replay engines.
    expect(find.text('技能'), findsNothing);
    expect(find.text('快捷宏工作流'), findsNothing);
    expect(find.textContaining('UserScripts'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('其他'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('关于 Operon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
