import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';
import '../../services/share_service.dart';
import '../../utils/result_export.dart';

enum _DataMode { table, json }

/// The full view of what a run scraped.
///
/// Two readings of the same payload: the table is what a person checks (did it
/// get the right rows?), the JSON is what a person verifies (is this what the
/// model actually said?). Both come from the same [ExportTable], so the counts
/// on this sheet, on the card behind it and in the exported file agree.
///
/// Keeping this a sheet rather than a page is deliberate: it is opened from the
/// panel, and a route push would hide the conversation the data belongs to.
class ExtractedDataSheet extends StatefulWidget {
  const ExtractedDataSheet({super.key, required this.data});

  final dynamic data;

  @override
  State<ExtractedDataSheet> createState() => ExtractedDataSheetState();
}

class ExtractedDataSheetState extends State<ExtractedDataSheet> {
  /// Rows past this are still exported, just not drawn: a 2000-row product list
  /// would build a table nobody scrolls to the end of.
  static const int _drawnRows = 200;

  _DataMode _mode = _DataMode.table;
  bool _copied = false;

  ExportTable get _table => buildExportTable(widget.data);

  Future<void> _copy() async {
    HapticService.selection();
    await Clipboard.setData(
      ClipboardData(text: exportToJson(widget.data)),
    );
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _exportCsv() async {
    final table = _table;
    if (table.isEmpty) return;
    HapticService.selection();
    final shared = await const ShareService().shareTextFile(
      fileName: exportFileName('csv'),
      content: exportToCsv(table),
      mimeType: exportMimeType('csv'),
    );
    if (!shared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台设备没有可用的分享目标，可以改用复制')),
      );
    }
  }

  void _exportText() {
    final text = exportToMarkdownTable(_table);
    if (text.isEmpty) return;
    HapticService.selection();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制为 Markdown 表格')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final table = _table;
    final showTable = _mode == _DataMode.table && !table.isEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.x2 + 2),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppInk.tertiary(isDark).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x2,
                AppSpace.x2,
                AppSpace.x1,
              ),
              child: Row(
                children: [
                  Icon(Icons.dataset_outlined,
                      size: 16, color: AppTheme.accentOf(isDark)),
                  const SizedBox(width: AppSpace.x1 + 2),
                  Expanded(
                    child: Text(
                      table.isEmpty
                          ? '抓取的数据'
                          : '${table.recordCount} 条 · ${table.fieldCount} 个字段',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label.copyWith(
                        color: AppInk.primary(isDark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppInk.tertiary(isDark)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
              child: Row(
                children: [
                  if (!table.isEmpty)
                    _ModeSwitch(
                      mode: _mode,
                      isDark: isDark,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                  const Spacer(),
                  _action(
                    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                    label: _copied ? '已复制' : '复制',
                    isDark: isDark,
                    onTap: _copy,
                  ),
                  if (!table.isEmpty)
                    _action(
                      icon: Icons.grid_on_rounded,
                      label: 'CSV',
                      isDark: isDark,
                      onTap: _exportCsv,
                    ),
                  if (!table.isEmpty)
                    _action(
                      icon: Icons.table_chart_outlined,
                      label: 'Markdown',
                      isDark: isDark,
                      onTap: _exportText,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x1),
            Divider(
              height: 1,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            Expanded(
              child: showTable
                  ? _TableBody(
                      table: table,
                      isDark: isDark,
                      drawnRows: _drawnRows,
                    )
                  : _JsonBody(
                      text: exportToJson(widget.data),
                      isDark: isDark,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpace.tap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1 + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppInk.secondary(isDark)),
              const SizedBox(width: AppSpace.x1 - 2),
              Text(
                label,
                style: AppType.caption.copyWith(color: AppInk.secondary(isDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Table / JSON, drawn as two chips rather than a TabBar: the sheet is not a
/// destination, and a tab bar would suggest a route of its own.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.isDark,
    required this.onChanged,
  });

  final _DataMode mode;
  final bool isDark;
  final ValueChanged<_DataMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(isDark);
    Widget chip(String label, _DataMode value) {
      final active = mode == value;
      return InkWell(
        onTap: active ? null : () => onChanged(value),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: AppType.caption.copyWith(
              color: active ? accent : AppInk.secondary(isDark),
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('表格', _DataMode.table),
        chip('JSON', _DataMode.json),
      ],
    );
  }
}

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.table,
    required this.isDark,
    required this.drawnRows,
  });

  final ExportTable table;
  final bool isDark;
  final int drawnRows;

  @override
  Widget build(BuildContext context) {
    final rows = table.rows.take(drawnRows).toList(growable: false);
    final truncated = table.recordCount > rows.length;
    final hairline = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x2,
                AppSpace.x4,
                AppSpace.x2,
              ),
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(150),
                border: TableBorder(
                  horizontalInside: BorderSide(color: hairline),
                ),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      for (final field in table.fields)
                        _cell(
                          field,
                          isDark,
                          header: true,
                        ),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (final value in row) _cell(value, isDark),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.x4,
            AppSpace.x1,
            AppSpace.x4,
            AppSpace.x3,
          ),
          child: Text(
            truncated
                ? '只显示前 ${rows.length} 行，导出 CSV 取全部 ${table.recordCount} 行'
                : '共 ${table.recordCount} 行',
            style: AppType.micro.copyWith(
              color: AppInk.tertiary(isDark),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(String value, bool isDark, {bool header = false}) {
    final empty = value.isEmpty && !header;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.x2,
        vertical: AppSpace.x2,
      ),
      child: Text(
        empty ? '—' : value,
        maxLines: header ? 1 : 4,
        overflow: TextOverflow.ellipsis,
        style: header
            ? AppType.caption.copyWith(
                color: AppInk.secondary(isDark),
                fontWeight: FontWeight.w600,
              )
            : AppType.caption.copyWith(
                color: empty
                    ? AppInk.tertiary(isDark)
                    : AppInk.primary(isDark),
              ),
      ),
    );
  }
}

class _JsonBody extends StatelessWidget {
  const _JsonBody({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x3,
        AppSpace.x4,
        AppSpace.x4,
      ),
      child: SelectableText(
        text,
        style: AppType.caption.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
          color: AppInk.primary(isDark).withValues(alpha: 0.86),
        ),
      ),
    );
  }
}
