import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/macro_workflow.dart';
import 'package:operon/services/skill_from_macro.dart';
import 'package:operon/services/skill_validator.dart';

void main() {
  test('recorded macro becomes an editable flow draft', () {
    final macro = MacroWorkflow(
      id: 'm1',
      title: '录制技能',
      initialUrl: '',
      createdAt: DateTime(2026, 1, 1),
      steps: const [
        MacroStep(
          action: 'click',
          selector: '[data-testid="reply"]',
          description: '点击回复',
          targetText: '回复',
        ),
        MacroStep(
          action: 'type',
          selector: 'textarea',
          text: '你好',
          description: '输入回复',
        ),
        MacroStep(
          action: 'press_key',
          key: 'Enter',
          description: '提交',
          nonIdempotent: true,
        ),
        MacroStep(
          action: 'scroll',
          direction: 'down',
          description: '向下滚动',
        ),
      ],
    );

    final draft = SkillFromMacro.fromMacro(macro);
    expect(draft, isNotNull);
    expect(draft!.steps.map((step) => step.tool), [
      'page.click',
      'page.type',
      'page.press_key',
      'page.scroll',
    ]);
    expect(draft.steps.first.params['locator'], contains('candidates'));
    expect(draft.policy.maxSideEffects, 3);

    final validation = SkillValidator().validateDraft(
      draft,
      allowWrites: true,
      currentHost: 'example.com',
    );
    expect(validation.hasErrors, isFalse, reason: validation.repairHint);
  });

  test('xpath selectors are preserved as xpath locators', () {
    final macro = MacroWorkflow(
      id: 'm2',
      title: 'xpath',
      initialUrl: '',
      createdAt: DateTime(2026, 1, 1),
      steps: const [
        MacroStep(
          action: 'click',
          selector: 'xpath://button[contains(text(), "发送")]',
          description: '点击发送',
        ),
      ],
    );

    final draft = SkillFromMacro.fromMacro(macro);
    final locator = draft!.steps.first.params['locator'] as Map;
    final candidate = (locator['candidates'] as List).first as Map;
    expect(candidate['type'], 'xpath');
    expect(candidate['value'], contains('button'));
  });

  test('empty macro returns null', () {
    final macro = MacroWorkflow(
      id: 'm3',
      title: 'empty',
      initialUrl: '',
      createdAt: DateTime(2026, 1, 1),
      steps: const [],
    );
    expect(SkillFromMacro.fromMacro(macro), isNull);
  });
}
