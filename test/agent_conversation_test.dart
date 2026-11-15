import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/transcript.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_conversation.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/services/conversation_store.dart';
import 'package:operon/views/widgets/agent_bottom_sheet.dart';


// A conversation is the thing that makes the agent feel like a chat instead of
// a command runner: it survives, it can be read again, and the next message
// knows what the last one did. Each test here pins one of those three.

AgentTurn turn({
  String message = '把这三条整理成要点',
  String status = 'completed',
  String? result = '整理好了。',
  int steps = 2,
  DateTime? at,
}) {
  final start = at ?? DateTime(2026, 3, 1, 10);
  return AgentTurn(
    id: 't${start.microsecondsSinceEpoch}',
    message: message,
    startedAt: start,
    endedAt: start.add(const Duration(seconds: 12)),
    status: status,
    result: result,
    steps: [
      for (var i = 0; i < steps; i++)
        AgentTurnStep(tool: 'click', summary: '点击第 ${i + 1} 条'),
    ],
  );
}

void main() {
  group('the store', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('operon-conversations');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('a turn survives a restart with its steps and tokens', () async {
      final store = await ConversationStore.open(directory: dir);
      final conversation = store.create(now: DateTime(2026, 3, 1, 9));
      await store.appendTurn(conversation.id, turn(steps: 3));

      // A second run of the app reads the same file.
      final reopened = await ConversationStore.open(directory: dir);
      expect(reopened.conversations, hasLength(1));
      final restored = reopened.conversations.first;
      expect(restored.turns, hasLength(1));
      expect(restored.turns.first.message, '把这三条整理成要点');
      expect(restored.turns.first.steps, hasLength(3));
      expect(restored.displayTitle, '把这三条整理成要点');
    });

    test('rename sticks, delete is gone from disk', () async {
      final store = await ConversationStore.open(directory: dir);
      final conversation = store.create();
      await store.appendTurn(conversation.id, turn());
      await store.rename(conversation.id, ' 我的清单 ');

      final renamed = await ConversationStore.open(directory: dir);
      expect(renamed.conversations.first.title, '我的清单');

      await renamed.delete(conversation.id);
      final empty = await ConversationStore.open(directory: dir);
      expect(empty.conversations, isEmpty);
    });

    test('a save that lands mid-write is still on disk when it returns',
        () async {
      final store = await ConversationStore.open(directory: dir);
      final conversation = store.create();
      await store.appendTurn(conversation.id, turn());

      // Second change while the first write is still running: coalescing must
      // merge them, not drop the later one behind the earlier write.
      final first = store.save();
      final renamed = store.rename(conversation.id, '后到的标题');
      await Future.wait([first, renamed]);

      final reopened = await ConversationStore.open(directory: dir);
      expect(reopened.conversations.first.title, '后到的标题');
      expect(reopened.conversations.first.turns, hasLength(1));
    });

    test('a conversation with no message is not kept', () async {
      final store = await ConversationStore.open(directory: dir);
      final opened = store.create();
      await store.appendTurn(opened.id, turn());
      store.create();
      // Opening the panel and closing it again leaves nothing behind.
      await store.pruneEmpty();

      final reopened = await ConversationStore.open(directory: dir);
      expect(reopened.conversations, hasLength(1));
      expect(reopened.conversations.first.id, opened.id);
    });

    test('a corrupt file empties the list instead of crashing the app', () async {
      await File('${dir.path}${Platform.pathSeparator}conversations.json')
          .writeAsString('{not json');
      final store = await ConversationStore.open(directory: dir);
      expect(store.conversations, isEmpty);

      // And it can still be used afterwards.
      final conversation = store.create();
      await store.appendTurn(conversation.id, turn());
      final reopened = await ConversationStore.open(directory: dir);
      expect(reopened.conversations, hasLength(1));
    });

    test('the newest conversation is first', () async {
      final store = await ConversationStore.open(directory: dir);
      final older = store.create(now: DateTime(2026, 3, 1, 9));
      await store.appendTurn(older.id, turn(at: DateTime(2026, 3, 1, 9)));
      final newer = store.create(now: DateTime(2026, 3, 2, 9));
      await store.appendTurn(newer.id, turn(at: DateTime(2026, 3, 2, 9)));

      expect(store.conversations.first.id, newer.id);
    });
  });

  group('the transcript handed to the model', () {
    test('a past turn goes back as what the user asked and what happened', () {
      final messages = priorMessages([
        turn(message: '打开热榜', result: '前五名在这。', steps: 2),
      ]);

      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'], '打开热榜');
      expect(messages[1]['role'], 'assistant');
      expect('${messages[1]['content']}', contains('前五名在这。'));
      expect('${messages[1]['content']}', contains('点击第 1 条'));
    });

    test('old turns keep their words but drop the trace', () {
      final turns = [
        for (var i = 0; i < 8; i++)
          turn(message: '第 $i 轮', result: '第 $i 轮好了', steps: 2),
      ];
      final messages = priorMessages(turns);

      // The first turn is archaeology: 8 turns back, only the words survive.
      expect('${messages[1]['content']}', contains('第 0 轮好了'));
      expect('${messages[1]['content']}', isNot(contains('点击第 1 条')));
      // The most recent one keeps its mechanics.
      expect('${messages[15]['content']}', contains('点击第 1 条'));
    });

    test('an empty history sends nothing at all', () {
      expect(priorMessages(const []), isEmpty);
    });
  });

  group('the panel', () {
    // In memory: real file I/O inside `testWidgets` runs in a zone where it
    // never completes. The disk path is covered by the store tests above.
    late ConversationStore store;

    setUp(() => store = ConversationStore.inMemory());

    /// Seeds one conversation with a finished turn.
    Future<AgentConversation> seed({
      String message = '把这三条整理成要点',
      String? title,
      DateTime? at,
    }) async {
      final conversation = store.create(now: at);
      if (title != null) {
        await store.rename(conversation.id, title);
      }
      await store.appendTurn(conversation.id, turn(message: message, at: at));
      return conversation;
    }

    Widget sheet({
      String? conversationId,
      AgentState state = const AgentState(),
      ValueChanged<String?>? onConversationChanged,
      void Function(String id, String goal)? onStart,
    }) {
      return MaterialApp(
        theme: AppTheme.darkTheme.copyWith(
          splashFactory: InkRipple.splashFactory,
        ),
        home: Scaffold(
          body: AgentBottomSheet(
            state: state,
            safeMode: true,
            store: store,
            conversationId: conversationId,
            onConversationChanged: onConversationChanged,
            onSafeModeChanged: (_) {},
            onStart: (id, goal, _) => onStart?.call(id, goal),
            onResume: () {},
            onStop: () {},
            onConfirmAction: (_) {},
            onConfirmCaptcha: (_) {},
          ),
        ),
      );
    }

    testWidgets('the panel lists what was talked about, newest first',
        (tester) async {
      await seed(message: '整理清单', title: '整理清单', at: DateTime(2026, 3, 1));
      await seed(message: '查航班', title: '查航班', at: DateTime(2026, 3, 2));

      await tester.pumpWidget(sheet());
      await tester.pump();

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('整理清单'), findsOneWidget);
      expect(find.text('查航班'), findsOneWidget);
      // A conversation list is a chooser: no composer until one is open.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('opening one shows its turns and remembers the choice',
        (tester) async {
      String? opened;
      await seed(title: '整理清单');

      await tester.pumpWidget(sheet(
        onConversationChanged: (id) => opened = id,
      ));
      await tester.pump();

      await tester.tap(find.text('整理清单'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(find.text('把这三条整理成要点'), findsOneWidget);
      expect(find.text('整理好了。'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a conversation can be opened directly and renamed',
        (tester) async {
      final conversation = await seed(title: '整理清单');

      await tester.pumpWidget(sheet(conversationId: conversation.id));
      await tester.pump();

      // The title is the rename affordance.
      await tester.tap(find.text('整理清单').first);
      await tester.pumpAndSettle();
      expect(find.text('重命名对话'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '每日清单');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(store.byId(conversation.id)?.title, '每日清单');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sent message is in the transcript before any answer',
        (tester) async {
      await tester.pumpWidget(sheet(
        conversationId: 'c1',
        state: const AgentState(
          status: AgentStatus.thinking,
          goal: '你好',
        ),
      ));
      await tester.pump();

      // The message you sent is in the chat, not waiting in the input box, and
      // it got there before the answer did.
      expect(find.text('你好'), findsOneWidget);
      // While a run is active the composer is the run bar.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('正在执行…'), findsOneWidget);
    });

    testWidgets('finished, the composer is empty and the message is not in it',
        (tester) async {
      await tester.pumpWidget(sheet(
        conversationId: 'c1',
        state: const AgentState(
          status: AgentStatus.completed,
          goal: '把第二条标成完成',
        ),
      ));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text ?? '', isEmpty);
      expect(find.text('把第二条标成完成'), findsOneWidget);
    });

    testWidgets('every answer carries its own copy button', (tester) async {
      final conversation = await seed(title: '整理清单');
      await tester.pumpWidget(sheet(conversationId: conversation.id));
      await tester.pump();

      // One per reply, under the reply: the place every chat puts it.
      expect(find.text('复制'), findsOneWidget);

      await tester.tap(find.text('复制'));
      await tester.pump();

      expect(find.text('已复制这条回答'), findsOneWidget);
    });

    testWidgets('a running turn is one line until asked', (tester) async {
      await tester.pumpWidget(sheet(
        conversationId: 'c1',
        state: AgentState(
          status: AgentStatus.thinking,
          goal: '点一下 Star',
          logs: [
            AgentLogItem(
              step: 2,
              title: '点击「Star」',
              kind: LogKind.action,
            ),
          ],
        ),
      ));
      await tester.pump();

      // One line, like a chat: what it is doing, not a trace of everything.
      expect(find.text('正在思考…'), findsOneWidget);
      expect(find.text('点击「Star」'), findsNothing);

      await tester.tap(find.text('正在思考…'));
      // The pulse and the skeleton never settle: this widget is alive.
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('点击「Star」'), findsOneWidget);
    });

    testWidgets('a finished turn keeps its answer and folds the steps',
        (tester) async {
      final conversation = await seed(title: '整理清单');
      await tester.pumpWidget(sheet(conversationId: conversation.id));
      await tester.pump();

      expect(find.text('整理好了。'), findsOneWidget);
      expect(find.text('点击第 1 条'), findsNothing);
      expect(find.textContaining('2 步'), findsNothing);

      await tester.tap(find.textContaining('执行过程'));
      await tester.pumpAndSettle();

      expect(find.text('点击第 1 条'), findsOneWidget);
      expect(find.text('点击第 2 条'), findsOneWidget);
    });

    testWidgets('a message starts a conversation and sends its id',
        (tester) async {
      String? startedId;
      String? startedGoal;
      await tester.pumpWidget(sheet(
        conversationId: 'draft-that-does-not-exist',
        onStart: (id, goal) {
          startedId = id;
          startedGoal = goal;
        },
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '打开 GitHub 热榜');
      await tester.pump();
      await tester.tap(find.byTooltip('开始任务'));
      await tester.pump();

      expect(startedGoal, '打开 GitHub 热榜');
      // The panel creates the conversation it writes into, instead of sending
      // a message that belongs to nothing.
      expect(startedId, isNotNull);
      expect(startedId, isNot('draft-that-does-not-exist'));
      expect(store.byId(startedId), isNotNull);
    });
  });
}
