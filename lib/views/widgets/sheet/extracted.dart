part of '../agent_bottom_sheet.dart';

// Structured data the run produced: what it is, and the three ways to take it
// away — a table to read, a CSV for a spreadsheet, text for a chat.

extension _SheetExtracted on _AgentBottomSheetState {
  void _copyExtractedData() {
    if (widget.state.extractedData == null) return;
    final jsonStr = exportToJson(widget.state.extractedData);
    HapticService.selection();
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制结构化数据至剪贴板！'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

  /// One preview cell: the same text the export would write, with a visible
  /// placeholder for "the model left this out".
  String _previewValue(dynamic value) {
    final text = exportCell(value);
    return text.isEmpty ? '—' : text;
  }

  String _dataSummary(dynamic data) {
    final table = buildExportTable(data);
    if (table.fieldCount == 0) return '已抓取结构化数据';
    return <String>[
      if (data is List) '${table.recordCount} 条数据',
      '${table.fieldCount} 个字段',
      // An empty cell reads as "the page had nothing there". If some records
      // simply left a field out, say so instead of letting the table answer
      // a question the page was never asked.
      if (table.hasMissing) '有缺列',
    ].join(' · ');
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  Widget _buildExtractedCard({
    required dynamic data,
    required Color surface,
    required Color hairline,
    required Color onSurface,
    required Color muted,
  }) {
    final entries = _dataEntries(data);
    final preview = entries.take(3).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.dataset_outlined,
                  size: 15, color: AppTheme.accentOf(_isDarkTheme)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dataSummary(data),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: onSurface.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _iconAction(
                icon: Icons.copy_rounded,
                tooltip: '复制数据（JSON）',
                color: muted,
                onTap: _copyExtractedData,
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...preview.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.micro.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _previewValue(entry.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.x1 + 2),
          // What the user came for. Copy holds the raw payload; these three
          // are the shapes an answer actually leaves in — a sheet, a file, a
          // message.
          Row(
            children: [
              _resultAction(
                icon: Icons.table_chart_outlined,
                label: '表格',
                color: muted,
                onTap: _showExtractedDataSheet,
              ),
              _resultAction(
                icon: Icons.grid_on_rounded,
                label: 'CSV',
                color: muted,
                onTap: _shareExtractedCsv,
              ),
              _resultAction(
                icon: Icons.ios_share_rounded,
                label: '分享',
                color: muted,
                onTap: _shareExtractedText,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showExtractedDataSheet() async {
    final data = widget.state.extractedData;
    if (data == null) return;
    HapticService.selection();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExtractedDataSheet(data: data),
    );
  }

  /// Sends the rows out as a `.csv` file.
  ///
  /// A CSV pasted into a chat is a wall of commas; the file is what opens in a
  /// spreadsheet, which is where scraped rows are actually used.
  Future<void> _shareExtractedCsv() async {
    final data = widget.state.extractedData;
    if (data == null) return;
    final table = buildExportTable(data);
    if (table.isEmpty) return;
    HapticService.selection();
    final goal = widget.state.goal.trim();
    final shared = await const ShareService().shareTextFile(
      fileName: exportFileName('csv'),
      content: exportToCsv(table),
      mimeType: exportMimeType('csv'),
      subject: goal.isEmpty ? null : goal,
    );
    if (!shared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台设备没有可用的分享目标，可以先复制数据')),
      );
    }
  }

  /// Sends the rows out as a Markdown table, for a chat or a document.
  Future<void> _shareExtractedText() async {
    final text = exportToMarkdownTable(
      buildExportTable(widget.state.extractedData),
    );
    if (text.isEmpty) return;
    HapticService.selection();
    final goal = widget.state.goal.trim();
    final shared = await const ShareService().shareText(
      text,
      subject: goal.isEmpty ? null : goal,
    );
    if (!shared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台设备没有可用的分享目标，可以改用复制')),
      );
    }
  }
}
