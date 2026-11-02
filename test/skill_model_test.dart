import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/models/tool_descriptor.dart';

void main() {
  test('skill JSON round-trip keeps inputs, steps and policy', () {
    const skill = Skill(
      id: 'skill_demo',
      name: '演示技能',
      description: '读取并总结',
      kind: SkillKind.flow,
      origin: SkillOrigin.user,
      inputs: [
        SkillInput(
          key: 'limit',
          label: '条数',
          type: SkillInputType.number,
          defaultValue: '10',
          required: true,
        ),
      ],
      steps: [
        SkillStep(
          id: 'read',
          name: '读取',
          tool: 'page.read_region',
          saveAs: 'comments',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': '.comments'},
              ],
              'requireUnique': true,
            },
            'limit': '{{inputs.limit}}',
          },
        ),
        SkillStep(
          id: 'show',
          name: '展示',
          tool: 'ui.show',
          params: {
            'title': '结果',
            'markdown': '{{steps.comments.data}}',
          },
        ),
      ],
      policy: SkillPolicy(
        maxSteps: 8,
        maxLlmCalls: 2,
        maxSideEffects: 0,
        maxItems: 10,
        hostScope: SkillHostScope.currentHost,
      ),
      builtin: false,
      sortOrder: 2,
    );

    final restored = Skill.fromJson(skill.toJson());

    expect(restored.id, 'skill_demo');
    expect(restored.name, '演示技能');
    expect(restored.kind, SkillKind.flow);
    expect(restored.origin, SkillOrigin.user);
    expect(restored.inputs.single.defaultValue, '10');
    expect(restored.steps.first.saveAs, 'comments');
    expect(restored.steps.first.contextKey, 'comments');
    expect(restored.steps.last.params['markdown'],
        '{{steps.comments.data}}');
    expect(restored.policy.hostScope, SkillHostScope.currentHost);
    expect(restored.policy.maxItems, 10);
  });

  test('unknown JSON fields are ignored and missing fields use defaults', () {
    final skill = Skill.fromJson({
      'id': 'x',
      'name': 'X',
      'unknownField': 'ignored',
      'steps': [
        {
          'id': 'a',
          'name': 'A',
          'tool': 'ui.show',
          'params': {},
        }
      ],
    });

    expect(skill.kind, SkillKind.instruction);
    expect(skill.schemaVersion, Skill.currentSchemaVersion);
    expect(skill.steps.single.enabled, isTrue);
    expect(skill.steps.single.onError.action, StepFailureAction.stop);
  });

  test('step context key falls back to id', () {
    const step = SkillStep(id: 'read', name: '读取', tool: 'page.read');
    expect(step.contextKey, 'read');
  });

  test('draft converts to a persisted skill', () {
    const draft = SkillDraft(
      name: '草稿',
      description: '描述',
      kind: SkillKind.flow,
      steps: [
        SkillStep(id: 'show', name: '展示', tool: 'ui.show'),
      ],
    );

    final skill = draft.toSkill(id: 'new_skill', sortOrder: 3);

    expect(skill.id, 'new_skill');
    expect(skill.origin, SkillOrigin.user);
    expect(skill.builtin, isFalse);
    expect(skill.sortOrder, 3);
    expect(skill.updatedAt, isNotNull);
  });

  test('tool result keeps the uniform envelope', () {
    final ok = ToolResult.success(
      data: {'count': 2},
      pageChanged: true,
      sideEffect: false,
      meta: {'confidence': 'high'},
    );
    final error = ToolResult.failure('LOCATOR_NOT_FOUND', '没有找到元素');

    expect(ok.ok, isTrue);
    expect(ok.toJson()['data'], {'count': 2});
    expect(error.ok, isFalse);
    expect(error.errorCode, 'LOCATOR_NOT_FOUND');
    expect(error.errorMessage, '没有找到元素');
  });
}
