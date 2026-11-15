/// What the layer is about to touch.
///
/// The size is part of the message on purpose: a cursor alone says "something
/// happens here", a ring around the element says "this is the thing it is about
/// to operate". The second sentence is the one a person watching actually
/// needs, and only the layer knows it — the box is measured before the event is
/// dispatched.
///
/// Coordinates are CSS pixels relative to the viewport, exactly as the input
/// event that follows them. Turning them into screen pixels is the UI's job:
/// they still have to be multiplied by the page's zoom.
class GestureTarget {
  const GestureTarget({
    required this.x,
    required this.y,
    this.width = 0,
    this.height = 0,
    required this.label,
  });

  /// The point the event lands on.
  final double x;
  final double y;

  /// The element's box. Zero when the node reported no area, in which case the
  /// overlay draws the cursor without a ring rather than inventing a size.
  final double width;
  final double height;

  /// What the element is called (`button "发送"`), shown beside the cursor.
  final String label;

  bool get hasBox => width > 1 && height > 1;

  @override
  String toString() => 'GestureTarget($label at $x,$y ${width}x$height)';
}
