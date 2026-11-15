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

    test('a form fill without a submit is not a write', () {
      final fill = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a1', 'value': '张三'},
            {'ref': 'a2', 'value': '北京', 'action': 'select'},
          ],
        },
        targetLabels: ['textbox "姓名"', 'combobox "城市"'],
      );
      expect(fill.writes, isFalse);
    });

    test('a form with a submit asks, whatever the button says', () {
      final submit = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a1', 'value': '张三'},
          ],
          'submitRef': 'a9',
        },
        targetLabel: 'button "下一步"',
        targetLabels: ['textbox "姓名"'],
      );
      expect(submit.writes, isTrue);
      expect(submit.kind, '提交表单');
      expect(submit.destructive, isFalse);
      expect(submit.handoff, isFalse);
    });

    test('a credential field hands the whole form to the user', () {
      final flagged = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a1', 'value': 'user@example.com'},
            {'ref': 'a2', 'value': 'x', 'secret': true},
          ],
          'submitRef': 'a9',
        },
        targetLabel: 'button "登录"',
      );
      expect(flagged.writes, isTrue);
      expect(flagged.handoff, isTrue);
      expect(flagged.destructive, isTrue);

      // The label alone is enough: a model that forgot the secret flag still
      // must not type a password.
      final byLabel = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a2', 'value': 'x'},
          ],
        },
        targetLabels: ['textbox "登录密码"'],
      );
      expect(byLabel.handoff, isTrue);
    });

    test('a secret flag is read the way the control layer reads it', () {
      for (final flag in <Object>[true, 1, 'true', 'yes']) {
        final result = assessWrite(
          'fill_form',
          {
            'fields': [
              {'ref': 'a1', 'value': '1234', 'secret': flag},
            ],
          },
          targetLabels: ['textbox "PIN"'],
        );
        expect(result.handoff, isTrue, reason: 'secret: $flag');
      }
      for (final flag in <Object?>[false, 0, 'false', null]) {
        final result = assessWrite(
          'fill_form',
          {
            'fields': [
              {'ref': 'a1', 'value': '1234', 'secret': flag},
            ],
          },
          targetLabels: ['textbox "PIN"'],
        );
        expect(result.handoff, isFalse, reason: 'secret: $flag');
      }
      expect(
        assessWrite('type', {'ref': 'a1', 'text': 'x', 'secret': 1}).handoff,
        isTrue,
      );
    });

    test('a destructive submit stays destructive', () {
      final remove = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a1', 'value': '不再使用'},
          ],
          'submitRef': 'a9',
        },
        targetLabel: 'button "删除账户"',
        targetLabels: ['textbox "原因"'],
      );
      expect(remove.destructive, isTrue);
      expect(remove.handoff, isFalse);
    });

    test('saving a draft is a draft even through a form', () {
      final draft = assessWrite(
        'fill_form',
        {
          'fields': [
            {'ref': 'a1', 'value': '未完成'},
          ],
          'submitRef': 'a9',
        },
        targetLabel: 'button "保存草稿"',
      );
      expect(draft.writes, isFalse);
      expect(draft.kind, '草稿');
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
