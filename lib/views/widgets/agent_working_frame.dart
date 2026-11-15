import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// A border around the page while the agent is working on it.
///
/// The status strip says what the agent is doing; this says where. Without it,
/// a run that moved to another tab looks identical to a run that hung. It is
/// drawn, never touched: `IgnorePointer`, no layout space, no hit testing.
class AgentWorkingFrame extends StatefulWidget {
  const AgentWorkingFrame({super.key, this.period = const Duration(milliseconds: 1600)});

  /// One full fade, in and out.
  final Duration period;

  @override
  State<AgentWorkingFrame> createState() => _AgentWorkingFrameState();
}

class _AgentWorkingFrameState extends State<AgentWorkingFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppTheme.primaryOf(isDark);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 0.35 → 0.85: visible enough to notice, quiet enough to read behind.
        final opacity = 0.35 + 0.5 * _controller.value;
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: color.withValues(alpha: opacity),
                width: 2,
              ),
              // A soft halo inward so the edge reads as light, not as a box.
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: opacity * 0.35),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
