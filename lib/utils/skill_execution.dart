import '../config/tool_catalog.dart';
import '../models/skill.dart';
import 'skill_template.dart';

/// Policy and prompt helpers shared by every skill entry point.
///
/// The agent panel, the skills page and the flow runner must agree on what a
/// skill run means. Keeping the rules here avoids each entry point drifting.

/// Returns the policy to use for one concrete run.
///
/// `count` / `limit` are the user's explicit item budget; the policy's
/// `maxItems` is the safety ceiling. The built-in batch skills ship with a
/// looser ceiling than their default count (replies: 5 vs 3), so a model that
/// ignored the prompt could keep processing after the requested number. The
/// smaller of the two always wins.
SkillPolicy skillPolicyForValues(Skill skill, Map<String, String> values) {
  final policy = skill.policy;
  final limit = _firstLimit(values);
  // `pages` is a navigation budget, not an item budget.
  if (limit == null || limit.key == 'pages') return policy;
  if (limit.value >= policy.maxItems) return policy;
  return policy.copyWith(maxItems: limit.value);
}

/// Whether running [skill] needs a configured model.
///
/// Read-only flow skills (export, link collection) used to be blocked by the
/// "configure an API key" check even though they never call a model.
bool skillNeedsModel(Skill skill) {
  if (skill.isInstruction) return true;
  for (final step in skill.steps) {
    if (!step.enabled) continue;
    final tool = ToolCatalog.find(step.tool);
    if (tool?.usesLlm == true) return true;
    if (step.onError.action == StepFailureAction.fallbackAgent) return true;
  }
  return false;
}

/// Renders an instruction skill and appends the user's hard batch limit.
///
/// The templates already say "最多 N 条", but a loose sentence in a long prompt
/// is easy for the model to skim. An explicit execution constraint at the end
/// keeps a batch run from quietly processing extra items.
String renderSkillGoal(Skill skill, Map<String, String> values) {
  final goal = SkillTemplate.renderString(
    skill.instructions,
    {'inputs': values},
    strict: false,
  ).trim();
  final limit = _firstLimit(values);
  if (goal.isEmpty || limit == null) return goal;
  final unit = limit.key == 'pages' ? '页' : '条';
  return '$goal\n\n【执行约束】最多处理 ${limit.value}$unit，达到上限后立即 finish；'
      '不要继续滚动、翻页或寻找新的目标。';
}

({String key, int value})? _firstLimit(Map<String, String> values) {
  for (final key in const ['count', 'limit', 'pages']) {
    final parsed = int.tryParse((values[key] ?? '').trim());
    if (parsed != null && parsed > 0) return (key: key, value: parsed);
  }
  return null;
}
