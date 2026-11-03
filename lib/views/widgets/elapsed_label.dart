import 'dart:async';
import 'package:flutter/material.dart';

/// Live `m:ss` counter for a running agent task.
///
/// A task can sit in a slow model call or a page transition for many seconds;
/// a ticking number is the cheapest way to show the app is still working and
/// how long the user has been waiting. It never animates, so it stays readable
/// with reduced motion enabled.
class ElapsedLabel extends StatefulWidget {
  final DateTime startedAt;
  final Color? color;
  final double fontSize;

  /// Injectable wall clock; widget tests advance it instead of sleeping.
  final DateTime Function() clock;

  const ElapsedLabel({
    super.key,
    required this.startedAt,
    this.color,
    this.fontSize = 11,
    this.clock = DateTime.now,
  });

  /// `m:ss` under an hour, `h:mm:ss` above it.
  static String format(Duration duration) {
    final value = duration.isNegative ? Duration.zero : duration;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final ss = seconds.toString().padLeft(2, '0');
    if (value.inHours > 0) {
      return '${value.inHours}:${minutes.toString().padLeft(2, '0')}:$ss';
    }
    return '$minutes:$ss';
  }

  @override
  State<ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<ElapsedLabel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.clock().difference(widget.startedAt);
    final text = ElapsedLabel.format(elapsed);
    return Text(
      text,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: widget.color,
      ),
    );
  }
}
