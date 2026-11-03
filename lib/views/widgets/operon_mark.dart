import 'package:flutter/material.dart';

/// The Operon monogram: a ring with a diagonal slash, matching the launcher
/// icon. Drawn instead of a stock icon so the browser's own controls read as
/// part of the same brand rather than a generic "tap here" hand.
class OperonMark extends StatelessWidget {
  final double size;
  final Color color;

  const OperonMark({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OperonMarkPainter(color),
    );
  }
}

class _OperonMarkPainter extends CustomPainter {
  final Color color;

  const _OperonMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = s * 0.33;

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.14;
    final slash = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.square;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(center, radius, ring);

    final dx = radius * 1.03;
    final start = Offset(center.dx - dx, center.dy + dx);
    final end = Offset(center.dx + dx, center.dy - dx);
    canvas.drawLine(start, end, slash);

    // Cut a small gap on both sides of the slash so the ring reads as the
    // split monogram from the launcher icon, not a crossed-out circle.
    final gap = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.25
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(start, end, gap);
    canvas.drawLine(start, end, slash);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OperonMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
