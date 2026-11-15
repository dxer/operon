import '../models/agent_conversation.dart';
import '../models/llm_config.dart';
import '../services/llm_service.dart';
import '../utils/cancellation.dart';
import 'context.dart';
import 'transcript.dart';

/// Built-in slash command offered alongside user-created quick prompts.
class BuiltinSlashCommand {
  const BuiltinSlashCommand({
    required this.name,
    required this.label,
    required this.description,
  });

  final String name;
  final String label;
  final String description;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.contains(q) || description.toLowerCase().contains(q);
  }
}

const List<BuiltinSlashCommand> builtinSlashCommands = [
  BuiltinSlashCommand(
    name: 'compact',
    label: '/compact [重点说明]',
    description: '压缩当前对话上下文，总结关键结论并释放上下文空间',
  ),
];

/// Parsed `/compact` invocation from the composer or prompt runner.
class CompactCommandInput {
  const CompactCommandInput({this.focusNote = ''});

  final String focusNote;
}

/// Parses `/compact` or `/compact <focus note>` cleanly without matching
/// unrelated prose that merely mentions `/compact` later in a sentence.
CompactCommandInput? parseCompactCommand(String input) {
  final trimmed = input.trim();
  if (!trimmed.toLowerCase().startsWith('/compact')) return null;
  final rest = trimmed.substring('/compact'.length);
  if (rest.isNotEmpty && !RegExp(r'^\s').hasMatch(rest)) return null;
  return CompactCommandInput(focusNote: rest.trim());
}

/// Result of compacting an [AgentConversation].
class CompactionOutcome {
  const CompactionOutcome({
    required this.summary,
    required this.compactedTurnCount,
    required this.beforeTokens,
    required this.afterTokens,
    required this.usedLlm,
  });

  final String summary;
  final int compactedTurnCount;
  final int beforeTokens;
  final int afterTokens;
  final bool usedLlm;
}

/// Summarizes earlier conversation turns into a dense summary block so long
/// browser sessions can continue cleanly via `/compact` or Auto-Compact.
class ContextCompactor {
  static const int _maxResultExcerptChars = 600;
  static const int _maxFallbackLines = 12;

  static Future<CompactionOutcome> compactConversation(
    AgentConversation conversation, {
    required LlmConfig config,
    String focusNote = '',
    LlmService? llmService,
    CancellationToken? cancelToken,
    void Function(String delta)? onDelta,
  }) async {
    final active = conversation.uncompactedTurns;
    final beforeTokens = estimateConversationTokens(conversation);
    final priorSummary = (conversation.compactedSummary ?? '').trim();

    if (active.isEmpty && priorSummary.isEmpty) {
      return const CompactionOutcome(
        summary: '',
        compactedTurnCount: 0,
        beforeTokens: 0,
        afterTokens: 0,
        usedLlm: false,
      );
    }

    final transcriptText = _buildSourceTranscript(
      priorSummary: priorSummary,
      turns: active,
    );

    String summary = '';
    var usedLlm = false;
    final ownedService = llmService == null ? LlmService() : null;
    final client = llmService ?? ownedService!;
    try {
      if (config.isValid) {
        final focusClause = focusNote.trim().isEmpty
            ? ''
            : '\n用户特别要求重点保留：${focusNote.trim()}\n';
        final prompt = '''
请把下面浏览器智能体与用户的历史对话压缩成一份简洁、高密度、忠实事实的中文上下文摘要，供后续继续执行任务使用。
$focusClause
输出要求：
1. 用简洁要点分条输出，总字数尽量控制在 400 字以内；
2. 保留：用户核心目标与偏好、已完成的关键页面操作、重要 URL、提取到的核心数据/结论、以及未完成或失败的事项；
3. 删去冗余过程噪音与失效的局部细节，不要编造对话中未出现的信息。

历史内容：
$transcriptText
''';
        summary = (await client.chatCompletion(
          config: config,
          messages: [
            {
              'role': 'system',
              'content': '你是一个精确提炼对话上下文摘要的助手，只保留对后续操作和回答有用的客观事实。',
            },
            {'role': 'user', 'content': prompt},
          ],
          temperature: 0.2,
          cancelToken: cancelToken,
          onDelta: onDelta,
        ))
            .trim();
        usedLlm = summary.isNotEmpty;
      }
    } on LlmCancelledException {
      rethrow;
    } catch (_) {
      // Fall back to deterministic local compaction so `/compact` and
      // Auto-Compact stay reliable even when the endpoint errors out.
    } finally {
      ownedService?.dispose();
    }

    if (summary.isEmpty) {
      summary = fallbackSummarize(
        priorSummary: priorSummary,
        turns: active,
        focusNote: focusNote,
      );
    }

    return CompactionOutcome(
      summary: summary,
      compactedTurnCount: active.length,
      beforeTokens: beforeTokens,
      afterTokens: ContextManager.estimateTokens(summary),
      usedLlm: usedLlm,
    );
  }

  /// Deterministic offline fallback used when no LLM endpoint is configured or
  /// the summarization call fails.
  static String fallbackSummarize({
    String priorSummary = '',
    required List<AgentTurn> turns,
    String focusNote = '',
  }) {
    final buffer = StringBuffer();
    final trimmedPrior = priorSummary.trim();
    if (trimmedPrior.isNotEmpty) {
      buffer.writeln('早前摘要：$trimmedPrior');
    }
    if (focusNote.trim().isNotEmpty) {
      buffer.writeln('关注重点：${focusNote.trim()}');
    }
    final recent = turns.length <= _maxFallbackLines
        ? turns
        : turns.sublist(turns.length - _maxFallbackLines);
    if (turns.length > recent.length) {
      buffer.writeln('（更早的 ${turns.length - recent.length} 轮对话已归并）');
    }
    for (final turn in recent) {
      final goal = turn.message.replaceAll(RegExp(r'\s+'), ' ').trim();
      final outcome = (turn.result ?? turn.stopReason ?? '').trim();
      final oneLineOutcome = outcome.replaceAll(RegExp(r'\s+'), ' ');
      final clippedOutcome = oneLineOutcome.length > 120
          ? '${oneLineOutcome.substring(0, 120)}…'
          : oneLineOutcome;
      final urlPart =
          (turn.targetUrl ?? '').isNotEmpty ? ' [${turn.targetUrl}]' : '';
      buffer.write('- 用户：$goal$urlPart');
      if (clippedOutcome.isNotEmpty) {
        buffer.write(' → $clippedOutcome');
      } else {
        buffer.write('（${turn.status}）');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static String _buildSourceTranscript({
    required String priorSummary,
    required List<AgentTurn> turns,
  }) {
    final buffer = StringBuffer();
    if (priorSummary.isNotEmpty) {
      buffer
        ..writeln('【早前摘要】')
        ..writeln(priorSummary)
        ..writeln();
    }
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      buffer.writeln('### 第 ${i + 1} 轮');
      buffer.writeln('用户：${turn.message.trim()}');
      if ((turn.targetUrl ?? '').isNotEmpty) {
        buffer.writeln('页面：${turn.targetUrl}');
      }
      if (turn.steps.isNotEmpty) {
        buffer.writeln(
          '操作：${turn.steps.take(8).map((s) => s.summary).join('；')}',
        );
      }
      final result = (turn.result ?? turn.stopReason ?? '').trim();
      if (result.isNotEmpty) {
        final clipped = result.length > _maxResultExcerptChars
            ? '${result.substring(0, _maxResultExcerptChars)}…'
            : result;
        buffer.writeln('结果：$clipped');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}
