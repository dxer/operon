import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/loop.dart';
import 'package:operon/agent/ports.dart';
import 'package:operon/control/perception/captcha.dart';
import 'package:operon/control/protocol/results.dart';
import 'package:operon/models/agent_state.dart';

/// The panel shows one card per call: what was dispatched, what the page did,
/// whether the expectation held — kept apart, never folded into one tick.

class _Llm implements LlmPort {
  _Llm(this.turns);
  final List<LlmTurn> turns;
  int _index = 0;

  @override
  Future<LlmTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async =>
      turns[_index++];
}

class _Control implements ControlPort {
  _Control(this.result);
  final ToolResult result;

  @override
  Future<ToolResult> execute(String tool, [Map<String, Object?> args = const {}]) async => result;

  @override
  CaptchaInfo? get captcha => null;

  @override
  String? refLabel(String? ref) => ref == null ? null : '搜索';

  @override
  set onGesture(void Function(double x, double y, String label)? value) {}
}

class _Host implements HostPort {
  @override
  Future<bool> confirm(ConfirmRequest request) async => true;

  @override
  Future<String?> askPerson(PersonRequest request) async => null;

  @override
  void note(String title, {String? detail, bool isError = false}) {}
}

void main() {
  group('StepEvidence', () {
    test('a receipt keeps delivery, reaction and expectation apart', () {
      final evidence = StepEvidence.fromReceipt({
        'tool': 'click',
        'delivery': 'delivered',
        'pageReacted': false,
        'expectedStateReached': false,
        'elapsedMs': 240,
      });
      expect(evidence.deliveryLabel, '已派发');
      expect(evidence.reactionLabel, '页面无变化');
      expect(evidence.expectationLabel, '未达预期');
      expect(evidence.summary, '已派发 · 页面无变化 · 未达预期 · 240ms');
      expect(evidence.isEmpty, isFalse);
    });

    test('a receipt with no outcome is empty', () {
      expect(StepEvidence.fromReceipt({'tool': 'snapshot'}).isEmpty, isTrue);
      expect(StepEvidence.none.isEmpty, isTrue);
    });

    test('changes and a note survive the trip', () {
      final evidence = StepEvidence.fromReceipt({
        'delivery': 'delivered',
        'changes': ['+ [a9] textbox "评论框"', '- [a3] button "发送"'],
        'note': '等待被缩短到 300ms',
        'urlBefore': 'https://x.com/a',
        'urlAfter': 'https://x.com/b',
      });
      expect(evidence.changes, hasLength(2));
      expect(evidence.note, '等待被缩短到 300ms');
      expect(evidence.urlChanged, isTrue);
    });
  });

  group('one call is one card', () {
    final opened = AgentLogItem(
      step: 3,
      title: '点击「搜索」',
      kind: LogKind.action,
    );

    test('a successful call fills the same row', () {
      final done = opened.completeWith(
        failed: false,
        evidence: StepEvidence.fromReceipt({
          'delivery': 'delivered',
          'pageReacted': true,
        }),
      );
      expect(done.title, opened.title);
      expect(done.step, opened.step);
      expect(done.kind, LogKind.action);
      expect(done.isError, isFalse);
      expect(done.evidence?.reactionLabel, '页面有反应');
      expect(done.timestamp, opened.timestamp);
    });

    test('a failure marks the same row, not a new one', () {
      final done = opened.completeWith(failed: true, detail: 'ref 已失效\n重新 snapshot 即可');
      expect(done.title, opened.title, reason: 'the action still says what it was');
      expect(done.kind, LogKind.error);
      expect(done.isError, isTrue);
      expect(done.detail, contains('重新 snapshot'));
    });
  });

  group('the loop hands the receipt to the panel', () {
    test('a click carries its receipt through onToolFinished', () async {
      Map<String, Object?>? seen;
      final loop = AgentLoop(
        llm: _Llm([
          const LlmTurn(
            content: '',
            calls: [ToolCallRequest(id: 'c1', name: 'click', args: {'ref': 'a1'})],
          ),
          const LlmTurn(
            content: '',
            calls: [
              ToolCallRequest(id: 'c2', name: 'done', args: {'summary': '好了', 'success': 'success'}),
            ],
          ),
        ]),
        control: _Control(ToolResult(
          ok: true,
          text: '已派发',
          receipt: Receipt(
            tool: 'click',
            delivery: Delivery.delivered,
            pageReacted: true,
            expectedStateReached: true,
            changes: const ['+ [a9] textbox "评论框"'],
            elapsed: const Duration(milliseconds: 180),
          ),
        )),
        host: _Host(),
        system: 'system',
        tools: const [],
        onToolFinished: (call, result) => seen = result.receipt,
      );
      await loop.run('搜索');
      expect(seen, isNotNull);
      final evidence = StepEvidence.fromReceipt(seen!);
      expect(evidence.delivery, 'delivered');
      expect(evidence.expectedStateReached, isTrue);
      expect(evidence.changes, hasLength(1));
      expect(evidence.elapsedMs, 180);
    });

    test('a screenshot too large to keep still reports the step', () async {
      Map<String, Object?>? seen;
      final huge = List.filled(500000, 'A').join();
      final loop = AgentLoop(
        llm: _Llm([
          const LlmTurn(
            content: '',
            calls: [ToolCallRequest(id: 'c1', name: 'screenshot')],
          ),
          const LlmTurn(
            content: '看不清',
            calls: [ToolCallRequest(id: 'c2', name: 'done', args: {'summary': '好了'})],
          ),
        ]),
        control: _Control(ToolResult(ok: true, text: '已截图', data: {'image': huge})),
        host: _Host(),
        system: 'system',
        tools: const [],
        onToolFinished: (call, result) => seen = result.receipt,
      );
      await loop.run('看看页面');
      expect(seen, isNotNull);
      expect(seen!.containsKey('image'), isFalse, reason: '300KB of base64 per step is not kept');
      expect(StepEvidence.fromReceipt(seen!).isEmpty, isTrue);
    });
  });
}
