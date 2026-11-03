import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/side_effect_ledger.dart';

void main() {
  final t0 = DateTime(2024, 1, 1);

  test('pending dispatches block until the observation window ends', () {
    final ledger = SideEffectLedger()..markPending('k', now: t0);

    expect(ledger.canAttempt('k', now: t0), isFalse);
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 11))),
      isFalse,
    );
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 13))),
      isTrue,
    );
  });

  test('unverified dispatches block longer', () {
    final ledger = SideEffectLedger()..markUnverified('k', now: t0);

    expect(ledger.isUnverified('k'), isTrue);
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 29))),
      isFalse,
    );
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 31))),
      isTrue,
    );
  });

  test('verified dispatches have a short double-tap cooldown', () {
    final ledger = SideEffectLedger()..markVerified('k', now: t0);

    expect(ledger.isUnverified('k'), isFalse);
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 2))),
      isFalse,
    );
    expect(
      ledger.canAttempt('k', now: t0.add(const Duration(seconds: 4))),
      isTrue,
    );
  });

  test('clear and reset release all keys', () {
    final ledger = SideEffectLedger()
      ..markPending('a', now: t0)
      ..markUnverified('b', now: t0);

    ledger.clear('a');
    expect(ledger.canAttempt('a', now: t0), isTrue);
    expect(ledger.canAttempt('b', now: t0), isFalse);

    ledger.reset();
    expect(ledger.canAttempt('b', now: t0), isTrue);
  });
}
