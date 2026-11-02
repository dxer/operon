import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/quick_command_defaults.dart';
import 'package:operon/config/skill_defaults.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/quick_command_service.dart';
import 'package:operon/services/skill_migration.dart';
import 'package:operon/services/skill_service.dart';
import 'package:operon/services/skill_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    QuickCommandService.resetForTest();
    SkillService.resetForTest();
  });

  test('legacy quick command migrates without changing its prompt', () {
    final command = QuickCommandDefaults.all().first;
    final skill = SkillMigration.fromQuickCommand(command);

    expect(skill.id, command.id);
    expect(skill.name, command.title);
    expect(skill.instructions, command.promptTemplate);
    expect(skill.kind, SkillKind.instruction);
    expect(skill.origin, SkillOrigin.migrated);
    expect(skill.inputs.length, command.inputs.length);
    expect(skill.policy.uniqueTarget, command.policy.uniqueTarget);
    expect(skill.policy.maxItems, command.policy.maxItems);
    expect(skill.steps, isEmpty);
  });

  test('fresh install seeds instruction and flow defaults', () async {
    final service = await SkillService.getInstance();
    final skills = service.getSkills();

    expect(skills.length, SkillDefaults.all().length);
    expect(skills.map((item) => item.id), contains('quick_batch_reply'));
    expect(skills.map((item) => item.id), contains('skill_region_summary'));
    expect(skills.map((item) => item.id), contains('skill_link_collect'));
    expect(skills.map((item) => item.id), contains('skill_page_export'));

    final validator = SkillValidator();
    for (final skill in skills) {
      final result = validator.validate(skill);
      expect(result.hasErrors, isFalse,
          reason: '${skill.id}: ${result.repairHint}');
    }
  });

  test('existing quick commands are migrated and the legacy key is kept',
      () async {
    final legacy = QuickCommandDefaults.all().first;
    SharedPreferences.setMockInitialValues({
      SkillService.legacyKey: [jsonEncode(legacy.toJson())],
    });
    QuickCommandService.resetForTest();
    SkillService.resetForTest();

    final service = await SkillService.getInstance();
    final skills = service.getSkills();
    final migrated = skills.firstWhere((item) => item.id == legacy.id);

    expect(migrated.origin, SkillOrigin.migrated);
    expect(migrated.instructions, legacy.promptTemplate);
    expect(skills.where((item) => item.id == 'skill_region_summary').length, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(SkillService.legacyKey), isNotNull);
    expect(prefs.getStringList('pref_skills_v1'), isNotNull);
  });

  test('saving an existing skill bumps its content version', () async {
    final service = await SkillService.getInstance();
    var skill = const Skill(
      id: 'user_skill',
      name: '我的技能',
      kind: SkillKind.instruction,
      instructions: '总结当前页面',
    );

    await service.saveSkill(skill);
    var saved = service.getSkills().firstWhere((item) => item.id == 'user_skill');
    expect(saved.version, 1);

    skill = saved.copyWith(name: '我的技能 2');
    await service.saveSkill(skill);
    saved = service.getSkills().firstWhere((item) => item.id == 'user_skill');
    expect(saved.version, 2);
    expect(saved.name, '我的技能 2');
  });

  test('restore defaults keeps user-created skills', () async {
    final service = await SkillService.getInstance();
    await service.saveSkill(const Skill(
      id: 'user_skill',
      name: '保留我',
      kind: SkillKind.instruction,
      instructions: '保留',
    ));

    await service.restoreDefaults();
    final skills = service.getSkills();

    expect(skills.map((item) => item.id), contains('user_skill'));
    expect(skills.where((item) => item.id == 'skill_region_summary').length, 1);
    expect(skills.where((item) => item.id == 'quick_batch_reply').length, 1);
  });

  test('corrupt entries do not discard the rest of the library', () async {
    SharedPreferences.setMockInitialValues({
      'pref_skills_v1': [
        'not-json',
        jsonEncode(const Skill(
          id: 'ok',
          name: '正常',
          kind: SkillKind.instruction,
          instructions: '正常',
        ).toJson()),
      ],
    });
    SkillService.resetForTest();

    final service = await SkillService.getInstance();
    final skills = service.getSkills();

    expect(skills.length, 1);
    expect(skills.single.id, 'ok');
  });
}
