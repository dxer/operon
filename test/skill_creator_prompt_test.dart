import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/skill_creator_prompt.dart';

void main() {
  test('creator rules include the demonstration content verbatim', () {
    final rules = SkillCreatorPrompt.rules(
      sampleContent: '很有启发，感谢分享。',
      host: 'x.com',
    );

    expect(rules, contains('x.com'));
    expect(rules, contains('很有启发，感谢分享。'));
    expect(rules, contains('{{inputs.content}}'));
    expect(rules, contains('不会真正发布'));
    expect(rules, contains('不要提前 finish'));
  });

  test('creator rules still work when no sample content is supplied', () {
    final rules = SkillCreatorPrompt.rules(
      sampleContent: '   ',
      host: 'example.com',
    );

    expect(rules, contains('示例文本'));
    expect(rules, isNot(contains('很有启发')));
  });

  test('creator goal names the host and asks for a demonstration', () {
    final goal = SkillCreatorPrompt.goal(
      description: '回复时间线推文',
      host: 'x.com',
    );

    expect(goal, contains('回复时间线推文'));
    expect(goal, contains('x.com'));
    expect(goal, contains('演示'));
  });
}
