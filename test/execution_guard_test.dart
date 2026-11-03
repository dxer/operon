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

  test('submit intent recognizes publishing words', () {
    expect(
      ExecutionGuard.looksLikeSubmitIntent(
        thought: '点击发送',
        targetText: '发送',
        description: '',
      ),
      isTrue,
    );
    expect(
      ExecutionGuard.looksLikeSubmitIntent(
        thought: '打开菜单',
        targetText: '设置',
        description: '',
      ),
      isFalse,
    );
  });

  test('search-only actions and composer openers are not side effects', () {
    expect(
      ExecutionGuard.assessClick(
        targetText: '搜索',
        thought: '提交搜索',
      ).sideEffect,
      isFalse,
    );
    expect(
      ExecutionGuard.assessClick(
        targetText: '回复',
        thought: '准备发布回复',
      ).sideEffect,
      isFalse,
    );
    expect(
      ExecutionGuard.assessClick(
        targetText: '发送',
        thought: '发布回复',
      ).sideEffect,
      isTrue,
    );
  });

  test('draft targets are blocked without blocking plain save', () {
    expect(
      ExecutionGuard.assessClick(targetText: '保存草稿').draftBlocked,
      isTrue,
    );
    expect(
      ExecutionGuard.assessClick(targetText: '保存').draftBlocked,
      isFalse,
    );
  });

  test('declared intent overrides keyword matching', () {
    expect(
      ExecutionGuard.assessClick(
        targetText: '下一步',
        declaredIntent: 'navigate',
      ).sideEffect,
      isFalse,
    );
    expect(
      ExecutionGuard.assessClick(
        targetText: '继续',
        declaredIntent: 'submit',
      ).sideEffect,
      isTrue,
    );
    expect(
      ExecutionGuard.assessClick(
        targetText: '继续',
        declaredIntent: 'destructive',
      ).destructive,
      isTrue,
    );
  });

  test('focus-only inputs and sensitive components are classified', () {
    expect(
      ExecutionGuard.assessClick(
        targetText: '搜索',
        tag: 'INPUT',
        inputType: 'text',
      ).sideEffect,
      isFalse,
    );
    expect(
      ExecutionGuard.assessClick(
        targetText: '继续',
        componentSensitive: true,
      ).sideEffect,
      isTrue,
    );
    final payment = ExecutionGuard.assessClick(
      targetText: '立即支付',
      componentSensitive: true,
    );
    expect(payment.sideEffect, isTrue);
    expect(payment.destructive, isTrue);
  });

  test('content normalization ignores punctuation and whitespace', () {
    final guard = ExecutionGuard();
    guard.rememberContent('Hello,  World!');
    expect(guard.contentAlreadySent('hello world'), isTrue);
  });

  test('clearDedupe resets content and target state', () {
    final guard = ExecutionGuard()
      ..rememberContent('same')
      ..rememberTarget('target');

    guard.clearDedupe();
    expect(guard.contentAlreadySent('same'), isFalse);
    expect(guard.targetAlreadyProcessed('target'), isFalse);
  });

  test('draft buttons are detected without blocking plain save', () {
    expect(ExecutionGuard.looksLikeDraftAction('保存草稿'), isTrue);
    expect(ExecutionGuard.looksLikeDraftAction('存草稿'), isTrue);
    expect(ExecutionGuard.looksLikeDraftAction('Save draft'), isTrue);
    expect(ExecutionGuard.looksLikeDraftAction('发送'), isFalse);
    expect(ExecutionGuard.looksLikeDraftAction('保存'), isFalse);
  });

  test('rate limit detection uses page text', () {
    expect(ExecutionGuard.looksRateLimited('操作过于频繁，请稍后再试'), isTrue);
    expect(ExecutionGuard.looksRateLimited('temporarily blocked'), isTrue);
    expect(ExecutionGuard.looksRateLimited('正常内容'), isFalse);
  });

  test('safe mode allows normal writes but asks for destructive actions',
      () async {
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
