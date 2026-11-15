import 'dart:async';
import 'dart:convert';

/// Parsed outcome of a streamed OpenAI-compatible chat completion.
class LlmStreamResult {
  const LlmStreamResult({
    required this.message,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });

  final Map<String, Object?> message;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
}

class _ToolCallAccumulator {
  String id = '';
  String type = 'function';
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();

  Map<String, Object?> toJson(int fallbackIndex) => {
        'id': id.isNotEmpty ? id : 'call_$fallbackIndex',
        'type': type,
        'function': {
          'name': name.toString(),
          'arguments': arguments.toString(),
        },
      };
}

/// Accumulates OpenAI-compatible Server-Sent Events (`data: {...}`) into a
/// standard completion message while forwarding text and reasoning deltas live.
class OpenAiSseAccumulator {
  OpenAiSseAccumulator({
    this.onTextDelta,
    this.onReasoningDelta,
  });

  final void Function(String delta)? onTextDelta;
  final void Function(String delta)? onReasoningDelta;

  String _role = 'assistant';
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final Map<int, _ToolCallAccumulator> _toolCalls = <int, _ToolCallAccumulator>{};
  String? _finishReason;
  int? _promptTokens;
  int? _completionTokens;
  bool _done = false;

  bool get isDone => _done;

  /// Consumes a raw UTF-8 byte stream of SSE frames and returns the assembled
  /// message once the stream ends or emits `[DONE]`.
  Future<LlmStreamResult> consume(Stream<List<int>> byteStream) async {
    final lines = utf8.decoder.bind(byteStream).transform(const LineSplitter());
    await for (final line in lines) {
      feedLine(line);
      if (_done) break;
    }
    return build();
  }

  /// Processes a single SSE line (useful for unit tests and streaming loops).
  void feedLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith(':')) return;
    if (!trimmed.startsWith('data:')) return;

    final data = trimmed.substring(5).trim();
    if (data.isEmpty) return;
    if (data == '[DONE]') {
      _done = true;
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      // Ignore malformed/partial keepalive lines instead of tearing down the run.
      return;
    }
    if (decoded is! Map) return;
    feedChunk(Map<String, dynamic>.from(decoded));
  }

  void feedChunk(Map<String, dynamic> chunk) {
    final usage = chunk['usage'];
    if (usage is Map) {
      final prompt = (usage['prompt_tokens'] as num?)?.toInt();
      final completion = (usage['completion_tokens'] as num?)?.toInt();
      if (prompt != null) _promptTokens = prompt;
      if (completion != null) _completionTokens = completion;
    }

    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty) return;
    final first = choices.first;
    if (first is! Map) return;

    final finish = first['finish_reason'];
    if (finish is String && finish.isNotEmpty) {
      _finishReason = finish;
    }

    final delta = first['delta'];
    if (delta is! Map) return;

    final role = delta['role'];
    if (role is String && role.isNotEmpty) {
      _role = role;
    }

    final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) {
      _reasoning.write(reasoning);
      onReasoningDelta?.call(reasoning);
    }

    final content = _extractContent(delta['content']);
    if (content != null && content.isNotEmpty) {
      _content.write(content);
      onTextDelta?.call(content);
    }

    final rawToolCalls = delta['tool_calls'];
    if (rawToolCalls is List) {
      for (final entry in rawToolCalls) {
        if (entry is! Map) continue;
        final index = (entry['index'] as num?)?.toInt() ?? 0;
        final acc = _toolCalls.putIfAbsent(index, _ToolCallAccumulator.new);
        final id = entry['id']?.toString();
        if (id != null && id.isNotEmpty) acc.id = id;
        final type = entry['type']?.toString();
        if (type != null && type.isNotEmpty) acc.type = type;
        final fn = entry['function'];
        if (fn is Map) {
          final name = fn['name']?.toString();
          if (name != null && name.isNotEmpty) acc.name.write(name);
          final args = fn['arguments']?.toString();
          if (args != null && args.isNotEmpty) acc.arguments.write(args);
        }
      }
    }
  }

  String? _extractContent(Object? raw) {
    if (raw is String) return raw;
    if (raw is List) {
      final buffer = StringBuffer();
      for (final part in raw) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map) {
          final text = part['text'];
          if (text is String) {
            buffer.write(text);
          } else if (text is Map && text['value'] is String) {
            buffer.write(text['value']);
          }
        }
      }
      return buffer.isEmpty ? null : buffer.toString();
    }
    return null;
  }

  LlmStreamResult build() {
    final sortedKeys = _toolCalls.keys.toList()..sort();
    final calls = [
      for (final idx in sortedKeys) _toolCalls[idx]!.toJson(idx),
    ];
    final message = <String, Object?>{
      'role': _role,
      if (_content.isNotEmpty) 'content': _content.toString(),
      if (_reasoning.isNotEmpty) 'reasoning_content': _reasoning.toString(),
      if (calls.isNotEmpty) 'tool_calls': calls,
    };
    return LlmStreamResult(
      message: message,
      finishReason: _finishReason,
      promptTokens: _promptTokens,
      completionTokens: _completionTokens,
    );
  }
}
