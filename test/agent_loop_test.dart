import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/agent/tools.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/errors.dart';
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
    if (_index >= script.length) {
      throw Exception('script exhausted');
    }
    return script[_index++];
  }
}

class FakeControl implements ControlPort {
  FakeControl({this.labels = const {}, this.results = const {}, this.challenge});

  final Map<String, String> labels;
  final Map<String, ToolResult> results;
  final List<String> calls = [];

  /// Set to report a challenge on the next capture.
  CaptchaInfo? challenge;

  @override
  Future<ToolResult> execute(String tool, [Map<String, Object?> args = const {}]) async {
    calls.add(tool);
    return results[tool] ?? ToolResult(ok: true, text: '$tool ok');
  }

  @override
  CaptchaInfo? get captcha => challenge;

  @override
  String? refLabel(String? ref) => ref == null ? null : labels[ref];

  @override
  set onGesture(void Function(double x, double y, String label)? value) {}
}

class FakeHost implements HostPort {
  FakeHost({this.answer = true});

  bool answer;
  final List<ConfirmRequest> asks = [];
  final List<String> notes = [];

  @override
  Future<bool> confirm(ConfirmRequest request) async {
    asks.add(request);
    return answer;
  }

  /// Answers handed out for a person request, in order.
  final List<String?> personAnswers = [];

  @override
  Future<String?> askPerson(PersonRequest request) async {
    notes.add('${request.kind}:${request.title}');
    if (personAnswers.isEmpty) return null;
    return personAnswers.removeAt(0);
  }

  @override
  void note(String title, {String? detail, bool isError = false}) => notes.add(title);
}

ToolResult snapshotResult({String url = 'https://x.com/1', bool changed = true}) => ToolResult(
      ok: true,
      text: '可操作元素:\n[a1] button "发送"\n[a3] link "下一条"',
      data: {'url': url, 'elements': 2},
      receipt: Receipt(tool: 'snapshot', delivery: Delivery.notDelivered, pageReacted: changed),
    );

ToolResult clickResult({bool pageReacted = true}) => ToolResult(
      ok: true,
      text: '已派发',
      receipt: Receipt(
        tool: 'click',
        delivery: Delivery.delivered,
        pageReacted: pageReacted,
        changes: pageReacted ? const ['+ [a9] textbox "评论框"'] : const [],
      ),
    );

LlmTurn say(String text) => LlmTurn(content: text);

LlmTurn use(List<ToolCallRequest> calls, {String? content}) =>
    LlmTurn(content: content ?? '', calls: calls);

ToolCallRequest call(String name, [Map<String, Object?> args = const {}, String? id]) =>
    ToolCallRequest(id: id ?? 'c_$name', name: name, args: args, rawArguments: '{}');

AgentLoop loop({
  required ScriptedLlm llm,
  required FakeControl control,
  FakeHost? host,
  bool safeMode = true,
  bool Function(String)? isSiteAllowed,
  int maxTurns = 20,
}) =>
    AgentLoop(
      llm: llm,
      control: control,
      host: host ?? FakeHost(),
      system: 'test system',
      tools: buildToolSchemas(),
      maxTurns: maxTurns,
      safeMode: safeMode,
      isSiteAllowed: isSiteAllowed,
    );

void main() {
  test('observe, act, done: the whole run and the conversation it leaves', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'})]),
      use([
        call('done', {'summary': '已回复 5 条', 'outcome': 'success'}),
      ]),
    ]);
    final control = FakeControl(
      labels: {'a1': 'link "下一条"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );
    final host = FakeHost();

    final end = await loop(llm: llm, control: control, host: host).run('翻到下一条');

    expect(control.calls, ['snapshot', 'click']);
    expect(end.outcome, LoopOutcome.success);
    expect(end.summary, '已回复 5 条');
    expect(end.toolCalls, 2);
    expect(host.asks, isEmpty, reason: 'a next-page link is not a write');

    // The model's own requests keep the calls and their answers paired.
    final last = llm.requests.last;
    expect(last.where((message) => message['role'] == 'tool'), hasLength(2));
    expect(last.first['role'], 'system');
    expect(last[1]['content'], '翻到下一条');
  });

  test('a click on a send button asks first, and a refusal is not retried', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'})]),
      use([call('done', {'summary': '用户不许发布，已停止', 'outcome': 'partial'})]),
    ]);
    final control = FakeControl(
      labels: {'a1': 'button "发送"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );
    final host = FakeHost(answer: false);

    final end = await loop(llm: llm, control: control, host: host).run('把这条发出去');

    expect(host.asks, hasLength(1));
    expect(host.asks.single.reason, contains('发送'));
    expect(control.calls, isNot(contains('click')));
    expect(end.outcome, LoopOutcome.partial);

    final refusal = llm.requests.last.firstWhere((message) =>
        message['role'] == 'tool' && '${message['content']}'.contains('用户拒绝'));
    expect(refusal['content'], contains('不要用同样的参数再试一次'));
  });

  test('a destructive click asks even with safe mode off and the site allowed', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a2'})]),
      use([call('done', {'summary': 'x', 'outcome': 'partial'})]),
    ]);
    final control = FakeControl(
      labels: {'a2': 'button "删除这条记录"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );
    final host = FakeHost(answer: false);

    await loop(
      llm: llm,
      control: control,
      host: host,
      safeMode: false,
      isSiteAllowed: (_) => true,
    ).run('删除它');

    expect(host.asks, hasLength(1));
    expect(host.asks.single.destructive, isTrue);
    expect(host.asks.single.title, contains('需要你来做'));
  });

  test('reads in one reply all run together', () async {
    final llm = ScriptedLlm([
      use([call('snapshot', const {}, 'c1'), call('find', {'query': '评论'}, 'c2')]),
      use([call('done', {'summary': '看过了', 'outcome': 'partial'})]),
    ]);
    final control = FakeControl(results: {'snapshot': snapshotResult()});

    await loop(llm: llm, control: control).run('看看页面');

    expect(control.calls, ['snapshot', 'find']);
  });

  test('only the first action runs; the rest are told to observe again', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'}, 'c1'), call('click', {'ref': 'a3'}, 'c2')]),
      use([call('done', {'summary': 'ok', 'outcome': 'success'})]),
    ]);
    final control = FakeControl(
      labels: {'a1': 'link "下一条"', 'a3': 'link "下一条"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );

    await loop(llm: llm, control: control).run('翻页');

    expect(control.calls.where((name) => name == 'click'), hasLength(1));
    final skipped = llm.requests.last.firstWhere((message) =>
        message['role'] == 'tool' && '${message['content']}'.contains('未执行'));
    expect(skipped['content'], contains('snapshot'));
  });

  test('the same action three times stops the run with a reason', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'})]),
      use([call('click', {'ref': 'a1'})]),
      use([call('click', {'ref': 'a1'})]),
    ]);
    final control = FakeControl(
      labels: {'a1': 'button "加载更多"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );

    final end = await loop(llm: llm, control: control).run('加载更多');

    expect(end.outcome, LoopOutcome.partial);
    expect(end.stopReason, contains('重复'));
    expect(control.calls.where((name) => name == 'click'), hasLength(2));
  });

  test('action after action that changes nothing stops instead of looping', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'})]),
      use([call('click', {'ref': 'a2'})]),
      use([call('click', {'ref': 'a3'})]),
      use([call('click', {'ref': 'a4'})]),
    ]);
    final control = FakeControl(results: {
      'snapshot': snapshotResult(),
      'click': clickResult(pageReacted: false),
    });

    final end = await loop(llm: llm, control: control).run('点死按钮');

    expect(end.outcome, LoopOutcome.partial);
    expect(end.stopReason, contains('没有让页面发生变化'));
  });

  test('a plain answer ends the run as partial: only done may claim success', () async {
    final llm = ScriptedLlm([say('我建议你先登录。')]);
    final control = FakeControl();

    final end = await loop(llm: llm, control: control).run('该怎么办');

    expect(end.outcome, LoopOutcome.partial);
    expect(end.summary, '我建议你先登录。');
    expect(end.stopReason, contains('没有调用 done'));
    expect(control.calls, isEmpty);
  });

  test('a truncated reply executes nothing', () async {
    final llm = ScriptedLlm([
      LlmTurn(content: '让我先点', finishReason: 'length', calls: [call('click', {'ref': 'a1'})]),
      use([call('done', {'summary': 'x', 'outcome': 'partial'})]),
    ]);
    final control = FakeControl(results: {'click': clickResult()});

    final end = await loop(llm: llm, control: control).run('点一下');

    expect(control.calls, isEmpty);
    expect(end.outcome, LoopOutcome.partial);
    expect(end.stopReason, contains('截断'));
  });

  test('done in the same reply as an action finishes after the action', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([
        call('click', {'ref': 'a3'}, 'c1'),
        call('done', {'summary': '已翻到下一页', 'outcome': 'success'}, 'c2'),
      ]),
    ]);
    final control = FakeControl(
      labels: {'a3': 'link "下一条"'},
      results: {'snapshot': snapshotResult(), 'click': clickResult()},
    );

    final end = await loop(llm: llm, control: control).run('翻页');

    expect(control.calls, ['snapshot', 'click']);
    expect(end.outcome, LoopOutcome.success);
    expect(end.summary, '已翻到下一页');
  });

  test('done carries structured results out of the run', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([
        call('done', {
          'summary': '抓到两条标题',
          'outcome': 'success',
          'data': {
            'items': ['A', 'B'],
          },
        }),
      ]),
    ]);
    final control = FakeControl(results: {'snapshot': snapshotResult()});

    final end = await loop(llm: llm, control: control).run('抓标题');

    expect(end.outcome, LoopOutcome.success);
    expect((end.data as Map)['items'], hasLength(2));
  });

  test('a model failure ends the run with a message the user can act on', () async {
    final llm = ScriptedLlm([]);
    final control = FakeControl();

    final end = await loop(llm: llm, control: control).run('做点什么');

    expect(end.outcome, LoopOutcome.failed);
    expect(end.error, contains('script exhausted'));
  });

  test('the turn budget ends the run instead of looping forever', () async {
    final llm = ScriptedLlm(List.generate(5, (_) => use([call('snapshot')])));
    final control = FakeControl(results: {'snapshot': snapshotResult()});

    final end = await loop(llm: llm, control: control, maxTurns: 3).run('一直看');

    expect(end.outcome, LoopOutcome.partial);
    expect(end.stopReason, contains('3 轮'));
  });

  test('stop is honoured between calls, and nothing after it runs', () async {
    var allowed = 2;
    final llm = ScriptedLlm(List.generate(5, (_) => use([call('snapshot')])));
    final control = FakeControl(results: {'snapshot': snapshotResult()});

    final end = await AgentLoop(
      llm: llm,
      control: control,
      host: FakeHost(),
      system: 's',
      tools: buildToolSchemas(),
      keepGoing: () async => allowed-- > 0,
    ).run('一直看');

    expect(end.stoppedByUser, isTrue);
    expect(control.calls, hasLength(1));
  });

  test('a layer error is reported as a failure the model can read', () async {
    final llm = ScriptedLlm([
      use([call('snapshot')]),
      use([call('click', {'ref': 'a1'})]),
      use([call('done', {'summary': '没点到', 'outcome': 'failed'})]),
    ]);
    final control = FakeControl(results: {
      'snapshot': snapshotResult(),
      'click': ToolResult.failure(const ControlException(
        ControlErrorCode.staleRef,
        '页面已变化，之前看到的元素不再有效',
        hint: '重新取一次页面快照',
      )),
    });

    final end = await loop(llm: llm, control: control).run('点它');

    expect(end.outcome, LoopOutcome.failed);
    final failedResult = llm.requests.last.firstWhere((message) =>
        message['role'] == 'tool' && '${message['content']}'.contains('staleRef'));
    expect(failedResult['content'], contains('重新取一次页面快照'));
  });
}
