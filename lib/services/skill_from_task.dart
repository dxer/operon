import '../models/macro_workflow.dart';
import '../models/skill.dart';
import 'skill_from_macro.dart';

/// Turns a finished agent task into an editable skill draft.
///
/// The default is an instruction skill: the goal becomes the prompt and the
/// agent resolves elements again at run time. That is the only form that
/// survives a feed re-render or a page redesign.
///
/// A recorded flow is only produced when the caller explicitly asks for it
/// *and* the recording contains a real write. Replaying "scroll down, open the
/// first item" as a skill is useless — it does the navigation but never the
/// actual task. Demo text is also replaced with an input so a saved reply
/// skill does not keep posting the same sentence.
class SkillFromTask {
  SkillFromTask._();

  /// Input key used when the recorded demonstration content becomes a field.
  static const String contentKey = 'content';

  static SkillDraft draftFor({
    required String goal,
    required List<MacroStep> steps,
    String summary = '',
    String url = '',
    String? name,
    bool preferFlow = false,
  }) {
    final trimmedGoal = goal.trim();
    final trimmedSummary = summary.trim();
    final title = _titleOf(name, trimmedGoal);

    if (preferFlow && steps.isNotEmpty) {
      final flow = SkillFromMacro.fromMacro(
        MacroWorkflow(
          id: 'task_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          initialUrl: url,
          createdAt: DateTime.now(),
          steps: steps,
        ),
      );
      // Without a write the recording is only navigation/reading; the goal
      // itself is the better skill.
      if (flow != null && _hasWrite(flow.steps)) {
        return _withContentInput(
          flow.copyWith(
            name: title,
            description: flow.description.isNotEmpty
                ? flow.description
                : trimmedSummary,
          ),
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

  /// Whether a recorded flow can stand alone as a replayable skill.
  static bool canReplayFlow(List<MacroStep> steps) {
    if (steps.isEmpty) return false;
    return steps.any((step) {
      final action = step.action.toLowerCase();
      return action == 'click' ||
          action == 'type' ||
          action == 'press_key' ||
          action == 'presskey' ||
          action == 'select' ||
          action == 'select_option';
    }) &&
        steps.any((step) => step.nonIdempotent);
  }

  static bool _hasWrite(List<SkillStep> steps) {
    return steps.any((step) => SkillFromMacro.isWrite(step.tool));
  }

  /// Replaces the literal demonstration text with `{{inputs.content}}` so the
  /// saved skill asks for content instead of reposting the same sentence.
  ///
  /// Only when there is exactly one literal text: a search term plus a reply
  /// body are different things, and collapsing both into one field would make
  /// the skill send the wrong value to one of them.
  ///
  /// Public because every path that turns a recording into a flow skill must
  /// apply it — the task-history import builds its draft through
  /// [SkillFromMacro] directly and would otherwise bake in the demo text.
  static SkillDraft withContentInput(SkillDraft draft) => _withContentInput(draft);

  static SkillDraft _withContentInput(SkillDraft draft) {
    final literals = draft.steps.where((step) {
      if (step.tool != 'page.type') return false;
      final text = step.params['text']?.toString().trim() ?? '';
      return text.isNotEmpty && !text.contains('{{');
    }).toList();
    if (literals.length != 1) return draft;

    final example =
        literals.single.params['text'].toString().trim();
    final replaced = draft.steps.map((step) {
      if (step.tool != 'page.type') return step;
      final text = step.params['text']?.toString().trim() ?? '';
      if (text.isEmpty || text.contains('{{')) return step;
      return step.copyWith(
        params: {...step.params, 'text': '{{inputs.$contentKey}}'},
      );
    }).toList();

    final inputs = [
      ...draft.inputs.where((input) => input.key != contentKey),
      SkillInput(
        key: contentKey,
        label: '内容',
        type: SkillInputType.multiline,
        required: true,
        hint: example.length <= 80 ? '示例：$example' : '运行时填写要输入的内容',
      ),
    ];
    return draft.copyWith(steps: replaced, inputs: inputs);
  }

  static String _titleOf(String? name, String goal) {
    final explicit = name?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    if (goal.isEmpty) return '新技能';
    return goal.length <= 20 ? goal : '${goal.substring(0, 20)}…';
  }
}
