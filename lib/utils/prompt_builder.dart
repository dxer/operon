import 'dart:convert';
import '../config/app_constants.dart';
import '../models/agent_state.dart';

class PromptBuilder {
  /// Builds the messages array for the OpenAI chat completion API
  static List<Map<String, String>> buildMessages({
    required String userGoal,
    required List<AgentLogItem> historyLogs,
    required String currentUrl,
    required String pageTitle,
    required String currentDomTree,
    int? currentStep,
    int? maxSteps,
    dynamic extractedData,
    List<String> sentContents = const [],
  }) {
    final messages = <Map<String, String>>[];

    // 1. System Prompt
    messages.add({
      'role': 'system',
      'content': AppConstants.agentSystemPrompt,
    });

    // 2. Build history summary (only actions taken, omitting past DOM trees).
    // Failed attempts must stay visible, otherwise the model repeats them.
    final historyLines = <String>[];
    for (final item in historyLogs) {
      if (item.step > 0) {
        var detail = '';
        if (item.isError && item.detail != null) {
          final reason = item.detail!.length > 200
              ? '${item.detail!.substring(0, 200)}…'
              : item.detail;
          detail = '（失败：$reason）';
        }
        historyLines.add('- 步骤 ${item.step}: ${item.title}$detail');
      }
    }
    final historyText =
        historyLines.isEmpty ? '（这是第一步，尚无历史操作）' : historyLines.join('\n');

    // 3. Make the immediate outcome explicit. This is the strongest signal for
    // the model to stop repeating a click that did nothing.
    final recent = historyLogs.where((item) => item.step > 0).toList();
    final recentLines = <String>[];
    for (final item
        in recent.length > 3 ? recent.sublist(recent.length - 3) : recent) {
      if (item.detail != null && item.detail!.isNotEmpty) {
        final detail = item.detail!.length > 160
            ? '${item.detail!.substring(0, 160)}…'
            : item.detail;
        recentLines.add('${item.isError ? '❌' : '✅'} ${item.title} — $detail');
      } else {
        recentLines.add('${item.isError ? '❌' : '✅'} ${item.title}');
      }
    }
    final recentText =
        recentLines.isEmpty ? '（尚无执行结果）' : recentLines.join('\n');

    // 4. Compact view of data already extracted, so multi-page scraping does
    // not keep returning the same records.
    var extractedText = '';
    if (extractedData != null) {
      try {
        final raw = jsonEncode(extractedData);
        final clipped =
            raw.length > 1800 ? '${raw.substring(0, 1800)}…（已截断）' : raw;
        extractedText = '\n【已提取的数据（不要重复提取相同内容）】:\n$clipped\n';
      } catch (_) {}
    }

    // 4.1 Previously sent content is shown explicitly so the model can vary
    // batch replies even though typed text is hidden from the audit logs.
    var sentText = '';
    if (sentContents.isNotEmpty) {
      final recentSent = sentContents.length > 5
          ? sentContents.sublist(sentContents.length - 5)
          : sentContents;
      sentText =
          '\n【本次已发送内容（禁止重复或近似复用）】:\n${recentSent.map((e) => '- $e').join('\n')}\n';
    }

    final step = currentStep ?? 1;
    final total = maxSteps ?? 15;
    final remaining = total - step + 1;

    // 5. User Message with Current State
    final userContent = '''
【用户最终目标】: $userGoal
【当前步骤进度】: $step / $total（剩余约 $remaining 步）

【已执行历史步骤】:
$historyText

【最近执行结果】:
$recentText
$extractedText$sentText
【当前网页状态】:
- URL: $currentUrl
- 标题: $pageTitle

$currentDomTree

请先根据【最近执行结果】和当前页面判断上一步是否生效，再决定下一步。
如果上一步显示“页面没有变化”“操作未生效”或“元素不存在”，严禁原样重复，必须换一种做法。
如果【本次已发送内容】里已经有相似句子，必须换一种表达，不要复用。
如果目标已达成，输出 finish；如果还需要继续，只输出一个原子动作的 JSON。
''';

    messages.add({
      'role': 'user',
      'content': userContent,
    });

    return messages;
  }
}
