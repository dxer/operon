import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/perception/find.dart';
import 'package:operon/control/protocol/results.dart';

OutlineLine line(String ref, String role, String name, {String? value}) => OutlineLine(
      ref: ref,
      role: role,
      name: name,
      value: value,
    );

void main() {
  final entries = [
    line('a1', 'button', '登录'),
    line('a2', 'button', '退出登录'),
    line('a3', 'link', '忘记密码'),
    line('a4', 'textbox', '用户名', value: 'bob'),
    line('a5', 'button', '登录', value: null),
  ];

  group('matchEntries', () {
    test('matches a name substring, ignoring case', () {
      final matches = matchEntries(entries, query: '登录');
      expect(matches.map((entry) => entry.ref), ['a1', 'a2', 'a5']);
    });

    test('narrows by role', () {
      final matches = matchEntries(entries, query: '登录', role: 'link');
      expect(matches, isEmpty);
      final links = matchEntries(entries, role: 'button');
      expect(links.map((entry) => entry.ref), ['a1', 'a2', 'a5']);
    });

    test('exact mode is what disambiguates two identical names', () {
      final loose = matchEntries(entries, query: '退出登录');
      expect(loose.map((entry) => entry.ref), ['a2']);
      final exact = matchEntries(entries, query: '登录', exact: true);
      expect(exact.map((entry) => entry.ref), ['a1', 'a5']);
    });

    test('the value is searchable too, so a filled field is findable', () {
      final matches = matchEntries(entries, query: 'bob');
      expect(matches.single.ref, 'a4');
    });

    test('an empty query with a role lists that role', () {
      expect(matchEntries(entries, role: 'textbox').single.ref, 'a4');
    });

    test('the limit is honoured, so a huge page cannot flood a prompt', () {
      final many = List.generate(50, (index) => line('a$index', 'button', '按钮'));
      expect(matchEntries(many, query: '按钮', limit: 5), hasLength(5));
    });

    test('no match returns nothing rather than a nearest guess', () {
      expect(matchEntries(entries, query: '删除账户'), isEmpty);
    });
  });
}
