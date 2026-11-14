import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/permission.dart';

void main() {
  group('assessWrite', () {
    test('typing alone is local until it is submitted', () {
      expect(assessWrite('type', {'ref': 'a1', 'text': '你好'}).writes, isFalse);
      final submitted = assessWrite('type', {'ref': 'a1', 'text': '你好', 'submit': true});
      expect(submitted.writes, isTrue);
      expect(submitted.kind, '提交');
    });

    test('enter submits, other keys do not', () {
      expect(assessWrite('press', {'key': 'Enter'}).writes, isTrue);
      expect(assessWrite('press', {'key': 'Tab'}).writes, isFalse);
      expect(assessWrite('press', {'key': 'ArrowDown'}).writes, isFalse);
    });

    test('a click is classified by the label it will hit', () {
      final send = assessWrite('click', {'ref': 'a1'}, targetLabel: 'button "发送"');
      expect(send.writes, isTrue);
      expect(send.kind, '提交');
      expect(send.destructive, isFalse);

      final remove =
          assessWrite('click', {'ref': 'a2'}, targetLabel: 'button "删除这条记录"');
      expect(remove.writes, isTrue);
      expect(remove.destructive, isTrue);

      final nav = assessWrite('click', {'ref': 'a3'}, targetLabel: 'link "首页"');
      expect(nav.writes, isFalse);
    });

    test('a pay button is destructive even when the label is in English', () {
      final pay = assessWrite('click', {'ref': 'a1'}, targetLabel: 'button "Pay now"');
      expect(pay.destructive, isTrue);
    });

    test('saving a draft is not publishing, and is not a write either', () {
      final draft =
          assessWrite('click', {'ref': 'a1'}, targetLabel: 'button "保存草稿"');
      expect(draft.writes, isFalse);
      // A draft label wins over the submit words it contains.
      final draftEn =
          assessWrite('click', {'ref': 'a1'}, targetLabel: 'button "Save draft"');
      expect(draftEn.writes, isFalse);
    });

    test('a click with no label at all is treated as a write', () {
      // Nothing says what it will do, so it asks rather than assumes.
      expect(assessWrite('click', {'ref': 'a1'}).writes, isTrue);
    });

    test('accepting a page dialog is always destructive', () {
      final accept = assessWrite('handle_dialog', {'accept': true});
      expect(accept.writes, isTrue);
      expect(accept.destructive, isTrue);
      expect(assessWrite('handle_dialog', {'accept': false}).writes, isTrue);
    });

    test('navigation and scrolling are not writes', () {
      expect(assessWrite('navigate', {'url': 'https://example.com'}).writes, isFalse);
      expect(assessWrite('scroll', {'direction': 'down'}).writes, isFalse);
      expect(assessWrite('snapshot', const {}).writes, isFalse);
    });
  });
}
