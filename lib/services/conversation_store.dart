import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/agent_conversation.dart';

/// Conversations live in one JSON file, newest first.
///
/// Why a file and not SharedPreferences: a conversation is a document, not a
/// preference. It is read and written whole, it can be tens of kilobytes, and
/// SharedPreferences on Android rewrites its entire XML on every commit — the
/// cost of one new turn would be paid by every other setting too.
///
/// The write is temp-file-then-rename so a kill mid-write cannot leave a
/// half-parsed history behind: worst case the last turn is lost, never all of
/// them.
class ConversationStore {
  ConversationStore._(this._file, this._conversations);

  static const int maxConversations = 50;
  static const int maxTurnsPerConversation = 40;
  static const int maxStepsPerTurn = 80;

  /// Null in a memory-only store: the panel's widget tests must not touch the
  /// disk, because `testWidgets` runs in a zone where real I/O never completes.
  final File? _file;
  final List<AgentConversation> _conversations;

  /// A write is running; another is owed because the store changed under it.
  bool _dirty = false;
  Future<void>? _pendingWrite;

  /// Newest first: what the list shows, in the order it shows them.
  List<AgentConversation> get conversations =>
      List.unmodifiable(_conversations);

  AgentConversation? byId(String? id) {
    if (id == null) return null;
    for (final item in _conversations) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Opens the store. [directory] is a test seam; the app passes nothing and
  /// gets the platform's application-support directory.
  /// A store that never writes. For tests and for the one case where the app
  /// has no writable directory: the session still works, it just forgets.
  factory ConversationStore.inMemory() =>
      ConversationStore._(null, <AgentConversation>[]);

  static Future<ConversationStore> open({Directory? directory}) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}conversations.json');
    final list = <AgentConversation>[];
    // A turn still marked running is one no process is running any more: the
    // file is only ever read at start-up. Say so once, here, rather than
    // leaving a row that looks busy forever.
    var migrated = false;
    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final conversation =
                  AgentConversation.fromJson(item.cast<String, Object?>());
              // An entry with no turns and no title is debris from an older
              // shape; it would show up in the list as a nameless row.
              if (conversation.id.isEmpty) continue;
              if (conversation.turns.isEmpty && conversation.title.isEmpty) {
                continue;
              }
              // A conversation cannot be longer than a run allows: a single
              // corrupted entry must not make the file unreadable.
              if (conversation.turns.length > maxTurnsPerConversation) {
                conversation.turns.removeRange(
                  0,
                  conversation.turns.length - maxTurnsPerConversation,
                );
              }
              for (var i = 0; i < conversation.turns.length; i++) {
                if (!conversation.turns[i].isRunning) continue;
                conversation.turns[i] =
                    conversation.turns[i].copyWith(status: 'interrupted');
                migrated = true;
              }
              list.add(conversation);
            }
          }
        }
      }
    } catch (_) {
      // A corrupt file is not a reason to lose the app: start empty. The next
      // save overwrites it, which is the only recovery that matters here.
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final store = ConversationStore._(file, list);
    if (migrated) await store.save();
    return store;
  }

  /// A conversation that exists in memory and on disk only once it has a turn.
  AgentConversation create({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    final conversation = AgentConversation(
      id: 'c${stamp.microsecondsSinceEpoch}',
      createdAt: stamp,
      updatedAt: stamp,
    );
    _conversations.insert(0, conversation);
    return conversation;
  }

  /// Appends one finished turn and writes the file.
  Future<void> appendTurn(String conversationId, AgentTurn turn) async {
    final conversation = byId(conversationId);
    if (conversation == null) return;
    if (turn.steps.length > maxStepsPerTurn) {
      turn = AgentTurn(
        id: turn.id,
        message: turn.message,
        startedAt: turn.startedAt,
        endedAt: turn.endedAt,
        status: turn.status,
        result: turn.result,
        stopReason: turn.stopReason,
        // Keep the tail: the end of a run explains it.
        steps: turn.steps.sublist(turn.steps.length - maxStepsPerTurn),
        attachmentNames: turn.attachmentNames,
        promptTokens: turn.promptTokens,
        completionTokens: turn.completionTokens,
        targetUrl: turn.targetUrl,
      );
    }
    conversation.append(turn);
    _pruneTurns(conversation);
    // Newest first, so the list order matches "most recent".
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
  }

  /// Starts a turn and writes it now, before the run touches the page.
  ///
  /// The old shape wrote a turn only when the run ended, so a killed app erased
  /// the work: reopening the panel showed a conversation as if the user had
  /// never asked. This row is the floor [journalStep] fills in and
  /// [completeTurn] closes.
  Future<AgentTurn> beginTurn(
    String conversationId, {
    required String message,
    required DateTime startedAt,
    String? targetUrl,
    List<String> attachmentNames = const [],
  }) async {
    final turn = AgentTurn(
      id: 't${startedAt.microsecondsSinceEpoch}',
      message: message,
      startedAt: startedAt,
      endedAt: startedAt,
      status: 'running',
      targetUrl: targetUrl,
      attachmentNames: attachmentNames,
      // Grown one step at a time by [journalStep].
      steps: <AgentTurnStep>[],
    );
    final conversation = byId(conversationId);
    if (conversation == null) return turn;
    conversation.append(turn);
    _pruneTurns(conversation);
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
    return turn;
  }

  /// Adds a step to a running turn, in the order the model asked for it.
  ///
  /// Appending the intent *before* the call is dispatched is the whole point:
  /// the last line on this list is always something that really went out.
  Future<void> journalStep(
    String conversationId,
    String turnId,
    AgentTurnStep step,
  ) async {
    final turn = _turnIn(conversationId, turnId);
    if (turn == null) return;
    if (turn.steps.length >= maxStepsPerTurn) return;
    turn.steps.add(step);
    await save();
  }

  /// Lands the outcome on the row its intent opened.
  ///
  /// A call that never announced itself still gets a row: a refusal or a guard
  /// is part of what happened, and dropping it would hide the reason.
  Future<void> settleStep(
    String conversationId,
    String turnId, {
    required String callId,
    required String status,
    String? detail,
  }) async {
    final turn = _turnIn(conversationId, turnId);
    if (turn == null) return;
    // Newest first, and preferably one that is still waiting: a model that
    // reuses a call id (the fake one in the tests does, and some providers have
    // been seen to) must not settle a row that was already closed.
    var index = -1;
    for (var i = turn.steps.length - 1; i >= 0; i--) {
      if (turn.steps[i].callId == callId && turn.steps[i].isPending) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      for (var i = turn.steps.length - 1; i >= 0; i--) {
        if (turn.steps[i].callId == callId) {
          index = i;
          break;
        }
      }
    }
    if (index < 0) return;
    turn.steps[index] = turn.steps[index].copyWith(status: status, detail: detail);
    await save();
  }

  /// Closes a running turn with what the run ended up being.
  ///
  /// The steps stay exactly as the journal wrote them: the answer and the steps
  /// cannot disagree, because neither was reconstructed after the fact.
  Future<void> completeTurn(
    String conversationId,
    String turnId, {
    required String status,
    String? result,
    String? stopReason,
    int promptTokens = 0,
    int completionTokens = 0,
    String? targetUrl,
  }) async {
    final turn = _turnIn(conversationId, turnId);
    if (turn == null) return;
    final conversation = byId(conversationId);
    final endedAt = DateTime.now();
    final closed = turn.copyWith(
      status: status,
      result: () => result,
      stopReason: () => stopReason,
      endedAt: endedAt,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      targetUrl: targetUrl,
    );
    final index = conversation!.turns.indexWhere((item) => item.id == turnId);
    if (index >= 0) conversation.turns[index] = closed;
    conversation.updatedAt = endedAt;
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
  }

  /// Keeps a conversation within its turn budget without losing the boundary
  /// of what was compacted: dropping old turns moves that index with it.
  void _pruneTurns(AgentConversation conversation) {
    if (conversation.turns.length <= maxTurnsPerConversation) return;
    final dropped = conversation.turns.length - maxTurnsPerConversation;
    conversation.turns.removeRange(0, dropped);
    conversation.compactedTurns = (conversation.compactedTurns - dropped)
        .clamp(0, conversation.turns.length);
  }

  AgentTurn? _turnIn(String conversationId, String turnId) {
    final conversation = byId(conversationId);
    if (conversation == null) return null;
    for (final turn in conversation.turns) {
      if (turn.id == turnId) return turn;
    }
    return null;
  }

  /// Records a `/compact` or Auto-Compact boundary and persists the summary.
  Future<void> applyCompaction(
    String conversationId, {
    required String summary,
    AgentTurn? recordTurn,
  }) async {
    final conversation = byId(conversationId);
    if (conversation == null) return;
    conversation.compactedSummary = summary.trim();
    if (recordTurn != null) {
      conversation.append(recordTurn);
      if (conversation.turns.length > maxTurnsPerConversation) {
        final dropped = conversation.turns.length - maxTurnsPerConversation;
        conversation.turns.removeRange(0, dropped);
      }
    }
    conversation.compactedTurns = conversation.turns.length;
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
  }

  Future<void> rename(String conversationId, String title) async {
    final conversation = byId(conversationId);
    if (conversation == null) return;
    conversation.title = title.trim();
    await save();
  }

  Future<void> delete(String conversationId) async {
    _conversations.removeWhere((item) => item.id == conversationId);
    await save();
  }

  /// Drops conversations that never got a message: opening the panel and
  /// closing it should not leave a row behind.
  Future<void> pruneEmpty() async {
    final before = _conversations.length;
    _conversations.removeWhere((item) => item.turns.isEmpty);
    if (_conversations.length != before) await save();
  }

  /// Marks the store dirty and writes it out.
  ///
  /// Every write is the whole file, so calls that arrive while one is running
  /// are coalesced into a single extra pass afterwards. A finishing run, a
  /// rename and a prune in the same second used to be three full encodes and
  /// three temp-file renames; the future returned by each caller still
  /// completes only once the change it asked for is on disk.
  Future<void> save() {
    if (_conversations.length > maxConversations) {
      _conversations.removeRange(maxConversations, _conversations.length);
    }
    _dirty = true;
    return _pendingWrite ??= _flush();
  }

  Future<void> _flush() async {
    try {
      while (true) {
        _dirty = false;
        await _writeToDisk();
        // A save that arrived mid-write marked the store dirty again; one more
        // pass picks it up. Nothing can slip in between this check and the next
        // pass, because the two run without an await.
        if (!_dirty) break;
      }
    } finally {
      // Cleared even if the write threw: a stuck pending future would make
      // every later save a no-op, which is a worse failure than a lost write.
      _pendingWrite = null;
    }
  }

  Future<void> _writeToDisk() async {
    final file = _file;
    if (file == null) return;
    final payload = jsonEncode([
      for (final conversation in _conversations) conversation.toJson(),
    ]);
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // History is best-effort: a full disk must not break the run in front of
      // the user.
    }
  }
}
