import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One gesture to draw: where it lands, and what it hits.
class GesturePulse {
  const GesturePulse({
    required this.at,
    required this.label,
    required this.seq,
  });

  /// The point in logical pixels, above the WebView.
  final Offset at;

  /// What the element is called, shown briefly beside the cursor.
  final String label;

  /// Increases per gesture, so two pulses on the same point still animate.
  final int seq;
}

/// Draws the gesture the control layer is about to dispatch.
///
/// The layer computes the point before any event leaves, so this never claims a
/// place the click did not go. It lives above the WebView rather than inside the
/// page: injecting a cursor node into a document is detectable and pollutes the
/// DOM an agent is reading, and the animation quality of the page's own
/// compositor is not ours to rely on.
class GestureOverlay extends StatefulWidget {
  const GestureOverlay({super.key, required this.pulse});

  final ValueListenable<GesturePulse?> pulse;

  @override
  State<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends State<GestureOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 640);

  /// Created in [initState], not lazily: a controller built inside `dispose`
  /// registers a ticker on a deactivated element and throws.
  late final AnimationController _controller;

  Offset? _from;
  Offset? _to;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        // Clears the label once the gesture is over, so nothing stays on top
        // of the page.
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _label = '');
        }
      });
    widget.pulse.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(GestureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) {
      oldWidget.pulse.removeListener(_onPulse);
      widget.pulse.addListener(_onPulse);
    }
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_onPulse);
    _controller.dispose();
    super.dispose();
  }

  void _onPulse() {
    final pulse = widget.pulse.value;
    if (pulse == null || !mounted) return;
    setState(() {
      _from = _to;
      _to = pulse.at;
      _label = pulse.label;
    });
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final target = _to;
    if (target == null) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final raw = _controller.value;
          // The cursor glides in the first half of the animation and stays put
          // while the ripple finishes, so the eye lands before the ring fades.
          final glide = Curves.easeOutCubic.transform(math.min(1, raw / 0.55));
          final origin = _from;
          final position = origin == null
              ? target
              : Offset.lerp(origin, target, glide)!;

          final ripple = (raw / 0.7).clamp(0.0, 1.0);
          final rippleOpacity = raw >= 0.7 ? 0.0 : (1 - ripple) * 0.85;
          final labelOpacity = raw < 0.5 ? 1.0 : (1 - (raw - 0.5) * 1.6).clamp(0.0, 1.0);

          return Stack(
            children: [
              if (rippleOpacity > 0)
                Positioned(
                  left: position.dx - 30,
                  top: position.dy - 30,
                  child: CustomPaint(
                    size: const Size(60, 60),
                    painter: _RipplePainter(
                      progress: ripple,
                      color: color.withValues(alpha: rippleOpacity),
                    ),
                  ),
                ),
              Positioned(
                left: position.dx - 11,
                top: position.dy - 11,
                child: _Cursor(color: color),
              ),
              if (_label.isNotEmpty && labelOpacity > 0)
                Positioned(
                  left: position.dx + 14,
                  top: position.dy - 30,
                  child: Opacity(
                    opacity: labelOpacity,
                    child: _Label(text: _label),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Cursor extends StatelessWidget {
  const _Cursor({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.42),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.75),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF2292929) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE1DFDD),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          color: isDark ? const Color(0xFFC8C6C4) : const Color(0xFF605E5C),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 8 + 22 * progress;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: color.a * 0.25),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
