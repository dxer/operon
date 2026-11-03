import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/finish_verifier.dart';

FinishDecision _verify({
  String goal = '总结当前页面',
  String summary = '已总结页面上的三个核心观点和一条结论，内容完整。',
  dynamic extractedData,
  int navigateCount = 0,
  bool pageHasContent = true,
  String currentUrl = 'https://example.com/article',
  int rejectionCount = 0,
}) {
  return FinishVerifier.verify(
    goal: goal,
    summary: summary,
    extractedData: extractedData,
    step: 3,
    navigateCount: navigateCount,
    pageHasContent: pageHasContent,
    currentUrl: currentUrl,
    rejectionCount: rejectionCount,
  );
}

void main() {
  test('rejects blank and internal pages', () {
    expect(_verify(currentUrl: '').allowed, isFalse);
    expect(_verify(currentUrl: 'about:blank').allowed, isFalse);
    expect(_verify(currentUrl: 'operon://newtab').allowed, isFalse);
  });

  test('rejects an empty page without extracted data', () {
    expect(_verify(pageHasContent: false).allowed, isFalse);
    expect(_verify(pageHasContent: false, extractedData: []).allowed, isTrue);
  });

  test('requires a summary', () {
    expect(_verify(summary: '   ').allowed, isFalse);
  });

  test('evidence goals reject short navigation-only summaries', () {
    final decision = _verify(
      goal: '提取当前页面的商品价格',
      summary: '已打开页面。',
      navigateCount: 1,
    );
    expect(decision.allowed, isFalse);
  });

  test('a substantial summary is enough for evidence goals', () {
    expect(
      _verify(
        goal: '总结当前页面',
        summary: '页面介绍了三个核心观点：成本、可靠性和可维护性。随后给出结论，'
            '认为长期收益高于初期投入，并提醒注意迁移成本。',
      ).allowed,
      isTrue,
    );
  });

  test('extracted data satisfies the evidence requirement', () {
    expect(
      _verify(
        goal: '提取商品价格',
        summary: '已提取。',
        extractedData: [
          {'title': 'A', 'price': '1'}
        ],
      ).allowed,
      isTrue,
    );
  });

  test('repeated rejections let the task finish with a warning', () {
    final decision = _verify(
      goal: '提取商品价格',
      summary: '已打开页面。',
      rejectionCount: 2,
    );
    expect(decision.allowed, isTrue);
    expect(decision.warning, isTrue);
  });
}
