import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/macro_workflow.dart';
import 'package:operon/services/macro_precondition.dart';

MacroWorkflow _macro(String initialUrl) => MacroWorkflow(
      id: 'm1',
      title: '测试宏',
      initialUrl: initialUrl,
      createdAt: DateTime(2024, 1, 1),
      steps: const [],
    );

void main() {
  test('macros saved without a URL stay replayable', () {
    final result = MacroPrecondition.check(
      macro: _macro(''),
      currentUrl: 'https://example.com/page',
    );
    expect(result.ok, isTrue);
    expect(result.legacyNoUrl, isTrue);
  });

  test('the current page must be a real web page', () {
    expect(
      MacroPrecondition.check(
        macro: _macro(''),
        currentUrl: '',
      ).ok,
      isFalse,
    );
    expect(
      MacroPrecondition.check(
        macro: _macro(''),
        currentUrl: 'about:blank',
      ).ok,
      isFalse,
    );
    expect(
      MacroPrecondition.check(
        macro: _macro(''),
        currentUrl: 'operon://newtab',
      ).ok,
      isFalse,
    );
  });

  test('a different host is rejected', () {
    final result = MacroPrecondition.check(
      macro: _macro('https://example.com/feed'),
      currentUrl: 'https://other.test/feed',
    );
    expect(result.ok, isFalse);
    expect(result.reason, contains('example.com'));
  });

  test('www prefixes are normalized', () {
    final result = MacroPrecondition.check(
      macro: _macro('https://www.example.com/feed'),
      currentUrl: 'https://example.com/other-path',
    );
    expect(result.ok, isTrue);
  });

  test('an invalid recorded URL is rejected', () {
    final result = MacroPrecondition.check(
      macro: _macro('://broken'),
      currentUrl: 'https://example.com',
    );
    expect(result.ok, isFalse);
    expect(result.reason, contains('无效'));
  });
}
