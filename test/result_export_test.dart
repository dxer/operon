import 'package:flutter_test/flutter_test.dart';
import 'package:operon/utils/result_export.dart';

void main() {
  group('buildExportTable', () {
    test('a list of records becomes one row per record', () {
      final table = buildExportTable([
        {'title': 'A', 'price': 12},
        {'title': 'B', 'price': 30},
      ]);

      expect(table.fields, ['title', 'price']);
      expect(table.rows, [
        ['A', '12'],
        ['B', '30'],
      ]);
      expect(table.recordCount, 2);
      expect(table.hasMissing, isFalse);
    });

    test('fields are the union, not the keys of the first record', () {
      final table = buildExportTable([
        {'title': 'A'},
        {'title': 'B', 'price': 5},
      ]);

      expect(table.fields, ['title', 'price']);
      // The missing value is an empty cell, not a shorter row: a ragged table
      // shifts every later column by one.
      expect(table.rows, [
        ['A', ''],
        ['B', '5'],
      ]);
      expect(table.missingIn('price'), 1);
      expect(table.hasMissing, isTrue);
    });

    test('a single record is one row', () {
      final table = buildExportTable({'title': '只有一条'});
      expect(table.recordCount, 1);
      expect(table.rows, [
        ['只有一条'],
      ]);
    });

    test('a list of strings gets a column named for what it is', () {
      final table = buildExportTable(['甲', '乙']);
      expect(table.fields, [ExportTable.scalarField]);
      expect(table.rows, [
        ['甲'],
        ['乙'],
      ]);
    });

    test('nested values are kept as JSON instead of being dropped', () {
      final table = buildExportTable([
        {
          'tags': ['a', 'b'],
          'meta': {'k': 1},
        },
      ]);
      expect(table.rows.single, ['["a","b"]', '{"k":1}']);
    });

    test('null and empty data produce an empty table', () {
      expect(buildExportTable(null).isEmpty, isTrue);
      expect(buildExportTable(const []).isEmpty, isTrue);
    });
  });

  group('exportToCsv', () {
    test('starts with a BOM and separates with CRLF', () {
      final csv = exportToCsv(buildExportTable([{'a': 1}]));
      expect(csv, '\uFEFFa\r\n1\r\n');
    });

    test('quotes commas, quotes and newlines', () {
      final csv = exportToCsv(buildExportTable([
        {'note': 'a,b'},
        {'note': 'say "hi"'},
        {'note': 'line1\nline2'},
      ]));

      expect(csv, contains('"a,b"'));
      expect(csv, contains('"say ""hi"""'));
      expect(csv, contains('"line1\nline2"'));
    });

    test('a value that needs no quoting is left alone', () {
      final csv = exportToCsv(buildExportTable([
        {'note': 'plain'},
      ]));
      expect(csv, '\uFEFFnote\r\nplain\r\n');
    });
  });

  test('the Markdown table escapes the pipe it uses as a separator', () {
    final text = exportToMarkdownTable(buildExportTable([
      {'a|b': 'x|y'},
    ]));
    expect(text.split('\n').first, r'| a\|b |');
    expect(text, contains(r'| x\|y |'));
  });

  test('JSON keeps the payload as it came', () {
    expect(exportToJson({'a': [1, 2]}), '{\n  "a": [\n    1,\n    2\n  ]\n}');
  });

  test('file names are timestamped and sort by name', () {
    expect(
      exportFileName('csv', at: DateTime(2026, 11, 5, 9, 7)),
      'operon-20261105-0907.csv',
    );
  });

  test('mime types match what a share target expects', () {
    expect(exportMimeType('csv'), 'text/csv');
    expect(exportMimeType('json'), 'application/json');
    expect(exportMimeType('md'), 'text/markdown');
    expect(exportMimeType('txt'), 'text/plain');
  });
}
