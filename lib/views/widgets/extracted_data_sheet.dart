import 'dart:convert';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// Full-screen-ish viewer for extracted data. Keeping the sheet itself short
/// avoids a nested scroll area inside the agent panel.
class ExtractedDataSheet extends StatefulWidget {
  final dynamic data;

  const ExtractedDataSheet({super.key, required this.data});

  @override
  State<ExtractedDataSheet> createState() => ExtractedDataSheetState();
}

class ExtractedDataSheetState extends State<ExtractedDataSheet> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.6);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(widget.data);

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.dataset_outlined,
                      size: 16, color: AppTheme.accentOf(isDark)),
                  const SizedBox(width: 6),
                  Text(
                    '抓取的数据',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: jsonStr));
                      if (mounted) setState(() => _copied = true);
                    },
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _copied ? '已复制' : '复制',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentOf(isDark),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, size: 18, color: muted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SelectableText(
                  jsonStr,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.5,
                    color: onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
