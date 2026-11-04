import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/utils/skill_placeholder_inputs.dart';

void main() {
  test('undeclared placeholders become optional inputs in order', () {
    final inputs = SkillPlaceholderInputs.resolve(
      '用 {{inputs.tone}} 的语气回复 {{inputs.content}}。',
    );

    expect(inputs.map((input) => input.key), ['tone', 'content']);
    // A placeholder the author never declared must not block the run: the
    // declaration is what marks a field required.
    expect(inputs.every((input) => input.required), isFalse);
  });

  test('bare placeholders are equivalent to inputs.*', () {
    final inputs = SkillPlaceholderInputs.resolve(
      '总结 {{query}}，语气 {{tone}}。',
    );

    expect(inputs.map((input) => input.key), ['query', 'tone']);
  });

  test('step, env, run and item references are not inputs', () {
    final inputs = SkillPlaceholderInputs.resolve(
      '{{steps.read.data}} {{env.url}} {{run.id}} {{item}} {{index}}',
    );

    expect(inputs, isEmpty);
  });

  test('escaped placeholders do not create inputs', () {
    expect(SkillPlaceholderInputs.resolve(r'字面量 \{{notAVariable}}'), isEmpty);
  });

  test('declared metadata decorates the placeholder', () {
    const declared = SkillInput(
      key: 'content',
      label: '内容',
      type: SkillInputType.multiline,
      required: true,
      hint: '要发布的内容',
    );
    final inputs = SkillPlaceholderInputs.resolve(
      '填写 {{inputs.content}}，语气 {{tone}}。',
      declared: const [declared],
    );

    expect(inputs, hasLength(2));
    expect(inputs.first.label, '内容');
    expect(inputs.first.type, SkillInputType.multiline);
    expect(inputs.first.required, isTrue);
    expect(inputs.last.key, 'tone');
  });

  test('declarations without a placeholder are dropped', () {
    const declared = SkillInput(key: 'unused', label: '没用上');
    final inputs = SkillPlaceholderInputs.resolve(
      '总结当前页面。',
      declared: const [declared],
    );

    expect(inputs, isEmpty);
  });

  test('undeclared keys get a readable label', () {
    expect(SkillPlaceholderInputs.labelFor('content'), '内容');
    expect(SkillPlaceholderInputs.labelFor('tone'), '语气');
    expect(SkillPlaceholderInputs.labelFor('reply_text'), 'reply text');
  });

  test('text without placeholders adds nothing', () {
    expect(SkillPlaceholderInputs.resolve('总结当前页面。'), isEmpty);
    expect(
      SkillPlaceholderInputs.keysOf('总结当前页面。'),
      isEmpty,
    );
  });
}
