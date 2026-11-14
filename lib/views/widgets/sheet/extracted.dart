part of '../agent_bottom_sheet.dart';

// Structured data the run produced, summarised and openable in full.

extension _SheetExtracted on _AgentBottomSheetState {
  void _copyExtractedData() {
    if (widget.state.extractedData == null) return;
    final jsonStr =
        const JsonEncoder.withIndent('  ').convert(widget.state.extractedData);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制结构化数据至剪贴板！'),
        backgroundColor: AppTheme.accent,
      ),
    );
  }

  int _dataCount(dynamic data) => data is List ? data.length : 1;

  String _shortValue(dynamic value) {
    if (value == null) return '—';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return jsonEncode(value);
  }

  String _dataSummary(dynamic data) {
    final fields = _dataEntries(data).length;
    if (fields == 0) return '已抓取结构化数据';
    final count = _dataCount(data);
    if (data is List) return '$count 条数据 · $fields 个字段';
    return '$fields 个字段';
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
    final count = _dataCount(data);
    final preview = entries.take(3).toList();
    final canExpand = entries.isEmpty ||
        entries.length > preview.length ||
        (data is List && count > 1);

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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
              _iconAction(
                icon: Icons.copy_rounded,
                tooltip: '复制数据',
                color: muted,
                onTap: _copyExtractedData,
              ),
              if (canExpand)
                _iconAction(
                  icon: Icons.open_in_full_rounded,
                  tooltip: '展开全部',
                  color: muted,
                  onTap: _showExtractedDataSheet,
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
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _shortValue(entry.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                          color: onSurface.withValues(alpha: 0.86),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showExtractedDataSheet() async {
    final data = widget.state.extractedData;
    if (data == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExtractedDataSheet(data: data),
    );
  }
}
