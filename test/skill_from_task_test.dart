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

  test('recorded actions default to an instruction skill', () {
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

    // A demo flow replayed later would only repeat one sentence and would
    // break as soon as the feed re-renders.
    expect(draft.kind, SkillKind.instruction);
    expect(draft.name, '推文回复');
    expect(draft.instructions, '回复第一条推文');
    expect(draft.steps, isEmpty);
  });

  test('an explicit flow request becomes a replayable flow', () {
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
        MacroStep(
          action: 'click',
          selector: '[data-testid="send"]',
          description: '点击发布',
          nonIdempotent: true,
        ),
      ],
      name: '推文回复',
      preferFlow: true,
    );

    expect(draft.kind, SkillKind.flow);
    expect(draft.steps.map((step) => step.tool),
        ['page.click', 'page.type', 'page.click']);
    // The demonstration text becomes an input instead of a hardcoded reply.
    expect(draft.steps[1].params['text'], '{{inputs.content}}');
    expect(draft.inputs.single.key, 'content');
    expect(draft.inputs.single.required, isTrue);
  });

  test('a flow request without a write stays an instruction skill', () {
    final draft = SkillFromTask.draftFor(
      goal: '读完这一页',
      steps: const [
        MacroStep(
          action: 'scroll',
          direction: 'down',
          description: '向下滚动',
        ),
      ],
      preferFlow: true,
    );

    expect(draft.kind, SkillKind.instruction);
    expect(draft.steps, isEmpty);
  });

  test('canReplayFlow requires an actual submit', () {
    expect(
      SkillFromTask.canReplayFlow(const [
        MacroStep(action: 'click', selector: '#a', description: '点击'),
      ]),
      isFalse,
    );
    expect(
      SkillFromTask.canReplayFlow(const [
        MacroStep(
          action: 'click',
          selector: '#a',
          description: '发布',
          nonIdempotent: true,
        ),
      ]),
      isTrue,
    );
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

  test('two different typed texts block the content input', () {
    // A search box and a composer are different inputs; one `content` field
    // cannot serve both, so the flow is left literal rather than made wrong.
    final draft = SkillFromTask.draftFor(
      goal: '搜索并回复',
      preferFlow: true,
      steps: const [
        MacroStep(
          action: 'type',
          selector: '#search',
          text: '关键词',
          description: '搜索',
        ),
        MacroStep(
          action: 'type',
          selector: 'textarea',
          text: '回复内容',
          description: '输入回复',
        ),
        MacroStep(
          action: 'click',
          selector: '#send',
          description: '发布',
          nonIdempotent: true,
        ),
      ],
    );

    expect(draft.kind, SkillKind.flow);
    expect(draft.inputs, isEmpty);
    expect(draft.steps[0].params['text'], '关键词');
    expect(draft.steps[1].params['text'], '回复内容');
  });

  test('long goals are shortened for the default name', () {
    const goal = '这是一个非常非常非常非常非常非常长的任务目标描述';
    final draft = SkillFromTask.draftFor(goal: goal, steps: const []);

    expect(draft.name.endsWith('…'), isTrue);
    expect(draft.name.length, lessThan(goal.length));
  });
}
