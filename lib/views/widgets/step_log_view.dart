import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../models/agent_state.dart';

/// The run, as a timeline: what the model thought, what it did, and what the
/// page did back.
///
/// This used to be a stack of self-contained cards, one per call. A card is a
/// good shape for a thing you read once; a run is a sequence, and a stack of
/// cards hides the only question the user actually has while it runs — *where
/// are we now*. A rail with nodes answers it: one glance down the left edge
/// shows how far the line goes and which node is still breathing.
///
/// It renders inline rather than as its own scroll view, because the panel is
/// the scroll view. A list inside a list is how a panel ends up with two
/// thumbs' worth of scrollable regions.
class StepLogView extends StatelessWidget {
  const StepLogView({super.key, required this.logs});

  final List<AgentLogItem> logs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x5),
        child: Text(
          '还没有开始。发出指令后，每一步都会出现在这里。',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: AppInk.tertiary(isDark)),
        ),
      );
    }

    // Newest at the bottom: a timeline reads downwards, and appending is what
    // a run does.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < logs.length; i++)
          _TimelineRow(
            key: ObjectKey(logs[i]),
            log: logs[i],
            isLast: i == logs.length - 1,
            isDark: isDark,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatefulWidget {
  const _TimelineRow({
    super.key,
    required this.log,
    required this.isLast,
    required this.isDark,
  });

  final AgentLogItem log;

  /// The last known step: its rail stops instead of leading nowhere.
  final bool isLast;
  final bool isDark;

  @override
  State<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<_TimelineRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _open = false;

  AgentLogItem get _log => widget.log;

  /// An action with no receipt yet is still out there.
  bool get _running => _log.kind == LogKind.action && _log.evidence == null;

  @override
  void initState() {
    super.initState();
    // Eager: a lazily created controller would be born inside dispose() for
    // rows that never animated.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _TimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (_running && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!_running && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final evidence = _log.evidence;
    // `isError` is what the loop sets; `kind` is what a caller may set. Either
    // one means the row is a failure.
    final kind = _log.isError ? LogKind.error : _log.kind;
    final (color, label) = switch (kind) {
      LogKind.thought => (AppInk.tertiary(isDark), '思考'),
      LogKind.action => (AppTheme.primaryOf(isDark), '动作'),
      LogKind.result => (AppTheme.accentOf(isDark), '结果'),
      LogKind.error => (AppTheme.dangerOf(isDark), '错误'),
      LogKind.note => (AppInk.tertiary(isDark), '备注'),
    };

    final summary = evidence?.summary ?? '';
    final hasDetail = summary.isNotEmpty ||
        (evidence?.changes.isNotEmpty ?? false) ||
        (evidence?.note?.isNotEmpty ?? false) ||
        (evidence?.image?.isNotEmpty ?? false) ||
        evidence?.urlChanged == true ||
        (_log.detail?.isNotEmpty ?? false);

    // Thinking is context, not an event: it gets less furniture and no node
    // weight, so the eye lands on actions and results first.
    final quiet = kind == LogKind.thought;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _Node(
                    kind: kind,
                    color: color,
                    running: _running,
                    pulse: _pulse,
                  ),
                ),
                // The rail: one hairline, drawn by the row that knows whether
                // anything follows it.
                Expanded(
                  child: Container(
                    width: AppStroke.hairline,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: widget.isLast
                        ? Colors.transparent
                        : AppInk.hairline(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isLast ? 0 : AppSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: hasDetail ? () => setState(() => _open = !_open) : null,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              label,
                              style: AppType.micro.copyWith(
                                color: color,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const Spacer(),
                            if (hasDetail)
                              Icon(
                                _open
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: AppInk.tertiary(isDark),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _log.title,
                          style: AppType.body.copyWith(
                            color: quiet
                                ? AppInk.secondary(isDark)
                                : (_log.isError
                                    ? AppTheme.dangerOf(isDark)
                                    : AppInk.primary(isDark)),
                            fontWeight: quiet ? FontWeight.w400 : FontWeight.w500,
                          ),
                        ),
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.x2 - 2),
                          _OutcomeLine(evidence: evidence!, isDark: isDark),
                        ] else if (_running) ...[
                          const SizedBox(height: AppSpace.x2),
                          _Skeleton(pulse: _pulse, isDark: isDark),
                        ] else if (_log.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _log.detail!,
                            maxLines: _open ? null : 2,
                            overflow: _open ? null : TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              color: AppInk.secondary(isDark),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_open && hasDetail) ...[
                    const SizedBox(height: AppSpace.x2),
                    _Detail(
                      evidence: evidence,
                      detail: _log.detail,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The node on the rail. Its shape is its kind, so the timeline can be scanned
/// without reading a word.
class _Node extends StatelessWidget {
  const _Node({
    required this.kind,
    required this.color,
    required this.running,
    required this.pulse,
  });

  final LogKind kind;
  final Color color;
  final bool running;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, _) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.35 + 0.45 * pulse.value),
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    switch (kind) {
      case LogKind.result:
        return Icon(Icons.check_rounded, size: 11, color: color);
      case LogKind.error:
        return Icon(Icons.priority_high_rounded, size: 11, color: color);
      case LogKind.action:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
      case LogKind.thought:
      case LogKind.note:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        );
    }
  }
}

/// What a running step looks like: enough shape to read as "busy", not enough
/// to look like content.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.pulse, required this.isDark});

  final Animation<double> pulse;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final tone = AppInk.tertiary(isDark)
            .withValues(alpha: 0.10 + 0.10 * pulse.value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final width in [0.7, 0.4])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.x1 + 2),
                child: FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(AppRadius.chip - 4),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
              : AppInk.tertiary(isDark),
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
          text: '变化 ${evidence.changes.length} 行',
          color: AppInk.secondary(isDark),
        ),
      if (evidence.image != null)
        _Chip(text: '截图', color: AppInk.secondary(isDark)),
      if (evidence.elapsedMs != null)
        Text(
          '${evidence.elapsedMs}ms',
          style: AppType.micro.copyWith(
            color: AppInk.tertiary(isDark),
            fontWeight: FontWeight.w400,
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpace.x1 + 2,
      runSpacing: AppSpace.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
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
        borderRadius: BorderRadius.circular(AppRadius.chip - 3),
      ),
      child: Text(
        text,
        style: AppType.micro.copyWith(color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Everything behind the arrow: what changed, what the layer noted, the shot.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.evidence,
    required this.detail,
    required this.isDark,
  });

  final StepEvidence? evidence;
  final String? detail;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = AppInk.secondary(isDark);
    final changes = evidence?.changes ?? const <String>[];
    final parts = <Widget>[];

    if (evidence?.urlChanged == true) {
      parts.add(_Line(
        label: '地址',
        value: '${evidence!.urlBefore} → ${evidence!.urlAfter}',
        muted: muted,
      ));
    }
    if (changes.isNotEmpty) {
      parts.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x2,
            vertical: AppSpace.x1 + 2,
          ),
          decoration: BoxDecoration(
            color: AppInk.sunken(isDark),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in changes.take(12))
                Text(
                  line,
                  style: AppType.caption.copyWith(
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
                Text(
                  '…还有 ${changes.length - 12} 行',
                  style: AppType.caption.copyWith(color: AppInk.tertiary(isDark)),
                ),
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
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Image.memory(
          base64Decode(image),
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => Text(
            '截图无法显示',
            style: AppType.caption.copyWith(color: muted),
          ),
        ),
      ));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.x1 + 2),
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
        Text(label, style: AppType.caption.copyWith(color: muted)),
        const SizedBox(width: AppSpace.x1 + 2),
        Expanded(
          child: Text(
            value,
            style: AppType.caption.copyWith(color: muted, height: 1.5),
          ),
        ),
      ],
    );
  }
}
