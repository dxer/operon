import 'package:flutter/material.dart';

/// The panel's frame. It owns exactly one number: how tall the panel is.
///
/// Only the handle changes that number. Scrolling the transcript scrolls the
/// transcript.
///
/// The previous version used `DraggableScrollableSheet`, whose contract is the
/// opposite: the sheet's height is driven by the *content's* scroll offset. So a
/// thumb dragged up over the conversation grew the window first and moved the
/// text later — the reply shifted under the finger, and a page you were reading
/// jumped when you only meant to scroll it. Two different gestures were sharing
/// one drag, and the one with the smaller range won.
///
/// Snapping stays: three resting heights with names are easier to use than an
/// infinite range of accidental ones.
class AgentSheetFrame extends StatefulWidget {
  const AgentSheetFrame({super.key, required this.builder});

  /// The panel, given the two callbacks its handle needs: the drag distance in
  /// logical pixels (positive grows the panel), and "the finger is up".
  final Widget Function(
    ValueChanged<double> onHandleDrag,
    VoidCallback onHandleDragEnd,
  ) builder;

  static const double minFactor = 0.38;
  static const double initialFactor = 0.6;
  static const double maxFactor = 0.9;

  /// Where the panel settles when the finger lifts: enough to read an answer,
  /// enough to see the page behind it, and as tall as it gets.
  static const List<double> snaps = [initialFactor, 0.75, maxFactor];

  @override
  State<AgentSheetFrame> createState() => _AgentSheetFrameState();
}

class _AgentSheetFrameState extends State<AgentSheetFrame> {
  double _factor = AgentSheetFrame.initialFactor;
  bool _dragging = false;

  /// The space the panel may use. Measured in `build` rather than assumed: the
  /// route, a split screen and a future `useSafeArea` all change the number, and
  /// a height computed from the raw screen size would overflow the box it is
  /// drawn in.
  double _available = 0;

  void _onHandleDrag(double growBy) {
    if (_available <= 0) return;
    setState(() {
      _dragging = true;
      _factor = (_factor + growBy / _available).clamp(
        AgentSheetFrame.minFactor,
        AgentSheetFrame.maxFactor,
      );
    });
  }

  void _onHandleDragEnd() {
    final nearest = AgentSheetFrame.snaps.reduce(
      (a, b) => (a - _factor).abs() <= (b - _factor).abs() ? a : b,
    );
    setState(() {
      _dragging = false;
      _factor = nearest;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _available = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return AnimatedContainer(
          // Instant under the finger, animated only for the snap: a resize that
          // eases while you drag reads as lag.
          duration:
              _dragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: _available * _factor,
          child: widget.builder(_onHandleDrag, _onHandleDragEnd),
        );
      },
    );
  }
}
