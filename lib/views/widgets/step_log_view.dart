import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/agent_state.dart';

/// One timeline for a run: what the model was thinking, what it did, and what
/// the page did back.
///
/// The old panel kept the reasoning in a card at the top and the actions in a
/// log sheet below, so following a run meant reading two places and pairing
/// them by eye. Here they are the same list, and an action is a card holding its
/// own receipt: the three outcomes stay separate lines because "点到了",
/// "页面动了" and "做成了" are three different answers.
class StepLogView extends StatelessWidget {
  const StepLogView({super.key, required this.logs});

  final List<AgentLogItem> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.38);

    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            '尚未开始执行，输入任务指令后点击开始',
            style: TextStyle(color: subtle, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[logs.length - 1 - index];
        final isNewest = index == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: log.kind == LogKind.thought
              ? _ThoughtRow(log: log)
              : _LogRow(key: ObjectKey(log), log: log, isNewest: isNewest),
        );
      },
    );
  }
}

/// What the model was thinking: same timeline, less furniture.
class _ThoughtRow extends StatelessWidget {
  const _ThoughtRow({required this.log});

  final AgentLogItem log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 4, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.auto_awesome_rounded, size: 13, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log.title,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({super.key, required this.log, required this.isNewest});

  final AgentLogItem log;

  /// The row still running: it says so instead of pretending to be finished.
  final bool isNewest;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final log = widget.log;
    final evidence = log.evidence;

    final (color, icon) = switch (log.kind) {
      LogKind.error => (AppTheme.dangerOf(isDark), Icons.error_outline_rounded),
      LogKind.result => (AppTheme.primaryOf(isDark), Icons.check_circle_outline_rounded),
      LogKind.action =>
        (AppTheme.primaryOf(isDark), Icons.ads_click_rounded),
      _ => (AppTheme.neutralOf(isDark), Icons.info_outline_rounded),
    };

    final running = log.kind == LogKind.action && evidence == null && widget.isNewest;
    final summary = evidence?.summary ?? '';
    final hasDetail = summary.isNotEmpty ||
        (evidence?.changes.isNotEmpty ?? false) ||
        (evidence?.note?.isNotEmpty ?? false) ||
        (evidence?.image?.isNotEmpty ?? false) ||
        evidence?.urlChanged == true ||
        (log.detail?.isNotEmpty ?? false);
    final shownDetail = _open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasDetail ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Badge(log: log, color: color, icon: icon, running: running),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              log.title,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: log.isError
                                    ? AppTheme.dangerOf(isDark)
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (hasDetail)
                            Icon(
                              shownDetail
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                        ],
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _OutcomeLine(evidence: evidence!, isDark: isDark),
                      ] else if (running) ...[
                        const SizedBox(height: 3),
                        Text(
                          '执行中…',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ] else if (log.detail != null && !shownDetail) ...[
                        const SizedBox(height: 2),
                        Text(
                          log.detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shownDetail)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 8, 6),
            child: _Detail(evidence: evidence, detail: log.detail, isDark: isDark),
          ),
        if (log.kind != LogKind.result)
          Divider(
            height: 1,
            indent: 32,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.log,
    required this.color,
    required this.icon,
    required this.running,
  });

  final AgentLogItem log;
  final Color color;
  final IconData icon;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final label = log.kind == LogKind.action && log.step > 0 ? '${log.step}' : null;
    return SizedBox(
      width: 22,
      height: 22,
      child: running
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
            )
          : Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: label == null
                  ? Icon(icon, size: 12, color: color)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
            ),
    );
  }
}

/// The three outcomes, each its own chip: delivery, reaction, expectation.
class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({required this.evidence, required this.isDark});

  final StepEvidence evidence;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      if (evidence.deliveryLabel != null)
        _Chip(
          text: evidence.deliveryLabel!,
          color: evidence.delivery == 'delivered'
              ? AppTheme.primaryOf(isDark)
              : AppTheme.warningOf(isDark),
        ),
      if (evidence.reactionLabel != null)
        _Chip(
          text: evidence.reactionLabel!,
          color: evidence.pageReacted == true
              ? AppTheme.primaryOf(isDark)
              : AppTheme.neutralOf(isDark),
        ),
      if (evidence.expectationLabel != null)
        _Chip(
          text: evidence.expectationLabel!,
          color: evidence.expectedStateReached == false
              ? AppTheme.warningOf(isDark)
              : AppTheme.primaryOf(isDark),
        ),
      if (evidence.changes.isNotEmpty)
        _Chip(
          text: '页面变化 ${evidence.changes.length} 行',
          color: AppTheme.accentOf(isDark),
        ),
      if (evidence.image != null)
        _Chip(text: '截图', color: AppTheme.accentOf(isDark)),
      if (evidence.elapsedMs != null)
        Text(
          '${evidence.elapsedMs}ms',
          style: TextStyle(
            fontSize: 10.5,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Everything behind the arrow: what changed, what the layer noted, the shot.
class _Detail extends StatelessWidget {
  const _Detail({required this.evidence, required this.detail, required this.isDark});

  final StepEvidence? evidence;
  final String? detail;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final changes = evidence?.changes ?? const <String>[];
    final parts = <Widget>[];

    if (evidence?.urlChanged == true) {
      parts.add(_Line(label: '地址', value: '${evidence!.urlBefore} → ${evidence!.urlAfter}', muted: muted));
    }
    if (changes.isNotEmpty) {
      parts.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in changes.take(12))
                Text(
                  line,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: line.startsWith('+')
                        ? AppTheme.primaryOf(isDark)
                        : line.startsWith('-')
                            ? AppTheme.dangerOf(isDark)
                            : muted,
                  ),
                ),
              if (changes.length > 12)
                Text('…还有 ${changes.length - 12} 行', style: TextStyle(fontSize: 10.5, color: muted)),
            ],
          ),
        ),
      );
    }
    if (evidence?.note != null && evidence!.note!.isNotEmpty) {
      parts.add(_Line(label: '备注', value: evidence!.note!, muted: muted));
    }
    if (detail != null && detail!.isNotEmpty) {
      parts.add(_Line(label: '说明', value: detail!, muted: muted));
    }
    final image = evidence?.image;
    if (image != null && image.isNotEmpty) {
      parts.add(ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.memory(
          base64Decode(image),
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) =>
              Text('截图无法显示', style: TextStyle(fontSize: 11, color: muted)),
        ),
      ));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          parts[i],
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.muted});

  final String label;
  final String value;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: muted)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 11, height: 1.4, color: muted),
          ),
        ),
      ],
    );
  }
}
