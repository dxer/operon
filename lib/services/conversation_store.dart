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

  /// Newest first: what the list shows, in the order it shows it.
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
    return ConversationStore._(file, list);
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
    if (conversation.turns.length > maxTurnsPerConversation) {
      final dropped = conversation.turns.length - maxTurnsPerConversation;
      conversation.turns.removeRange(0, dropped);
      conversation.compactedTurns =
          (conversation.compactedTurns - dropped).clamp(0, conversation.turns.length);
    }
    // Newest first, so the list order matches "most recent".
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
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

  Future<void> save() async {
    if (_conversations.length > maxConversations) {
      _conversations.removeRange(maxConversations, _conversations.length);
    }
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
