import 'package:flutter/material.dart';

import 'finance_colors.dart';

/// Balance Desk design system — "Modern Professional Ledger".
///
/// Visual identity derived from the brand mark (deep emerald emblem, mint
/// accent, ivory paper). One shared geometry/typography backbone drives both
/// brightnesses; only the color tokens change.
///
/// Light  — warm paper canvas, white cards, deep emerald actions.
/// Dark   — deep green-ink canvas, lifted emerald surfaces, mint actions.
class BalanceDeskTheme {
  BalanceDeskTheme._();

  /// Primary UI typeface (bundled, OFL).
  static const String displayFont = 'Lato';

  /// Face used for ledger amounts and tabular figures (bundled, OFL).
  static const String amountFont = 'IBM Plex Mono';

  // ─────────────────────────────────────────────────────────────
  // Color tokens — light ("Paper Ledger")
  // ─────────────────────────────────────────────────────────────
  static const Color _paperScaffold = Color(0xFFF4F5F0);
  static const Color _paperSurface = Color(0xFFFFFFFF);
  static const Color _paperSurfaceLowest = Color(0xFFFFFFFF);
  static const Color _paperSurfaceLow = Color(0xFFFAFAF7);
  static const Color _paperSurfaceHigh = Color(0xFFEBEDE7);
  static const Color _paperSurfaceHighest = Color(0xFFDFE2D8);
  static const Color _paperInk = Color(0xFF182420);
  static const Color _paperInkVariant = Color(0xFF55645A);
  static const Color _paperOutline = Color(0xFFD9DCD1);
  static const Color _paperOutlineVariant = Color(0xFFE7E9E0);
  static const Color _paperPrimary = Color(0xFF0E5F3D);
  static const Color _paperOnPrimary = Color(0xFFFFFFFF);
  static const Color _paperPrimaryContainer = Color(0xFFE0EFE5);
  static const Color _paperOnPrimaryContainer = Color(0xFF0C4A2F);
  static const Color _paperSecondary = Color(0xFF3F5B4C);
  static const Color _paperOnSecondary = Color(0xFFFFFFFF);
  static const Color _paperSecondaryContainer = Color(0xFFDFE9E1);
  static const Color _paperOnSecondaryContainer = Color(0xFF27402F);
  static const Color _paperTertiary = Color(0xFF8A6D1D);
  static const Color _paperOnTertiary = Color(0xFFFFFFFF);
  static const Color _paperTertiaryContainer = Color(0xFFF1E8CE);
  static const Color _paperOnTertiaryContainer = Color(0xFF5C4A12);
  static const Color _paperError = Color(0xFFC72B4A);
  static const Color _paperOnError = Color(0xFFFFFFFF);
  static const Color _paperErrorContainer = Color(0xFFFBE3E7);
  static const Color _paperOnErrorContainer = Color(0xFF7A1F33);

  // ─────────────────────────────────────────────────────────────
  // Color tokens — dark ("Night Ledger")
  // ─────────────────────────────────────────────────────────────
  static const Color _nightScaffold = Color(0xFF0E1511);
  static const Color _nightSurface = Color(0xFF151F19);
  static const Color _nightSurfaceLowest = Color(0xFF101813);
  static const Color _nightSurfaceLow = Color(0xFF1A2620);
  static const Color _nightSurfaceHigh = Color(0xFF223028);
  static const Color _nightSurfaceHighest = Color(0xFF2C3D33);
  static const Color _nightInk = Color(0xFFE9EFEA);
  static const Color _nightInkVariant = Color(0xFFA5B6AB);
  static const Color _nightOutline = Color(0xFF33463B);
  static const Color _nightOutlineVariant = Color(0xFF223128);
  static const Color _nightPrimary = Color(0xFF5BE0A4);
  static const Color _nightOnPrimary = Color(0xFF05301E);
  static const Color _nightPrimaryContainer = Color(0xFF173B29);
  static const Color _nightOnPrimaryContainer = Color(0xFFA9F0CB);
  static const Color _nightSecondary = Color(0xFF9CC7AE);
  static const Color _nightOnSecondary = Color(0xFF123324);
  static const Color _nightSecondaryContainer = Color(0xFF223B2C);
  static const Color _nightOnSecondaryContainer = Color(0xFFC4E6D0);
  static const Color _nightTertiary = Color(0xFFE3B95B);
  static const Color _nightOnTertiary = Color(0xFF2E2408);
  static const Color _nightTertiaryContainer = Color(0xFF3A2F14);
  static const Color _nightOnTertiaryContainer = Color(0xFFF3DC9C);
  static const Color _nightError = Color(0xFFFB7A95);
  static const Color _nightOnError = Color(0xFF3B0A16);
  static const Color _nightErrorContainer = Color(0xFF47202B);
  static const Color _nightOnErrorContainer = Color(0xFFFFCDD6);

  // ─────────────────────────────────────────────────────────────
  // Public entry points (kept API-compatible with previous theme)
  // ─────────────────────────────────────────────────────────────
  static ThemeData lightTheme() => _buildTheme(Brightness.light);

  static ThemeData darkTheme() => _buildTheme(Brightness.dark);

  /// Compatibility shim — the desktop build now follows the user's theme
  /// mode like every other platform.
  static ThemeData desktopTheme() => lightTheme();

  // ─────────────────────────────────────────────────────────────
  // Schemes
  // ─────────────────────────────────────────────────────────────
  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _paperPrimary,
    onPrimary: _paperOnPrimary,
    primaryContainer: _paperPrimaryContainer,
    onPrimaryContainer: _paperOnPrimaryContainer,
    secondary: _paperSecondary,
    onSecondary: _paperOnSecondary,
    secondaryContainer: _paperSecondaryContainer,
    onSecondaryContainer: _paperOnSecondaryContainer,
    tertiary: _paperTertiary,
    onTertiary: _paperOnTertiary,
    tertiaryContainer: _paperTertiaryContainer,
    onTertiaryContainer: _paperOnTertiaryContainer,
    error: _paperError,
    onError: _paperOnError,
    errorContainer: _paperErrorContainer,
    onErrorContainer: _paperOnErrorContainer,
    surface: _paperSurface,
    onSurface: _paperInk,
    onSurfaceVariant: _paperInkVariant,
    outline: _paperOutline,
    outlineVariant: _paperOutlineVariant,
    surfaceContainerLowest: _paperSurfaceLowest,
    surfaceContainerLow: _paperSurfaceLow,
    surfaceContainer: Color(0xFFF2F3EE),
    surfaceContainerHigh: _paperSurfaceHigh,
    surfaceContainerHighest: _paperSurfaceHighest,
    inverseSurface: Color(0xFF1B2921),
    onInverseSurface: Color(0xFFEDF3ED),
    inversePrimary: Color(0xFF7EE2AC),
    scrim: Color(0xFF0E1511),
    shadow: Color(0xFF182420),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _nightPrimary,
    onPrimary: _nightOnPrimary,
    primaryContainer: _nightPrimaryContainer,
    onPrimaryContainer: _nightOnPrimaryContainer,
    secondary: _nightSecondary,
    onSecondary: _nightOnSecondary,
    secondaryContainer: _nightSecondaryContainer,
    onSecondaryContainer: _nightOnSecondaryContainer,
    tertiary: _nightTertiary,
    onTertiary: _nightOnTertiary,
    tertiaryContainer: _nightTertiaryContainer,
    onTertiaryContainer: _nightOnTertiaryContainer,
    error: _nightError,
    onError: _nightOnError,
    errorContainer: _nightErrorContainer,
    onErrorContainer: _nightOnErrorContainer,
    surface: _nightSurface,
    onSurface: _nightInk,
    onSurfaceVariant: _nightInkVariant,
    outline: _nightOutline,
    outlineVariant: _nightOutlineVariant,
    surfaceContainerLowest: _nightSurfaceLowest,
    surfaceContainerLow: _nightSurfaceLow,
    surfaceContainer: Color(0xFF182119),
    surfaceContainerHigh: _nightSurfaceHigh,
    surfaceContainerHighest: _nightSurfaceHighest,
    inverseSurface: Color(0xFFE4EAE4),
    onInverseSurface: Color(0xFF1B2921),
    inversePrimary: Color(0xFF0E5F3D),
    scrim: Colors.black,
    shadow: Colors.black,
  );

  // ─────────────────────────────────────────────────────────────
  // Typography
  // ─────────────────────────────────────────────────────────────
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = const TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 18,
        height: 1.32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 15,
        height: 1.32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 15,
        height: 1.42,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 13.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
      labelMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 10.5,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    );
    return base.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Theme builder
  // ─────────────────────────────────────────────────────────────
  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight ? _lightScheme : _darkScheme;
    final balanceColors = isLight ? BalanceColors.light : BalanceColors.dark;
    final textTheme = _textTheme(scheme);

    final scaffold = isLight ? _paperScaffold : _nightScaffold;
    final cardBorder = scheme.outlineVariant;
    final inputFill = isLight ? _paperSurfaceLowest : scheme.surfaceContainerHigh;
    final snackbarBackground =
        isLight ? const Color(0xFF182420) : const Color(0xFF223128);
    final snackbarForeground =
        isLight ? const Color(0xFFEDF3ED) : const Color(0xFFE9EFEA);
    final tooltipBackground = snackbarBackground;
    final tooltipForeground = snackbarForeground;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      splashFactory: InkRipple.splashFactory,
      fontFamily: displayFont,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[balanceColors],
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          backgroundColor: scheme.surface,
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: 340,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        selectedColor: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.2,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll<Color?>(
          scheme.surfaceContainerLow,
        ),
        headingTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        headingRowHeight: 42,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 48,
        horizontalMargin: 16,
        columnSpacing: 20,
        dividerThickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        horizontalTitleGap: 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: cardBorder,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackbarBackground,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: snackbarForeground,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tooltipBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: tooltipForeground),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        waitDuration: const Duration(milliseconds: 450),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurfaceVariant.withValues(alpha: 0.38),
        ),
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(8),
        interactive: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
