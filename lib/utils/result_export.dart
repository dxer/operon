import 'dart:convert';

/// Turns whatever the model put in `done.data` into rows a person can take
/// away.
///
/// The model chooses the shape: a list of records, one record, or a list of
/// plain strings. The app should not care which — but the user always wants the
/// same three things out of a run that scraped something: a table to read, a
/// CSV for a spreadsheet, and text to paste into a chat.
///
/// Everything here is pure. The panel and the export sheet both build from the
/// same [ExportTable], so the row count on the card and the row count in the
/// file can never disagree.
class ExportTable {
  const ExportTable({required this.fields, required this.rows});

  /// Every field, in the order it was first seen across all records.
  ///
  /// The union of the records, not the keys of the first one: a run that
  /// returned twenty items where only the last one has a `price` would
  /// otherwise drop that column without saying so.
  final List<String> fields;

  /// One row per record, already flattened to strings. A missing value is an
  /// empty cell, never a shorter row.
  final List<List<String>> rows;

  static const ExportTable empty = ExportTable(fields: [], rows: []);

  bool get isEmpty => fields.isEmpty;
  int get recordCount => rows.length;
  int get fieldCount => fields.length;

  /// Cells in [field] that have no value.
  int missingIn(String field) {
    final index = fields.indexOf(field);
    if (index < 0) return 0;
    return rows.where((row) => row[index].isEmpty).length;
  }

  /// True when at least one record left a field empty.
  ///
  /// Worth saying out loud: an empty cell reads as "the page had nothing
  /// there", and the user needs to know whether that is the page's answer or
  /// the model's omission.
  bool get hasMissing => fields.any((field) => missingIn(field) > 0);

  /// The field used for records that are not objects (a list of strings).
  static const String scalarField = '值';
}

/// The cell text for one value.
///
/// Nested objects and arrays become compact JSON: a table cell cannot show a
/// tree, and dropping the value would silently lose data.
String exportCell(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return jsonEncode(value);
}

/// Builds the table for one run's data.
ExportTable buildExportTable(dynamic data) {
  if (data == null) return ExportTable.empty;
  final records = data is List ? data : <dynamic>[data];
  if (records.isEmpty) return ExportTable.empty;

  final fields = <String>[];
  final seen = <String>{};
  final rows = <Map<String, String>>[];

  for (final record in records) {
    final row = <String, String>{};
    if (record is Map) {
      for (final entry in record.entries) {
        final name = entry.key.toString();
        if (seen.add(name)) fields.add(name);
        row[name] = exportCell(entry.value);
      }
    } else {
      if (seen.add(ExportTable.scalarField)) {
        fields.add(ExportTable.scalarField);
      }
      row[ExportTable.scalarField] = exportCell(record);
    }
    rows.add(row);
  }

  return ExportTable(
    fields: List.unmodifiable(fields),
    rows: List.unmodifiable([
      for (final row in rows)
        List<String>.unmodifiable([
          for (final field in fields) row[field] ?? '',
        ]),
    ]),
  );
}

/// Excel reads a UTF-8 CSV as mojibake unless the file starts with a BOM, and
/// the people who ask for a CSV are opening it in Excel.
const String _csvBom = '\uFEFF';

/// RFC 4180, with CRLF line endings (Excel again) and a BOM in front.
String exportToCsv(ExportTable table) {
  if (table.isEmpty) return _csvBom;
  final buffer = StringBuffer(_csvBom)
    ..write(table.fields.map(_csvCell).join(','))
    ..write('\r\n');
  for (final row in table.rows) {
    buffer
      ..write(row.map(_csvCell).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

String _csvCell(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// The raw payload, pretty-printed. What the model actually said, for the
/// people who want to check it.
String exportToJson(dynamic data) =>
    const JsonEncoder.withIndent('  ').convert(data);

/// The table as Markdown, for pasting into a document or a chat.
String exportToMarkdownTable(ExportTable table) {
  if (table.isEmpty) return '';
  String cell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();
  final buffer = StringBuffer()
    ..writeln('| ${table.fields.map(cell).join(' | ')} |')
    ..writeln('| ${table.fields.map((_) => '---').join(' | ')} |');
  for (final row in table.rows) {
    buffer.writeln('| ${row.map(cell).join(' | ')} |');
  }
  return buffer.toString().trimRight();
}

/// `operon-20261115-1430.csv` — sortable, and distinct per export.
String exportFileName(String extension, {DateTime? at}) {
  final now = at ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'operon-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.$extension';
}

/// The MIME type a share target needs to offer the right apps.
String exportMimeType(String extension) => switch (extension) {
      'csv' => 'text/csv',
      'json' => 'application/json',
      'md' => 'text/markdown',
      _ => 'text/plain',
    };
