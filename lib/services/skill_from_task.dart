import '../models/macro_workflow.dart';
import '../models/skill.dart';
import 'skill_from_macro.dart';

/// Turns a finished agent task into an editable skill draft.
///
/// Concrete recorded actions are preferred: they become a deterministic flow
/// skill with zero model cost on replay. Tasks that only read or extract data
/// have no actions to record, so the goal itself becomes an instruction skill.
/// Either way the user gets something they can edit before saving.
class SkillFromTask {
  SkillFromTask._();

  static SkillDraft draftFor({
    required String goal,
    required List<MacroStep> steps,
    String summary = '',
    String url = '',
    String? name,
  }) {
    final trimmedGoal = goal.trim();
    final trimmedSummary = summary.trim();
    final title = _titleOf(name, trimmedGoal);

    if (steps.isNotEmpty) {
      final flow = SkillFromMacro.fromMacro(MacroWorkflow(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        initialUrl: url,
        createdAt: DateTime.now(),
        steps: steps,
      ));
      if (flow != null) {
        return flow.copyWith(
          name: title,
          description: flow.description.isNotEmpty
              ? flow.description
              : trimmedSummary,
        );
      }
    }

    return SkillDraft(
      name: title,
      description: trimmedSummary,
      kind: SkillKind.instruction,
      instructions: trimmedGoal,
      policy: const SkillPolicy(),
    );
  }

  static String _titleOf(String? name, String goal) {
    final explicit = name?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    if (goal.isEmpty) return '新技能';
    return goal.length <= 20 ? goal : '${goal.substring(0, 20)}…';
  }
}
