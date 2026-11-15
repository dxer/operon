import '../models/agent_conversation.dart';
import 'context.dart';

// Turning stored turns back into messages for the model.
//
// A conversation on disk is a record; what the model needs is a transcript.
// The two differ in one important way: the record keeps a step as one readable
// line, while the protocol keeps it as a tool call with an id and a payload.
//
// Replaying the protocol is not an option here. A tool call must be answered by
// a tool message with the same id, and the moment we trim a single result to
// fit the window the pairing breaks and the endpoint rejects the request. So a
// past turn goes back as plain text: what the user asked, and what happened.
// Only the turn being run right now uses the real protocol.

/// Turns older than this keep their words but lose their step-by-step trace.
///
/// The model needs the mechanics of what it just did; the mechanics of twenty
/// messages ago are archaeology, and paying for them every turn is how a
/// conversation becomes unusable after a day.
const int _tracedTurns = 5;

/// Steps kept per turn. The tail is what explains the outcome.
const int _stepsPerTurn = 12;

/// One line per step, trimmed: a summary is worth 200 characters, not a whole
/// accessibility tree.
const int _stepLineLimit = 200;

/// Told to the model once, before any of the history.
const String continuationNote = '''
## 这是同一段对话的延续

下面是你和这位用户之前的消息。它们已经发生过了：

- 用户消息里的事，你已经做过；不要重做，除非用户明确要求再来一次。
- 「这一轮的操作」是你当时真实做过的动作。里面的页面早已不是当时的样子，ref 全部失效，要用必须重新 snapshot。
- 用户说「继续」「换成第三个」「刚才那个」时，指的就是这些内容。
- 页面的当前状态以这一轮第一个 snapshot 为准，不要假设它还停在历史里的某一页。
''';

/// The messages that make a stored conversation usable as context.
List<Map<String, Object?>> priorMessages(
  List<AgentTurn> turns, {
  String? compactedSummary,
  int compactedTurns = 0,
}) {
  final summary = (compactedSummary ?? '').trim();
  final start = compactedTurns.clamp(0, turns.length);
  final active = <AgentTurn>[
    for (var i = start; i < turns.length; i++)
      if (!turns[i].isCompaction) turns[i],
  ];
  if (active.isEmpty && summary.isEmpty) return const [];

  final firstTraced = active.length - _tracedTurns;
  final messages = <Map<String, Object?>>[];
  if (summary.isNotEmpty) {
    messages.add({
      'role': 'system',
      'content': '## 早前对话的压缩摘要\n以下是之前多轮交互浓缩后的关键上下文：\n\n$summary',
    });
  }

  for (var index = 0; index < active.length; index++) {
    final turn = active[index];
    messages.add({'role': 'user', 'content': _userText(turn)});
    messages.add({
      'role': 'assistant',
      'content': _assistantText(turn, traced: index >= firstTraced),
    });
  }
  return messages;
}

/// Estimates how many tokens a conversation's uncompacted history + summary
/// will inject into the next model call.
int estimateConversationTokens(AgentConversation conversation) {
  final messages = priorMessages(
    conversation.turns,
    compactedSummary: conversation.compactedSummary,
    compactedTurns: conversation.compactedTurns,
  );
  if (messages.isEmpty) return 0;
  return ContextManager.estimateMessages(messages);
}

String _userText(AgentTurn turn) {
  final message = turn.message.trim();
  if (turn.attachmentNames.isEmpty) return message;
  return '$message\n\n（附带文件：${turn.attachmentNames.join('、')}。'
      '它们只在那一轮读取过，内容不在当前上下文里；需要时请让用户重新附带。）';
}

String _assistantText(AgentTurn turn, {required bool traced}) {
  final buffer = StringBuffer();
  final result = (turn.result ?? '').trim();
  if (result.isNotEmpty) {
    buffer.writeln(result);
  } else {
    buffer.writeln(switch (turn.status) {
      'completed' => '（已完成，没有留下总结）',
      'error' => '（这一轮执行失败）',
      'stopped' => '（这一轮被用户停止）',
      _ => '（这一轮没有完成）',
    });
  }

  final stop = (turn.stopReason ?? '').trim();
  if (stop.isNotEmpty) buffer.writeln('结束原因：$stop');

  if (traced && turn.steps.isNotEmpty) {
    final steps = turn.steps.length <= _stepsPerTurn
        ? turn.steps
        : turn.steps.sublist(turn.steps.length - _stepsPerTurn);
    buffer
      ..writeln()
      ..writeln('这一轮的操作（${turn.steps.length} 步${steps.length < turn.steps.length ? '，这里是最后 ${steps.length} 步' : ''}）：');
    for (final step in steps) {
      final line = StringBuffer('- ${step.summary}');
      if (!step.ok) line.write('（失败）');
      final detail = (step.detail ?? '').trim();
      if (detail.isNotEmpty) {
        line
          ..write(' — ')
          ..write(detail.length > _stepLineLimit
              ? '${detail.substring(0, _stepLineLimit)}…'
              : detail);
      }
      buffer.writeln(line);
    }
  } else if (turn.steps.isNotEmpty) {
    buffer.writeln('（这一轮做了 ${turn.steps.length} 步，细节已省略）');
  }
  return buffer.toString().trimRight();
}
