import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/agent/tools.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/gesture.dart';
import 'package:operon/control/protocol/results.dart';
import 'package:operon/models/agent_conversation.dart';
import 'package:operon/services/conversation_store.dart';

/// A model with a script: one reply per call, in order.
class ScriptedLlm implements LlmPort {
  ScriptedLlm(this.script);

  final List<LlmTurn> script;
  int _index = 0;

  @override
  Future<LlmTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    if (_index >= script.length) throw Exception('script exhausted');
    return script[_index++];
  }
}

/// Control that records what had already been written when it was asked.
class OrderingControl implements ControlPort {
  OrderingControl(this.onExecute);

  final void Function(String tool) onExecute;
  final List<String> calls = [];

  @override
  Future<ToolResult> execute(String tool,
      [Map<String, Object?> args = const {}]) async {
    onExecute(tool);
    calls.add(tool);
    return ToolResult(
      ok: true,
      receipt: Receipt(tool: tool, delivery: Delivery.delivered, pageReacted: true),
    );
  }

  @override
  CaptchaInfo? get captcha => null;

  @override
  String? refLabel(String? ref) => null;

  @override
  set onGesture(void Function(GestureTarget target)? value) {}
}

class QuietHost implements HostPort {
  @override
  Future<bool> confirm(ConfirmRequest request) async => true;

  @override
  Future<String?> askPerson(PersonRequest request) async => null;

  @override
  Future<List<String>?> pickFiles() async => null;

  @override
  void note(String title, {String? detail, bool isError = false}) {}
}

ToolCallRequest call(String name, [Map<String, Object?> args = const {}]) =>
    ToolCallRequest(id: 'c_$name', name: name, args: args, rawArguments: '{}');

void main() {
  late Directory dir;
  late ConversationStore store;
  late String conversationId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('operon_journal');
    store = await ConversationStore.open(directory: dir);
    conversationId = store.create().id;
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<List<AgentConversation>> reload() async {
    final again = await ConversationStore.open(directory: dir);
    return again.conversations;
  }

  /// The file as written, without the restart-time migration.
  Future<List<Object?>> rawFile() async {
    final file = File('${dir.path}${Platform.pathSeparator}conversations.json');
    return jsonDecode(await file.readAsString()) as List<Object?>;
  }

  group('the journal', () {
    test('a turn exists on disk while the run is still going', () async {
      final turn = await store.beginTurn(
        conversationId,
        message: '把这条发出去',
        startedAt: DateTime(2026, 5, 1, 10),
        targetUrl: 'https://x.com/1',
      );
      await store.journalStep(
        conversationId,
        turn.id,
        const AgentTurnStep(
          tool: 'click',
          summary: '点击「发送」',
          status: AgentTurnStep.stepStarted,
          callId: 'c1',
        ),
      );

      // Read the file, not a new store: opening one migrates a running turn to
      // interrupted, which is the restart path and not what is being tested.
      final raw = await rawFile();
      final onDisk = ((raw.single as Map)['turns'] as List).single as Map;
      expect(onDisk['message'], '把这条发出去');
      expect(onDisk['status'], 'running',
          reason: 'the row is written before the run ends');
      final step = (onDisk['steps'] as List).single as Map;
      expect(step['summary'], '点击「发送」');
      expect(step['status'], AgentTurnStep.stepStarted,
          reason: 'the intent is there, its outcome is not');
    });

    test('a result lands on the row its intent opened', () async {
      final turn = await store.beginTurn(
        conversationId,
        message: '发出去',
        startedAt: DateTime(2026, 5, 1, 10),
      );
      await store.journalStep(
        conversationId,
        turn.id,
        const AgentTurnStep(
          tool: 'click',
          summary: '点击「发送」',
          status: AgentTurnStep.stepStarted,
          callId: 'c1',
        ),
      );
      await store.settleStep(
        conversationId,
        turn.id,
        callId: 'c1',
        status: AgentTurnStep.stepFailed,
        detail: '元素被遮挡',
      );

      final steps = store.byId(conversationId)!.turns.single.steps;
      expect(steps, hasLength(1), reason: 'one call is one row, not two');
      expect(steps.single.ok, isFalse);
      expect(steps.single.detail, '元素被遮挡');
    });

    test('closing a turn keeps the steps it actually took', () async {
      final turn = await store.beginTurn(
        conversationId,
        message: '发出去',
        startedAt: DateTime(2026, 5, 1, 10),
      );
      await store.journalStep(
        conversationId,
        turn.id,
        const AgentTurnStep(
          tool: 'click',
          summary: '点击「发送」',
          status: AgentTurnStep.stepStarted,
          callId: 'c1',
        ),
      );
      await store.settleStep(
        conversationId,
        turn.id,
        callId: 'c1',
        status: AgentTurnStep.stepOk,
      );
      await store.completeTurn(
        conversationId,
        turn.id,
        status: 'completed',
        result: '已经发出去了',
        promptTokens: 120,
        completionTokens: 30,
      );

      final closed = store.byId(conversationId)!.turns.single;
      expect(closed.status, 'completed');
      expect(closed.result, '已经发出去了');
      expect(closed.steps.single.ok, isTrue);
      expect(closed.promptTokens, 120);
      expect(closed.isRunning, isFalse);
    });

    test('a run the app killed is read back as interrupted, not as busy', () async {
      final turn = await store.beginTurn(
        conversationId,
        message: '把表填完',
        startedAt: DateTime(2026, 5, 1, 10),
      );
      await store.journalStep(
        conversationId,
        turn.id,
        const AgentTurnStep(
          tool: 'fill_form',
          summary: '填写表单',
          status: AgentTurnStep.stepStarted,
          callId: 'c1',
        ),
      );

      // The file is only ever read at start-up, so a running row cannot belong
      // to a live process by then.
      final afterRestart = (await reload()).single.turns.single;

      expect(afterRestart.wasInterrupted, isTrue);
      expect(afterRestart.steps.single.summary, '填写表单');
      expect(afterRestart.steps.single.isPending, isTrue);
    });

    test('the migration is written back, not replayed on every start', () async {
      final turn = await store.beginTurn(
        conversationId,
        message: 'x',
        startedAt: DateTime(2026, 5, 1, 10),
      );
      await reload();

      final raw = await rawFile();
      final status = ((raw.single as Map)['turns'] as List).single['status'];
      expect(status, 'interrupted');
      expect(turn.isRunning, isTrue, reason: 'the in-memory copy is untouched');
    });

    test('older files that carried `ok` instead of `status` still load', () async {
      final file = File('${dir.path}${Platform.pathSeparator}conversations.json');
      await file.writeAsString(jsonEncode([
        {
          'id': 'c_old',
          'title': '旧对话',
          'createdAt': '2026-01-01T10:00:00.000',
          'updatedAt': '2026-01-01T10:00:05.000',
          'turns': [
            {
              'id': 't_old',
              'message': '老任务',
              'startedAt': '2026-01-01T10:00:00.000',
              'endedAt': '2026-01-01T10:00:05.000',
              'status': 'completed',
              'steps': [
                {'tool': 'click', 'summary': '点击', 'ok': false},
                {'tool': 'click', 'summary': '再点击', 'ok': true},
              ],
            },
          ],
        },
      ]));

      final loaded = (await ConversationStore.open(directory: dir))
          .byId('c_old')!
          .turns
          .single
          .steps;

      expect(loaded.first.ok, isFalse);
      expect(loaded.last.ok, isTrue);
      expect(loaded.first.status, AgentTurnStep.stepFailed);
    });
  });

  group('the run', () {
    test('the intent is written and awaited before the call is dispatched',
        () async {
      final order = <String>[];
      final control = OrderingControl((tool) => order.add('dispatch:$tool'));

      final loop = AgentLoop(
        llm: ScriptedLlm([
          LlmTurn(
            content: '',
            calls: [call('click', {'ref': 'a1'})],
          ),
          LlmTurn(
            content: '',
            calls: [
              call('done', {'summary': '好了', 'outcome': 'success'}),
            ],
          ),
        ]),
        control: control,
        host: QuietHost(),
        system: 'test system',
        tools: buildToolSchemas(),
        safeMode: false,
        // The journal rides on this hook; making it async is what buys the
        // guarantee that the row is on disk first.
        onToolStarted: (index, call, description) async {
          await Future<void>.delayed(Duration.zero);
          order.add('intent:${call.name}');
        },
        onToolFinished: (call, result) => order.add('result:${call.name}'),
      );

      final end = await loop.run('点一下');

      expect(end.outcome, LoopOutcome.success);
      expect(order, ['intent:click', 'dispatch:click', 'result:click']);
    });
  });
}

