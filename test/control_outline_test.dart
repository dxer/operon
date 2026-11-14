import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/perception/ax.dart';
import 'package:operon/control/perception/outline.dart';
import 'package:operon/control/refs.dart';

AxNode node(
  String id, {
  required String role,
  String? parentId,
  List<String> children = const [],
  String name = '',
  String? value,
  int? backendNodeId,
  bool ignored = false,
  Map<String, Object?> properties = const {},
  String? sessionId,
}) =>
    AxNode(
      nodeId: id,
      role: role,
      parentId: parentId,
      childIds: children,
      name: name,
      value: value,
      backendNodeId: backendNodeId,
      ignored: ignored,
      properties: properties,
      sessionId: sessionId,
    );

void main() {
  group('outline', () {
    late RefRegistry refs;

    setUp(() => refs = RefRegistry());

    test('structural wrappers collapse and controls get refs in reading order', () {
      final nodes = [
        node('1', role: 'RootWebArea', name: '示例页', children: ['2']),
        node('2', role: 'generic', parentId: '1', children: ['3', '4', '5']),
        node('3', role: 'heading', parentId: '2', name: '登录'),
        node('4', role: 'textbox', parentId: '2', name: '用户名', value: 'bob', backendNodeId: 101),
        node('5', role: 'button', parentId: '2', name: '登录', backendNodeId: 102),
      ];

      final outline = OutlineBuilder().build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com/login',
        title: '示例页',
      );

      expect(outline.entries.map((entry) => entry.role), ['textbox', 'button']);
      expect(outline.entries.first.ref, 'a1');
      expect(outline.entries.last.ref, 'a2');
      // An input takes text, a button does not: the layer refuses type on the
      // latter before anything is dispatched.
      expect(refs.lookup('a1').editable, isTrue);
      expect(refs.lookup('a2').editable, isFalse);
      expect(outline.content, contains('# 登录'));
      expect(outline.lines.first, contains('[a1] textbox "用户名" = "bob"'));
    });

    test('password-like and protected values never reach the outline', () {
      final nodes = [
        node('1', role: 'RootWebArea', name: 't', children: ['2', '3', '4']),
        node('2', role: 'textbox', parentId: '1', name: '密码', value: 'hunter2', backendNodeId: 1),
        node('3', role: 'textbox', parentId: '1', name: '验证码', value: '8891', backendNodeId: 2),
        node(
          '4',
          role: 'textbox',
          parentId: '1',
          name: 'PIN',
          value: '4321',
          backendNodeId: 3,
          properties: {'protected': true},
        ),
      ];

      final outline = OutlineBuilder().build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com',
        title: 't',
      );

      for (final entry in outline.entries) {
        expect(entry.value, '•••');
      }
      expect(outline.render(), isNot(contains('hunter2')));
      expect(outline.render(), isNot(contains('8891')));
      expect(outline.render(), isNot(contains('4321')));
    });

    test('states are printed, so a disabled control is not clicked', () {
      final nodes = [
        node('1', role: 'RootWebArea', name: 't', children: ['2', '3']),
        node(
          '2',
          role: 'button',
          parentId: '1',
          name: '提交',
          backendNodeId: 1,
          properties: {'disabled': true},
        ),
        node(
          '3',
          role: 'checkbox',
          parentId: '1',
          name: '记住我',
          backendNodeId: 2,
          properties: {'checked': 'true'},
        ),
      ];

      final outline = OutlineBuilder().build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com',
        title: 't',
      );

      expect(outline.lines.first, contains('disabled'));
      expect(outline.lines.last, contains('checked'));
      // The layer refuses to dispatch at a disabled control, so the flag has to
      // survive into the ref record, not only into the printed line.
      expect(refs.lookup('a1').disabled, isTrue);
      expect(refs.lookup('a2').disabled, isFalse);
    });

    test('a control without a node id is reported, not given a dead ref', () {
      final nodes = [
        node('1', role: 'RootWebArea', name: 't', children: ['2']),
        node('2', role: 'button', parentId: '1', name: '幽灵按钮'),
      ];

      final outline = OutlineBuilder().build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com',
        title: 't',
      );

      expect(outline.entries, isEmpty);
      expect(outline.omitted.join(), contains('无法直接操作'));
      expect(refs.length, 0);
    });

    test('truncation is counted and stated', () {
      final nodes = <AxNode>[
        node('1', role: 'RootWebArea', name: 't'),
      ];
      for (var index = 0; index < 30; index++) {
        nodes.add(node(
          'b$index',
          role: 'button',
          parentId: '1',
          name: '按钮$index',
          backendNodeId: 1000 + index,
        ));
      }

      final outline = OutlineBuilder(maxEntries: 10).build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com',
        title: 't',
      );

      expect(outline.entries.length, 10);
      expect(outline.truncated, isTrue);
      expect(outline.omitted.join(), contains('20 个元素未显示'));
    });

    test('child frame nodes keep their session, so an action knows where to go', () {
      final nodes = [
        node('1', role: 'RootWebArea', name: 't', children: ['2']),
        node('2', role: 'Iframe', parentId: '1', name: '支付', backendNodeId: 5),
        node('9', role: 'button', name: '确认支付', backendNodeId: 7, sessionId: 'S1'),
      ];

      final outline = OutlineBuilder().build(
        nodes: nodes,
        refs: refs,
        url: 'https://example.com',
        title: 't',
      );

      final payoff = outline.entries.firstWhere((entry) => entry.name == '确认支付');
      expect(payoff.frameId, 'S1');
      expect(refs.lookup(payoff.ref).sessionId, 'S1');
      expect(outline.omitted.join(), contains('iframe'));
    });
  });

  group('parseAxNodes', () {
    test('reads role, name, value, states and the backend node id', () {
      final parsed = parseAxNodes([
        {
          'nodeId': '1',
          'ignored': false,
          'role': {'type': 'role', 'value': 'button'},
          'name': {'type': 'computedString', 'value': '登录'},
          'backendDOMNodeId': 42,
          'childIds': <String>[],
          'properties': [
            {
              'name': 'disabled',
              'value': {'type': 'boolean', 'value': true},
            },
          ],
        },
        {
          'nodeId': '2',
          'role': {'value': 'textbox'},
          'name': {'value': '用户名'},
          'value': {'value': 'bob'},
          'backendDOMNodeId': 43,
        },
      ]);

      expect(parsed, hasLength(2));
      expect(parsed.first.role, 'button');
      expect(parsed.first.name, '登录');
      expect(parsed.first.backendNodeId, 42);
      expect(parsed.first.flag('disabled'), isTrue);
      expect(parsed.last.value, 'bob');
      expect(parsed.last.flag('disabled'), isFalse);
    });

    test('tolerates a payload with no nodes', () {
      expect(parseAxNodes(null), isEmpty);
      expect(parseAxNodes(<Object?>[]), isEmpty);
      expect(parseAxNodes(['nonsense']), isEmpty);
    });
  });
}
