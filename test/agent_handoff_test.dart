import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/agent/tools.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/results.dart';

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
  FakeControl({this.captchaInfo, this.results = const {}});

  final Map<String, ToolResult> results;
  CaptchaInfo? captchaInfo;
  final List<String> calls = [];

  @override
  Future<ToolResult> execute(String tool, [Map<String, Object?> args = const {}]) async {
    calls.add(tool);
    return results[tool] ?? ToolResult(ok: true, text: '$tool ok');
  }

  @override
  CaptchaInfo? get captcha => captchaInfo;

  @override
  String? refLabel(String? ref) => null;

  @override
  set onGesture(void Function(double x, double y, String label)? value) {}
}

class FakeHost implements HostPort {
  FakeHost({this.answers = const []});

  final List<String?> answers;
  final List<PersonRequest> persons = [];
  final List<ConfirmRequest> confirms = [];
  final List<String> notes = [];

  @override
  Future<bool> confirm(ConfirmRequest request) async {
    confirms.add(request);
    return true;
  }

  @override
  Future<String?> askPerson(PersonRequest request) async {
    persons.add(request);
    if (answers.isEmpty) return null;
    return answers.removeAt(0);
  }

  @override
  void note(String title, {String? detail, bool isError = false}) => notes.add(title);
}

ToolCallRequest call(String name, [Map<String, Object?> args = const {}, String? id]) =>
    ToolCallRequest(id: id ?? 'c_$name', name: name, args: args, rawArguments: '{}');

LlmTurn use(List<ToolCallRequest> calls) => LlmTurn(content: '', calls: calls);

AgentLoop loop({
  required ScriptedLlm llm,
  required FakeControl control,
  required FakeHost host,
  bool vision = false,
}) =>
    AgentLoop(
      llm: llm,
      control: control,
      host: host,
      system: 's',
      tools: buildToolSchemas(vision: vision),
      vision: vision,
    );

ToolResult snapshot({String url = 'https://x.com/1'}) => ToolResult(
      ok: true,
      text: '[a1] button "发送"',
      data: {'url': url},
      receipt: Receipt(tool: 'snapshot', delivery: Delivery.notDelivered, pageReacted: false),
    );

void main() {
  group('captcha hand-off', () {
    test('a challenge is handed to the person, never solved by the agent', () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('done', {'summary': '登录成功', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(
        results: {'snapshot': snapshot()},
        captchaInfo: const CaptchaInfo(present: true, kind: 'Cloudflare'),
      );
      final host = FakeHost(answers: ['ok']);

      final end = await loop(llm: llm, control: control, host: host).run('登录');

      expect(host.persons, hasLength(1));
      expect(host.persons.single.isCaptcha, isTrue);
      expect(host.persons.single.title, contains('Cloudflare'));
      expect(end.outcome, LoopOutcome.success);

      final note = llm.requests.last.firstWhere((message) =>
          message['role'] == 'tool' && '${message['content']}'.contains('人机验证'));
      expect(note['content'], contains('先 snapshot'));
    });

    test('a person who cancels stops the run instead of clicking on', () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('done', {'summary': 'x', 'outcome': 'partial'})]),
      ]);
      final control = FakeControl(
        results: {'snapshot': snapshot()},
        captchaInfo: const CaptchaInfo(present: true, kind: '人机验证'),
      );

      final end = await loop(llm: llm, control: control, host: FakeHost()).run('登录');

      expect(end.outcome, LoopOutcome.partial);
      expect(end.stopReason, contains('人机验证'));
      expect(control.calls, ['snapshot']);
    });

    test('no challenge means no hand-off', () async {
      final llm = ScriptedLlm([
        use([call('snapshot')]),
        use([call('done', {'summary': 'ok', 'outcome': 'success'})]),
      ]);
      final control = FakeControl(results: {'snapshot': snapshot()});
      final host = FakeHost();

      await loop(llm: llm, control: control, host: host).run('看看');

      expect(host.persons, isEmpty);
    });
  });

  group('ask_user', () {
    test('the answer comes back to the model as the call result', () async {
      final llm = ScriptedLlm([
        use([call(askUserToolName, {'question': '用哪个账号登录？'})]),
        use([call('done', {'summary': '已用工作账号登录', 'outcome': 'success'})]),
      ]);
      final host = FakeHost(answers: ['工作账号']);

      final end = await loop(
        llm: llm,
        control: FakeControl(),
        host: host,
      ).run('登录');

      expect(host.persons.single.kind, 'question');
      expect(host.persons.single.title, '用哪个账号登录？');
      expect(end.outcome, LoopOutcome.success);

      final answer = llm.requests.last.firstWhere((message) =>
          message['role'] == 'tool' && '${message['content']}'.contains('工作账号'));
      expect(answer['content'], contains('用户的回答'));
    });

    test('asking does not touch the page, and is not a write', () {
      expect(toolMutates(askUserToolName), isFalse);
      final schema = buildToolSchemas()
          .firstWhere((entry) => (entry['function'] as Map)['name'] == askUserToolName);
      final properties = ((schema['function'] as Map)['parameters'] as Map)['properties'] as Map;
      expect(properties.keys, contains('question'));
    });

    test('a cancelled question stops the run', () async {
      final llm = ScriptedLlm([use([call(askUserToolName, {'question': '继续吗？'})])]);

      final end = await loop(
        llm: llm,
        control: FakeControl(),
        host: FakeHost(),
      ).run('继续');

      expect(end.outcome, LoopOutcome.partial);
      expect(end.stopReason, contains('没有回答'));
    });

    test('an empty question is reported instead of asked', () async {
      final llm = ScriptedLlm([
        use([call(askUserToolName, const {})]),
        use([call('done', {'summary': 'ok', 'outcome': 'partial'})]),
      ]);
      final host = FakeHost(answers: ['whatever']);

      await loop(llm: llm, control: FakeControl(), host: host).run('做点什么');

      expect(host.persons, isEmpty);
    });
  });

  group('vision', () {
    ToolResult shot() => const ToolResult(
          ok: true,
          text: '已截取页面',
          data: {'image': 'AAAA', 'mimeType': 'image/png'},
        );

    test('a screenshot follows as an image message when the model can see', () async {
      final llm = ScriptedLlm([
        use([call('screenshot')]),
        use([call('done', {'summary': 'ok', 'outcome': 'success'})]),
      ]);

      await loop(
        llm: llm,
        control: FakeControl(results: {'screenshot': shot()}),
        host: FakeHost(),
        vision: true,
      ).run('看看这个页面');

      final last = llm.requests.last;
      final imageMessage = last.firstWhere(
        (message) => message['content'] is List,
        orElse: () => const <String, Object?>{},
      );
      expect(imageMessage, isNotEmpty);
      final parts = imageMessage['content'] as List;
      expect((parts.last as Map)['type'], 'image_url');
      expect('${(parts.last as Map)['image_url']}'.toString(), contains('data:image/png;base64,AAAA'));
    });

    test('a blind model gets no image and is told it was skipped', () async {
      final llm = ScriptedLlm([
        use([call('screenshot')]),
        use([call('done', {'summary': 'ok', 'outcome': 'success'})]),
      ]);

      await loop(
        llm: llm,
        control: FakeControl(results: {'screenshot': shot()}),
        host: FakeHost(),
      ).run('看看这个页面');

      final last = llm.requests.last;
      expect(last.where((message) => message['content'] is List), isEmpty);
      final note = last.firstWhere((message) =>
          message['role'] == 'tool' && '${message['content']}'.contains('截图'));
      expect(note['content'], contains('看不到图片'));
    });
  });
}
