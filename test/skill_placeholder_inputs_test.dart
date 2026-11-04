import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/utils/skill_placeholder_inputs.dart';

void main() {
  test('undeclared placeholders become required inputs in order', () {
    final inputs = SkillPlaceholderInputs.merge(
      '用 {{inputs.tone}} 的语气回复 {{inputs.content}}。',
    );

    expect(inputs.map((input) => input.key), ['tone', 'content']);
    expect(inputs.every((input) => input.required), isTrue);
  });

  test('declared inputs are kept and not duplicated', () {
    const declared = SkillInput(
      key: 'content',
      label: '内容',
      type: SkillInputType.multiline,
      required: true,
    );
    final inputs = SkillPlaceholderInputs.merge(
      '填写 {{inputs.content}}，语气 {{inputs.tone}}。',
      existing: const [declared],
    );

    expect(inputs, hasLength(2));
    expect(inputs.first.label, '内容');
    expect(inputs.first.type, SkillInputType.multiline);
    expect(inputs.last.key, 'tone');
  });

  test('text without placeholders adds nothing', () {
    expect(SkillPlaceholderInputs.merge('总结当前页面。'), isEmpty);
    expect(SkillPlaceholderInputs.hasPlaceholders('总结当前页面。'), isFalse);
  });
}
