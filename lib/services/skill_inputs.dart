import 'dart:convert';

import '../models/skill.dart';
import '../utils/skill_placeholder_inputs.dart';

/// The single authority on which run-time inputs a skill actually has.
///
/// Placeholders are the source of truth: an input exists because the skill
/// text references it, not because some declaration says so. The declared
/// `inputs` list only decorates a placeholder (label, type, default, required).
/// A declaration with no matching placeholder is dropped, so the run sheet can
/// never show a field the skill would ignore.
class SkillInputs {
  SkillInputs._();

  /// Text that can reference inputs, in scan order.
  ///
  /// Instruction skills: the prompt itself. Flow skills: step params, their
  /// expectations and the `output` map — the fields the runner actually
  /// renders. A flow's `instructions` is only the SKILL.md 说明 section and is
  /// never evaluated, so scanning it would invent inputs nothing can use.
  static String scanText(Skill skill) {
    final buffer = StringBuffer();
    if (skill.isInstruction) {
      buffer.writeln(skill.instructions);
    }
    for (final step in skill.steps) {
      if (!step.enabled) continue;
      buffer.writeln(_encode(step.params));
      final expect = step.expect;
      if (expect != null) buffer.writeln(_encode(expect.toJson()));
    }
    for (final value in skill.output.values) {
      buffer.writeln(value);
    }
    return buffer.toString();
  }

  /// The inputs this skill will actually ask for at run time.
  static List<SkillInput> effective(Skill skill) {
    return SkillPlaceholderInputs.resolve(
      scanText(skill),
      declared: skill.inputs,
    );
  }

  /// Returns [skill] with its `inputs` list narrowed to what the placeholders
  /// actually use. Idempotent, so it is safe to apply on every load and save.
  static Skill normalize(Skill skill) {
    final resolved = effective(skill);
    if (_sameInputs(skill.inputs, resolved)) return skill;
    return skill.copyWith(inputs: resolved);
  }

  /// Declared input keys that no placeholder references.
  ///
  /// [normalize] drops these, which is right for a placeholder-first skill but
  /// surprising when the author added a field in the editor and has not written
  /// `{{inputs.key}}` into the prompt yet. Callers warn before discarding.
  static List<String> unusedDeclarations(Skill skill) {
    final used = {for (final input in effective(skill)) input.key};
    return [
      for (final input in skill.inputs)
        if (input.key.trim().isNotEmpty && !used.contains(input.key.trim()))
          input.key.trim(),
    ];
  }

  static bool _sameInputs(List<SkillInput> a, List<SkillInput> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.key != right.key ||
          left.label != right.label ||
          left.type != right.type ||
          left.defaultValue != right.defaultValue ||
          left.required != right.required ||
          left.hint != right.hint ||
          left.maxLength != right.maxLength ||
          left.options.length != right.options.length) {
        return false;
      }
      for (var j = 0; j < left.options.length; j++) {
        if (left.options[j] != right.options[j]) return false;
      }
    }
    return true;
  }

  static String _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      // A non-encodable param is a validation problem, not a scan problem.
      return value?.toString() ?? '';
    }
  }
}
