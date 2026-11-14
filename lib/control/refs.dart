import 'protocol/errors.dart';

/// One element the caller was shown, and the handle to reach it again.
class RefRecord {
  const RefRecord({
    required this.ref,
    required this.sessionId,
    required this.backendNodeId,
    required this.role,
    required this.name,
    required this.generation,
    this.disabled = false,
    this.editable = false,
  });

  final String ref;
  final String? sessionId;
  final int backendNodeId;
  final String role;
  final String name;

  /// Which document this ref was seen in.
  final int generation;

  /// Disabled when the outline was taken; the layer refuses to dispatch.
  final bool disabled;

  /// Whether the node can take text, decided from its role.
  final bool editable;

  String get label => name.isEmpty ? role : '$role "$name"';
}

/// The refs the caller was shown, and nothing else.
///
/// A ref is valid only for the document it was seen in and only because it was
/// shown. Any other ref fails with a typed error instead of resolving to
/// "whatever is there now": after a re-render, the same ref may point at a
/// different node, and acting on it silently would be the worst outcome.
class RefRegistry {
  final Map<String, RefRecord> _shown = {};
  final Map<String, String> _byNode = {};
  final Map<String, int> _history = {};
  int _generation = 0;
  int _next = 1;

  int get generation => _generation;

  int get length => _shown.length;

  Iterable<RefRecord> get records => _shown.values;

  /// Called on every navigation: every earlier ref stops being valid.
  void beginDocument() {
    _generation++;
    _shown.clear();
    _byNode.clear();
  }

  /// Reuses the ref for a node seen twice in one document, so a diff stays
  /// readable and a caller holding the old ref keeps working.
  String register({
    required String? sessionId,
    required int backendNodeId,
    required String role,
    required String name,
    bool disabled = false,
    bool editable = false,
  }) {
    final key = '${sessionId ?? 'main'}:$backendNodeId';
    final existing = _byNode[key];
    if (existing != null) {
      final record = _shown[existing];
      if (record != null && record.generation == _generation) {
        // The same node seen again refreshes what is known about it: a button
        // that was disabled can become enabled while its ref stays the same.
        _shown[existing] = RefRecord(
          ref: record.ref,
          sessionId: record.sessionId,
          backendNodeId: record.backendNodeId,
          role: role,
          name: name,
          generation: record.generation,
          disabled: disabled,
          editable: editable,
        );
        return existing;
      }
    }
    final ref = 'a${_next++}';
    _shown[ref] = RefRecord(
      ref: ref,
      sessionId: sessionId,
      backendNodeId: backendNodeId,
      role: role,
      name: name,
      generation: _generation,
      disabled: disabled,
      editable: editable,
    );
    _byNode[key] = ref;
    _history[ref] = _generation;
    return ref;
  }

  /// Resolves [ref], or fails closed.
  RefRecord lookup(String ref) {
    final record = _shown[ref];
    if (record != null && record.generation == _generation) return record;
    final seenIn = _history[ref];
    if (seenIn != null) {
      throw ControlException(
        ControlErrorCode.staleRef,
        '元素 [$ref] 来自页面变化之前，已失效',
        hint: '重新取一次页面快照，用新的 ref 操作',
        details: {'ref': ref, 'seenInGeneration': seenIn, 'now': _generation},
      );
    }
    throw ControlException(
      ControlErrorCode.unknownRef,
      '元素 [$ref] 从未被展示过',
      hint: '只能操作快照里出现过的 ref；先取一次页面快照',
      details: {'ref': ref},
    );
  }

  void clear() {
    _shown.clear();
    _byNode.clear();
    _history.clear();
    _generation = 0;
    _next = 1;
  }
}
