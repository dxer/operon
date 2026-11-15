import 'dart:math' as math;

/// Keeps the conversation inside the model's window without losing the task.
///
/// Two moves, cheapest first:
///
/// 1. **Elide**: old tool results become stubs. The message stays, so the
///    assistant/tool pairing an OpenAI-compatible endpoint requires stays
///    valid, and only the bulk goes.
/// 2. **Drop**: when even stubs do not fit, the oldest whole turns go, replaced
///    by one line saying how many. A turn is removed whole — an assistant
///    message with tool calls is never left without its results.
///
/// The system prompt, the first user message and every later user message are
/// never shortened or dropped: the task must survive a long run.
class ContextLimits {
  const ContextLimits({
    this.windowTokens = 200000,
    this.threshold = 0.6,
    this.hardLimit = 0.85,
    this.autoCompact = true,
    this.autoCompactTokens,
    this.keepRecentResults = 4,
    this.keepRecentImages = 1,
    this.stubChars = 140,
  });

  /// Conservative token budget charged per attached/screenshot image.
  static const int imageTokenEstimate = 1024;

  final int windowTokens;

  /// From here, old results are elided when [autoCompactTokens] is unset.
  final double threshold;

  /// Past here, whole turns are dropped. Over it even after both moves, the
  /// run stops instead of sending a request the provider will reject.
  final double hardLimit;

  /// Whether automatic compaction runs before reaching the model's hard limit.
  final bool autoCompact;

  /// User-configured Auto-Compact trigger size in tokens (e.g., 200000).
  /// When null, falls back to `[windowTokens] * [threshold]`.
  final int? autoCompactTokens;

  /// How many of the newest tool results stay full.
  final int keepRecentResults;

  /// How many of the newest page screenshots stay attached as images.
  final int keepRecentImages;

  final int stubChars;
}

/// What to send now, and whether the run may go on.
class ContextPlan {
  const ContextPlan({
    required this.messages,
    required this.estimatedTokens,
    this.stop,
    this.elided = 0,
    this.droppedTurns = 0,
    this.autoCompacted = false,
  });

  final List<Map<String, Object?>> messages;
  final int estimatedTokens;

  /// Set when the conversation cannot be made to fit.
  final String? stop;

  final int elided;
  final int droppedTurns;
  final bool autoCompacted;

  bool get changed => elided > 0 || droppedTurns > 0;
}

/// The outcome of shortening one conversation.
class _Trim {
  const _Trim(this.messages, this.droppedTurns);

  final List<Map<String, Object?>> messages;
  final int droppedTurns;
}

class ContextManager {
  ContextManager({this.limits = const ContextLimits()});

  final ContextLimits limits;

  ContextPlan prepare(
    List<Map<String, Object?>> messages, {
    int? observedPromptTokens,
  }) {
    final hardLimit = (limits.windowTokens * limits.hardLimit).round();
    final rawEstimate =
        math.max(estimateMessages(messages), observedPromptTokens ?? 0);

    // When Auto-Compact is turned off, leave context untouched until it
    // approaches the model's hard physical window.
    if (!limits.autoCompact && rawEstimate <= hardLimit) {
      return ContextPlan(
        messages: messages,
        estimatedTokens: rawEstimate,
      );
    }

    final elided = _elide(messages);
    final elidedCharEstimate = estimateMessages(elided.messages);
    final estimate = elided.count > 0
        ? elidedCharEstimate
        : math.max(elidedCharEstimate, observedPromptTokens ?? 0);

    final rawThreshold =
        limits.autoCompactTokens ?? (limits.windowTokens * limits.threshold).round();
    final softLimit = limits.autoCompact
        ? (rawThreshold <= hardLimit
            ? rawThreshold
            : math.min(rawThreshold, (limits.windowTokens * limits.threshold).round()))
        : hardLimit;

    if (estimate < softLimit && estimate <= hardLimit) {
      return ContextPlan(
        messages: elided.messages,
        estimatedTokens: estimate,
        elided: elided.count,
      );
    }

    // Explicit Auto-Compact threshold reached while still below hardLimit:
    // shed older intermediate turns so context stays comfortably below trigger.
    if (limits.autoCompact &&
        limits.autoCompactTokens != null &&
        estimate >= softLimit &&
        estimate <= hardLimit) {
      final compactTarget = math.max((softLimit * 0.7).round(), 1);
      final trimmed = _dropOldTurns(elided.messages, compactTarget);
      final after = estimateMessages(trimmed.messages);
      return ContextPlan(
        messages: trimmed.messages,
        estimatedTokens: after,
        elided: elided.count,
        droppedTurns: trimmed.droppedTurns,
        autoCompacted: elided.count > 0 || trimmed.droppedTurns > 0,
      );
    }

    // Between softLimit and hardLimit when using default ratio threshold.
    if (estimate <= hardLimit) {
      return ContextPlan(
        messages: elided.messages,
        estimatedTokens: estimate,
        elided: elided.count,
      );
    }

    final trimmed = _dropOldTurns(elided.messages, hardLimit);
    final after = estimateMessages(trimmed.messages);
    return ContextPlan(
      messages: trimmed.messages,
      estimatedTokens: after,
      elided: elided.count,
      droppedTurns: trimmed.droppedTurns,
      autoCompacted: limits.autoCompact &&
          (elided.count > 0 || trimmed.droppedTurns > 0),
      stop: after > hardLimit
          ? '对话已经超出模型的上下文窗口（约 ${after ~/ 1000}k tokens），'
              '继续下去只会被截断。请把任务拆小，或换一个上下文更大的模型。'
          : null,
    );
  }

  /// Tokens are estimated from characters, not counted.
  ///
  /// A tokenizer per provider is not worth a dependency here, and the estimate
  /// only decides when to start shortening. It must not undercount, or a
  /// request could be sent over the window: a CJK character is charged as one
  /// token (really about 0.6), four other characters as one (really about 3.5
  /// for English, but code and JSON are denser than prose).
  static int estimateTokens(String text) {
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (rune >= 0x2E80) {
        cjk++;
      } else {
        other++;
      }
    }
    return cjk + (other / 4).ceil();
  }

  static int estimateMessages(List<Map<String, Object?>> messages) {
    var total = 0;
    for (final message in messages) {
      total += 4; // role and framing overhead
      final content = message['content'];
      if (content is String) {
        total += estimateTokens(content);
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type'];
          if (type == 'image_url') {
            total += ContextLimits.imageTokenEstimate;
          } else if (part['text'] != null) {
            total += estimateTokens('${part['text']}');
          }
        }
      }
      final calls = message['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          if (call is Map) {
            final function = call['function'];
            if (function is Map) {
              total += estimateTokens('${function['name']}${function['arguments']}');
            }
          }
        }
      }
    }
    return total;
  }

  /// Shortens old tool results and older page screenshots, keeping the newest
  /// [ContextLimits.keepRecentResults] and [ContextLimits.keepRecentImages].
  ///
  /// The message itself stays: an assistant message with tool calls must be
  /// answered, and an endpoint rejects the request when one is missing.
  _Elide _elide(List<Map<String, Object?>> messages) {
    final toolIndexes = <int>[
      for (var index = 0; index < messages.length; index++)
        if (messages[index]['role'] == 'tool') index,
    ];
    final screenshotIndexes = <int>[
      for (var index = 0; index < messages.length; index++)
        if (_isPageScreenshot(messages[index])) index,
    ];
    final elideTools = toolIndexes.length > limits.keepRecentResults;
    final elideImages = screenshotIndexes.length > limits.keepRecentImages;
    if (!elideTools && !elideImages) {
      return _Elide(messages, 0);
    }

    final result = List<Map<String, Object?>>.of(messages);
    var count = 0;
    if (elideTools) {
      final elideUpTo = toolIndexes.length - limits.keepRecentResults;
      for (var position = 0; position < elideUpTo; position++) {
        final index = toolIndexes[position];
        final message = result[index];
        final content = message['content'];
        if (content is! String || content.length <= limits.stubChars) continue;
        result[index] = {
          ...message,
          'content': '[早先的工具结果已省略，原长 ${content.length} 字符。'
              '需要时用 snapshot 重新读取当前页面。]',
        };
        count++;
      }
    }
    if (elideImages) {
      final elideUpTo = screenshotIndexes.length - limits.keepRecentImages;
      for (var position = 0; position < elideUpTo; position++) {
        final index = screenshotIndexes[position];
        result[index] = const {
          'role': 'user',
          'content': '[早先的页面截图已省略，需要时重新 screenshot。]',
        };
        count++;
      }
    }
    return _Elide(result, count);
  }

  static bool _isPageScreenshot(Map<String, Object?> message) {
    if (message['role'] != 'user') return false;
    final content = message['content'];
    if (content is! List) return false;
    var hasImage = false;
    var hasMarker = false;
    for (final part in content) {
      if (part is! Map) continue;
      if (part['type'] == 'image_url') hasImage = true;
      final text = part['text'];
      if (text is String && text.startsWith('上面这张图是当前页面的截图')) {
        hasMarker = true;
      }
    }
    return hasImage && hasMarker;
  }

  /// Drops the oldest whole turns until the conversation fits.
  ///
  /// A user or system message is never part of a droppable turn, and a turn is
  /// removed with all of its results, so what is left is always a conversation
  /// an endpoint will accept.
  _Trim _dropOldTurns(List<Map<String, Object?>> messages, int hardLimit) {
    final items = _items(messages);
    final turnIndexes = <int>[
      for (var index = 0; index < items.length; index++)
        if (!items[index].pinned) index,
    ];
    if (turnIndexes.isEmpty) return _Trim(messages, 0);

    for (var dropCount = 1; dropCount <= turnIndexes.length; dropCount++) {
      final dropSet = turnIndexes.take(dropCount).toSet();
      final kept = <Map<String, Object?>>[];
      var noteInserted = false;
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item.pinned) {
          kept.addAll(item.messages);
          continue;
        }
        if (dropSet.contains(index)) {
          if (!noteInserted) {
            kept.add({'role': 'assistant', 'content': _note(dropCount)});
            noteInserted = true;
          }
          continue;
        }
        kept.addAll(item.messages);
      }
      if (estimateMessages(kept) <= hardLimit) return _Trim(kept, dropCount);
    }
    // Not even one turn fits on its own: hand the conversation back unchanged
    // and let the caller stop the run instead of sending a mutilated request.
    return _Trim(messages, 0);
  }

  String _note(int turns) =>
      '[已省略 $turns 轮更早的交互记录，任务仍在继续。需要时重新 snapshot。]';

  /// Splits a conversation into pinned messages and removable turns.
  ///
  /// A turn starts at an assistant message and includes every result that
  /// answers it. A user or system message is pinned: it is never dropped, so a
  /// later instruction from the user survives even a very long run.
  List<_Item> _items(List<Map<String, Object?>> messages) {
    final items = <_Item>[];
    var index = 0;
    while (index < messages.length) {
      final role = messages[index]['role'];
      if (role != 'assistant') {
        items.add(_Item(true, [messages[index]]));
        index++;
        continue;
      }
      final start = index;
      index++;
      while (index < messages.length && messages[index]['role'] == 'tool') {
        index++;
      }
      items.add(_Item(false, messages.sublist(start, index)));
    }
    return items;
  }
}

class _Item {
  const _Item(this.pinned, this.messages);

  final bool pinned;
  final List<Map<String, Object?>> messages;
}

class _Elide {
  const _Elide(this.messages, this.count);

  final List<Map<String, Object?>> messages;
  final int count;
}

