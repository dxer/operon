import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/perception/diff.dart';

void main() {
  group('diffLines', () {
    test('reports what appeared and what went away', () {
      final changes = diffLines(
        ['[a1] button "登录"', '[a2] link "帮助"'],
        ['[a1] button "登录"', '[a3] textbox "用户名"'],
      );

      expect(changes, contains('- [a2] link "帮助"'));
      expect(changes, contains('+ [a3] textbox "用户名"'));
      expect(changes, isNot(contains('- [a1] button "登录"')));
    });

    test('a scroll that only adds rows is all additions', () {
      final changes = diffLines(
        ['[a1] button "1"'],
        ['[a1] button "1"', '[a2] button "2"', '[a3] button "3"'],
      );

      expect(changes.where((line) => line.startsWith('-')), isEmpty);
      expect(changes.where((line) => line.startsWith('+')), hasLength(2));
    });

    test('nothing changed means an empty diff', () {
      expect(diffLines(const [], const []), isEmpty);
      expect(diffLines(['a', 'b'], ['a', 'b']), isEmpty);
    });

    test('the result is capped, so one page swap cannot flood a prompt', () {
      final before = List.generate(50, (index) => 'old $index');
      final after = List.generate(50, (index) => 'new $index');
      final changes = diffLines(before, after, max: 6);
      expect(changes, hasLength(6));
    });

    test('a very large pair falls back to set diff and still answers', () {
      final before = List.generate(600, (index) => 'row $index');
      final after = List.generate(600, (index) => 'row ${index + 600}');
      final changes = diffLines(before, after, max: 10);
      expect(changes, hasLength(10));
    });
  });
}
