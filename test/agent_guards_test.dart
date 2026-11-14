import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/guards.dart';

ToolResultSummary ok({bool mutates = true, bool? pageReacted}) =>
    ToolResultSummary.of(true, mutates, pageReacted: pageReacted);

ToolResultSummary failed() => ToolResultSummary.of(false, true);

void main() {
  group('repeat guard', () {
    test('the third identical action stops the run', () {
      final guards = Guards();
      expect(guards.before('click', {'ref': 'a1'}), isNull);
      guards.record('click', {'ref': 'a1'}, ok(pageReacted: true));
      expect(guards.before('click', {'ref': 'a1'}), isNull);
      guards.record('click', {'ref': 'a1'}, ok(pageReacted: true));

      final stop = guards.before('click', {'ref': 'a1'});
      expect(stop, isNotNull);
      expect(stop!.reason, contains('重复'));
    });

    test('a different target is a different action', () {
      final guards = Guards();
      for (final ref in ['a1', 'a2', 'a3', 'a1']) {
        expect(guards.before('click', {'ref': ref}), isNull);
        guards.record('click', {'ref': ref}, ok(pageReacted: true));
      }
    });

    test('reading again never trips it: re-observing is how an agent recovers', () {
      final guards = Guards();
      for (var i = 0; i < 10; i++) {
        expect(guards.before('snapshot', const {}), isNull);
        guards.record('snapshot', const {}, ok(mutates: false));
        expect(guards.before('find', {'query': '登录'}), isNull);
        guards.record('find', {'query': '登录'}, ok(mutates: false));
      }
    });

    test('five consecutive failures stop the run', () {
      final guards = Guards();
      for (var i = 0; i < 5; i++) {
        expect(guards.before('click', {'ref': 'a$i'}), isNull);
        guards.record('click', {'ref': 'a$i'}, failed());
      }
      final stop = guards.before('click', {'ref': 'a9'});
      expect(stop, isNotNull);
      expect(stop!.reason, contains('连续错误'));
    });

    test('a success clears the error streak', () {
      final guards = Guards();
      for (var i = 0; i < 4; i++) {
        guards.record('click', {'ref': 'a$i'}, failed());
      }
      guards.record('click', {'ref': 'b1'}, ok(pageReacted: true));
      expect(guards.before('click', {'ref': 'b2'}), isNull);
      expect(guards.state.errors, 0);
    });
  });

  group('no-effect guard', () {
    test('a dead button earns a nudge, then stops the run', () {
      final guards = Guards();
      // Different targets, so the repeat guard stays out of the way.
      expect(guards.record('click', {'ref': 'a1'}, ok(pageReacted: false)), isNull);
      final nudge = guards.record('click', {'ref': 'a2'}, ok(pageReacted: false));
      expect(nudge, isNotNull);
      expect(nudge!.text, contains('没有变化'));

      final stronger = guards.record('click', {'ref': 'a3'}, ok(pageReacted: false));
      expect(stronger, isNotNull);
      expect(stronger!.text, contains('done'));
      expect(guards.noEffectExhausted, isTrue);
    });

    test('a call that changed nothing but is not a write is not counted', () {
      final guards = Guards();
      expect(guards.record('snapshot', const {}, ok(mutates: false)), isNull);
      expect(guards.state.noEffect, 0);
    });

    test('a successful write resets the counter', () {
      final guards = Guards();
      guards.record('click', {'ref': 'a1'}, ok(pageReacted: false));
      guards.record('click', {'ref': 'a2'}, ok(pageReacted: true));
      expect(guards.state.noEffect, 0);
    });
  });

  group('signature', () {
    test('the same call always signs the same', () {
      expect(
        Guards.signature('type', {'ref': 'a1', 'text': '你好', 'submit': true}),
        Guards.signature('type', {'submit': true, 'text': '你好', 'ref': 'a1'}),
      );
    });

    test('different text is a different action', () {
      expect(
        Guards.signature('type', {'ref': 'a1', 'text': '第一句'}),
        isNot(Guards.signature('type', {'ref': 'a1', 'text': '第二句'})),
      );
    });
  });

  group('resumable state', () {
    test('a resumed run keeps counting where it left off', () {
      final failing = Guards();
      failing.record('click', {'ref': 'a1'}, failed());
      failing.record('click', {'ref': 'a2'}, failed());
      final resumedErrors = Guards(state: GuardState.fromJson(failing.state.toJson()));
      expect(resumedErrors.state.errors, 2);
      expect(resumedErrors.state.recent, hasLength(2));

      final dead = Guards();
      dead.record('click', {'ref': 'a1'}, ok(pageReacted: false));
      final resumedDead = Guards(state: GuardState.fromJson(dead.state.toJson()));
      expect(resumedDead.state.noEffect, 1);
    });
  });
}
