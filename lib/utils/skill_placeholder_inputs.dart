import '../models/skill.dart';

/// Derives run-time inputs from `{{inputs.key}}` placeholders.
///
/// A prompt skill is just text, so authors (and the model) often reference an
/// input without declaring it. Without this step the placeholder would render
/// as an empty string and the skill would silently do the wrong thing.
class SkillPlaceholderInputs {
  SkillPlaceholderInputs._();

  static final RegExp _placeholder =
      RegExp(r'\{\{\s*inputs\.([A-Za-z0-9_一-龥-]+)');

  /// Returns [existing] plus one text input per undeclared placeholder, in
  /// first-appearance order. Existing inputs keep their order and settings.
  static List<SkillInput> merge(
    String text, {
    List<SkillInput> existing = const [],
  }) {
    final keys = {for (final input in existing) input.key};
    final result = <SkillInput>[...existing];
    for (final match in _placeholder.allMatches(text)) {
      final key = match.group(1) ?? '';
      if (key.isEmpty || !keys.add(key)) continue;
      result.add(SkillInput(
        key: key,
        label: key,
        type: SkillInputType.text,
        required: true,
      ));
    }
    return result;
  }

  static bool hasPlaceholders(String text) => _placeholder.hasMatch(text);
}
