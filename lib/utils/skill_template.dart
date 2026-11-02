import 'dart:convert';

class SkillTemplateException implements Exception {
  final String message;

  const SkillTemplateException(this.message);

  @override
  String toString() => message;
}

/// Renders `{{inputs.x}}`, `{{steps.alias.data}}` and `{{env.url}}` bindings.
///
/// Rules:
/// - A value that is exactly one placeholder keeps its original type.
/// - A placeholder embedded in text is stringified.
/// - Unknown references fail in strict mode so a flow never runs with an
///   accidentally empty parameter.
/// - `\{{` escapes a literal `{{`.
class SkillTemplate {
  SkillTemplate._();

  static final RegExp _token = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');
  static const String _escapedOpen = '\uE000';

  static List<String> references(String template) {
    final result = <String>[];
    for (final match in _token.allMatches(template)) {
      final ref = match.group(1)?.trim() ?? '';
      if (ref.isNotEmpty) result.add(ref);
    }
    return result;
  }

  /// Walks maps/lists and returns every template reference found in strings.
  static List<String> referencesIn(dynamic value) {
    final result = <String>[];
    void visit(dynamic node) {
      if (node is String) {
        result.addAll(references(node));
      } else if (node is Map) {
        for (final item in node.values) {
          visit(item);
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item);
        }
      }
    }

    visit(value);
    return result;
  }

  static String renderString(
    String template,
    Map<String, dynamic> context, {
    bool strict = true,
  }) {
    if (template.isEmpty) return template;
    final prepared = template.replaceAll(r'\{{', _escapedOpen);

    final exact = _token.firstMatch(prepared);
    if (exact != null &&
        exact.start == 0 &&
        exact.end == prepared.length &&
        !prepared.contains(_escapedOpen)) {
      final value =
          resolve(exact.group(1)?.trim() ?? '', context, strict: strict);
      return value == null ? '' : stringify(value);
    }

    final rendered = prepared.replaceAllMapped(_token, (match) {
      final ref = match.group(1)?.trim() ?? '';
      final value = resolve(ref, context, strict: strict);
      return value == null ? '' : stringify(value);
    });
    return rendered.replaceAll(_escapedOpen, '{{');
  }

  /// Renders a JSON-like value recursively, preserving types.
  static dynamic renderValue(
    dynamic value,
    Map<String, dynamic> context, {
    bool strict = true,
  }) {
    if (value is String) {
      final prepared = value.replaceAll(r'\{{', _escapedOpen);
      final exact = _token.firstMatch(prepared);
      if (exact != null &&
          exact.start == 0 &&
          exact.end == prepared.length &&
          !prepared.contains(_escapedOpen)) {
        return resolve(
          exact.group(1)?.trim() ?? '',
          context,
          strict: strict,
        );
      }
      return renderString(value, context, strict: strict);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(
          key.toString(),
          renderValue(item, context, strict: strict),
        ),
      );
    }
    if (value is List) {
      return value
          .map((item) => renderValue(item, context, strict: strict))
          .toList();
    }
    return value;
  }

  static Map<String, dynamic> renderParams(
    Map<String, dynamic> params,
    Map<String, dynamic> context, {
    bool strict = true,
  }) {
    final result = <String, dynamic>{};
    for (final entry in params.entries) {
      result[entry.key] = renderValue(
        entry.value,
        context,
        strict: strict,
      );
    }
    return result;
  }

  static dynamic resolve(
    String path,
    Map<String, dynamic> context, {
    bool strict = true,
  }) {
    if (path.isEmpty) {
      if (strict) throw const SkillTemplateException('空的模板变量');
      return null;
    }

    // Backward compatibility: `{{count}}` is equivalent to `{{inputs.count}}`.
    final normalized = path.contains('.') ? path : 'inputs.$path';
    dynamic current = context;
    for (final segment in normalized.split('.')) {
      if (current is Map) {
        if (!current.containsKey(segment)) {
          if (strict) {
            throw SkillTemplateException('未找到模板变量: $path');
          }
          return null;
        }
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          if (strict) {
            throw SkillTemplateException('未找到模板变量: $path');
          }
          return null;
        }
        current = current[index];
      } else {
        if (strict) {
          throw SkillTemplateException('未找到模板变量: $path');
        }
        return null;
      }
    }
    return current;
  }

  static String stringify(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }
}
