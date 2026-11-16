import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/agent/tools.dart';
import 'package:operon/agent/verification.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/gesture.dart';
import 'package:operon/control/protocol/results.dart';

/// A model with a script: one reply per call, in order.
class ScriptedLlm implements LlmPort {
  ScriptedLlm(this.script);

  final List<LlmTurn> script;
  final List<List<Map<String, Object?>>> requests = [];
  int _index = 0;

  @override
  Future<LlmTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    requests.add(messages);
    if (_index >= script.length) throw Exception('script exhausted');
    return script[_index++];
  }
}

class FakeControl implements ControlPort {
  FakeControl({this.labels = const {}, this.results = const {}});

  final Map<String, String> labels;
  final Map<String, ToolResult> results;
  final List<String> calls = [];

  @override
  Future<ToolResult> execute(String tool,
      [Map<String, Object?> args = const {}]) async {
    calls.add(tool);
    return results[tool] ?? ToolResult(ok: true, text: '$tool ok');
  }

  @override
  CaptchaInfo? get captcha => null;

  @override
  String? refLabel(String? ref) => ref == null ? null : labels[ref];

  @override
  set onGesture(void Function(GestureTarget target)? value) {}
}

class FakeHost implements HostPort {
  FakeHost({this.answer = true});

  bool answer;

  @override
  Future<bool> confirm(ConfirmRequest request) async => answer;

  @override
  Future<String?> askPerson(PersonRequest request) async => null;

  @override
  Future<List<String>?> pickFiles() async => null;

  @override
  void note(String title, {String? detail, bool isError = false}) {}
}

ToolResult snapshotResult({String url = 'https://x.com/1'}) => ToolResult(
      ok: true,
      text: '[a1] button "发送"',
      data: {'url': url},
      receipt: Receipt(
        tool: 'snapshot',
        delivery: Delivery.notDelivered,
        pageReacted: true,
      ),
    );

ToolResult clickResult({
  bool pageReacted = false,
  String? urlAfter,
  bool ok = true,
  Delivery? delivery,
}) {
  final receipt = Receipt(
    tool: 'click',
    delivery: delivery ?? Delivery.delivered,
    pageReacted: pageReacted,
    changes: pageReacted ? const ['+ [a9] textbox "评论框"'] : const [],
    urlAfter: urlAfter,
  );
  if (!ok) {
    return ToolResult(ok: false, receipt: receipt, text: '失败了');
  }
  return ToolResult(ok: true, receipt: receipt, text: '已派发');
}

LlmTurn use(List<ToolCallRequest> calls) => LlmTurn(content: '', calls: calls);

ToolCallRequest call(String name, [Map<String, Object?> args = const {}]) =>
    ToolCallRequest(id: 'c_$name', name: name, args: args, rawArguments: '{}');

AgentLoop loop({required ScriptedLlm llm, required FakeControl control}) =>
    AgentLoop(
      llm: llm,
      control: control,
      host: FakeHost(),
      system: 'test system',
      tools: buildToolSchemas(),
      // The point of these tests is the ledger, not the permission card.
      safeMode: false,
      startUrl: 'https://x.com/1',
    );

void main() {
  group('createsDebt', () {
    test('an action that visibly moved the page owes nothing', () {
      expect(createsDebt('click', clickResult(pageReacted: true)), isFalse);
    });

    test('an action that was dispatched and changed nothing owes evidence', () {
      expect(createsDebt('click', clickResult()), isTrue);
    });

    test('a failure before dispatch owes nothing', () {
      // A stale ref never reached the page: there is nothing to verify.
      expect(
        createsDebt('click', const ToolResult(ok: false, text: '失败')),
        isFalse,
      );
    });

    test('a failure that may have reached the page owes evidence', () {
      expect(createsDebt('click', clickResult(ok: false)), isTrue);
    });

    test('an explicit "not delivered" owes nothing', () {
      expect(
        createsDebt('click', clickResult(ok: false, delivery: Delivery.notDelivered)),
        isFalse,
      );
    });

    test('scroll never owes anything, whatever the page did', () {
      final scrolled = ToolResult(
        ok: true,
        receipt: Receipt(
          tool: 'scroll',
          delivery: Delivery.delivered,
          pageReacted: false,
        ),
      );
      expect(createsDebt('scroll', scrolled), isFalse);
    });

    test('a write with no receipt at all owes evidence', () {
      expect(
        createsDebt('fill_form', const ToolResult(ok: true, text: '填好了')),
        isTrue,
      );
    });
  });

  group('clearsDebt', () {
    test('a successful look at the page pays the debt', () {
      expect(clearsDebt('snapshot', snapshotResult()), isTrue);
      expect(clearsDebt('find', snapshotResult()), isTrue);
    });

    test('a failed look pays nothing', () {
      expect(
        clearsDebt('snapshot', const ToolResult(ok: false, text: '超时')),
        isFalse,
      );
    });

    test('navigating away is not a look at the page it left', () {
      final nav = ToolResult(
        ok: true,
        data: {'url': 'https://x.com/2'},
        receipt: Receipt(
          tool: 'navigate',
          delivery: Delivery.notDelivered,
          pageReacted: true,
          urlBefore: 'https://x.com/1',
          urlAfter: 'https://x.com/2',
        ),
      );
      expect(clearsDebt('navigate', nav), isFalse);
    });

    test('an action that changed the page shows its own effect', () {
      expect(clearsDebt('click', clickResult(pageReacted: true)), isTrue);
    });
  });

  group('DebtLedger', () {
    test('the same step repeated is one unknown, not three', () {
      final ledger = DebtLedger()
        ..add(DebtItem(tool: 'click', label: '点击「发送」', url: 'https://x.com/1'))
        ..add(DebtItem(tool: 'click', label: '点击「发送」', url: 'https://x.com/1'))
        ..add(DebtItem(tool: 'click', label: '点击「发送」', url: 'https://x.com/1'));

      expect(ledger.all, hasLength(1));
    });

    test('leaving the page turns debt into something only the answer can say', () {
      final ledger = DebtLedger()
        ..add(DebtItem(tool: 'click', label: '点击「提交」', url: 'https://x.com/1'))
        ..retireElsewhere('https://x.com/2');

      expect(ledger.open, isEmpty);
      expect(ledger.all.single.lost, isTrue);
      expect(ledger.unverifiedLines().single, contains('已经离开那个页面'));
    });

    test('a look at the page pays off what is still checkable, not what is lost',
        () {
      final ledger = DebtLedger()
        ..add(DebtItem(tool: 'click', label: '点击「提交」', url: 'https://x.com/1'))
        ..retireElsewhere('https://x.com/2')
        ..add(DebtItem(tool: 'click', label: '点击「返回」', url: 'https://x.com/2'))
        ..clear();

      expect(ledger.all, hasLength(1));
      expect(ledger.all.single.label, '点击「提交」');
    });

    test('the refusal names the step and what to do about it', () {
      final ledger = DebtLedger()
        ..add(DebtItem(tool: 'click', label: '点击「发送」', url: 'https://x.com/1'));

      final text = ledger.refusal();
      expect(text, contains('还不能说成功'));
      expect(text, contains('点击「发送」'));
      expect(text, contains('snapshot'));
      expect(text, contains('partial'));
    });
  });

  group('the run', () {
    test('a click nobody checked refuses success, then accepts it after a look',
        () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('click', {'ref': 'a1'})]),
        use([
          call('done', {'summary': '已经发出去了', 'outcome': 'success'}),
        ]),
        use([call('snapshot')]),
        use([
          call('done', {'summary': '已经发出去了', 'outcome': 'success'}),
        ]),
      ]);
      final control = FakeControl(
        labels: {'a1': 'button "发送"'},
        results: {'snapshot': snapshotResult(), 'click': clickResult()},
      );

      final end = await loop(llm: llm, control: control).run('把这条发出去');

      // The model learns why, in words it can act on.
      final refusal = llm.requests[3].lastWhere(
        (message) => message['role'] == 'tool' && '${message['content']}'.contains('还不能说成功'),
      );
      expect(refusal['content'], contains('点击「发送」'));
      expect(refusal['content'], contains('先 snapshot'));

      // After the second snapshot the debt is paid and success is allowed.
      expect(end.outcome, LoopOutcome.success);
      expect(end.summary, '已经发出去了');
      expect(end.summary, isNot(contains('未证实')));
      expect(control.calls, ['snapshot', 'click', 'snapshot']);
    });

    test('refused twice: the run ends as partial and says what it could not confirm',
        () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('click', {'ref': 'a1'})]),
        use([
          call('done', {'summary': '留言已经提交', 'outcome': 'success'}),
        ]),
        use([
          call('done', {'summary': '留言已经提交', 'outcome': 'success'}),
        ]),
      ]);
      final control = FakeControl(
        labels: {'a1': 'button "提交"'},
        results: {'snapshot': snapshotResult(), 'click': clickResult()},
      );

      final end = await loop(llm: llm, control: control).run('提交留言');

      expect(end.outcome, LoopOutcome.partial);
      expect(end.stopReason, contains('没有确认'));
      expect(end.summary, contains('留言已经提交'));
      expect(end.summary, contains('未能确认的步骤'));
      expect(end.summary, contains('点击「提交」'));
      expect(end.summary, contains('未证实'));
    });

    test('leaving the page keeps the doubt, in the answer', () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('click', {'ref': 'a1'})]),
        use([call('navigate', {'url': 'https://x.com/2'})]),
        use([
          call('done', {'summary': '填完并提交了', 'outcome': 'partial'}),
        ]),
      ]);
      final control = FakeControl(
        labels: {'a1': 'button "提交"'},
        results: {
          'snapshot': snapshotResult(),
          'click': clickResult(),
          'navigate': ToolResult(
            ok: true,
            data: {'url': 'https://x.com/2'},
            receipt: Receipt(
              tool: 'navigate',
              delivery: Delivery.notDelivered,
              pageReacted: true,
              urlBefore: 'https://x.com/1',
              urlAfter: 'https://x.com/2',
            ),
          ),
        },
      );

      final end = await loop(llm: llm, control: control).run('提交然后往下走');

      expect(end.outcome, LoopOutcome.partial);
      expect(end.summary, contains('点击「提交」'));
      expect(end.summary, contains('已经离开那个页面'));
    });

    test('a click that moved the page owes nothing, so a clean run stays clean',
        () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('click', {'ref': 'a1'})]),
        use([
          call('done', {'summary': '已翻页', 'outcome': 'success'}),
        ]),
      ]);
      final control = FakeControl(
        labels: {'a1': 'link "下一条"'},
        results: {
          'snapshot': snapshotResult(),
          'click': clickResult(pageReacted: true),
        },
      );

      final end = await loop(llm: llm, control: control).run('翻到下一条');

      expect(end.outcome, LoopOutcome.success);
      expect(end.summary, '已翻页');
      expect(end.summary, isNot(contains('未证实')));
    });

    test('a conversation with no action is untouched', () async {
      final llm = ScriptedLlm([
        const LlmTurn(content: '你好，我能帮你看这个页面。'),
      ]);

      final end = await loop(llm: llm, control: FakeControl()).run('你好');

      expect(end.outcome, LoopOutcome.success);
      expect(end.summary, '你好，我能帮你看这个页面。');
    });

    test('a user stop still admits what was never checked', () async {
      var keepGoingCalls = 0;
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('click', {'ref': 'a1'})]),
      ]);
      final control = FakeControl(
        labels: {'a1': 'button "提交"'},
        results: {'snapshot': snapshotResult(), 'click': clickResult()},
      );
      final agent = AgentLoop(
        llm: llm,
        control: control,
        host: FakeHost(),
        system: 'test system',
        tools: buildToolSchemas(),
        safeMode: false,
        startUrl: 'https://x.com/1',
        keepGoing: () async {
          // turn 1, snapshot, turn 2 and the click run; turn 3 stops.
          keepGoingCalls++;
          return keepGoingCalls <= 4;
        },
      );

      final end = await agent.run('提交留言');

      expect(end.stoppedByUser, isTrue);
      expect(end.outcome, LoopOutcome.partial);
      expect(end.summary, contains('点击「提交」'));
    });
  });
}
