import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/ports.dart' show RunJournal;
import 'package:operon/agent/prompt.dart';
import 'package:operon/agent/runner.dart';
import 'package:operon/models/agent_conversation.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/models/model_profile.dart';
import 'package:operon/services/conversation_journal.dart';
import 'package:operon/services/conversation_store.dart';

import 'support/fake_devtools.dart';
import 'support/fake_openai.dart';

/// The whole path in one test: a scripted model speaks the OpenAI protocol, the
/// real loop decides what to do, the real control layer talks to a page, and the
/// state the panel renders comes out the other end.
///
/// What this catches that the unit tests cannot: prompt and tool schemas that
/// disagree, a tool result the model cannot read, receipts that never reach the
/// panel, and a loop that runs but never ends.

FakePage articlePage() {
  final page = FakePage(
    url: 'https://news.example.com/article/1',
    title: '春季发布会',
    nodes: const [
      FakePageNode(backendNodeId: 1, role: 'heading', name: '春季发布会'),
      FakePageNode(backendNodeId: 2, role: 'textbox', name: '评论', editable: true),
      FakePageNode(backendNodeId: 3, role: 'button', name: '发送'),
      FakePageNode(backendNodeId: 4, role: 'link', name: '下一篇'),
    ],
  );
  page.boxes
    ..[1] = const FakeBox(10, 10, 300, 30)
    ..[2] = const FakeBox(10, 100, 300, 40)
    ..[3] = const FakeBox(320, 100, 70, 40)
    ..[4] = const FakeBox(10, 160, 100, 24);
  return page;
}

void main() {
  late FakeDevTools page;
  late FakeOpenAi model;
  late AgentLoopRunner runner;

  AgentLoopRunner makeRunner() => AgentLoopRunner();

  tearDown(() async {
    runner.stop();
    await page.close();
    await model.close();
  });

  Future<void> runWith({
    required FakePage fakePage,
    required List<FakeTurn> script,
    required String goal,
    Future<String?> Function(String question)? onAsk,
    bool safeMode = false,
    bool expectThrow = false,
    ThinkingLevel thinking = ThinkingLevel.auto,
    void Function(FakeOpenAi model)? prepare,
    ModelProfile profile = const ModelProfile(),
    RunJournal? journal,
  }) async {
    page = await FakeDevTools.start(fakePage);
    model = await FakeOpenAi.start(script);
    prepare?.call(model);
    runner = makeRunner();
    if (onAsk != null) runner.onAsk = onAsk;
    final run = runner.run(
      goal: goal,
      urlHint: fakePage.url,
      config: model.config.copyWith(thinking: thinking),
      profile: profile,
      safeMode: safeMode,
      notifyOnComplete: false,
      controlConnect: page.connect,
      journal: journal,
    );
    if (expectThrow) {
      await expectLater(run, throwsA(isA<StateError>()));
    } else {
      await run;
    }
  }

  test('reads a page and answers, with the tool results in the next request', () async {
    await runWith(
      fakePage: articlePage(),
      goal: '这页讲了什么',
      script: [
        call('snapshot'),
        call('done', {
          'summary': '一场春季发布会',
          'success': 'success',
          'data': {'title': '春季发布会'},
        }),
      ],
    );

    final state = runner.state;
    expect(state.status, AgentStatus.completed, reason: state.errorMessage);
    expect(state.extractedData, {'title': '春季发布会'});
    expect(model.requests, hasLength(2));

    // The second request must carry the page back to the model, wrapped so it
    // cannot be mistaken for instructions.
    final second = model.messagesOf(1);
    final toolMessage = second.lastWhere((message) => message['role'] == 'tool');
    expect('${toolMessage['content']}', contains(pageContentOpen));
    expect('${toolMessage['content']}', contains('春季发布会'));

    // The system prompt is the first thing a real model receives.
    expect(model.messagesOf(0).first['role'], 'system');
    expect(model.authHeaders.every((header) => header == 'Bearer sk-test-token'), isTrue);
  });

  test('types and sends: the page receives real input and the panel sees it', () async {
    final fakePage = articlePage();
    await runWith(
      fakePage: fakePage,
      goal: '在评论框里说一句「期待」',
      script: [
        call('snapshot'),
        call('type', {'ref': 'a1', 'text': '期待'}),
        call('click', {'ref': 'a2'}),
        call('done', {'summary': '已评论', 'success': 'success'}),
      ],
    );

    expect(runner.state.status, AgentStatus.completed, reason: runner.state.errorMessage);
    expect(fakePage.typedText.join(), '期待');

    // Every action is one card, completed in place.
    final actions = runner.state.logs.where((log) => log.kind == LogKind.action).toList();
    expect(actions, hasLength(3), reason: actions.map((a) => a.title).join(' | '));
    expect(actions.every((action) => action.evidence != null), isTrue);
    expect(actions.last.evidence!.deliveryLabel, '已派发');
  });

  test('a ref the page no longer has is reported, and the model can recover', () async {
    await runWith(
      fakePage: articlePage(),
      goal: '点发送',
      script: [
        // No snapshot first: the ref was never handed out.
        call('click', {'ref': 'a99'}),
        call('snapshot'),
        call('click', {'ref': 'a2'}),
        call('done', {'summary': '点到了', 'success': 'success'}),
      ],
    );

    expect(runner.state.status, AgentStatus.completed, reason: runner.state.errorMessage);
    final errorRow = runner.state.logs.firstWhere(
      (log) => log.kind == LogKind.error,
      orElse: () => fail('a failure must show up as a row: ${runner.state.logs.map((l) => l.title)}'),
    );
    expect(errorRow.detail, contains('从未被展示过'));
    // And the model is told which kind of failure it was, so it can act on it.
    expect(
      model.allMessages.map((m) => '${m['content']}').join('\n'),
      contains('unknownRef'),
    );
    // The recovery happened: the request after the failure still worked.
    expect(model.requests.length, greaterThanOrEqualTo(3));
  });

  test('clicking the same dead button is stopped by the guards, not by luck', () async {
    await runWith(
      fakePage: articlePage(),
      goal: '一直点',
      // A link that changes nothing: the shape of a dead control.
      script: List.generate(8, (_) => call('click', {'ref': 'a3'})),
    );

    final text = runner.state.logs
        .map((log) => '${log.title} ${log.detail ?? ''}')
        .join('\n');
    expect(text, contains('重复'), reason: text);
    expect(
      runner.state.status,
      anyOf(AgentStatus.completed, AgentStatus.error),
    );
    expect(model.requests.length, lessThan(8), reason: 'the run must end early');
  });

  test('an endpoint that rejects the thinking level still finishes, and says so',
      () async {
    await runWith(
      fakePage: articlePage(),
      script: [
        call('read'),
        say('讲的是春季发布会。'),
      ],
      goal: '这页讲了什么',
      thinking: ThinkingLevel.deep,
      prepare: (fake) => fake.rejectReasoningEffort = true,
    );

    expect(runner.state.status, AgentStatus.completed);
    // The preference was sent, refused, and dropped — once.
    expect(model.requests.first['reasoning_effort'], 'high');
    expect(model.requests[1].containsKey('reasoning_effort'), isFalse);
    expect(
      runner.state.logs.any((item) => item.title.contains('端点不支持')),
      isTrue,
      reason: 'a silently ignored setting is worse than a refused one',
    );
  });

  test('a model marked as not calling tools stops before the first call', () async {
    await runWith(
      fakePage: articlePage(),
      script: [say('我不会用工具')],
      goal: '这页讲了什么',
      profile: const ModelProfile(supportsTools: false),
      expectThrow: true,
    );

    expect(runner.state.status, AgentStatus.error);
    expect(runner.state.errorMessage, contains('不支持工具调用'));
    expect(model.requests, isEmpty,
        reason: 'a model that cannot call tools cannot do anything here');
  });

  test('a model marked as not taking reasoning_effort never receives it', () async {
    await runWith(
      fakePage: articlePage(),
      script: [say('讲的是春季发布会。')],
      goal: '这页讲了什么',
      thinking: ThinkingLevel.deep,
      profile: const ModelProfile(reasoning: ModelTrait.no),
    );

    expect(runner.state.status, AgentStatus.completed);
    expect(model.requests.first.containsKey('reasoning_effort'), isFalse);
    expect(model.requests.length, 1, reason: 'no wasted round trip either');
  });

  test('a plain answer with no tool call ends the run without touching the page', () async {
    final fakePage = articlePage();
    await runWith(
      fakePage: fakePage,
      goal: '你好',
      script: [say('你好，我可以帮你读这个页面。')],
    );

    expect(runner.state.status, AgentStatus.completed);
    final texts = runner.state.logs.map((log) => log.title).join('\n');
    expect(texts, contains('你好，我可以帮你读这个页面。'));
    expect(fakePage.typedText, isEmpty);
  });

  test('arguments a model wrote badly become a readable error, not a crash', () async {
    await runWith(
      fakePage: articlePage(),
      goal: '点一下',
      script: [
        const FakeTurn(calls: [
          (name: 'click', arguments: '{"ref": a3}', id: 'c1'),
        ]),
        call('snapshot'),
        call('done', {'summary': '改用 ref', 'success': 'partial'}),
      ],
    );

    expect(runner.state.status, AgentStatus.completed, reason: runner.state.errorMessage);
    // Broken JSON is not a parse crash: the tool complains about the missing ref.
    final messages = model.allMessages.map((m) => '${m['content']}').join('\n');
    expect(messages, contains('ref'));
  });

  test('a question for the user reaches the panel and comes back as an answer', () async {
    final asked = <String>[];
    await runWith(
      fakePage: articlePage(),
      goal: '用我的名字评论',
      onAsk: (question) async {
        asked.add(question);
        return '小林';
      },
      script: [
        call('ask_user', {'question': '你希望用什么名字？'}),
        call('snapshot'),
        call('type', {'ref': 'a1', 'text': '小林'}),
        call('done', {'summary': '用你的名字评论了', 'success': 'success'}),
      ],
    );

    expect(runner.state.status, AgentStatus.completed, reason: runner.state.errorMessage);
    expect(asked, hasLength(1));
    // The answer must be visible to the model, or asking was pointless.
    expect(model.allMessages.map((m) => '${m['content']}').join('\n'), contains('小林'));
  });

  test('a model endpoint that rejects the request is reported in the panel', () async {
    page = await FakeDevTools.start(articlePage());
    model = await FakeOpenAi.start(const []);
    model.failWith = 'this model does not support tools';
    runner = makeRunner();

    await runner.run(
      goal: '读页面',
      urlHint: 'https://news.example.com/article/1',
      config: model.config,
      notifyOnComplete: false,
      controlConnect: page.connect,
    );

    expect(runner.state.status, AgentStatus.error);
    expect(runner.state.errorMessage, contains('tools'));
  });

  test('writes ask first in safe mode, and the answer decides', () async {
    final fakePage = articlePage();
    page = await FakeDevTools.start(fakePage);
    model = await FakeOpenAi.start([
      call('snapshot'),
      call('click', {'ref': 'a2'}),
      call('done', {'summary': '没有点', 'success': 'partial'}),
    ]);
    runner = makeRunner();

    final run = runner.run(
      goal: '点发送',
      urlHint: fakePage.url,
      config: model.config,
      safeMode: true,
      notifyOnComplete: false,
      controlConnect: page.connect,
    );
    // The panel is what a person touches; here it declines.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(runner.state.status, AgentStatus.waitingConfirmation);
    expect(runner.state.confirmationReason, isNotNull);
    runner.confirmAction(false);
    await run;

    expect(runner.state.status, AgentStatus.completed);
    final skipped = runner.state.logs.map((log) => log.title).join('\n');
    expect(skipped, contains('跳过'));
  });
  test('the model receives the earlier turns of the same conversation',
      () async {
    // The file's own page/model/runner, so tearDown cleans them up.
    page = await FakeDevTools.start(FakePage(
      url: 'https://example.com/list',
      title: '清单',
      nodes: const [FakePageNode(backendNodeId: 1, role: 'heading', name: '清单')],
    ));
    model = await FakeOpenAi.start([call('done', {'summary': '好了'})]);
    runner = makeRunner();

    await runner.run(
      goal: '继续，把第二条也标上',
      urlHint: 'https://example.com/list',
      config: model.config,
      safeMode: false,
      notifyOnComplete: false,
      controlConnect: page.connect,
      priorTurns: [
        AgentTurn(
          id: 't1',
          message: '把第一条标成完成',
          startedAt: DateTime(2026, 3, 1, 10),
          endedAt: DateTime(2026, 3, 1, 10, 1),
          status: 'completed',
          result: '标好了。',
        ),
      ],
    );

    // The earlier turn is in the request, before this turn's own goal: that is
    // what 「继续」 points at.
    final all = model.allMessages.map((m) => '${m['content']}').join('\n');
    expect(all, contains('把第一条标成完成'));
    expect(all, contains('标好了。'));
    expect(all, contains('继续，把第二条也标上'));
    final index = model.allMessages.indexWhere(
      (m) => '${m['content']}'.contains('把第一条标成完成'),
    );
    final goalIndex = model.allMessages.indexWhere(
      (m) => '${m['content']}'.contains('继续，把第二条也标上'),
    );
    expect(index, lessThan(goalIndex));
  });

  test('modelVision profile exposes screenshot tool and targetUrl stays populated', () async {
    page = await FakeDevTools.start(articlePage());
    model = await FakeOpenAi.start([
      call('done', {'summary': '完成'}),
    ]);
    runner = makeRunner();

    await runner.run(
      goal: '看看页面',
      urlHint: 'https://news.example.com/article/1',
      config: model.config,
      profile: const ModelProfile(vision: ModelTrait.yes),
      safeMode: false,
      notifyOnComplete: false,
      controlConnect: page.connect,
    );

    final tools = (model.requests.single['tools'] as List)
        .map((entry) => ((entry as Map)['function'] as Map)['name'])
        .toList();
    expect(tools, contains('screenshot'));
    expect(runner.state.targetUrl, 'https://news.example.com/article/1');
  });

  test('stopping a runner does not poison its next run', () async {
    page = await FakeDevTools.start(articlePage());
    model = await FakeOpenAi.start([
      call('done', {'summary': '第二次完成'}),
    ]);
    runner = makeRunner();
    runner.stop();

    await runner.run(
      goal: '再次执行',
      urlHint: 'https://news.example.com/article/1',
      config: model.config,
      safeMode: false,
      notifyOnComplete: false,
      controlConnect: page.connect,
    );

    expect(runner.state.status, AgentStatus.completed,
        reason: runner.state.errorMessage);
    expect(model.requests, hasLength(1));
    expect(
      runner.state.logs.any((item) => (item.detail ?? '').contains('第二次完成')),
      isTrue,
    );
  });

  test('a run writes each step before it happens, so a kill still leaves them',
      () async {
    // A real store and a real journal: the question is whether the runner
    // actually fills it, not whether the store can hold a list.
    final store = ConversationStore.inMemory();
    final conversation = store.create();
    final turn = await store.beginTurn(
      conversation.id,
      message: '在评论框里说一句「期待」',
      startedAt: DateTime(2026, 5, 1, 10),
    );

    await runWith(
      fakePage: articlePage(),
      goal: '在评论框里说一句「期待」',
      script: [
        call('snapshot'),
        call('type', {'ref': 'a1', 'text': '期待'}),
        call('click', {'ref': 'a2'}),
        call('done', {'summary': '已评论', 'success': 'success'}),
      ],
      journal: ConversationJournal(store, conversation.id, turn.id),
    );

    final stored = store.byId(conversation.id)!.turns.single;
    expect(stored.steps, isNotEmpty, reason: 'the journal was never called');
    expect(stored.steps.map((step) => step.tool), contains('click'));
    expect(stored.steps.every((step) => step.summary.trim().isNotEmpty), isTrue);
    expect(stored.steps.any((step) => step.isPending), isFalse,
        reason: 'every result landed on the row its intent opened');

    // Nothing closed the turn: that is what the app being killed looks like,
    // and a restart turns exactly this state into "interrupted".
    expect(stored.isRunning, isTrue);
  });
}
