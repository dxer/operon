import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_inputs.dart';
import 'package:operon/services/skill_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SkillService.resetForTest();
  });

  test('a fresh install starts with an empty library', () async {
    final service = await SkillService.getInstance();

    expect(service.getSkills(), isEmpty);
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
    var saved =
        service.getSkills().firstWhere((item) => item.id == 'user_skill');
    expect(saved.version, 1);

    skill = saved.copyWith(name: '我的技能 2');
    await service.saveSkill(skill);
    saved = service.getSkills().firstWhere((item) => item.id == 'user_skill');
    expect(saved.version, 2);
    expect(saved.name, '我的技能 2');
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

  test('a placeholder typed by hand becomes a run-time input', () async {
    final service = await SkillService.getInstance();
    // No declared inputs, but the prompt references one.
    await service.saveSkill(const Skill(
      id: 'prompt_skill',
      name: '手写占位符',
      kind: SkillKind.instruction,
      instructions: '用 {{inputs.tone}} 的语气总结当前页面。',
    ));

    final saved = service.getSkills().single;
    expect(saved.inputs.map((input) => input.key), ['tone']);
    expect(saved.inputs.single.required, isFalse);
  });

  test('a declaration with no placeholder is dropped on save', () async {
    final service = await SkillService.getInstance();
    await service.saveSkill(const Skill(
      id: 'stale_decl',
      name: '过期声明',
      kind: SkillKind.instruction,
      instructions: '总结当前页面。',
      inputs: [
        SkillInput(key: 'unused', label: '没用上', required: true),
      ],
    ));

    expect(service.getSkills().single.inputs, isEmpty);
  });

  test('flow notes placeholders do not become inputs', () async {
    final service = await SkillService.getInstance();
    await service.saveSkill(const Skill(
      id: 'flow_with_notes',
      name: '流程',
      kind: SkillKind.flow,
      instructions: '说明里提到 {{inputs.ignored}}，但它不参与执行。',
      steps: [
        SkillStep(
          id: 'read',
          name: '读取',
          tool: 'page.read_region',
          params: {
            'locator': {'candidates': []},
          },
        ),
      ],
    ));

    expect(service.getSkills().single.inputs, isEmpty);
  });

  test('unusedDeclarations lists fields the prompt never references', () {
    const skill = Skill(
      id: 'decl_check',
      name: '检查声明',
      kind: SkillKind.instruction,
      instructions: '按 {{inputs.content}} 总结。',
      inputs: [
        SkillInput(key: 'content', label: '内容', required: true),
        SkillInput(key: 'stale', label: '过期'),
      ],
    );

    expect(SkillInputs.unusedDeclarations(skill), ['stale']);
  });

  test('unusedDeclarations is empty when everything is used', () {
    const skill = Skill(
      id: 'decl_ok',
      name: '全部使用',
      kind: SkillKind.instruction,
      instructions: '按 {{content}} 总结，语气 {{tone}}。',
      inputs: [SkillInput(key: 'content', label: '内容')],
    );

    // `tone` is placeholder-derived, `content` is declared and used.
    expect(SkillInputs.unusedDeclarations(skill), isEmpty);
  });
}
