import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/tool_descriptor.dart';
import 'package:operon/services/execution_guard.dart';

void main() {
  test('content dedupe normalizes whitespace and case', () {
    final guard = ExecutionGuard();
    guard.rememberContent('Hello   World');
    expect(guard.contentAlreadySent('hello world'), isTrue);
    expect(guard.contentAlreadySent('hello there'), isFalse);
  });

  test('target dedupe is case insensitive', () {
    final guard = ExecutionGuard();
    guard.rememberTarget('Example.com|abc|Reply');
    expect(guard.targetAlreadyProcessed('example.com|ABC|reply'), isTrue);
  });

  test('rate limit detection uses page text', () {
    expect(ExecutionGuard.looksRateLimited('操作过于频繁，请稍后再试'), isTrue);
    expect(ExecutionGuard.looksRateLimited('temporarily blocked'), isTrue);
    expect(ExecutionGuard.looksRateLimited('正常内容'), isFalse);
  });

  test('safe mode allows normal writes but asks for destructive actions', () async {
    var asked = 0;
    final guard = ExecutionGuard(
      safeMode: false,
      onConfirm: (request) async {
        asked++;
        expect(request.risk, ToolRisk.destructive);
        return true;
      },
    );

    expect(
      await guard.confirm(const ConfirmationRequest(
        title: '点击',
        reason: '普通点击',
        target: '按钮',
        risk: ToolRisk.write,
      )),
      isTrue,
    );
    expect(asked, 0);

    expect(
      await guard.confirm(const ConfirmationRequest(
        title: '发送',
        reason: '发布内容',
        target: '发送按钮',
        risk: ToolRisk.destructive,
      )),
      isTrue,
    );
    expect(asked, 1);
  });

  test('confirmation is denied when no handler is configured', () async {
    final guard = ExecutionGuard(safeMode: true);
    expect(
      await guard.confirm(const ConfirmationRequest(
        title: '点击',
        reason: '写入',
        target: '按钮',
      )),
      isFalse,
    );
  });
}
