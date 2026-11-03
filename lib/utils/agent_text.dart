import '../models/agent_action.dart';

/// One-line, human readable description of an agent action.
///
/// A `type` action deliberately hides the typed text: the confirmation card
/// shows the exact payload in its own block, so repeating it here would only
/// add noise (and could leak a secret into a status strip).
String agentActionLabel(AgentAction? action) {
  if (action == null) return '';
  if (action.action == ActionType.type) {
    return '在 [${action.elementId}] 输入内容';
  }
  return action.description;
}
