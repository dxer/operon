import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/skill_defaults.dart';
import 'package:operon/services/skill_validator.dart';

void main() {
  test('builtin skills have unique ids', () {
    final ids = SkillDefaults.all().map((skill) => skill.id).toList();
    expect(ids.toSet().length, ids.length);
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
