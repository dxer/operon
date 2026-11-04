import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_service.dart';
import 'package:operon/views/settings/skills_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SkillService.resetForTest();
  });

  testWidgets('skills page starts empty and offers AI creation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const SkillsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('技能'), findsOneWidget);
    expect(find.text('还没有技能'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skills page lists a user-created skill', (tester) async {
    final service = await SkillService.getInstance();
    await service.saveSkill(const Skill(
      id: 'my_summary',
      name: '我的总结',
      kind: SkillKind.instruction,
      instructions: '总结当前页面。',
    ));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      home: const SkillsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('我的总结'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '不存在的技能');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的技能'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
