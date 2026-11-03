import 'package:flutter/material.dart';

/// Black and white register, with PPL green used only as the accent.
class AppTheme {
  AppTheme._();

  /// Brand green. Dark enough for white text on buttons.
  static const Color pplGreen = Color(0xFF16803C);

  /// Brighter green for dark backgrounds, where [pplGreen] would disappear.
  static const Color pplGreenBright = Color(0xFF3DDC84);

  static const Color black = Color(0xFF111111);
  static const Color white = Color(0xFFFFFFFF);
  static const Color rail = Color(0xFF0C0C0C);

  static const double _radius = 16;

  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final green = dark ? pplGreenBright : pplGreen;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: green,
      onPrimary: dark ? black : white,
      primaryContainer: dark ? const Color(0xFF14532D) : const Color(0xFFE7F6EC),
      onPrimaryContainer: dark ? const Color(0xFFD1FAE5) : const Color(0xFF14532D),
      secondary: dark ? const Color(0xFFA3A3A3) : const Color(0xFF3F3F3F),
      onSecondary: dark ? black : white,
      secondaryContainer: dark ? const Color(0xFF262626) : const Color(0xFFF2F2F2),
      onSecondaryContainer: dark ? white : black,
      tertiary: green,
      onTertiary: dark ? black : white,
      tertiaryContainer: dark ? const Color(0xFF14532D) : const Color(0xFFE7F6EC),
      onTertiaryContainer: dark ? const Color(0xFFD1FAE5) : const Color(0xFF14532D),
      error: const Color(0xFFDC2626),
      onError: white,
      errorContainer: dark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2),
      onErrorContainer: dark ? const Color(0xFFFECACA) : const Color(0xFF7F1D1D),
      surface: dark ? const Color(0xFF111111) : white,
      onSurface: dark ? const Color(0xFFF5F5F5) : black,
      onSurfaceVariant: dark ? const Color(0xFFA3A3A3) : const Color(0xFF525252),
      outline: dark ? const Color(0xFF3A3A3A) : const Color(0xFFD4D4D4),
      outlineVariant: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
      shadow: black,
      scrim: const Color(0x99000000),
      inverseSurface: dark ? white : black,
      onInverseSurface: dark ? black : white,
      inversePrimary: dark ? pplGreen : pplGreenBright,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: dark ? const Color(0xFF161616) : white,
      surfaceContainerLow: dark ? const Color(0xFF1C1C1C) : const Color(0xFFFAFAFA),
      surfaceContainer: dark ? const Color(0xFF232323) : const Color(0xFFF3F3F3),
      surfaceContainerHigh: dark ? const Color(0xFF2A2A2A) : const Color(0xFFECECEC),
      surfaceContainerHighest: dark ? const Color(0xFF333333) : const Color(0xFFE4E4E4),
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      splashFactory: InkSparkle.splashFactory,
    );

    final ink = colorScheme.onSurface;
    final textTheme = base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: ink,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: ink),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: ink),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        titleTextStyle: textTheme.headlineSmall,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(64, 54),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          selectedBackgroundColor: green,
          selectedForegroundColor: colorScheme.onPrimary,
          foregroundColor: ink,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: green, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: rail,
        indicatorColor: green,
        indicatorShape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimary),
        unselectedIconTheme: const IconThemeData(color: Color(0xFFD4D4D4)),
        selectedLabelTextStyle: TextStyle(color: green, fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelTextStyle: const TextStyle(color: Color(0xFFA3A3A3), fontWeight: FontWeight.w600, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? green : colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? green : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: green),
    );
  }
}
