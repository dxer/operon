import 'package:flutter/services.dart';

/// Single switch for all UI haptics.
///
/// Widgets should call this instead of [HapticFeedback] so the user can turn
/// tactile feedback off from browsing settings.
class HapticService {
  HapticService._();

  static bool enabled = true;

  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
