import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1D9BF0); // Twitter/X Blue
  static const Color accent = Color(0xFF00BA7C); // Success Green
  static const Color warning = Color(0xFFFF7A00); // Warning Amber

  // Dark Palette
  static const Color darkBg = Color(0xFF0F141C);
  static const Color darkCard = Color(0xFF1A212B);
  static const Color darkBorder = Color(0xFF2A313B);
  static const Color darkInput = Color(0xFF161D26);

  // Light Palette
  static const Color lightBg = Color(0xFFF7F9FA);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE3E8EC);
  static const Color lightInput = Color(0xFFEFF3F4);

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
      surface: darkCard,
      onSurface: Colors.white,
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
      iconTheme: IconThemeData(color: Colors.white, size: 22),
      titleTextStyle: TextStyle(
        color: Colors.white,
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
      color: Colors.white.withValues(alpha: 0.07),
      thickness: 0.7,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkInput,
      hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.32), fontSize: 13.5),
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
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? primary : Colors.white24,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF232B36),
      elevation: 6,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
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
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 13.5,
        height: 1.5,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white70,
      textColor: Colors.white,
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
      surface: lightCard,
      onSurface: Color(0xFF0F141C),
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
      iconTheme: IconThemeData(color: Color(0xFF0F141C), size: 22),
      titleTextStyle: TextStyle(
        color: Color(0xFF0F141C),
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
      hintStyle: const TextStyle(color: Color(0x66000000), fontSize: 13.5),
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
            : const Color(0xFFD5DCE2),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1F2937),
      elevation: 6,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
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
        color: Color(0xFF0F141C),
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
      iconColor: Color(0xFF536471),
      textColor: Color(0xFF0F141C),
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
