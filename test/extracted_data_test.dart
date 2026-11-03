import 'package:flutter_test/flutter_test.dart';
import 'package:operon/utils/extracted_data.dart';

void main() {
  test('lists from consecutive pages are concatenated', () {
    final merged = mergeExtractedData(
      [
        {'author': 'a', 'text': 'one'},
      ],
      [
        {'author': 'b', 'text': 'two'},
      ],
    );
    expect(merged, [
      {'author': 'a', 'text': 'one'},
      {'author': 'b', 'text': 'two'},
    ]);
  });

  test('repeated records are merged once', () {
    final merged = mergeExtractedData(
      [
        {'id': 1},
        {'id': 2},
      ],
      [
        {'id': 2},
        {'id': 3},
      ],
    );
    expect((merged as List).map((e) => e['id']), [1, 2, 3]);
  });

  test('maps merge key by key and concatenate nested lists', () {
    final merged = mergeExtractedData(
      {
        'title': 'page 1',
        'items': [
          {'id': 1},
        ],
      },
      {
        'items': [
          {'id': 2},
        ],
      },
    ) as Map;
    expect(merged['title'], 'page 1');
    expect((merged['items'] as List).map((e) => e['id']), [1, 2]);
  });

  test('a new value of a different type replaces the old one', () {
    expect(mergeExtractedData('text', 42), 42);
    expect(mergeExtractedData({'a': 1}, [1, 2]), [1, 2]);
  });

  test('null input leaves the accumulated value untouched', () {
    expect(mergeExtractedData([1, 2], null), [1, 2]);
    expect(mergeExtractedData(null, [1, 2]), [1, 2]);
  });

  test('the stored list stays bounded', () {
    final merged = mergeExtractedData(
      List.generate(3, (i) => {'id': i}),
      List.generate(3, (i) => {'id': i + 10}),
      maxItems: 4,
    );
    expect((merged as List).length, 4);
  });
}
