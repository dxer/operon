import 'dart:convert';

class JsonParser {
  /// Extracts and parses the first valid JSON object from LLM response text
  static Map<String, dynamic>? extractJson(String text) {
    if (text.trim().isEmpty) return null;

    String candidate = text.trim();

    // 1. Check for markdown code blocks ```json ... ``` or ``` ... ```
    final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
    final match = codeBlockRegex.firstMatch(candidate);
    if (match != null && match.groupCount >= 1) {
      candidate = match.group(1)?.trim() ?? candidate;
    }

    // 2. Direct tryParse
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Continue to bracket matching fallback
    }

    // 3. Find outer '{' and '}'
    final startIdx = candidate.indexOf('{');
    final endIdx = candidate.lastIndexOf('}');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      final substring = candidate.substring(startIdx, endIdx + 1);
      try {
        final decoded = jsonDecode(substring);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (e) {
        // Fallback: try cleaning control characters
        try {
          final cleaned = substring.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
          final decoded = jsonDecode(cleaned);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }
    }

    return null;
  }
}
