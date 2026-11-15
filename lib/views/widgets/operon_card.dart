import 'package:flutter/material.dart';

import '../../config/app_tokens.dart';

/// A rounded surface that holds rows, tiles and sections.
///
/// The background is painted by a [Material], never by a [Container]. Every
/// ListTile — including the row a `SwitchListTile`, a `CheckboxListTile` or an
/// `ExpansionTile` header builds for itself — paints its ink on the nearest
/// Material ancestor. A colored `DecoratedBox` in between puts that ink *under*
/// the background, so the ripple disappears; Flutter asserts on exactly this
/// since 3.47, and at runtime it is a tap that looks dead.
///
/// The border and the rounded corners stay on the outer box, so the surface
/// still reads as a card and nothing paints outside it.
class OperonCard extends StatelessWidget {
  const OperonCard({
    super.key,
    required this.color,
    required this.child,
    this.borderColor,
    this.padding,
    this.radius,
    this.borderRadius,
    this.height,
  });

  /// The surface color. Use the theme's card color, not a hand-picked one.
  final Color color;
  final Widget child;

  /// Painted as a hairline border. Null draws no border.
  final Color? borderColor;

  /// Space between the surface edge and the content, inside the background.
  final EdgeInsetsGeometry? padding;

  /// Defaults to [AppRadius.icon], the card size used across settings.
  final double? radius;

  /// Overrides [radius] when the corners are not all the same — a bottom
  /// sheet surface is rounded only at the top.
  final BorderRadiusGeometry? borderRadius;

  final double? height;

  @override
  Widget build(BuildContext context) {
    final shape = borderRadius ?? BorderRadius.circular(radius ?? AppRadius.icon);
    final border = borderColor;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: shape,
        border:
            border == null ? null : Border.all(color: border, width: AppStroke.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: color,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}
