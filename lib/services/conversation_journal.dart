import 'dart:async';

import '../agent/ports.dart';
import '../models/agent_conversation.dart';
import 'conversation_store.dart';

/// The conversation store as a run's journal.
///
/// The two writes have different weights on purpose. [intent] is awaited by the
/// loop before the call is dispatched, so the row is on disk before the page is
/// touched; [result] is fire-and-forget, because a run must not wait on history.
/// A step whose result never arrives keeps its `started` status, which is
/// exactly what a killed run should look like when it is read back.
class ConversationJournal implements RunJournal {
  ConversationJournal(this._store, this._conversationId, this._turnId);

  final ConversationStore _store;
  final String _conversationId;
  final String _turnId;

  @override
  Future<void> intent({
    required String callId,
    required String tool,
    required String summary,
  }) =>
      _store.journalStep(
        _conversationId,
        _turnId,
        AgentTurnStep(
          tool: tool,
          summary: summary,
          status: AgentTurnStep.stepStarted,
          callId: callId,
        ),
      );

  @override
  void result({
    required String callId,
    required String tool,
    required String summary,
    required bool ok,
    String? detail,
  }) {
    unawaited(_store.settleStep(
      _conversationId,
      _turnId,
      callId: callId,
      status: ok ? AgentTurnStep.stepOk : AgentTurnStep.stepFailed,
      detail: detail,
    ));
  }
}
