import '../models/skill.dart';

/// Derives run-time inputs from `{{...}}` placeholders.
///
/// Placeholders are the source of truth: a prompt skill is just text, and the
/// only thing that tells us it needs a value is the reference itself. The
/// declared `inputs` list decorates a placeholder (label, type, default,
/// required) but never invents one.
///
/// Both spellings are equivalent, matching [SkillTemplate] and the validator:
/// `{{inputs.content}}` and `{{content}}`.
class SkillPlaceholderInputs {
  SkillPlaceholderInputs._();

  /// Matches `{{name}}` and `{{inputs.name}}`. `steps.`, `env.`, `run.`,
  /// `item` and `index` are handled by the template engine and are skipped.
  static final RegExp _token = RegExp(
    r'\{\{\s*(?:inputs\.)?([A-Za-z0-9_一-龥-]+)\s*\}\}',
  );

  static const Set<String> _reserved = {
    'steps',
    'env',
    'run',
    'item',
    'index',
  };

  /// Replaces an escaped `\{{` with a character that cannot start a token.
  static String _guardEscapes(String text) => text.replaceAll(
        r'\{{',
        String.fromCharCode(0xE000),
      );

  /// Placeholder keys in first-appearance order, without duplicates.
  static List<String> keysOf(String text) {
    if (text.isEmpty) return const [];
    final prepared = _guardEscapes(text);
    final seen = <String>{};
    final keys = <String>[];
    for (final match in _token.allMatches(prepared)) {
      final key = match.group(1) ?? '';
      if (key.isEmpty || _reserved.contains(key)) continue;
      if (seen.add(key)) keys.add(key);
    }
    return keys;
  }

  /// One [SkillInput] per placeholder found in [text].
  ///
  /// Declared inputs keep their metadata; placeholders without a declaration
  /// get a readable label and stay optional, so the run sheet does not block on
  /// a field the author never asked for. Declarations with no placeholder are
  /// dropped.
  static List<SkillInput> resolve(
    String text, {
    List<SkillInput> declared = const [],
  }) {
    final byKey = <String, SkillInput>{
      for (final input in declared)
        if (input.key.trim().isNotEmpty) input.key.trim(): input,
    };
    return [
      for (final key in keysOf(text)) byKey[key] ?? _defaultInput(key),
    ];
  }

  static SkillInput _defaultInput(String key) {
    return SkillInput(
      key: key,
      label: labelFor(key),
      type: SkillInputType.text,
      required: false,
    );
  }

  /// Readable fallback label for a key nobody declared.
  static String labelFor(String key) {
    final known = _labelHints[key.toLowerCase()];
    if (known != null) return known;
    // `reply_text` reads better as `reply text` than as a bare identifier.
    return key.replaceAll('_', ' ');
  }

  static const Map<String, String> _labelHints = {    'content': '内容',
    'text': '文本',
    'query': '查询',
    'keyword': '关键词',
    'keywords': '关键词',
    'count': '数量',
    'limit': '数量',
    'max': '数量',
    'tone': '语气',
    'style': '风格',
    'length': '长度',
    'url': '网址',
    'link': '链接',
    'topic': '主题',
    'focus': '关注重点',
    'language': '语言',
    'name': '名称',
    'title': '标题',
  };
}
