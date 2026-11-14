import 'dart:math' as math;

/// One quad from `DOM.getContentQuads`, in page coordinates.
class Quad {
  const Quad(this.points);

  /// Four x/y pairs, clockwise from the top-left.
  final List<double> points;

  double get left => points[0];
  double get top => points[1];

  double get width => math.max(
        math.max(
          (points[2] - points[0]).abs(),
          (points[4] - points[6]).abs(),
        ),
        0,
      );

  double get height => math.max(
        math.max(
          (points[5] - points[1]).abs(),
          (points[7] - points[3]).abs(),
        ),
        0,
      );

  double get area => width * height;

  /// The quad's centre, in the same coordinates the quad came in.
  ({double x, double y}) get center => (
        x: (points[0] + points[2] + points[4] + points[6]) / 4,
        y: (points[1] + points[3] + points[5] + points[7]) / 4,
      );

  /// Moves the quad from page coordinates into viewport coordinates.
  Quad toViewport(double scrollX, double scrollY) => Quad([
        for (var index = 0; index < points.length; index++)
          index.isEven ? points[index] - scrollX : points[index] - scrollY,
      ]);

  static Quad? fromRaw(Object? raw) {
    if (raw is! List || raw.length < 8) return null;
    final points = <double>[];
    for (final value in raw) {
      if (value is num) {
        points.add(value.toDouble());
      } else {
        return null;
      }
    }
    return Quad(points);
  }

  /// Builds the quad from `DOM.getBoxModel`, whose `content` field is
  /// `[x, y, x, y, x, y, x, y]` laid out the same way.
  static Quad? fromBoxModel(List<double> content) {
    if (content.length < 8) return null;
    return Quad(content.sublist(0, 8));
  }
}

/// Where the page is scrolled, so page coordinates can become viewport ones.
class ScrollOffset {
  const ScrollOffset(this.x, this.y, {this.width = 0, this.height = 0});

  static const ScrollOffset zero = ScrollOffset(0, 0);

  final double x;
  final double y;

  /// The visible area, in CSS pixels. Zero when the page could not be measured.
  final double width;
  final double height;

  bool get isKnown => width > 0 && height > 0;

  /// Whether a viewport point is on screen.
  ///
  /// An event dispatched outside this box reaches nothing: the page never sees
  /// it, no handler runs, and the action looks like a dead button. Knowing the
  /// box is what lets the layer scroll first instead of firing into the void.
  bool contains(double pointX, double pointY) {
    if (!isKnown) return true;
    return pointX >= 0 && pointY >= 0 && pointX <= width && pointY <= height;
  }

  factory ScrollOffset.fromLayoutMetrics(Map<String, Object?> metrics) {
    final viewport = metrics['cssLayoutViewport'] ?? metrics['layoutViewport'];
    if (viewport is! Map) return ScrollOffset.zero;
    return ScrollOffset(
      (viewport['pageX'] as num?)?.toDouble() ?? 0,
      (viewport['pageY'] as num?)?.toDouble() ?? 0,
      width: (viewport['clientWidth'] as num?)?.toDouble() ?? 0,
      height: (viewport['clientHeight'] as num?)?.toDouble() ?? 0,
    );
  }
}
