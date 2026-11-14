import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/context.dart';

Map<String, Object?> assistantWithCall(String id, String name) => {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': '{}'},
        },
      ],
    };

Map<String, Object?> resultFor(String id, int chars) => {
      'role': 'tool',
      'tool_call_id': id,
      'content': 'x' * chars,
    };

/// Every assistant tool call must be answered, and every answer must belong to
/// the call before it. An endpoint rejects a conversation that breaks this.
void expectPairingIntact(List<Map<String, Object?>> messages) {
  var pending = <String>{};
  for (final message in messages) {
    switch (message['role']) {
      case 'assistant':
        expect(pending, isEmpty, reason: 'an assistant turn was left unanswered');
        final calls = message['tool_calls'];
        if (calls is List) {
          pending = {
            for (final call in calls)
              if (call is Map) '${call['id']}',
          };
        }
      case 'tool':
        final id = '${message['tool_call_id']}';
        expect(pending, contains(id), reason: 'tool result $id has no call');
        pending.remove(id);
      case 'user':
      case 'system':
        expect(pending, isEmpty, reason: 'a new message started mid-answer');
    }
  }
  expect(pending, isEmpty, reason: 'the conversation ended mid-answer');
}

List<Map<String, Object?>> conversation({int turns = 6, int resultChars = 4000}) {
  final messages = <Map<String, Object?>>[
    {'role': 'system', 'content': 'system'},
    {'role': 'user', 'content': '把这条推文回复掉'},
  ];
  for (var index = 0; index < turns; index++) {
    messages.add(assistantWithCall('c$index', 'snapshot'));
    messages.add(resultFor('c$index', resultChars));
  }
  return messages;
}

void main() {
  group('estimate', () {
    test('counts characters conservatively', () {
      expect(ContextManager.estimateTokens(''), 0);
      // Four latin characters are about one token.
      expect(ContextManager.estimateTokens('abcd'), 1);
      // Chinese really costs about 0.6 tokens per character; charging one is
      // the conservative side, which is the only side that is safe.
      expect(ContextManager.estimateTokens('你好世界'), 4);
    });

    test('adds the tool call arguments to the estimate', () {
      final withCall = [assistantWithCall('c1', 'type'), resultFor('c1', 100)];
      final withoutCall = [
        {'role': 'assistant', 'content': ''},
        resultFor('c1', 100),
      ];
      expect(
        ContextManager.estimateMessages(withCall),
        greaterThan(ContextManager.estimateMessages(withoutCall)),
      );
    });
  });

  group('prepare', () {
    test('a short conversation is sent untouched', () {
      final messages = conversation(turns: 2, resultChars: 100);
      final plan = ContextManager().prepare(messages);
      expect(plan.changed, isFalse);
      expect(plan.messages, hasLength(messages.length));
      expect(plan.stop, isNull);
    });

    test('old results become stubs but keep their message and id', () {
      final messages = conversation(turns: 8);
      // Elision alone is enough here: 8 x 4000 chars of results shrink to 4
      // stubs, and the rest still fits, so nothing is dropped.
      final plan = ContextManager(limits: const ContextLimits(windowTokens: 10000)).prepare(messages);

      expect(plan.elided, greaterThan(0));
      expect(plan.droppedTurns, 0);
      expect(plan.messages, hasLength(messages.length));
      expectPairingIntact(plan.messages);

      // The newest results stay full.
      final tools = plan.messages.where((message) => message['role'] == 'tool').toList();
      expect('${tools.last['content']}'.length, 4000);
      expect('${tools.first['content']}', contains('已省略'));
    });

    test('the system prompt and every user message survive', () {
      final messages = conversation(turns: 6)
        ..insert(4, {'role': 'user', 'content': '另外把时间也记下来'});
      final plan = ContextManager(limits: const ContextLimits(windowTokens: 10000)).prepare(messages);
      expect(plan.messages.first['content'], 'system');
      expect(
        plan.messages.where((message) => message['role'] == 'user').map((message) => message['content']),
        containsAll(['把这条推文回复掉', '另外把时间也记下来']),
      );
    });

    test('a conversation that cannot fit stops the run instead of being sent', () {
      // A goal too large to send: nothing may shorten it, so the only honest
      // answer is to stop before the request.
      final messages = conversation(turns: 2, resultChars: 200)
        ..add({'role': 'user', 'content': '把这段要求看完：' * 400});
      final plan = ContextManager(
        limits: const ContextLimits(windowTokens: 200, threshold: 0.1, hardLimit: 0.2),
      ).prepare(messages);

      expect(plan.stop, isNotNull);
      // Even when it gives up, what it hands back is still a valid conversation.
      expectPairingIntact(plan.messages);
    });

    test('everything droppable goes before a run gives up', () {
      final messages = conversation(turns: 30, resultChars: 4000);
      final plan = ContextManager(
        limits: const ContextLimits(windowTokens: 400, threshold: 0.1, hardLimit: 0.3),
      ).prepare(messages);
      expect(plan.droppedTurns, greaterThan(0));
      expect(plan.messages.where((message) => message['role'] == 'user'), hasLength(1));
      expectPairingIntact(plan.messages);
    });

    test('dropping turns never leaves a call unanswered', () {
      final messages = conversation(turns: 12);
      final plan = ContextManager(
        limits: const ContextLimits(windowTokens: 2500, threshold: 0.2, hardLimit: 0.5),
      ).prepare(messages);
      expectPairingIntact(plan.messages);
      if (plan.droppedTurns > 0) {
        expect(plan.messages.length, lessThan(messages.length));
      }
    });
  });
}
