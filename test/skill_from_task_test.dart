import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/macro_workflow.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_from_task.dart';

void main() {
  test('read-only task becomes an instruction skill', () {
    final draft = SkillFromTask.draftFor(
      goal: '总结当前页面的核心技术要点',
      steps: const [],
      summary: '已总结 3 点',
    );

    expect(draft.kind, SkillKind.instruction);
    expect(draft.instructions, '总结当前页面的核心技术要点');
    expect(draft.description, '已总结 3 点');
  });

  test('recorded actions become a flow skill', () {
    final draft = SkillFromTask.draftFor(
      goal: '回复第一条推文',
      steps: const [
        MacroStep(
          action: 'click',
          selector: '[data-testid="reply"]',
          description: '点击回复',
        ),
        MacroStep(
          action: 'type',
          selector: 'textarea',
          text: '你好',
          description: '输入回复',
        ),
      ],
      name: '推文回复',
    );

    expect(draft.kind, SkillKind.flow);
    expect(draft.name, '推文回复');
    expect(draft.steps.map((step) => step.tool), ['page.click', 'page.type']);
  });

  test('unconvertible actions fall back to the instruction draft', () {
    final draft = SkillFromTask.draftFor(
      goal: '打开设置并修改主题',
      steps: const [
        MacroStep(action: 'click', description: '没有选择器'),
      ],
    );

    expect(draft.kind, SkillKind.instruction);
    expect(draft.steps, isEmpty);
    expect(draft.instructions, '打开设置并修改主题');
  });

  test('long goals are shortened for the default name', () {
    const goal = '这是一个非常非常非常非常非常非常长的任务目标描述';
    final draft = SkillFromTask.draftFor(goal: goal, steps: const []);

    expect(draft.name.endsWith('…'), isTrue);
    expect(draft.name.length, lessThan(goal.length));
  });
}
