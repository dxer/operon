import 'package:flutter/material.dart';

/// Operon's "Operator" palette.
///
/// Browser chrome stays neutral graphite/warm paper; a single copper accent is
/// reserved for the agent and primary actions. Semantic colors are deliberately
/// desaturated so status is readable without turning the UI into a dashboard.
class AppTheme {
  // Brand / action
  static const Color primary = Color(0xFFBA6030); // Operator copper
  static const Color accent = Color(0xFF2A8563); // Sage success
  static const Color warning = Color(0xFFB07A24); // Ochre warning
  static const Color danger = Color(0xFFC0453C); // Brick danger
  static const Color neutral = Color(0xFF7E786D); // Mid warm grey

  // Dark Palette
  static const Color darkBg = Color(0xFF111214);
  static const Color darkCard = Color(0xFF1A1C20);
  static const Color darkBorder = Color(0xFF2B2E34);
  static const Color darkInput = Color(0xFF14161A);
  static const Color darkOnSurface = Color(0xFFF2EFE8);
  static const Color darkMuted = Color(0xFFA7A29A);

  // Light Palette
  static const Color lightBg = Color(0xFFF6F4EF);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE6E2D9);
  static const Color lightInput = Color(0xFFF1EDE5);
  static const Color lightOnSurface = Color(0xFF17181A);
  static const Color lightMuted = Color(0xFF6E6A62);

  /// Decoration for text fields that already sit inside a custom-drawn box.
  ///
  /// The global [InputDecorationTheme] fills and outlines inputs; leaving just
  /// `border: InputBorder.none` still lets `enabledBorder`/`focusedBorder`
  /// through and produces a box inside a box.
  static const InputDecoration flatInput = InputDecoration(
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.zero,
  );

  static const Map<TargetPlatform, PageTransitionsBuilder> _pageTransitions = {
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
  };

  // --- Dark Theme ---
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    primaryColor: primary,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme:
        const PageTransitionsTheme(builders: _pageTransitions),
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.black,
      error: danger,
      onError: Colors.white,
      surface: darkCard,
      onSurface: darkOnSurface,
      surfaceContainerHighest: darkInput,
      outline: darkBorder,
      outlineVariant: darkBorder,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 8,
      iconTheme: IconThemeData(color: darkOnSurface, size: 22),
      titleTextStyle: TextStyle(
        color: darkOnSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkBorder, width: 0.8),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: darkOnSurface.withValues(alpha: 0.07),
      thickness: 0.7,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkInput,
      hintStyle: TextStyle(
        color: darkOnSurface.withValues(alpha: 0.36),
        fontSize: 13.5,
      ),
      floatingLabelStyle: const TextStyle(color: primary, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(darkOnSurface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? primary : Colors.white24,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF23252A),
      elevation: 6,
      contentTextStyle: const TextStyle(
        color: darkOnSurface,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkCard,
      modalBackgroundColor: darkCard,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkCard,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: darkOnSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: darkOnSurface.withValues(alpha: 0.8),
        fontSize: 13.5,
        height: 1.5,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: darkMuted,
      textColor: darkOnSurface,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Colors.transparent,
      circularTrackColor: Colors.transparent,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.35),
      selectionHandleColor: primary,
    ),
  );

  // --- Light Theme ---
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    primaryColor: primary,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme:
        const PageTransitionsTheme(builders: _pageTransitions),
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.black,
      error: danger,
      onError: Colors.white,
      surface: lightCard,
      onSurface: lightOnSurface,
      surfaceContainerHighest: lightInput,
      outline: lightBorder,
      outlineVariant: lightBorder,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 8,
      iconTheme: IconThemeData(color: lightOnSurface, size: 22),
      titleTextStyle: TextStyle(
        color: lightOnSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: lightCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: lightBorder, width: 0.8),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x14000000),
      thickness: 0.7,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightInput,
      hintStyle: TextStyle(
        color: lightOnSurface.withValues(alpha: 0.38),
        fontSize: 13.5,
      ),
      floatingLabelStyle: const TextStyle(color: primary, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : const Color(0xFFD8D2C8),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF23252A),
      elevation: 6,
      contentTextStyle: const TextStyle(
        color: darkOnSurface,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: lightCard,
      modalBackgroundColor: lightCard,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: lightCard,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: lightOnSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: Color(0xB3000000),
        fontSize: 13.5,
        height: 1.5,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: lightMuted,
      textColor: lightOnSurface,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Colors.transparent,
      circularTrackColor: Colors.transparent,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.28),
      selectionHandleColor: primary,
    ),
  );
}
