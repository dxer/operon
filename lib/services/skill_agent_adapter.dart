import '../models/quick_command.dart';
import '../models/skill.dart';

/// Bridges a skill policy to the existing AgentRunner policy.
///
/// Instruction skills still run through AgentRunner, so their batch/dedupe
/// settings must keep working exactly as before.
QuickCommandPolicy skillPolicyToAgentPolicy(SkillPolicy policy) {
  final mode =
      policy.maxItems > 1 ? QuickCommandMode.batch : QuickCommandMode.single;
  return QuickCommandPolicy(
    mode: mode,
    maxItems: policy.maxItems,
    uniqueTarget: policy.uniqueTarget,
    uniqueContent: policy.uniqueContent,
    pacingMs: policy.pacingMs,
    confirmBeforeSideEffect: policy.confirmWrites,
    showPayloadInConfirmation: true,
    maxSteps: policy.maxSteps,
    stopOn: policy.stopOn,
  );
}
