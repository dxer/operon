import '../config/tool_catalog.dart';
import '../models/skill.dart';
import '../models/tool_descriptor.dart';
import 'webview_controller_wrapper.dart';

class SkillPrecheckItem {
  final String stepId;
  final String stepName;
  final String tool;
  final String param;
  final bool found;
  final bool ambiguous;
  final int count;
  final String detail;

  const SkillPrecheckItem({
    required this.stepId,
    required this.stepName,
    required this.tool,
    required this.param,
    required this.found,
    required this.ambiguous,
    required this.count,
    required this.detail,
  });
}

/// Resolves read-only locators without dispatching any action.
///
/// This is the safety net for AI-authored drafts: static validation cannot
/// know whether a selector still matches the live page.
class SkillPrecheckService {
  Future<List<SkillPrecheckItem>> check(
    SkillDraft draft,
    WebViewControllerWrapper webView,
  ) async {
    final items = <SkillPrecheckItem>[];
    for (final step in draft.steps) {
      final tool = ToolCatalog.find(step.tool);
      if (tool == null) continue;
      for (final param in tool.params) {
        if (param.type != ToolParamType.locator) continue;
        final value = step.params[param.key];
        if (value is! Map) continue;
        final result = await webView.resolveLocator(
          Map<String, dynamic>.from(value),
        );
        final found = result['found'] == true;
        final ambiguous = result['ambiguous'] == true;
        items.add(SkillPrecheckItem(
          stepId: step.id,
          stepName: step.name,
          tool: tool.name,
          param: param.key,
          found: found,
          ambiguous: ambiguous,
          count: (result['count'] as num?)?.toInt() ?? 0,
          detail: found
              ? '找到：${result['label'] ?? result['text'] ?? ''}'
              : (ambiguous ? '有多个匹配，需要更精确的定位器' : '没有找到目标元素'),
        ));
      }
    }
    return items;
  }
}
