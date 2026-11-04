import '../models/quick_command.dart';
import '../models/skill.dart';

/// Converts legacy quick commands into instruction skills.
///
/// The prompt and inputs are preserved verbatim so an upgrade never changes
/// what an existing command does.
class SkillMigration {
  SkillMigration._();

  static Skill fromQuickCommand(
    QuickCommand command, {
    SkillOrigin origin = SkillOrigin.migrated,
  }) {
    final maxItems = command.policy.isBatch && command.policy.maxItems > 0
        ? command.policy.maxItems
        : 1;
    return Skill(
      id: command.id,
      name: command.title,
      description: command.description,
      kind: SkillKind.instruction,
      origin: origin,
      version: 1,
      inputs: command.inputs.map(_input).toList(),
      instructions: command.promptTemplate,
      steps: const [],
      output: const {},
      policy: SkillPolicy(
        maxSteps: command.policy.maxSteps ?? 30,
        maxSideEffects: maxItems,
        maxItems: maxItems,
        maxDurationMs: 300000,
        pacingMs: command.policy.pacingMs,
        uniqueTarget: command.policy.uniqueTarget,
        uniqueContent: command.policy.uniqueContent,
        confirmWrites: command.policy.confirmBeforeSideEffect,
        confirmDestructive: true,
        stopOn: command.policy.stopOn,
        hostScope: SkillHostScope.any,
        allowedHosts: const [],
      ),
      builtin: command.builtin,
      sortOrder: command.sortOrder,
      updatedAt: DateTime.now(),
    );
  }

  static SkillInput _input(QuickCommandInput input) {
    return SkillInput(
      key: input.key,
      label: input.label,
      type: _type(input.type),
      defaultValue: input.defaultValue,
      options: input.options,
      required: input.required,
    );
  }

  static SkillInputType _type(QuickCommandInputType type) {
    switch (type) {
      case QuickCommandInputType.text:
        return SkillInputType.text;
      case QuickCommandInputType.multiline:
        return SkillInputType.multiline;
      case QuickCommandInputType.number:
        return SkillInputType.number;
      case QuickCommandInputType.select:
        return SkillInputType.select;
      case QuickCommandInputType.toggle:
        return SkillInputType.toggle;
    }
  }
}
