import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/control/protocol/gesture.dart';
import 'package:operon/agent/tools.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/protocol/results.dart';
import 'package:operon/models/agent_attachment.dart';

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
  set onGesture(void Function(GestureTarget target)? value) {}
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

  /// Files returned by [pickFiles].
  List<String>? pickedFiles;
  int pickFilesCount = 0;

  @override
  Future<String?> askPerson(PersonRequest request) async {
    notes.add('${request.kind}:${request.title}');
    if (personAnswers.isEmpty) return null;
    return personAnswers.removeAt(0);
  }

  @override
  Future<List<String>?> pickFiles() async {
    pickFilesCount++;
    return pickedFiles;
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
  bool Function(String)? isSiteBlocked,
  List<AgentAttachment> attachments = const [],
  String? startUrl,
}) =>
    AgentLoop(
      llm: llm,
      control: control,
      host: host ?? FakeHost(),
      system: 'test system',
      tools: buildToolSchemas(),
      safeMode: safeMode,
      isSiteAllowed: isSiteAllowed,
      isSiteBlocked: isSiteBlocked,
      attachments: attachments,
      startUrl: startUrl,
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

  test('an answer in words is an answer, not a protocol complaint', () async {
    // 「你好」 gets 「你好」. The old behaviour returned partial with
    // 「模型用文字结束，没有调用 done」, which the panel then showed *as* the
    // answer: an internal note where the reply should be.
    final llm = ScriptedLlm([say('我建议你先登录。')]);
    final control = FakeControl();

    final end = await loop(llm: llm, control: control).run('该怎么办');

    expect(end.outcome, LoopOutcome.success);
    expect(end.summary, '我建议你先登录。');
    expect(end.stopReason, isNull);
    expect(control.calls, isEmpty);
  });

  test('a reply that is neither words nor a call says so', () async {
    final llm = ScriptedLlm([const LlmTurn()]);
    final control = FakeControl();

    final end = await loop(llm: llm, control: control).run('你好');

    expect(end.outcome, LoopOutcome.failed);
    expect(end.stopReason, contains('没有回答'));
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

  test('a run that only looks at the page is stopped by itself', () async {
    // There is no step ceiling any more, so nothing counts turns except this:
    // a model that keeps calling snapshot never touches the page, and every
    // call succeeds, so the guards see nothing wrong either.
    final llm = ScriptedLlm(List.generate(20, (_) => use([call('snapshot')])));
    final control = FakeControl(results: {'snapshot': snapshotResult()});

    final end = await loop(llm: llm, control: control).run('一直看');

    expect(end.outcome, LoopOutcome.partial);
    expect(end.stopReason, contains('只观察页面'));
    expect(end.turns, lessThan(15));
  });

  test('a run that acts keeps going past that point', () async {
    // Reading a lot is fine as long as it does something in between: the
    // counter is about a streak, not about a total.
    final llm = ScriptedLlm([
      for (var round = 0; round < 3; round++) ...[
        ...List.generate(6, (_) => use([call('snapshot')])),
        use([call('click', {'ref': 'a1'})]),
      ],
      use([call('done', {'summary': '好了', 'outcome': 'success'})]),
    ]);
    final control = FakeControl(results: {
      'snapshot': snapshotResult(),
      'click': clickResult(),
    });

    final end = await loop(llm: llm, control: control).run('做事');

    expect(end.outcome, LoopOutcome.success);
    expect(end.turns, greaterThan(10));
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

  group('what a site rule may and may not waive', () {
    test('an allowed site is asked about with a bare host, not a url', () async {
      final asked = <String>[];
      final llm = ScriptedLlm([
        use([call('click', {'ref': 'a1'})]),
        use([call('done', {'summary': '好', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(
        labels: {'a1': '发送'},
        results: {'click': clickResult()},
      );
      final host = FakeHost();
      await loop(
        llm: llm,
        control: control,
        host: host,
        startUrl: 'https://x.com/1',
        // The page url includes a path; the allow list stores hosts, so the
        // loop has to reduce it before asking.
        isSiteAllowed: (value) {
          asked.add(value);
          return value == 'x.com';
        },
      ).run('回复一条');

      expect(asked, contains('x.com'));
      expect(asked.every((value) => !value.contains('/')), isTrue,
          reason: 'a whole url never matches a host allow list');
      expect(host.asks, isEmpty, reason: 'the site is trusted, so no card');
    });

    test('a blocked site is not touched and asks nothing', () async {
      final llm = ScriptedLlm([
        use([call('click', {'ref': 'a1'})]),
        use([call('done', {'summary': '做不了', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl(labels: {'a1': '发送'});
      final host = FakeHost();
      await loop(
        llm: llm,
        control: control,
        host: host,
        isSiteBlocked: (value) => value == 'x.com',
        startUrl: 'https://x.com/1',
        safeMode: false,
      ).run('回复一条');

      expect(control.calls, isNot(contains('click')),
          reason: 'a forbidden site is not negotiable');
      expect(host.asks, isEmpty);
      expect(
        llm.requests[1].where((m) => m['role'] == 'tool').map((m) => m['content']).join(),
        contains('禁止'),
      );
    });
  });

  group('money and credentials are the user\'s step', () {
    test('a yes on a payment card still does not dispatch', () async {
      final llm = ScriptedLlm([
        use([call('click', {'ref': 'a1'})]),
        use([call('done', {'summary': '用户自己付款', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl(
        labels: {'a1': '立即支付'},
        results: {'click': clickResult()},
      );
      final host = FakeHost(answer: true);
      await loop(llm: llm, control: control, host: host).run('买下它');

      expect(host.asks.single.handoff, isTrue,
          reason: 'the card must say this is the user\'s step');
      expect(control.calls, isNot(contains('click')),
          reason: 'approving a handoff means "I did it myself"');
      expect(
        llm.requests[1]
            .where((m) => m['role'] == 'tool')
            .map((m) => m['content'])
            .join(),
        contains('用户自己完成'),
      );
    });

    test('a form submit asks with every field and the button in the preview',
        () async {
      final llm = ScriptedLlm([
        use([
          call('fill_form', {
            'fields': [
              {'ref': 'a1', 'value': '张三'},
              {'ref': 'a2', 'value': 'zhang@example.com'},
            ],
            'submitRef': 'a3',
          }),
        ]),
        use([call('done', {'summary': '已提交', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(labels: {
        'a1': 'textbox "姓名"',
        'a2': 'textbox "邮箱"',
        'a3': 'button "提交申请"',
      });
      final host = FakeHost(answer: true);

      await loop(llm: llm, control: control, host: host).run('提交申请');

      expect(host.asks, hasLength(1));
      expect(host.asks.single.title, '确认提交表单');
      expect(host.asks.single.reason, contains('2 个字段'));
      final payload = host.asks.single.payload ?? '';
      // The button is the first line: a five-line card must never hide it.
      expect(payload.split('\n').first, contains('提交：提交申请'));
      expect(payload, contains('姓名：张三'));
      expect(payload, contains('邮箱：zhang@example.com'));
      expect(control.calls, contains('fill_form'));
    });

    test('a password field hands the form over and never shows its value',
        () async {
      final llm = ScriptedLlm([
        use([
          call('fill_form', {
            'fields': [
              {'ref': 'a1', 'value': 'user@example.com'},
              {'ref': 'a2', 'value': 'hunter2'},
            ],
            'submitRef': 'a3',
          }),
        ]),
        use([call('done', {'summary': '请用户自己登录', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl(labels: {
        'a1': 'textbox "用户名"',
        'a2': 'textbox "密码"',
        'a3': 'button "登录"',
      });
      final host = FakeHost(answer: true);

      await loop(llm: llm, control: control, host: host).run('登录');

      expect(host.asks.single.handoff, isTrue);
      expect(host.asks.single.reason, contains('请自己填写'));
      final payload = host.asks.single.payload ?? '';
      expect(payload, contains('密码：（敏感内容，未显示）'));
      expect(payload, isNot(contains('hunter2')));
      expect(control.calls, isNot(contains('fill_form')),
          reason: 'a yes on a credential card means the user did it');
    });

    test('a normal submit still runs after a yes', () async {
      final llm = ScriptedLlm([
        use([call('click', {'ref': 'a1'})]),
        use([call('done', {'summary': '已提交', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(
        labels: {'a1': '提交申请'},
        results: {'click': clickResult()},
      );
      final host = FakeHost(answer: true);
      await loop(llm: llm, control: control, host: host).run('提交');

      expect(host.asks.single.handoff, isFalse);
      expect(control.calls, contains('click'));
    });

    test('deleting asks, but the agent may do it once told yes', () async {
      final llm = ScriptedLlm([
        use([call('click', {'ref': 'a1'})]),
        use([call('done', {'summary': '已删除', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(
        labels: {'a1': '删除这条'},
        results: {'click': clickResult()},
      );
      final host = FakeHost(answer: true);
      await loop(llm: llm, control: control, host: host).run('删除');

      expect(host.asks.single.destructive, isTrue);
      expect(host.asks.single.handoff, isFalse,
          reason: 'deletion is reversible by asking; a payment is not');
      expect(control.calls, contains('click'));
    });
  });

  group('attachments', () {
    test('a text file travels with the goal inside the data markers', () async {
      final llm = ScriptedLlm([
        use([call('done', {'summary': '读完了', 'outcome': 'success'})]),
      ]);
      await loop(
        llm: llm,
        control: FakeControl(),
        attachments: const [
          AgentAttachment.text(
            name: 'notes.md',
            text: '# 预算\n- 3000 元',
            sizeBytes: 18,
          ),
        ],
      ).run('按附件里的预算筛选');

      final goal = llm.requests.first.last['content'] as String;
      expect(goal, contains('按附件里的预算筛选'));
      expect(goal, contains('notes.md'));
      expect(goal, contains('3000 元'));
      expect(goal, contains('<<<page-content>>>'),
          reason: 'file content is data, exactly like a page');
    });

    test('an image rides in its own user message, and only when vision', () async {
      const image = AgentAttachment.image(
        name: 'photo.jpg',
        base64: 'AAAA',
        sizeBytes: 3,
      );
      final llm = ScriptedLlm([
        use([call('done', {'summary': '看过', 'outcome': 'success'})]),
      ]);
      await AgentLoop(
        llm: llm,
        control: FakeControl(),
        host: FakeHost(),
        system: 'test system',
        tools: buildToolSchemas(),
        vision: true,
        attachments: const [image],
      ).run('这是什么');

      final parts = llm.requests.first[2]['content'] as List;
      expect(parts.first, containsPair('type', 'text'));
      expect(
        parts.where((part) => part['type'] == 'image_url'),
        hasLength(1),
      );
    });
  });

  group('blocked navigation and upload handoff', () {
    test('navigate to a blocked host is rejected before loading it', () async {
      final llm = ScriptedLlm([
        use([call('navigate', {'url': 'https://www.blocked.example/login'})]),
        use([call('done', {'summary': '被禁止了', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl();
      final end = await loop(
        llm: llm,
        control: control,
        startUrl: 'https://allowed.example/',
        isSiteBlocked: (host) => host == 'blocked.example',
      ).run('打开网站');

      expect(control.calls, isNot(contains('navigate')));
      expect(end.outcome, LoopOutcome.partial);
      final toolText = llm.requests.last
          .firstWhere((m) => m['role'] == 'tool')['content']
          .toString();
      expect(toolText, contains('blocked.example'));
    });

    test('upload without files invokes host picker and forwards selected paths', () async {
      final llm = ScriptedLlm([
        use([call('upload', {'ref': 'a4'})]),
        use([call('done', {'summary': '已上传', 'outcome': 'success'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost()..pickedFiles = ['/tmp/report.pdf'];
      final end = await loop(
        llm: llm,
        control: control,
        host: host,
        safeMode: false,
      ).run('上传文件');

      expect(host.pickFilesCount, 1);
      expect(control.calls, contains('upload'));
      expect(end.outcome, LoopOutcome.success);
    });

    test('upload cancelled by user in picker does not execute upload', () async {
      final llm = ScriptedLlm([
        use([call('upload', {'ref': 'a4'})]),
        use([call('done', {'summary': '用户取消', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost()..pickedFiles = null;
      final end = await loop(
        llm: llm,
        control: control,
        host: host,
        safeMode: false,
      ).run('上传文件');

      expect(host.pickFilesCount, 1);
      expect(control.calls, isNot(contains('upload')));
      expect(end.outcome, LoopOutcome.partial);
    });
  });

  group('going to a new site', () {
    test('asks before leaving the current host', () async {
      final llm = ScriptedLlm([
        use([call('navigate', {'url': 'https://evil.example/steal'})]),
        use([call('done', {'summary': '完成', 'outcome': 'success'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost();

      await loop(
        llm: llm,
        control: control,
        host: host,
        startUrl: 'https://shop.example/cart',
      ).run('去别的地方看看');

      // A page can tell the model where to go next. Going there is the user's
      // decision, and it is the one step no write assessment covers.
      expect(host.asks, hasLength(1));
      expect(host.asks.single.navigation, isTrue);
      expect(host.asks.single.payload, 'https://evil.example/steal');
      expect(control.calls, contains('navigate'));
    });

    test('a link on the same site is not a decision', () async {
      final llm = ScriptedLlm([
        use([call('navigate', {'url': 'https://shop.example/checkout'})]),
        use([call('done', {'summary': '完成', 'outcome': 'success'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost();

      await loop(
        llm: llm,
        control: control,
        host: host,
        startUrl: 'https://shop.example/cart',
      ).run('去结算');

      expect(host.asks, isEmpty);
      expect(control.calls, contains('navigate'));
    });

    test('one approval covers the rest of the run', () async {
      final llm = ScriptedLlm([
        use([call('navigate', {'url': 'https://a.example/one'})]),
        use([call('navigate', {'url': 'https://a.example/two'})]),
        use([call('done', {'summary': '完成', 'outcome': 'success'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost();

      await loop(
        llm: llm,
        control: control,
        host: host,
        startUrl: 'https://shop.example/cart',
      ).run('搬去 a.example');

      expect(host.asks, hasLength(1));
      expect(control.calls.where((name) => name == 'navigate'), hasLength(2));
    });

    test('a refusal keeps the page where it is and is not retried', () async {
      final llm = ScriptedLlm([
        use([call('navigate', {'url': 'https://evil.example/steal'})]),
        use([call('done', {'summary': '没去', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl();
      final host = FakeHost()..answer = false;

      final end = await loop(
        llm: llm,
        control: control,
        host: host,
        startUrl: 'https://shop.example/cart',
      ).run('去别的地方看看');

      expect(control.calls, isNot(contains('navigate')));
      expect(end.outcome, LoopOutcome.partial);
      final toolMessages =
          llm.requests.last.where((message) => message['role'] == 'tool').toList();
      expect(toolMessages.single['content'], contains('没有同意'));
    });
  });
}
