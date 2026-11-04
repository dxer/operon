import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_package_codec.dart';
import 'package:operon/services/skill_package_store.dart';
import 'package:operon/services/skill_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SkillService.resetForTest();
    root = await Directory.systemTemp.createTemp('operon_skill_service_');
    SkillService.debugPackageStore = FileSkillPackageStore(root);
  });

  tearDown(() async {
    SkillService.resetForTest();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('saving a flow skill writes both package files', () async {
    final service = await SkillService.getInstance();
    const skill = Skill(
      id: 'reply_timeline',
      name: '回复时间线',
      description: '回复时间线推文。',
      kind: SkillKind.flow,
      steps: [
        SkillStep(
          id: 'step_1_click',
          name: '点击回复',
          tool: 'page.click',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': '[data-testid="reply"]'},
              ],
              'requireUnique': false,
              'nth': 0,
            },
          },
        ),
      ],
      policy: SkillPolicy(maxSteps: 5, maxSideEffects: 1),
    );

    await service.saveSkill(skill);

    final dir = Directory(
      '${root.path}/${SkillPackageCodec.packageDirName(skill)}',
    );
    final markdown = await File('${dir.path}/SKILL.md').readAsString();
    final flow = await File('${dir.path}/flow.json').readAsString();
    expect(markdown, contains('回复时间线'));
    expect(flow, contains('"page.click"'));
  });

  test('standard SKILL.md imports as an instruction skill', () async {
    final service = await SkillService.getInstance();
    const markdown = '''
---
name: reply-x-timeline
description: Reply to posts on the x.com timeline.
---

# Reply to timeline

Open the reply box and write a reply.
''';

    final errors = await service.importPackages(
      const [SkillPackageFiles(markdown: markdown)],
    );

    expect(errors, isEmpty);
    final imported = service
        .getSkills()
        .firstWhere((skill) => skill.id == 'skill_reply-to-timeline');
    expect(imported.kind, SkillKind.instruction);
    expect(imported.name, 'Reply to timeline');
  });

  test('exportPackages returns a package for every skill', () async {
    final service = await SkillService.getInstance();
    // Nothing ships any more, so the library starts empty.
    expect(service.getSkills(), isEmpty);

    await service.saveSkill(const Skill(
      id: 'exported_one',
      name: '导出示例',
      kind: SkillKind.instruction,
      instructions: '总结当前页面。',
    ));
    final exported = service.exportPackages();

    expect(exported, isNotEmpty);
    final skills = service.getSkills();
    for (var i = 0; i < exported.length; i++) {
      final files = exported[i];
      expect(files.id, skills[i].id);
      expect(files.markdown, contains('---'));
      expect(
        files.flowJson == null,
        skills[i].kind == SkillKind.instruction,
      );
    }
  });
}
