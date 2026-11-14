import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/protocol/errors.dart';
import 'package:operon/control/refs.dart';

void main() {
  group('RefRegistry', () {
    test('a ref is only good for the document it was seen in', () {
      final refs = RefRegistry();
      final ref = refs.register(
        sessionId: null,
        backendNodeId: 12,
        role: 'button',
        name: '登录',
      );
      expect(ref, 'a1');
      expect(refs.lookup(ref).name, '登录');

      refs.beginDocument();

      expect(
        () => refs.lookup(ref),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.staleRef,
        )),
      );
    });

    test('a ref that was never shown is not resolved by guessing', () {
      final refs = RefRegistry();
      expect(
        () => refs.lookup('a99'),
        throwsA(isA<ControlException>().having(
          (error) => error.code,
          'code',
          ControlErrorCode.unknownRef,
        )),
      );
    });

    test('the same node seen twice in one document keeps its ref', () {
      final refs = RefRegistry();
      final first = refs.register(
        sessionId: null,
        backendNodeId: 7,
        role: 'link',
        name: '更多',
      );
      final second = refs.register(
        sessionId: null,
        backendNodeId: 7,
        role: 'link',
        name: '更多',
      );
      expect(second, first);
      expect(refs.length, 1);
    });

    test('a re-rendered node gets a new ref, so the old one cannot act', () {
      final refs = RefRegistry();
      final old = refs.register(
        sessionId: null,
        backendNodeId: 7,
        role: 'button',
        name: '关注',
      );
      // Same control, new DOM node after a re-render.
      final fresh = refs.register(
        sessionId: null,
        backendNodeId: 44,
        role: 'button',
        name: '关注',
      );
      expect(fresh, isNot(old));
      expect(refs.length, 2);
    });

    test('frames are kept apart even with the same node id', () {
      final refs = RefRegistry();
      final main = refs.register(
        sessionId: null,
        backendNodeId: 5,
        role: 'button',
        name: 'A',
      );
      final child = refs.register(
        sessionId: 'S1',
        backendNodeId: 5,
        role: 'button',
        name: 'A',
      );
      expect(main, isNot(child));
      expect(refs.lookup(child).sessionId, 'S1');
    });

    test('numbering keeps going across documents, so an old ref never matches a new node', () {
      final refs = RefRegistry();
      final stale = refs.register(
          sessionId: null, backendNodeId: 1, role: 'button', name: 'A');
      refs.beginDocument();
      final next = refs.register(
        sessionId: null,
        backendNodeId: 2,
        role: 'button',
        name: 'B',
      );
      // A reused ref would let a caller holding the old one act on a different
      // node without noticing.
      expect(next, isNot(stale));
      expect(next, 'a2');
      expect(refs.length, 1);
      expect(refs.generation, 1);
    });
  });
}
