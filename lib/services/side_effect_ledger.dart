/// At-most-once protection for non-idempotent actions (reply, post, pay,
/// delete, submit). A successful dispatch is not proof that the side effect
/// happened, so an unverified attempt blocks retries instead of risking a
/// duplicate post/payment.
class SideEffectRecord {
  final DateTime at;
  final bool verified;
  final bool unverified;

  const SideEffectRecord({
    required this.at,
    required this.verified,
    required this.unverified,
  });
}

class SideEffectLedger {
  static const Duration _verifiedCooldown = Duration(seconds: 3);
  static const Duration _pendingTimeout = Duration(seconds: 12);
  static const Duration _unverifiedBlock = Duration(seconds: 30);

  final Map<String, SideEffectRecord> _records = {};

  bool canAttempt(String key, {DateTime? now}) {
    final record = _records[key];
    if (record == null) return true;
    final time = now ?? DateTime.now();
    final age = time.difference(record.at);

    if (record.unverified) {
      return age > _unverifiedBlock;
    }
    if (!record.verified) {
      // Dispatch happened but the next observation has not resolved yet.
      return age > _pendingTimeout;
    }
    // The same target was just confirmed; avoid accidental double taps.
    return age > _verifiedCooldown;
  }

  bool isUnverified(String key) => _records[key]?.unverified == true;

  void markPending(String key, {DateTime? now}) {
    _records[key] = SideEffectRecord(
      at: now ?? DateTime.now(),
      verified: false,
      unverified: false,
    );
  }

  void markVerified(String key, {DateTime? now}) {
    _records[key] = SideEffectRecord(
      at: now ?? DateTime.now(),
      verified: true,
      unverified: false,
    );
  }

  void markUnverified(String key, {DateTime? now}) {
    _records[key] = SideEffectRecord(
      at: now ?? DateTime.now(),
      verified: false,
      unverified: true,
    );
  }

  /// The executor failed before dispatching, so no side effect can exist.
  void clear(String key) {
    _records.remove(key);
  }

  void reset() {
    _records.clear();
  }
}
