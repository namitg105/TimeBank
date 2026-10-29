import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The application theme.
///
/// Two rules shape everything below.
///
/// 1. Borders, not shadows. A drop shadow is invisible against a black
///    canvas, so hierarchy comes from hairline borders and one step of
///    surface lightness.
///
/// 2. Tabular figures everywhere a number appears. Proportional digits
///    make a column of balances jitter as the values change; tabular
///    digits all take the same width, so decimal points line up and the
///    column reads like a ledger.
abstract final class AppTheme {
  /// Numbers: fixed-width digits, slightly tightened.
  static const _tabular = [FontFeature.tabularFigures()];

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onPrimary: AppColors.canvas,
      secondary: AppColors.info,
      error: AppColors.negative,
      onSurface: AppColors.textPrimary,
      outline: AppColors.border,
    );

    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      dividerColor: AppColors.border,

      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            // The one place the design raises its voice: a balance.
            displaySmall: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              letterSpacing: -1.2,
              height: 1.0,
              color: AppColors.accent,
              fontFeatures: _tabular,
            ),
            headlineSmall: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
            bodySmall: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
            // Column headers and small labels.
            labelSmall: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: AppColors.textMuted,
            ),
          ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.textSecondary, size: 20),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle:
            const TextStyle(color: AppColors.accent, fontSize: 13),
        border: _fieldBorder(AppColors.border),
        enabledBorder: _fieldBorder(AppColors.border),
        focusedBorder: _fieldBorder(AppColors.accent),
        errorBorder: _fieldBorder(AppColors.negative),
        focusedErrorBorder: _fieldBorder(AppColors.negative),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.canvas,
          disabledBackgroundColor: AppColors.surfaceHover,
          disabledForegroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentWash,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textMuted,
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHover,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13.5,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHover,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c),
      );

  /// Monospaced-feeling numerals for tables and balances.
  static const numeric = TextStyle(
    fontFeatures: _tabular,
    fontSize: 14,
    color: AppColors.textPrimary,
  );
}
