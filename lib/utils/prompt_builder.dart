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
  }) {
    final messages = <Map<String, String>>[];

    // 1. System Prompt
    messages.add({
      'role': 'system',
      'content': AppConstants.agentSystemPrompt,
    });

    // 2. Build history summary (only actions taken, omitting past DOM trees)
    final historyLines = <String>[];
    for (final item in historyLogs) {
      if (item.step > 0 && !item.isError) {
        historyLines.add('- 步骤 ${item.step}: ${item.title}');
      }
    }
    final historyText = historyLines.isEmpty
        ? '（这是第一步，尚无历史操作）'
        : historyLines.join('\n');

    // 3. User Message with Current State
    final userContent = '''
【用户最终目标】: $userGoal
【当前步骤进度】: ${currentStep ?? 1} / ${maxSteps ?? 15}

【已执行历史步骤】:
$historyText

【当前网页状态】:
- URL: $currentUrl
- 标题: $pageTitle

$currentDomTree

请根据上述信息，判断当前执行进度，并严格输出下一步操作的 JSON。如果目标已达成，输出 finish。
''';

    messages.add({
      'role': 'user',
      'content': userContent,
    });

    return messages;
  }
}
