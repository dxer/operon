import 'package:flutter_test/flutter_test.dart';
import 'package:operon/control/perception/options.dart';
import 'package:operon/control/protocol/errors.dart';

/// Picking a dropdown option happens in Dart, not in page script: a dropdown
/// that answers "改了" without changing anything is the usual failure, so the
/// choice is made where it can be tested and the page is only told the index.

const cityOptions = [
  SelectOption(index: 0, value: '', label: '请选择'),
  SelectOption(index: 1, value: '110000', label: '北京'),
  SelectOption(index: 2, value: '310000', label: '上海'),
  SelectOption(index: 3, value: '440300', label: '深圳'),
  SelectOption(index: 4, value: 'x', label: '上海（已停用）', disabled: true),
];

void main() {
  group('chooseOption', () {
    test('an exact value wins over a label that also matches', () {
      final choice = chooseOption(cityOptions, label: '上海', value: '440300');
      expect(choice.option.label, '深圳');
      expect(choice.how, 'value');
    });

    test('an exact label match ignores case and spacing', () {
      final choice = chooseOption(cityOptions, label: '  上海 ');
      expect(choice.option.index, 2);
      expect(choice.how, 'label');
    });

    test('a partial label is the last resort, never a prefix of a longer one', () {
      final choice = chooseOption(cityOptions, label: '深');
      expect(choice.option.label, '深圳');
      expect(choice.how, 'label-contains');
    });

    test('a disabled option is never a candidate by text', () {
      // "上海（已停用）" contains neither of the enabled labels, and a disabled
      // row must not be picked by text even when it is the only match.
      expect(
        () => chooseOption(cityOptions, label: '停用'),
        throwsA(isA<ControlException>()
            .having((e) => e.code, 'code', ControlErrorCode.notFound)),
      );
    });

    test('an index picks exactly, including a disabled row, and refuses it', () {
      expect(chooseOption(cityOptions, index: 3).option.label, '深圳');
      expect(
        () => chooseOption(cityOptions, index: 4),
        throwsA(isA<ControlException>()
            .having((e) => e.code, 'code', ControlErrorCode.notFound)
            .having((e) => e.message, 'message', contains('禁用'))),
      );
    });

    test('an index that is not there is a typed failure, not a guess', () {
      expect(
        () => chooseOption(cityOptions, index: 99),
        throwsA(isA<ControlException>()
            .having((e) => e.code, 'code', ControlErrorCode.notFound)),
      );
    });

    test('no match lists what was actually available', () {
      try {
        chooseOption(cityOptions, label: '广州');
        fail('should have thrown');
      } on ControlException catch (error) {
        expect(error.code, ControlErrorCode.notFound);
        expect(error.hint, contains('北京'));
        expect(error.hint, contains('上海'));
        expect(error.details?['options'], isA<List>());
      }
    });

    test('an empty dropdown says why it is empty', () {
      try {
        chooseOption(const [], label: '北京');
        fail('should have thrown');
      } on ControlException catch (error) {
        expect(error.hint, contains('没有选项'));
      }
    });

    test('a value nobody has falls back to text before giving up', () {
      // The caller may send the visible text as the value; that is not a reason
      // to fail when the label matches.
      final choice = chooseOption(cityOptions, label: '北京', value: '北京市');
      expect(choice.option.value, '110000');
    });
  });

  group('SelectOption.fromJson', () {
    test('reads what the page sent, and tolerates missing fields', () {
      final option = SelectOption.fromJson({'index': 2, 'value': 'v', 'label': '标签'});
      expect(option.index, 2);
      expect(option.value, 'v');
      expect(option.label, '标签');
      expect(option.disabled, isFalse);
      expect(SelectOption.fromJson(const {}).index, -1);
    });
  });
}
