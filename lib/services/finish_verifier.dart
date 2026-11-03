class FinishDecision {
  final bool allowed;
  final String? reason;
  final bool warning;

  const FinishDecision({
    required this.allowed,
    this.reason,
    this.warning = false,
  });
}

/// Guards the model's `finish` action.
///
/// The model tends to treat "I navigated to the site" as "the task is done".
/// A general agent must require some evidence from the page instead of
/// trusting that sentence.
class FinishVerifier {
  static const int _maxRejections = 2;

  static FinishDecision verify({
    required String goal,
    required String summary,
    required dynamic extractedData,
    required int step,
    required int navigateCount,
    required bool pageHasContent,
    required String currentUrl,
    required int rejectionCount,
  }) {
    final text = summary.trim();
    final hasExtractedData = extractedData != null;

    if (currentUrl.isEmpty ||
        currentUrl.startsWith('about:') ||
        currentUrl.startsWith('operon://')) {
      return const FinishDecision(
        allowed: false,
        reason: '当前仍停留在空白页或起始页，请先打开目标网页并读取内容。',
      );
    }

    if (!pageHasContent && !hasExtractedData) {
      return const FinishDecision(
        allowed: false,
        reason: '当前页面没有可读内容，无法证明任务已经完成。',
      );
    }

    if (text.isEmpty) {
      return const FinishDecision(
        allowed: false,
        reason: 'finish 缺少 summary，请说明实际完成了什么。',
      );
    }

    if (rejectionCount >= _maxRejections) {
      return const FinishDecision(
        allowed: true,
        warning: true,
        reason: '完成校验多次未通过，已放行，但结果可能不完整。',
      );
    }

    final goalNeedsEvidence = RegExp(
      r'找|搜索|搜一下|列出|提取|抓取|总结|汇总|对比|推荐|热门|排行|哪些|多少|'
      r'find|search|list|extract|summar|compare|trending|top',
      caseSensitive: false,
    ).hasMatch(goal);

    final summaryLooksLikeOpenOnly = RegExp(
      r'已打开|打开页面|已跳转|跳转到|已进入|opened|navigated',
      caseSensitive: false,
    ).hasMatch(text);

    final summarySubstantial = text.length >= 40;

    if (goalNeedsEvidence && !hasExtractedData && !summarySubstantial) {
      return const FinishDecision(
        allowed: false,
        reason: '目标要求查找/提取/总结内容，但尚未提取数据，'
            '完成说明也过于简短。请先读取页面具体条目，把结果放进 extracted_data 或输出详细 summary。',
      );
    }

    if (navigateCount > 0 && !hasExtractedData && text.length < 24) {
      return const FinishDecision(
        allowed: false,
        reason: '刚刚只完成了页面跳转，还没有读取页面内容。'
            '请继续观察/滚动/提取后再 finish。',
      );
    }

    if (summaryLooksLikeOpenOnly && !hasExtractedData && !summarySubstantial) {
      return const FinishDecision(
        allowed: false,
        reason: '“已打开/已跳转”不等于完成任务。请给出页面上的具体结果或提取数据。',
      );
    }

    return const FinishDecision(allowed: true);
  }
}
