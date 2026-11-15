import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The four scales every screen draws from.
///
/// The colours in [AppTheme] were already one system; the sizes were not —
/// 22 font sizes, 18 corner radii and three tiers of grey invented per widget.
/// That is what makes an interface read as assembled rather than designed, and
/// it is not fixable by choosing nicer colours.
///
/// So: a screen may only use the values below. If a design needs a size that is
/// not here, the design is wrong, not the scale. Files that adopt these are
/// listed in `test/design_system_test.dart`, which fails if a stray value
/// creeps back in.
///
/// Type: seven sizes, each with a line height suited to Chinese.
///
/// The line heights matter as much as the sizes: Han characters fill their
/// em box in a way Latin text does not, so the default ~1.17 that Flutter uses
/// for unstyled text reads as cramped no matter how large the type is.
class AppType {
  AppType._();

  /// Only the start page wordmark. Nothing else is 28.
  static const TextStyle display = TextStyle(
    fontSize: 28,
    height: 1.21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  /// A panel or page title.
  static const TextStyle title = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// A card heading, a list row's main line.
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 1.41,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Body copy, input text, button labels.
  static const TextStyle body = TextStyle(fontSize: 15, height: 1.5);

  /// Secondary labels and metadata that has to stay readable.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    height: 1.38,
    fontWeight: FontWeight.w500,
  );

  /// Timestamps, domains, step metadata.
  static const TextStyle caption = TextStyle(fontSize: 12, height: 1.33);

  /// Badges. Four characters or fewer, never a sentence.
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    height: 1.27,
    fontWeight: FontWeight.w600,
  );
}

/// Spacing: a 4-point grid. Anything not in this list is a typo.
class AppSpace {
  AppSpace._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;

  /// Horizontal page margin.
  static const double page = 16;

  /// Height of a settings row.
  static const double row = 56;

  /// Minimum touch target, per platform guidance.
  static const double tap = 44;

  /// Height of the address pill and the composer pill.
  static const double pill = 48;
}

/// Corners: five steps instead of the eighteen that grew here by accident.
class AppRadius {
  AppRadius._();

  /// Chips, code spans, small buttons.
  static const double chip = 8;

  /// Site icons.
  static const double icon = 13;

  /// Cards and inputs.
  static const double card = 16;

  /// Sheets and dialogs.
  static const double sheet = 20;

  /// Fully rounded: address bar, search box, composer.
  static const double pill = 999;
}

/// Text ink: three levels, resolved per brightness.
///
/// Widgets used to reach for `Colors.white38` and friends, which is where the
/// contrast inconsistencies came from — on `#292929` that grey is about 4.0:1,
/// under AA for the 11–12sp text it was most often used on. [tertiary] is the
/// floor: nothing smaller than 11sp may use anything dimmer.
class AppInk {
  AppInk._();

  static Color primary(bool isDark) =>
      isDark ? AppTheme.darkOnSurface : AppTheme.lightOnSurface;

  static Color secondary(bool isDark) => primary(isDark).withValues(alpha: 0.70);

  static Color tertiary(bool isDark) => primary(isDark).withValues(alpha: 0.55);

  /// Hairline between regions. One width, one alpha, everywhere.
  static Color hairline(bool isDark) =>
      isDark ? const Color(0x17FFFFFF) : const Color(0x14000000);

  /// A surface that is one step in front of the page background.
  static Color raised(bool isDark) =>
      isDark ? AppTheme.darkCard : AppTheme.lightCard;

  /// A surface one step further in: inputs, tiles, chips.
  static Color sunken(bool isDark) =>
      isDark ? AppTheme.darkInput : AppTheme.lightInput;

  /// The accent at 10–14% for selected states, agent bubbles and busy marks.
  /// Without it, blue only ever appears as text, which reads as a link.
  static Color accentTint(bool isDark) => AppTheme.primaryOf(isDark)
      .withValues(alpha: isDark ? 0.16 : 0.10);
}

/// Strokes. 0.8 was used before, which lands on fractional physical pixels and
/// renders unevenly at some densities.
class AppStroke {
  AppStroke._();

  static const double hairline = 1;
  static const BorderSide side = BorderSide(width: hairline);
}
