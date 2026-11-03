import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/skill_defaults.dart';
import 'package:operon/services/skill_validator.dart';

void main() {
  test('builtin skills have unique ids', () {
    final ids = SkillDefaults.all().map((skill) => skill.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('builtin reply is single-item and forbids draft buttons', () {
    final reply = SkillDefaults.all().firstWhere(
      (skill) => skill.id == 'quick_batch_reply',
    );

    expect(reply.policy.maxItems, 1);
    expect(reply.policy.maxSideEffects, 1);
    expect(reply.inputs.map((input) => input.key), isNot(contains('count')));
    expect(reply.instructions, contains('保存草稿'));
    expect(reply.instructions, isNot(contains('最多 {{count}} 条')));
  });

  test('builtin flow skills pass validation', () {
    final validator = SkillValidator();
    for (final skill in SkillDefaults.all()) {
      final result = validator.validate(skill);
      expect(
        result.hasErrors,
        isFalse,
        reason: '${skill.name}: ${result.repairHint}',
      );
    }
  });
}
