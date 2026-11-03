import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/services/skill_service.dart';
import 'package:operon/views/settings/skills_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SkillService.resetForTest();
  });

  testWidgets('skills page renders built-in skills and AI entry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const SkillsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('技能'), findsOneWidget);
    expect(find.text('AI 创建'), findsOneWidget);
    expect(find.text('智能回复'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '区域内容总结');
    await tester.pumpAndSettle();
    expect(find.text('区域内容总结'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
