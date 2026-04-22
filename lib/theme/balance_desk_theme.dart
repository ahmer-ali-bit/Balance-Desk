import 'package:flutter/material.dart';

class BalanceDeskTheme {
  BalanceDeskTheme._();

  static const ColorScheme _desktopColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF56C48D),
    onPrimary: Color(0xFF071B12),
    primaryContainer: Color(0xFF153728),
    onPrimaryContainer: Color(0xFFD5F5E2),
    secondary: Color(0xFF3F8D69),
    onSecondary: Color(0xFFF2FBF5),
    secondaryContainer: Color(0xFF183C2D),
    onSecondaryContainer: Color(0xFFD6F0E1),
    tertiary: Color(0xFF4DB889),
    onTertiary: Color(0xFF071B12),
    tertiaryContainer: Color(0xFF133427),
    onTertiaryContainer: Color(0xFFD5F5E2),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3A0A07),
    errorContainer: Color(0xFF5F1914),
    onErrorContainer: Color(0xFFFFDAD4),
    surface: Color(0xFF0C241B),
    onSurface: Color(0xFFF1F7F3),
    onSurfaceVariant: Color(0xFF92B3A1),
    outline: Color(0xFF194233),
    outlineVariant: Color(0xFF15362A),
    surfaceContainerLowest: Color(0xFF06110D),
    surfaceContainerLow: Color(0xFF0A1B15),
    surfaceContainer: Color(0xFF0E2219),
    surfaceContainerHigh: Color(0xFF133126),
    surfaceContainerHighest: Color(0xFF214438),
    inverseSurface: Color(0xFFE7F2EB),
    onInverseSurface: Color(0xFF10221A),
    inversePrimary: Color(0xFF1E5D45),
    scrim: Colors.black,
    shadow: Colors.black,
  );
  static const Color _desktopScaffoldBackgroundColor = Color(0xFF071611);
  static const Color _desktopCanvasColor = Color(0xFF081610);
  static const Color _desktopAppBarBackgroundColor = Color(0xFF0A1D16);
  static const Color _desktopDrawerBackgroundColor = Color(0xFF081911);
  static const Color _desktopInputFillColor = Color(0xFF05100C);

  static ThemeData lightTheme() => _buildMobileTheme();

  static ThemeData darkTheme() => _buildMobileTheme();

  static ThemeData desktopTheme() {
    final colorScheme = _desktopColorScheme;

    final baseText = Typography.material2021().white;
    final textTheme = baseText
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        )
        .copyWith(
          headlineSmall: baseText.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          titleLarge: baseText.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          titleMedium: baseText.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleSmall: baseText.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: baseText.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          bodyMedium: baseText.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          labelLarge: baseText.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          labelMedium: baseText.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _desktopScaffoldBackgroundColor,
      canvasColor: _desktopCanvasColor,
      splashFactory: InkRipple.splashFactory,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _desktopAppBarBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _desktopInputFillColor,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          backgroundColor: colorScheme.surfaceContainerLow,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: _desktopDrawerBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: textTheme.labelMedium,
        selectedColor: colorScheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll<Color?>(
          colorScheme.surfaceContainerHighest,
        ),
        headingTextStyle: textTheme.titleSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        horizontalMargin: 12,
        columnSpacing: 18,
        dividerThickness: 1,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData _buildMobileTheme() {
    final colorScheme = _desktopColorScheme;
    final textBase = Typography.material2021().white;
    final textTheme = textBase
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        )
        .copyWith(
          headlineSmall: textBase.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleLarge: textBase.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: textBase.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: textBase.bodyLarge?.copyWith(height: 1.35),
          bodyMedium: textBase.bodyMedium?.copyWith(height: 1.35),
          labelLarge: textBase.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const scaffoldColor = _desktopScaffoldBackgroundColor;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldColor,
      canvasColor: _desktopCanvasColor,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _desktopAppBarBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _desktopInputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: _desktopDrawerBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: textTheme.labelMedium,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll<Color?>(
          colorScheme.surfaceContainerHigh,
        ),
        dividerThickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
